-module(shurbej_http_searches).
-include_lib("shurbej_store/include/shurbej_records.hrl").

-export([init/2]).

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
        {error, Reason, _} ->
            Req = shurbej_http_common:auth_error_response(Reason, Req0),
            {ok, Req, State}
    end.

perm_for_method(<<"GET">>) -> read;
perm_for_method(<<"HEAD">>) -> read;
perm_for_method(_) -> write.

handle(<<"GET">>, Req0, State) ->
    LibRef = shurbej_http_common:lib_ref(Req0),
    Since = shurbej_http_common:get_since(Req0),
    {ok, LibVersion} = shurbej_version:get(LibRef),
    case shurbej_http_common:get_if_modified(Req0) of
        V when is_integer(V), V >= LibVersion ->
            Req = cowboy_req:reply(304, #{
                <<"last-modified-version">> => integer_to_binary(LibVersion)
            }, Req0),
            {ok, Req, State};
        _ ->
            Searches0 = shurbej_db:list_searches(LibRef, Since),
            Searches = shurbej_http_common:filter_by_keys(Searches0,
                shurbej_http_common:get_search_keys(Req0)),
            Format = shurbej_http_common:get_format(Req0),
            case Format of
                <<"versions">> ->
                    Pairs = shurbej_db:list_search_versions(LibRef, Since),
                    Req = shurbej_http_common:json_response(200, maps:from_list(Pairs), LibVersion, Req0),
                    {ok, Req, State};
                <<"keys">> ->
                    Keys = [K || #shurbej_search{id = {_, _, K}} <- Searches],
                    Req = shurbej_http_common:json_response(200, Keys, LibVersion, Req0),
                    {ok, Req, State};
                _ ->
                    Req = shurbej_http_common:list_response(Req0, Searches, LibVersion,
                        fun(S) -> shurbej_http_common:envelope_search(LibRef, S) end),
                    {ok, Req, State}
            end
    end;

%% PUT/PATCH single search
handle(Method, Req0, #{scope := single} = State) when Method =:= <<"PUT">>; Method =:= <<"PATCH">> ->
    {LT, LI} = LibRef = shurbej_http_common:lib_ref(Req0),
    SearchKey = cowboy_req:binding(search_key, Req0),
    ExpectedVersion = shurbej_http_common:get_if_unmodified(Req0),
    case shurbej_http_common:read_json_body(Req0) of
        {error, _, Req1} ->
            Req = shurbej_http_common:error_response(400, <<"Invalid JSON">>, Req1),
            {ok, Req, State};
        {ok, Incoming, Req1} ->
    case shurbej_db:get_search(LibRef, SearchKey) of
        undefined ->
            Req = shurbej_http_common:error_response(404, <<"Search not found">>, Req1),
            {ok, Req, State};
        {ok, #shurbej_search{data = Existing}} ->
            Merged = case Method of
                <<"PATCH">> -> maps:merge(Existing, Incoming);
                <<"PUT">> -> Incoming
            end,
            Search = Merged#{<<"key">> => SearchKey},
            case shurbej_validate:search(Search) of
                {error, Reason} ->
                    Req = shurbej_http_common:error_response(400, Reason, Req1),
                    {ok, Req, State};
                ok ->
                    case shurbej_version:write(LibRef, ExpectedVersion, fun(NewVersion) ->
                        FullData = Search#{<<"version">> => NewVersion},
                        shurbej_db:write_search(#shurbej_search{
                            id = {LT, LI, SearchKey}, version = NewVersion,
                            data = FullData, deleted = false
                        })
                    end) of
                        {ok, NewVersion} ->
                            FullData = Search#{<<"version">> => NewVersion, <<"key">> => SearchKey},
                            Updated = #shurbej_search{
                                id = {LT, LI, SearchKey}, version = NewVersion,
                                data = FullData, deleted = false
                            },
                            Envelope = shurbej_http_common:envelope_search(LibRef, Updated),
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

handle(<<"POST">>, Req0, State) ->
    {LT, LI} = LibRef = shurbej_http_common:lib_ref(Req0),
    ExpectedVersion = shurbej_http_common:get_if_unmodified(Req0),
    case shurbej_http_common:read_json_body(Req0) of
        {error, _, Req1} ->
            Req = shurbej_http_common:error_response(400, <<"Invalid JSON">>, Req1),
            {ok, Req, State};
        {ok, Searches, Req1} when is_list(Searches) ->
    KeyedSearches = [ensure_key(S) || S <- Searches],
    {Valid, Failed} = shurbej_http_items:validate_each(KeyedSearches, fun shurbej_validate:search/1),
    case Valid of
        [] when map_size(Failed) > 0 ->
            Result = #{<<"successful">> => #{}, <<"unchanged">> => #{}, <<"failed">> => Failed},
            Req = shurbej_http_common:json_response(400, Result, Req1),
            {ok, Req, State};
        _ ->
            case shurbej_version:write(LibRef, ExpectedVersion, fun(NewVersion) ->
                lists:foreach(fun({_Idx, S}) ->
                    Key = maps:get(<<"key">>, S),
                    FullData = S#{<<"key">> => Key, <<"version">> => NewVersion},
                    shurbej_db:write_search(#shurbej_search{
                        id = {LT, LI, Key},
                        version = NewVersion,
                        data = FullData,
                        deleted = false
                    })
                end, Valid),
                ok
            end) of
                {ok, NewVersion} ->
                    Successful = maps:from_list(
                        [{integer_to_binary(Idx), shurbej_http_items:envelope_for_write(LibRef, S, NewVersion)}
                         || {Idx, S} <- Valid]),
                    Result = #{
                        <<"successful">> => Successful,
                        <<"unchanged">> => #{},
                        <<"failed">> => Failed
                    },
                    Req = shurbej_http_common:json_response(200, Result, NewVersion, Req1),
                    {ok, Req, State};
                {error, precondition, CurrentVersion} ->
                    Req = shurbej_http_common:json_response(412,
                        #{<<"message">> => <<"Library has been modified since specified version">>},
                        CurrentVersion, Req1),
                    {ok, Req, State}
            end
    end;
        {ok, _, Req1} ->
            Req = shurbej_http_common:error_response(400, <<"Body must be a JSON array">>, Req1),
            {ok, Req, State}
    end;

handle(<<"DELETE">>, Req0, State) ->
    LibRef = shurbej_http_common:lib_ref(Req0),
    ExpectedVersion = shurbej_http_common:get_if_unmodified(Req0),
    #{searchKey := KeysParam} = cowboy_req:match_qs([{searchKey, [], <<>>}], Req0),
    Keys = [K || K <- binary:split(KeysParam, <<",">>, [global]), K =/= <<>>],
    case Keys of
        [] ->
            Req = shurbej_http_common:error_response(400,
                <<"No search keys specified">>, Req0),
            {ok, Req, State};
        _ ->
            case shurbej_version:write(LibRef, ExpectedVersion, fun(NewVersion) ->
                lists:foreach(fun(K) ->
                    shurbej_db:mark_search_deleted(LibRef, K, NewVersion),
                    shurbej_db:record_deletion(LibRef, <<"search">>, K, NewVersion)
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

ensure_key(Item) ->
    case maps:get(<<"key">>, Item, undefined) of
        undefined -> Item#{<<"key">> => shurbej_http_items:generate_key()};
        _ -> Item
    end.
