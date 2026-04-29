-module(shurbej_http_auth).
-include_lib("shurbej_store/include/shurbej_records.hrl").

-export([init/2]).

%% POST /auth/login — JSON-based login for the web UI.
%% Accepts: {"username": "...", "password": "..."}
%% Returns: {"apiKey": "...", "userID": N, "username": "..."}
init(Req0, State) ->
    case cowboy_req:method(Req0) of
        <<"POST">> -> handle_login(Req0, State);
        _ ->
            Req = shurbej_http_common:error_response(405, <<"Method not allowed">>, Req0),
            {ok, Req, State}
    end.

handle_login(Req0, State) ->
    case shurbej_http_common:read_json_body(Req0) of
        {ok, #{<<"username">> := Username, <<"password">> := Password}, Req1} ->
            case shurbej_session:check_login_rate(Username) of
                {error, rate_limited} ->
                    Req = shurbej_http_common:error_response(429,
                        <<"Too many login attempts. Please wait a few minutes.">>, Req1),
                    {ok, Req, State};
                ok ->
                    case shurbej_db:authenticate_password(Username, Password) of
                        {ok, UserUuid} ->
                            {ok, #shurbej_user{user_id = UserId}} =
                                shurbej_db:get_user_by_uuid(UserUuid),
                            shurbej_session:record_login_success(Username),
                            ApiKey = generate_api_key(),
                            shurbej_db:create_key(ApiKey, UserUuid,
                                shurbej_http_common:normalize_perms(undefined)),
                            Body = #{
                                <<"apiKey">> => ApiKey,
                                <<"userID">> => UserId,
                                <<"username">> => Username
                            },
                            Req = shurbej_http_common:json_response(200, Body, Req1),
                            {ok, Req, State};
                        {error, invalid} ->
                            Req = shurbej_http_common:error_response(401,
                                <<"Invalid username or password">>, Req1),
                            {ok, Req, State}
                    end
            end;
        {ok, _, Req1} ->
            Req = shurbej_http_common:error_response(400,
                <<"Missing username or password">>, Req1),
            {ok, Req, State};
        {error, _Reason, Req1} ->
            Req = shurbej_http_common:error_response(400,
                <<"Invalid JSON">>, Req1),
            {ok, Req, State}
    end.

generate_api_key() ->
    binary:encode_hex(crypto:strong_rand_bytes(32), lowercase).
