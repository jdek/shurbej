-module(shurbej_http_schema).
-export([init/2]).

%% GET /schema — serve the bundled Zotero schema from priv/schema.json.
init(Req0, State) ->
    case cowboy_req:method(Req0) of
        <<"GET">> ->
            SchemaPath = schema_path(),
            case file:read_file(SchemaPath) of
                {ok, SchemaJson} ->
                    Req = cowboy_req:reply(200, #{
                        <<"content-type">> => <<"application/json">>
                    }, SchemaJson, Req0),
                    {ok, Req, State};
                {error, _} ->
                    Req = shurbej_http_common:error_response(500,
                        <<"Schema file not found">>, Req0),
                    {ok, Req, State}
            end;
        _ ->
            Req = shurbej_http_common:error_response(405, <<"Method not allowed">>, Req0),
            {ok, Req, State}
    end.

schema_path() ->
    PrivDir = code:priv_dir(shurbej_web),
    filename:join(PrivDir, "schema.json").
