-module(shurbej_admin).
-include_lib("shurbej_store/include/shurbej_records.hrl").
-include_lib("stdlib/include/ms_transform.hrl").

-export([
    %% Users
    create_user/2, create_user/3, list_users/0, delete_user/1,
    set_user_id/2,
    %% API keys
    create_api_key/2, create_api_key/3,
    %% Groups
    create_group/3, create_group/4, delete_group/1, list_groups/0,
    add_member/3, remove_member/2, list_members/1, list_user_groups/1
]).

%% ===================================================================
%% Users
%% ===================================================================

%% Create a user with a default phash2-based user_id label. Use
%% set_user_id/2 afterwards if you want the label to mirror an existing
%% zotero.org account.
create_user(Username, Password) when is_binary(Username), is_binary(Password) ->
    case shurbej_db:get_user_by_username(Username) of
        {ok, _} -> {error, already_exists};
        undefined ->
            {ok, UserUuid} = shurbej_db:create_user(Username, Password),
            {ok, #shurbej_user{user_id = UserId}} =
                shurbej_db:get_user_by_uuid(UserUuid),
            logger:notice("created user ~s (uuid=~s, user_id=~p)",
                          [Username, UserUuid, UserId]),
            {ok, UserUuid}
    end.

create_user(Username, Password, UserId)
        when is_binary(Username), is_binary(Password), is_integer(UserId) ->
    case shurbej_db:get_user_by_username(Username) of
        {ok, _} -> {error, already_exists};
        undefined ->
            {ok, UserUuid} = shurbej_db:create_user(Username, Password, UserId),
            logger:notice("created user ~s (uuid=~s, user_id=~p)",
                          [Username, UserUuid, UserId]),
            {ok, UserUuid}
    end.

list_users() ->
    MS = ets:fun2ms(
        fun(#shurbej_user{user_uuid = Uu, user_id = Id, username = U}) ->
            {U, Id, Uu}
        end),
    mnesia:dirty_select(shurbej_user, MS).

delete_user(Username) when is_binary(Username) ->
    case shurbej_db:get_user_by_username(Username) of
        undefined -> {error, not_found};
        {ok, #shurbej_user{user_uuid = UserUuid}} ->
            shurbej_db:delete_user(UserUuid)
    end.

%% Change the Zotero-API user_id label for a user, identified by username.
%% Existing Zotero clients paired against this server will see the change at
%% their next /keys/current call and offer to wipe-and-resync — call this
%% before pairing, or accept the wipe.
set_user_id(Username, NewUserId)
        when is_binary(Username), is_integer(NewUserId), NewUserId >= 0 ->
    case shurbej_db:get_user_by_username(Username) of
        undefined -> {error, not_found};
        {ok, #shurbej_user{user_uuid = UserUuid}} ->
            shurbej_db:set_user_id(UserUuid, NewUserId)
    end.

%% ===================================================================
%% API keys
%% ===================================================================

%% Shortcut: create_api_key(Username, Name) — full access to the user library
%% and every group they belong to.
create_api_key(Username, Name) ->
    create_api_key(Username, Name, full).

%% create_api_key(Username, Name, Access) where Access is one of:
%%   full            — library+write+files+notes on user, library+write on groups.all
%%   read_only       — library only on user, library only on groups.all
%%   Map             — canonical perms map; passes through normalize_perms.
create_api_key(Username, Name, Access)
        when is_binary(Username), is_binary(Name) ->
    case shurbej_db:get_user_by_username(Username) of
        undefined -> {error, user_not_found};
        {ok, #shurbej_user{user_uuid = UserUuid}} ->
            Perms = resolve_access(Access),
            ApiKey = generate_api_key(),
            shurbej_db:create_key(ApiKey, UserUuid, Perms),
            logger:notice("created API key '~s' for user ~s", [Name, Username]),
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
    binary:encode_hex(crypto:strong_rand_bytes(32), lowercase).

%% ===================================================================
%% Groups
%% ===================================================================

%% create_group(Name, OwnerUsername, Type) — owner auto-added as member.
create_group(Name, OwnerUsername, Type) ->
    create_group(Name, OwnerUsername, Type, #{}).

%% Opts: description, url, library_editing, library_reading, file_editing.
create_group(Name, OwnerUsername, Type, Opts)
        when is_binary(Name), is_binary(OwnerUsername),
             (Type =:= private orelse Type =:= public_closed
              orelse Type =:= public_open) ->
    case shurbej_db:get_user_by_username(OwnerUsername) of
        undefined -> {error, owner_not_found};
        {ok, #shurbej_user{user_uuid = OwnerUuid}} ->
            create_group_1(Name, OwnerUuid, Type, Opts)
    end;
create_group(_, _, Type, _) ->
    {error, {bad_type, Type}}.

create_group_1(Name, OwnerUuid, Type, Opts) ->
    LibEd = maps:get(library_editing, Opts, members),
    LibRd = maps:get(library_reading, Opts, members),
    FileEd = maps:get(file_editing, Opts, admins),
    %% Allocate group_id and write within a single transaction so concurrent
    %% creates can't collide on the same id.
    {atomic, GroupId} = mnesia:transaction(fun() ->
        Gid = tx_next_group_id(),
        mnesia:write(#shurbej_group{
            group_id = Gid,
            name = Name,
            owner_uuid = OwnerUuid,
            type = Type,
            description = maps:get(description, Opts, <<>>),
            url = maps:get(url, Opts, <<>>),
            has_image = false,
            library_editing = LibEd,
            library_reading = LibRd,
            file_editing = FileEd,
            created = erlang:system_time(second),
            version = 0
        }),
        mnesia:write(#shurbej_group_member{
            id = {Gid, OwnerUuid}, role = owner
        }),
        mnesia:write(#shurbej_library{
            ref = {group, Gid}, version = 0
        }),
        Gid
    end),
    logger:notice("created group ~s (group_id=~p, owner=~s)",
                  [Name, GroupId, OwnerUuid]),
    {ok, GroupId}.

tx_next_group_id() ->
    MS = ets:fun2ms(fun(#shurbej_group{group_id = Id}) -> Id end),
    case mnesia:select(shurbej_group, MS) of
        [] -> 1;
        Ids -> lists:max(Ids) + 1
    end.

delete_group(GroupId) when is_integer(GroupId) ->
    shurbej_db:delete_group(GroupId).

list_groups() ->
    [{G#shurbej_group.group_id, G#shurbej_group.name, G#shurbej_group.owner_uuid,
      G#shurbej_group.type} || G <- shurbej_db:list_groups()].

add_member(GroupId, Username, Role)
        when is_integer(GroupId), is_binary(Username),
             (Role =:= owner orelse Role =:= admin orelse Role =:= member) ->
    case {shurbej_db:get_group(GroupId), shurbej_db:get_user_by_username(Username)} of
        {undefined, _} -> {error, group_not_found};
        {_, undefined} -> {error, user_not_found};
        {{ok, _}, {ok, #shurbej_user{user_uuid = UserUuid}}} ->
            shurbej_db:add_group_member(GroupId, UserUuid, Role)
    end;
add_member(_, _, Role) ->
    {error, {bad_role, Role}}.

remove_member(GroupId, Username)
        when is_integer(GroupId), is_binary(Username) ->
    case shurbej_db:get_user_by_username(Username) of
        undefined -> {error, user_not_found};
        {ok, #shurbej_user{user_uuid = UserUuid}} ->
            shurbej_db:remove_group_member(GroupId, UserUuid)
    end.

list_members(GroupId) ->
    [{U, R} || #shurbej_group_member{id = {_, U}, role = R}
               <- shurbej_db:list_group_members(GroupId)].

list_user_groups(Username) when is_binary(Username) ->
    case shurbej_db:get_user_by_username(Username) of
        undefined -> {error, user_not_found};
        {ok, #shurbej_user{user_uuid = UserUuid}} ->
            {ok, [{G, R} || #shurbej_group_member{id = {G, _}, role = R}
                            <- shurbej_db:list_user_groups(UserUuid)]}
    end.
