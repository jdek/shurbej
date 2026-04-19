-module(shurbej_http_tags).
-include_lib("shurbej_store/include/shurbej_records.hrl").

-export([init/2]).

init(Req0, State) ->
    case shurbej_http_common:authorize(Req0) of
        {ok, _LibRef, _} ->
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

needs_write(<<"DELETE">>) -> true;
needs_write(_) -> false.

%% GET — list tags (optionally scoped to items matching filters)
handle(<<"GET">>, Req0, State) ->
    LibRef = shurbej_http_common:lib_ref(Req0),
    {ok, LibVersion} = shurbej_version:get(LibRef),
    case shurbej_http_common:check_304(Req0, LibVersion) of
        {304, Req} -> {ok, Req, State};
        continue -> handle_get_tags(Req0, LibRef, LibVersion, State)
    end;

%% DELETE /tags?tag=t1||t2
handle(<<"DELETE">>, Req0, State) ->
    LibRef = shurbej_http_common:lib_ref(Req0),
    ExpectedVersion = shurbej_http_common:get_if_unmodified(Req0),
    #{tag := TagParam} = cowboy_req:match_qs([{tag, [], <<>>}], Req0),
    case TagParam of
        <<>> ->
            Req = shurbej_http_common:error_response(400, <<"No tags specified">>, Req0),
            {ok, Req, State};
        _ ->
            TagNames = binary:split(TagParam, <<"||">>, [global]),
            case shurbej_version:write(LibRef, ExpectedVersion, fun(NewVersion) ->
                Deleted = shurbej_db:delete_tags_by_name(LibRef, TagNames),
                lists:foreach(fun(Tag) ->
                    shurbej_db:record_deletion(LibRef, <<"tag">>, Tag, NewVersion)
                end, Deleted),
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
            end
    end;

handle(_, Req0, State) ->
    Req = shurbej_http_common:error_response(405, <<"Method not allowed">>, Req0),
    {ok, Req, State}.

handle_get_tags(Req0, LibRef, LibVersion, State) ->
    Since = shurbej_http_common:get_since(Req0),
    Scope = maps:get(scope, State, all),
    TagPairs = case Scope of
        item_tags ->
            ItemKey = cowboy_req:binding(item_key, Req0),
            shurbej_db:list_item_tags(LibRef, ItemKey);
        _ ->
            shurbej_db:list_tags(LibRef, Since)
    end,
    Format = shurbej_http_common:get_format(Req0),
    case Format of
        <<"versions">> ->
            VersionMap = maps:from_list([{Tag, 0} || {Tag, _} <- TagPairs]),
            Req = shurbej_http_common:json_response(200, VersionMap, LibVersion, Req0),
            {ok, Req, State};
        _ ->
            Tags = [#{<<"tag">> => Tag, <<"type">> => Type} || {Tag, Type} <- TagPairs],
            Req = shurbej_http_common:json_response(200, Tags, LibVersion, Req0),
            {ok, Req, State}
    end.
