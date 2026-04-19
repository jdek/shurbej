# Shurbej

[![Erlang CI](https://github.com/jdek/shurbej/actions/workflows/erlang.yml/badge.svg)](https://github.com/jdek/shurbej/actions/workflows/erlang.yml)
[![Coverage](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/jdek/e28b9a35b796ab5996313c844f01ac59/raw/shurbej-coverage.json)](https://jdek.github.io/shurbej/)

Self-hosted Zotero sync server with basic web UI.

## Setup

```bash
rebar3 release
export SHURBEJ_COOKIE=$(openssl rand -hex 32)
./_build/default/rel/shurbej/bin/shurbej daemon
./_build/default/rel/shurbej/bin/shurbej eval 'shurbej_admin:create_user(<<"name">>, <<"pass">>, 1).'
```

Set `SHURBEJ_COOKIE` to a random secret — it gates `eval`/`remote` access to the running node. Default is `change_me_in_production`.

Point Zotero at `http://localhost:8080` in **Settings > Sync > Custom API URL**.

- extensions.zotero.api.url - http://localhost:8080/
- extensions.zotero.streaming.url - ws://localhost:8080/stream

To match your Zotero.org identity (avoids "different account" warning), use your Zotero user ID as the third argument — find it at `https://api.zotero.org/keys/<your-key>`.

### Web UI

```bash
cd web && npm install && npm run dev    # dev on :3000
cd web && npm run build                 # prod served by cowboy on :8080
```

### Config (`config/sys.config`)

```erlang
{http_port, 8080},
{db_path, "./data/shurbej.db"},
{file_storage_path, "./data/files"},
{base_url, "http://localhost:8080"}
```

## What works

Everything needed for Zotero desktop sync: items, collections, searches, tags, settings, file upload/download (ZIP-compressed), full-text content, deletion tombstones, version-based sync, streaming WebSocket, batch writes, pagination, `POST /keys` login flow.

The web UI has a PDF viewer (pdf.js, multi-tab with LRU caching), customizable sortable columns, collection tree with drag-drop, multi-tag filtering, tag colors, and stale-while-revalidate caching.

## What doesn't

OAuth 1.0a, export formats (bibtex/RIS/CSL), `include` parameter, backoff header.

Group libraries are supported server-side (`/groups/:id/...`, streaming, admin helpers), but the web UI has no group picker yet.

Publications (`/users/:id/publications/items`) are intentionally omitted.

Partial file upload (`PATCH /items/:key/file?algorithm=xdelta|vcdiff|bsdiff`) is also unimplemented, but the official Zotero desktop client does not use it — it always does a full-file upload. Only relevant for third-party clients.
