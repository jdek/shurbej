-module(shurbej_http_items).
-include_lib("shurbej_store/include/shurbej_records.hrl").

-export([init/2, generate_key/0, validate_each/2, envelope_for_write/3]).

-define(MAX_WRITE_ITEMS, 50).

init(Req0, State) ->
    case shurbej_http_common:authorize(Req0) of
        {ok, LibRef, _} ->
            Method = cowboy_req:method(Req0),
            Perm = perm_for_method(Method),
            case shurbej_http_common:check_lib_perm(Perm, LibRef) of
                {error, forbidden} ->
                    Req = shurbej_http_common:error_response(403, <<"Access denied">>, Req0),
                    {ok, Req, State};
                ok ->
                    handle(Method, Req0, State)
            end;
        {error, bad_request, Req} ->
            Req2 = shurbej_http_common:error_response(400, <<"Invalid user ID">>, Req),
            {ok, Req2, State};
        {error, Reason, _} ->
            Req = shurbej_http_common:auth_error_response(Reason, Req0),
            {ok, Req, State}
    end.

perm_for_method(<<"GET">>) -> read;
perm_for_method(<<"HEAD">>) -> read;
perm_for_method(_) -> write.

%% GET single item
handle(<<"GET">>, Req0, #{scope := single} = State) ->
    LibRef = shurbej_http_common:lib_ref(Req0),
    ItemKey = cowboy_req:binding(item_key, Req0),
    case shurbej_db:get_item(LibRef, ItemKey) of
        {ok, Item} ->
            {ok, LibVersion} = shurbej_version:get(LibRef),
            ChildrenCounts = cached_children_counts(LibRef, LibVersion),
            Body = shurbej_http_common:envelope_item(LibRef, Item, ChildrenCounts),
            Req = shurbej_http_common:json_response(200, Body, Item#shurbej_item.version, Req0),
            {ok, Req, State};
        undefined ->
            Req = shurbej_http_common:error_response(404, <<"Item not found">>, Req0),
            {ok, Req, State}
    end;

%% GET list — dispatch by scope
handle(<<"GET">>, Req0, #{scope := Scope} = State) ->
    LibRef = shurbej_http_common:lib_ref(Req0),
    Since = shurbej_http_common:get_since(Req0),
    {ok, LibVersion} = shurbej_version:get(LibRef),
    case shurbej_http_common:check_304(Req0, LibVersion) of
        {304, Req} ->
            {ok, Req, State};
        continue ->
            Items = fetch_items(Scope, LibRef, Since, Req0),
            Items2 = apply_filters(Items, Req0),
            Format = shurbej_http_common:get_format(Req0),
            respond_list(Format, Items2, LibRef, LibVersion, Req0, State)
    end;

%% POST — create/update items (with write token idempotency)
handle(<<"POST">>, Req0, State) ->
    WriteToken = shurbej_http_common:get_write_token(Req0),
    case shurbej_write_token:check(WriteToken) of
        {duplicate, {Result, Version}} ->
            Req = shurbej_http_common:json_response(200, Result, Version, Req0),
            {ok, Req, State};
        in_progress ->
            %% Concurrent request with same token — proceed without token caching
            do_post(Req0, State, undefined);
        new ->
            do_post(Req0, State, WriteToken)
    end;

%% PUT/PATCH single item — update a specific item
handle(Method, Req0, #{scope := single} = State) when Method =:= <<"PUT">>; Method =:= <<"PATCH">> ->
    LibRef = shurbej_http_common:lib_ref(Req0),
    ItemKey = cowboy_req:binding(item_key, Req0),
    ExpectedVersion = shurbej_http_common:get_if_unmodified(Req0),
    case shurbej_http_common:read_json_body(Req0) of
        {error, Reason, Req1} ->
            Req = shurbej_http_common:error_response(400, body_error(Reason), Req1),
            {ok, Req, State};
        {ok, Incoming, Req1} ->
            case shurbej_db:get_item(LibRef, ItemKey) of
                undefined ->
                    Req = shurbej_http_common:error_response(404, <<"Item not found">>, Req1),
                    {ok, Req, State};
                {ok, #shurbej_item{data = Existing}} ->
                    Merged = case Method of
                        <<"PATCH">> -> maps:merge(Existing, Incoming);
                        <<"PUT">> -> Incoming
                    end,
                    Item = Merged#{<<"key">> => ItemKey},
                    case shurbej_validate:item(Item) of
                        {error, Reason2} ->
                            Req = shurbej_http_common:error_response(400, Reason2, Req1),
                            {ok, Req, State};
                        ok ->
                            case shurbej_version:write(LibRef, ExpectedVersion, fun(NewVersion) ->
                                write_item(LibRef, Item, NewVersion)
                            end) of
                                {ok, NewVersion} ->
                                    Envelope = envelope_for_write(LibRef, Item, NewVersion),
                                    Req = shurbej_http_common:json_response(200, Envelope, NewVersion, Req1),
                                    {ok, Req, State};
                                {error, precondition, CurrentVersion} ->
                                    Req = shurbej_http_common:json_response(412,
                                        #{<<"message">> => <<"Library has been modified since specified version">>},
                                        CurrentVersion, Req1),
                                    {ok, Req, State}
                            end
                    end
            end
    end;

%% DELETE single item
handle(<<"DELETE">>, Req0, #{scope := single} = State) ->
    LibRef = shurbej_http_common:lib_ref(Req0),
    ItemKey = cowboy_req:binding(item_key, Req0),
    ExpectedVersion = shurbej_http_common:get_if_unmodified(Req0),
    case shurbej_version:write(LibRef, ExpectedVersion, fun(NewVersion) ->
        cascade_delete(LibRef, ItemKey, NewVersion),
        ok
    end) of
        {ok, NewVersion} ->
            Req = cowboy_req:reply(204, #{
                <<"last-modified-version">> => integer_to_binary(NewVersion)
            }, Req0),
            {ok, Req, State};
        {error, precondition, CurrentVersion} ->
            Req = shurbej_http_common:json_response(412,
                #{<<"message">> => <<"Library has been modified since specified version">>},
                CurrentVersion, Req0),
            {ok, Req, State}
    end;

%% DELETE multiple — cascade to tags, fulltext, file metadata, children
handle(<<"DELETE">>, Req0, State) ->
    LibRef = shurbej_http_common:lib_ref(Req0),
    ExpectedVersion = shurbej_http_common:get_if_unmodified(Req0),
    #{itemKey := KeysParam} = cowboy_req:match_qs([{itemKey, [], <<>>}], Req0),
    Keys = [K || K <- binary:split(KeysParam, <<",">>, [global]), K =/= <<>>],
    case Keys of
        [] ->
            Req = shurbej_http_common:error_response(400, <<"No item keys specified">>, Req0),
            {ok, Req, State};
        _ ->
            case shurbej_version:write(LibRef, ExpectedVersion, fun(NewVersion) ->
                lists:foreach(fun(K) ->
                    cascade_delete(LibRef, K, NewVersion)
                end, Keys),
                ok
            end) of
                {ok, NewVersion} ->
                    Req = cowboy_req:reply(204, #{
                        <<"last-modified-version">> => integer_to_binary(NewVersion)
                    }, Req0),
                    {ok, Req, State};
                {error, precondition, CurrentVersion} ->
                    Req = shurbej_http_common:json_response(412,
                        #{<<"message">> => <<"Library has been modified since specified version">>},
                        CurrentVersion, Req0),
                    {ok, Req, State}
            end
    end;

handle(_, Req0, State) ->
    Req = shurbej_http_common:error_response(405, <<"Method not allowed">>, Req0),
    {ok, Req, State}.

%% Internal — respond to list GET by format

respond_list(<<"versions">>, Items, _LibRef, LibVersion, Req0, State) ->
    VersionMap = maps:from_list(
        [{K, V} || #shurbej_item{id = {_, _, K}, version = V} <- Items]),
    Req = shurbej_http_common:json_response(200, VersionMap, LibVersion, Req0),
    {ok, Req, State};
respond_list(<<"keys">>, Items, _LibRef, LibVersion, Req0, State) ->
    Keys = [K || #shurbej_item{id = {_, _, K}} <- Items],
    Req = shurbej_http_common:json_response(200, Keys, LibVersion, Req0),
    {ok, Req, State};
respond_list(Format, _Items, _LibRef, _LibVersion, Req0, State)
        when Format =:= <<"atom">>; Format =:= <<"bib">>;
             Format =:= <<"ris">>; Format =:= <<"mods">> ->
    Req = shurbej_http_common:error_response(400,
        <<"Export format '", Format/binary, "' is not supported by this server">>, Req0),
    {ok, Req, State};
respond_list(_, Items, LibRef, LibVersion, Req0, State) ->
    ChildrenCounts = cached_children_counts(LibRef, LibVersion),
    Sorted = shurbej_http_common:sort_records(Items,
        shurbej_http_common:get_sort(Req0),
        shurbej_http_common:get_direction(Req0)),
    Req = shurbej_http_common:list_response(Req0, Sorted, LibVersion,
        fun(I) -> shurbej_http_common:envelope_item(LibRef, I, ChildrenCounts) end),
    {ok, Req, State}.

%% Internal — fetch items by scope

fetch_items(all, LibRef, Since, Req) ->
    Base = shurbej_db:list_items(LibRef, Since),
    maybe_include_trashed(Base, LibRef, Since, Req);
fetch_items(top, LibRef, Since, Req) ->
    Base = shurbej_db:list_items_top(LibRef, Since),
    maybe_include_trashed(Base, LibRef, Since, Req);
fetch_items(trash, LibRef, Since, _Req) ->
    shurbej_db:list_items_trash(LibRef, Since);
fetch_items(children, LibRef, Since, Req) ->
    ParentKey = cowboy_req:binding(item_key, Req),
    shurbej_db:list_items_children(LibRef, ParentKey, Since);
fetch_items(collection, LibRef, Since, Req) ->
    CollKey = cowboy_req:binding(coll_key, Req),
    shurbej_db:list_items_in_collection(LibRef, CollKey, Since);
fetch_items(collection_top, LibRef, Since, Req) ->
    CollKey = cowboy_req:binding(coll_key, Req),
    [I || #shurbej_item{data = D} = I
          <- shurbej_db:list_items_in_collection(LibRef, CollKey, Since),
          maps:get(<<"parentItem">>, D, false) =:= false].

maybe_include_trashed(Items, LibRef, Since, Req) ->
    case shurbej_http_common:get_include_trashed(Req) of
        true -> Items ++ shurbej_db:list_items_trash(LibRef, Since);
        false -> Items
    end.

apply_filters(Items, Req) ->
    Items2 = filter_by_item_keys(Items, shurbej_http_common:get_item_keys(Req)),
    Items3 = shurbej_http_common:filter_by_tag(Items2, shurbej_http_common:get_tag_filter(Req)),
    Items4 = shurbej_http_common:filter_by_item_type(Items3, shurbej_http_common:get_item_type_filter(Req)),
    shurbej_http_common:filter_by_query(Items4, shurbej_http_common:get_query(Req),
        shurbej_http_common:get_qmode(Req)).

filter_by_item_keys(Items, all) -> Items;
filter_by_item_keys(Items, Keys) ->
    KeySet = sets:from_list(Keys),
    [I || #shurbej_item{id = {_, _, K}} = I <- Items, sets:is_element(K, KeySet)].

do_post(Req0, State, WriteToken) ->
    LibRef = shurbej_http_common:lib_ref(Req0),
    ExpectedVersion = shurbej_http_common:get_if_unmodified(Req0),
    case shurbej_http_common:read_json_body(Req0) of
        {error, Reason, Req1} ->
            Req = shurbej_http_common:error_response(400, body_error(Reason), Req1),
            {ok, Req, State};
        {ok, Items, Req1} when is_list(Items), length(Items) =< ?MAX_WRITE_ITEMS ->
            KeyedItems = [ensure_key(I) || I <- Items],
            {Valid, Failed} = validate_each(KeyedItems, fun shurbej_validate:item/1),
            case Valid of
                [] when map_size(Failed) > 0 ->
                    Result = #{<<"successful">> => #{}, <<"unchanged">> => #{}, <<"failed">> => Failed},
                    Req = shurbej_http_common:json_response(400, Result, Req1),
                    {ok, Req, State};
                _ ->
                    case shurbej_version:write(LibRef, ExpectedVersion, fun(NewVersion) ->
                        lists:foreach(fun({_Idx, Item}) ->
                            write_item(LibRef, Item, NewVersion)
                        end, Valid),
                        ok
                    end) of
                        {ok, NewVersion} ->
                            Successful = maps:from_list(
                                [{integer_to_binary(Idx), envelope_for_write(LibRef, Item, NewVersion)}
                                 || {Idx, Item} <- Valid]),
                            Result = #{
                                <<"successful">> => Successful,
                                <<"unchanged">> => #{},
                                <<"failed">> => Failed
                            },
                            shurbej_write_token:store(WriteToken, {Result, NewVersion}),
                            Req = shurbej_http_common:json_response(200, Result, NewVersion, Req1),
                            {ok, Req, State};
                        {error, precondition, CurrentVersion} ->
                            Req = shurbej_http_common:json_response(412,
                                #{<<"message">> => <<"Library has been modified since specified version">>},
                                CurrentVersion, Req1),
                            {ok, Req, State}
                    end
            end;
        {ok, Items, Req1} when is_list(Items) ->
            Req = shurbej_http_common:error_response(413,
                <<"Too many items (max ", (integer_to_binary(?MAX_WRITE_ITEMS))/binary, ")">>, Req1),
            {ok, Req, State};
        {ok, _, Req1} ->
            Req = shurbej_http_common:error_response(400, <<"Body must be a JSON array">>, Req1),
            {ok, Req, State}
    end.

%% Cascade delete — wrapped in Mnesia transaction for atomicity
cascade_delete(LibRef, ItemKey, NewVersion) ->
    shurbej_db:mark_item_deleted(LibRef, ItemKey, NewVersion),
    shurbej_db:record_deletion(LibRef, <<"item">>, ItemKey, NewVersion),
    shurbej_db:delete_item_tags(LibRef, ItemKey),
    shurbej_db:delete_item_collections(LibRef, ItemKey),
    shurbej_db:delete_fulltext(LibRef, ItemKey),
    shurbej_db:delete_file_meta(LibRef, ItemKey),
    %% list_items_children now uses the parent_key secondary index — O(k) not O(n).
    Children = shurbej_db:list_items_children(LibRef, ItemKey, 0),
    lists:foreach(fun(#shurbej_item{id = {_, _, ChildKey}}) ->
        cascade_delete(LibRef, ChildKey, NewVersion)
    end, Children).

ensure_key(Item) when is_map(Item) ->
    case maps:get(<<"key">>, Item, undefined) of
        undefined -> Item#{<<"key">> => generate_key()};
        _ -> Item
    end;
ensure_key(_) -> #{<<"key">> => generate_key()}.

write_item({LT, LI} = LibRef, Item, NewVersion) ->
    Key = maps:get(<<"key">>, Item),
    FullData = Item#{<<"version">> => NewVersion},
    ParentKey = case maps:get(<<"parentItem">>, Item, false) of
        P when is_binary(P) -> P;
        _ -> undefined
    end,
    shurbej_db:write_item(#shurbej_item{
        id = {LT, LI, Key},
        version = NewVersion,
        data = FullData,
        deleted = false,
        parent_key = ParentKey
    }),
    Collections = maps:get(<<"collections">>, Item, []),
    shurbej_db:set_item_collections(LibRef, Key, Collections),
    Tags = maps:get(<<"tags">>, Item, []),
    TagPairs = [{maps:get(<<"tag">>, T, <<>>), maps:get(<<"type">>, T, 0)} || T <- Tags],
    shurbej_db:set_item_tags(LibRef, Key, TagPairs).

validate_each(Items, ValidateFn) ->
    {Valid, Failed} = lists:foldl(fun({Idx, Item}, {V, F}) ->
        case ValidateFn(Item) of
            ok -> {[{Idx, Item} | V], F};
            {error, Reason} ->
                F2 = F#{integer_to_binary(Idx) => #{
                    <<"key">> => maps:get(<<"key">>, Item, <<>>),
                    <<"code">> => 400,
                    <<"message">> => Reason
                }},
                {V, F2}
        end
    end, {[], #{}}, lists:enumerate(0, Items)),
    {lists:reverse(Valid), Failed}.

envelope_for_write(LibRef, Item, NewVersion) ->
    Key = maps:get(<<"key">>, Item),
    Base = shurbej_http_common:base_url(),
    Prefix = shurbej_http_common:lib_path_prefix(LibRef),
    FullData = Item#{<<"key">> => Key, <<"version">> => NewVersion},
    #{
        <<"key">> => Key,
        <<"version">> => NewVersion,
        <<"library">> => shurbej_http_common:library_obj(LibRef),
        <<"links">> => #{
            <<"self">> => #{
                <<"href">> => <<Base/binary, Prefix/binary, "/items/", Key/binary>>,
                <<"type">> => <<"application/json">>
            }
        },
        <<"meta">> => #{<<"numChildren">> => 0},
        <<"data">> => FullData
    }.

%% Generate item key using CSPRNG — not rand:uniform
generate_key() ->
    Chars = <<"23456789ABCDEFGHIJKLMNPQRSTUVWXYZ">>,
    Len = byte_size(Chars),
    Bytes = crypto:strong_rand_bytes(8),
    list_to_binary([binary:at(Chars, B rem Len) || <<B>> <= Bytes]).

body_error(invalid_json) -> <<"Invalid JSON">>;
body_error(body_too_large) -> <<"Request body too large">>.

%% Cache children counts by {LibRef, LibVersion} — computed at most once per write.
cached_children_counts(LibRef, LibVersion) ->
    Key = {shurbej_children, LibRef, LibVersion},
    case persistent_term:get(Key, undefined) of
        undefined ->
            Counts = shurbej_db:count_item_children(LibRef),
            catch persistent_term:erase({shurbej_children, LibRef, LibVersion - 1}),
            persistent_term:put(Key, Counts),
            Counts;
        Counts ->
            Counts
    end.
