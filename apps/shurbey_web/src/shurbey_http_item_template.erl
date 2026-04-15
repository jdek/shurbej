-module(shurbey_http_item_template).
-export([init/2]).

%% GET /items/new?itemType=book — return a blank template for the given item type.
init(Req0, State) ->
    case cowboy_req:method(Req0) of
        <<"GET">> ->
            #{itemType := Type} = cowboy_req:match_qs([{itemType, [], <<>>}], Req0),
            case Type of
                <<>> ->
                    Req = shurbey_http_common:error_response(400,
                        <<"'itemType' query parameter is required">>, Req0),
                    {ok, Req, State};
                _ ->
                    case lists:member(Type, shurbey_validate:item_types()) of
                        true ->
                            Template = base_template(Type),
                            Req = shurbey_http_common:json_response(200, Template, Req0),
                            {ok, Req, State};
                        false ->
                            Req = shurbey_http_common:error_response(400,
                                <<"Unknown item type: ", Type/binary>>, Req0),
                            {ok, Req, State}
                    end
            end;
        _ ->
            Req = shurbey_http_common:error_response(405, <<"Method not allowed">>, Req0),
            {ok, Req, State}
    end.

base_template(Type) ->
    Base = #{
        <<"itemType">> => Type,
        <<"title">> => <<>>,
        <<"creators">> => [],
        <<"tags">> => [],
        <<"collections">> => [],
        <<"relations">> => #{}
    },
    %% Add type-specific fields
    maps:merge(Base, type_fields(Type)).

type_fields(<<"note">>) ->
    #{<<"note">> => <<>>};
type_fields(<<"attachment">>) ->
    #{<<"linkMode">> => <<>>, <<"contentType">> => <<>>, <<"charset">> => <<>>,
      <<"filename">> => <<>>, <<"path">> => <<>>};
type_fields(<<"annotation">>) ->
    #{<<"annotationType">> => <<>>, <<"annotationText">> => <<>>,
      <<"annotationComment">> => <<>>, <<"annotationColor">> => <<>>,
      <<"annotationPageLabel">> => <<>>, <<"annotationPosition">> => <<>>};
type_fields(_) ->
    %% Common fields for most item types
    #{<<"abstractNote">> => <<>>, <<"date">> => <<>>, <<"language">> => <<>>,
      <<"shortTitle">> => <<>>, <<"url">> => <<>>, <<"accessDate">> => <<>>,
      <<"extra">> => <<>>, <<"rights">> => <<>>}.
