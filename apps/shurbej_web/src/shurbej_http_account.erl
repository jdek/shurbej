-module(shurbej_http_account).
-include_lib("shurbej_store/include/shurbej_records.hrl").

-export([init/2]).

%% GET  /account — return the authenticated user's profile.
%% POST /account — update one or more profile fields. Body shape:
%%   {"userID": <int>, "username": <bin>, "displayName": <bin>}
%% Each field is optional; missing fields are left untouched.
%%
%% NOTE: changing userID will cause any already-paired Zotero client to hit
%% the account-switch wipe dialog on its next /keys/current call (the client
%% compares the cached integer label against the freshly returned one). The
%% client's UX, not our problem — but document it on whatever surface lets
%% the user perform this change.
init(Req0, State) ->
    case shurbej_http_common:authenticate(Req0) of
        {ok, UserUuid, Req1} ->
            case cowboy_req:method(Req1) of
                <<"GET">>  -> handle_get(UserUuid, Req1, State);
                <<"POST">> -> handle_post(UserUuid, Req1, State);
                _ ->
                    Req = shurbej_http_common:error_response(
                        405, <<"Method not allowed">>, Req1),
                    {ok, Req, State}
            end;
        {error, Req1} ->
            Req = shurbej_http_common:error_response(403, <<"Forbidden">>, Req1),
            {ok, Req, State}
    end.

handle_get(UserUuid, Req0, State) ->
    {ok, #shurbej_user{
        user_id = UserId, username = Username, display_name = Display}} =
        shurbej_db:get_user_by_uuid(UserUuid),
    Body = #{
        <<"userID">> => UserId,
        <<"username">> => Username,
        <<"displayName">> => display_or(Display, Username)
    },
    Req = shurbej_http_common:json_response(200, Body, Req0),
    {ok, Req, State}.

handle_post(UserUuid, Req0, State) ->
    case shurbej_http_common:read_json_body(Req0) of
        {ok, Body, Req1} when is_map(Body) ->
            case apply_updates(UserUuid, Body) of
                ok ->
                    handle_get(UserUuid, Req1, State);
                {error, {bad_field, F}} ->
                    Req = shurbej_http_common:error_response(
                        400, <<"Invalid value for ", F/binary>>, Req1),
                    {ok, Req, State}
            end;
        {ok, _, Req1} ->
            Req = shurbej_http_common:error_response(400, <<"Expected JSON object">>, Req1),
            {ok, Req, State};
        {error, _, Req1} ->
            Req = shurbej_http_common:error_response(400, <<"Invalid JSON">>, Req1),
            {ok, Req, State}
    end.

%% Apply only the fields actually present in the body. Each field is
%% validated; if any is malformed the whole batch is rejected.
apply_updates(UserUuid, Body) ->
    Updates = [
        {<<"userID">>, fun is_non_neg_int/1, fun shurbej_db:set_user_id/2},
        {<<"username">>, fun is_non_empty_binary/1, fun shurbej_db:set_username/2},
        {<<"displayName">>, fun is_binary/1, fun shurbej_db:set_display_name/2}
    ],
    apply_updates_1(UserUuid, Body, Updates).

apply_updates_1(_UserUuid, _Body, []) -> ok;
apply_updates_1(UserUuid, Body, [{Field, Validate, Apply} | Rest]) ->
    case maps:find(Field, Body) of
        error -> apply_updates_1(UserUuid, Body, Rest);
        {ok, Value} ->
            case Validate(Value) of
                true ->
                    Apply(UserUuid, Value),
                    apply_updates_1(UserUuid, Body, Rest);
                false ->
                    {error, {bad_field, Field}}
            end
    end.

is_non_neg_int(V) -> is_integer(V) andalso V >= 0.
is_non_empty_binary(V) -> is_binary(V) andalso byte_size(V) > 0.

display_or(undefined, Fallback) -> Fallback;
display_or(<<>>, Fallback) -> Fallback;
display_or(Display, _) -> Display.
