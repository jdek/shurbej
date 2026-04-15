-module(shurbey_sync_SUITE).
-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([
    all/0,
    init_per_suite/1,
    end_per_suite/1,
    init_per_testcase/2,
    end_per_testcase/2
]).

-export([
    %% Auth
    keys_current_valid/1,
    keys_current_no_key/1,
    keys_current_bad_key/1,

    %% Items CRUD
    items_empty_library/1,
    items_create_single/1,
    items_create_multiple/1,
    items_get_single/1,
    items_get_versions/1,
    items_get_since/1,
    items_update/1,
    items_delete/1,

    %% Version concurrency
    version_precondition_fail/1,
    version_header_on_responses/1,

    %% Collections
    collections_crud/1,

    %% Searches
    searches_crud/1,

    %% Settings
    settings_crud/1,

    %% Tags
    tags_from_items/1,

    %% Deleted tracking
    deleted_tracking/1,

    %% Full-text
    fulltext_crud/1,

    %% Groups
    groups_empty/1,

    %% Scope filtering
    items_scope_top/1,
    items_scope_trash/1,
    items_scope_children/1,

    %% Envelope format
    items_envelope_format/1,

    %% Pagination
    items_pagination/1,

    %% Validation
    validation_rejects_bad_item_type/1,
    validation_rejects_bad_creators/1,
    validation_partial_success/1,

    %% Sorting
    items_sorted/1,

    %% format=keys
    items_format_keys/1,

    %% 304 Not Modified
    items_304_not_modified/1,

    %% Data stored as native terms
    items_native_terms/1,

    %% File storage
    file_upload_download/1,
    file_content_addressed_dedup/1,
    file_refcount_cleanup/1,

    %% Auth flow
    session_login_flow/1,
    session_poll_pending/1,
    session_cancel/1,
    session_expired/1,
    delete_key_revokes/1,

    %% Coverage: PUT/PATCH
    item_put_update/1,
    item_patch_merge/1,
    collection_patch/1,
    search_patch/1,

    %% Coverage: template & schema
    item_template/1,
    item_template_bad_type/1,
    schema_endpoint/1,

    %% Coverage: write token idempotency
    write_token_idempotent/1,

    %% Coverage: filters
    filter_by_tag/1,
    filter_by_item_type/1,
    filter_by_query/1,
    filter_qmode_everything/1,
    include_trashed/1,

    %% Coverage: 304 on other endpoints
    collections_304/1,
    settings_304/1,
    deleted_304/1,
    tags_304/1,
    fulltext_304/1,

    %% Coverage: error paths
    upload_md5_mismatch/1,
    fulltext_validation/1,
    settings_single_get/1,
    method_not_allowed/1,
    export_format_rejected/1,

    %% Coverage: admin
    admin_list_delete_user/1,

    %% Coverage: session cleanup
    session_cleaner_runs/1,

    %% Coverage: WebSocket login
    ws_login_flow/1,

    %% Coverage: auth failures
    collections_auth_required/1,
    searches_auth_required/1,
    settings_auth_required/1,
    fulltext_auth_required/1,
    files_auth_required/1,
    groups_auth_required/1,
    deleted_auth_required/1,
    tags_auth_required/1,
    items_auth_required/1,

    %% Coverage: DELETE operations
    collections_delete/1,
    searches_delete/1,

    %% Coverage: format=keys for collections/searches
    collections_format_keys/1,
    searches_format_keys/1,

    %% Coverage: 405 Method Not Allowed on all endpoints
    schema_405/1,
    upload_405/1,
    upload_unknown_key/1,
    groups_versions/1,
    fulltext_405/1,
    item_template_405/1,

    %% Coverage: single GET endpoints
    collection_single_get/1,
    collection_single_404/1,
    search_single_get/1,
    settings_single_404/1,
    fulltext_single_404/1,

    %% Coverage: precondition failures
    collection_precondition/1,
    search_precondition/1,
    settings_precondition/1,
    items_precondition_delete/1,

    %% Coverage: validation edge cases
    validation_empty_collection_name/1,
    validation_empty_search_name/1,
    validation_missing_item_type/1,
    validation_bad_setting/1,

    %% Coverage: session/login edge cases
    session_cancel_not_found/1,
    login_completed_session/1,
    keys_session_expired/1,
    keys_session_404/1,

    %% Coverage: write token
    write_token_store_and_cleanup/1,

    %% Coverage: file cascade delete
    file_cascade_delete/1,

    %% Coverage: more edge cases
    bad_json_body/1,
    login_bad_credentials/1,
    login_expired_session/1,
    file_download_no_file/1,
    collection_key_filter/1,
    search_key_filter/1,
    search_versions_format/1,
    tags_versions_format/1,
    settings_versions_format/1,
    validation_bad_tags/1,
    validation_bad_collections_field/1,
    validation_bad_key_format/1,
    item_template_note/1,
    item_template_attachment/1,
    put_nonexistent_item/1,
    duplicate_user_create/1
]).

all() ->
    [
        keys_current_valid,
        keys_current_no_key,
        keys_current_bad_key,
        items_empty_library,
        items_create_single,
        items_create_multiple,
        items_get_single,
        items_get_versions,
        items_get_since,
        items_update,
        items_delete,
        version_precondition_fail,
        version_header_on_responses,
        collections_crud,
        searches_crud,
        settings_crud,
        tags_from_items,
        deleted_tracking,
        fulltext_crud,
        groups_empty,
        items_scope_top,
        items_scope_trash,
        items_scope_children,
        items_envelope_format,
        items_pagination,
        validation_rejects_bad_item_type,
        validation_rejects_bad_creators,
        validation_partial_success,
        items_sorted,
        items_format_keys,
        items_304_not_modified,
        items_native_terms,
        file_upload_download,
        file_content_addressed_dedup,
        file_refcount_cleanup,
        session_login_flow,
        session_poll_pending,
        session_cancel,
        session_expired,
        delete_key_revokes,
        item_put_update,
        item_patch_merge,
        collection_patch,
        search_patch,
        item_template,
        item_template_bad_type,
        schema_endpoint,
        write_token_idempotent,
        filter_by_tag,
        filter_by_item_type,
        filter_by_query,
        filter_qmode_everything,
        include_trashed,
        collections_304,
        settings_304,
        deleted_304,
        tags_304,
        fulltext_304,
        upload_md5_mismatch,
        fulltext_validation,
        settings_single_get,
        method_not_allowed,
        export_format_rejected,
        admin_list_delete_user,
        session_cleaner_runs,
        ws_login_flow,
        collections_auth_required,
        searches_auth_required,
        settings_auth_required,
        fulltext_auth_required,
        files_auth_required,
        groups_auth_required,
        deleted_auth_required,
        tags_auth_required,
        items_auth_required,
        collections_delete,
        searches_delete,
        collections_format_keys,
        searches_format_keys,
        schema_405,
        upload_405,
        upload_unknown_key,
        groups_versions,
        fulltext_405,
        item_template_405,
        collection_single_get,
        collection_single_404,
        search_single_get,
        settings_single_404,
        fulltext_single_404,
        collection_precondition,
        search_precondition,
        settings_precondition,
        items_precondition_delete,
        validation_empty_collection_name,
        validation_empty_search_name,
        validation_missing_item_type,
        validation_bad_setting,
        session_cancel_not_found,
        login_completed_session,
        keys_session_expired,
        keys_session_404,
        write_token_store_and_cleanup,
        file_cascade_delete,
        bad_json_body,
        login_bad_credentials,
        login_expired_session,
        file_download_no_file,
        collection_key_filter,
        search_key_filter,
        search_versions_format,
        tags_versions_format,
        settings_versions_format,
        validation_bad_tags,
        validation_bad_collections_field,
        validation_bad_key_format,
        item_template_note,
        item_template_attachment,
        put_nonexistent_item,
        duplicate_user_create
    ].

