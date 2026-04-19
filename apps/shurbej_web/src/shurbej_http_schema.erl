-module(shurbej_http_schema).
-export([init/2]).

%% GET /schema — serve the bundled Zotero schema from priv/schema.json.
%% The bytes are cached in persistent_term (set-once, read-many — the ideal
%% use) so we don't hit the disk on every poll.
init(Req0, State) ->
    case cowboy_req:method(Req0) of
        <<"GET">> ->
            case schema_bytes() of
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

schema_bytes() ->
    case persistent_term:get({?MODULE, schema}, undefined) of
        undefined ->
            case file:read_file(schema_path()) of
                {ok, Bin} ->
                    persistent_term:put({?MODULE, schema}, Bin),
                    {ok, Bin};
                {error, _} = Err ->
                    Err
            end;
        Bin ->
            {ok, Bin}
    end.

schema_path() ->
    PrivDir = code:priv_dir(shurbej_web),
    filename:join(PrivDir, "schema.json").
