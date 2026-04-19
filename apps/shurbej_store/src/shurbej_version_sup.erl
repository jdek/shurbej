-module(shurbej_version_sup).
-behaviour(supervisor).

-export([start_link/0, start_child/1, terminate_child/1]).
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

start_child(LibraryId) ->
    supervisor:start_child(?MODULE, [LibraryId]).

%% Ask the supervisor to shut down the version server for LibRef (if any).
%% Safe no-op if no such child is running.
terminate_child(LibRef) ->
    case global:whereis_name({shurbej_version, LibRef}) of
        undefined -> ok;
        Pid -> supervisor:terminate_child(?MODULE, Pid)
    end.

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
