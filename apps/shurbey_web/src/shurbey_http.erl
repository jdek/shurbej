-module(shurbey_http).
-export([routes/0]).

routes() ->
    [
        %% Auth — session-based login flow
        {"/keys", shurbey_http_keys, #{action => create_key}},
        {"/keys/current", shurbey_http_keys, #{action => current}},
        {"/keys/sessions", shurbey_http_keys, #{action => sessions}},
        {"/keys/sessions/:token", shurbey_http_keys, #{action => session}},
        {"/keys/:key", shurbey_http_keys, #{action => by_key}},

        %% Login page (browser-facing)
        {"/login", shurbey_http_login, #{}},

        %% JSON login for web UI
        {"/auth/login", shurbey_http_auth, #{}},

        %% WebSocket for login session notifications
        {"/ws", shurbey_ws_login, #{}},

        %% Streaming API (Zotero-compatible topicUpdated push)
        {"/stream", shurbey_ws_stream, #{}},

        %% Item template
        {"/items/new", shurbey_http_item_template, #{}},

        %% Item type metadata
        {"/itemTypes", shurbey_http_meta, #{action => item_types}},
        {"/itemFields", shurbey_http_meta, #{action => item_fields}},
        {"/itemTypeFields", shurbey_http_meta, #{action => item_type_fields}},
        {"/itemTypeCreatorTypes", shurbey_http_meta, #{action => item_type_creator_types}},
        {"/creatorFields", shurbey_http_meta, #{action => creator_fields}},

        %% Items
        {"/users/:user_id/items", shurbey_http_items, #{scope => all}},
        {"/users/:user_id/items/top", shurbey_http_items, #{scope => top}},
        {"/users/:user_id/items/trash", shurbey_http_items, #{scope => trash}},
        {"/users/:user_id/items/:item_key", shurbey_http_items, #{scope => single}},
        {"/users/:user_id/items/:item_key/children", shurbey_http_items, #{scope => children}},
        {"/users/:user_id/items/:item_key/tags", shurbey_http_tags, #{scope => item_tags}},

        %% Collections
        {"/users/:user_id/collections", shurbey_http_collections, #{scope => all}},
        {"/users/:user_id/collections/top", shurbey_http_collections, #{scope => top}},
        {"/users/:user_id/collections/:coll_key", shurbey_http_collections, #{scope => single}},
        {"/users/:user_id/collections/:coll_key/collections", shurbey_http_collections, #{scope => subcollections}},
        {"/users/:user_id/collections/:coll_key/items", shurbey_http_items, #{scope => collection}},
        {"/users/:user_id/collections/:coll_key/items/top", shurbey_http_items, #{scope => collection_top}},

        %% Searches
        {"/users/:user_id/searches", shurbey_http_searches, #{scope => all}},
        {"/users/:user_id/searches/:search_key", shurbey_http_searches, #{scope => single}},

        %% Tags
        {"/users/:user_id/tags", shurbey_http_tags, #{scope => all}},

        %% Settings
        {"/users/:user_id/settings", shurbey_http_settings, #{scope => all}},
        {"/users/:user_id/settings/:setting_key", shurbey_http_settings, #{scope => single}},

        %% Deleted
        {"/users/:user_id/deleted", shurbey_http_deleted, #{}},

        %% Full-text
        {"/users/:user_id/fulltext", shurbey_http_fulltext, #{scope => versions}},
        {"/users/:user_id/items/:item_key/fulltext", shurbey_http_fulltext, #{scope => single}},

        %% Files
        {"/users/:user_id/items/:item_key/file", shurbey_http_files, #{}},
        {"/users/:user_id/items/:item_key/file/view", shurbey_http_files, #{action => view}},
        {"/users/:user_id/items/:item_key/file/view/url", shurbey_http_files, #{action => view_url}},

        %% Groups
        {"/users/:user_id/groups", shurbey_http_groups, #{}},

        %% File upload endpoint
        {"/upload/:upload_key", shurbey_http_upload, #{}},

        %% Schema
        {"/schema", shurbey_http_schema, #{}},

        %% Retractions (stub — Zotero checks this for retracted papers)
        {"/retractions/list", shurbey_http_stub, #{body => []}},

        %% Web UI (built SPA — catch-all, must be last)
        {"/assets/[...]", cowboy_static, {dir, "web/dist/assets"}},
        {"/[...]", shurbey_http_spa, #{}}
    ].
