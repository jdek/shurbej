-module(shurbej_db).
-include("shurbej_records.hrl").
-include_lib("stdlib/include/ms_transform.hrl").

-export([
    %% Libraries
    get_library/1, ensure_library/1, update_library_version/2,
    %% Users / identities
    create_user/2, create_user/3,
    authenticate_password/2,
    get_user_by_uuid/1, get_user_by_username/1, find_users_by_user_id/1,
    set_user_id/2, set_username/2, set_display_name/2,
    link_identity/4, unlink_identity/1, get_identity/1,
    delete_user/1, delete_key/1,
    hash_password/2,
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
    get_search/2, list_searches/2, list_search_versions/2, write_search/1, mark_search_deleted/3,
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
    blob_exists/1, blob_ref/1, blob_unref/1,
    reset_orphan_blobs/0, reap_orphan_blobs/0,
    %% Groups
    get_group/1, list_groups/0, write_group/1, delete_group/1,
    add_group_member/3, remove_group_member/2, get_group_member/2,
    list_group_members/1, list_user_groups/1
]).

%% ===================================================================
%% Libraries
%% ===================================================================

get_library(LibRef) ->
    case db_read(shurbej_library, LibRef) of
        [Lib] -> {ok, Lib};
        [] -> undefined
    end.

%% Ensure a library row exists — idempotent, called on user/group creation
%% and lazily on first access.
ensure_library(LibRef) ->
    {atomic, ok} = mnesia:transaction(fun() ->
        case mnesia:read(shurbej_library, LibRef) of
            [] -> mnesia:write(#shurbej_library{ref = LibRef, version = 0});
            _ -> ok
        end
    end),
    ok.

update_library_version(LibRef, NewVersion) ->
    db_write(#shurbej_library{ref = LibRef, version = NewVersion}).

%% ===================================================================
%% Users / identities
%% ===================================================================

%% create_user/2 — fresh user with a password binding. user_uuid is allocated
%% randomly; the user_id label is derived from the uuid so /keys/current has
%% something stable to return before the user picks their preferred label.
%% Returns {ok, UserUuid}.
create_user(Username, Password) ->
    create_user(Username, Password, default_user_id(Username)).

create_user(Username, Password, UserId) ->
    UserUuid = new_user_uuid(),
    Salt = crypto:strong_rand_bytes(16),
    Hash = hash_password(Password, Salt),
    Now = erlang:system_time(second),
    {atomic, ok} = mnesia:transaction(fun() ->
        mnesia:write(#shurbej_user{
            user_uuid = UserUuid,
            user_id = UserId,
            username = Username,
            display_name = Username,
            created_at = Now
        }),
        mnesia:write(#shurbej_identity{
            key = {password, Username},
            user_uuid = UserUuid,
            credentials = {pbkdf2_sha256, Hash, Salt}
        }),
        LibRef = {user, UserUuid},
        case mnesia:read(shurbej_library, LibRef) of
            [] -> mnesia:write(#shurbej_library{ref = LibRef, version = 0});
            _ -> ok
        end
    end),
    {ok, UserUuid}.

%% Verify a password identity. The not-found path runs a dummy PBKDF2 with a
%% throwaway salt so a missing-user response can't be timing-distinguished
%% from a wrong-password one.
authenticate_password(Username, Password) ->
    case db_read(shurbej_identity, {password, Username}) of
        [#shurbej_identity{
                user_uuid = UserUuid,
                credentials = {pbkdf2_sha256, Hash, Salt}}] ->
            Computed = hash_password(Password, Salt),
            case constant_time_compare(Computed, Hash) of
                true -> {ok, UserUuid};
                false -> {error, invalid}
            end;
        _ ->
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

get_user_by_uuid(UserUuid) ->
    case db_read(shurbej_user, UserUuid) of
        [User] -> {ok, User};
        [] -> undefined
    end.

