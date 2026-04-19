%% Library identifier — disjoint keyspace for user and group libraries.
-type lib_ref() :: {user, integer()} | {group, integer()}.

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
    user_id       :: integer(),
    permissions   :: map()
}).

-record(shurbej_item, {
    id            :: {user | group, integer(), binary()},
    version       :: integer(),
    data          :: map(),       %% full Zotero item as native map
    deleted = false :: boolean(),
    parent_key    :: binary() | undefined  %% denormalized from data.parentItem
}).

%% Denormalized index: which items belong to which collections.
%% Bag table — key is {LibType, LibId, CollKey}, multiple rows per collection.
-record(shurbej_item_collection, {
    id            :: {user | group, integer(), binary()},
    item_key      :: binary()
}).

-record(shurbej_collection, {
    id            :: {user | group, integer(), binary()},
    version       :: integer(),
    data          :: map(),
    deleted = false :: boolean()
}).

-record(shurbej_search, {
    id            :: {user | group, integer(), binary()},
    version       :: integer(),
    data          :: map(),
    deleted = false :: boolean()
}).

-record(shurbej_tag, {
    id            :: {user | group, integer(), binary(), binary()},
    tag_type = 0  :: integer()
}).

-record(shurbej_setting, {
    id            :: {user | group, integer(), binary()},
    version       :: integer(),
    value         :: term()
}).

-record(shurbej_deleted, {
    id            :: {user | group, integer(), binary(), binary()},
    version       :: integer()
}).

-record(shurbej_fulltext, {
    id            :: {user | group, integer(), binary()},
    version       :: integer(),
    content       :: binary(),
    indexed_pages :: integer(),
    total_pages   :: integer(),
    indexed_chars :: integer(),
    total_chars   :: integer()
}).

%% Per-item attachment metadata — points at a blob by content hash.
-record(shurbej_file_meta, {
    id            :: {user | group, integer(), binary()},
    md5           :: binary(),     %% MD5 for Zotero protocol compatibility
    sha256        :: binary(),     %% SHA-256 for content addressing
    filename      :: binary(),
    filesize      :: integer(),
    mtime         :: integer()
}).

%% User accounts for authentication.
-record(shurbej_user, {
    username      :: binary(),
    password_hash :: binary(),   %% PBKDF2-SHA256
    salt          :: binary(),
    user_id       :: integer()
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
    owner_id         :: integer(),
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
    id   :: {integer(), integer()},  %% {GroupId, UserId}
    role :: owner | admin | member
}).
