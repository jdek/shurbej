-module(shurbej_http).
-export([routes/0]).

routes() ->
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

        %% Items
        {"/users/:user_id/items", shurbej_http_items, #{scope => all}},
        {"/users/:user_id/items/top", shurbej_http_items, #{scope => top}},
        {"/users/:user_id/items/trash", shurbej_http_items, #{scope => trash}},
        {"/users/:user_id/items/:item_key", shurbej_http_items, #{scope => single}},
        {"/users/:user_id/items/:item_key/children", shurbej_http_items, #{scope => children}},
        {"/users/:user_id/items/:item_key/tags", shurbej_http_tags, #{scope => item_tags}},

        %% Collections
        {"/users/:user_id/collections", shurbej_http_collections, #{scope => all}},
        {"/users/:user_id/collections/top", shurbej_http_collections, #{scope => top}},
        {"/users/:user_id/collections/:coll_key", shurbej_http_collections, #{scope => single}},
        {"/users/:user_id/collections/:coll_key/collections", shurbej_http_collections, #{scope => subcollections}},
        {"/users/:user_id/collections/:coll_key/items", shurbej_http_items, #{scope => collection}},
        {"/users/:user_id/collections/:coll_key/items/top", shurbej_http_items, #{scope => collection_top}},

        %% Searches
        {"/users/:user_id/searches", shurbej_http_searches, #{scope => all}},
        {"/users/:user_id/searches/:search_key", shurbej_http_searches, #{scope => single}},

        %% Tags
        {"/users/:user_id/tags", shurbej_http_tags, #{scope => all}},

        %% Settings
        {"/users/:user_id/settings", shurbej_http_settings, #{scope => all}},
        {"/users/:user_id/settings/:setting_key", shurbej_http_settings, #{scope => single}},

        %% Deleted
        {"/users/:user_id/deleted", shurbej_http_deleted, #{}},

        %% Full-text
        {"/users/:user_id/fulltext", shurbej_http_fulltext, #{scope => versions}},
        {"/users/:user_id/items/:item_key/fulltext", shurbej_http_fulltext, #{scope => single}},

        %% Files
        {"/users/:user_id/items/:item_key/file", shurbej_http_files, #{}},
        {"/users/:user_id/items/:item_key/file/view", shurbej_http_files, #{action => view}},
        {"/users/:user_id/items/:item_key/file/view/url", shurbej_http_files, #{action => view_url}},

        %% Groups
        {"/users/:user_id/groups", shurbej_http_groups, #{}},

        %% File upload endpoint
        {"/upload/:upload_key", shurbej_http_upload, #{}},

        %% Schema
        {"/schema", shurbej_http_schema, #{}},

        %% Retractions (stub — Zotero checks this for retracted papers)
        {"/retractions/list", shurbej_http_stub, #{body => []}},

        %% Web UI (built SPA — catch-all, must be last)
        {"/assets/[...]", cowboy_static, {dir, "web/dist/assets"}},
        {"/[...]", shurbej_http_spa, #{}}
    ].
