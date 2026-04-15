-module(shurbey_http_auth).
-include_lib("shurbey_store/include/shurbey_records.hrl").

-export([init/2]).

%% POST /auth/login — JSON-based login for the web UI.
%% Accepts: {"username": "...", "password": "..."}
%% Returns: {"apiKey": "...", "userID": N, "username": "..."}
init(Req0, State) ->
    case cowboy_req:method(Req0) of
        <<"POST">> -> handle_login(Req0, State);
        _ ->
            Req = shurbey_http_common:error_response(405, <<"Method not allowed">>, Req0),
            {ok, Req, State}
    end.

handle_login(Req0, State) ->
    case shurbey_http_common:read_json_body(Req0) of
        {ok, #{<<"username">> := Username, <<"password">> := Password}, Req1} ->
            case shurbey_session:check_login_rate(Username) of
                {error, rate_limited} ->
                    Req = shurbey_http_common:error_response(429,
                        <<"Too many login attempts. Please wait a few minutes.">>, Req1),
                    {ok, Req, State};
                ok ->
                    case shurbey_db:authenticate_user(Username, Password) of
                        {ok, UserId} ->
                            ApiKey = generate_api_key(),
                            shurbey_db:create_key(ApiKey, UserId,
                                #{library => true, write => true,
                                  files => true, notes => true}),
                            Body = #{
                                <<"apiKey">> => ApiKey,
                                <<"userID">> => UserId,
                                <<"username">> => Username
                            },
                            Req = shurbey_http_common:json_response(200, Body, Req1),
                            {ok, Req, State};
                        {error, invalid} ->
                            shurbey_session:record_login_failure(Username),
                            Req = shurbey_http_common:error_response(401,
                                <<"Invalid username or password">>, Req1),
                            {ok, Req, State}
                    end
            end;
        {ok, _, Req1} ->
            Req = shurbey_http_common:error_response(400,
                <<"Missing username or password">>, Req1),
            {ok, Req, State};
        {error, _Reason, Req1} ->
            Req = shurbey_http_common:error_response(400,
                <<"Invalid JSON">>, Req1),
            {ok, Req, State}
    end.

generate_api_key() ->
    Bytes = crypto:strong_rand_bytes(32),
    list_to_binary(lists:flatten(
        [io_lib:format("~2.16.0b", [B]) || <<B>> <= Bytes]
    )).
