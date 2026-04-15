-module(shurbey_http_items).
-include_lib("shurbey_store/include/shurbey_records.hrl").

-export([init/2, generate_key/0, validate_each/2, envelope_for_write/3]).

-define(MAX_WRITE_ITEMS, 50).

init(Req0, State) ->
    case shurbey_http_common:authorize(Req0) of
        {ok, _LibId, _} ->
            Method = cowboy_req:method(Req0),
            case needs_write(Method) andalso shurbey_http_common:check_perm(write) of
                {error, forbidden} ->
                    Req = shurbey_http_common:error_response(403, <<"Write access denied">>, Req0),
                    {ok, Req, State};
                _ ->
                    handle(Method, Req0, State)
            end;
        {error, bad_request, Req} ->
            Req2 = shurbey_http_common:error_response(400, <<"Invalid user ID">>, Req),
            {ok, Req2, State};
        {error, Reason, _} ->
            Req = shurbey_http_common:auth_error_response(Reason, Req0),
            {ok, Req, State}
    end.

needs_write(<<"POST">>) -> true;
needs_write(<<"PUT">>) -> true;
needs_write(<<"PATCH">>) -> true;
needs_write(<<"DELETE">>) -> true;
needs_write(_) -> false.

%% GET single item
handle(<<"GET">>, Req0, #{scope := single} = State) ->
    LibId = shurbey_http_common:library_id(Req0),
    ItemKey = cowboy_req:binding(item_key, Req0),
    case shurbey_db:get_item(LibId, ItemKey) of
        {ok, Item} ->
            ChildrenCounts = shurbey_db:count_item_children(LibId),
            Body = shurbey_http_common:envelope_item(LibId, Item, ChildrenCounts),
            Req = shurbey_http_common:json_response(200, Body, Item#shurbey_item.version, Req0),
            {ok, Req, State};
        undefined ->
            Req = shurbey_http_common:error_response(404, <<"Item not found">>, Req0),
            {ok, Req, State}
    end;

%% GET list — dispatch by scope
handle(<<"GET">>, Req0, #{scope := Scope} = State) ->
    LibId = shurbey_http_common:library_id(Req0),
    Since = shurbey_http_common:get_since(Req0),
    {ok, LibVersion} = shurbey_version:get(LibId),
    case shurbey_http_common:check_304(Req0, LibVersion) of
        {304, Req} ->
            {ok, Req, State};
        continue ->
            Items = fetch_items(Scope, LibId, Since, Req0),
            Items2 = apply_filters(Items, Req0),
            Format = shurbey_http_common:get_format(Req0),
            respond_list(Format, Items2, LibId, LibVersion, Req0, State)
    end;

%% POST — create/update items (with write token idempotency)
handle(<<"POST">>, Req0, State) ->
    WriteToken = shurbey_http_common:get_write_token(Req0),
    case shurbey_write_token:check(WriteToken) of
        {duplicate, {Result, Version}} ->
            Req = shurbey_http_common:json_response(200, Result, Version, Req0),
            {ok, Req, State};
        in_progress ->
            %% Concurrent request with same token — proceed without token caching
            do_post(Req0, State, undefined);
        new ->
            do_post(Req0, State, WriteToken)
    end;

%% PUT/PATCH single item — update a specific item
handle(Method, Req0, #{scope := single} = State) when Method =:= <<"PUT">>; Method =:= <<"PATCH">> ->
    LibId = shurbey_http_common:library_id(Req0),
    ItemKey = cowboy_req:binding(item_key, Req0),
    ExpectedVersion = shurbey_http_common:get_if_unmodified(Req0),
    case shurbey_http_common:read_json_body(Req0) of
        {error, Reason, Req1} ->
            Req = shurbey_http_common:error_response(400, body_error(Reason), Req1),
            {ok, Req, State};
        {ok, Incoming, Req1} ->
            case shurbey_db:get_item(LibId, ItemKey) of
                undefined ->
                    Req = shurbey_http_common:error_response(404, <<"Item not found">>, Req1),
                    {ok, Req, State};
                {ok, #shurbey_item{data = Existing}} ->
                    Merged = case Method of
                        <<"PATCH">> -> maps:merge(Existing, Incoming);
                        <<"PUT">> -> Incoming
                    end,
                    Item = Merged#{<<"key">> => ItemKey},
                    case shurbey_validate:item(Item) of
                        {error, Reason2} ->
                            Req = shurbey_http_common:error_response(400, Reason2, Req1),
                            {ok, Req, State};
                        ok ->
                            case shurbey_version:write(LibId, ExpectedVersion, fun(NewVersion) ->
                                write_item(LibId, Item, NewVersion)
                            end) of
                                {ok, NewVersion} ->
                                    {ok, UpdatedItem} = shurbey_db:get_item(LibId, ItemKey),
                                    Envelope = shurbey_http_common:envelope_item(LibId, UpdatedItem),
                                    Req = shurbey_http_common:json_response(200, Envelope, NewVersion, Req1),
                                    {ok, Req, State};
                                {error, precondition, CurrentVersion} ->
                                    Req = shurbey_http_common:json_response(412,
                                        #{<<"message">> => <<"Library has been modified since specified version">>},
                                        CurrentVersion, Req1),
                                    {ok, Req, State}
                            end
                    end
            end
    end;

%% DELETE single item
handle(<<"DELETE">>, Req0, #{scope := single} = State) ->
    LibId = shurbey_http_common:library_id(Req0),
    ItemKey = cowboy_req:binding(item_key, Req0),
    ExpectedVersion = shurbey_http_common:get_if_unmodified(Req0),
    case shurbey_version:write(LibId, ExpectedVersion, fun(NewVersion) ->
        cascade_delete(LibId, ItemKey, NewVersion),
        ok
    end) of
        {ok, NewVersion} ->
            Req = cowboy_req:reply(204, #{
                <<"last-modified-version">> => integer_to_binary(NewVersion)
            }, Req0),
            {ok, Req, State};
        {error, precondition, CurrentVersion} ->
            Req = shurbey_http_common:json_response(412,
                #{<<"message">> => <<"Library has been modified since specified version">>},
                CurrentVersion, Req0),
            {ok, Req, State}
    end;

%% DELETE multiple — cascade to tags, fulltext, file metadata, children
handle(<<"DELETE">>, Req0, State) ->
    LibId = shurbey_http_common:library_id(Req0),
    ExpectedVersion = shurbey_http_common:get_if_unmodified(Req0),
    #{itemKey := KeysParam} = cowboy_req:match_qs([{itemKey, [], <<>>}], Req0),
    Keys = [K || K <- binary:split(KeysParam, <<",">>, [global]), K =/= <<>>],
    case Keys of
        [] ->
            Req = shurbey_http_common:error_response(400, <<"No item keys specified">>, Req0),
            {ok, Req, State};
        _ ->
            case shurbey_version:write(LibId, ExpectedVersion, fun(NewVersion) ->
                lists:foreach(fun(K) ->
                    cascade_delete(LibId, K, NewVersion)
                end, Keys),
                ok
            end) of
                {ok, NewVersion} ->
                    Req = cowboy_req:reply(204, #{
                        <<"last-modified-version">> => integer_to_binary(NewVersion)
                    }, Req0),
                    {ok, Req, State};
                {error, precondition, CurrentVersion} ->
                    Req = shurbey_http_common:json_response(412,
                        #{<<"message">> => <<"Library has been modified since specified version">>},
                        CurrentVersion, Req0),
                    {ok, Req, State}
            end
    end;

handle(_, Req0, State) ->
    Req = shurbey_http_common:error_response(405, <<"Method not allowed">>, Req0),
    {ok, Req, State}.

%% Internal — respond to list GET by format

respond_list(<<"versions">>, Items, _LibId, LibVersion, Req0, State) ->
    VersionMap = maps:from_list(
        [{K, V} || #shurbey_item{id = {_, K}, version = V} <- Items]),
    Req = shurbey_http_common:json_response(200, VersionMap, LibVersion, Req0),
    {ok, Req, State};
respond_list(<<"keys">>, Items, _LibId, LibVersion, Req0, State) ->
    Keys = [K || #shurbey_item{id = {_, K}} <- Items],
    Req = shurbey_http_common:json_response(200, Keys, LibVersion, Req0),
    {ok, Req, State};
respond_list(Format, _Items, _LibId, _LibVersion, Req0, State)
        when Format =:= <<"atom">>; Format =:= <<"bib">>;
             Format =:= <<"ris">>; Format =:= <<"mods">> ->
    Req = shurbey_http_common:error_response(400,
        <<"Export format '", Format/binary, "' is not supported by this server">>, Req0),
    {ok, Req, State};
respond_list(_, Items, LibId, LibVersion, Req0, State) ->
    ChildrenCounts = shurbey_db:count_item_children(LibId),
    Sorted = shurbey_http_common:sort_records(Items,
        shurbey_http_common:get_sort(Req0),
        shurbey_http_common:get_direction(Req0)),
    Req = shurbey_http_common:list_response(Req0, Sorted, LibVersion,
        fun(I) -> shurbey_http_common:envelope_item(LibId, I, ChildrenCounts) end),
    {ok, Req, State}.

%% Internal — fetch items by scope

fetch_items(all, LibId, Since, Req) ->
    Base = shurbey_db:list_items(LibId, Since),
    maybe_include_trashed(Base, LibId, Since, Req);
fetch_items(top, LibId, Since, Req) ->
    Base = shurbey_db:list_items_top(LibId, Since),
    maybe_include_trashed(Base, LibId, Since, Req);
fetch_items(trash, LibId, Since, _Req) ->
    shurbey_db:list_items_trash(LibId, Since);
fetch_items(children, LibId, Since, Req) ->
    ParentKey = cowboy_req:binding(item_key, Req),
    shurbey_db:list_items_children(LibId, ParentKey, Since);
fetch_items(collection, LibId, Since, Req) ->
    CollKey = cowboy_req:binding(coll_key, Req),
    shurbey_db:list_items_in_collection(LibId, CollKey, Since);
fetch_items(collection_top, LibId, Since, Req) ->
    CollKey = cowboy_req:binding(coll_key, Req),
    [I || #shurbey_item{data = D} = I
          <- shurbey_db:list_items_in_collection(LibId, CollKey, Since),
          maps:get(<<"parentItem">>, D, false) =:= false].

maybe_include_trashed(Items, LibId, Since, Req) ->
    case shurbey_http_common:get_include_trashed(Req) of
        true -> Items ++ shurbey_db:list_items_trash(LibId, Since);
        false -> Items
    end.

apply_filters(Items, Req) ->
    Items2 = filter_by_item_keys(Items, shurbey_http_common:get_item_keys(Req)),
    Items3 = shurbey_http_common:filter_by_tag(Items2, shurbey_http_common:get_tag_filter(Req)),
    Items4 = shurbey_http_common:filter_by_item_type(Items3, shurbey_http_common:get_item_type_filter(Req)),
    shurbey_http_common:filter_by_query(Items4, shurbey_http_common:get_query(Req),
        shurbey_http_common:get_qmode(Req)).

filter_by_item_keys(Items, all) -> Items;
filter_by_item_keys(Items, Keys) ->
    KeySet = sets:from_list(Keys),
    [I || #shurbey_item{id = {_, K}} = I <- Items, sets:is_element(K, KeySet)].

do_post(Req0, State, WriteToken) ->
    LibId = shurbey_http_common:library_id(Req0),
    ExpectedVersion = shurbey_http_common:get_if_unmodified(Req0),
    case shurbey_http_common:read_json_body(Req0) of
        {error, Reason, Req1} ->
            Req = shurbey_http_common:error_response(400, body_error(Reason), Req1),
            {ok, Req, State};
        {ok, Items, Req1} when is_list(Items), length(Items) =< ?MAX_WRITE_ITEMS ->
            KeyedItems = [ensure_key(I) || I <- Items],
            {Valid, Failed} = validate_each(KeyedItems, fun shurbey_validate:item/1),
            case Valid of
                [] when map_size(Failed) > 0 ->
                    Result = #{<<"successful">> => #{}, <<"unchanged">> => #{}, <<"failed">> => Failed},
                    Req = shurbey_http_common:json_response(400, Result, Req1),
                    {ok, Req, State};
                _ ->
                    case shurbey_version:write(LibId, ExpectedVersion, fun(NewVersion) ->
                        lists:foreach(fun({_Idx, Item}) ->
                            write_item(LibId, Item, NewVersion)
                        end, Valid),
                        ok
                    end) of
                        {ok, NewVersion} ->
                            Successful = maps:from_list(
                                [{integer_to_binary(Idx), envelope_for_write(LibId, Item, NewVersion)}
                                 || {Idx, Item} <- Valid]),
                            Result = #{
                                <<"successful">> => Successful,
                                <<"unchanged">> => #{},
                                <<"failed">> => Failed
                            },
                            shurbey_write_token:store(WriteToken, {Result, NewVersion}),
                            Req = shurbey_http_common:json_response(200, Result, NewVersion, Req1),
                            {ok, Req, State};
                        {error, precondition, CurrentVersion} ->
                            Req = shurbey_http_common:json_response(412,
                                #{<<"message">> => <<"Library has been modified since specified version">>},
                                CurrentVersion, Req1),
                            {ok, Req, State}
                    end
            end;
        {ok, Items, Req1} when is_list(Items) ->
            Req = shurbey_http_common:error_response(413,
                <<"Too many items (max ", (integer_to_binary(?MAX_WRITE_ITEMS))/binary, ")">>, Req1),
            {ok, Req, State};
        {ok, _, Req1} ->
            Req = shurbey_http_common:error_response(400, <<"Body must be a JSON array">>, Req1),
            {ok, Req, State}
    end.

%% Cascade delete — wrapped in Mnesia transaction for atomicity
cascade_delete(LibId, ItemKey, NewVersion) ->
    shurbey_db:mark_item_deleted(LibId, ItemKey, NewVersion),
    shurbey_db:record_deletion(LibId, <<"item">>, ItemKey, NewVersion),
    shurbey_db:delete_item_tags(LibId, ItemKey),
    shurbey_db:delete_fulltext(LibId, ItemKey),
    shurbey_db:delete_file_meta(LibId, ItemKey),
    Children = shurbey_db:list_items_children(LibId, ItemKey, 0),
    lists:foreach(fun(#shurbey_item{id = {_, ChildKey}}) ->
        cascade_delete(LibId, ChildKey, NewVersion)
    end, Children).

ensure_key(Item) when is_map(Item) ->
    case maps:get(<<"key">>, Item, undefined) of
        undefined -> Item#{<<"key">> => generate_key()};
        _ -> Item
    end;
ensure_key(_) -> #{<<"key">> => generate_key()}.

write_item(LibId, Item, NewVersion) ->
    Key = maps:get(<<"key">>, Item),
    FullData = Item#{<<"version">> => NewVersion},
    shurbey_db:write_item(#shurbey_item{
        id = {LibId, Key},
        version = NewVersion,
        data = FullData,
        deleted = false
    }),
    Tags = maps:get(<<"tags">>, Item, []),
    TagPairs = [{maps:get(<<"tag">>, T, <<>>), maps:get(<<"type">>, T, 0)} || T <- Tags],
    shurbey_db:set_item_tags(LibId, Key, TagPairs).

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

envelope_for_write(LibId, Item, NewVersion) ->
    Key = maps:get(<<"key">>, Item),
    Base = shurbey_http_common:base_url(),
    LibBin = integer_to_binary(LibId),
    FullData = Item#{<<"key">> => Key, <<"version">> => NewVersion},
    #{
        <<"key">> => Key,
        <<"version">> => NewVersion,
        <<"library">> => #{<<"type">> => <<"user">>, <<"id">> => LibId},
        <<"links">> => #{
            <<"self">> => #{
                <<"href">> => <<Base/binary, "/users/", LibBin/binary, "/items/", Key/binary>>,
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
