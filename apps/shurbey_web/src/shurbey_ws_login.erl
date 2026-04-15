-module(shurbey_ws_login).

%% Cowboy WebSocket handler for login session notifications.
%% The Zotero client connects to this to get instant loginComplete events.

-export([init/2, websocket_init/1, websocket_handle/2, websocket_info/2, terminate/3]).

init(Req, State) ->
    {cowboy_websocket, Req, State, #{idle_timeout => 600000}}.

websocket_init(State) ->
    {ok, State}.

%% Handle incoming messages from the client.
websocket_handle({text, Msg}, State) ->
    case catch simdjson:decode(Msg) of
        #{<<"action">> := <<"subscribe">>, <<"topic">> := <<"login-session:", Token/binary>>} ->
            shurbey_session:subscribe(Token, self()),
            Reply = simdjson:encode(#{
                <<"event">> => <<"subscribed">>,
                <<"topic">> => <<"login-session:", Token/binary>>
            }),
            {reply, {text, Reply}, State#{token => Token}};
        _ ->
            {ok, State}
    end;
websocket_handle(_Frame, State) ->
    {ok, State}.

%% Handle messages from the session manager.
websocket_info({session_event, {login_complete, ApiKey, UserInfo}}, State) ->
    #{user_id := UserId, username := Username} = UserInfo,
    Reply = simdjson:encode(#{
        <<"event">> => <<"loginComplete">>,
        <<"apiKey">> => ApiKey,
        <<"userID">> => UserId,
        <<"username">> => Username,
        <<"displayName">> => maps:get(display_name, UserInfo, Username)
    }),
    {reply, {text, Reply}, State};

websocket_info({session_event, login_cancelled}, State) ->
    Reply = simdjson:encode(#{<<"event">> => <<"loginCancelled">>}),
    {reply, {text, Reply}, State};

websocket_info(_Info, State) ->
    {ok, State}.

terminate(_Reason, _Req, _State) ->
    ok.
