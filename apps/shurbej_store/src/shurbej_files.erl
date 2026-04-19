-module(shurbej_files).
-behaviour(gen_server).
-include("shurbej_records.hrl").

%% Public API
-export([
    start_link/0,
    blob_path/1,
    prepare_upload/3,
    get_pending/1,
    store/3,
    register_upload/1,
    mark_stored/2,
    cleanup_expired_uploads/0,
    confirm_existing/2
]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-define(TABLE, shurbej_pending_uploads).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% Content-addressed path: <root>/<first 2 hex chars of sha256>/<full sha256>
blob_path(Hash) ->
    Root = to_list(application:get_env(shurbej, file_storage_path, <<"./data/files">>)),
    Prefix = binary_to_list(binary:part(Hash, 0, 2)),
    filename:join([Root, Prefix, binary_to_list(Hash)]).

prepare_upload(LibRef, ItemKey, Meta) ->
    gen_server:call(?MODULE, {prepare, LibRef, ItemKey, Meta}).

get_pending(UploadKey) ->
    %% Reads are safe from any process on a public/protected table
    case ets:lookup(?TABLE, UploadKey) of
        [{_, Info}] -> {ok, Info};
        [] -> {error, not_found}
    end.

%% Store file data to disk. Verifies MD5 and computes SHA-256.
%% Zotero sends files as ZIP-compressed. Extract first, then verify MD5.
store(UploadKey, #{meta := Meta} = _Info, Data) ->
    #{md5 := ExpectedMd5} = Meta,
    FileData = maybe_unzip(Data),
    ActualMd5 = hex_hash(md5, FileData),
    case ActualMd5 of
        ExpectedMd5 ->
            Sha256 = hex_hash(sha256, FileData),
            BlobFile = blob_path(Sha256),
            case filelib:is_regular(BlobFile) of
                true ->
                    gen_server:call(?MODULE, {mark_stored, UploadKey, Sha256}),
                    ok;
                false ->
                    ok = filelib:ensure_dir(BlobFile),
                    case file:write_file(BlobFile, FileData) of
                        ok ->
                            gen_server:call(?MODULE, {mark_stored, UploadKey, Sha256}),
                            ok;
                        {error, _} = Err ->
                            Err
                    end
            end;
        _ ->
            {error, md5_mismatch}
    end.

%% Mark a pending upload as pre-stored (for dedup when blob already exists).
mark_stored(UploadKey, Info) ->
    gen_server:call(?MODULE, {mark_stored_raw, UploadKey, Info}).

%% Clean up expired pending uploads.
cleanup_expired_uploads() ->
    gen_server:call(?MODULE, cleanup_expired).

%% Register a completed upload (atomic via gen_server to prevent TOCTOU races).
register_upload(UploadKey) ->
    gen_server:call(?MODULE, {register_upload, UploadKey}).

%% gen_server callbacks

init([]) ->
    Table = ets:new(?TABLE, [named_table, protected, set]),
    {ok, #{table => Table}}.

handle_call({prepare, LibRef, ItemKey, Meta}, _From, State) ->
    UploadKey = generate_upload_key(),
    ets:insert(?TABLE, {UploadKey, #{
        lib_ref => LibRef,
        item_key => ItemKey,
        meta => Meta,
        stored => false,
        created => erlang:system_time(millisecond)
    }}),
    {reply, UploadKey, State};

handle_call({mark_stored, UploadKey, Sha256}, _From, State) ->
    case ets:lookup(?TABLE, UploadKey) of
        [{_, Info}] ->
            ets:insert(?TABLE, {UploadKey, Info#{stored => true, sha256 => Sha256}}),
            {reply, ok, State};
        [] ->
            {reply, {error, not_found}, State}
    end;

handle_call({mark_stored_raw, UploadKey, Info}, _From, State) ->
    ets:insert(?TABLE, {UploadKey, Info#{stored => true}}),
    {reply, ok, State};

handle_call({register_upload, UploadKey}, _From, State) ->
    Result = case ets:lookup(?TABLE, UploadKey) of
        [{_, #{stored := true, lib_ref := {LT, LI} = LibRef, item_key := ItemKey, meta := Meta,
               sha256 := Sha256}}] ->
            #{md5 := Md5, filename := Filename, filesize := Filesize,
              mtime := Mtime} = Meta,
            %% Use `any` — concurrent uploads must not fail with precondition
            %% errors. The gen_server serializes writes, so versions are
            %% monotonically increasing and responses stay ordered.
            WriteResult = shurbej_version:write(LibRef, any, fun(NewVersion) ->
                case shurbej_db:get_file_meta(LibRef, ItemKey) of
                    {ok, #shurbej_file_meta{sha256 = OldHash}} when OldHash =/= Sha256 ->
                        case shurbej_db:blob_unref(OldHash) of
                            {ok, 0} -> delete_blob_file(OldHash);
                            {ok, _} -> ok
                        end;
                    _ -> ok
                end,
                shurbej_db:blob_ref(Sha256),
                shurbej_db:write_file_meta(#shurbej_file_meta{
                    id = {LT, LI, ItemKey},
                    md5 = Md5, sha256 = Sha256,
                    filename = Filename, filesize = Filesize,
                    mtime = Mtime
                }),
                %% Bump item version so incremental sync detects the file change
                bump_item_version(LibRef, ItemKey, NewVersion),
                ok
            end),
            ets:delete(?TABLE, UploadKey),
            WriteResult;
        [{_, #{stored := false}}] ->
            {error, not_stored};
        [] ->
            {error, not_found}
    end,
    {reply, Result, State};

handle_call(cleanup_expired, _From, State) ->
    Now = erlang:system_time(millisecond),
    TTL = 3600000, %% 1 hour
    Expired = ets:foldl(fun({Key, Info}, Acc) ->
        Created = maps:get(created, Info, 0),
        case Created > 0 andalso Now - Created > TTL of
            true -> [Key | Acc];
            false -> Acc
        end
    end, [], ?TABLE),
    lists:foreach(fun(Key) -> ets:delete(?TABLE, Key) end, Expired),
    {reply, ok, State};

handle_call(_Msg, _From, State) ->
    {reply, {error, unknown}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Msg, State) ->
    {noreply, State}.

%% Confirm an existing file — bumps library + item version so concurrent
%% exists responses are serialized with registrations through the version
%% gen_server, keeping Last-Modified-Version monotonic for the client.
confirm_existing(LibRef, ItemKey) ->
    shurbej_version:write(LibRef, any, fun(NewVersion) ->
        bump_item_version(LibRef, ItemKey, NewVersion),
        ok
    end).

bump_item_version(LibRef, ItemKey, NewVersion) ->
    case shurbej_db:get_item(LibRef, ItemKey) of
        {ok, Item} ->
            shurbej_db:write_item(Item#shurbej_item{version = NewVersion});
        _ -> ok
    end.

%% Internal

delete_blob_file(Hash) ->
    file:delete(blob_path(Hash)).

%% If the data is a ZIP archive, extract the first file from it.
%% Zotero ZFS compresses files into ZIP before uploading.
maybe_unzip(<<80, 75, 3, 4, _/binary>> = ZipData) ->
    case zip:unzip(ZipData, [memory]) of
        {ok, [{_Filename, Content}]} ->
            Content;
        {ok, [{_Filename, Content} | _Rest]} ->
            Content;
        _ ->
            ZipData  %% fallback: treat as raw
    end;
maybe_unzip(Data) ->
    Data.

hex_hash(Algorithm, Data) ->
    binary:encode_hex(crypto:hash(Algorithm, Data), lowercase).

generate_upload_key() ->
    binary:encode_hex(crypto:strong_rand_bytes(16), lowercase).

to_list(B) when is_binary(B) -> binary_to_list(B);
to_list(L) when is_list(L) -> L.