%% Username is an indexed secondary field on shurbej_user. Returns the first
%% match; usernames are not strictly unique-constrained server-side but the
%% admin/login paths only ever create one user per username.
get_user_by_username(Username) ->
    case db_index_read(shurbej_user, Username, #shurbej_user.username) of
        [User | _] -> {ok, User};
        [] -> undefined
    end.

%% user_id is a non-unique label, so this returns a list. Used by tooling that
%% wants to find "all users currently advertising label N" — not by request
%% routing (which compares URL :userID against the authenticated user's
%% label, not the other way around).
find_users_by_user_id(UserId) ->
    db_index_read(shurbej_user, UserId, #shurbej_user.user_id).

set_user_id(UserUuid, NewUserId) when is_integer(NewUserId), NewUserId >= 0 ->
    Result = update_user_field(UserUuid,
        fun(U) -> U#shurbej_user{user_id = NewUserId} end),
    %% The version gen_server caches the pubsub topic string, which embeds
    %% the user_id label. Bounce the worker so its next start picks up the
    %% new label. ensure_started in shurbej_version:call/2 spawns a fresh
    %% one transparently on the next request.
    case Result of
        ok -> shurbej_version_sup:terminate_child({user, UserUuid});
        _ -> ok
    end,
    Result.

set_username(UserUuid, NewUsername) when is_binary(NewUsername) ->
    update_user_field(UserUuid, fun(U) -> U#shurbej_user{username = NewUsername} end).

set_display_name(UserUuid, NewDisplay) ->
    update_user_field(UserUuid,
        fun(U) -> U#shurbej_user{display_name = NewDisplay} end).

update_user_field(UserUuid, F) ->
    {atomic, Result} = mnesia:transaction(fun() ->
        case mnesia:read(shurbej_user, UserUuid, write) of
            [User] -> mnesia:write(F(User)), ok;
            [] -> {error, not_found}
        end
    end),
    Result.

%% Add (or replace) an authentication binding. Subjects are scoped per
%% provider — `{password, "alice"}` and `{oidc_kanidm, "alice"}` are
%% disjoint. Replacing an existing row with a different user_uuid is allowed
%% and is the natural semantics for "rebind this OIDC subject to a different
%% local account".
link_identity(UserUuid, Provider, Subject, Credentials)
        when is_binary(UserUuid), is_atom(Provider), is_binary(Subject) ->
    db_write(#shurbej_identity{
        key = {Provider, Subject},
        user_uuid = UserUuid,
        credentials = Credentials
    }),
    ok.

unlink_identity({Provider, Subject} = Key)
        when is_atom(Provider), is_binary(Subject) ->
    db_delete({shurbej_identity, Key}).

get_identity({Provider, Subject} = Key)
        when is_atom(Provider), is_binary(Subject) ->
    case db_read(shurbej_identity, Key) of
        [Ident] -> {ok, Ident};
        [] -> undefined
    end.

delete_user(UserUuid) when is_binary(UserUuid) ->
    {atomic, ok} = mnesia:transaction(fun() ->
        IdentMS = ets:fun2ms(
            fun(#shurbej_identity{user_uuid = U} = I) when U =:= UserUuid -> I end),
        [mnesia:delete_object(I) || I <- mnesia:select(shurbej_identity, IdentMS)],
        mnesia:delete({shurbej_user, UserUuid}),
        ok
    end),
    ok.

%% UUID generation — 16 random bytes hex-encoded for shell-friendliness.
new_user_uuid() ->
    binary:encode_hex(crypto:strong_rand_bytes(16), lowercase).

%% Default user_id label derived from the username. We want it stable per
%% user, fitting in an int32 (Zotero clients store it as INTEGER PRIMARY
%% KEY), and unlikely to collide with an existing zotero.org user_id the
%% admin might want to claim later. phash2/2 with 1 bsl 31 gives 0..2^31-1
%% which is the safe int32 range.
default_user_id(Subject) ->
    erlang:phash2(Subject, 1 bsl 31).

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
    case db_read(shurbej_api_key, hash_api_key(Key)) of
        [#shurbej_api_key{user_uuid = UserUuid}] -> {ok, UserUuid};
        [] -> {error, invalid}
    end;
verify_key(_) ->
    {error, invalid}.

%% Return the auth context for an API key: the internal user_uuid, the user's
%% current user_id label and username (joined from shurbej_user so callers
%% don't double-fetch), and the permission map. Stable shape across password
%% and OIDC-backed keys.
get_key_info(Key) ->
    case db_read(shurbej_api_key, hash_api_key(Key)) of
        [#shurbej_api_key{user_uuid = UserUuid, permissions = Perms}] ->
            case db_read(shurbej_user, UserUuid) of
                [#shurbej_user{user_id = UserId, username = Username,
                               display_name = DisplayName}] ->
                    {ok, #{
                        user_uuid => UserUuid,
                        user_id => UserId,
                        username => Username,
                        display_name => DisplayName,
                        permissions => Perms
                    }};
                [] ->
                    {error, invalid}
            end;
        [] ->
            {error, invalid}
    end.

create_key(Key, UserUuid, Permissions) ->
    db_write(#shurbej_api_key{
        key = hash_api_key(Key), user_uuid = UserUuid, permissions = Permissions
    }).

has_any_key() ->
    mnesia:dirty_first(shurbej_api_key) =/= '$end_of_table'.

delete_key(Key) ->
    db_delete({shurbej_api_key, hash_api_key(Key)}).

%% ===================================================================
%% Items
%% ===================================================================

get_item({LT, LI}, ItemKey) ->
    case db_read(shurbej_item, {LT, LI, ItemKey}) of
        [#shurbej_item{deleted = false} = Item] -> {ok, Item};
        _ -> undefined
    end.

list_items({LT, LI}, Since) ->
    MS = ets:fun2ms(
        fun(#shurbej_item{id = {T, I, _}, version = V, deleted = false} = Item)
            when T =:= LT, I =:= LI, V > Since -> Item
        end),
    mnesia:dirty_select(shurbej_item, MS).

list_item_versions({LT, LI}, Since) ->
    MS = ets:fun2ms(
        fun(#shurbej_item{id = {T, I, K}, version = V, deleted = false})
            when T =:= LT, I =:= LI, V > Since -> {K, V}
        end),
    mnesia:dirty_select(shurbej_item, MS).

write_item(Item) when is_record(Item, shurbej_item) ->
    db_write(Item).

mark_item_deleted({LT, LI}, ItemKey, Version) ->
    case db_read(shurbej_item, {LT, LI, ItemKey}) of
        [Item] ->
            db_write(Item#shurbej_item{version = Version, deleted = true});
        [] ->
            ok
    end.

list_items_top({LT, LI}, Since) ->
    MS = ets:fun2ms(
        fun(#shurbej_item{id = {T, I, _}, version = V, deleted = false,
                          parent_key = undefined} = Item)
            when T =:= LT, I =:= LI, V > Since -> Item
        end),
    mnesia:dirty_select(shurbej_item, MS).

list_items_trash({LT, LI}, Since) ->
    MS = ets:fun2ms(
        fun(#shurbej_item{id = {T, I, _}, version = V, deleted = true} = Item)
            when T =:= LT, I =:= LI, V > Since -> Item
        end),
    mnesia:dirty_select(shurbej_item, MS).

list_items_children({LT, LI}, ParentKey, Since) ->
    %% Secondary index on parent_key: O(k) instead of full table scan.
    Candidates = db_index_read(shurbej_item, ParentKey,
                               #shurbej_item.parent_key),
    [I || #shurbej_item{id = {T, Id, _}, version = V, deleted = false} = I
          <- Candidates, T =:= LT, Id =:= LI, V > Since].

list_items_in_collection({LT, LI} = LibRef, CollKey, Since) ->
    %% Bag table: O(1) key lookup returns all items in this collection.
    Rows = mnesia:dirty_read(shurbej_item_collection, {LT, LI, CollKey}),
    lists:filtermap(fun(#shurbej_item_collection{item_key = IK}) ->
        case get_item(LibRef, IK) of
            {ok, #shurbej_item{version = V} = Item} when V > Since -> {true, Item};
            _ -> false
        end
    end, Rows).

count_item_children({LT, LI}) ->
    %% Return only the parent_key field — no full data maps deserialized.
    MS = ets:fun2ms(
        fun(#shurbej_item{id = {T, I, _}, deleted = false, parent_key = PK})
            when T =:= LT, I =:= LI, PK =/= undefined -> PK
        end),
    ParentKeys = mnesia:dirty_select(shurbej_item, MS),
    lists:foldl(fun(PK, Acc) ->
        maps:update_with(PK, fun(N) -> N + 1 end, 1, Acc)
    end, #{}, ParentKeys).

%% ===================================================================
%% Collections
%% ===================================================================

get_collection({LT, LI}, CollKey) ->
    case db_read(shurbej_collection, {LT, LI, CollKey}) of
        [#shurbej_collection{deleted = false} = Coll] -> {ok, Coll};
        _ -> undefined
    end.

list_collections({LT, LI}, Since) ->
    MS = ets:fun2ms(
        fun(#shurbej_collection{id = {T, I, _}, version = V, deleted = false} = Coll)
            when T =:= LT, I =:= LI, V > Since -> Coll
        end),
    mnesia:dirty_select(shurbej_collection, MS).

list_collection_versions({LT, LI}, Since) ->
    MS = ets:fun2ms(
        fun(#shurbej_collection{id = {T, I, K}, version = V, deleted = false})
            when T =:= LT, I =:= LI, V > Since -> {K, V}
        end),
    mnesia:dirty_select(shurbej_collection, MS).

list_collections_top(LibRef, Since) ->
    [C || #shurbej_collection{data = D} = C <- list_collections(LibRef, Since),
          maps:get(<<"parentCollection">>, D, false) =:= false].

list_subcollections(LibRef, ParentKey, Since) ->
    [C || #shurbej_collection{data = D} = C <- list_collections(LibRef, Since),
          maps:get(<<"parentCollection">>, D, false) =:= ParentKey].

write_collection(Coll) when is_record(Coll, shurbej_collection) ->
    db_write(Coll).

mark_collection_deleted({LT, LI}, CollKey, Version) ->
    case db_read(shurbej_collection, {LT, LI, CollKey}) of
        [Coll] ->
            db_write(Coll#shurbej_collection{version = Version, deleted = true});
        [] ->
            ok
    end.

%% ===================================================================
%% Searches
%% ===================================================================

get_search({LT, LI}, SearchKey) ->
    case db_read(shurbej_search, {LT, LI, SearchKey}) of
        [#shurbej_search{deleted = false} = S] -> {ok, S};
        _ -> undefined
    end.

list_searches({LT, LI}, Since) ->
    MS = ets:fun2ms(
        fun(#shurbej_search{id = {T, I, _}, version = V, deleted = false} = S)
            when T =:= LT, I =:= LI, V > Since -> S
        end),
    mnesia:dirty_select(shurbej_search, MS).

list_search_versions({LT, LI}, Since) ->
    MS = ets:fun2ms(
        fun(#shurbej_search{id = {T, I, K}, version = V, deleted = false})
            when T =:= LT, I =:= LI, V > Since -> {K, V}
        end),
    mnesia:dirty_select(shurbej_search, MS).

write_search(Search) when is_record(Search, shurbej_search) ->
    db_write(Search).

mark_search_deleted({LT, LI}, SearchKey, Version) ->
    case db_read(shurbej_search, {LT, LI, SearchKey}) of
        [Search] ->
            db_write(Search#shurbej_search{version = Version, deleted = true});
        [] ->
            ok
    end.

%% ===================================================================
%% Tags
%% ===================================================================

list_tags({LT, LI} = LibRef, Since) ->
    case Since of
        0 ->
            %% Full sync: single scan of the tag table by LibRef.
            MS = ets:fun2ms(
                fun(#shurbej_tag{id = {T, I, Tag, _}, tag_type = Type})
                    when T =:= LT, I =:= LI -> {Tag, Type}
                end),
            lists:usort(mnesia:dirty_select(shurbej_tag, MS));
        _ ->
            %% Incremental: build key set from changed items, single tag scan.
            ItemKeySet = sets:from_list(
                [K || {K, _V} <- list_item_versions(LibRef, Since)]),
            MS = ets:fun2ms(
                fun(#shurbej_tag{id = {T, I, Tag, IK}, tag_type = Type})
                    when T =:= LT, I =:= LI -> {Tag, Type, IK}
                end),
            AllTags = mnesia:dirty_select(shurbej_tag, MS),
            lists:usort([{Tag, Type} || {Tag, Type, IK} <- AllTags,
                                        sets:is_element(IK, ItemKeySet)])
    end.

set_item_tags({LT, LI} = LibRef, ItemKey, Tags) ->
    delete_item_tags(LibRef, ItemKey),
    lists:foreach(fun({Tag, Type}) ->
        db_write(#shurbej_tag{id = {LT, LI, Tag, ItemKey}, tag_type = Type})
    end, Tags).

delete_item_tags({LT, LI}, ItemKey) ->
    MS = ets:fun2ms(
        fun(#shurbej_tag{id = {T, I, _, IK}} = Tag)
            when T =:= LT, I =:= LI, IK =:= ItemKey -> Tag
        end),
    Existing = db_select(shurbej_tag, MS),
    lists:foreach(fun(T) -> db_delete_object(T) end, Existing).

list_item_tags({LT, LI}, ItemKey) ->
    MS = ets:fun2ms(
        fun(#shurbej_tag{id = {T, I, Tag, IK}, tag_type = Type})
            when T =:= LT, I =:= LI, IK =:= ItemKey -> {Tag, Type}
        end),
    mnesia:dirty_select(shurbej_tag, MS).

delete_tags_by_name({LT, LI}, TagNames) ->
    TagSet = sets:from_list(TagNames),
    MS = ets:fun2ms(
        fun(#shurbej_tag{id = {T, I, Tag, _}} = Row)
            when T =:= LT, I =:= LI -> {Row, Tag}
        end),
    AllTags = mnesia:dirty_select(shurbej_tag, MS),
    Deleted = [begin db_delete_object(Row), Tag end
               || {Row, Tag} <- AllTags, sets:is_element(Tag, TagSet)],
    lists:usort(Deleted).

%% ===================================================================
%% Settings
%% ===================================================================

get_setting({LT, LI}, SettingKey) ->
    case db_read(shurbej_setting, {LT, LI, SettingKey}) of
        [Setting] -> {ok, Setting};
        [] -> undefined
    end.

list_settings({LT, LI}, Since) ->
    MS = ets:fun2ms(
        fun(#shurbej_setting{id = {T, I, _}, version = V} = S)
            when T =:= LT, I =:= LI, V > Since -> S
        end),
    mnesia:dirty_select(shurbej_setting, MS).

list_setting_versions({LT, LI}, Since) ->
    MS = ets:fun2ms(
        fun(#shurbej_setting{id = {T, I, K}, version = V})
            when T =:= LT, I =:= LI, V > Since -> {K, V}
        end),
    mnesia:dirty_select(shurbej_setting, MS).

write_setting(Setting) when is_record(Setting, shurbej_setting) ->
    db_write(Setting).

delete_setting({LT, LI}, SettingKey) ->
    db_delete({shurbej_setting, {LT, LI, SettingKey}}).

%% ===================================================================
%% Deleted tracking
%% ===================================================================

list_deleted({LT, LI}, ObjectType, Since) ->
    MS = ets:fun2ms(
        fun(#shurbej_deleted{id = {T, I, OT, Key}, version = V})
            when T =:= LT, I =:= LI, OT =:= ObjectType, V > Since -> Key
        end),
    mnesia:dirty_select(shurbej_deleted, MS).

record_deletion({LT, LI}, ObjectType, ObjectKey, Version) ->
    db_write(#shurbej_deleted{
        id = {LT, LI, ObjectType, ObjectKey}, version = Version
    }).

%% ===================================================================
%% Full-text
%% ===================================================================

get_fulltext({LT, LI}, ItemKey) ->
    case db_read(shurbej_fulltext, {LT, LI, ItemKey}) of
        [Ft] -> {ok, Ft};
        [] -> undefined
    end.

list_fulltext_versions({LT, LI}, Since) ->
    MS = ets:fun2ms(
        fun(#shurbej_fulltext{id = {T, I, K}, version = V})
            when T =:= LT, I =:= LI, V > Since -> {K, V}
        end),
    mnesia:dirty_select(shurbej_fulltext, MS).

write_fulltext(Ft) when is_record(Ft, shurbej_fulltext) ->
    db_write(Ft).

delete_fulltext({LT, LI}, ItemKey) ->
    db_delete({shurbej_fulltext, {LT, LI, ItemKey}}).

%% ===================================================================
%% File metadata
%% ===================================================================

get_file_meta({LT, LI}, ItemKey) ->
    case db_read(shurbej_file_meta, {LT, LI, ItemKey}) of
        [Meta] -> {ok, Meta};
        [] -> undefined
    end.

write_file_meta(Meta) when is_record(Meta, shurbej_file_meta) ->
    db_write(Meta).

delete_file_meta({LT, LI}, ItemKey) ->
    %% Unref the blob before removing metadata. If the refcount hits 0 the
    %% blob file needs unlinking from disk — we never do that inside the
    %% transaction because file IO isn't rollback-safe (an aborted txn would
    %% leave the metadata restored pointing at a missing file). Instead:
    %%  - inside a transaction: stash the hash so the transaction's driver
    %%    can unlink post-commit via reap_orphan_blobs/0
    %%  - outside: finish the transaction, then unlink.
    case db_read(shurbej_file_meta, {LT, LI, ItemKey}) of
        [#shurbej_file_meta{sha256 = Hash}] ->
            case mnesia:is_transaction() of
                true ->
                    case blob_unref_tx(Hash) of
                        0 -> mark_orphan_blob(Hash);
                        _ -> ok
                    end,
                    mnesia:delete({shurbej_file_meta, {LT, LI, ItemKey}});
                false ->
                    %% Wrap read/unref/delete in one transaction, then unlink.
                    {atomic, Remaining} = mnesia:transaction(fun() ->
                        N = blob_unref_tx(Hash),
                        mnesia:delete({shurbej_file_meta, {LT, LI, ItemKey}}),
                        N
                    end),
                    case Remaining of
                        0 -> _ = file:delete(shurbej_files:blob_path(Hash));
                        _ -> ok
                    end,
                    ok
            end;
        [] ->
            ok
    end.

%% ===================================================================
%% Blobs (content-addressed store)
%% ===================================================================

blob_exists(Hash) ->
    case db_read(shurbej_blob, Hash) of
        [#shurbej_blob{}] -> true;
        [] -> false
    end.

blob_ref(Hash) ->
    {atomic, ok} = mnesia:transaction(fun() ->
        case mnesia:read(shurbej_blob, Hash, write) of
            [#shurbej_blob{refcount = N} = Blob] ->
                mnesia:write(Blob#shurbej_blob{refcount = N + 1});
            [] ->
                mnesia:write(#shurbej_blob{hash = Hash, size = 0, refcount = 1})
        end
    end),
    ok.

%% Decrement the refcount on a blob. Returns the remaining count (0 means
%% the blob row was deleted — the file on disk still needs unlinking, which
%% is the caller's responsibility and must happen *after* the enclosing
%% transaction commits so an abort can't leave us referencing a missing file).
blob_unref(Hash) ->
    {atomic, N} = mnesia:transaction(fun() -> blob_unref_tx(Hash) end),
    N.

%% ===================================================================
%% Collection index
%% ===================================================================

set_item_collections({LT, LI} = LibRef, ItemKey, CollKeys) ->
    delete_item_collections(LibRef, ItemKey),
    lists:foreach(fun(CollKey) ->
        db_write(#shurbej_item_collection{id = {LT, LI, CollKey}, item_key = ItemKey})
    end, CollKeys).

delete_item_collections({LT, LI}, ItemKey) ->
    MS = ets:fun2ms(
        fun(#shurbej_item_collection{id = {T, I, _}, item_key = IK} = R)
            when T =:= LT, I =:= LI, IK =:= ItemKey -> R
        end),
    Existing = db_select(shurbej_item_collection, MS),
    lists:foreach(fun(R) -> db_delete_object(R) end, Existing).

%% ===================================================================
%% Groups
%% ===================================================================

get_group(GroupId) ->
    case db_read(shurbej_group, GroupId) of
        [Group] -> {ok, Group};
        [] -> undefined
    end.

list_groups() ->
    mnesia:dirty_select(shurbej_group,
        ets:fun2ms(fun(#shurbej_group{} = G) -> G end)).

write_group(Group) when is_record(Group, shurbej_group) ->
    db_write(Group).

delete_group(GroupId) ->
    %% Wipe group library data + membership; admin-only op, so no perm check.
    %% Runs in a single Mnesia transaction so partial failure can't leave
    %% orphaned items/tags/file_meta/etc. Freed blobs get unlinked from disk
    %% only after the transaction commits, and the per-library version
    %% server is shut down after everything has settled.
    LibRef = {group, GroupId},
    reset_orphan_blobs(),
    Result = mnesia:transaction(fun() ->
        cascade_delete_library(LibRef),
        mnesia:delete({shurbej_group, GroupId}),
        MemberMS = ets:fun2ms(
            fun(#shurbej_group_member{id = {G, _}} = M) when G =:= GroupId -> M end),
        [mnesia:delete_object(M) || M <- mnesia:select(shurbej_group_member, MemberMS)],
        mnesia:delete({shurbej_library, LibRef}),
        ok
    end),
    case Result of
        {atomic, ok} ->
            reap_orphan_blobs(),
            shurbej_version_sup:terminate_child(LibRef),
            ok;
        {aborted, Reason} ->
            reset_orphan_blobs(),
            erlang:error({delete_group_failed, Reason})
    end.

%% Delete every row belonging to the given library from every per-library
%% table, releasing blob references as we go. Must be called inside a
%% Mnesia transaction. Tables listed here must have their primary key
%% start with {LibType, LibId, ...} — we only guard on those first two
%% elements so the match spec is uniform.
cascade_delete_library({LT, LI}) ->
    [delete_lib_rows(Table, LT, LI) || Table <- lib_tables_3tuple_key()],
    [delete_lib_rows(Table, LT, LI) || Table <- lib_tables_4tuple_key()],
    %% file_meta: release the blob ref first (which may mark it for
    %% post-commit unlink), then delete the row.
    FileMetaMS = ets:fun2ms(
        fun(#shurbej_file_meta{id = {T, I, _}} = R) when T =:= LT, I =:= LI -> R end),
    lists:foreach(fun(#shurbej_file_meta{sha256 = Sha256} = R) ->
        case blob_unref_tx(Sha256) of
            0 -> mark_orphan_blob(Sha256);
            _ -> ok
        end,
        mnesia:delete_object(R)
    end, mnesia:select(shurbej_file_meta, FileMetaMS)),
    ok.

lib_tables_3tuple_key() ->
    [shurbej_item, shurbej_collection, shurbej_search,
     shurbej_setting, shurbej_fulltext, shurbej_item_collection].

lib_tables_4tuple_key() ->
    [shurbej_tag, shurbej_deleted].

delete_lib_rows(Table, LT, LI) ->
    %% Every library-scoped table puts the id tuple in position 2 of the
    %% record (mnesia record attributes start at 2). Match specs work the
    %% same for 3- and 4-element id tuples because we only bind the first
    %% two positions.
    MS = [{mk_row_pattern(Table), [{'=:=', {element, 1, {element, 2, '$_'}}, LT},
                                   {'=:=', {element, 2, {element, 2, '$_'}}, LI}],
           ['$_']}],
    lists:foreach(fun(R) -> mnesia:delete_object(R) end,
                  mnesia:select(Table, MS)).

mk_row_pattern(Table) ->
    %% A fully-wild record pattern — Table tagged, every field '_'.
    Arity = length(mnesia:table_info(Table, attributes)),
    list_to_tuple([Table | lists:duplicate(Arity, '_')]).

%% Orphan-blob bookkeeping. `delete_file_meta` and `cascade_delete_library`
%% record freed blob hashes here while running inside a Mnesia transaction;
%% the transaction driver (shurbej_version:do_write or delete_group) then
%% unlinks the files from disk after the transaction commits. On abort the
%% driver calls reset_orphan_blobs/0 instead so nothing gets unlinked.

-define(ORPHAN_PDICT_KEY, shurbej_orphan_blobs).

mark_orphan_blob(Hash) ->
    put(?ORPHAN_PDICT_KEY, [Hash | orphan_blobs()]),
    ok.

orphan_blobs() ->
    case get(?ORPHAN_PDICT_KEY) of
        undefined -> [];
        L when is_list(L) -> L
    end.

%% Clear the pending-unlink list. Use this before starting a transaction
%% whose failure should not trigger any blob deletions.
reset_orphan_blobs() ->
    erase(?ORPHAN_PDICT_KEY),
    ok.

%% Flush the pending-unlink list and delete each blob from disk. Call this
%% AFTER a successful transaction commit (never before — if the commit
%% aborts we must not unlink).
reap_orphan_blobs() ->
    Hashes = orphan_blobs(),
    erase(?ORPHAN_PDICT_KEY),
    lists:foreach(fun(Hash) ->
        _ = file:delete(shurbej_files:blob_path(Hash))
    end, Hashes),
    ok.

%% In-transaction blob unref — mirrors blob_unref/1 but without starting a
%% nested transaction. Returns the remaining refcount.
blob_unref_tx(Hash) ->
    case mnesia:read(shurbej_blob, Hash, write) of
        [#shurbej_blob{refcount = N} = Blob] when N > 1 ->
            mnesia:write(Blob#shurbej_blob{refcount = N - 1}),
            N - 1;
        [#shurbej_blob{}] ->
            mnesia:delete({shurbej_blob, Hash}),
            0;
        [] ->
            0
    end.

add_group_member(GroupId, UserUuid, Role)
        when is_integer(GroupId), is_binary(UserUuid) ->
    db_write(#shurbej_group_member{id = {GroupId, UserUuid}, role = Role}).

remove_group_member(GroupId, UserUuid)
        when is_integer(GroupId), is_binary(UserUuid) ->
    db_delete({shurbej_group_member, {GroupId, UserUuid}}).

get_group_member(GroupId, UserUuid)
        when is_integer(GroupId), is_binary(UserUuid) ->
    case db_read(shurbej_group_member, {GroupId, UserUuid}) of
        [Member] -> {ok, Member};
        [] -> undefined
    end.

list_group_members(GroupId) ->
    MS = ets:fun2ms(
        fun(#shurbej_group_member{id = {G, _}} = M) when G =:= GroupId -> M end),
    mnesia:dirty_select(shurbej_group_member, MS).

list_user_groups(UserUuid) when is_binary(UserUuid) ->
    MS = ets:fun2ms(
        fun(#shurbej_group_member{id = {_, U}} = M) when U =:= UserUuid -> M end),
    mnesia:dirty_select(shurbej_group_member, MS).

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

db_select(Table, MS) ->
    case mnesia:is_transaction() of
        true -> mnesia:select(Table, MS);
        false -> mnesia:dirty_select(Table, MS)
    end.

db_index_read(Table, Key, Pos) ->
    case mnesia:is_transaction() of
        true -> mnesia:index_read(Table, Key, Pos);
        false -> mnesia:dirty_index_read(Table, Key, Pos)
    end.
