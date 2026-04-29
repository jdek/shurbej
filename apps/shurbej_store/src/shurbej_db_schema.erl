-module(shurbej_db_schema).
-include("shurbej_records.hrl").

-export([ensure/0, current_version/0]).

%% Bump this when records change, keys change shape, or tables get
%% added/removed in a way that would misalign an older on-disk copy.
-define(SCHEMA_VERSION, 2).

current_version() -> ?SCHEMA_VERSION.

ensure() ->
    ensure_schema(),
    ensure_tables(),
    check_schema_version(),
    check_users(),
    ok.

ensure_schema() ->
    mnesia:stop(),
    Node = node(),
    case mnesia:create_schema([Node]) of
        ok -> ok;
        {error, {Node, {already_exists, Node}}} -> ok
    end,
    ok = mnesia:start().

ensure_tables() ->
    StorageType = case node() of
        nonode@nohost -> ram_copies;
        _ -> disc_copies
    end,
    Tables = [
        {shurbej_schema_meta, record_info(fields, shurbej_schema_meta), set, []},
        {shurbej_library, record_info(fields, shurbej_library), set, []},
        {shurbej_api_key, record_info(fields, shurbej_api_key), set, []},
        {shurbej_item, record_info(fields, shurbej_item), set, [parent_key]},
        {shurbej_collection, record_info(fields, shurbej_collection), set, []},
        {shurbej_search, record_info(fields, shurbej_search), set, []},
        {shurbej_tag, record_info(fields, shurbej_tag), set, []},
        {shurbej_setting, record_info(fields, shurbej_setting), set, []},
        {shurbej_deleted, record_info(fields, shurbej_deleted), set, []},
        {shurbej_fulltext, record_info(fields, shurbej_fulltext), set, []},
        {shurbej_file_meta, record_info(fields, shurbej_file_meta), set, []},
        {shurbej_blob, record_info(fields, shurbej_blob), set, []},
        {shurbej_user, record_info(fields, shurbej_user), set, [user_id, username]},
        {shurbej_identity, record_info(fields, shurbej_identity), set, [user_uuid]},
        {shurbej_item_collection, record_info(fields, shurbej_item_collection), bag, []},
        {shurbej_group, record_info(fields, shurbej_group), set, [owner_uuid]},
        {shurbej_group_member, record_info(fields, shurbej_group_member), set, []}
    ],
    lists:foreach(fun({Name, Fields, Type, Indices}) ->
        case mnesia:create_table(Name, [
            {attributes, Fields},
            {type, Type},
            {StorageType, [node()]}
        | [{index, Indices} || Indices =/= []]
        ]) of
            {atomic, ok} -> ok;
            {aborted, {already_exists, Name}} -> ok
        end
    end, Tables),
    ok = mnesia:wait_for_tables(
        [shurbej_schema_meta, shurbej_library, shurbej_api_key, shurbej_item,
         shurbej_collection, shurbej_search, shurbej_tag, shurbej_setting,
         shurbej_deleted, shurbej_fulltext, shurbej_file_meta, shurbej_blob,
         shurbej_user, shurbej_identity, shurbej_item_collection, shurbej_group,
         shurbej_group_member],
        5000
    ).

%% Compare on-disk schema version with the compiled constant. On a fresh
%% install, stamp the sentinel row. On mismatch, abort startup: silently
%% running against an incompatible on-disk layout can corrupt data.
check_schema_version() ->
    case mnesia:dirty_read(shurbej_schema_meta, version) of
        [] ->
            mnesia:dirty_write(#shurbej_schema_meta{
                key = version, value = ?SCHEMA_VERSION
            }),
            ok;
        [#shurbej_schema_meta{value = ?SCHEMA_VERSION}] ->
            ok;
        [#shurbej_schema_meta{value = OnDisk}] ->
            Msg = io_lib:format(
                "schema version mismatch: on-disk=~p, compiled=~p. "
                "Migrate or wipe the mnesia dir before starting.",
                [OnDisk, ?SCHEMA_VERSION]),
            logger:error("~s", [Msg]),
            erlang:error({schema_version_mismatch, OnDisk, ?SCHEMA_VERSION})
    end.

check_users() ->
    case mnesia:dirty_first(shurbej_user) of
        '$end_of_table' ->
            logger:notice("no users configured. "
                          "Create one with: shurbej_admin:create_user(<<\"username\">>, <<\"password\">>).");
        _ ->
            ok
    end.
