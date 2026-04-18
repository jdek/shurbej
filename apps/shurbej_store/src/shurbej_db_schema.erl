-module(shurbej_db_schema).
-include("shurbej_records.hrl").

-export([ensure/0]).

ensure() ->
    ensure_schema(),
    ensure_tables(),
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
        {shurbej_user, record_info(fields, shurbej_user), set, []},
        {shurbej_item_collection, record_info(fields, shurbej_item_collection), bag, []}
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
        [shurbej_library, shurbej_api_key, shurbej_item, shurbej_collection,
         shurbej_search, shurbej_tag, shurbej_setting, shurbej_deleted,
         shurbej_fulltext, shurbej_file_meta, shurbej_blob, shurbej_user,
         shurbej_item_collection],
        5000
    ).

check_users() ->
    case mnesia:dirty_first(shurbej_user) of
        '$end_of_table' ->
            logger:notice("no users configured. "
                          "Create one with: shurbej_admin:create_user(<<\"username\">>, <<\"password\">>, 1).");
        _ ->
            ok
    end.
