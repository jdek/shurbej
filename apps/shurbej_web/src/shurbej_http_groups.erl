-module(shurbej_http_groups).
-include_lib("shurbej_store/include/shurbej_records.hrl").

-export([init/2]).

init(Req0, State) ->
    case cowboy_req:method(Req0) of
        <<"GET">> ->
            case shurbej_http_common:authorize(Req0) of
                {ok, {user, UserUuid}, _} -> handle_get(UserUuid, Req0, State);
                {error, Reason, _} ->
                    Req = shurbej_http_common:auth_error_response(Reason, Req0),
                    {ok, Req, State}
            end;
        _ ->
            Req = shurbej_http_common:error_response(405, <<"Method not allowed">>, Req0),
            {ok, Req, State}
    end.

%% GET /users/:user_id/groups — list groups the user is a member of.
handle_get(UserUuid, Req0, State) ->
    Memberships = shurbej_db:list_user_groups(UserUuid),
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
            Body = [shurbej_http_common:envelope_group(G) || G <- Groups],
            Req = shurbej_http_common:json_response(200, Body, 0, Req0),
            {ok, Req, State}
    end.
