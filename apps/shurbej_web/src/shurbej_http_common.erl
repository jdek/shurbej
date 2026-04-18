-module(shurbej_http_common).
-include_lib("shurbej_store/include/shurbej_records.hrl").

-export([
    extract_api_key/1,
    authenticate/1,
    authorize/1,
    check_perm/1,
    library_id/1,
    get_since/1,
    get_format/1,
    get_if_unmodified/1,
    get_if_modified/1,
    get_item_keys/1,
    get_collection_keys/1,
    get_search_keys/1,
    get_tag_filter/1,
    get_item_type_filter/1,
    get_query/1,
    get_qmode/1,
    get_include_trashed/1,
    get_write_token/1,
    get_limit/1,
    get_start/1,
    get_sort/1,
    get_direction/1,
    check_304/2,
    filter_by_keys/2,
    filter_by_tag/2,
    filter_by_item_type/2,
    filter_by_query/3,
    json_response/3,
    json_response/4,
    error_response/3,
    paginate/3,
    sort_records/3,
    list_response/4,
    read_json_body/1,
    safe_int/1,
    sanitize_filename/1,
    validate_md5/1,
    base_url/0,
    envelope_item/2,
    envelope_item/3,
    envelope_collection/2,
    envelope_search/2,
    auth_error_response/2
]).

-define(MAX_BODY_SIZE, 8_000_000). %% 8MB

%% ===================================================================
%% Authentication & Authorization
%% ===================================================================

%% Extract API key from request (header or query param).
extract_api_key(Req) ->
    case cowboy_req:header(<<"zotero-api-key">>, Req) of
        undefined ->
            case cowboy_req:header(<<"authorization">>, Req) of
                <<"Bearer ", Key/binary>> -> Key;
                _ ->
                    #{key := Key} = cowboy_req:match_qs([{key, [], undefined}], Req),
                    Key
            end;
        Key ->
            Key
    end.

