-module(shurbej_http_spa).

-export([init/2]).

%% Catch-all handler: serves index.html for browser navigation,
%% returns JSON 404 for API-like requests.
init(Req0, State) ->
    case is_browser_navigation(Req0) of
        true ->
            serve_spa(Req0, State);
        false ->
            Req = shurbej_http_common:error_response(404, <<"Not found">>, Req0),
            {ok, Req, State}
    end.

serve_spa(Req0, State) ->
    case file:read_file(shurbej_http:web_dist_path("index.html")) of
        {ok, Body} ->
            Req = cowboy_req:reply(200,
                #{<<"content-type">> => <<"text/html; charset=utf-8">>},
                Body, Req0),
            {ok, Req, State};
        {error, _} ->
            Req = cowboy_req:reply(404,
                #{<<"content-type">> => <<"text/plain">>},
                <<"UI not built — run: cd web && npm run build">>, Req0),
            {ok, Req, State}
    end.

%% Only serve the SPA for GET requests that accept HTML (browser navigation).
is_browser_navigation(Req) ->
    case cowboy_req:method(Req) of
        <<"GET">> ->
            Accept = cowboy_req:header(<<"accept">>, Req, <<>>),
            binary:match(Accept, <<"text/html">>) =/= nomatch;
        _ ->
            false
    end.
