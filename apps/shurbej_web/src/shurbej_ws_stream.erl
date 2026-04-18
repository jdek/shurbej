-module(shurbej_ws_stream).

%% Zotero Streaming API — WebSocket handler.
%% Clients subscribe to library topics and receive topicUpdated events
%% when library versions change. Uses pg (process groups) for pub/sub.

-export([init/2, websocket_init/1, websocket_handle/2, websocket_info/2, terminate/3]).

-define(SCOPE, shurbej_stream).
-define(RETRY_MS, 10000).
-define(PING_INTERVAL, 25000).

init(Req, State) ->
    ApiKey = shurbej_http_common:extract_api_key(Req),
    {cowboy_websocket, Req, State#{api_key => ApiKey}, #{
        idle_timeout => 120000,
        max_frame_size => 1048576
    }}.

websocket_init(#{api_key := ApiKey} = State) ->
    erlang:send_after(?PING_INTERVAL, self(), keepalive),
    case ApiKey of
        undefined ->
            %% Multi-key connection — no auto-subscribe
            Reply = simdjson:encode(#{<<"event">> => <<"connected">>, <<"retry">> => ?RETRY_MS}),
            {reply, {text, Reply}, State#{subscriptions => #{}, single_key => false}};
        Key ->
            %% Single-key connection — auto-subscribe to user's library
            case shurbej_auth:verify(Key) of
                {ok, UserId} ->
                    Topic = user_topic(UserId),
                    pg:join(?SCOPE, Topic, self()),
                    Reply = simdjson:encode(#{
                        <<"event">> => <<"connected">>,
                        <<"retry">> => ?RETRY_MS,
                        <<"topics">> => [Topic]
                    }),
                    {reply, {text, Reply},
                     State#{subscriptions => #{Key => [Topic]}, single_key => true}};
                {error, _} ->
                    {reply, {close, 4403, <<"Forbidden">>}, State}
            end
    end.

%% Client messages
websocket_handle({text, Msg}, State) ->
    case catch simdjson:decode(Msg) of
        #{<<"action">> := Action} = Payload ->
            handle_action(Action, Payload, State);
        _ ->
            {reply, {close, 4400, <<"Bad request">>}, State}
    end;
websocket_handle(_Frame, State) ->
    {ok, State}.

%% Topic updates from pg
websocket_info({topic_updated, Topic, Version}, State) ->
    Reply = simdjson:encode(#{
        <<"event">> => <<"topicUpdated">>,
        <<"topic">> => Topic,
        <<"version">> => Version
    }),
    {reply, {text, Reply}, State};

websocket_info(keepalive, State) ->
    erlang:send_after(?PING_INTERVAL, self(), keepalive),
    {reply, {ping, <<>>}, State};

websocket_info(_Info, State) ->
    {ok, State}.

terminate(_Reason, _Req, _State) ->
    %% pg auto-removes the pid from all groups on process exit
    ok.

%% ===================================================================
%% Actions
%% ===================================================================

handle_action(<<"createSubscriptions">>, #{<<"subscriptions">> := Subs}, State)
        when is_list(Subs) ->
    case maps:get(single_key, State, false) of
        true ->
            {reply, {close, 4405, <<"Single-key connection cannot be modified">>}, State};
        false ->
            {ResultSubs, Errors, NewState} = process_creates(Subs, State),
            Reply = simdjson:encode(#{
                <<"event">> => <<"subscriptionsCreated">>,
                <<"subscriptions">> => ResultSubs,
                <<"errors">> => Errors
            }),
            {reply, {text, Reply}, NewState}
    end;

handle_action(<<"deleteSubscriptions">>, #{<<"subscriptions">> := Subs}, State)
        when is_list(Subs) ->
    case maps:get(single_key, State, false) of
        true ->
            {reply, {close, 4405, <<"Single-key connection cannot be modified">>}, State};
        false ->
            NewState = process_deletes(Subs, State),
            Reply = simdjson:encode(#{
                <<"event">> => <<"subscriptionsDeleted">>
            }),
            {reply, {text, Reply}, NewState}
    end;

handle_action(_, _, State) ->
    {reply, {close, 4400, <<"Unknown action">>}, State}.

%% ===================================================================
%% Subscription management
%% ===================================================================

process_creates(Subs, State) ->
    lists:foldl(fun(Sub, {AccSubs, AccErrs, AccState}) ->
        Key = maps:get(<<"apiKey">>, Sub, undefined),
        ReqTopics = maps:get(<<"topics">>, Sub, undefined),
        case Key of
            undefined ->
                {AccSubs, AccErrs, AccState};
            _ ->
                case shurbej_auth:verify(Key) of
                    {ok, UserId} ->
                        Allowed = [user_topic(UserId)],
                        Topics = case ReqTopics of
                            undefined -> Allowed;
                            T when is_list(T) ->
                                [Topic || Topic <- T, lists:member(Topic, Allowed)]
                        end,
                        lists:foreach(fun(Topic) ->
                            pg:join(?SCOPE, Topic, self())
                        end, Topics),
                        SubsMap = maps:get(subscriptions, AccState, #{}),
                        Existing = maps:get(Key, SubsMap, []),
                        Merged = lists:usort(Existing ++ Topics),
                        NewSubsMap = SubsMap#{Key => Merged},
                        Entry = #{<<"apiKey">> => Key, <<"topics">> => Merged},
                        {[Entry | AccSubs], AccErrs,
                         AccState#{subscriptions => NewSubsMap}};
                    {error, _} ->
                        Err = #{<<"apiKey">> => Key,
                                <<"error">> => <<"Invalid API key">>},
                        {AccSubs, [Err | AccErrs], AccState}
                end
        end
    end, {[], [], State}, Subs).

process_deletes(Subs, State) ->
    lists:foldl(fun(Sub, AccState) ->
        Key = maps:get(<<"apiKey">>, Sub, undefined),
        Topic = maps:get(<<"topic">>, Sub, undefined),
        SubsMap = maps:get(subscriptions, AccState, #{}),
        case Key of
            undefined -> AccState;
            _ ->
                OldTopics = maps:get(Key, SubsMap, []),
                ToRemove = case Topic of
                    undefined -> OldTopics;
                    T -> [T]
                end,
                lists:foreach(fun(T) ->
                    pg:leave(?SCOPE, T, self())
                end, ToRemove),
                NewTopics = OldTopics -- ToRemove,
                NewSubsMap = case NewTopics of
                    [] -> maps:remove(Key, SubsMap);
                    _ -> SubsMap#{Key => NewTopics}
                end,
                AccState#{subscriptions => NewSubsMap}
        end
    end, State, Subs).

%% ===================================================================
%% Internal
%% ===================================================================

user_topic(UserId) ->
    <<"/users/", (integer_to_binary(UserId))/binary>>.
