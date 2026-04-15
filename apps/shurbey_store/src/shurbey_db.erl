-module(shurbey_db).
-include("shurbey_records.hrl").
-include_lib("stdlib/include/ms_transform.hrl").

-export([
    %% Libraries
    get_library/1, update_library_version/2,
    %% Users
    create_user/3, authenticate_user/2, get_user/1, get_user_by_id/1, delete_key/1,
    %% API keys
    verify_key/1, get_key_info/1, create_key/3, has_any_key/0,
    %% Items
    get_item/2, list_items/2, list_item_versions/2, write_item/1, mark_item_deleted/3,
    list_items_top/2, list_items_trash/2, list_items_children/3, list_items_in_collection/3,
    count_item_children/1,
    %% Collection index
    set_item_collections/3, delete_item_collections/2,
    %% Collections
    get_collection/2, list_collections/2, list_collection_versions/2,
    list_collections_top/2, list_subcollections/3,
    write_collection/1, mark_collection_deleted/3,
    %% Searches
    list_searches/2, list_search_versions/2, write_search/1, mark_search_deleted/3,
    %% Tags
    list_tags/2, list_item_tags/2, delete_tags_by_name/2, set_item_tags/3, delete_item_tags/2,
    %% Settings
    get_setting/2, list_settings/2, list_setting_versions/2, write_setting/1,
    delete_setting/2,
    %% Deleted
    list_deleted/3, record_deletion/4,
    %% Full-text
    get_fulltext/2, list_fulltext_versions/2, write_fulltext/1, delete_fulltext/2,
    %% File metadata
    get_file_meta/2, write_file_meta/1, delete_file_meta/2,
    %% Blobs (content-addressed)
    blob_exists/1, blob_ref/1, blob_unref/1
]).

%% ===================================================================
%% Libraries
%% ===================================================================

get_library(LibId) ->
    case db_read(shurbey_library, LibId) of
        [Lib] -> {ok, Lib};
        [] -> undefined
    end.

update_library_version(LibId, NewVersion) ->
    db_write(#shurbey_library{
        library_id = LibId, library_type = user, version = NewVersion
    }).

%% ===================================================================
%% Users
%% ===================================================================

create_user(Username, Password, UserId) ->
    Salt = crypto:strong_rand_bytes(16),
    Hash = hash_password(Password, Salt),
    {atomic, ok} = mnesia:transaction(fun() ->
        mnesia:write(#shurbey_user{
            username = Username,
            password_hash = Hash,
            salt = Salt,
            user_id = UserId
        }),
        case mnesia:read(shurbey_library, UserId) of
            [] ->
                mnesia:write(#shurbey_library{
                    library_id = UserId, library_type = user, version = 0
                });
            _ -> ok
        end
    end),
    ok.

