-module(shurbej_admin).
-include_lib("shurbej_store/include/shurbej_records.hrl").
-include_lib("stdlib/include/ms_transform.hrl").

-export([
    %% Users
    create_user/2, create_user/3, list_users/0, delete_user/1,
    %% API keys
    create_api_key/2, create_api_key/3,
    %% Groups
    create_group/3, create_group/4, delete_group/1, list_groups/0,
    add_member/3, remove_member/2, list_members/1, list_user_groups/1
]).

%% ===================================================================
%% Users
%% ===================================================================

create_user(Username, Password) when is_binary(Username), is_binary(Password) ->
    UserId = next_user_id(),
    create_user(Username, Password, UserId).

create_user(Username, Password, UserId) when is_binary(Username), is_binary(Password) ->
    case shurbej_db:get_user(Username) of
        {ok, _} ->
            {error, already_exists};
        undefined ->
            ok = shurbej_db:create_user(Username, Password, UserId),
            logger:notice("created user ~s (user_id=~p)", [Username, UserId]),
            ok
    end.

list_users() ->
    MS = ets:fun2ms(
        fun(#shurbej_user{username = U, user_id = Id}) -> {U, Id} end),
    mnesia:dirty_select(shurbej_user, MS).

delete_user(Username) ->
    mnesia:dirty_delete({shurbej_user, Username}).

next_user_id() ->
    MS = ets:fun2ms(fun(#shurbej_user{user_id = Id}) -> Id end),
    case mnesia:dirty_select(shurbej_user, MS) of
        [] -> 1;
        Ids -> lists:max(Ids) + 1
    end.

%% ===================================================================
%% API keys
%% ===================================================================

%% Shortcut: create_api_key(UserId, Name) — full access to the user library
%% and every group they belong to.
create_api_key(UserId, Name) ->
    create_api_key(UserId, Name, full).

%% create_api_key(UserId, Name, Access) where Access is one of:
%%   full            — library+write+files+notes on user, library+write on groups.all
%%   read_only       — library only on user, library only on groups.all
%%   Map             — canonical perms map; passes through normalize_perms.
create_api_key(UserId, Name, Access) when is_integer(UserId), is_binary(Name) ->
    case shurbej_db:get_user_by_id(UserId) of
        undefined -> {error, user_not_found};
        {ok, _} ->
            Perms = resolve_access(Access),
            ApiKey = generate_api_key(),
            shurbej_db:create_key(ApiKey, UserId, Perms),
            logger:notice("created API key '~s' for user_id=~p", [Name, UserId]),
            {ok, ApiKey}
    end.

resolve_access(full) ->
    shurbej_http_common:normalize_perms(undefined);
resolve_access(read_only) ->
    shurbej_http_common:normalize_perms(#{
        user => #{library => true, write => false, files => false, notes => false},
        groups => #{all => #{library => true, write => false}}
    });
resolve_access(Map) when is_map(Map) ->
    shurbej_http_common:normalize_perms(Map).

generate_api_key() ->
    Bytes = crypto:strong_rand_bytes(32),
    list_to_binary(lists:flatten(
        [io_lib:format("~2.16.0b", [B]) || <<B>> <= Bytes]
    )).

%% ===================================================================
%% Groups
%% ===================================================================

%% create_group(Name, OwnerUserId, Type) — owner auto-added as member.
create_group(Name, OwnerUserId, Type) ->
    create_group(Name, OwnerUserId, Type, #{}).

%% Opts: description, url, library_editing, library_reading, file_editing.
create_group(Name, OwnerUserId, Type, Opts)
        when is_binary(Name), is_integer(OwnerUserId),
             Type =:= private; Type =:= public_closed; Type =:= public_open ->
    create_group_1(Name, OwnerUserId, Type, Opts);
create_group(_, _, Type, _) ->
    {error, {bad_type, Type}}.

create_group_1(Name, OwnerUserId, Type, Opts) ->
    case shurbej_db:get_user_by_id(OwnerUserId) of
        undefined -> {error, owner_not_found};
        {ok, _} ->
            GroupId = next_group_id(),
            LibEd = maps:get(library_editing, Opts, members),
            LibRd = maps:get(library_reading, Opts, members),
            FileEd = maps:get(file_editing, Opts, admins),
            Group = #shurbej_group{
                group_id = GroupId,
                name = Name,
                owner_id = OwnerUserId,
                type = Type,
                description = maps:get(description, Opts, <<>>),
                url = maps:get(url, Opts, <<>>),
                has_image = false,
                library_editing = LibEd,
                library_reading = LibRd,
                file_editing = FileEd,
                created = erlang:system_time(second),
                version = 0
            },
            {atomic, ok} = mnesia:transaction(fun() ->
                mnesia:write(Group),
                mnesia:write(#shurbej_group_member{
                    id = {GroupId, OwnerUserId}, role = owner
                }),
                mnesia:write(#shurbej_library{
                    ref = {group, GroupId}, version = 0
                })
            end),
            logger:notice("created group ~s (group_id=~p, owner=~p)",
                          [Name, GroupId, OwnerUserId]),
            {ok, GroupId}
    end.

delete_group(GroupId) when is_integer(GroupId) ->
    shurbej_db:delete_group(GroupId).

list_groups() ->
    [{G#shurbej_group.group_id, G#shurbej_group.name, G#shurbej_group.owner_id,
      G#shurbej_group.type} || G <- shurbej_db:list_groups()].

add_member(GroupId, UserId, Role)
        when is_integer(GroupId), is_integer(UserId),
             Role =:= owner; Role =:= admin; Role =:= member ->
    case {shurbej_db:get_group(GroupId), shurbej_db:get_user_by_id(UserId)} of
        {undefined, _} -> {error, group_not_found};
        {_, undefined} -> {error, user_not_found};
        {{ok, _}, {ok, _}} ->
            shurbej_db:add_group_member(GroupId, UserId, Role)
    end;
add_member(_, _, Role) ->
    {error, {bad_role, Role}}.

remove_member(GroupId, UserId) ->
    shurbej_db:remove_group_member(GroupId, UserId).

list_members(GroupId) ->
    [{U, R} || #shurbej_group_member{id = {_, U}, role = R}
               <- shurbej_db:list_group_members(GroupId)].

list_user_groups(UserId) ->
    [{G, R} || #shurbej_group_member{id = {G, _}, role = R}
               <- shurbej_db:list_user_groups(UserId)].

next_group_id() ->
    MS = ets:fun2ms(fun(#shurbej_group{group_id = Id}) -> Id end),
    case mnesia:dirty_select(shurbej_group, MS) of
        [] -> 1;
        Ids -> lists:max(Ids) + 1
    end.
