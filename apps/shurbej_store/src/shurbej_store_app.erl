-module(shurbej_store_app).
-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    ok = shurbej_db_schema:ensure(),
    shurbej_store_sup:start_link().

stop(_State) ->
    ok.
