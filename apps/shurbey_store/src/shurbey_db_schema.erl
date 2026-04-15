-module(shurbey_db_schema).
-include("shurbey_records.hrl").

-export([ensure/0]).

ensure() ->
    ensure_schema(),
    ensure_tables(),
    check_users(),
    ok.

ensure_schema() ->
    %% create_schema must be called before mnesia:start for disc_copies.
    %% Stop mnesia in case it was started as a dependency elsewhere.
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
        {shurbey_library, record_info(fields, shurbey_library), set, []},
        {shurbey_api_key, record_info(fields, shurbey_api_key), set, []},
        {shurbey_item, record_info(fields, shurbey_item), set, []},
        {shurbey_collection, record_info(fields, shurbey_collection), set, []},
        {shurbey_search, record_info(fields, shurbey_search), set, []},
        {shurbey_tag, record_info(fields, shurbey_tag), set, []},
        {shurbey_setting, record_info(fields, shurbey_setting), set, []},
        {shurbey_deleted, record_info(fields, shurbey_deleted), set, []},
        {shurbey_fulltext, record_info(fields, shurbey_fulltext), set, []},
        {shurbey_file_meta, record_info(fields, shurbey_file_meta), set, []},
        {shurbey_blob, record_info(fields, shurbey_blob), set, []},
        {shurbey_user, record_info(fields, shurbey_user), set, []}
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
        [shurbey_library, shurbey_api_key, shurbey_item, shurbey_collection,
         shurbey_search, shurbey_tag, shurbey_setting, shurbey_deleted,
         shurbey_fulltext, shurbey_file_meta, shurbey_blob, shurbey_user],
        5000
    ).

check_users() ->
    case mnesia:dirty_first(shurbey_user) of
        '$end_of_table' ->
            logger:notice("no users configured. "
                          "Create one with: shurbey_admin:create_user(<<\"username\">>, <<\"password\">>, 1).");
        _ ->
            ok
    end.
