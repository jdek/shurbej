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
                    {ok, Version} = shurbej_version:get({user, UserId}),
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

%% GET /keys/:key — verify a specific API key. The caller must present the
%% same key (Zotero-Api-Key header) as the one in the URL; introspecting
%% another user's key is forbidden.
handle_get_by_key(Req0, State) ->
    UrlKey = cowboy_req:binding(key, Req0),
    case authenticated_key_matches(UrlKey, Req0) of
        {error, Code, Msg} ->
            Req = shurbej_http_common:error_response(Code, Msg, Req0),
            {ok, Req, State};
        ok ->
            {ok, #{user_id := UserId, permissions := RawPerms}} =
                shurbej_auth:key_info(UrlKey),
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
            {ok, Version} = shurbej_version:get({user, UserId}),
            Req = shurbej_http_common:json_response(200, Body, Version, Req0),
            {ok, Req, State}
    end.

%% DELETE /keys/:key — revoke a specific API key. Same ownership rule as GET.
handle_delete_by_key(Req0, State) ->
    UrlKey = cowboy_req:binding(key, Req0),
    case authenticated_key_matches(UrlKey, Req0) of
        {error, Code, Msg} ->
            Req = shurbej_http_common:error_response(Code, Msg, Req0),
            {ok, Req, State};
        ok ->
            shurbej_db:delete_key(UrlKey),
            Req = cowboy_req:reply(204, #{}, <<>>, Req0),
            {ok, Req, State}
    end.

%% Authorize /keys/:key operations. The caller's presented key must be valid
%% and identical to the URL key — introspection/deletion of another user's
%% key is refused.
authenticated_key_matches(UrlKey, Req) ->
    case shurbej_http_common:extract_api_key(Req) of
        undefined -> {error, 403, <<"Forbidden">>};
        PresentedKey ->
            case shurbej_auth:key_info(PresentedKey) of
                {error, invalid} -> {error, 403, <<"Invalid key">>};
                {ok, _} when PresentedKey =:= UrlKey -> ok;
                {ok, _} -> {error, 403, <<"Forbidden">>}
            end
    end.

%% POST /keys — create API key with credentials (Zotero-compatible)
%% Body: {"username": "...", "password": "...", "name": "...", "access": {...}}
%% `access` is optional; shape matches `format_access/1` output. When omitted,
%% the key gets full access on the user library + `groups.all` grants.
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
                                    shurbej_session:record_login_success(Username),
                                    Perms = parse_access_or_default(
                                        maps:get(<<"access">>, Body, undefined)),
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

%% Parse the body's "access" field (Zotero shape with binary keys) into the
%% canonical internal form. Missing or malformed → full access.
parse_access_or_default(undefined) ->
    shurbej_http_common:normalize_perms(undefined);
parse_access_or_default(Access) when is_map(Access) ->
    Parsed = #{
        user => parse_user_access(maps:get(<<"user">>, Access, #{})),
        groups => parse_groups_access(maps:get(<<"groups">>, Access, #{}))
    },
    shurbej_http_common:normalize_perms(Parsed);
parse_access_or_default(_) ->
    shurbej_http_common:normalize_perms(undefined).

parse_user_access(U) when is_map(U) ->
    #{
        library => bin_truthy(<<"library">>, U),
        write   => bin_truthy(<<"write">>, U),
        files   => bin_truthy(<<"files">>, U),
        notes   => bin_truthy(<<"notes">>, U)
    };
parse_user_access(_) ->
    #{library => false, write => false, files => false, notes => false}.

parse_groups_access(G) when is_map(G) ->
    maps:fold(fun(K, V, Acc) when is_map(V) ->
        Acc#{K => #{
            library => bin_truthy(<<"library">>, V),
            write   => bin_truthy(<<"write">>, V)
        }};
        (_, _, Acc) -> Acc
    end, #{}, G);
parse_groups_access(_) -> #{}.

bin_truthy(K, M) ->
    case maps:get(K, M, false) of
        true -> true;
        _ -> false
    end.

generate_api_key() ->
    Bytes = crypto:strong_rand_bytes(32),
    list_to_binary(lists:flatten(
        [io_lib:format("~2.16.0b", [B]) || <<B>> <= Bytes]
    )).

method_not_allowed(Req0, State) ->
    Req = shurbej_http_common:error_response(405, <<"Method not allowed">>, Req0),
    {ok, Req, State}.

%% Render stored permissions in the Zotero-compatible response shape. Stored
%% legacy flat forms (or `#{access := all}`) are upgraded first via
%% normalize_perms, then rendered.
format_access(Perms) ->
    Canon = shurbej_http_common:normalize_perms(Perms),
    #{
        <<"user">> => format_user_bucket(maps:get(user, Canon, #{})),
        <<"groups">> => format_groups_bucket(maps:get(groups, Canon, #{}))
    }.

format_user_bucket(U) when is_map(U) ->
    #{
        <<"library">> => maps:get(library, U, false),
        <<"write">>   => maps:get(write, U, false),
        <<"files">>   => maps:get(files, U, false),
        <<"notes">>   => maps:get(notes, U, false)
    };
format_user_bucket(_) ->
    #{<<"library">> => false, <<"write">> => false,
      <<"files">> => false, <<"notes">> => false}.

format_groups_bucket(G) when is_map(G) ->
    maps:fold(fun(K, V, Acc) ->
        Acc#{format_group_key(K) => #{
            <<"library">> => maps:get(library, V, false),
            <<"write">>   => maps:get(write, V, false)
        }}
    end, #{}, G);
format_groups_bucket(_) -> #{}.

format_group_key(all) -> <<"all">>;
format_group_key(N) when is_integer(N) -> integer_to_binary(N);
format_group_key(B) when is_binary(B) -> B.
