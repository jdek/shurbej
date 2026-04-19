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
            {ok, #{lib_ref => LibRef, version => Version}};
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

do_write(LibRef, Current, WriteFun, State) ->
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
            %% Notify stream subscribers via pg (no compile-time dependency)
            Topic = topic(LibRef),
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

topic({user, Id}) ->
    <<"/users/", (integer_to_binary(Id))/binary>>;
topic({group, Id}) ->
    <<"/groups/", (integer_to_binary(Id))/binary>>.

call(LibRef, Msg) ->
    case global:whereis_name({?MODULE, LibRef}) of
        undefined ->
            case shurbej_version_sup:start_child(LibRef) of
                {ok, Pid} ->
                    gen_server:call(Pid, Msg);
                {error, {already_started, Pid}} ->
                    gen_server:call(Pid, Msg)
            end;
        Pid ->
            gen_server:call(Pid, Msg)
    end.
