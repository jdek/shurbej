-module(shurbej_http_deleted).
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

handle_get(Req0, State) ->
    LibId = shurbej_http_common:library_id(Req0),
    {ok, LibVersion} = shurbej_version:get(LibId),
    case shurbej_http_common:check_304(Req0, LibVersion) of
        {304, Req} -> {ok, Req, State};
        continue ->
            Since = shurbej_http_common:get_since(Req0),
            Result = #{
        <<"collections">> => shurbej_db:list_deleted(LibId, <<"collection">>, Since),
        <<"items">>       => shurbej_db:list_deleted(LibId, <<"item">>, Since),
        <<"searches">>    => shurbej_db:list_deleted(LibId, <<"search">>, Since),
        <<"tags">>        => shurbej_db:list_deleted(LibId, <<"tag">>, Since),
        <<"settings">>    => shurbej_db:list_deleted(LibId, <<"setting">>, Since)
    },

            Req = shurbej_http_common:json_response(200, Result, LibVersion, Req0),
            {ok, Req, State}
    end.
