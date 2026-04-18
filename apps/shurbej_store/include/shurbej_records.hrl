-record(shurbej_library, {
    library_id    :: integer(),
    library_type  :: user | group,
    version = 0   :: integer()
}).

-record(shurbej_api_key, {
    key           :: binary(),
    user_id       :: integer(),
    permissions   :: map()
}).

-record(shurbej_item, {
    id            :: {LibraryId :: integer(), ItemKey :: binary()},
    version       :: integer(),
    data          :: map(),       %% full Zotero item as native map
    deleted = false :: boolean(),
    parent_key    :: binary() | undefined  %% denormalized from data.parentItem
}).

%% Denormalized index: which items belong to which collections.
%% Bag table — key is {LibId, CollKey}, multiple rows per collection.
-record(shurbej_item_collection, {
    id            :: {LibraryId :: integer(), CollKey :: binary()},
    item_key      :: binary()
}).

-record(shurbej_collection, {
    id            :: {LibraryId :: integer(), CollKey :: binary()},
    version       :: integer(),
    data          :: map(),
    deleted = false :: boolean()
}).

-record(shurbej_search, {
    id            :: {LibraryId :: integer(), SearchKey :: binary()},
    version       :: integer(),
    data          :: map(),
    deleted = false :: boolean()
}).

-record(shurbej_tag, {
    id            :: {LibraryId :: integer(), Tag :: binary(), ItemKey :: binary()},
    tag_type = 0  :: integer()
}).

-record(shurbej_setting, {
    id            :: {LibraryId :: integer(), SettingKey :: binary()},
    version       :: integer(),
    value         :: term()
}).

-record(shurbej_deleted, {
    id            :: {LibraryId :: integer(), ObjectType :: binary(), ObjectKey :: binary()},
    version       :: integer()
}).

-record(shurbej_fulltext, {
    id            :: {LibraryId :: integer(), ItemKey :: binary()},
    version       :: integer(),
    content       :: binary(),
    indexed_pages :: integer(),
    total_pages   :: integer(),
    indexed_chars :: integer(),
    total_chars   :: integer()
}).

%% Per-item attachment metadata — points at a blob by content hash.
-record(shurbej_file_meta, {
    id            :: {LibraryId :: integer(), ItemKey :: binary()},
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
    user_id       :: integer()   %% maps to library_id
}).

%% Content-addressed blob store with refcounting, keyed by SHA-256.
-record(shurbej_blob, {
    hash          :: binary(),    %% SHA-256 content hash, primary key
    size          :: integer(),
    refcount = 1  :: integer()
}).
