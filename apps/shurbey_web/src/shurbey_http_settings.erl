-module(shurbey_http_settings).
-include_lib("shurbey_store/include/shurbey_records.hrl").

-export([init/2]).

init(Req0, State) ->
    case shurbey_http_common:authorize(Req0) of
        {ok, _LibId, _} ->
            Method = cowboy_req:method(Req0),
            case needs_write(Method) andalso shurbey_http_common:check_perm(write) of
                {error, forbidden} ->
                    Req = shurbey_http_common:error_response(403, <<"Write access denied">>, Req0),
                    {ok, Req, State};
                _ ->
                    handle(Method, Req0, State)
            end;
        {error, Reason, _} ->
            Req = shurbey_http_common:auth_error_response(Reason, Req0),
            {ok, Req, State}
    end.

needs_write(<<"POST">>) -> true;
needs_write(<<"PUT">>) -> true;
needs_write(<<"DELETE">>) -> true;
needs_write(_) -> false.

handle(<<"GET">>, Req0, #{scope := single} = State) ->
    LibId = shurbey_http_common:library_id(Req0),
    SettingKey = cowboy_req:binding(setting_key, Req0),
    case shurbey_db:get_setting(LibId, SettingKey) of
        {ok, #shurbey_setting{value = Value, version = Version}} ->
            Body = #{<<"value">> => Value, <<"version">> => Version},
            Req = shurbey_http_common:json_response(200, Body, Version, Req0),
            {ok, Req, State};
        undefined ->
            Req = shurbey_http_common:error_response(404, <<"Setting not found">>, Req0),
            {ok, Req, State}
    end;

handle(<<"GET">>, Req0, State) ->
    LibId = shurbey_http_common:library_id(Req0),
    Since = shurbey_http_common:get_since(Req0),
    {ok, LibVersion} = shurbey_version:get(LibId),
    case shurbey_http_common:get_if_modified(Req0) of
        V when is_integer(V), V >= LibVersion ->
            Req = cowboy_req:reply(304, #{
                <<"last-modified-version">> => integer_to_binary(LibVersion)
            }, Req0),
            {ok, Req, State};
        _ -> handle_get_list(Req0, LibId, Since, LibVersion, State)
    end;

handle(<<"POST">>, Req0, State) ->
    LibId = shurbey_http_common:library_id(Req0),
    ExpectedVersion = shurbey_http_common:get_if_unmodified(Req0),
    case shurbey_http_common:read_json_body(Req0) of
        {error, _, Req1} ->
            Req = shurbey_http_common:error_response(400, <<"Invalid JSON">>, Req1),
            {ok, Req, State};
        {ok, SettingsMap, Req1} when is_map(SettingsMap) ->
    %% Validate each setting
    Errors = maps:fold(fun(Key, ValObj, Acc) ->
        Value = case is_map(ValObj) of
            true -> maps:get(<<"value">>, ValObj, ValObj);
            false -> ValObj
        end,
        case shurbey_validate:setting(Key, Value) of
            ok -> Acc;
            {error, Reason} -> [{Key, Reason} | Acc]
        end
    end, [], SettingsMap),
    case Errors of
        [{BadKey, Reason} | _] ->
            Req = shurbey_http_common:error_response(400,
                <<"Invalid setting '", BadKey/binary, "': ", Reason/binary>>, Req1),
            {ok, Req, State};
        [] ->
            case shurbey_version:write(LibId, ExpectedVersion, fun(NewVersion) ->
                maps:foreach(fun(Key, ValObj) ->
                    Value = case is_map(ValObj) of
                        true -> maps:get(<<"value">>, ValObj, ValObj);
                        false -> ValObj
                    end,
                    shurbey_db:write_setting(#shurbey_setting{
                        id = {LibId, Key},
                        version = NewVersion,
                        value = Value
                    })
                end, SettingsMap),
                ok
            end) of
                {ok, NewVersion} ->
                    Req = cowboy_req:reply(204, #{
                        <<"last-modified-version">> => integer_to_binary(NewVersion)
                    }, Req1),
                    {ok, Req, State};
                {error, precondition, CurrentVersion} ->
                    Req = shurbey_http_common:json_response(412,
                        #{<<"message">> => <<"Library has been modified since specified version">>},
                        CurrentVersion, Req1),
                    {ok, Req, State}
            end
    end;
        {ok, _, Req1} ->
            Req = shurbey_http_common:error_response(400, <<"Body must be a JSON object">>, Req1),
            {ok, Req, State}
    end;

