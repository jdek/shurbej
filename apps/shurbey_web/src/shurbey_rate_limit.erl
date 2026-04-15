-module(shurbey_rate_limit).
-behaviour(gen_server).

-export([start_link/0, check/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-define(TABLE, shurbey_api_rate).
-define(CLEANUP_INTERVAL, 60000).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% Check rate limit for a user. Direct ETS access (no gen_server bottleneck).
check(UserId) ->
    MaxReqs = application:get_env(shurbey, rate_limit_max, 1000),
    WindowSecs = application:get_env(shurbey, rate_limit_window, 60),
    Now = erlang:system_time(second),
    Window = Now div WindowSecs,
    Key = {UserId, Window},
    try ets:update_counter(?TABLE, Key, {2, 1}) of
        Count when Count > MaxReqs -> {error, rate_limited};
        _ -> ok
    catch
        error:badarg ->
            ets:insert_new(?TABLE, {Key, 1}),
            ok
    end.

init([]) ->
    ets:new(?TABLE, [named_table, public, set, {write_concurrency, true}]),
    erlang:send_after(?CLEANUP_INTERVAL, self(), cleanup),
    {ok, #{}}.

handle_call(_Msg, _From, State) -> {reply, ok, State}.
handle_cast(_Msg, State) -> {noreply, State}.

handle_info(cleanup, State) ->
    WindowSecs = application:get_env(shurbey, rate_limit_window, 60),
    Now = erlang:system_time(second),
    CurrentWindow = Now div WindowSecs,
    ets:select_delete(?TABLE, [{{{'_', '$1'}, '_'}, [{'<', '$1', CurrentWindow}], [true]}]),
    erlang:send_after(?CLEANUP_INTERVAL, self(), cleanup),
    {noreply, State};
handle_info(_Msg, State) ->
    {noreply, State}.
