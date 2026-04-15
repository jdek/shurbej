-module(shurbey_http_stub).
-export([init/2]).

%% Returns a static JSON body. Used for endpoints Zotero expects
%% but that aren't meaningful for a self-hosted server.
init(Req0, #{body := Body} = State) ->
    case cowboy_req:method(Req0) of
        <<"GET">> ->
            Req = shurbey_http_common:json_response(200, Body, Req0),
            {ok, Req, State};
        _ ->
            Req = shurbey_http_common:error_response(405, <<"Method not allowed">>, Req0),
            {ok, Req, State}
    end.