%% PUT /settings/:setting_key — create or update a single setting
handle(<<"PUT">>, Req0, #{scope := single} = State) ->
    LibId = shurbey_http_common:library_id(Req0),
    SettingKey = cowboy_req:binding(setting_key, Req0),
    ExpectedVersion = shurbey_http_common:get_if_unmodified(Req0),
    case shurbey_http_common:read_json_body(Req0) of
        {error, Reason, Req1} ->
            Msg = case Reason of invalid_json -> <<"Invalid JSON">>; _ -> <<"Bad request">> end,
            Req = shurbey_http_common:error_response(400, Msg, Req1),
            {ok, Req, State};
        {ok, Data, Req1} ->
            Value = case is_map(Data) of
                true -> maps:get(<<"value">>, Data, Data);
                false -> Data
            end,
            case shurbey_validate:setting(SettingKey, Value) of
                {error, Reason2} ->
                    Req = shurbey_http_common:error_response(400, Reason2, Req1),
                    {ok, Req, State};
                ok ->
                    case shurbey_version:write(LibId, ExpectedVersion, fun(NewVersion) ->
                        shurbey_db:write_setting(#shurbey_setting{
                            id = {LibId, SettingKey},
                            version = NewVersion,
                            value = Value
                        }),
                        ok
                    end) of
                        {ok, NewVersion} ->
                            Req = cowboy_req:reply(204, #{
                                <<"last-modified-version">> => integer_to_binary(NewVersion)
                            }, Req1),
                            {ok, Req, State};
                        {error, precondition, CurrentVersion} ->
                            Req = shurbey_http_common:json_response(412,
                                #{<<"message">> => <<"Library has been modified since specified version">>},
                                CurrentVersion, Req1),
                            {ok, Req, State}
                    end
            end
    end;

%% DELETE /settings/:setting_key
handle(<<"DELETE">>, Req0, #{scope := single} = State) ->
    LibId = shurbey_http_common:library_id(Req0),
    SettingKey = cowboy_req:binding(setting_key, Req0),
    ExpectedVersion = shurbey_http_common:get_if_unmodified(Req0),
    case shurbey_version:write(LibId, ExpectedVersion, fun(NewVersion) ->
        shurbey_db:delete_setting(LibId, SettingKey),
        shurbey_db:record_deletion(LibId, <<"setting">>, SettingKey, NewVersion),
        ok
    end) of
        {ok, NewVersion} ->
            Req = cowboy_req:reply(204, #{
                <<"last-modified-version">> => integer_to_binary(NewVersion)
            }, Req0),
            {ok, Req, State};
        {error, precondition, CurrentVersion} ->
            Req = shurbey_http_common:json_response(412,
                #{<<"message">> => <<"Library has been modified since specified version">>},
                CurrentVersion, Req0),
            {ok, Req, State}
    end;

handle(_, Req0, State) ->
    Req = shurbey_http_common:error_response(405, <<"Method not allowed">>, Req0),
    {ok, Req, State}.

handle_get_list(Req0, LibId, Since, LibVersion, State) ->
    Format = shurbey_http_common:get_format(Req0),
    case Format of
        <<"versions">> ->
            Pairs = shurbey_db:list_setting_versions(LibId, Since),
            Req = shurbey_http_common:json_response(200, maps:from_list(Pairs), LibVersion, Req0),
            {ok, Req, State};
        _ ->
            Settings = shurbey_db:list_settings(LibId, Since),
            Map = maps:from_list([{Key, #{<<"value">> => S#shurbey_setting.value,
                                          <<"version">> => S#shurbey_setting.version}}
                                  || #shurbey_setting{id = {_, Key}} = S <- Settings]),
            Req = shurbey_http_common:json_response(200, Map, LibVersion, Req0),
            {ok, Req, State}
    end.
