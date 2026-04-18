-module(shurbej_version_sup).
-behaviour(supervisor).

-export([start_link/0, start_child/1]).
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

start_child(LibraryId) ->
    supervisor:start_child(?MODULE, [LibraryId]).

init([]) ->
    SupFlags = #{
        strategy => simple_one_for_one,
        intensity => 5,
        period => 10
    },
    ChildSpec = #{
        id => shurbej_version,
        start => {shurbej_version, start_link, []},
        restart => transient,
        type => worker
    },
    {ok, {SupFlags, [ChildSpec]}}.
