-module(shurbej_http_settings).
-include_lib("shurbej_store/include/shurbej_records.hrl").

-export([init/2]).

init(Req0, State) ->
    case shurbej_http_common:authorize(Req0) of
        {ok, _LibId, _} ->
            Method = cowboy_req:method(Req0),
            case needs_write(Method) andalso shurbej_http_common:check_perm(write) of
                {error, forbidden} ->
                    Req = shurbej_http_common:error_response(403, <<"Write access denied">>, Req0),
                    {ok, Req, State};
                _ ->
                    handle(Method, Req0, State)
            end;
        {error, Reason, _} ->
            Req = shurbej_http_common:auth_error_response(Reason, Req0),
            {ok, Req, State}
    end.

needs_write(<<"POST">>) -> true;
needs_write(<<"PUT">>) -> true;
needs_write(<<"DELETE">>) -> true;
needs_write(_) -> false.

handle(<<"GET">>, Req0, #{scope := single} = State) ->
    LibId = shurbej_http_common:library_id(Req0),
    SettingKey = cowboy_req:binding(setting_key, Req0),
    case shurbej_db:get_setting(LibId, SettingKey) of
        {ok, #shurbej_setting{value = Value, version = Version}} ->
            Body = #{<<"value">> => Value, <<"version">> => Version},
            Req = shurbej_http_common:json_response(200, Body, Version, Req0),
            {ok, Req, State};
        undefined ->
            Req = shurbej_http_common:error_response(404, <<"Setting not found">>, Req0),
            {ok, Req, State}
    end;

handle(<<"GET">>, Req0, State) ->
    LibId = shurbej_http_common:library_id(Req0),
    Since = shurbej_http_common:get_since(Req0),
    {ok, LibVersion} = shurbej_version:get(LibId),
    case shurbej_http_common:get_if_modified(Req0) of
        V when is_integer(V), V >= LibVersion ->
            Req = cowboy_req:reply(304, #{
                <<"last-modified-version">> => integer_to_binary(LibVersion)
            }, Req0),
            {ok, Req, State};
        _ -> handle_get_list(Req0, LibId, Since, LibVersion, State)
    end;

handle(<<"POST">>, Req0, State) ->
    LibId = shurbej_http_common:library_id(Req0),
    ExpectedVersion = shurbej_http_common:get_if_unmodified(Req0),
    case shurbej_http_common:read_json_body(Req0) of
        {error, _, Req1} ->
            Req = shurbej_http_common:error_response(400, <<"Invalid JSON">>, Req1),
            {ok, Req, State};
        {ok, SettingsMap, Req1} when is_map(SettingsMap) ->
    %% Validate each setting
    Errors = maps:fold(fun(Key, ValObj, Acc) ->
        Value = case is_map(ValObj) of
            true -> maps:get(<<"value">>, ValObj, ValObj);
            false -> ValObj
        end,
        case shurbej_validate:setting(Key, Value) of
            ok -> Acc;
            {error, Reason} -> [{Key, Reason} | Acc]
        end
    end, [], SettingsMap),
    case Errors of
        [{BadKey, Reason} | _] ->
            Req = shurbej_http_common:error_response(400,
                <<"Invalid setting '", BadKey/binary, "': ", Reason/binary>>, Req1),
            {ok, Req, State};
        [] ->
            case shurbej_version:write(LibId, ExpectedVersion, fun(NewVersion) ->
                maps:foreach(fun(Key, ValObj) ->
                    Value = case is_map(ValObj) of
                        true -> maps:get(<<"value">>, ValObj, ValObj);
                        false -> ValObj
                    end,
                    shurbej_db:write_setting(#shurbej_setting{
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
                    Req = shurbej_http_common:json_response(412,
                        #{<<"message">> => <<"Library has been modified since specified version">>},
                        CurrentVersion, Req1),
                    {ok, Req, State}
            end
    end;
        {ok, _, Req1} ->
            Req = shurbej_http_common:error_response(400, <<"Body must be a JSON object">>, Req1),
            {ok, Req, State}
    end;

%% PUT /settings/:setting_key — create or update a single setting
handle(<<"PUT">>, Req0, #{scope := single} = State) ->
    LibId = shurbej_http_common:library_id(Req0),
    SettingKey = cowboy_req:binding(setting_key, Req0),
    ExpectedVersion = shurbej_http_common:get_if_unmodified(Req0),
    case shurbej_http_common:read_json_body(Req0) of
        {error, Reason, Req1} ->
            Msg = case Reason of invalid_json -> <<"Invalid JSON">>; _ -> <<"Bad request">> end,
            Req = shurbej_http_common:error_response(400, Msg, Req1),
            {ok, Req, State};
        {ok, Data, Req1} ->
            Value = case is_map(Data) of
                true -> maps:get(<<"value">>, Data, Data);
                false -> Data
            end,
            case shurbej_validate:setting(SettingKey, Value) of
                {error, Reason2} ->
                    Req = shurbej_http_common:error_response(400, Reason2, Req1),
                    {ok, Req, State};
                ok ->
                    case shurbej_version:write(LibId, ExpectedVersion, fun(NewVersion) ->
                        shurbej_db:write_setting(#shurbej_setting{
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
                            Req = shurbej_http_common:json_response(412,
                                #{<<"message">> => <<"Library has been modified since specified version">>},
                                CurrentVersion, Req1),
                            {ok, Req, State}
                    end
            end
    end;

%% DELETE /settings/:setting_key
handle(<<"DELETE">>, Req0, #{scope := single} = State) ->
    LibId = shurbej_http_common:library_id(Req0),
    SettingKey = cowboy_req:binding(setting_key, Req0),
    ExpectedVersion = shurbej_http_common:get_if_unmodified(Req0),
    case shurbej_version:write(LibId, ExpectedVersion, fun(NewVersion) ->
        shurbej_db:delete_setting(LibId, SettingKey),
        shurbej_db:record_deletion(LibId, <<"setting">>, SettingKey, NewVersion),
        ok
    end) of
        {ok, NewVersion} ->
            Req = cowboy_req:reply(204, #{
                <<"last-modified-version">> => integer_to_binary(NewVersion)
            }, Req0),
            {ok, Req, State};
        {error, precondition, CurrentVersion} ->
            Req = shurbej_http_common:json_response(412,
                #{<<"message">> => <<"Library has been modified since specified version">>},
                CurrentVersion, Req0),
            {ok, Req, State}
    end;

handle(_, Req0, State) ->
    Req = shurbej_http_common:error_response(405, <<"Method not allowed">>, Req0),
    {ok, Req, State}.

handle_get_list(Req0, LibId, Since, LibVersion, State) ->
    Format = shurbej_http_common:get_format(Req0),
    case Format of
        <<"versions">> ->
            Pairs = shurbej_db:list_setting_versions(LibId, Since),
            Req = shurbej_http_common:json_response(200, maps:from_list(Pairs), LibVersion, Req0),
            {ok, Req, State};
        _ ->
            Settings = shurbej_db:list_settings(LibId, Since),
            Map = maps:from_list([{Key, #{<<"value">> => S#shurbej_setting.value,
                                          <<"version">> => S#shurbej_setting.version}}
                                  || #shurbej_setting{id = {_, Key}} = S <- Settings]),
            Req = shurbej_http_common:json_response(200, Map, LibVersion, Req0),
            {ok, Req, State}
    end.
