-module(shurbej_http_groups).
-export([init/2]).

init(Req0, State) ->
    case cowboy_req:method(Req0) of
        <<"GET">> ->
            case shurbej_http_common:authorize(Req0) of
                {ok, _LibId, _} -> handle_get(Req0, State);
                {error, Reason, _} ->
                    Req = shurbej_http_common:auth_error_response(Reason, Req0),
                    {ok, Req, State}
            end;
        _ ->
            Req = shurbej_http_common:error_response(405, <<"Method not allowed">>, Req0),
            {ok, Req, State}
    end.

%% Single-user mode: no groups, return empty.
handle_get(Req0, State) ->
    LibId = shurbej_http_common:library_id(Req0),
    {ok, LibVersion} = shurbej_version:get(LibId),
    Format = shurbej_http_common:get_format(Req0),
    case Format of
        <<"versions">> ->
            Req = shurbej_http_common:json_response(200, #{}, LibVersion, Req0),
            {ok, Req, State};
        _ ->
            Req = shurbej_http_common:json_response(200, [], LibVersion, Req0),
            {ok, Req, State}
    end.