authenticate_user(Username, Password) ->
    case db_read(shurbey_user, Username) of
        [#shurbey_user{password_hash = Hash, salt = Salt, user_id = UserId}] ->
            Computed = hash_password(Password, Salt),
            case constant_time_compare(Computed, Hash) of
                true -> {ok, UserId};
                false -> {error, invalid}
            end;
        [] ->
            _Dummy = hash_password(Password, crypto:strong_rand_bytes(16)),
            {error, invalid}
    end.

%% Constant-time binary comparison to prevent timing side-channels.
constant_time_compare(<<A, RestA/binary>>, <<B, RestB/binary>>) ->
    constant_time_compare(RestA, RestB, A bxor B);
constant_time_compare(<<>>, <<>>) -> true;
constant_time_compare(_, _) -> false.

constant_time_compare(<<A, RestA/binary>>, <<B, RestB/binary>>, Acc) ->
    constant_time_compare(RestA, RestB, Acc bor (A bxor B));
constant_time_compare(<<>>, <<>>, 0) -> true;
constant_time_compare(<<>>, <<>>, _) -> false.

get_user(Username) ->
    case db_read(shurbey_user, Username) of
        [User] -> {ok, User};
        [] -> undefined
    end.

get_user_by_id(UserId) ->
    MS = ets:fun2ms(
        fun(#shurbey_user{user_id = Id} = U) when Id =:= UserId -> U end),
    case mnesia:dirty_select(shurbey_user, MS) of
        [User | _] -> {ok, User};
        [] -> undefined
    end.

hash_password(Password, Salt) ->
    {ok, DK} = pbkdf2(Password, Salt, 100000, 32),
    DK.

pbkdf2(Password, Salt, Iterations, DkLen) ->
    U1 = crypto:mac(hmac, sha256, Password, <<Salt/binary, 1:32>>),
    Result = pbkdf2_loop(Password, U1, U1, Iterations - 1),
    {ok, binary:part(Result, 0, DkLen)}.

pbkdf2_loop(_Password, _U, Acc, 0) -> Acc;
pbkdf2_loop(Password, U, Acc, N) ->
    U2 = crypto:mac(hmac, sha256, Password, U),
    pbkdf2_loop(Password, U2, crypto:exor(Acc, U2), N - 1).

%% ===================================================================
%% API Keys
%% ===================================================================

verify_key(Key) when is_binary(Key) ->
    case db_read(shurbey_api_key, hash_api_key(Key)) of
        [#shurbey_api_key{user_id = UserId}] -> {ok, UserId};
        [] -> {error, invalid}
    end;
verify_key(_) ->
    {error, invalid}.

get_key_info(Key) ->
    case db_read(shurbey_api_key, hash_api_key(Key)) of
        [#shurbey_api_key{user_id = UserId, permissions = Perms}] ->
            {ok, #{user_id => UserId, permissions => Perms}};
        [] ->
            {error, invalid}
    end.

create_key(Key, UserId, Permissions) ->
    db_write(#shurbey_api_key{
        key = hash_api_key(Key), user_id = UserId, permissions = Permissions
    }).

has_any_key() ->
    mnesia:dirty_first(shurbey_api_key) =/= '$end_of_table'.

delete_key(Key) ->
    db_delete({shurbey_api_key, hash_api_key(Key)}).

%% ===================================================================
%% Items
%% ===================================================================

get_item(LibId, ItemKey) ->
    case db_read(shurbey_item, {LibId, ItemKey}) of
        [#shurbey_item{deleted = false} = Item] -> {ok, Item};
        _ -> undefined
    end.

list_items(LibId, Since) ->
    MS = ets:fun2ms(
        fun(#shurbey_item{id = {L, _}, version = V, deleted = false} = Item)
            when L =:= LibId, V > Since -> Item
        end),
    mnesia:dirty_select(shurbey_item, MS).

list_item_versions(LibId, Since) ->
    MS = ets:fun2ms(
        fun(#shurbey_item{id = {L, K}, version = V, deleted = false})
            when L =:= LibId, V > Since -> {K, V}
        end),
    mnesia:dirty_select(shurbey_item, MS).

write_item(Item) when is_record(Item, shurbey_item) ->
    db_write(Item).

mark_item_deleted(LibId, ItemKey, Version) ->
    case db_read(shurbey_item, {LibId, ItemKey}) of
        [Item] ->
            db_write(Item#shurbey_item{version = Version, deleted = true});
        [] ->
            ok
    end.

list_items_top(LibId, Since) ->
    MS = ets:fun2ms(
        fun(#shurbey_item{id = {L, _}, version = V, deleted = false,
                          parent_key = undefined} = Item)
            when L =:= LibId, V > Since -> Item
        end),
    mnesia:dirty_select(shurbey_item, MS).

list_items_trash(LibId, Since) ->
    MS = ets:fun2ms(
        fun(#shurbey_item{id = {L, _}, version = V, deleted = true} = Item)
            when L =:= LibId, V > Since -> Item
        end),
    mnesia:dirty_select(shurbey_item, MS).

list_items_children(LibId, ParentKey, Since) ->
    %% Secondary index on parent_key: O(k) instead of full table scan.
    Candidates = mnesia:dirty_index_read(shurbey_item, ParentKey,
                                         #shurbey_item.parent_key),
    [I || #shurbey_item{id = {L, _}, version = V, deleted = false} = I
          <- Candidates, L =:= LibId, V > Since].

list_items_in_collection(LibId, CollKey, Since) ->
    %% Bag table: O(1) key lookup returns all items in this collection.
    Rows = mnesia:dirty_read(shurbey_item_collection, {LibId, CollKey}),
    lists:filtermap(fun(#shurbey_item_collection{item_key = IK}) ->
        case get_item(LibId, IK) of
            {ok, #shurbey_item{version = V} = Item} when V > Since -> {true, Item};
            _ -> false
        end
    end, Rows).

count_item_children(LibId) ->
    %% Return only the parent_key field — no full data maps deserialized.
    MS = ets:fun2ms(
        fun(#shurbey_item{id = {L, _}, deleted = false, parent_key = PK})
            when L =:= LibId, PK =/= undefined -> PK
        end),
    ParentKeys = mnesia:dirty_select(shurbey_item, MS),
    lists:foldl(fun(PK, Acc) ->
        maps:update_with(PK, fun(N) -> N + 1 end, 1, Acc)
    end, #{}, ParentKeys).

%% ===================================================================
%% Collections
%% ===================================================================

get_collection(LibId, CollKey) ->
    case db_read(shurbey_collection, {LibId, CollKey}) of
        [#shurbey_collection{deleted = false} = Coll] -> {ok, Coll};
        _ -> undefined
    end.

list_collections(LibId, Since) ->
    MS = ets:fun2ms(
        fun(#shurbey_collection{id = {L, _}, version = V, deleted = false} = Coll)
            when L =:= LibId, V > Since -> Coll
        end),
    mnesia:dirty_select(shurbey_collection, MS).

list_collection_versions(LibId, Since) ->
    MS = ets:fun2ms(
        fun(#shurbey_collection{id = {L, K}, version = V, deleted = false})
            when L =:= LibId, V > Since -> {K, V}
        end),
    mnesia:dirty_select(shurbey_collection, MS).

list_collections_top(LibId, Since) ->
    [C || #shurbey_collection{data = D} = C <- list_collections(LibId, Since),
          maps:get(<<"parentCollection">>, D, false) =:= false].

list_subcollections(LibId, ParentKey, Since) ->
    [C || #shurbey_collection{data = D} = C <- list_collections(LibId, Since),
          maps:get(<<"parentCollection">>, D, false) =:= ParentKey].

write_collection(Coll) when is_record(Coll, shurbey_collection) ->
    db_write(Coll).

mark_collection_deleted(LibId, CollKey, Version) ->
    case db_read(shurbey_collection, {LibId, CollKey}) of
        [Coll] ->
            db_write(Coll#shurbey_collection{version = Version, deleted = true});
        [] ->
            ok
    end.

%% ===================================================================
%% Searches
%% ===================================================================

list_searches(LibId, Since) ->
    MS = ets:fun2ms(
        fun(#shurbey_search{id = {L, _}, version = V, deleted = false} = S)
            when L =:= LibId, V > Since -> S
        end),
    mnesia:dirty_select(shurbey_search, MS).

list_search_versions(LibId, Since) ->
    MS = ets:fun2ms(
        fun(#shurbey_search{id = {L, K}, version = V, deleted = false})
            when L =:= LibId, V > Since -> {K, V}
        end),
    mnesia:dirty_select(shurbey_search, MS).

write_search(Search) when is_record(Search, shurbey_search) ->
    db_write(Search).

mark_search_deleted(LibId, SearchKey, Version) ->
    case db_read(shurbey_search, {LibId, SearchKey}) of
        [Search] ->
            db_write(Search#shurbey_search{version = Version, deleted = true});
        [] ->
            ok
    end.

%% ===================================================================
%% Tags
%% ===================================================================

list_tags(LibId, Since) ->
    case Since of
        0 ->
            %% Full sync: single scan of the tag table by LibId.
            MS = ets:fun2ms(
                fun(#shurbey_tag{id = {L, Tag, _}, tag_type = Type})
                    when L =:= LibId -> {Tag, Type}
                end),
            lists:usort(mnesia:dirty_select(shurbey_tag, MS));
        _ ->
            %% Incremental: build key set from changed items, single tag scan.
            ItemKeySet = sets:from_list(
                [K || {K, _V} <- list_item_versions(LibId, Since)]),
            MS = ets:fun2ms(
                fun(#shurbey_tag{id = {L, Tag, IK}, tag_type = Type})
                    when L =:= LibId -> {Tag, Type, IK}
                end),
            AllTags = mnesia:dirty_select(shurbey_tag, MS),
            lists:usort([{Tag, Type} || {Tag, Type, IK} <- AllTags,
                                        sets:is_element(IK, ItemKeySet)])
    end.

set_item_tags(LibId, ItemKey, Tags) ->
    delete_item_tags(LibId, ItemKey),
    lists:foreach(fun({Tag, Type}) ->
        db_write(#shurbey_tag{id = {LibId, Tag, ItemKey}, tag_type = Type})
    end, Tags).

delete_item_tags(LibId, ItemKey) ->
    MS = ets:fun2ms(
        fun(#shurbey_tag{id = {L, _, I}} = T)
            when L =:= LibId, I =:= ItemKey -> T
        end),
    Existing = mnesia:dirty_select(shurbey_tag, MS),
    lists:foreach(fun(T) -> db_delete_object(T) end, Existing).

list_item_tags(LibId, ItemKey) ->
    MS = ets:fun2ms(
        fun(#shurbey_tag{id = {L, Tag, IK}, tag_type = Type})
            when L =:= LibId, IK =:= ItemKey -> {Tag, Type}
        end),
    mnesia:dirty_select(shurbey_tag, MS).

delete_tags_by_name(LibId, TagNames) ->
    TagSet = sets:from_list(TagNames),
    MS = ets:fun2ms(
        fun(#shurbey_tag{id = {L, Tag, _}} = T)
            when L =:= LibId -> {T, Tag}
        end),
    AllTags = mnesia:dirty_select(shurbey_tag, MS),
    Deleted = [begin db_delete_object(T), Tag end
               || {T, Tag} <- AllTags, sets:is_element(Tag, TagSet)],
    lists:usort(Deleted).

%% ===================================================================
%% Settings
%% ===================================================================

get_setting(LibId, SettingKey) ->
    case db_read(shurbey_setting, {LibId, SettingKey}) of
        [Setting] -> {ok, Setting};
        [] -> undefined
    end.

list_settings(LibId, Since) ->
    MS = ets:fun2ms(
        fun(#shurbey_setting{id = {L, _}, version = V} = S)
            when L =:= LibId, V > Since -> S
        end),
    mnesia:dirty_select(shurbey_setting, MS).

list_setting_versions(LibId, Since) ->
    MS = ets:fun2ms(
        fun(#shurbey_setting{id = {L, K}, version = V})
            when L =:= LibId, V > Since -> {K, V}
        end),
    mnesia:dirty_select(shurbey_setting, MS).

write_setting(Setting) when is_record(Setting, shurbey_setting) ->
    db_write(Setting).

delete_setting(LibId, SettingKey) ->
    db_delete({shurbey_setting, {LibId, SettingKey}}).

%% ===================================================================
%% Deleted tracking
%% ===================================================================

list_deleted(LibId, ObjectType, Since) ->
    MS = ets:fun2ms(
        fun(#shurbey_deleted{id = {L, OT, Key}, version = V})
            when L =:= LibId, OT =:= ObjectType, V > Since -> Key
        end),
    mnesia:dirty_select(shurbey_deleted, MS).

record_deletion(LibId, ObjectType, ObjectKey, Version) ->
    db_write(#shurbey_deleted{
        id = {LibId, ObjectType, ObjectKey}, version = Version
    }).

%% ===================================================================
%% Full-text
%% ===================================================================

get_fulltext(LibId, ItemKey) ->
    case db_read(shurbey_fulltext, {LibId, ItemKey}) of
        [Ft] -> {ok, Ft};
        [] -> undefined
    end.

list_fulltext_versions(LibId, Since) ->
    MS = ets:fun2ms(
        fun(#shurbey_fulltext{id = {L, K}, version = V})
            when L =:= LibId, V > Since -> {K, V}
        end),
    mnesia:dirty_select(shurbey_fulltext, MS).

write_fulltext(Ft) when is_record(Ft, shurbey_fulltext) ->
    db_write(Ft).

delete_fulltext(LibId, ItemKey) ->
    db_delete({shurbey_fulltext, {LibId, ItemKey}}).

%% ===================================================================
%% File metadata
%% ===================================================================

get_file_meta(LibId, ItemKey) ->
    case db_read(shurbey_file_meta, {LibId, ItemKey}) of
        [Meta] -> {ok, Meta};
        [] -> undefined
    end.

write_file_meta(Meta) when is_record(Meta, shurbey_file_meta) ->
    db_write(Meta).

delete_file_meta(LibId, ItemKey) ->
    %% Unref the blob before removing metadata
    case db_read(shurbey_file_meta, {LibId, ItemKey}) of
        [#shurbey_file_meta{sha256 = Hash}] ->
            case blob_unref(Hash) of
                {ok, 0} -> file:delete(shurbey_files:blob_path(Hash));
                _ -> ok
            end,
            db_delete({shurbey_file_meta, {LibId, ItemKey}});
        [] ->
            ok
    end.

%% ===================================================================
%% Blobs (content-addressed store)
%% ===================================================================

blob_exists(Hash) ->
    case db_read(shurbey_blob, Hash) of
        [#shurbey_blob{}] -> true;
        [] -> false
    end.

blob_ref(Hash) ->
    {atomic, ok} = mnesia:transaction(fun() ->
        case mnesia:read(shurbey_blob, Hash, write) of
            [#shurbey_blob{refcount = N} = Blob] ->
                mnesia:write(Blob#shurbey_blob{refcount = N + 1});
            [] ->
                mnesia:write(#shurbey_blob{hash = Hash, size = 0, refcount = 1})
        end
    end),
    ok.

blob_unref(Hash) ->
    {atomic, Result} = mnesia:transaction(fun() ->
        case mnesia:read(shurbey_blob, Hash, write) of
            [#shurbey_blob{refcount = N} = Blob] when N > 1 ->
                mnesia:write(Blob#shurbey_blob{refcount = N - 1}),
                {ok, N - 1};
            [#shurbey_blob{refcount = 1}] ->
                mnesia:delete({shurbey_blob, Hash}),
                {ok, 0};
            [] ->
                {ok, 0}
        end
    end),
    Result.

%% ===================================================================
%% Collection index
%% ===================================================================

set_item_collections(LibId, ItemKey, CollKeys) ->
    delete_item_collections(LibId, ItemKey),
    lists:foreach(fun(CollKey) ->
        db_write(#shurbey_item_collection{id = {LibId, CollKey}, item_key = ItemKey})
    end, CollKeys).

delete_item_collections(LibId, ItemKey) ->
    MS = ets:fun2ms(
        fun(#shurbey_item_collection{id = {L, _}, item_key = IK} = R)
            when L =:= LibId, IK =:= ItemKey -> R
        end),
    Existing = mnesia:dirty_select(shurbey_item_collection, MS),
    lists:foreach(fun(R) -> db_delete_object(R) end, Existing).

%% ===================================================================
%% Internal
%% ===================================================================

hash_api_key(Key) ->
    crypto:hash(sha256, Key).

%% ===================================================================
%% Internal — transaction-aware Mnesia operations.
%% Uses mnesia:write/read/delete inside transactions, dirty_* outside.
%% ===================================================================

db_write(Record) ->
    case mnesia:is_transaction() of
        true -> mnesia:write(Record);
        false -> mnesia:dirty_write(Record)
    end.

db_read(Table, Key) ->
    case mnesia:is_transaction() of
        true -> mnesia:read(Table, Key);
        false -> mnesia:dirty_read(Table, Key)
    end.

db_delete(TableKey) ->
    case mnesia:is_transaction() of
        true -> mnesia:delete(TableKey);
        false -> mnesia:dirty_delete(TableKey)
    end.

db_delete_object(Record) ->
    case mnesia:is_transaction() of
        true -> mnesia:delete_object(Record);
        false -> mnesia:dirty_delete_object(Record)
    end.
