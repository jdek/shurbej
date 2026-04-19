-module(shurbej_web_sup).
-behaviour(supervisor).

-export([start_link/0, init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    Children = [
        %% pg scope for streaming pub/sub — first so subsequent workers can
        %% assume it exists. pg:start_link/1 starts the named scope process.
        #{id => shurbej_stream_pg,
          start => {pg, start_link, [shurbej_stream]},
          type => worker},
        #{id => shurbej_rate_limit,
          start => {shurbej_rate_limit, start_link, []},
          type => worker},
        #{id => shurbej_session,
          start => {shurbej_session, start_link, []},
          type => worker},
        #{id => shurbej_write_token,
          start => {shurbej_write_token, start_link, []},
          type => worker},
        #{id => shurbej_session_cleaner,
          start => {shurbej_session_cleaner, start_link, []},
          type => worker}
    ],
    {ok, {#{strategy => one_for_one, intensity => 5, period => 10}, Children}}.
