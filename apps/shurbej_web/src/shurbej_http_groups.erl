-module(shurbej_http_groups).
-include_lib("shurbej_store/include/shurbej_records.hrl").

-export([init/2]).

init(Req0, State) ->
    case cowboy_req:method(Req0) of
        <<"GET">> ->
            case shurbej_http_common:authorize(Req0) of
                {ok, {user, UserId}, _} -> handle_get(UserId, Req0, State);
                {error, Reason, _} ->
                    Req = shurbej_http_common:auth_error_response(Reason, Req0),
                    {ok, Req, State}
            end;
        _ ->
            Req = shurbej_http_common:error_response(405, <<"Method not allowed">>, Req0),
            {ok, Req, State}
    end.

%% GET /users/:user_id/groups — list groups the user is a member of.
handle_get(UserId, Req0, State) ->
    Memberships = shurbej_db:list_user_groups(UserId),
    Groups = lists:filtermap(fun(#shurbej_group_member{id = {GroupId, _}}) ->
        case shurbej_db:get_group(GroupId) of
            {ok, Group} -> {true, Group};
            undefined -> false
        end
    end, Memberships),
    Format = shurbej_http_common:get_format(Req0),
    case Format of
        <<"versions">> ->
            Map = maps:from_list(
                [{integer_to_binary(G#shurbej_group.group_id), G#shurbej_group.version}
                 || G <- Groups]),
            Req = shurbej_http_common:json_response(200, Map, 0, Req0),
            {ok, Req, State};
        _ ->
            Body = [envelope_group(G) || G <- Groups],
            Req = shurbej_http_common:json_response(200, Body, 0, Req0),
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
            },
            <<"alternate">> => #{
                <<"href">> => <<Base/binary, "/groups/", IdBin/binary>>,
                <<"type">> => <<"text/html">>
            }
        },
        <<"meta">> => #{
            <<"created">> => <<>>,
            <<"lastModified">> => <<>>,
            <<"numItems">> => 0
        },
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
