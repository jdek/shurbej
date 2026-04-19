-module(shurbej_http_login).
-include_lib("shurbej_store/include/shurbej_records.hrl").

-export([init/2]).

-define(HTML_HEADERS, #{
    <<"content-type">> => <<"text/html; charset=utf-8">>,
    <<"x-frame-options">> => <<"DENY">>,
    <<"x-content-type-options">> => <<"nosniff">>,
    <<"content-security-policy">> =>
        <<"default-src 'none'; style-src 'unsafe-inline'; form-action 'self'">>
}).

%% GET /login?token=... — serve the HTML login form
%% POST /login — handle form submission
init(Req0, State) ->
    case cowboy_req:method(Req0) of
        <<"GET">>  -> handle_get(Req0, State);
        <<"POST">> -> handle_post(Req0, State);
        _ ->
            Req = shurbej_http_common:error_response(405, <<"Method not allowed">>, Req0),
            {ok, Req, State}
    end.

handle_get(Req0, State) ->
    #{token := Token} = cowboy_req:match_qs([{token, [], <<>>}], Req0),
    case shurbej_session:get(Token) of
        {ok, #{status := pending, csrf_token := Csrf}} ->
            Html = login_page(Token, Csrf, <<>>),
            Req = cowboy_req:reply(200, ?HTML_HEADERS,
                                  Html, Req0),
            {ok, Req, State};
        {ok, #{status := completed}} ->
            Req = cowboy_req:reply(200, ?HTML_HEADERS,
                                  success_page(), Req0),
            {ok, Req, State};
        _ ->
            Req = cowboy_req:reply(404, ?HTML_HEADERS,
                                  error_page(<<"Session not found or expired.">>), Req0),
            {ok, Req, State}
    end.

handle_post(Req0, State) ->
    {ok, Body, Req1} = cowboy_req:read_body(Req0, #{length => 4096}),
    Params = cow_qs:parse_qs(Body),
    Token = proplists:get_value(<<"token">>, Params, <<>>),
    Username = proplists:get_value(<<"username">>, Params, <<>>),
    Password = proplists:get_value(<<"password">>, Params, <<>>),
    CsrfParam = proplists:get_value(<<"csrf">>, Params, <<>>),
    case shurbej_session:get(Token) of
        {ok, #{status := pending, csrf_token := ExpectedCsrf}} ->
            %% Verify CSRF token
            case constant_time_compare(ExpectedCsrf, CsrfParam) of
                false ->
                    Html = login_page(Token, ExpectedCsrf, <<"Invalid request. Please try again.">>),
                    Req = cowboy_req:reply(403, ?HTML_HEADERS,
                                          Html, Req1),
                    {ok, Req, State};
                true ->
                    %% Check rate limiting
                    case shurbej_session:check_login_rate(Username) of
                        {error, rate_limited} ->
                            Html = login_page(Token, ExpectedCsrf,
                                <<"Too many login attempts. Please wait a few minutes.">>),
                            Req = cowboy_req:reply(429, ?HTML_HEADERS,
                                                  Html, Req1),
                            {ok, Req, State};
                        ok ->
                            case shurbej_db:authenticate_user(Username, Password) of
                                {ok, UserId} ->
                                    shurbej_session:record_login_success(Username),
                                    ApiKey = generate_api_key(),
                                    shurbej_db:create_key(ApiKey, UserId,
                                        shurbej_http_common:normalize_perms(undefined)),
                                    UserInfo = #{user_id => UserId, username => Username, display_name => Username},
                                    ok = shurbej_session:complete(Token, ApiKey, UserInfo),
                                    Req = cowboy_req:reply(200,
                                        ?HTML_HEADERS,
                                        success_page(), Req1),
                                    {ok, Req, State};
                                {error, invalid} ->
                                    Html = login_page(Token, ExpectedCsrf, <<"Invalid username or password.">>),
                                    Req = cowboy_req:reply(200,
                                        ?HTML_HEADERS,
                                        Html, Req1),
                                    {ok, Req, State}
                            end
                    end
            end;
        _ ->
            Req = cowboy_req:reply(404,
                ?HTML_HEADERS,
                error_page(<<"Session not found or expired.">>), Req1),
            {ok, Req, State}
    end.

%% Internal — key generation (256 bits)
generate_api_key() ->
    binary:encode_hex(crypto:strong_rand_bytes(32), lowercase).

%% HTML escaping to prevent XSS
html_escape(Bin) ->
    B1 = binary:replace(Bin, <<"&">>, <<"&amp;">>, [global]),
    B2 = binary:replace(B1, <<"<">>, <<"&lt;">>, [global]),
    B3 = binary:replace(B2, <<">">>, <<"&gt;">>, [global]),
    binary:replace(B3, <<"\"">>, <<"&quot;">>, [global]).

login_page(Token, CsrfToken, Error) ->
    ErrorHtml = case Error of
        <<>> -> <<>>;
        Msg -> <<"<p style=\"color:#c33;margin-bottom:16px\">", (html_escape(Msg))/binary, "</p>">>
    end,
    EscToken = html_escape(Token),
    EscCsrf = html_escape(CsrfToken),
    <<"<!DOCTYPE html>
<html>
<head>
<meta charset=\"utf-8\">
<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">
<title>Shurbej — Sign In</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:system-ui,sans-serif;display:flex;justify-content:center;
     align-items:center;min-height:100vh;background:#f5f5f5}
.card{background:#fff;border-radius:8px;padding:32px;width:360px;
      box-shadow:0 2px 8px rgba(0,0,0,.1)}
h1{font-size:20px;margin-bottom:24px;text-align:center}
label{display:block;font-size:14px;margin-bottom:4px;font-weight:500}
input[type=text],input[type=password]{width:100%;padding:8px 12px;
      border:1px solid #ccc;border-radius:4px;font-size:14px;margin-bottom:16px}
button{width:100%;padding:10px;background:#2563eb;color:#fff;border:none;
       border-radius:4px;font-size:14px;cursor:pointer}
button:hover{background:#1d4ed8}
</style>
</head>
<body>
<div class=\"card\">
<h1>Shurbej</h1>",
ErrorHtml/binary,
"<form method=\"POST\" action=\"/login\">
<input type=\"hidden\" name=\"token\" value=\"", EscToken/binary, "\">
<input type=\"hidden\" name=\"csrf\" value=\"", EscCsrf/binary, "\">
<label for=\"username\">Username</label>
<input type=\"text\" id=\"username\" name=\"username\" required autofocus>
<label for=\"password\">Password</label>
<input type=\"password\" id=\"password\" name=\"password\" required>
<button type=\"submit\">Sign In</button>
</form>
</div>
</body>
</html>">>.

success_page() ->
    <<"<!DOCTYPE html>
<html>
<head>
<meta charset=\"utf-8\">
<title>Shurbej — Signed In</title>
<style>
body{font-family:system-ui,sans-serif;display:flex;justify-content:center;
     align-items:center;min-height:100vh;background:#f5f5f5}
.card{background:#fff;border-radius:8px;padding:32px;width:360px;
      box-shadow:0 2px 8px rgba(0,0,0,.1);text-align:center}
h1{font-size:20px;margin-bottom:12px}
p{color:#666}
</style>
</head>
<body>
<div class=\"card\">
<h1>Signed in</h1>
<p>You can close this window and return to Zotero.</p>
</div>
</body>
</html>">>.

error_page(Message) ->
    <<"<!DOCTYPE html>
<html>
<head>
<meta charset=\"utf-8\">
<title>Shurbej — Error</title>
<style>
body{font-family:system-ui,sans-serif;display:flex;justify-content:center;
     align-items:center;min-height:100vh;background:#f5f5f5}
.card{background:#fff;border-radius:8px;padding:32px;width:360px;
      box-shadow:0 2px 8px rgba(0,0,0,.1);text-align:center}
p{color:#c33}
</style>
</head>
<body>
<div class=\"card\"><p>", (html_escape(Message))/binary, "</p></div>
</body>
</html>">>.

%% Constant-time binary comparison to prevent timing side-channels.
constant_time_compare(<<A, RestA/binary>>, <<B, RestB/binary>>) ->
    constant_time_compare(RestA, RestB, A bxor B);
constant_time_compare(<<>>, <<>>) -> true;
constant_time_compare(_, _) -> false.

constant_time_compare(<<A, RestA/binary>>, <<B, RestB/binary>>, Acc) ->
    constant_time_compare(RestA, RestB, Acc bor (A bxor B));
constant_time_compare(<<>>, <<>>, 0) -> true;
constant_time_compare(<<>>, <<>>, _) -> false.
