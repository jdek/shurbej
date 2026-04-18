-module(shurbej_version).
-behaviour(gen_server).
-include("shurbej_records.hrl").

-export([start_link/1]).
-export([get/1, write/3]).
-export([init/1, handle_call/3, handle_cast/2]).

start_link(LibraryId) ->
    gen_server:start_link({global, {?MODULE, LibraryId}}, ?MODULE, LibraryId, []).

%% Get current library version.
get(LibraryId) ->
    call(LibraryId, get_version).

%% Execute a write operation with version tracking.
%% WriteFun is called as WriteFun(NewVersion) and must return ok | {error, _}.
%% Returns {ok, NewVersion} | {error, precondition, CurrentVersion} | {error, _}.
write(LibraryId, ExpectedVersion, WriteFun) ->
    call(LibraryId, {write, ExpectedVersion, WriteFun}).

%% gen_server callbacks

init(LibraryId) ->
    case shurbej_db:get_library(LibraryId) of
        {ok, #shurbej_library{version = Version}} ->
            {ok, #{library_id => LibraryId, version => Version}};
        undefined ->
            {stop, {unknown_library, LibraryId}}
    end.

handle_call(get_version, _From, #{version := V} = State) ->
    {reply, {ok, V}, State};

handle_call({write, ExpectedVersion, WriteFun}, _From, #{library_id := LibId, version := Current} = State) ->
    case ExpectedVersion of
        any ->
            do_write(LibId, Current, WriteFun, State);
        Current ->
            do_write(LibId, Current, WriteFun, State);
        _ when Current =:= 0 ->
            %% Fresh library — fast-forward to client's version for migration
            do_write(LibId, ExpectedVersion, WriteFun, State);
        _ ->
            {reply, {error, precondition, Current}, State}
    end;

handle_call(_Msg, _From, State) ->
    {reply, {error, unknown}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

%% Internal

do_write(LibId, Current, WriteFun, State) ->
    NewVersion = Current + 1,
    %% Execute write + version update atomically in a Mnesia transaction
    case mnesia:transaction(fun() ->
        case WriteFun(NewVersion) of
            ok ->
                mnesia:write(#shurbej_library{
                    library_id = LibId, library_type = user, version = NewVersion
                }),
                ok;
            {error, _} = Err ->
                mnesia:abort(Err)
        end
    end) of
        {atomic, ok} ->
            %% Notify stream subscribers via pg (no compile-time dependency)
            Topic = <<"/users/", (integer_to_binary(LibId))/binary>>,
            try
                Members = pg:get_members(shurbej_stream, Topic),
                [Pid ! {topic_updated, Topic, NewVersion} || Pid <- Members]
            catch _:_ -> ok
            end,
            {reply, {ok, NewVersion}, State#{version := NewVersion}};
        {aborted, {error, _} = Err} ->
            {reply, Err, State};
        {aborted, Reason} ->
            {reply, {error, Reason}, State}
    end.

call(LibraryId, Msg) ->
    case global:whereis_name({?MODULE, LibraryId}) of
        undefined ->
            case shurbej_version_sup:start_child(LibraryId) of
                {ok, Pid} ->
                    gen_server:call(Pid, Msg);
                {error, {already_started, Pid}} ->
                    gen_server:call(Pid, Msg)
            end;
        Pid ->
            gen_server:call(Pid, Msg)
    end.
