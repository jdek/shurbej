-module(shurbej_http_group).
-include_lib("shurbej_store/include/shurbej_records.hrl").

-export([init/2]).

%% GET /groups/:group_id — single group metadata.
%% Authorization requires group membership.
init(Req0, State) ->
    case cowboy_req:method(Req0) of
        <<"GET">> ->
            case shurbej_http_common:authorize(Req0) of
                {ok, {group, GroupId} = LibRef, _} ->
                    case shurbej_http_common:check_lib_perm(read, LibRef) of
                        ok -> handle_get(GroupId, Req0, State);
                        {error, forbidden} ->
                            Req = shurbej_http_common:error_response(403,
                                <<"Access denied">>, Req0),
                            {ok, Req, State}
                    end;
                {error, Reason, _} ->
                    Req = shurbej_http_common:auth_error_response(Reason, Req0),
                    {ok, Req, State}
            end;
        _ ->
            Req = shurbej_http_common:error_response(405, <<"Method not allowed">>, Req0),
            {ok, Req, State}
    end.

handle_get(GroupId, Req0, State) ->
    case shurbej_db:get_group(GroupId) of
        {ok, Group} ->
            Body = envelope_group(Group),
            Req = shurbej_http_common:json_response(200, Body,
                Group#shurbej_group.version, Req0),
            {ok, Req, State};
        undefined ->
            Req = shurbej_http_common:error_response(404, <<"Group not found">>, Req0),
            {ok, Req, State}
    end.

envelope_group(#shurbej_group{
        group_id = Id, name = Name, owner_id = Owner, type = Type,
        description = Desc, url = Url, has_image = HasImage,
        library_editing = LibEd, library_reading = LibRd, file_editing = FileEd,
        version = Version}) ->
    Base = shurbej_http_common:base_url(),
    IdBin = integer_to_binary(Id),
    #{
        <<"id">> => Id,
        <<"version">> => Version,
        <<"links">> => #{
            <<"self">> => #{
                <<"href">> => <<Base/binary, "/groups/", IdBin/binary>>,
                <<"type">> => <<"application/json">>
            }
        },
        <<"meta">> => #{<<"numItems">> => 0},
        <<"data">> => #{
            <<"id">> => Id,
            <<"version">> => Version,
            <<"name">> => Name,
            <<"owner">> => Owner,
            <<"type">> => type_to_binary(Type),
            <<"description">> => Desc,
            <<"url">> => Url,
            <<"hasImage">> => HasImage,
            <<"libraryEditing">> => atom_to_binary(LibEd),
            <<"libraryReading">> => atom_to_binary(LibRd),
            <<"fileEditing">> => atom_to_binary(FileEd)
        }
    }.

type_to_binary(private) -> <<"Private">>;
type_to_binary(public_closed) -> <<"PublicClosed">>;
type_to_binary(public_open) -> <<"PublicOpen">>.
