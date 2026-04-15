-module(shurbey_session).
-behaviour(gen_server).

%% Login session manager — gen_server owning protected ETS tables.
%% All writes go through gen_server calls.

-export([
    start_link/0,
    create/0,
    get/1,
    complete/3,
    cancel/1,
    delete/1,
    subscribe/2,
    cleanup_expired/0,
    check_login_rate/1,
    record_login_failure/1,
    insert_raw/2
]).

-define(MAX_LOGIN_ATTEMPTS, 5).
-define(RATE_WINDOW_SECS, 300). %% 5 minutes

-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-define(TABLE, shurbey_login_sessions).
-define(SUBSCRIBERS, shurbey_login_subscribers).
-define(SESSION_TTL_MS, 600000). %% 10 minutes
-define(MAX_PENDING_SESSIONS, 100).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% Public API — reads are direct ETS lookups (safe on protected tables),
%% writes go through gen_server.

create() ->
    gen_server:call(?MODULE, create).

get(Token) ->
    %% Reads are safe from any process
    case ets:lookup(?TABLE, Token) of
        [{_, #{created := Created} = Session}] ->
            Now = erlang:system_time(millisecond),
            case Now - Created > ?SESSION_TTL_MS of
                true ->
                    %% Expired — delete via gen_server
                    gen_server:cast(?MODULE, {delete, Token}),
                    {error, expired};
                false ->
                    {ok, Session}
            end;
        [] ->
            {error, not_found}
    end.

complete(Token, ApiKey, UserInfo) ->
    gen_server:call(?MODULE, {complete, Token, ApiKey, UserInfo}).

cancel(Token) ->
    gen_server:call(?MODULE, {cancel, Token}).

delete(Token) ->
    gen_server:call(?MODULE, {delete, Token}).

subscribe(Token, Pid) ->
    gen_server:call(?MODULE, {subscribe, Token, Pid}).

cleanup_expired() ->
    gen_server:call(?MODULE, cleanup_expired).

%% Rate limiting for login attempts.
check_login_rate(Username) ->
    Key = {login_rate, Username},
    Now = erlang:system_time(second),
    case ets:lookup(?TABLE, Key) of
        [{_, Count, WindowStart}] when Now - WindowStart < ?RATE_WINDOW_SECS,
                                       Count >= ?MAX_LOGIN_ATTEMPTS ->
            {error, rate_limited};
        _ ->
            ok
    end.

record_login_failure(Username) ->
    gen_server:cast(?MODULE, {login_failure, Username}).

%% Insert a session with a specific timestamp (for testing expiry).
insert_raw(Token, Session) ->
    gen_server:call(?MODULE, {insert_raw, Token, Session}).

%% gen_server callbacks

init([]) ->
    ets:new(?TABLE, [named_table, protected, set]),
    ets:new(?SUBSCRIBERS, [named_table, protected, bag]),
    {ok, #{}}.

handle_call(create, _From, State) ->
    PendingCount = ets:info(?TABLE, size),
    case PendingCount >= ?MAX_PENDING_SESSIONS of
        true ->
            {reply, {error, too_many}, State};
        false ->
            Token = generate_token(),
            CsrfToken = generate_token(),
            BaseUrl = to_binary(application:get_env(shurbey, base_url, <<"http://localhost:8080">>)),
            LoginUrl = <<BaseUrl/binary, "/login?token=", Token/binary>>,
            ets:insert(?TABLE, {Token, #{
                status => pending,
                created => erlang:system_time(millisecond),
                login_url => LoginUrl,
                csrf_token => CsrfToken
            }}),
            {reply, {ok, Token, LoginUrl}, State}
    end;

handle_call({complete, Token, ApiKey, UserInfo}, _From, State) ->
    Result = case ets:lookup(?TABLE, Token) of
        [{_, #{status := pending} = Session}] ->
            Completed = Session#{
                status => completed,
                api_key => ApiKey,
                user_info => UserInfo
            },
            ets:insert(?TABLE, {Token, Completed}),
            do_notify(Token, {login_complete, ApiKey, UserInfo}),
            ok;
        _ ->
            {error, not_found}
    end,
    {reply, Result, State};

handle_call({cancel, Token}, _From, State) ->
    Result = case ets:lookup(?TABLE, Token) of
        [{_, _}] ->
            do_notify(Token, login_cancelled),
            ets:delete(?TABLE, Token),
            ok;
        [] ->
            {error, not_found}
    end,
    {reply, Result, State};

handle_call({delete, Token}, _From, State) ->
    ets:delete(?TABLE, Token),
    ets:delete(?SUBSCRIBERS, Token),
    {reply, ok, State};

handle_call({subscribe, Token, Pid}, _From, State) ->
    ets:insert(?SUBSCRIBERS, {Token, Pid}),
    {reply, ok, State};

handle_call(cleanup_expired, _From, State) ->
    Now = erlang:system_time(millisecond),
    Expired = ets:foldl(fun
        ({Token, #{created := Created}}, Acc) when Now - Created > ?SESSION_TTL_MS ->
            [Token | Acc];
        (_, Acc) ->
            %% Skip rate-limit entries (3-element tuples) and other non-session entries
            Acc
    end, [], ?TABLE),
    lists:foreach(fun(Token) ->
        ets:delete(?TABLE, Token),
        ets:delete(?SUBSCRIBERS, Token)
    end, Expired),
    {reply, ok, State};

handle_call({insert_raw, Token, Session}, _From, State) ->
    ets:insert(?TABLE, {Token, Session}),
    {reply, ok, State};

handle_call(_Msg, _From, State) ->
    {reply, {error, unknown}, State}.

handle_cast({delete, Token}, State) ->
    ets:delete(?TABLE, Token),
    ets:delete(?SUBSCRIBERS, Token),
    {noreply, State};

handle_cast({login_failure, Username}, State) ->
    Key = {login_rate, Username},
    Now = erlang:system_time(second),
    case ets:lookup(?TABLE, Key) of
        [{_, Count, WindowStart}] when Now - WindowStart < ?RATE_WINDOW_SECS ->
            ets:insert(?TABLE, {Key, Count + 1, WindowStart});
        _ ->
            ets:insert(?TABLE, {Key, 1, Now})
    end,
    {noreply, State};

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Msg, State) ->
    {noreply, State}.

%% Internal

do_notify(Token, Event) ->
    Subscribers = ets:lookup(?SUBSCRIBERS, Token),
    lists:foreach(fun({_, Pid}) ->
        Pid ! {session_event, Event}
    end, Subscribers),
    ets:delete(?SUBSCRIBERS, Token).

generate_token() ->
    Bytes = crypto:strong_rand_bytes(24),
    list_to_binary(lists:flatten(
        [io_lib:format("~2.16.0b", [B]) || <<B>> <= Bytes]
    )).

to_binary(B) when is_binary(B) -> B;
to_binary(L) when is_list(L) -> list_to_binary(L).
