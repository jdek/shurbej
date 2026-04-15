-module(shurbey_web_app).
-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    %% Start pg scope for streaming pub/sub
    pg:start_link(shurbey_stream),
    Dispatch = cowboy_router:compile([
        {'_', shurbey_http:routes()}
    ]),
    Port = application:get_env(shurbey, http_port, 8080),
    {ok, _} = cowboy:start_clear(
        shurbey_http,
        [{port, Port}],
        #{env => #{dispatch => Dispatch}}
    ),
    logger:notice("shurbey listening on port ~p", [Port]),
    shurbey_web_sup:start_link().

stop(_State) ->
    cowboy:stop_listener(shurbey_http),
    ok.