%% Authenticate only — verify the API key is valid, stash permissions.
authenticate(Req) ->
    case extract_api_key(Req) of
        undefined ->
            {error, Req};
        Key ->
            case shurbej_auth:key_info(Key) of
                {ok, #{user_id := UserId, permissions := Perms}} ->
                    put(shurbej_perms, normalize_perms(Perms)),
                    {ok, UserId, Req};
                {error, _} -> {error, Req}
            end
    end.

%% Authenticate AND authorize — verify API key AND that the authenticated
%% user owns the library specified in the URL path. Prevents IDOR.
authorize(Req) ->
    case authenticate(Req) of
        {ok, UserId, Req2} ->
            case shurbej_rate_limit:check(UserId) of
                {error, rate_limited} ->
                    {error, rate_limited, Req2};
                ok ->
                    case cowboy_req:binding(user_id, Req2) of
                        undefined ->
                            %% Endpoints without :user_id (e.g., /schema, /items/new)
                            {ok, UserId, Req2};
                        UserIdBin ->
                            case safe_int(UserIdBin) of
                                {ok, UserId} -> {ok, UserId, Req2};
                                {ok, _Other} -> {error, forbidden, Req2};
                                error -> {error, bad_request, Req2}
                            end
                    end
            end;
        {error, Req2} ->
            {error, forbidden, Req2}
    end.

%% Get library ID from user_id path binding (safe).
library_id(Req) ->
    {ok, LibId} = safe_int(cowboy_req:binding(user_id, Req)),
    LibId.

%% ===================================================================
%% Permissions
%% ===================================================================

%% Normalize legacy permission formats to canonical form.
normalize_perms(#{access := all}) ->
    #{library => true, write => true, files => true, notes => true};
normalize_perms(Perms) when is_map(Perms) ->
    #{
        library => maps:get(library, Perms, false),
        write => maps:get(write, Perms, false),
        files => maps:get(files, Perms, false),
        notes => maps:get(notes, Perms, false)
    };
normalize_perms(_) ->
    #{library => true, write => true, files => true, notes => true}.

%% Check a specific permission. Call after authorize/1.
check_perm(Perm) ->
    case get(shurbej_perms) of
        #{Perm := true} -> ok;
        _ -> {error, forbidden}
    end.

%% ===================================================================
%% Safe input parsing
%% ===================================================================

safe_int(Bin) when is_binary(Bin) ->
    try {ok, binary_to_integer(Bin)}
    catch error:badarg -> error
    end;
safe_int(_) -> error.

%% Read and decode a JSON body with size limit.
%% Returns {ok, Term, Req} | {error, Reason, Req}.
read_json_body(Req) ->
    case cowboy_req:read_body(Req, #{length => ?MAX_BODY_SIZE, period => 15000}) of
        {ok, Body, Req2} ->
            Decoded = maybe_decompress(Body, Req2),
            try {ok, simdjson:decode(Decoded), Req2}
            catch _:_ -> {error, invalid_json, Req2}
            end;
        {more, _, Req2} ->
            {error, body_too_large, Req2}
    end.

%% Validate MD5 is exactly 32 lowercase hex characters.
validate_md5(Md5) when is_binary(Md5), byte_size(Md5) =:= 32 ->
    case re:run(Md5, <<"^[0-9a-f]{32}$">>) of
        {match, _} -> ok;
        nomatch -> {error, invalid_md5}
    end;
validate_md5(_) -> {error, invalid_md5}.

%% Sanitize filename for Content-Disposition header.
sanitize_filename(Filename) ->
    %% Remove characters that could break Content-Disposition or allow CRLF injection
    Clean = binary:replace(
        binary:replace(
            binary:replace(
                binary:replace(Filename, <<"\"">>, <<>>, [global]),
                <<"\r">>, <<>>, [global]),
            <<"\n">>, <<>>, [global]),
        <<"\0">>, <<>>, [global]),
    case byte_size(Clean) of
        0 -> <<"file">>;
        _ -> Clean
    end.

%% ===================================================================
%% Query parameter parsers (all safe — no crashes on bad input)
%% ===================================================================

get_since(Req) ->
    #{since := Since} = cowboy_req:match_qs([{since, [], <<"0">>}], Req),
    case safe_int(Since) of {ok, N} -> max(0, N); error -> 0 end.

get_format(Req) ->
    #{format := Format} = cowboy_req:match_qs([{format, [], <<"json">>}], Req),
    Format.

get_if_unmodified(Req) ->
    case cowboy_req:header(<<"if-unmodified-since-version">>, Req) of
        undefined -> any;
        V -> case safe_int(V) of {ok, N} -> N; error -> any end
    end.

get_if_modified(Req) ->
    case cowboy_req:header(<<"if-modified-since-version">>, Req) of
        undefined -> undefined;
        V -> case safe_int(V) of {ok, N} -> N; error -> undefined end
    end.

get_item_keys(Req) ->
    #{itemKey := P} = cowboy_req:match_qs([{itemKey, [], <<>>}], Req),
    case P of <<>> -> all; _ -> binary:split(P, <<",">>, [global]) end.

get_collection_keys(Req) ->
    #{collectionKey := P} = cowboy_req:match_qs([{collectionKey, [], <<>>}], Req),
    case P of <<>> -> all; _ -> binary:split(P, <<",">>, [global]) end.

get_search_keys(Req) ->
    #{searchKey := P} = cowboy_req:match_qs([{searchKey, [], <<>>}], Req),
    case P of <<>> -> all; _ -> binary:split(P, <<",">>, [global]) end.

get_tag_filter(Req) ->
    #{tag := T} = cowboy_req:match_qs([{tag, [], <<>>}], Req),
    case T of <<>> -> none; _ -> T end.

get_item_type_filter(Req) ->
    #{itemType := T} = cowboy_req:match_qs([{itemType, [], <<>>}], Req),
    case T of <<>> -> none; _ -> T end.

get_query(Req) ->
    #{q := Q} = cowboy_req:match_qs([{q, [], <<>>}], Req),
    case Q of <<>> -> none; _ -> Q end.

get_qmode(Req) ->
    #{qmode := Mode} = cowboy_req:match_qs([{qmode, [], <<"titleCreatorYear">>}], Req),
    Mode.

get_include_trashed(Req) ->
    #{includeTrashed := V} = cowboy_req:match_qs([{includeTrashed, [], <<"0">>}], Req),
    V =:= <<"1">> orelse V =:= <<"true">>.

get_write_token(Req) ->
    cowboy_req:header(<<"zotero-write-token">>, Req).

get_limit(Req) ->
    #{limit := Limit} = cowboy_req:match_qs([{limit, [], <<"25">>}], Req),
    case safe_int(Limit) of {ok, N} -> min(max(1, N), 100); error -> 25 end.

get_start(Req) ->
    #{start := Start} = cowboy_req:match_qs([{start, [], <<"0">>}], Req),
    case safe_int(Start) of {ok, N} -> max(0, N); error -> 0 end.

get_sort(Req) ->
    #{sort := Sort} = cowboy_req:match_qs([{sort, [], <<"dateModified">>}], Req),
    Sort.

get_direction(Req) ->
    #{direction := Dir} = cowboy_req:match_qs([{direction, [], <<"desc">>}], Req),
    Dir.

%% ===================================================================
%% Pagination & sorting
%% ===================================================================

paginate(Items, Start, Limit) ->
    Total = length(Items),
    Safe = max(0, min(Start, Total)),
    Page = lists:sublist(lists:nthtail(Safe, Items), Limit),
    {Page, Total}.

sort_records(Records, SortField, Direction) ->
    ExtractFn = sort_key_fn(SortField),
    lists:sort(fun(A, B) ->
        KA = ExtractFn(A),
        KB = ExtractFn(B),
        case Direction of
            <<"asc">> -> KA =< KB;
            _ -> KA >= KB
        end
    end, Records).

sort_key_fn(<<"dateModified">>) ->
    fun(#shurbej_item{data = D}) -> maps:get(<<"dateModified">>, D, <<>>);
       (#shurbej_collection{data = D}) -> maps:get(<<"dateModified">>, D, <<>>);
       (#shurbej_search{data = D}) -> maps:get(<<"dateModified">>, D, <<>>)
    end;
sort_key_fn(<<"dateAdded">>) ->
    fun(#shurbej_item{data = D}) -> maps:get(<<"dateAdded">>, D, <<>>);
       (#shurbej_collection{data = D}) -> maps:get(<<"dateAdded">>, D, <<>>);
       (#shurbej_search{data = D}) -> maps:get(<<"dateAdded">>, D, <<>>)
    end;
sort_key_fn(<<"title">>) ->
    fun(#shurbej_item{data = D}) -> maps:get(<<"title">>, D, <<>>);
       (#shurbej_collection{data = D}) -> maps:get(<<"name">>, D, <<>>);
       (#shurbej_search{data = D}) -> maps:get(<<"name">>, D, <<>>)
    end;
sort_key_fn(<<"creator">>) ->
    fun(#shurbej_item{data = D}) ->
        case maps:get(<<"creators">>, D, []) of
            [C | _] -> maps:get(<<"lastName">>, C, maps:get(<<"name">>, C, <<>>));
            _ -> <<>>
        end;
       (_) -> <<>>
    end;
sort_key_fn(<<"itemType">>) ->
    fun(#shurbej_item{data = D}) -> maps:get(<<"itemType">>, D, <<>>);
       (_) -> <<>>
    end;
sort_key_fn(_) ->
    fun(#shurbej_item{version = V}) -> V;
       (#shurbej_collection{version = V}) -> V;
       (#shurbej_search{version = V}) -> V
    end.

%% Build a paginated list response with Total-Results and Link headers.
list_response(Req, Items, LibVersion, EnvelopeFn) ->
    Start = get_start(Req),
    Limit = get_limit(Req),
    {Page, Total} = paginate(Items, Start, Limit),
    Enveloped = [EnvelopeFn(I) || I <- Page],
    Headers = #{
        <<"content-type">> => <<"application/json">>,
        <<"last-modified-version">> => integer_to_binary(LibVersion),
        <<"total-results">> => integer_to_binary(Total),
        <<"zotero-api-version">> => <<"3">>
    },
    Headers2 = add_link_headers(Headers, Req, Start, Limit, Total),
    cowboy_req:reply(200, Headers2, simdjson:encode(Enveloped), Req).

add_link_headers(Headers, Req, Start, Limit, Total) ->
    Base = page_base_url(Req),
    Links = lists:flatten([
        [page_link(Base, Start + Limit, Limit, <<"next">>) || Start + Limit < Total],
        [page_link(Base, max(0, Start - Limit), Limit, <<"prev">>) || Start > 0]
    ]),
    case Links of
        [] -> Headers;
        _ -> Headers#{<<"link">> => iolist_to_binary(lists:join(<<", ">>, Links))}
    end.

page_base_url(Req) ->
    Path = cowboy_req:path(Req),
    QS = strip_qs_params(cowboy_req:qs(Req), [<<"start">>, <<"limit">>]),
    iolist_to_binary([Path, <<"?">>, QS]).

page_link(Base, Start, Limit, Rel) ->
    <<Base/binary, "&start=", (integer_to_binary(Start))/binary,
      "&limit=", (integer_to_binary(Limit))/binary,
      "; rel=\"", Rel/binary, "\"">>.

strip_qs_params(QS, Remove) ->
    Params = cow_qs:parse_qs(QS),
    Filtered = [{K, V} || {K, V} <- Params, not lists:member(K, Remove)],
    cow_qs:qs(Filtered).

%% ===================================================================
%% Filters
%% ===================================================================

check_304(Req, LibVersion) ->
    case get_if_modified(Req) of
        V when is_integer(V), V >= LibVersion ->
            {304, cowboy_req:reply(304, #{
                <<"last-modified-version">> => integer_to_binary(LibVersion)
            }, Req)};
        _ ->
            continue
    end.

filter_by_keys(Records, all) -> Records;
filter_by_keys(Records, Keys) ->
    KeySet = sets:from_list(Keys),
    [R || R <- Records, sets:is_element(record_key(R), KeySet)].

record_key(#shurbej_collection{id = {_, K}}) -> K;
record_key(#shurbej_search{id = {_, K}}) -> K;
record_key(#shurbej_item{id = {_, K}}) -> K.

filter_by_tag(Items, none) -> Items;
filter_by_tag(Items, Tag) ->
    [I || #shurbej_item{data = D} = I <- Items,
     lists:any(fun(T) -> maps:get(<<"tag">>, T, <<>>) =:= Tag end,
               maps:get(<<"tags">>, D, []))].

filter_by_item_type(Items, none) -> Items;
filter_by_item_type(Items, Type) ->
    [I || #shurbej_item{data = D} = I <- Items,
     maps:get(<<"itemType">>, D, <<>>) =:= Type].

filter_by_query(Items, none, _Mode) -> Items;
filter_by_query(Items, Query, Mode) ->
    Lower = string:lowercase(Query),
    [I || #shurbej_item{data = D} = I <- Items,
     matches_query(D, Lower, Mode)].

matches_query(Data, Query, <<"everything">>) ->
    maps:fold(fun(_K, V, Acc) ->
        Acc orelse (is_binary(V) andalso
                    binary:match(string:lowercase(V), Query) =/= nomatch)
    end, false, Data);
matches_query(Data, Query, _TitleCreatorYear) ->
    Title = string:lowercase(maps:get(<<"title">>, Data, <<>>)),
    Date = string:lowercase(maps:get(<<"date">>, Data, <<>>)),
    CreatorStr = case maps:get(<<"creators">>, Data, []) of
        [C | _] ->
            Name = maps:get(<<"name">>, C, <<>>),
            Last = maps:get(<<"lastName">>, C, <<>>),
            First = maps:get(<<"firstName">>, C, <<>>),
            string:lowercase(<<Name/binary, " ", Last/binary, " ", First/binary>>);
        _ -> <<>>
    end,
    binary:match(Title, Query) =/= nomatch orelse
    binary:match(CreatorStr, Query) =/= nomatch orelse
    binary:match(Date, Query) =/= nomatch.

%% ===================================================================
%% JSON responses
%% ===================================================================

json_response(StatusCode, Body, Req) ->
    cowboy_req:reply(StatusCode, #{
        <<"content-type">> => <<"application/json">>,
        <<"zotero-api-version">> => <<"3">>
    }, simdjson:encode(Body), Req).

json_response(StatusCode, Body, Version, Req) ->
    cowboy_req:reply(StatusCode, #{
        <<"content-type">> => <<"application/json">>,
        <<"last-modified-version">> => integer_to_binary(Version),
        <<"zotero-api-version">> => <<"3">>
    }, simdjson:encode(Body), Req).

error_response(StatusCode, Message, Req) ->
    json_response(StatusCode, #{<<"message">> => Message}, Req).

auth_error_response(rate_limited, Req) ->
    cowboy_req:reply(429, #{
        <<"content-type">> => <<"application/json">>,
        <<"retry-after">> => <<"60">>,
        <<"zotero-api-version">> => <<"3">>
    }, simdjson:encode(#{<<"message">> => <<"Rate limit exceeded. Try again later.">>}), Req);
auth_error_response(_, Req) ->
    error_response(403, <<"Forbidden">>, Req).

%% ===================================================================
%% Envelope helpers — wrap raw data in Zotero API format
%% ===================================================================

base_url() ->
    to_binary(application:get_env(shurbej, base_url, <<"http://localhost:8080">>)).

envelope_item(LibId, Item) ->
    envelope_item(LibId, Item, #{}).

envelope_item(LibId, #shurbej_item{id = {_, Key}, version = Version, data = Data}, ChildrenCounts) ->
    Base = base_url(),
    LibBin = integer_to_binary(LibId),
    NumChildren = maps:get(Key, ChildrenCounts, 0),
    #{
        <<"key">> => Key,
        <<"version">> => Version,
        <<"library">> => library_obj(LibId),
        <<"links">> => #{
            <<"self">> => #{
                <<"href">> => <<Base/binary, "/users/", LibBin/binary, "/items/", Key/binary>>,
                <<"type">> => <<"application/json">>
            },
            <<"alternate">> => #{
                <<"href">> => <<Base/binary, "/users/", LibBin/binary, "/items/", Key/binary>>,
                <<"type">> => <<"text/html">>
            }
        },
        <<"meta">> => #{<<"numChildren">> => NumChildren},
        <<"data">> => Data#{<<"key">> => Key, <<"version">> => Version}
    }.

envelope_collection(LibId, #shurbej_collection{id = {_, Key}, version = Version, data = Data}) ->
    Base = base_url(),
    LibBin = integer_to_binary(LibId),
    NumColls = maps:get(<<"numCollections">>, Data, 0),
    #{
        <<"key">> => Key,
        <<"version">> => Version,
        <<"library">> => library_obj(LibId),
        <<"links">> => #{
            <<"self">> => #{
                <<"href">> => <<Base/binary, "/users/", LibBin/binary, "/collections/", Key/binary>>,
                <<"type">> => <<"application/json">>
            }
        },
        <<"meta">> => #{<<"numCollections">> => NumColls, <<"numItems">> => 0},
        <<"data">> => Data#{<<"key">> => Key, <<"version">> => Version}
    }.

envelope_search(LibId, #shurbej_search{id = {_, Key}, version = Version, data = Data}) ->
    Base = base_url(),
    LibBin = integer_to_binary(LibId),
    #{
        <<"key">> => Key,
        <<"version">> => Version,
        <<"library">> => library_obj(LibId),
        <<"links">> => #{
            <<"self">> => #{
                <<"href">> => <<Base/binary, "/users/", LibBin/binary, "/searches/", Key/binary>>,
                <<"type">> => <<"application/json">>
            }
        },
        <<"meta">> => #{},
        <<"data">> => Data#{<<"key">> => Key, <<"version">> => Version}
    }.

library_obj(LibId) ->
    #{<<"type">> => <<"user">>, <<"id">> => LibId}.

maybe_decompress(Body, Req) ->
    case cowboy_req:header(<<"content-encoding">>, Req) of
        <<"gzip">> ->
            try zlib:gunzip(Body)
            catch _:_ -> Body
            end;
        _ -> Body
    end.

to_binary(B) when is_binary(B) -> B;
to_binary(L) when is_list(L) -> list_to_binary(L).
