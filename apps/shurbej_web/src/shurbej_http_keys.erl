-module(shurbej_http_keys).
-include_lib("shurbej_store/include/shurbej_records.hrl").

-export([init/2]).

init(Req0, #{action := create_key} = State) ->
    case cowboy_req:method(Req0) of
        <<"POST">> -> handle_create_key(Req0, State);
        _ -> method_not_allowed(Req0, State)
    end;

init(Req0, #{action := current} = State) ->
    case cowboy_req:method(Req0) of
        <<"GET">>    -> handle_get_current(Req0, State);
        <<"DELETE">> -> handle_delete_current(Req0, State);
        _ -> method_not_allowed(Req0, State)
    end;

init(Req0, #{action := sessions} = State) ->
    case cowboy_req:method(Req0) of
        <<"POST">> -> handle_create_session(Req0, State);
        _ -> method_not_allowed(Req0, State)
    end;

init(Req0, #{action := session} = State) ->
    case cowboy_req:method(Req0) of
        <<"GET">>    -> handle_get_session(Req0, State);
        <<"DELETE">> -> handle_cancel_session(Req0, State);
        _ -> method_not_allowed(Req0, State)
    end;

init(Req0, #{action := by_key} = State) ->
    case cowboy_req:method(Req0) of
        <<"GET">>    -> handle_get_by_key(Req0, State);
        <<"DELETE">> -> handle_delete_by_key(Req0, State);
        _ -> method_not_allowed(Req0, State)
    end;

init(Req0, State) ->
    Req = shurbej_http_common:error_response(404, <<"Not found">>, Req0),
    {ok, Req, State}.

%% GET /keys/current — verify API key, return user info
handle_get_current(Req0, State) ->
    case shurbej_http_common:extract_api_key(Req0) of
        undefined ->
            Req = shurbej_http_common:error_response(403, <<"Forbidden">>, Req0),
            {ok, Req, State};
        Key ->
            case shurbej_auth:key_info(Key) of
                {ok, #{user_id := UserId, permissions := RawPerms}} ->
                    Username = case shurbej_db:get_user_by_id(UserId) of
                        {ok, #shurbej_user{username = U}} -> U;
                        undefined -> <<"unknown">>
                    end,
                    Body = #{
                        <<"userID">> => UserId,
                        <<"username">> => Username,
                        <<"displayName">> => Username,
                        <<"access">> => format_access(RawPerms)
                    },
                    {ok, Version} = shurbej_version:get(UserId),
                    Req = shurbej_http_common:json_response(200, Body, Version, Req0),
                    {ok, Req, State};
                {error, invalid} ->
                    Req = shurbej_http_common:error_response(403, <<"Invalid key">>, Req0),
                    {ok, Req, State}
            end
    end.

%% DELETE /keys/current — revoke API key
handle_delete_current(Req0, State) ->
    case shurbej_http_common:extract_api_key(Req0) of
        undefined ->
            Req = shurbej_http_common:error_response(403, <<"Forbidden">>, Req0),
            {ok, Req, State};
        Key ->
            shurbej_db:delete_key(Key),
            Req = cowboy_req:reply(204, #{}, <<>>, Req0),
            {ok, Req, State}
    end.

%% POST /keys/sessions — create a login session
handle_create_session(Req0, State) ->
    case shurbej_session:create() of
        {ok, Token, LoginUrl} ->
            Body = #{
                <<"sessionToken">> => Token,
                <<"loginURL">> => LoginUrl
            },
            Req = shurbej_http_common:json_response(201, Body, Req0),
            {ok, Req, State};
        {error, too_many} ->
            Req = shurbej_http_common:error_response(429,
                <<"Too many pending sessions. Try again later.">>, Req0),
            {ok, Req, State}
    end.

%% GET /keys/sessions/:token — poll session status
handle_get_session(Req0, State) ->
    Token = cowboy_req:binding(token, Req0),
    case shurbej_session:get(Token) of
        {ok, #{status := pending}} ->
            Req = shurbej_http_common:json_response(200, #{<<"status">> => <<"pending">>}, Req0),
            {ok, Req, State};
        {ok, #{status := completed, api_key := ApiKey, user_info := UserInfo}} ->
            #{user_id := UserId, username := Username} = UserInfo,
            DisplayName = maps:get(display_name, UserInfo, Username),
            Body = #{
                <<"status">> => <<"completed">>,
                <<"apiKey">> => ApiKey,
                <<"userID">> => UserId,
                <<"username">> => Username,
                <<"displayName">> => DisplayName
            },
            Req = shurbej_http_common:json_response(200, Body, Req0),
            shurbej_session:delete(Token),
            {ok, Req, State};
        {error, expired} ->
            Req = shurbej_http_common:json_response(410,
                #{<<"status">> => <<"expired">>}, Req0),
            {ok, Req, State};
        {error, not_found} ->
            Req = shurbej_http_common:error_response(404, <<"Session not found">>, Req0),
            {ok, Req, State}
    end.

%% DELETE /keys/sessions/:token — cancel session
handle_cancel_session(Req0, State) ->
    Token = cowboy_req:binding(token, Req0),
    case shurbej_session:cancel(Token) of
        ok ->
            Req = cowboy_req:reply(204, #{}, <<>>, Req0),
            {ok, Req, State};
        {error, not_found} ->
            Req = shurbej_http_common:error_response(404, <<"Session not found">>, Req0),
            {ok, Req, State}
    end.

%% GET /keys/:key — verify a specific API key (Zotero-compatible)
handle_get_by_key(Req0, State) ->
    UrlKey = cowboy_req:binding(key, Req0),
    case shurbej_auth:key_info(UrlKey) of
        {ok, #{user_id := UserId, permissions := RawPerms}} ->
            Username = case shurbej_db:get_user_by_id(UserId) of
                {ok, #shurbej_user{username = U}} -> U;
                undefined -> <<"unknown">>
            end,
            Body = #{
                <<"key">> => UrlKey,
                <<"userID">> => UserId,
                <<"username">> => Username,
                <<"displayName">> => Username,
                <<"access">> => format_access(RawPerms)
            },
            {ok, Version} = shurbej_version:get(UserId),
            Req = shurbej_http_common:json_response(200, Body, Version, Req0),
            {ok, Req, State};
        {error, invalid} ->
            Req = shurbej_http_common:error_response(403, <<"Invalid key">>, Req0),
            {ok, Req, State}
    end.

%% DELETE /keys/:key — revoke a specific API key
handle_delete_by_key(Req0, State) ->
    UrlKey = cowboy_req:binding(key, Req0),
    shurbej_db:delete_key(UrlKey),
    Req = cowboy_req:reply(204, #{}, <<>>, Req0),
    {ok, Req, State}.

%% POST /keys — create API key with credentials (Zotero-compatible)
%% Body: {"username": "...", "password": "...", "name": "...", "access": {...}}
handle_create_key(Req0, State) ->
    case shurbej_http_common:read_json_body(Req0) of
        {ok, #{<<"username">> := Username, <<"password">> := Password} = Body, Req1} ->
            Name = maps:get(<<"name">>, Body, <<"API Key">>),
            case byte_size(Name) > 255 of
                true ->
                    Req = shurbej_http_common:error_response(400,
                        <<"Key name too long">>, Req1),
                    {ok, Req, State};
                false ->
                    case shurbej_session:check_login_rate(Username) of
                        {error, rate_limited} ->
                            Req = shurbej_http_common:error_response(429,
                                <<"Too many login attempts. Please wait a few minutes.">>, Req1),
                            {ok, Req, State};
                        ok ->
                            case shurbej_db:authenticate_user(Username, Password) of
                                {ok, UserId} ->
                                    Perms = #{library => true, write => true,
                                              files => true, notes => true},
                                    ApiKey = generate_api_key(),
                                    shurbej_db:create_key(ApiKey, UserId, Perms),
                                    RespBody = #{
                                        <<"key">> => ApiKey,
                                        <<"userID">> => UserId,
                                        <<"username">> => Username,
                                        <<"displayName">> => Username,
                                        <<"name">> => Name,
                                        <<"access">> => format_access(Perms)
                                    },
                                    Req = shurbej_http_common:json_response(201, RespBody, Req1),
                                    {ok, Req, State};
                                {error, invalid} ->
                                    shurbej_session:record_login_failure(Username),
                                    Req = shurbej_http_common:error_response(403,
                                        <<"Invalid username or password">>, Req1),
                                    {ok, Req, State}
                            end
                    end
            end;
        {ok, _, Req1} ->
            Req = shurbej_http_common:error_response(403,
                <<"Username and password required">>, Req1),
            {ok, Req, State};
        {error, _Reason, Req1} ->
            Req = shurbej_http_common:error_response(400,
                <<"Invalid JSON">>, Req1),
            {ok, Req, State}
    end.

generate_api_key() ->
    Bytes = crypto:strong_rand_bytes(32),
    list_to_binary(lists:flatten(
        [io_lib:format("~2.16.0b", [B]) || <<B>> <= Bytes]
    )).

method_not_allowed(Req0, State) ->
    Req = shurbej_http_common:error_response(405, <<"Method not allowed">>, Req0),
    {ok, Req, State}.

format_access(#{access := all}) ->
    format_access(#{library => true, write => true, files => true, notes => true});
format_access(Perms) when is_map(Perms) ->
    #{
        <<"user">> => #{
            <<"library">> => maps:get(library, Perms, false),
            <<"files">> => maps:get(files, Perms, false),
            <<"notes">> => maps:get(notes, Perms, false),
            <<"write">> => maps:get(write, Perms, false)
        },
        <<"groups">> => #{
            <<"all">> => #{
                <<"library">> => maps:get(library, Perms, false),
                <<"write">> => maps:get(write, Perms, false)
            }
        }
    };
format_access(_) ->
    format_access(#{library => true, write => true, files => true, notes => true}).