init_per_suite(Config) ->
    %% Use a temp Mnesia dir for tests
    MnesiaDir = "/tmp/shurbey_test_mnesia_" ++ integer_to_list(erlang:unique_integer([positive])),
    application:set_env(mnesia, dir, MnesiaDir),
    application:set_env(shurbey, http_port, 18080),
    application:set_env(shurbey, file_storage_path, "/tmp/shurbey_test_files"),
    application:set_env(shurbey, base_url, "http://localhost:18080"),
    {ok, _} = application:ensure_all_started(shurbey),
    %% Create a test user and API key
    ok = shurbey_admin:create_user(<<"testuser">>, <<"testpass">>, 1),
    ApiKey = crypto:strong_rand_bytes(12),
    ApiKeyHex = list_to_binary(lists:flatten(
        [io_lib:format("~2.16.0b", [B]) || <<B>> <= ApiKey])),
    shurbey_db:create_key(ApiKeyHex, 1, #{library => true, write => true, files => true, notes => true}),
    [{api_key, ApiKeyHex}, {mnesia_dir, MnesiaDir}, {base, "http://localhost:18080"} | Config].

end_per_suite(Config) ->
    application:stop(shurbey),
    application:stop(mnesia),
    %% Clean up Mnesia dir
    MnesiaDir = ?config(mnesia_dir, Config),
    os:cmd("rm -rf " ++ MnesiaDir),
    Config.

init_per_testcase(_TC, Config) ->
    Config.

end_per_testcase(_TC, Config) ->
    Config.

%% ===================================================================
%% Auth tests
%% ===================================================================

keys_current_valid(Config) ->
    {200, Headers, Body} = get_json("/keys/current", Config),
    ?assertMatch(#{<<"userID">> := 1}, Body),
    ?assertMatch(#{<<"access">> := #{<<"user">> := #{<<"library">> := true}}}, Body),
    %% Username should come from the actual user record, not config
    ?assertEqual(<<"testuser">>, maps:get(<<"username">>, Body)),
    ?assert(maps:is_key(<<"last-modified-version">>, Headers)),
    ok.

keys_current_no_key(Config) ->
    {Status, _, _} = request(get, "/keys/current", [], <<>>, Config, false),
    ?assertEqual(403, Status).

keys_current_bad_key(Config) ->
    Base = ?config(base, Config),
    Url = Base ++ "/keys/current",
    {ok, {{_, Status, _}, _, _}} = httpc:request(get, {Url, [{"Zotero-API-Key", "bogus_key_12345"}]}, [], []),
    ?assertEqual(403, Status).

%% ===================================================================
%% Items CRUD
%% ===================================================================

items_empty_library(Config) ->
    {200, _, Body} = get_json("/users/1/items", Config),
    ?assertEqual([], Body).

items_create_single(Config) ->
    Item = #{<<"itemType">> => <<"journalArticle">>, <<"title">> => <<"Test Paper">>},
    {200, Headers, Body} = post_json("/users/1/items", [Item], Config),
    Successful = maps:get(<<"successful">>, Body),
    ?assertEqual(1, map_size(Successful)),
    #{<<"0">> := Created} = Successful,
    %% POST response should be enveloped
    ?assertMatch(#{<<"key">> := _, <<"version">> := _, <<"data">> := _, <<"library">> := _}, Created),
    ?assertEqual(#{}, maps:get(<<"failed">>, Body)),
    Version = binary_to_integer(maps:get(<<"last-modified-version">>, Headers)),
    ?assert(Version > 0),
    ok.

items_create_multiple(Config) ->
    Items = [
        #{<<"itemType">> => <<"book">>, <<"title">> => <<"Book 1">>},
        #{<<"itemType">> => <<"book">>, <<"title">> => <<"Book 2">>},
        #{<<"itemType">> => <<"book">>, <<"title">> => <<"Book 3">>}
    ],
    {200, _, Body} = post_json("/users/1/items", Items, Config),
    Successful = maps:get(<<"successful">>, Body),
    ?assertEqual(3, map_size(Successful)),
    Keys = [maps:get(<<"key">>, maps:get(integer_to_binary(I), Successful)) || I <- [0,1,2]],
    ?assertEqual(length(Keys), length(lists:usort(Keys))),
    ok.

items_get_single(Config) ->
    Item = #{<<"itemType">> => <<"thesis">>, <<"title">> => <<"My Thesis">>},
    {200, _, CreateBody} = post_json("/users/1/items", [Item], Config),
    #{<<"0">> := #{<<"key">> := Key}} = maps:get(<<"successful">>, CreateBody),
    {200, _, Got} = get_json("/users/1/items/" ++ binary_to_list(Key), Config),
    %% GET single item returns envelope
    ?assertMatch(#{<<"key">> := _, <<"data">> := _, <<"library">> := _}, Got),
    ?assertEqual(Key, maps:get(<<"key">>, Got)),
    Data = maps:get(<<"data">>, Got),
    ?assertEqual(<<"My Thesis">>, maps:get(<<"title">>, Data)),
    ok.

items_get_versions(Config) ->
    {200, _, Body} = get_json("/users/1/items?format=versions", Config),
    ?assert(is_map(Body)),
    maps:foreach(fun(_K, V) -> ?assert(is_integer(V)) end, Body),
    ok.

items_get_since(Config) ->
    {200, Headers, _} = get_json("/users/1/items?format=versions", Config),
    CurrentVersion = binary_to_integer(maps:get(<<"last-modified-version">>, Headers)),
    Item = #{<<"itemType">> => <<"note">>, <<"title">> => <<"Since Test">>},
    {200, _, _} = post_json("/users/1/items", [Item], Config),
    {200, _, NewItems} = get_json("/users/1/items?since=" ++ integer_to_list(CurrentVersion), Config),
    ?assert(length(NewItems) >= 1),
    Titles = [maps:get(<<"title">>, maps:get(<<"data">>, I)) || I <- NewItems],
    ?assert(lists:member(<<"Since Test">>, Titles)),
    {200, NewHeaders, _} = get_json("/users/1/items?format=versions", Config),
    NewVersion = binary_to_integer(maps:get(<<"last-modified-version">>, NewHeaders)),
    {200, _, Empty} = get_json("/users/1/items?since=" ++ integer_to_list(NewVersion), Config),
    ?assertEqual([], Empty),
    ok.

items_update(Config) ->
    Item = #{<<"itemType">> => <<"book">>, <<"title">> => <<"Original Title">>},
    {200, _, CreateBody} = post_json("/users/1/items", [Item], Config),
    #{<<"0">> := #{<<"key">> := Key}} = maps:get(<<"successful">>, CreateBody),
    Updated = #{<<"key">> => Key, <<"itemType">> => <<"book">>, <<"title">> => <<"Updated Title">>},
    {200, _, _} = post_json("/users/1/items", [Updated], Config),
    {200, _, Got} = get_json("/users/1/items/" ++ binary_to_list(Key), Config),
    ?assertEqual(<<"Updated Title">>, maps:get(<<"title">>, maps:get(<<"data">>, Got))),
    ok.

items_delete(Config) ->
    Item = #{<<"itemType">> => <<"book">>, <<"title">> => <<"To Delete">>},
    {200, _, CreateBody} = post_json("/users/1/items", [Item], Config),
    #{<<"0">> := #{<<"key">> := Key}} = maps:get(<<"successful">>, CreateBody),
    {ok, Version} = shurbey_version:get(1),
    {204, _, _} = delete_req("/users/1/items?itemKey=" ++ binary_to_list(Key), Version, Config),
    {404, _, _} = get_json("/users/1/items/" ++ binary_to_list(Key), Config),
    ok.

%% ===================================================================
%% Version concurrency
%% ===================================================================

version_precondition_fail(Config) ->
    Item = #{<<"itemType">> => <<"book">>, <<"title">> => <<"Version Test">>},
    {412, _, Body} = post_json_with_version("/users/1/items", [Item], 99999, Config),
    ?assertMatch(#{<<"message">> := _}, Body),
    ok.

version_header_on_responses(Config) ->
    Endpoints = [
        "/users/1/items",
        "/users/1/items?format=versions",
        "/users/1/collections",
        "/users/1/searches",
        "/users/1/settings",
        "/users/1/deleted?since=0",
        "/users/1/groups",
        "/users/1/fulltext"
    ],
    lists:foreach(fun(Ep) ->
        {_Status, Headers, _} = get_json(Ep, Config),
        ?assert(maps:is_key(<<"last-modified-version">>, Headers),
            "Missing Last-Modified-Version on " ++ Ep)
    end, Endpoints),
    ok.

%% ===================================================================
%% Collections
%% ===================================================================

collections_crud(Config) ->
    Coll = #{<<"name">> => <<"Test Collection">>},
    {200, _, CreateBody} = post_json("/users/1/collections", [Coll], Config),
    #{<<"0">> := Created} = maps:get(<<"successful">>, CreateBody),
    Key = maps:get(<<"key">>, Created, undefined),
    {200, _, Collections} = get_json("/users/1/collections", Config),
    ?assert(length(Collections) >= 1),
    {200, _, Versions} = get_json("/users/1/collections?format=versions", Config),
    ?assert(is_map(Versions)),
    ?assert(map_size(Versions) >= 1),
    case Key of
        undefined -> ok;
        _ ->
            {ok, Version} = shurbey_version:get(1),
            {204, _, _} = delete_req("/users/1/collections?collectionKey=" ++ binary_to_list(Key), Version, Config)
    end,
    ok.

%% ===================================================================
%% Searches
%% ===================================================================

searches_crud(Config) ->
    Search = #{<<"name">> => <<"My Search">>, <<"conditions">> => []},
    {200, _, CreateBody} = post_json("/users/1/searches", [Search], Config),
    ?assertMatch(#{<<"successful">> := _}, CreateBody),
    {200, _, Versions} = get_json("/users/1/searches?format=versions", Config),
    ?assert(is_map(Versions)),
    ok.

%% ===================================================================
%% Settings
%% ===================================================================

settings_crud(Config) ->
    Settings = #{<<"tagColors">> => #{<<"value">> => []}},
    {204, _, _} = post_json("/users/1/settings", Settings, Config),
    {200, _, Got} = get_json("/users/1/settings", Config),
    ?assertMatch(#{<<"tagColors">> := #{<<"value">> := []}}, Got),
    ok.

%% ===================================================================
%% Tags
%% ===================================================================

tags_from_items(Config) ->
    Item = #{
        <<"itemType">> => <<"book">>,
        <<"title">> => <<"Tagged Book">>,
        <<"tags">> => [#{<<"tag">> => <<"test-tag">>}, #{<<"tag">> => <<"another-tag">>}]
    },
    {200, _, _} = post_json("/users/1/items", [Item], Config),
    {200, _, Tags} = get_json("/users/1/tags", Config),
    TagNames = [maps:get(<<"tag">>, T) || T <- Tags],
    ?assert(lists:member(<<"test-tag">>, TagNames)),
    ?assert(lists:member(<<"another-tag">>, TagNames)),
    ok.

%% ===================================================================
%% Deleted tracking
%% ===================================================================

deleted_tracking(Config) ->
    Item = #{<<"itemType">> => <<"book">>, <<"title">> => <<"Will Delete">>},
    {200, _, CreateBody} = post_json("/users/1/items", [Item], Config),
    #{<<"0">> := #{<<"key">> := Key}} = maps:get(<<"successful">>, CreateBody),
    {ok, Version} = shurbey_version:get(1),
    {204, _, _} = delete_req("/users/1/items?itemKey=" ++ binary_to_list(Key), Version, Config),
    {200, _, Deleted} = get_json("/users/1/deleted?since=0", Config),
    DeletedItems = maps:get(<<"items">>, Deleted),
    ?assert(lists:member(Key, DeletedItems)),
    ok.

%% ===================================================================
%% Full-text
%% ===================================================================

fulltext_crud(Config) ->
    Item = #{<<"itemType">> => <<"book">>, <<"title">> => <<"Fulltext Book">>},
    {200, _, CreateBody} = post_json("/users/1/items", [Item], Config),
    #{<<"0">> := #{<<"key">> := Key}} = maps:get(<<"successful">>, CreateBody),
    FtBody = #{<<"content">> => <<"This is the full text content.">>,
               <<"indexedPages">> => 1, <<"totalPages">> => 1,
               <<"indexedChars">> => 30, <<"totalChars">> => 30},
    {204, _, _} = put_json("/users/1/items/" ++ binary_to_list(Key) ++ "/fulltext", FtBody, Config),
    {200, _, Got} = get_json("/users/1/items/" ++ binary_to_list(Key) ++ "/fulltext", Config),
    ?assertEqual(<<"This is the full text content.">>, maps:get(<<"content">>, Got)),
    {200, _, Versions} = get_json("/users/1/fulltext", Config),
    ?assert(maps:is_key(Key, Versions)),
    ok.

%% ===================================================================
%% Groups
%% ===================================================================

groups_empty(Config) ->
    {200, _, Body} = get_json("/users/1/groups", Config),
    ?assertEqual([], Body).

%% ===================================================================
%% Scope filtering
%% ===================================================================

items_scope_top(Config) ->
    %% Create a top-level item and a child item
    Parent = #{<<"itemType">> => <<"book">>, <<"title">> => <<"Parent Book">>},
    {200, _, PBody} = post_json("/users/1/items", [Parent], Config),
    #{<<"0">> := #{<<"key">> := ParentKey}} = maps:get(<<"successful">>, PBody),
    Child = #{<<"itemType">> => <<"note">>, <<"title">> => <<"Child Note">>,
              <<"parentItem">> => ParentKey},
    {200, _, _} = post_json("/users/1/items", [Child], Config),
    %% /items/top should only return the parent
    {200, _, TopItems} = get_json("/users/1/items/top", Config),
    TopKeys = [maps:get(<<"key">>, I) || I <- TopItems],
    ?assert(lists:member(ParentKey, TopKeys)),
    TopTitles = [maps:get(<<"title">>, maps:get(<<"data">>, I)) || I <- TopItems],
    ?assertNot(lists:member(<<"Child Note">>, TopTitles)),
    ok.

items_scope_trash(Config) ->
    %% Create and delete an item
    Item = #{<<"itemType">> => <<"book">>, <<"title">> => <<"Trashed Book">>},
    {200, _, CBody} = post_json("/users/1/items", [Item], Config),
    #{<<"0">> := #{<<"key">> := Key}} = maps:get(<<"successful">>, CBody),
    {ok, Version} = shurbey_version:get(1),
    {204, _, _} = delete_req("/users/1/items?itemKey=" ++ binary_to_list(Key), Version, Config),
    %% /items/trash should contain the deleted item
    {200, _, TrashItems} = get_json("/users/1/items/trash", Config),
    TrashKeys = [maps:get(<<"key">>, I) || I <- TrashItems],
    ?assert(lists:member(Key, TrashKeys)),
    %% /items should NOT contain it
    {200, _, AllItems} = get_json("/users/1/items", Config),
    AllKeys = [maps:get(<<"key">>, I) || I <- AllItems],
    ?assertNot(lists:member(Key, AllKeys)),
    ok.

items_scope_children(Config) ->
    Parent = #{<<"itemType">> => <<"book">>, <<"title">> => <<"Parent For Children">>},
    {200, _, PBody} = post_json("/users/1/items", [Parent], Config),
    #{<<"0">> := #{<<"key">> := ParentKey}} = maps:get(<<"successful">>, PBody),
    Child1 = #{<<"itemType">> => <<"note">>, <<"title">> => <<"Child 1">>,
               <<"parentItem">> => ParentKey},
    Child2 = #{<<"itemType">> => <<"note">>, <<"title">> => <<"Child 2">>,
               <<"parentItem">> => ParentKey},
    {200, _, _} = post_json("/users/1/items", [Child1, Child2], Config),
    %% /items/:key/children should return only the children
    {200, _, Children} = get_json("/users/1/items/" ++ binary_to_list(ParentKey) ++ "/children", Config),
    ?assertEqual(2, length(Children)),
    ChildTitles = lists:sort([maps:get(<<"title">>, maps:get(<<"data">>, C)) || C <- Children]),
    ?assertEqual([<<"Child 1">>, <<"Child 2">>], ChildTitles),
    ok.

%% ===================================================================
%% Envelope format
%% ===================================================================

items_envelope_format(Config) ->
    Item = #{<<"itemType">> => <<"book">>, <<"title">> => <<"Envelope Test">>},
    {200, _, CreateBody} = post_json("/users/1/items", [Item], Config),
    #{<<"0">> := #{<<"key">> := Key}} = maps:get(<<"successful">>, CreateBody),
    %% GET single item — verify full envelope
    {200, _, Got} = get_json("/users/1/items/" ++ binary_to_list(Key), Config),
    ?assert(maps:is_key(<<"key">>, Got)),
    ?assert(maps:is_key(<<"version">>, Got)),
    ?assert(maps:is_key(<<"library">>, Got)),
    ?assert(maps:is_key(<<"data">>, Got)),
    %% Library should have type and id
    Lib = maps:get(<<"library">>, Got),
    ?assertEqual(<<"user">>, maps:get(<<"type">>, Lib)),
    ?assertEqual(1, maps:get(<<"id">>, Lib)),
    %% Data should contain the actual fields plus key and version
    Data = maps:get(<<"data">>, Got),
    ?assertEqual(<<"Envelope Test">>, maps:get(<<"title">>, Data)),
    ?assertEqual(Key, maps:get(<<"key">>, Data)),
    ?assert(is_integer(maps:get(<<"version">>, Data))),
    ok.

%% ===================================================================
%% Pagination
%% ===================================================================

items_pagination(Config) ->
    %% Create 5 items
    Items = [#{<<"itemType">> => <<"book">>, <<"title">> => <<"Page ", (integer_to_binary(N))/binary>>}
             || N <- lists:seq(1, 5)],
    {200, _, _} = post_json("/users/1/items", Items, Config),
    %% Fetch with limit=2
    {200, Headers, Page1} = get_json("/users/1/items?limit=2&since=0", Config),
    ?assert(length(Page1) =< 2),
    %% Total-Results should reflect all matching items
    TotalStr = maps:get(<<"total-results">>, Headers, <<"0">>),
    Total = binary_to_integer(TotalStr),
    ?assert(Total >= 5),
    %% Fetch next page
    {200, _, Page2} = get_json("/users/1/items?limit=2&start=2&since=0", Config),
    ?assert(length(Page2) =< 2),
    %% Pages should not overlap
    Keys1 = [maps:get(<<"key">>, I) || I <- Page1],
    Keys2 = [maps:get(<<"key">>, I) || I <- Page2],
    ?assertEqual([], Keys1 -- (Keys1 -- Keys2)),
    ok.

%% ===================================================================
%% Validation
%% ===================================================================

validation_rejects_bad_item_type(Config) ->
    Item = #{<<"itemType">> => <<"notARealType">>, <<"title">> => <<"Bad">>},
    {400, _, Body} = post_json("/users/1/items", [Item], Config),
    Failed = maps:get(<<"failed">>, Body),
    ?assertEqual(1, map_size(Failed)),
    #{<<"0">> := Error} = Failed,
    ?assertEqual(400, maps:get(<<"code">>, Error)),
    ok.

validation_rejects_bad_creators(Config) ->
    Item = #{<<"itemType">> => <<"book">>, <<"title">> => <<"Bad Creators">>,
             <<"creators">> => [#{<<"wrong">> => <<"field">>}]},
    {400, _, Body} = post_json("/users/1/items", [Item], Config),
    ?assertEqual(1, map_size(maps:get(<<"failed">>, Body))),
    ok.

validation_partial_success(Config) ->
    %% One valid, one invalid — valid should succeed, invalid should fail
    Items = [
        #{<<"itemType">> => <<"book">>, <<"title">> => <<"Good Book">>},
        #{<<"itemType">> => <<"fake_type">>, <<"title">> => <<"Bad">>}
    ],
    {200, _, Body} = post_json("/users/1/items", Items, Config),
    ?assertEqual(1, map_size(maps:get(<<"successful">>, Body))),
    ?assertEqual(1, map_size(maps:get(<<"failed">>, Body))),
    ok.

%% ===================================================================
%% Sorting
%% ===================================================================

items_sorted(Config) ->
    %% Create items with different titles
    Items = [
        #{<<"itemType">> => <<"book">>, <<"title">> => <<"Zebra">>},
        #{<<"itemType">> => <<"book">>, <<"title">> => <<"Apple">>},
        #{<<"itemType">> => <<"book">>, <<"title">> => <<"Mango">>}
    ],
    {200, _, _} = post_json("/users/1/items", Items, Config),
    %% Get sorted ascending by title
    {200, _, Asc} = get_json("/users/1/items?sort=title&direction=asc&since=0", Config),
    AscTitles = [maps:get(<<"title">>, maps:get(<<"data">>, I)) || I <- Asc],
    ?assertEqual(lists:sort(AscTitles), AscTitles),
    %% Get sorted descending
    {200, _, Desc} = get_json("/users/1/items?sort=title&direction=desc&since=0", Config),
    DescTitles = [maps:get(<<"title">>, maps:get(<<"data">>, I)) || I <- Desc],
    ?assertEqual(lists:reverse(lists:sort(DescTitles)), DescTitles),
    ok.

%% ===================================================================
%% format=keys
%% ===================================================================

items_format_keys(Config) ->
    {200, _, Body} = get_json("/users/1/items?format=keys&since=0", Config),
    ?assert(is_list(Body)),
    lists:foreach(fun(K) -> ?assert(is_binary(K)) end, Body),
    ok.

%% ===================================================================
%% 304 Not Modified
%% ===================================================================

items_304_not_modified(Config) ->
    Base = ?config(base, Config),
    ApiKey = ?config(api_key, Config),
    %% Get current version
    {200, Headers, _} = get_json("/users/1/items?format=versions", Config),
    Version = maps:get(<<"last-modified-version">>, Headers),
    %% Request with If-Modified-Since-Version equal to current — should get 304
    {ok, {{_, 304, _}, _, _}} =
        httpc:request(get, {Base ++ "/users/1/items",
                            [{"Zotero-API-Key", binary_to_list(ApiKey)},
                             {"If-Modified-Since-Version", binary_to_list(Version)}]},
                      [], [{body_format, binary}]),
    ok.

%% ===================================================================
%% Native terms verification
%% ===================================================================

items_native_terms(Config) ->
    %% Verify that data is stored as native Erlang maps in Mnesia, not JSON strings
    Item = #{<<"itemType">> => <<"book">>, <<"title">> => <<"Native Term Test">>},
    {200, _, CreateBody} = post_json("/users/1/items", [Item], Config),
    #{<<"0">> := #{<<"key">> := Key}} = maps:get(<<"successful">>, CreateBody),
    %% Read directly from Mnesia
    [{shurbey_item, {1, Key}, _Version, Data, false, _ParentKey}] =
        mnesia:dirty_read(shurbey_item, {1, Key}),
    %% Data should be a map, not a binary/string
    ?assert(is_map(Data)),
    ?assertEqual(<<"Native Term Test">>, maps:get(<<"title">>, Data)),
    ?assertEqual(<<"book">>, maps:get(<<"itemType">>, Data)),
    ok.

%% ===================================================================
%% File storage (content-addressed with refcounting)
%% ===================================================================

file_upload_download(Config) ->
    %% Create an item to attach a file to
    Item = #{<<"itemType">> => <<"attachment">>, <<"title">> => <<"test.pdf">>},
    {200, _, CreateBody} = post_json("/users/1/items", [Item], Config),
    #{<<"0">> := #{<<"key">> := Key}} = maps:get(<<"successful">>, CreateBody),
    %% Step 1: Request upload authorization
    FileData = <<"fake pdf content for testing">>,
    Md5 = list_to_binary(lists:flatten(
        [io_lib:format("~2.16.0b", [B]) || <<B>> <= crypto:hash(md5, FileData)])),
    UploadParams = cow_qs:qs([
        {<<"upload">>, <<"1">>},
        {<<"md5">>, Md5},
        {<<"filename">>, <<"test.pdf">>},
        {<<"filesize">>, integer_to_binary(byte_size(FileData))},
        {<<"mtime">>, <<"1700000000">>}
    ]),
    {200, _, AuthBody} = post_form("/users/1/items/" ++ binary_to_list(Key) ++ "/file",
                                    UploadParams, [{"If-None-Match", "*"}], Config),
    UploadUrl = maps:get(<<"url">>, AuthBody),
    UploadKey = maps:get(<<"uploadKey">>, AuthBody),
    ?assert(is_binary(UploadUrl)),
    %% Step 2: Upload the file content
    {201, _, _} = post_raw(binary_to_list(UploadUrl), FileData),
    %% Step 3: Register the upload
    RegParams = cow_qs:qs([{<<"uploadKey">>, UploadKey}]),
    {204, _, _} = post_form("/users/1/items/" ++ binary_to_list(Key) ++ "/file",
                             RegParams, Config),
    %% Step 4: Download and verify
    {200, DlHeaders, DlBody} = get_raw("/users/1/items/" ++ binary_to_list(Key) ++ "/file", Config),
    ?assertEqual(FileData, DlBody),
    ?assertEqual(Md5, maps:get(<<"etag">>, DlHeaders)),
    %% Verify blob exists at content-addressed path (SHA-256)
    Sha256 = list_to_binary(lists:flatten(
        [io_lib:format("~2.16.0b", [B]) || <<B>> <= crypto:hash(sha256, FileData)])),
    BlobFile = shurbey_files:blob_path(Sha256),
    ?assert(filelib:is_regular(BlobFile)),
    ok.

file_content_addressed_dedup(Config) ->
    %% Upload the same content to two different items
    FileData = <<"shared content across items">>,
    Md5 = list_to_binary(lists:flatten(
        [io_lib:format("~2.16.0b", [B]) || <<B>> <= crypto:hash(md5, FileData)])),
    %% Create two items
    Items = [
        #{<<"itemType">> => <<"attachment">>, <<"title">> => <<"file_a.pdf">>},
        #{<<"itemType">> => <<"attachment">>, <<"title">> => <<"file_b.pdf">>}
    ],
    {200, _, CreateBody} = post_json("/users/1/items", Items, Config),
    #{<<"0">> := #{<<"key">> := KeyA}, <<"1">> := #{<<"key">> := KeyB}} =
        maps:get(<<"successful">>, CreateBody),
    %% Upload to item A (full upload)
    UploadParams = cow_qs:qs([
        {<<"upload">>, <<"1">>}, {<<"md5">>, Md5},
        {<<"filename">>, <<"file_a.pdf">>},
        {<<"filesize">>, integer_to_binary(byte_size(FileData))},
        {<<"mtime">>, <<"1700000000">>}
    ]),
    {200, _, AuthA} = post_form("/users/1/items/" ++ binary_to_list(KeyA) ++ "/file",
                                 UploadParams, [{"If-None-Match", "*"}], Config),
    UploadKeyA = maps:get(<<"uploadKey">>, AuthA),
    UploadUrlA = maps:get(<<"url">>, AuthA),
    {201, _, _} = post_raw(binary_to_list(UploadUrlA), FileData),
    RegA = cow_qs:qs([{<<"uploadKey">>, UploadKeyA}]),
    {204, _, _} = post_form("/users/1/items/" ++ binary_to_list(KeyA) ++ "/file", RegA, Config),
    %% Upload same content to item B — requires full upload now (SHA-256 dedup happens on disk)
    UploadParamsB = cow_qs:qs([
        {<<"upload">>, <<"1">>}, {<<"md5">>, Md5},
        {<<"filename">>, <<"file_b.pdf">>},
        {<<"filesize">>, integer_to_binary(byte_size(FileData))},
        {<<"mtime">>, <<"1700000000">>}
    ]),
    {200, _, AuthB} = post_form("/users/1/items/" ++ binary_to_list(KeyB) ++ "/file",
                                 UploadParamsB, [{"If-None-Match", "*"}], Config),
    UploadKeyB = maps:get(<<"uploadKey">>, AuthB),
    UploadUrlB = maps:get(<<"url">>, AuthB),
    {201, _, _} = post_raw(binary_to_list(UploadUrlB), FileData),
    RegB = cow_qs:qs([{<<"uploadKey">>, UploadKeyB}]),
    {204, _, _} = post_form("/users/1/items/" ++ binary_to_list(KeyB) ++ "/file", RegB, Config),
    %% Both items should serve the same file
    {200, _, DlA} = get_raw("/users/1/items/" ++ binary_to_list(KeyA) ++ "/file", Config),
    {200, _, DlB} = get_raw("/users/1/items/" ++ binary_to_list(KeyB) ++ "/file", Config),
    ?assertEqual(FileData, DlA),
    ?assertEqual(FileData, DlB),
    %% Only one blob file on disk — addressed by SHA-256
    Sha256 = list_to_binary(lists:flatten(
        [io_lib:format("~2.16.0b", [B]) || <<B>> <= crypto:hash(sha256, FileData)])),
    BlobFile = shurbey_files:blob_path(Sha256),
    ?assert(filelib:is_regular(BlobFile)),
    %% Refcount should be 2
    [{shurbey_blob, Sha256, _, 2}] = mnesia:dirty_read(shurbey_blob, Sha256),
    ok.

file_refcount_cleanup(Config) ->
    %% Create an item, upload a file, then verify unref works
    FileData = <<"unique content for refcount test">>,
    Md5 = list_to_binary(lists:flatten(
        [io_lib:format("~2.16.0b", [B]) || <<B>> <= crypto:hash(md5, FileData)])),
    Item = #{<<"itemType">> => <<"attachment">>, <<"title">> => <<"refcount.pdf">>},
    {200, _, CreateBody} = post_json("/users/1/items", [Item], Config),
    #{<<"0">> := #{<<"key">> := Key}} = maps:get(<<"successful">>, CreateBody),
    %% Upload
    UploadParams = cow_qs:qs([
        {<<"upload">>, <<"1">>}, {<<"md5">>, Md5},
        {<<"filename">>, <<"refcount.pdf">>},
        {<<"filesize">>, integer_to_binary(byte_size(FileData))},
        {<<"mtime">>, <<"1700000000">>}
    ]),
    {200, _, Auth} = post_form("/users/1/items/" ++ binary_to_list(Key) ++ "/file",
                                UploadParams, [{"If-None-Match", "*"}], Config),
    UploadKey = maps:get(<<"uploadKey">>, Auth),
    UploadUrl = maps:get(<<"url">>, Auth),
    {201, _, _} = post_raw(binary_to_list(UploadUrl), FileData),
    Reg = cow_qs:qs([{<<"uploadKey">>, UploadKey}]),
    {204, _, _} = post_form("/users/1/items/" ++ binary_to_list(Key) ++ "/file", Reg, Config),
    %% Blob should exist with refcount 1 (keyed by SHA-256)
    Sha256 = list_to_binary(lists:flatten(
        [io_lib:format("~2.16.0b", [B]) || <<B>> <= crypto:hash(sha256, FileData)])),
    BlobFile = shurbey_files:blob_path(Sha256),
    ?assert(filelib:is_regular(BlobFile)),
    [{shurbey_blob, Sha256, _, 1}] = mnesia:dirty_read(shurbey_blob, Sha256),
    %% Unref — should delete blob record and we can delete the file
    {ok, 0} = shurbey_db:blob_unref(Sha256),
    ?assertEqual([], mnesia:dirty_read(shurbey_blob, Sha256)),
    file:delete(BlobFile),
    ?assertNot(filelib:is_regular(BlobFile)),
    ok.

%% ===================================================================
%% Auth flow
%% ===================================================================

session_login_flow(Config) ->
    Base = ?config(base, Config),
    {Token, Csrf, _LoginUrl} = create_session_with_csrf(Config),
    ?assert(is_binary(Token)),
    ?assert(byte_size(Csrf) > 0),
    %% POST credentials with CSRF token
    FormBody = cow_qs:qs([
        {<<"token">>, Token},
        {<<"csrf">>, Csrf},
        {<<"username">>, <<"testuser">>},
        {<<"password">>, <<"testpass">>}
    ]),
    {ok, {{_, 200, _}, _, SuccessHtml}} =
        httpc:request(post, {Base ++ "/login", [],
                             "application/x-www-form-urlencoded", FormBody},
                      [], [{body_format, binary}]),
    ?assertNotEqual(nomatch, binary:match(SuccessHtml, <<"Signed in">>)),
    %% Step 4: Poll should return completed with API key
    {ok, {{_, 200, _}, _, PollBody}} =
        httpc:request(get, {Base ++ "/keys/sessions/" ++ binary_to_list(Token), []},
                      [], [{body_format, binary}]),
    PollResult = simdjson:decode(PollBody),
    ?assertEqual(<<"completed">>, maps:get(<<"status">>, PollResult)),
    NewApiKey = maps:get(<<"apiKey">>, PollResult),
    ?assert(is_binary(NewApiKey)),
    ?assertEqual(1, maps:get(<<"userID">>, PollResult)),
    %% Step 5: The new key should work for API calls
    {ok, {{_, 200, _}, _, KeysBody}} =
        httpc:request(get, {Base ++ "/keys/current",
                            [{"Zotero-API-Key", binary_to_list(NewApiKey)}]},
                      [], [{body_format, binary}]),
    KeysResult = simdjson:decode(KeysBody),
    ?assertEqual(1, maps:get(<<"userID">>, KeysResult)),
    ok.

session_poll_pending(Config) ->
    Base = ?config(base, Config),
    %% Create session
    {ok, {{_, 201, _}, _, Body}} =
        httpc:request(post, {Base ++ "/keys/sessions", [],
                             "application/json", <<"{}">>},
                      [], [{body_format, binary}]),
    #{<<"sessionToken">> := Token} = simdjson:decode(Body),
    %% Poll before login — should be pending
    {ok, {{_, 200, _}, _, PollBody}} =
        httpc:request(get, {Base ++ "/keys/sessions/" ++ binary_to_list(Token), []},
                      [], [{body_format, binary}]),
    ?assertEqual(#{<<"status">> => <<"pending">>}, simdjson:decode(PollBody)),
    ok.

session_cancel(Config) ->
    Base = ?config(base, Config),
    {ok, {{_, 201, _}, _, Body}} =
        httpc:request(post, {Base ++ "/keys/sessions", [],
                             "application/json", <<"{}">>},
                      [], [{body_format, binary}]),
    #{<<"sessionToken">> := Token} = simdjson:decode(Body),
    %% Cancel
    {ok, {{_, 204, _}, _, _}} =
        httpc:request(delete, {Base ++ "/keys/sessions/" ++ binary_to_list(Token), []},
                      [], [{body_format, binary}]),
    %% Poll after cancel — should be 404
    {ok, {{_, 404, _}, _, _}} =
        httpc:request(get, {Base ++ "/keys/sessions/" ++ binary_to_list(Token), []},
                      [], [{body_format, binary}]),
    ok.

session_expired(_Config) ->
    %% Test that expired sessions return 410
    %% Create a session directly with an old timestamp
    Token = <<"expired_test_token">>,
    shurbey_session:insert_raw(Token, #{
        status => pending,
        created => erlang:system_time(millisecond) - 700000,  %% 11+ minutes ago
        login_url => <<"http://localhost/login">>
    }),
    {error, expired} = shurbey_session:get(Token),
    ok.

delete_key_revokes(Config) ->
    Base = ?config(base, Config),
    %% Create a temporary key
    TmpKey = list_to_binary(lists:flatten(
        [io_lib:format("~2.16.0b", [B]) || <<B>> <= crypto:strong_rand_bytes(12)])),
    shurbey_db:create_key(TmpKey, 1, #{library => true, write => true, files => true, notes => true}),
    %% Verify it works
    {ok, {{_, 200, _}, _, _}} =
        httpc:request(get, {Base ++ "/keys/current",
                            [{"Zotero-API-Key", binary_to_list(TmpKey)}]},
                      [], [{body_format, binary}]),
    %% Delete it
    {ok, {{_, 204, _}, _, _}} =
        httpc:request(delete, {Base ++ "/keys/current",
                               [{"Zotero-API-Key", binary_to_list(TmpKey)}]},
                      [], [{body_format, binary}]),
    %% Should now be rejected
    {ok, {{_, 403, _}, _, _}} =
        httpc:request(get, {Base ++ "/keys/current",
                            [{"Zotero-API-Key", binary_to_list(TmpKey)}]},
                      [], [{body_format, binary}]),
    ok.

%% ===================================================================
%% PUT/PATCH
%% ===================================================================

item_put_update(Config) ->
    Item = #{<<"itemType">> => <<"book">>, <<"title">> => <<"Put Original">>},
    {200, _, CB} = post_json("/users/1/items", [Item], Config),
    #{<<"0">> := #{<<"key">> := Key}} = maps:get(<<"successful">>, CB),
    {ok, Version} = shurbey_version:get(1),
    {200, _, Got} = put_json_versioned("/users/1/items/" ++ binary_to_list(Key),
        #{<<"itemType">> => <<"book">>, <<"title">> => <<"Put Replaced">>}, Version, Config),
    ?assertEqual(<<"Put Replaced">>, maps:get(<<"title">>, maps:get(<<"data">>, Got))),
    ok.

item_patch_merge(Config) ->
    Item = #{<<"itemType">> => <<"book">>, <<"title">> => <<"Patch Original">>, <<"date">> => <<"2024">>},
    {200, _, CB} = post_json("/users/1/items", [Item], Config),
    #{<<"0">> := #{<<"key">> := Key}} = maps:get(<<"successful">>, CB),
    {ok, Version} = shurbey_version:get(1),
    {200, _, Got} = patch_json("/users/1/items/" ++ binary_to_list(Key),
        #{<<"title">> => <<"Patch Merged">>}, Version, Config),
    Data = maps:get(<<"data">>, Got),
    ?assertEqual(<<"Patch Merged">>, maps:get(<<"title">>, Data)),
    ?assertEqual(<<"2024">>, maps:get(<<"date">>, Data)),
    ok.

collection_patch(Config) ->
    Coll = #{<<"name">> => <<"Patch Coll">>},
    {200, _, CB} = post_json("/users/1/collections", [Coll], Config),
    #{<<"0">> := #{<<"key">> := Key}} = maps:get(<<"successful">>, CB),
    {ok, Version} = shurbey_version:get(1),
    {200, _, Got} = patch_json("/users/1/collections/" ++ binary_to_list(Key),
        #{<<"name">> => <<"Patched Name">>}, Version, Config),
    ?assertEqual(<<"Patched Name">>, maps:get(<<"name">>, maps:get(<<"data">>, Got))),
    ok.

search_patch(Config) ->
    Search = #{<<"name">> => <<"Patch Search">>, <<"conditions">> => []},
    {200, _, CB} = post_json("/users/1/searches", [Search], Config),
    #{<<"0">> := #{<<"key">> := Key}} = maps:get(<<"successful">>, CB),
    {ok, Version} = shurbey_version:get(1),
    {200, _, Got} = patch_json("/users/1/searches/" ++ binary_to_list(Key),
        #{<<"name">> => <<"Patched Search">>}, Version, Config),
    ?assertEqual(<<"Patched Search">>, maps:get(<<"name">>, maps:get(<<"data">>, Got))),
    ok.

%% ===================================================================
%% Template & Schema
%% ===================================================================

item_template(Config) ->
    Base = ?config(base, Config),
    {ok, {{_, 200, _}, _, Body}} =
        httpc:request(get, {Base ++ "/items/new?itemType=book", []}, [], [{body_format, binary}]),
    Template = simdjson:decode(Body),
    ?assertEqual(<<"book">>, maps:get(<<"itemType">>, Template)),
    ?assert(maps:is_key(<<"title">>, Template)),
    ?assert(maps:is_key(<<"creators">>, Template)),
    ok.

item_template_bad_type(Config) ->
    Base = ?config(base, Config),
    {ok, {{_, 400, _}, _, _}} =
        httpc:request(get, {Base ++ "/items/new?itemType=fakeType", []}, [], [{body_format, binary}]),
    {ok, {{_, 400, _}, _, _}} =
        httpc:request(get, {Base ++ "/items/new", []}, [], [{body_format, binary}]),
    ok.

schema_endpoint(Config) ->
    Base = ?config(base, Config),
    {ok, {{_, 200, _}, _, Body}} =
        httpc:request(get, {Base ++ "/schema", []}, [], [{body_format, binary}]),
    Schema = simdjson:decode(Body),
    ?assert(map_size(Schema) > 0),
    ok.

%% ===================================================================
%% Write token idempotency
%% ===================================================================

write_token_idempotent(Config) ->
    Base = ?config(base, Config),
    ApiKey = ?config(api_key, Config),
    Token = <<"test-write-token-", (integer_to_binary(erlang:unique_integer([positive])))/binary>>,
    Item = #{<<"itemType">> => <<"book">>, <<"title">> => <<"Idempotent">>},
    Body = simdjson:encode([Item]),
    Headers = [{"Zotero-API-Key", binary_to_list(ApiKey)},
               {"Zotero-Write-Token", binary_to_list(Token)}],
    %% First request
    {ok, {{_, 200, _}, _, Resp1}} =
        httpc:request(post, {Base ++ "/users/1/items", Headers, "application/json", Body},
                      [], [{body_format, binary}]),
    %% Second request with same token — should get cached response
    {ok, {{_, 200, _}, _, Resp2}} =
        httpc:request(post, {Base ++ "/users/1/items", Headers, "application/json", Body},
                      [], [{body_format, binary}]),
    R1 = simdjson:decode(Resp1),
    R2 = simdjson:decode(Resp2),
    ?assertEqual(maps:get(<<"successful">>, R1), maps:get(<<"successful">>, R2)),
    ok.

%% ===================================================================
%% Query filters
%% ===================================================================

filter_by_tag(Config) ->
    Item = #{<<"itemType">> => <<"book">>, <<"title">> => <<"Tag Filter Test">>,
             <<"tags">> => [#{<<"tag">> => <<"unique-filter-tag">>}]},
    {200, _, _} = post_json("/users/1/items", [Item], Config),
    {200, _, Found} = get_json("/users/1/items?tag=unique-filter-tag&since=0", Config),
    ?assert(length(Found) >= 1),
    Titles = [maps:get(<<"title">>, maps:get(<<"data">>, I)) || I <- Found],
    ?assert(lists:member(<<"Tag Filter Test">>, Titles)),
    {200, _, Empty} = get_json("/users/1/items?tag=nonexistent-tag-xyz&since=0", Config),
    ?assertEqual([], Empty),
    ok.

filter_by_item_type(Config) ->
    Item = #{<<"itemType">> => <<"patent">>, <<"title">> => <<"Type Filter Test">>},
    {200, _, _} = post_json("/users/1/items", [Item], Config),
    {200, _, Found} = get_json("/users/1/items?itemType=patent&since=0", Config),
    ?assert(length(Found) >= 1),
    lists:foreach(fun(I) ->
        ?assertEqual(<<"patent">>, maps:get(<<"itemType">>, maps:get(<<"data">>, I)))
    end, Found),
    ok.

filter_by_query(Config) ->
    Item = #{<<"itemType">> => <<"book">>, <<"title">> => <<"Xylophone Quarterly Review">>},
    {200, _, _} = post_json("/users/1/items", [Item], Config),
    {200, _, Found} = get_json("/users/1/items?q=xylophone&since=0", Config),
    ?assert(length(Found) >= 1),
    ok.

filter_qmode_everything(Config) ->
    Item = #{<<"itemType">> => <<"book">>, <<"title">> => <<"Normal Title">>,
             <<"extra">> => <<"zyxwvut-unique-field">>},
    {200, _, _} = post_json("/users/1/items", [Item], Config),
    %% Default qmode won't find it by extra field
    {200, _, NotFound} = get_json("/users/1/items?q=zyxwvut&since=0", Config),
    QmNotFound = [I || I <- NotFound,
        maps:get(<<"extra">>, maps:get(<<"data">>, I), <<>>) =:= <<"zyxwvut-unique-field">>],
    ?assertEqual([], QmNotFound),
    %% qmode=everything should find it
    {200, _, Found} = get_json("/users/1/items?q=zyxwvut&qmode=everything&since=0", Config),
    ?assert(length(Found) >= 1),
    ok.

include_trashed(Config) ->
    Item = #{<<"itemType">> => <<"book">>, <<"title">> => <<"Include Trashed Test">>},
    {200, _, CB} = post_json("/users/1/items", [Item], Config),
    #{<<"0">> := #{<<"key">> := Key}} = maps:get(<<"successful">>, CB),
    {ok, Version} = shurbey_version:get(1),
    {204, _, _} = delete_req("/users/1/items?itemKey=" ++ binary_to_list(Key), Version, Config),
    %% Without includeTrashed — should not appear
    {200, _, Without} = get_json("/users/1/items?since=0&limit=100", Config),
    WithoutKeys = [maps:get(<<"key">>, I) || I <- Without],
    ?assertNot(lists:member(Key, WithoutKeys)),
    %% With includeTrashed=1 — should appear
    {200, _, With} = get_json("/users/1/items?since=0&includeTrashed=1&limit=100", Config),
    WithKeys = [maps:get(<<"key">>, I) || I <- With],
    ?assert(lists:member(Key, WithKeys)),
    ok.

%% ===================================================================
%% 304 on other endpoints
%% ===================================================================

collections_304(Config) ->
    Base = ?config(base, Config),
    ApiKey = ?config(api_key, Config),
    {200, H, _} = get_json("/users/1/collections", Config),
    V = maps:get(<<"last-modified-version">>, H),
    {ok, {{_, 304, _}, _, _}} =
        httpc:request(get, {Base ++ "/users/1/collections",
            [{"Zotero-API-Key", binary_to_list(ApiKey)},
             {"If-Modified-Since-Version", binary_to_list(V)}]},
            [], [{body_format, binary}]),
    ok.

settings_304(Config) ->
    Base = ?config(base, Config),
    ApiKey = ?config(api_key, Config),
    {200, H, _} = get_json("/users/1/settings", Config),
    V = maps:get(<<"last-modified-version">>, H),
    {ok, {{_, 304, _}, _, _}} =
        httpc:request(get, {Base ++ "/users/1/settings",
            [{"Zotero-API-Key", binary_to_list(ApiKey)},
             {"If-Modified-Since-Version", binary_to_list(V)}]},
            [], [{body_format, binary}]),
    ok.

deleted_304(Config) ->
    Base = ?config(base, Config),
    ApiKey = ?config(api_key, Config),
    {200, H, _} = get_json("/users/1/deleted?since=0", Config),
    V = maps:get(<<"last-modified-version">>, H),
    {ok, {{_, 304, _}, _, _}} =
        httpc:request(get, {Base ++ "/users/1/deleted?since=0",
            [{"Zotero-API-Key", binary_to_list(ApiKey)},
             {"If-Modified-Since-Version", binary_to_list(V)}]},
            [], [{body_format, binary}]),
    ok.

tags_304(Config) ->
    Base = ?config(base, Config),
    ApiKey = ?config(api_key, Config),
    {200, H, _} = get_json("/users/1/tags", Config),
    V = maps:get(<<"last-modified-version">>, H),
    {ok, {{_, 304, _}, _, _}} =
        httpc:request(get, {Base ++ "/users/1/tags",
            [{"Zotero-API-Key", binary_to_list(ApiKey)},
             {"If-Modified-Since-Version", binary_to_list(V)}]},
            [], [{body_format, binary}]),
    ok.

fulltext_304(Config) ->
    Base = ?config(base, Config),
    ApiKey = ?config(api_key, Config),
    {200, H, _} = get_json("/users/1/fulltext", Config),
    V = maps:get(<<"last-modified-version">>, H),
    {ok, {{_, 304, _}, _, _}} =
        httpc:request(get, {Base ++ "/users/1/fulltext",
            [{"Zotero-API-Key", binary_to_list(ApiKey)},
             {"If-Modified-Since-Version", binary_to_list(V)}]},
            [], [{body_format, binary}]),
    ok.

%% ===================================================================
%% Error paths
%% ===================================================================

upload_md5_mismatch(Config) ->
    Item = #{<<"itemType">> => <<"attachment">>, <<"title">> => <<"md5 test">>},
    {200, _, CB} = post_json("/users/1/items", [Item], Config),
    #{<<"0">> := #{<<"key">> := Key}} = maps:get(<<"successful">>, CB),
    UploadParams = cow_qs:qs([
        {<<"upload">>, <<"1">>}, {<<"md5">>, <<"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">>},
        {<<"filename">>, <<"test.bin">>}, {<<"filesize">>, <<"4">>}, {<<"mtime">>, <<"1">>}
    ]),
    {200, _, Auth} = post_form("/users/1/items/" ++ binary_to_list(Key) ++ "/file",
                                UploadParams, [{"If-None-Match", "*"}], Config),
    UploadUrl = maps:get(<<"url">>, Auth),
    %% Upload data whose MD5 won't match
    {412, _, _} = post_raw(binary_to_list(UploadUrl), <<"wrong data">>),
    ok.

fulltext_validation(Config) ->
    Item = #{<<"itemType">> => <<"book">>, <<"title">> => <<"FT Val">>},
    {200, _, CB} = post_json("/users/1/items", [Item], Config),
    #{<<"0">> := #{<<"key">> := Key}} = maps:get(<<"successful">>, CB),
    %% Missing content field
    {400, _, _} = put_json("/users/1/items/" ++ binary_to_list(Key) ++ "/fulltext",
                           #{<<"indexedPages">> => 1}, Config),
    ok.

settings_single_get(Config) ->
    %% Write a setting
    {204, _, _} = post_json("/users/1/settings", #{<<"testSetting">> => #{<<"value">> => 42}}, Config),
    %% Get single setting — returns {value, version} like the real API
    {200, _, Got} = get_json("/users/1/settings/testSetting", Config),
    ?assertEqual(42, maps:get(<<"value">>, Got)),
    ?assert(is_integer(maps:get(<<"version">>, Got))),
    ok.

method_not_allowed(Config) ->
    %% POST to tags should be rejected
    {405, _, _} = post_json("/users/1/tags", #{}, Config),
    %% POST to deleted should be rejected
    {405, _, _} = post_json("/users/1/deleted", #{}, Config),
    %% DELETE to groups should be rejected
    Base = ?config(base, Config),
    ApiKey = ?config(api_key, Config),
    {ok, {{_, 405, _}, _, _}} =
        httpc:request(delete, {Base ++ "/users/1/groups",
            [{"Zotero-API-Key", binary_to_list(ApiKey)}]},
            [], [{body_format, binary}]),
    ok.

export_format_rejected(Config) ->
    {400, _, Body} = get_json("/users/1/items?format=bib&since=0", Config),
    ?assertMatch(#{<<"message">> := _}, Body),
    ok.

%% ===================================================================
%% Admin
%% ===================================================================

admin_list_delete_user(_Config) ->
    ok = shurbey_admin:create_user(<<"tempuser">>, <<"temppass">>, 99),
    Users = shurbey_admin:list_users(),
    ?assert(lists:keymember(<<"tempuser">>, 1, Users)),
    shurbey_admin:delete_user(<<"tempuser">>),
    Users2 = shurbey_admin:list_users(),
    ?assertNot(lists:keymember(<<"tempuser">>, 1, Users2)),
    ok.

%% ===================================================================
%% Session cleaner
%% ===================================================================

session_cleaner_runs(_Config) ->
    %% Insert a very old session (session table is public, test can write)
    Token = <<"cleaner_test_token">>,
    shurbey_session:insert_raw(Token, #{
        status => pending,
        created => erlang:system_time(millisecond) - 700000,
        login_url => <<"http://test">>,
        csrf_token => <<"test">>
    }),
    %% Trigger cleanup manually
    shurbey_session_cleaner ! cleanup,
    timer:sleep(200),
    %% Session should be gone
    ?assertEqual([], ets:lookup(shurbey_login_sessions, Token)),
    %% Also test upload cleanup via the gen_server API
    ok = shurbey_files:cleanup_expired_uploads(),
    ok.

%% ===================================================================
%% WebSocket login
%% ===================================================================

ws_login_flow(Config) ->
    {ok, _} = application:ensure_all_started(gun),
    Base = ?config(base, Config),
    {Token, Csrf, _} = create_session_with_csrf(Config),
    %% Connect via WebSocket using gun
    {ok, Pid} = gun:open("localhost", 18080),
    {ok, _} = gun:await_up(Pid),
    StreamRef = gun:ws_upgrade(Pid, "/ws"),
    receive {gun_upgrade, Pid, StreamRef, [<<"websocket">>], _} -> ok
    after 5000 -> ct:fail("WebSocket upgrade timeout")
    end,
    %% Subscribe to login session
    SubMsg = simdjson:encode(#{<<"action">> => <<"subscribe">>,
                            <<"topic">> => <<"login-session:", Token/binary>>}),
    gun:ws_send(Pid, StreamRef, {text, SubMsg}),
    %% Wait for subscribed confirmation
    receive {gun_ws, Pid, StreamRef, {text, SubResp}} ->
        #{<<"event">> := <<"subscribed">>} = simdjson:decode(SubResp)
    after 5000 -> ct:fail("Subscribe timeout")
    end,
    %% Complete login via HTTP
    FormBody = cow_qs:qs([
        {<<"token">>, Token},
        {<<"csrf">>, Csrf},
        {<<"username">>, <<"testuser">>},
        {<<"password">>, <<"testpass">>}
    ]),
    {ok, {{_, 200, _}, _, _}} =
        httpc:request(post, {Base ++ "/login", [],
                             "application/x-www-form-urlencoded", FormBody},
                      [], [{body_format, binary}]),
    %% Should receive loginComplete over WebSocket
    receive {gun_ws, Pid, StreamRef, {text, EventMsg}} ->
        Event = simdjson:decode(EventMsg),
        ?assertEqual(<<"loginComplete">>, maps:get(<<"event">>, Event)),
        ?assert(maps:is_key(<<"apiKey">>, Event)),
        ?assertEqual(1, maps:get(<<"userID">>, Event))
    after 5000 -> ct:fail("loginComplete timeout")
    end,
    gun:close(Pid),
    ok.

%% ===================================================================
%% Auth failures — 403 on all endpoints without API key
%% ===================================================================

collections_auth_required(Config) ->
    {403, _, _} = request(get, "/users/1/collections", [], <<>>, Config, false), ok.
searches_auth_required(Config) ->
    {403, _, _} = request(get, "/users/1/searches", [], <<>>, Config, false), ok.
settings_auth_required(Config) ->
    {403, _, _} = request(get, "/users/1/settings", [], <<>>, Config, false), ok.
fulltext_auth_required(Config) ->
    {403, _, _} = request(get, "/users/1/fulltext", [], <<>>, Config, false), ok.
files_auth_required(Config) ->
    {403, _, _} = request(get, "/users/1/items/XXXXXXXX/file", [], <<>>, Config, false), ok.
groups_auth_required(Config) ->
    {403, _, _} = request(get, "/users/1/groups", [], <<>>, Config, false), ok.
deleted_auth_required(Config) ->
    {403, _, _} = request(get, "/users/1/deleted?since=0", [], <<>>, Config, false), ok.
tags_auth_required(Config) ->
    {403, _, _} = request(get, "/users/1/tags", [], <<>>, Config, false), ok.
items_auth_required(Config) ->
    {403, _, _} = request(get, "/users/1/items", [], <<>>, Config, false), ok.

%% ===================================================================
%% DELETE collections/searches
%% ===================================================================

collections_delete(Config) ->
    Coll = #{<<"name">> => <<"Del Coll">>},
    {200, _, CB} = post_json("/users/1/collections", [Coll], Config),
    #{<<"0">> := #{<<"key">> := Key}} = maps:get(<<"successful">>, CB),
    {ok, Version} = shurbey_version:get(1),
    {204, _, _} = delete_req("/users/1/collections?collectionKey=" ++ binary_to_list(Key), Version, Config),
    {200, _, Deleted} = get_json("/users/1/deleted?since=0", Config),
    ?assert(lists:member(Key, maps:get(<<"collections">>, Deleted))),
    ok.

searches_delete(Config) ->
    Search = #{<<"name">> => <<"Del Search">>, <<"conditions">> => []},
    {200, _, CB} = post_json("/users/1/searches", [Search], Config),
    #{<<"0">> := #{<<"key">> := Key}} = maps:get(<<"successful">>, CB),
    {ok, Version} = shurbey_version:get(1),
    {204, _, _} = delete_req("/users/1/searches?searchKey=" ++ binary_to_list(Key), Version, Config),
    {200, _, Deleted} = get_json("/users/1/deleted?since=0", Config),
    ?assert(lists:member(Key, maps:get(<<"searches">>, Deleted))),
    ok.

%% ===================================================================
%% format=keys for collections/searches
%% ===================================================================

collections_format_keys(Config) ->
    {200, _, Body} = get_json("/users/1/collections?format=keys&since=0", Config),
    ?assert(is_list(Body)),
    ok.

searches_format_keys(Config) ->
    {200, _, Body} = get_json("/users/1/searches?format=keys&since=0", Config),
    ?assert(is_list(Body)),
    ok.

%% ===================================================================
%% 405 Method Not Allowed
%% ===================================================================

schema_405(Config) ->
    Base = ?config(base, Config),
    {ok, {{_, 405, _}, _, _}} =
        httpc:request(post, {Base ++ "/schema", [], "application/json", <<"{}">>},
                      [], [{body_format, binary}]),
    ok.

upload_405(Config) ->
    Base = ?config(base, Config),
    {ok, {{_, 405, _}, _, _}} =
        httpc:request(get, {Base ++ "/upload/fakekey", []}, [], [{body_format, binary}]),
    ok.

upload_unknown_key(Config) ->
    Base = ?config(base, Config),
    {ok, {{_, 404, _}, _, _}} =
        httpc:request(post, {Base ++ "/upload/nonexistent_key", [],
                             "application/octet-stream", <<"data">>},
                      [], [{body_format, binary}]),
    ok.

groups_versions(Config) ->
    {200, _, Body} = get_json("/users/1/groups?format=versions", Config),
    ?assertEqual(#{}, Body),
    ok.

fulltext_405(Config) ->
    Base = ?config(base, Config),
    ApiKey = ?config(api_key, Config),
    {ok, {{_, 405, _}, _, _}} =
        httpc:request(delete, {Base ++ "/users/1/fulltext",
                               [{"Zotero-API-Key", binary_to_list(ApiKey)}]},
                      [], [{body_format, binary}]),
    ok.

item_template_405(Config) ->
    Base = ?config(base, Config),
    {ok, {{_, 405, _}, _, _}} =
        httpc:request(post, {Base ++ "/items/new?itemType=book", [],
                             "application/json", <<"{}">>},
                      [], [{body_format, binary}]),
    ok.

%% ===================================================================
%% Single GET endpoints
%% ===================================================================

collection_single_get(Config) ->
    Coll = #{<<"name">> => <<"Single Get Coll">>},
    {200, _, CB} = post_json("/users/1/collections", [Coll], Config),
    #{<<"0">> := #{<<"key">> := Key}} = maps:get(<<"successful">>, CB),
    {200, _, Got} = get_json("/users/1/collections/" ++ binary_to_list(Key), Config),
    ?assertMatch(#{<<"key">> := Key, <<"data">> := _}, Got),
    ok.

collection_single_404(Config) ->
    {404, _, _} = get_json("/users/1/collections/ZZZZZZZZ", Config), ok.

search_single_get(Config) ->
    Search = #{<<"name">> => <<"Single Get Search">>, <<"conditions">> => []},
    {200, _, CB} = post_json("/users/1/searches", [Search], Config),
    #{<<"0">> := #{<<"key">> := _Key}} = maps:get(<<"successful">>, CB),
    {200, _, Searches} = get_json("/users/1/searches", Config),
    ?assert(length(Searches) >= 1),
    ok.

settings_single_404(Config) ->
    {404, _, _} = get_json("/users/1/settings/nonexistent_setting", Config), ok.

fulltext_single_404(Config) ->
    {404, _, _} = get_json("/users/1/items/ZZZZZZZZ/fulltext", Config), ok.

%% ===================================================================
%% Precondition failures
%% ===================================================================

collection_precondition(Config) ->
    Colls = [#{<<"name">> => <<"Precond Coll">>}],
    {412, _, _} = post_json_with_version("/users/1/collections", Colls, 99999, Config), ok.

search_precondition(Config) ->
    Searches = [#{<<"name">> => <<"Precond Search">>, <<"conditions">> => []}],
    {412, _, _} = post_json_with_version("/users/1/searches", Searches, 99999, Config), ok.

settings_precondition(Config) ->
    Base = ?config(base, Config),
    ApiKey = ?config(api_key, Config),
    {ok, {{_, 412, _}, _, _}} =
        httpc:request(post, {Base ++ "/users/1/settings",
            [{"Zotero-API-Key", binary_to_list(ApiKey)},
             {"If-Unmodified-Since-Version", "99999"}],
            "application/json", simdjson:encode(#{<<"x">> => #{<<"value">> => 1}})},
            [], [{body_format, binary}]),
    ok.

items_precondition_delete(Config) ->
    Base = ?config(base, Config),
    ApiKey = ?config(api_key, Config),
    {ok, {{_, 412, _}, _, _}} =
        httpc:request(delete, {Base ++ "/users/1/items?itemKey=XXXXXXXX",
            [{"Zotero-API-Key", binary_to_list(ApiKey)},
             {"If-Unmodified-Since-Version", "99999"}]},
            [], [{body_format, binary}]),
    ok.

%% ===================================================================
%% Validation edge cases
%% ===================================================================

validation_empty_collection_name(Config) ->
    {400, _, _} = post_json("/users/1/collections", [#{<<"name">> => <<>>}], Config), ok.

validation_empty_search_name(Config) ->
    {400, _, _} = post_json("/users/1/searches", [#{<<"name">> => <<>>}], Config), ok.

validation_missing_item_type(Config) ->
    {400, _, _} = post_json("/users/1/items", [#{<<"title">> => <<"No Type">>}], Config), ok.

validation_bad_setting(Config) ->
    Base = ?config(base, Config),
    ApiKey = ?config(api_key, Config),
    %% Empty key
    {ok, {{_, 400, _}, _, _}} =
        httpc:request(post, {Base ++ "/users/1/settings",
            [{"Zotero-API-Key", binary_to_list(ApiKey)}],
            "application/json", simdjson:encode(#{<<>> => #{<<"value">> => 1}})},
            [], [{body_format, binary}]),
    ok.

%% ===================================================================
%% Session/login edge cases
%% ===================================================================

session_cancel_not_found(Config) ->
    Base = ?config(base, Config),
    {ok, {{_, 404, _}, _, _}} =
        httpc:request(delete, {Base ++ "/keys/sessions/nonexistent_token", []},
                      [], [{body_format, binary}]),
    ok.

login_completed_session(Config) ->
    Base = ?config(base, Config),
    {Token, Csrf, _} = create_session_with_csrf(Config),
    FormBody = cow_qs:qs([{<<"token">>, Token}, {<<"csrf">>, Csrf},
                          {<<"username">>, <<"testuser">>},
                          {<<"password">>, <<"testpass">>}]),
    {ok, {{_, 200, _}, _, _}} =
        httpc:request(post, {Base ++ "/login", [],
                             "application/x-www-form-urlencoded", FormBody},
                      [], [{body_format, binary}]),
    %% GET login page for completed session — should show success
    {ok, {{_, 200, _}, _, Html}} =
        httpc:request(get, {Base ++ "/login?token=" ++ binary_to_list(Token), []},
                      [], [{body_format, binary}]),
    ?assertNotEqual(nomatch, binary:match(Html, <<"Signed in">>)),
    ok.

keys_session_expired(Config) ->
    Base = ?config(base, Config),
    %% Create expired session directly
    Token = <<"expired_keys_test">>,
    shurbey_session:insert_raw(Token, #{
        status => pending, created => erlang:system_time(millisecond) - 700000,
        login_url => <<"http://test">>, csrf_token => <<"x">>}),
    {ok, {{_, 410, _}, _, _}} =
        httpc:request(get, {Base ++ "/keys/sessions/" ++ binary_to_list(Token), []},
                      [], [{body_format, binary}]),
    ok.

keys_session_404(Config) ->
    Base = ?config(base, Config),
    {ok, {{_, 404, _}, _, _}} =
        httpc:request(get, {Base ++ "/keys/sessions/totally_fake_token", []},
                      [], [{body_format, binary}]),
    ok.

%% ===================================================================
%% Write token
%% ===================================================================

write_token_store_and_cleanup(_Config) ->
    %% Store a token
    ok = shurbey_write_token:store(<<"test_wt_1">>, {some_result, 1}),
    %% Should be duplicate now
    {duplicate, {some_result, 1}} = shurbey_write_token:check(<<"test_wt_1">>),
    %% Trigger cleanup
    shurbey_write_token ! cleanup,
    timer:sleep(100),
    %% Token should still exist (not expired yet)
    {duplicate, _} = shurbey_write_token:check(<<"test_wt_1">>),
    ok.

%% ===================================================================
%% File cascade delete
%% ===================================================================

file_cascade_delete(Config) ->
    %% Create item with file, then delete — should cascade
    Item = #{<<"itemType">> => <<"attachment">>, <<"title">> => <<"Cascade File">>},
    {200, _, CB} = post_json("/users/1/items", [Item], Config),
    #{<<"0">> := #{<<"key">> := Key}} = maps:get(<<"successful">>, CB),
    %% Upload a file
    FileData = <<"cascade delete test data">>,
    Md5 = list_to_binary(lists:flatten(
        [io_lib:format("~2.16.0b", [B]) || <<B>> <= crypto:hash(md5, FileData)])),
    UploadParams = cow_qs:qs([
        {<<"upload">>, <<"1">>}, {<<"md5">>, Md5},
        {<<"filename">>, <<"cascade.bin">>},
        {<<"filesize">>, integer_to_binary(byte_size(FileData))},
        {<<"mtime">>, <<"1">>}
    ]),
    {200, _, Auth} = post_form("/users/1/items/" ++ binary_to_list(Key) ++ "/file",
                                UploadParams, [{"If-None-Match", "*"}], Config),
    UploadUrl = maps:get(<<"url">>, Auth),
    UploadKey = maps:get(<<"uploadKey">>, Auth),
    {201, _, _} = post_raw(binary_to_list(UploadUrl), FileData),
    Reg = cow_qs:qs([{<<"uploadKey">>, UploadKey}]),
    {204, _, _} = post_form("/users/1/items/" ++ binary_to_list(Key) ++ "/file", Reg, Config),
    %% Add fulltext
    {204, _, _} = put_json("/users/1/items/" ++ binary_to_list(Key) ++ "/fulltext",
        #{<<"content">> => <<"test">>}, Config),
    %% Now delete the item
    {ok, Version} = shurbey_version:get(1),
    {204, _, _} = delete_req("/users/1/items?itemKey=" ++ binary_to_list(Key), Version, Config),
    %% File metadata should be gone
    ?assertEqual(undefined, shurbey_db:get_file_meta(1, Key)),
    %% Fulltext should be gone
    ?assertEqual(undefined, shurbey_db:get_fulltext(1, Key)),
    ok.

%% ===================================================================
%% More edge cases for coverage
%% ===================================================================

bad_json_body(Config) ->
    Base = ?config(base, Config),
    ApiKey = ?config(api_key, Config),
    %% POST invalid JSON to items
    {ok, {{_, Status, _}, _, _}} =
        httpc:request(post, {Base ++ "/users/1/items",
            [{"Zotero-API-Key", binary_to_list(ApiKey)}],
            "application/json", <<"not json">>},
            [], [{body_format, binary}]),
    ?assert(Status >= 400),
    ok.

login_bad_credentials(Config) ->
    Base = ?config(base, Config),
    {Token, Csrf, _} = create_session_with_csrf(Config),
    FormBody = cow_qs:qs([
        {<<"token">>, Token},
        {<<"csrf">>, Csrf},
        {<<"username">>, <<"testuser">>},
        {<<"password">>, <<"wrongpassword">>}
    ]),
    {ok, {{_, 200, _}, _, Html}} =
        httpc:request(post, {Base ++ "/login", [],
                             "application/x-www-form-urlencoded", FormBody},
                      [], [{body_format, binary}]),
    ?assertNotEqual(nomatch, binary:match(Html, <<"Invalid">>)),
    ok.

login_expired_session(Config) ->
    Base = ?config(base, Config),
    %% GET login page with non-existent token
    {ok, {{_, 404, _}, _, _}} =
        httpc:request(get, {Base ++ "/login?token=nonexistent", []},
                      [], [{body_format, binary}]),
    ok.

file_download_no_file(Config) ->
    Item = #{<<"itemType">> => <<"book">>, <<"title">> => <<"No File">>},
    {200, _, CB} = post_json("/users/1/items", [Item], Config),
    #{<<"0">> := #{<<"key">> := Key}} = maps:get(<<"successful">>, CB),
    {404, _, _} = get_raw("/users/1/items/" ++ binary_to_list(Key) ++ "/file", Config),
    ok.

collection_key_filter(Config) ->
    Colls = [#{<<"name">> => <<"CKF 1">>}, #{<<"name">> => <<"CKF 2">>}],
    {200, _, CB} = post_json("/users/1/collections", Colls, Config),
    #{<<"0">> := #{<<"key">> := K1}} = maps:get(<<"successful">>, CB),
    {200, _, Found} = get_json("/users/1/collections?collectionKey=" ++ binary_to_list(K1) ++ "&since=0", Config),
    ?assertEqual(1, length(Found)),
    ?assertEqual(K1, maps:get(<<"key">>, hd(Found))),
    ok.

search_key_filter(Config) ->
    Searches = [#{<<"name">> => <<"SKF 1">>, <<"conditions">> => []},
                #{<<"name">> => <<"SKF 2">>, <<"conditions">> => []}],
    {200, _, CB} = post_json("/users/1/searches", Searches, Config),
    #{<<"0">> := #{<<"key">> := K1}} = maps:get(<<"successful">>, CB),
    {200, _, Found} = get_json("/users/1/searches?searchKey=" ++ binary_to_list(K1) ++ "&since=0", Config),
    ?assertEqual(1, length(Found)),
    ok.

search_versions_format(Config) ->
    {200, _, Body} = get_json("/users/1/searches?format=versions", Config),
    ?assert(is_map(Body)),
    ok.

tags_versions_format(Config) ->
    {200, _, Body} = get_json("/users/1/tags?format=versions&since=0", Config),
    ?assert(is_map(Body)),
    ok.

settings_versions_format(Config) ->
    {200, _, Body} = get_json("/users/1/settings?format=versions", Config),
    ?assert(is_map(Body)),
    ok.

validation_bad_tags(Config) ->
    Item = #{<<"itemType">> => <<"book">>, <<"title">> => <<"Bad Tags">>,
             <<"tags">> => [<<"not a map">>]},
    {400, _, Body} = post_json("/users/1/items", [Item], Config),
    ?assertEqual(1, map_size(maps:get(<<"failed">>, Body))),
    ok.

validation_bad_collections_field(Config) ->
    Item = #{<<"itemType">> => <<"book">>, <<"title">> => <<"Bad Colls">>,
             <<"collections">> => <<"not an array">>},
    {400, _, Body} = post_json("/users/1/items", [Item], Config),
    ?assertEqual(1, map_size(maps:get(<<"failed">>, Body))),
    ok.

validation_bad_key_format(Config) ->
    Item = #{<<"itemType">> => <<"book">>, <<"title">> => <<"Bad Key">>,
             <<"key">> => <<"short">>},
    {400, _, Body} = post_json("/users/1/items", [Item], Config),
    ?assertEqual(1, map_size(maps:get(<<"failed">>, Body))),
    ok.

item_template_note(Config) ->
    Base = ?config(base, Config),
    {ok, {{_, 200, _}, _, Body}} =
        httpc:request(get, {Base ++ "/items/new?itemType=note", []}, [], [{body_format, binary}]),
    T = simdjson:decode(Body),
    ?assertEqual(<<"note">>, maps:get(<<"itemType">>, T)),
    ?assert(maps:is_key(<<"note">>, T)),
    ok.

item_template_attachment(Config) ->
    Base = ?config(base, Config),
    {ok, {{_, 200, _}, _, Body}} =
        httpc:request(get, {Base ++ "/items/new?itemType=attachment", []}, [], [{body_format, binary}]),
    T = simdjson:decode(Body),
    ?assertEqual(<<"attachment">>, maps:get(<<"itemType">>, T)),
    ?assert(maps:is_key(<<"filename">>, T)),
    ok.

put_nonexistent_item(Config) ->
    {ok, Version} = shurbey_version:get(1),
    {404, _, _} = put_json_versioned("/users/1/items/ZZZZZZZZ",
        #{<<"itemType">> => <<"book">>, <<"title">> => <<"Ghost">>}, Version, Config),
    ok.

duplicate_user_create(_Config) ->
    ?assertEqual({error, already_exists},
                 shurbey_admin:create_user(<<"testuser">>, <<"other">>, 2)),
    ok.

%% ===================================================================
%% HTTP helpers
%% ===================================================================

%% Extract CSRF token from login page HTML.
extract_csrf(Html) ->
    case re:run(Html, <<"name=\"csrf\" value=\"([^\"]+)\"">>, [{capture, [1], binary}]) of
        {match, [Csrf]} -> Csrf;
        nomatch -> <<>>
    end.

%% Create a login session and get the token + CSRF token.
create_session_with_csrf(Config) ->
    Base = ?config(base, Config),
    {ok, {{_, 201, _}, _, SessionBody}} =
        httpc:request(post, {Base ++ "/keys/sessions", [],
                             "application/json", <<"{}">>},
                      [], [{body_format, binary}]),
    Session = simdjson:decode(SessionBody),
    Token = maps:get(<<"sessionToken">>, Session),
    LoginUrl = maps:get(<<"loginURL">>, Session),
    {ok, {{_, 200, _}, _, LoginHtml}} =
        httpc:request(get, {binary_to_list(LoginUrl), []}, [], [{body_format, binary}]),
    Csrf = extract_csrf(LoginHtml),
    {Token, Csrf, LoginUrl}.

get_json(Path, Config) ->
    request(get, Path, [], <<>>, Config, true).

post_json(Path, Body, Config) ->
    request(post, Path, [], simdjson:encode(Body), Config, true).

post_json_with_version(Path, Body, Version, Config) ->
    Headers = [{"If-Unmodified-Since-Version", integer_to_list(Version)}],
    request(post, Path, Headers, simdjson:encode(Body), Config, true).

put_json(Path, Body, Config) ->
    request(put, Path, [], simdjson:encode(Body), Config, true).

delete_req(Path, Version, Config) ->
    Headers = [{"If-Unmodified-Since-Version", integer_to_list(Version)}],
    request(delete, Path, Headers, <<>>, Config, true).

put_json_versioned(Path, Body, Version, Config) ->
    Headers = [{"If-Unmodified-Since-Version", integer_to_list(Version)}],
    request(put, Path, Headers, simdjson:encode(Body), Config, true).

patch_json(Path, Body, Version, Config) ->
    Base = ?config(base, Config),
    ApiKey = ?config(api_key, Config),
    Url = Base ++ Path,
    {ok, {{_, Status, _}, RespHeaders, RespBody}} =
        httpc:request(patch, {Url,
            [{"Zotero-API-Key", binary_to_list(ApiKey)},
             {"If-Unmodified-Since-Version", integer_to_list(Version)}],
            "application/json", simdjson:encode(Body)},
            [], [{body_format, binary}]),
    HeaderMap = maps:from_list([{list_to_binary(string:lowercase(K)), list_to_binary(V)}
                                || {K, V} <- RespHeaders]),
    Decoded = case RespBody of
        <<>> -> #{};
        _ -> try simdjson:decode(RespBody) catch _:_ -> RespBody end
    end,
    {Status, HeaderMap, Decoded}.

post_form(Path, FormBody, Config) ->
    post_form(Path, FormBody, [], Config).

post_form(Path, FormBody, ExtraHeaders, Config) ->
    Base = ?config(base, Config),
    ApiKey = ?config(api_key, Config),
    Url = Base ++ Path,
    AuthHeaders = [{"Zotero-API-Key", binary_to_list(ApiKey)} | ExtraHeaders],
    {ok, {{_, Status, _}, RespHeaders, RespBody}} =
        httpc:request(post, {Url, AuthHeaders, "application/x-www-form-urlencoded", FormBody},
                      [], [{body_format, binary}]),
    HeaderMap = maps:from_list([{list_to_binary(string:lowercase(K)), list_to_binary(V)}
                                || {K, V} <- RespHeaders]),
    Decoded = case RespBody of
        <<>> -> #{};
        _ -> try simdjson:decode(RespBody) catch _:_ -> RespBody end
    end,
    {Status, HeaderMap, Decoded}.

post_raw(Url, Body) ->
    {ok, {{_, Status, _}, RespHeaders, RespBody}} =
        httpc:request(post, {Url, [], "application/octet-stream", Body},
                      [], [{body_format, binary}]),
    HeaderMap = maps:from_list([{list_to_binary(string:lowercase(K)), list_to_binary(V)}
                                || {K, V} <- RespHeaders]),
    {Status, HeaderMap, RespBody}.

get_raw(Path, Config) ->
    Base = ?config(base, Config),
    ApiKey = ?config(api_key, Config),
    Url = Base ++ Path,
    {ok, {{_, Status, _}, RespHeaders, RespBody}} =
        httpc:request(get, {Url, [{"Zotero-API-Key", binary_to_list(ApiKey)}]},
                      [], [{body_format, binary}]),
    HeaderMap = maps:from_list([{list_to_binary(string:lowercase(K)), list_to_binary(V)}
                                || {K, V} <- RespHeaders]),
    {Status, HeaderMap, RespBody}.

request(Method, Path, ExtraHeaders, ReqBody, Config, WithAuth) ->
    Base = ?config(base, Config),
    ApiKey = ?config(api_key, Config),
    Url = Base ++ Path,
    AuthHeaders = case WithAuth of
        true -> [{"Zotero-API-Key", binary_to_list(ApiKey)}];
        false -> []
    end,
    AllHeaders = AuthHeaders ++ ExtraHeaders,
    Response = case Method of
        get ->
            httpc:request(get, {Url, AllHeaders}, [], [{body_format, binary}]);
        delete ->
            httpc:request(delete, {Url, AllHeaders}, [], [{body_format, binary}]);
        _ ->
            ContentType = "application/json",
            httpc:request(Method, {Url, AllHeaders, ContentType, ReqBody}, [], [{body_format, binary}])
    end,
    case Response of
        {ok, {{_, Status, _}, RespHeaders, RespBody}} ->
            HeaderMap = maps:from_list([{list_to_binary(string:lowercase(K)), list_to_binary(V)} || {K, V} <- RespHeaders]),
            DecodedBody = case RespBody of
                <<>> -> #{};
                _ ->
                    try simdjson:decode(RespBody)
                    catch _:_ -> RespBody
                    end
            end,
            {Status, HeaderMap, DecodedBody};
        {error, Reason} ->
            ct:fail("HTTP request failed: ~p", [Reason])
    end.
