-module(shurbej_session_cleaner).
-behaviour(gen_server).

%% Periodically cleans up expired login sessions and orphaned uploads.

-export([start_link/0, init/1, handle_call/3, handle_cast/2, handle_info/2]).

-define(CLEANUP_INTERVAL, 60000). %% 1 minute
-define(SESSION_TTL_MS, 600000).  %% 10 minutes (must match shurbej_session)
-define(UPLOAD_TTL_MS, 3600000).  %% 1 hour for pending uploads

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    erlang:send_after(?CLEANUP_INTERVAL, self(), cleanup),
    {ok, #{}}.

handle_call(_Msg, _From, State) ->
    {reply, ok, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(cleanup, State) ->
    cleanup_sessions(),
    cleanup_uploads(),
    erlang:send_after(?CLEANUP_INTERVAL, self(), cleanup),
    {noreply, State};
handle_info(_Msg, State) ->
    {noreply, State}.

cleanup_sessions() ->
    shurbej_session:cleanup_expired().

cleanup_uploads() ->
    shurbej_files:cleanup_expired_uploads().
