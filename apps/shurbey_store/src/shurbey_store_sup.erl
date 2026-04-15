-module(shurbey_store_sup).
-behaviour(supervisor).

-export([start_link/0, init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    SupFlags = #{
        strategy => one_for_one,
        intensity => 5,
        period => 10
    },
    Children = [
        #{
            id => shurbey_files,
            start => {shurbey_files, start_link, []},
            type => worker
        },
        #{
            id => shurbey_version_sup,
            start => {shurbey_version_sup, start_link, []},
            type => supervisor
        }
    ],
    {ok, {SupFlags, Children}}.
