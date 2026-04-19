-module(shurbej_http).
-export([routes/0, web_dist_dir/0, web_dist_path/1]).

%% Resolve once at route-compile time so the SPA handler doesn't recompute it
%% per request. Falls back to "web/dist" relative to cwd for dev.
web_dist_dir() ->
    case application:get_env(shurbej, web_dist_dir) of
        {ok, Dir} -> to_list(Dir);
        undefined -> "web/dist"
    end.

web_dist_path(Rel) ->
    filename:join(web_dist_dir(), Rel).

to_list(B) when is_binary(B) -> binary_to_list(B);
to_list(L) when is_list(L) -> L.

routes() ->
    UserRoutes = library_routes("/users/:user_id"),
    GroupRoutes = library_routes("/groups/:group_id"),
    AssetsDir = filename:join(web_dist_dir(), "assets"),
    [
        %% Auth — session-based login flow
        {"/keys", shurbej_http_keys, #{action => create_key}},
        {"/keys/current", shurbej_http_keys, #{action => current}},
        {"/keys/sessions", shurbej_http_keys, #{action => sessions}},
        {"/keys/sessions/:token", shurbej_http_keys, #{action => session}},
        {"/keys/:key", shurbej_http_keys, #{action => by_key}},

        %% Login page (browser-facing)
        {"/login", shurbej_http_login, #{}},

        %% JSON login for web UI
        {"/auth/login", shurbej_http_auth, #{}},

        %% WebSocket for login session notifications
        {"/ws", shurbej_ws_login, #{}},

        %% Streaming API (Zotero-compatible topicUpdated push)
        {"/stream", shurbej_ws_stream, #{}},

        %% Item template
        {"/items/new", shurbej_http_item_template, #{}},

        %% Item type metadata
        {"/itemTypes", shurbej_http_meta, #{action => item_types}},
        {"/itemFields", shurbej_http_meta, #{action => item_fields}},
        {"/itemTypeFields", shurbej_http_meta, #{action => item_type_fields}},
        {"/itemTypeCreatorTypes", shurbej_http_meta, #{action => item_type_creator_types}},
        {"/creatorFields", shurbej_http_meta, #{action => creator_fields}},

        %% Group listing (per-user) + group metadata
        {"/users/:user_id/groups", shurbej_http_groups, #{}},
        {"/groups/:group_id", shurbej_http_group, #{}}
    ]
    ++ UserRoutes
    ++ GroupRoutes
    ++ [
        %% File upload endpoint
        {"/upload/:upload_key", shurbej_http_upload, #{}},

        %% Schema
        {"/schema", shurbej_http_schema, #{}},

        %% Retractions (stub — Zotero checks this for retracted papers)
        {"/retractions/list", shurbej_http_stub, #{body => []}},

        %% Web UI (built SPA — catch-all, must be last)
        {"/assets/[...]", cowboy_static, {dir, AssetsDir}},
        {"/[...]", shurbej_http_spa, #{}}
    ].

%% Produce the library-scoped route set for a given path prefix.
%% Used for both /users/:user_id and /groups/:group_id.
library_routes(Prefix) ->
    [
        %% Items
        {Prefix ++ "/items", shurbej_http_items, #{scope => all}},
        {Prefix ++ "/items/top", shurbej_http_items, #{scope => top}},
        {Prefix ++ "/items/trash", shurbej_http_items, #{scope => trash}},
        {Prefix ++ "/items/:item_key", shurbej_http_items, #{scope => single}},
        {Prefix ++ "/items/:item_key/children", shurbej_http_items, #{scope => children}},
        {Prefix ++ "/items/:item_key/tags", shurbej_http_tags, #{scope => item_tags}},

        %% Collections
        {Prefix ++ "/collections", shurbej_http_collections, #{scope => all}},
        {Prefix ++ "/collections/top", shurbej_http_collections, #{scope => top}},
        {Prefix ++ "/collections/:coll_key", shurbej_http_collections, #{scope => single}},
        {Prefix ++ "/collections/:coll_key/collections", shurbej_http_collections, #{scope => subcollections}},
        {Prefix ++ "/collections/:coll_key/items", shurbej_http_items, #{scope => collection}},
        {Prefix ++ "/collections/:coll_key/items/top", shurbej_http_items, #{scope => collection_top}},

        %% Searches
        {Prefix ++ "/searches", shurbej_http_searches, #{scope => all}},
        {Prefix ++ "/searches/:search_key", shurbej_http_searches, #{scope => single}},

        %% Tags
        {Prefix ++ "/tags", shurbej_http_tags, #{scope => all}},

        %% Settings
        {Prefix ++ "/settings", shurbej_http_settings, #{scope => all}},
        {Prefix ++ "/settings/:setting_key", shurbej_http_settings, #{scope => single}},

        %% Deleted
        {Prefix ++ "/deleted", shurbej_http_deleted, #{}},

        %% Full-text
        {Prefix ++ "/fulltext", shurbej_http_fulltext, #{scope => versions}},
        {Prefix ++ "/items/:item_key/fulltext", shurbej_http_fulltext, #{scope => single}},

        %% Files
        {Prefix ++ "/items/:item_key/file", shurbej_http_files, #{}},
        {Prefix ++ "/items/:item_key/file/view", shurbej_http_files, #{action => view}},
        {Prefix ++ "/items/:item_key/file/view/url", shurbej_http_files, #{action => view_url}}
    ].
