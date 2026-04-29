%% Library identifier — disjoint keyspace for user and group libraries.
%% User libraries are keyed by the opaque internal user_uuid (binary), group
%% libraries by the auto-assigned integer group_id (which is also the
%% Zotero-protocol identifier exposed in /groups/:groupID URLs).
-type lib_id() :: binary() | integer().
-type lib_ref() :: {user, binary()} | {group, integer()}.

%% On-disk schema version. Bump when any record layout, key shape, or
%% table set changes in a way incompatible with earlier data. A single row
%% in shurbej_schema_meta pins the current expected version; startup
%% compares and refuses to boot on mismatch so a stale db.dmp can't silently
%% misalign fields.
-record(shurbej_schema_meta, {
    key     :: version,
    value   :: integer()
}).

-record(shurbej_library, {
    ref           :: lib_ref(),
    version = 0   :: integer()
}).

-record(shurbej_api_key, {
    key           :: binary(),
    user_uuid     :: binary(),
    permissions   :: map()
}).

%% lib_id is binary() for user libraries, integer() for group libraries.
-record(shurbej_item, {
    id            :: {user | group, lib_id(), binary()},
    version       :: integer(),
    data          :: map(),       %% full Zotero item as native map
    deleted = false :: boolean(),
    parent_key    :: binary() | undefined  %% denormalized from data.parentItem
}).

%% Denormalized index: which items belong to which collections.
%% Bag table — key is {LibType, LibId, CollKey}, multiple rows per collection.
-record(shurbej_item_collection, {
    id            :: {user | group, lib_id(), binary()},
    item_key      :: binary()
}).

-record(shurbej_collection, {
    id            :: {user | group, lib_id(), binary()},
    version       :: integer(),
    data          :: map(),
    deleted = false :: boolean()
}).

-record(shurbej_search, {
    id            :: {user | group, lib_id(), binary()},
    version       :: integer(),
    data          :: map(),
    deleted = false :: boolean()
}).

-record(shurbej_tag, {
    id            :: {user | group, lib_id(), binary(), binary()},
    tag_type = 0  :: integer()
}).

-record(shurbej_setting, {
    id            :: {user | group, lib_id(), binary()},
    version       :: integer(),
    value         :: term()
}).

-record(shurbej_deleted, {
    id            :: {user | group, lib_id(), binary(), binary()},
    version       :: integer()
}).

-record(shurbej_fulltext, {
    id            :: {user | group, lib_id(), binary()},
    version       :: integer(),
    content       :: binary(),
    indexed_pages :: integer(),
    total_pages   :: integer(),
    indexed_chars :: integer(),
    total_chars   :: integer()
}).

%% Per-item attachment metadata — points at a blob by content hash.
-record(shurbej_file_meta, {
    id            :: {user | group, lib_id(), binary()},
    md5           :: binary(),     %% MD5 for Zotero protocol compatibility
    sha256        :: binary(),     %% SHA-256 for content addressing
    filename      :: binary(),
    filesize      :: integer(),
    mtime         :: integer()
}).

%% User accounts. Profile-only — no auth material lives here.
%%
%%   user_uuid is the opaque internal identity, the primary key, never
%%   changes. All foreign references (api keys, identities, group members,
%%   storage record ids) point at it.
%%
%%   user_id is a Zotero-API label echoed at /keys/current and matched
%%   against the URL :userID. User-settable (e.g. to mirror an existing
%%   zotero.org account so a 1-line client config change repoints sync at
%%   this server). NOT unique across users — auth is via api key, the label
%%   is just identification on the wire.
%%
%%   username is the display name returned at /keys/current. For password
%%   identities it doubles as the credential subject, but it's stored here
%%   independently so it can be changed without touching the binding.
-record(shurbej_user, {
    user_uuid     :: binary(),     %% PK — 32-char lowercase hex
    user_id       :: integer(),    %% Zotero-API label, non-unique
    username      :: binary(),
    display_name  :: binary() | undefined,
    created_at    :: integer()     %% unix seconds
}).

%% Authentication bindings — one row per (provider, subject) pair, pointing
%% at a user_uuid. A user can have multiple bindings (password + OIDC, or
%% several OIDC providers). Adding a new auth method = inserting a row with
%% a fresh provider atom; no schema change.
%%
%%   key       :: {Provider :: atom(), Subject :: binary()}
%%                Provider examples:
%%                  password         — Subject is the username at signup
%%                  oidc_kanidm      — Subject is the OIDC `sub` claim
%%                  oidc_<name>      — same shape for any OIDC issuer
%%   credentials :: provider-specific opaque term:
%%                  password   → {pbkdf2_sha256, Hash, Salt}
%%                  oidc_*     → undefined (or refresh-token blob if cached)
-record(shurbej_identity, {
    key           :: {atom(), binary()},
    user_uuid     :: binary(),
    credentials   :: term()
}).

%% Content-addressed blob store with refcounting, keyed by SHA-256.
-record(shurbej_blob, {
    hash          :: binary(),    %% SHA-256 content hash, primary key
    size          :: integer(),
    refcount = 1  :: integer()
}).

%% Group metadata.
-record(shurbej_group, {
    group_id         :: integer(),
    name             :: binary(),
    owner_uuid       :: binary(),
    type             :: private | public_closed | public_open,
    description = <<>> :: binary(),
    url = <<>>       :: binary(),
    has_image = false :: boolean(),
    library_editing  :: admins | members,
    library_reading  :: all | members,
    file_editing     :: admins | members | none,
    created          :: integer(),   %% unix seconds
    version = 0      :: integer()
}).

%% Group membership — one row per (group, user) pair.
-record(shurbej_group_member, {
    id   :: {integer(), binary()},  %% {GroupId, UserUuid}
    role :: owner | admin | member
}).
