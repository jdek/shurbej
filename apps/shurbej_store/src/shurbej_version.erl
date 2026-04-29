-module(shurbej_version).
-behaviour(gen_server).
-include("shurbej_records.hrl").

-export([start_link/1]).
-export([get/1, write/3]).
-export([init/1, handle_call/3, handle_cast/2]).

start_link(LibRef) ->
    gen_server:start_link({global, {?MODULE, LibRef}}, ?MODULE, LibRef, []).

%% Get current library version.
get(LibRef) ->
    call(LibRef, get_version).

%% Execute a write operation with version tracking.
%% WriteFun is called as WriteFun(NewVersion) and must return ok | {error, _}.
%% Returns {ok, NewVersion} | {error, precondition, CurrentVersion} | {error, _}.
write(LibRef, ExpectedVersion, WriteFun) ->
    call(LibRef, {write, ExpectedVersion, WriteFun}).

%% gen_server callbacks

init(LibRef) ->
    ok = shurbej_db:ensure_library(LibRef),
    case shurbej_db:get_library(LibRef) of
        {ok, #shurbej_library{version = Version}} ->
            %% The pubsub topic depends on the user's current user_id label
            %% (Zotero clients parse `/users/:userID` topic strings back into
            %% libraries — see streamer.js getPathLibrary). The label can
            %% only change via /account, which terminates this worker so a
            %% fresh init/1 picks up the new value. Keeping it cached here
            %% means writes don't pay a per-write DB hop just to publish.
            Topic = build_topic(LibRef),
            {ok, #{lib_ref => LibRef, version => Version, topic => Topic}};
        undefined ->
            {stop, {unknown_library, LibRef}}
    end.

handle_call(get_version, _From, #{version := V} = State) ->
    {reply, {ok, V}, State};

handle_call({write, ExpectedVersion, WriteFun}, _From,
            #{lib_ref := LibRef, version := Current} = State) ->
    case ExpectedVersion of
        any ->
            do_write(LibRef, Current, WriteFun, State);
        Current ->
            do_write(LibRef, Current, WriteFun, State);
        _ when Current =:= 0 ->
            %% Fresh library — fast-forward to client's version for migration
            do_write(LibRef, ExpectedVersion, WriteFun, State);
        _ ->
            {reply, {error, precondition, Current}, State}
    end;

handle_call(_Msg, _From, State) ->
    {reply, {error, unknown}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

%% Internal

do_write(LibRef, Current, WriteFun, #{topic := Topic} = State) ->
    NewVersion = Current + 1,
    %% Clear any leftover orphan-blob entries from a prior run so aborts
    %% from that run can't pollute this one.
    shurbej_db:reset_orphan_blobs(),
    %% Execute write + version update atomically in a Mnesia transaction
    case mnesia:transaction(fun() ->
        case WriteFun(NewVersion) of
            ok ->
                mnesia:write(#shurbej_library{ref = LibRef, version = NewVersion}),
                ok;
            {error, _} = Err ->
                mnesia:abort(Err)
        end
    end) of
        {atomic, ok} ->
            %% Transaction committed — safe to unlink freed blobs now.
            shurbej_db:reap_orphan_blobs(),
            %% Notify stream subscribers via pg (no compile-time dependency).
            try
                Members = pg:get_members(shurbej_stream, Topic),
                [Pid ! {topic_updated, Topic, NewVersion} || Pid <- Members]
            catch _:_ -> ok
            end,
            {reply, {ok, NewVersion}, State#{version := NewVersion}};
        {aborted, {error, _} = Err} ->
            shurbej_db:reset_orphan_blobs(),
            {reply, Err, State};
        {aborted, Reason} ->
            shurbej_db:reset_orphan_blobs(),
            {reply, {error, Reason}, State}
    end.

%% Resolve the on-wire path that Zotero clients use as a topic identifier:
%% `/users/:userID` for user libraries (where userID is the integer label,
%% not the storage uuid) and `/groups/:groupID` for groups.
build_topic({user, UserUuid}) ->
    Label = case shurbej_db:get_user_by_uuid(UserUuid) of
        {ok, #shurbej_user{user_id = Id}} -> Id;
        undefined -> 0
    end,
    <<"/users/", (integer_to_binary(Label))/binary>>;
build_topic({group, Id}) ->
    <<"/groups/", (integer_to_binary(Id))/binary>>.

call(LibRef, Msg) ->
    %% The version server is lazy-started per library. `ensure_started` is
    %% race-free — start_child returns {already_started, Pid} if another
    %% caller beat us to it — and we also tolerate the server dying
    %% between resolve and call (e.g. during a group wipe) by retrying
    %% once. A single retry is enough because ensure_started will always
    %% spawn a fresh worker on the second attempt.
    try gen_server:call(ensure_started(LibRef), Msg)
    catch exit:{noproc, _} ->
        gen_server:call(ensure_started(LibRef), Msg)
    end.

ensure_started(LibRef) ->
    case shurbej_version_sup:start_child(LibRef) of
        {ok, Pid} -> Pid;
        {error, {already_started, Pid}} -> Pid
    end.
