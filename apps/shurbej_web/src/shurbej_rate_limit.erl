-module(shurbej_rate_limit).
-behaviour(gen_server).

-export([start_link/0, check/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-define(TABLE, shurbej_api_rate).
-define(CLEANUP_INTERVAL, 60000).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% Check rate limit for a user. Direct ETS access (no gen_server bottleneck).
%% Returns:
%%   ok                              — under soft threshold, no hint
%%   {backoff, Secs}                 — past soft threshold, advise client to pause
%%   {error, rate_limited, Retry}    — past hard limit, 429 with Retry-After
check(UserId) ->
    MaxReqs = application:get_env(shurbej, rate_limit_max, 1000),
    WindowSecs = application:get_env(shurbej, rate_limit_window, 60),
    SoftPct = application:get_env(shurbej, rate_limit_soft_pct, 80),
    Now = erlang:system_time(second),
    Window = Now div WindowSecs,
    Key = {UserId, Window},
    Count = try ets:update_counter(?TABLE, Key, {2, 1})
    catch error:badarg ->
        ets:insert_new(?TABLE, {Key, 0}),
        ets:update_counter(?TABLE, Key, {2, 1})
    end,
    RetryAfter = WindowSecs - (Now rem WindowSecs),
    SoftCount = (MaxReqs * SoftPct) div 100,
    if
        Count > MaxReqs ->
            {error, rate_limited, RetryAfter};
        Count > SoftCount ->
            {backoff, backoff_secs(Count, SoftCount, MaxReqs, WindowSecs)};
        true ->
            ok
    end.

%% Linear backoff from 1s at soft threshold to half the window at the hard limit.
backoff_secs(Count, Soft, Hard, WindowSecs) when Hard > Soft ->
    MaxBackoff = max(1, WindowSecs div 2),
    Step = max(1, ((Count - Soft) * MaxBackoff) div max(1, Hard - Soft)),
    min(MaxBackoff, Step);
backoff_secs(_, _, _, WindowSecs) ->
    max(1, WindowSecs div 2).

init([]) ->
    ets:new(?TABLE, [named_table, public, set, {write_concurrency, true}]),
    erlang:send_after(?CLEANUP_INTERVAL, self(), cleanup),
    {ok, #{}}.

handle_call(_Msg, _From, State) -> {reply, ok, State}.
handle_cast(_Msg, State) -> {noreply, State}.

handle_info(cleanup, State) ->
    WindowSecs = application:get_env(shurbej, rate_limit_window, 60),
    Now = erlang:system_time(second),
    CurrentWindow = Now div WindowSecs,
    ets:select_delete(?TABLE, [{{{'_', '$1'}, '_'}, [{'<', '$1', CurrentWindow}], [true]}]),
    erlang:send_after(?CLEANUP_INTERVAL, self(), cleanup),
    {noreply, State};
handle_info(_Msg, State) ->
    {noreply, State}.
