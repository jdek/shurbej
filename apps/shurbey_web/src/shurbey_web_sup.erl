-module(shurbey_web_sup).
-behaviour(supervisor).

-export([start_link/0, init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    Children = [
        #{id => shurbey_rate_limit,
          start => {shurbey_rate_limit, start_link, []},
          type => worker},
        #{id => shurbey_session,
          start => {shurbey_session, start_link, []},
          type => worker},
        #{id => shurbey_write_token,
          start => {shurbey_write_token, start_link, []},
          type => worker},
        #{id => shurbey_session_cleaner,
          start => {shurbey_session_cleaner, start_link, []},
          type => worker}
    ],
    {ok, {#{strategy => one_for_one, intensity => 5, period => 10}, Children}}.
