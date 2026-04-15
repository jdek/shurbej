-module(shurbey_write_token).
-behaviour(gen_server).

%% Tracks Zotero-Write-Token headers for idempotent writes.
%% Tokens are kept for 12 hours then pruned.

-export([start_link/0, check/1, store/2, init/1, handle_call/3, handle_cast/2, handle_info/2]).

-define(TTL_MS, 43200000). %% 12 hours
-define(CLEANUP_INTERVAL, 3600000). %% 1 hour

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% Check if a write token has been seen before.
%% Returns new | {duplicate, StoredResponse}.
check(undefined) -> new;
check(Token) -> gen_server:call(?MODULE, {check, Token}).

%% Store a completed write token with its response for future dedup.
store(undefined, _Response) -> ok;
store(Token, Response) -> gen_server:call(?MODULE, {store, Token, Response}).

init([]) ->
    Table = ets:new(shurbey_write_tokens, [set, protected]),
    erlang:send_after(?CLEANUP_INTERVAL, self(), cleanup),
    {ok, #{table => Table}}.

handle_call({check, Token}, _From, #{table := Table} = State) ->
    case ets:lookup(Table, Token) of
        [{_, {complete, StoredResponse}, _}] ->
            {reply, {duplicate, StoredResponse}, State};
        [{_, in_progress, _}] ->
            {reply, in_progress, State};
        [] ->
            ets:insert(Table, {Token, in_progress, erlang:system_time(millisecond)}),
            {reply, new, State}
    end;

handle_call({store, Token, Response}, _From, #{table := Table} = State) ->
    ets:insert(Table, {Token, {complete, Response}, erlang:system_time(millisecond)}),
    {reply, ok, State};

handle_call(_Msg, _From, State) ->
    {reply, {error, unknown}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(cleanup, #{table := Table} = State) ->
    Cutoff = erlang:system_time(millisecond) - ?TTL_MS,
    ets:select_delete(Table, [{{'_', '_', '$1'}, [{'<', '$1', Cutoff}], [true]}]),
    erlang:send_after(?CLEANUP_INTERVAL, self(), cleanup),
    {noreply, State};
handle_info(_Msg, State) ->
    {noreply, State}.
