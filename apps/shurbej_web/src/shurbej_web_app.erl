-module(shurbej_web_app).
-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    Dispatch = cowboy_router:compile([
        {'_', shurbej_http:routes()}
    ]),
    Port = application:get_env(shurbej, http_port, 8080),
    {ok, _} = cowboy:start_clear(
        shurbej_http,
        [{port, Port}],
        #{env => #{dispatch => Dispatch}}
    ),
    logger:notice("shurbej listening on port ~p", [Port]),
    shurbej_web_sup:start_link().

stop(_State) ->
    cowboy:stop_listener(shurbej_http),
    ok.
