-module(shurbey_http_meta).
-export([init/2]).

%% Serves schema-derived metadata endpoints:
%% GET /itemTypes — all item types
%% GET /itemFields — all item fields
%% GET /itemTypeFields?itemType=<type> — fields for a type
%% GET /itemTypeCreatorTypes?itemType=<type> — creator types for a type
%% GET /creatorFields — creator field names

init(Req0, #{action := Action} = State) ->
    case cowboy_req:method(Req0) of
        <<"GET">> -> handle(Action, Req0, State);
        _ ->
            Req = shurbey_http_common:error_response(405, <<"Method not allowed">>, Req0),
            {ok, Req, State}
    end.

handle(item_types, Req0, State) ->
    Schema = get_schema(),
    Types = [#{<<"itemType">> => maps:get(<<"itemType">>, IT),
               <<"localized">> => maps:get(<<"itemType">>, IT)}
             || IT <- maps:get(<<"itemTypes">>, Schema, [])],
    Req = shurbey_http_common:json_response(200, Types, Req0),
    {ok, Req, State};

handle(item_fields, Req0, State) ->
    Schema = get_schema(),
    AllFields = lists:usort(lists:flatmap(fun(IT) ->
        [maps:get(<<"field">>, F) || F <- maps:get(<<"fields">>, IT, [])]
    end, maps:get(<<"itemTypes">>, Schema, []))),
    Fields = [#{<<"field">> => F, <<"localized">> => F} || F <- AllFields],
    Req = shurbey_http_common:json_response(200, Fields, Req0),
    {ok, Req, State};

handle(item_type_fields, Req0, State) ->
    #{itemType := Type} = cowboy_req:match_qs([{itemType, [], <<>>}], Req0),
    case Type of
        <<>> ->
            Req = shurbey_http_common:error_response(400,
                <<"'itemType' is required">>, Req0),
            {ok, Req, State};
        _ ->
            Schema = get_schema(),
            case find_item_type(Type, Schema) of
                undefined ->
                    Req = shurbey_http_common:error_response(404,
                        <<"Unknown item type">>, Req0),
                    {ok, Req, State};
                IT ->
                    Fields = [format_field(F) || F <- maps:get(<<"fields">>, IT, [])],
                    Req = shurbey_http_common:json_response(200, Fields, Req0),
                    {ok, Req, State}
            end
    end;

handle(item_type_creator_types, Req0, State) ->
    #{itemType := Type} = cowboy_req:match_qs([{itemType, [], <<>>}], Req0),
    case Type of
        <<>> ->
            Req = shurbey_http_common:error_response(400,
                <<"'itemType' is required">>, Req0),
            {ok, Req, State};
        _ ->
            Schema = get_schema(),
            case find_item_type(Type, Schema) of
                undefined ->
                    Req = shurbey_http_common:error_response(404,
                        <<"Unknown item type">>, Req0),
                    {ok, Req, State};
                IT ->
                    CTypes = [#{<<"creatorType">> => maps:get(<<"creatorType">>, C),
                                <<"localized">> => maps:get(<<"creatorType">>, C)}
                              || C <- maps:get(<<"creatorTypes">>, IT, [])],
                    Req = shurbey_http_common:json_response(200, CTypes, Req0),
                    {ok, Req, State}
            end
    end;

handle(creator_fields, Req0, State) ->
    Fields = [
        #{<<"field">> => <<"firstName">>, <<"localized">> => <<"firstName">>},
        #{<<"field">> => <<"lastName">>, <<"localized">> => <<"lastName">>}
    ],
    Req = shurbey_http_common:json_response(200, Fields, Req0),
    {ok, Req, State}.

%% Internal

get_schema() ->
    SchemaPath = filename:join(code:priv_dir(shurbey_web), "schema.json"),
    {ok, SchemaJson} = file:read_file(SchemaPath),
    jiffy:decode(SchemaJson, [return_maps]).

find_item_type(Type, Schema) ->
    case [IT || IT <- maps:get(<<"itemTypes">>, Schema, []),
                maps:get(<<"itemType">>, IT) =:= Type] of
        [Found | _] -> Found;
        [] -> undefined
    end.

format_field(F) ->
    Base = #{<<"field">> => maps:get(<<"field">>, F),
             <<"localized">> => maps:get(<<"field">>, F)},
    case maps:get(<<"baseField">>, F, undefined) of
        undefined -> Base;
        BF -> Base#{<<"baseField">> => BF}
    end.
