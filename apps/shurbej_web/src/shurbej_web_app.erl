-module(shurbej_web_app).
-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    Dispatch = cowboy_router:compile([
        {'_', shurbej_http:routes()}
    ]),
    {ListenOpts, ListenDesc} = listen_opts(),
    {ok, _} = cowboy:start_clear(
        shurbej_http,
        ListenOpts,
        #{env => #{dispatch => Dispatch}}
    ),
    ok = post_listen(ListenOpts),
    logger:notice("shurbej listening on ~s", [ListenDesc]),
    shurbej_web_sup:start_link().

stop(_State) ->
    cowboy:stop_listener(shurbej_http),
    ok.

%% Resolve the listener spec. Prefers the structured `listen` env so
%% deployments can pick between TCP and a Unix domain socket; falls back
%% to the legacy `http_port` integer if `listen` isn't set.
listen_opts() ->
    case application:get_env(shurbej, listen) of
        {ok, {unix, RawPath}} ->
            Path = to_list(RawPath),
            ok = clear_stale_socket(Path),
            {[{ip, {local, Path}}, {port, 0}], "unix:" ++ Path};
        {ok, {tcp, Port}} when is_integer(Port) ->
            {[{port, Port}], "port " ++ integer_to_list(Port)};
        _ ->
            Port = application:get_env(shurbej, http_port, 8080),
            {[{port, Port}], "port " ++ integer_to_list(Port)}
    end.

%% Tighten perms on a freshly-bound Unix socket. 0660 lets the front-end
%% proxy connect via shared group membership without exposing the API to
%% every uid on the host.
post_listen([{ip, {local, Path}} | _]) ->
    file:change_mode(Path, 8#660);
post_listen(_) ->
    ok.

%% gen_tcp:listen on a unix path fails with eaddrinuse if a stale socket
%% file is still on disk from a previous run. systemd's RuntimeDirectory
%% normally cleans this up, but a crash without RuntimeDirectoryPreserve
%% can leave one behind.
clear_stale_socket(Path) ->
    case file:read_file_info(Path) of
        {ok, _} ->
            _ = file:delete(Path),
            ok;
        {error, enoent} ->
            ok;
        {error, _} ->
            ok
    end.

to_list(L) when is_list(L) -> L;
to_list(B) when is_binary(B) -> binary_to_list(B).
