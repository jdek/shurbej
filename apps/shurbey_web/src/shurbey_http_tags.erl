-module(shurbey_http_tags).
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

needs_write(<<"DELETE">>) -> true;
needs_write(_) -> false.

%% GET — list tags (optionally scoped to items matching filters)
handle(<<"GET">>, Req0, State) ->
    LibId = shurbey_http_common:library_id(Req0),
    {ok, LibVersion} = shurbey_version:get(LibId),
    case shurbey_http_common:check_304(Req0, LibVersion) of
        {304, Req} -> {ok, Req, State};
        continue -> handle_get_tags(Req0, LibId, LibVersion, State)
    end;

%% DELETE /tags?tag=t1||t2
handle(<<"DELETE">>, Req0, State) ->
    LibId = shurbey_http_common:library_id(Req0),
    ExpectedVersion = shurbey_http_common:get_if_unmodified(Req0),
    #{tag := TagParam} = cowboy_req:match_qs([{tag, [], <<>>}], Req0),
    case TagParam of
        <<>> ->
            Req = shurbey_http_common:error_response(400, <<"No tags specified">>, Req0),
            {ok, Req, State};
        _ ->
            TagNames = binary:split(TagParam, <<"||">>, [global]),
            case shurbey_version:write(LibId, ExpectedVersion, fun(NewVersion) ->
                Deleted = shurbey_db:delete_tags_by_name(LibId, TagNames),
                lists:foreach(fun(Tag) ->
                    shurbey_db:record_deletion(LibId, <<"tag">>, Tag, NewVersion)
                end, Deleted),
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
            end
    end;

handle(_, Req0, State) ->
    Req = shurbey_http_common:error_response(405, <<"Method not allowed">>, Req0),
    {ok, Req, State}.

handle_get_tags(Req0, LibId, LibVersion, State) ->
    Since = shurbey_http_common:get_since(Req0),
    Scope = maps:get(scope, State, all),
    TagPairs = case Scope of
        item_tags ->
            ItemKey = cowboy_req:binding(item_key, Req0),
            shurbey_db:list_item_tags(LibId, ItemKey);
        _ ->
            shurbey_db:list_tags(LibId, Since)
    end,
    Format = shurbey_http_common:get_format(Req0),
    case Format of
        <<"versions">> ->
            VersionMap = maps:from_list([{Tag, 0} || {Tag, _} <- TagPairs]),
            Req = shurbey_http_common:json_response(200, VersionMap, LibVersion, Req0),
            {ok, Req, State};
        _ ->
            Tags = [#{<<"tag">> => Tag, <<"type">> => Type} || {Tag, Type} <- TagPairs],
            Req = shurbey_http_common:json_response(200, Tags, LibVersion, Req0),
            {ok, Req, State}
    end.
