-module(shurbey_http_fulltext).
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

needs_write(<<"PUT">>) -> true;
needs_write(_) -> false.

%% GET /users/:user_id/fulltext — list versions of all full-text entries
handle(<<"GET">>, Req0, #{scope := versions} = State) ->
    LibId = shurbey_http_common:library_id(Req0),
    {ok, LibVersion} = shurbey_version:get(LibId),
    case shurbey_http_common:check_304(Req0, LibVersion) of
        {304, Req} -> {ok, Req, State};
        continue ->
            Since = shurbey_http_common:get_since(Req0),
            Pairs = shurbey_db:list_fulltext_versions(LibId, Since),
            Req = shurbey_http_common:json_response(200, maps:from_list(Pairs), LibVersion, Req0),
            {ok, Req, State}
    end;

%% GET /users/:user_id/items/:item_key/fulltext
handle(<<"GET">>, Req0, #{scope := single} = State) ->
    LibId = shurbey_http_common:library_id(Req0),
    ItemKey = cowboy_req:binding(item_key, Req0),
    case shurbey_db:get_fulltext(LibId, ItemKey) of
        {ok, #shurbey_fulltext{content = Content, version = Version,
                               indexed_pages = IP, total_pages = TP,
                               indexed_chars = IC, total_chars = TC}} ->
            Body = #{
                <<"content">> => Content,
                <<"indexedPages">> => IP, <<"totalPages">> => TP,
                <<"indexedChars">> => IC, <<"totalChars">> => TC
            },
            Req = shurbey_http_common:json_response(200, Body, Version, Req0),
            {ok, Req, State};
        undefined ->
            Req = shurbey_http_common:error_response(404, <<"Full-text content not found">>, Req0),
            {ok, Req, State}
    end;

%% PUT /users/:user_id/items/:item_key/fulltext — with input validation
handle(<<"PUT">>, Req0, #{scope := single} = State) ->
    LibId = shurbey_http_common:library_id(Req0),
    ItemKey = cowboy_req:binding(item_key, Req0),
    ExpectedVersion = shurbey_http_common:get_if_unmodified(Req0),
    case shurbey_http_common:read_json_body(Req0) of
        {error, _, Req1} ->
            Req = shurbey_http_common:error_response(400, <<"Invalid JSON">>, Req1),
            {ok, Req, State};
        {ok, Data, Req1} ->
    case validate_fulltext(Data) of
        {error, Reason} ->
            Req = shurbey_http_common:error_response(400, Reason, Req1),
            {ok, Req, State};
        ok ->
            Content = maps:get(<<"content">>, Data, <<>>),
            case shurbey_version:write(LibId, ExpectedVersion, fun(NewVersion) ->
                shurbey_db:write_fulltext(#shurbey_fulltext{
                    id = {LibId, ItemKey},
                    version = NewVersion,
                    content = Content,
                    indexed_pages = to_int(maps:get(<<"indexedPages">>, Data, 0)),
                    total_pages = to_int(maps:get(<<"totalPages">>, Data, 0)),
                    indexed_chars = to_int(maps:get(<<"indexedChars">>, Data, 0)),
                    total_chars = to_int(maps:get(<<"totalChars">>, Data, 0))
                }),
                ok
            end) of
                {ok, NewVersion} ->
                    Req = cowboy_req:reply(204, #{
                        <<"last-modified-version">> => integer_to_binary(NewVersion)
                    }, Req1),
                    {ok, Req, State};
                {error, precondition, CurrentVersion} ->
                    Req = shurbey_http_common:json_response(412,
                        #{<<"message">> => <<"Library has been modified since specified version">>},
                        CurrentVersion, Req1),
                    {ok, Req, State}
            end
    end
    end;

handle(_, Req0, State) ->
    Req = shurbey_http_common:error_response(405, <<"Method not allowed">>, Req0),
    {ok, Req, State}.

validate_fulltext(Data) when is_map(Data) ->
    case maps:get(<<"content">>, Data, undefined) of
        undefined -> {error, <<"Missing required field: content">>};
        C when is_binary(C) -> ok;
        _ -> {error, <<"'content' must be a string">>}
    end;
validate_fulltext(_) ->
    {error, <<"Body must be a JSON object">>}.

to_int(V) when is_integer(V) -> V;
to_int(_) -> 0.
