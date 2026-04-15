-module(shurbey_http_collections).
-include_lib("shurbey_store/include/shurbey_records.hrl").

-export([init/2]).

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
        {error, Reason, _} ->
            Req = shurbey_http_common:auth_error_response(Reason, Req0),
            {ok, Req, State}
    end.

needs_write(<<"POST">>) -> true;
needs_write(<<"PUT">>) -> true;
needs_write(<<"PATCH">>) -> true;
needs_write(<<"DELETE">>) -> true;
needs_write(_) -> false.

handle(<<"GET">>, Req0, #{scope := single} = State) ->
    LibId = shurbey_http_common:library_id(Req0),
    CollKey = cowboy_req:binding(coll_key, Req0),
    case shurbey_db:get_collection(LibId, CollKey) of
        {ok, Coll} ->
            Body = shurbey_http_common:envelope_collection(LibId, Coll),
            Req = shurbey_http_common:json_response(200, Body, Coll#shurbey_collection.version, Req0),
            {ok, Req, State};
        undefined ->
            Req = shurbey_http_common:error_response(404, <<"Collection not found">>, Req0),
            {ok, Req, State}
    end;

handle(<<"GET">>, Req0, #{scope := Scope} = State) ->
    LibId = shurbey_http_common:library_id(Req0),
    Since = shurbey_http_common:get_since(Req0),
    {ok, LibVersion} = shurbey_version:get(LibId),
    case shurbey_http_common:get_if_modified(Req0) of
        V when is_integer(V), V >= LibVersion ->
            Req = cowboy_req:reply(304, #{
                <<"last-modified-version">> => integer_to_binary(LibVersion)
            }, Req0),
            {ok, Req, State};
        _ ->
            Colls0 = case Scope of
                top -> shurbey_db:list_collections_top(LibId, Since);
                subcollections ->
                    ParentKey = cowboy_req:binding(coll_key, Req0),
                    shurbey_db:list_subcollections(LibId, ParentKey, Since);
                _ -> shurbey_db:list_collections(LibId, Since)
            end,
            Colls = shurbey_http_common:filter_by_keys(Colls0,
                shurbey_http_common:get_collection_keys(Req0)),
            Format = shurbey_http_common:get_format(Req0),
            case Format of
                <<"versions">> ->
                    Pairs = [{K, V} || #shurbey_collection{id = {_, K}, version = V} <- Colls],
                    Req = shurbey_http_common:json_response(200, maps:from_list(Pairs), LibVersion, Req0),
                    {ok, Req, State};
                <<"keys">> ->
                    Keys = [K || #shurbey_collection{id = {_, K}} <- Colls],
                    Req = shurbey_http_common:json_response(200, Keys, LibVersion, Req0),
                    {ok, Req, State};
                _ ->
                    Sorted = shurbey_http_common:sort_records(Colls,
                        shurbey_http_common:get_sort(Req0),
                        shurbey_http_common:get_direction(Req0)),
                    Req = shurbey_http_common:list_response(Req0, Sorted, LibVersion,
                        fun(C) -> shurbey_http_common:envelope_collection(LibId, C) end),
                    {ok, Req, State}
            end
    end;

%% PUT/PATCH single collection
handle(Method, Req0, #{scope := single} = State) when Method =:= <<"PUT">>; Method =:= <<"PATCH">> ->
    LibId = shurbey_http_common:library_id(Req0),
    CollKey = cowboy_req:binding(coll_key, Req0),
    ExpectedVersion = shurbey_http_common:get_if_unmodified(Req0),
    case shurbey_http_common:read_json_body(Req0) of
        {error, _, Req1} ->
            Req = shurbey_http_common:error_response(400, <<"Invalid JSON">>, Req1),
            {ok, Req, State};
        {ok, Incoming, Req1} ->
    case shurbey_db:get_collection(LibId, CollKey) of
        undefined ->
            Req = shurbey_http_common:error_response(404, <<"Collection not found">>, Req1),
            {ok, Req, State};
        {ok, #shurbey_collection{data = Existing}} ->
            Merged = case Method of
                <<"PATCH">> -> maps:merge(Existing, Incoming);
                <<"PUT">> -> Incoming
            end,
            Coll = Merged#{<<"key">> => CollKey},
            case shurbey_validate:collection(Coll) of
                {error, Reason} ->
                    Req = shurbey_http_common:error_response(400, Reason, Req1),
                    {ok, Req, State};
                ok ->
                    case shurbey_version:write(LibId, ExpectedVersion, fun(NewVersion) ->
                        FullData = Coll#{<<"version">> => NewVersion},
                        shurbey_db:write_collection(#shurbey_collection{
                            id = {LibId, CollKey}, version = NewVersion,
                            data = FullData, deleted = false
                        })
                    end) of
                        {ok, NewVersion} ->
                            FullData = Coll#{<<"version">> => NewVersion},
                            Updated = #shurbey_collection{
                                id = {LibId, CollKey}, version = NewVersion,
                                data = FullData, deleted = false
                            },
                            Envelope = shurbey_http_common:envelope_collection(LibId, Updated),
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

handle(<<"POST">>, Req0, State) ->
    LibId = shurbey_http_common:library_id(Req0),
    ExpectedVersion = shurbey_http_common:get_if_unmodified(Req0),
    case shurbey_http_common:read_json_body(Req0) of
        {error, _, Req1} ->
            Req = shurbey_http_common:error_response(400, <<"Invalid JSON">>, Req1),
            {ok, Req, State};
        {ok, Collections, Req1} when is_list(Collections) ->
    KeyedColls = [ensure_key(C) || C <- Collections],
    {Valid, Failed} = shurbey_http_items:validate_each(KeyedColls, fun shurbey_validate:collection/1),
    case Valid of
        [] when map_size(Failed) > 0 ->
            Result = #{<<"successful">> => #{}, <<"unchanged">> => #{}, <<"failed">> => Failed},
            Req = shurbey_http_common:json_response(400, Result, Req1),
            {ok, Req, State};
        _ ->
            case shurbey_version:write(LibId, ExpectedVersion, fun(NewVersion) ->
                lists:foreach(fun({_Idx, Coll}) ->
                    Key = maps:get(<<"key">>, Coll),
                    FullData = Coll#{<<"key">> => Key, <<"version">> => NewVersion},
                    shurbey_db:write_collection(#shurbey_collection{
                        id = {LibId, Key},
                        version = NewVersion,
                        data = FullData,
                        deleted = false
                    })
                end, Valid),
                ok
            end) of
                {ok, NewVersion} ->
                    Successful = maps:from_list(
                        [{integer_to_binary(Idx), shurbey_http_items:envelope_for_write(LibId, C, NewVersion)}
                         || {Idx, C} <- Valid]),
                    Result = #{
                        <<"successful">> => Successful,
                        <<"unchanged">> => #{},
                        <<"failed">> => Failed
                    },
                    Req = shurbey_http_common:json_response(200, Result, NewVersion, Req1),
                    {ok, Req, State};
                {error, precondition, CurrentVersion} ->
                    Req = shurbey_http_common:json_response(412,
                        #{<<"message">> => <<"Library has been modified since specified version">>},
                        CurrentVersion, Req1),
                    {ok, Req, State}
            end
    end;
        {ok, _, Req1} ->
            Req = shurbey_http_common:error_response(400, <<"Body must be a JSON array">>, Req1),
            {ok, Req, State}
    end;

handle(<<"DELETE">>, Req0, State) ->
    LibId = shurbey_http_common:library_id(Req0),
    ExpectedVersion = shurbey_http_common:get_if_unmodified(Req0),
    #{collectionKey := KeysParam} = cowboy_req:match_qs([{collectionKey, [], <<>>}], Req0),
    Keys = binary:split(KeysParam, <<",">>, [global]),
    case shurbey_version:write(LibId, ExpectedVersion, fun(NewVersion) ->
        lists:foreach(fun(K) ->
            shurbey_db:mark_collection_deleted(LibId, K, NewVersion),
            shurbey_db:record_deletion(LibId, <<"collection">>, K, NewVersion)
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
    end;

handle(_, Req0, State) ->
    Req = shurbey_http_common:error_response(405, <<"Method not allowed">>, Req0),
    {ok, Req, State}.

ensure_key(Item) ->
    case maps:get(<<"key">>, Item, undefined) of
        undefined -> Item#{<<"key">> => shurbey_http_items:generate_key()};
        _ -> Item
    end.
