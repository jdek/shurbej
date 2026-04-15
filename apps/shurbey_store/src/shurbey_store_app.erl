-module(shurbey_store_app).
-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    ok = shurbey_db_schema:ensure(),
    shurbey_store_sup:start_link().

stop(_State) ->
    ok.
