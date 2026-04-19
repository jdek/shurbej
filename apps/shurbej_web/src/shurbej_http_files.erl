-module(shurbej_http_files).
-include_lib("shurbej_store/include/shurbej_records.hrl").

-export([init/2]).

init(Req0, State) ->
    case shurbej_http_common:authorize(Req0) of
        {ok, _LibRef, _} ->
            case shurbej_http_common:check_perm(files) of
                {error, forbidden} ->
                    Req = shurbej_http_common:error_response(403, <<"File access denied">>, Req0),
                    {ok, Req, State};
                ok ->
                    case maps:get(action, State, default) of
                        view -> handle_view(Req0, State);
                        view_url -> handle_view_url(Req0, State);
                        default -> handle(cowboy_req:method(Req0), Req0, State)
                    end
            end;
        {error, Reason, _} ->
            Req = shurbej_http_common:auth_error_response(Reason, Req0),
            {ok, Req, State}
    end.

%% GET — download file by looking up metadata, serving from SHA-256 blob store
handle(<<"GET">>, Req0, State) ->
    LibRef = shurbej_http_common:lib_ref(Req0),
    ItemKey = cowboy_req:binding(item_key, Req0),
    case shurbej_db:get_file_meta(LibRef, ItemKey) of
        {ok, #shurbej_file_meta{md5 = Md5, sha256 = Sha256, filename = Filename}} ->
            BlobFile = shurbej_files:blob_path(Sha256),
            case filelib:is_regular(BlobFile) of
                true ->
                    Req = cowboy_req:reply(200, shurbej_http_common:maybe_backoff(#{
                        <<"content-type">> => <<"application/octet-stream">>,
                        <<"content-disposition">> => <<"attachment; filename=\"",
                            (shurbej_http_common:sanitize_filename(Filename))/binary, "\"">>,
                        <<"etag">> => Md5
                    }), {sendfile, 0, filelib:file_size(BlobFile), BlobFile}, Req0),
                    {ok, Req, State};
                false ->
                    Req = shurbej_http_common:error_response(404, <<"File not found on disk">>, Req0),
                    {ok, Req, State}
            end;
        undefined ->
            Req = shurbej_http_common:error_response(404, <<"No file for this item">>, Req0),
            {ok, Req, State}
    end;

%% POST — upload authorization or file registration
handle(<<"POST">>, Req0, State) ->
    LibRef = shurbej_http_common:lib_ref(Req0),
    ItemKey = cowboy_req:binding(item_key, Req0),
    {ok, Body, Req1} = cowboy_req:read_body(Req0),
    case cowboy_req:header(<<"content-type">>, Req1) of
        <<"application/x-www-form-urlencoded", _/binary>> ->
            Params = cow_qs:parse_qs(Body),
            Upload = proplists:get_value(<<"upload">>, Params),
            UploadKeyParam = proplists:get_value(<<"uploadKey">>, Params),
            Md5 = proplists:get_value(<<"md5">>, Params),
            case classify_file_post(Upload, UploadKeyParam, Md5) of
                {register, UploadKey} ->
                    %% Registration: client confirms upload with uploadKey
                    case shurbej_files:register_upload(UploadKey) of
                        {ok, NewVersion} ->
                            Req = cowboy_req:reply(204, shurbej_http_common:maybe_backoff(#{
                                <<"last-modified-version">> => integer_to_binary(NewVersion)
                            }), Req1),
                            {ok, Req, State};
                        {error, not_found} ->
                            Req = shurbej_http_common:error_response(400, <<"Invalid upload key">>, Req1),
                            {ok, Req, State};
                        {error, not_stored} ->
                            Req = shurbej_http_common:error_response(400, <<"File not yet uploaded">>, Req1),
                            {ok, Req, State};
                        {error, precondition_failed} ->
                            Req = shurbej_http_common:error_response(412, <<"Library version conflict">>, Req1),
                            {ok, Req, State}
                    end;
                {authorize, Md5} ->
                    %% Upload authorization: validate inputs
                    case shurbej_http_common:validate_md5(Md5) of
                        {error, _} ->
                            Req = shurbej_http_common:error_response(400, <<"Invalid MD5 hash">>, Req1),
                            {ok, Req, State};
                        ok ->
                    Filename = shurbej_http_common:sanitize_filename(
                        proplists:get_value(<<"filename">>, Params, <<"file">>)),
                    Filesize = case shurbej_http_common:safe_int(
                        proplists:get_value(<<"filesize">>, Params, <<"0">>)) of
                        {ok, FS} -> FS; error -> 0
                    end,
                    Mtime = case shurbej_http_common:safe_int(
                        proplists:get_value(<<"mtime">>, Params, <<"0">>)) of
                        {ok, MT} -> MT; error -> 0
                    end,
                    IfNoneMatch = cowboy_req:header(<<"if-none-match">>, Req1),
                    IfMatch = cowboy_req:header(<<"if-match">>, Req1),
                    ExistingMeta = shurbej_db:get_file_meta(LibRef, ItemKey),
                    case check_file_preconditions(IfNoneMatch, IfMatch, ExistingMeta) of
                        {error, precondition_required} ->
                            Req = shurbej_http_common:error_response(428,
                                <<"If-None-Match: * or If-Match: <md5> required">>, Req1),
                            {ok, Req, State};
                        {error, precondition_failed} ->
                            Req = shurbej_http_common:error_response(412,
                                <<"File has been modified">>, Req1),
                            {ok, Req, State};
                        ok ->
                    case ExistingMeta of
                        {ok, #shurbej_file_meta{md5 = Md5}} ->
                            %% Bump version through the gen_server so concurrent
                            %% exists + registration responses stay ordered.
                            {ok, NewVer} = shurbej_files:confirm_existing(LibRef, ItemKey),
                            Req = shurbej_http_common:json_response(200, #{<<"exists">> => 1}, NewVer, Req1),
                            {ok, Req, State};
                        _ ->
                            %% New file — require upload. SHA-256 dedup happens in store().
                                    UploadKey = shurbej_files:prepare_upload(LibRef, ItemKey, #{
                                        md5 => Md5, filename => Filename,
                                        filesize => Filesize, mtime => Mtime
                                    }),
                                    BaseUrl = application:get_env(shurbej, base_url, <<"http://localhost:8080">>),
                                    UploadUrl = iolist_to_binary([BaseUrl, "/upload/", UploadKey]),
                                    Req = shurbej_http_common:json_response(200, #{
                                        <<"url">> => UploadUrl,
                                        <<"contentType">> => <<"application/x-www-form-urlencoded">>,
                                        <<"prefix">> => <<>>,
                                        <<"suffix">> => <<>>,
                                        <<"uploadKey">> => UploadKey
                                    }, Req1),
                                    {ok, Req, State}
                    end
                    end %% close check_file_preconditions case
                    end; %% close validate_md5 case
                _ ->
                    Req = shurbej_http_common:error_response(400, <<"Missing required parameters">>, Req1),
                    {ok, Req, State}
            end;
        _ ->
            Req = shurbej_http_common:error_response(400, <<"Unsupported content type">>, Req1),
            {ok, Req, State}
    end;

handle(_, Req0, State) ->
    Req = shurbej_http_common:error_response(405, <<"Method not allowed">>, Req0),
    {ok, Req, State}.

%% GET /items/:item_key/file/view — serve file inline
handle_view(Req0, State) ->
    case cowboy_req:method(Req0) of
        <<"GET">> ->
            LibRef = shurbej_http_common:lib_ref(Req0),
            ItemKey = cowboy_req:binding(item_key, Req0),
            case shurbej_db:get_file_meta(LibRef, ItemKey) of
                {ok, #shurbej_file_meta{sha256 = Sha256, filename = Filename}} ->
                    BlobFile = shurbej_files:blob_path(Sha256),
                    case filelib:is_regular(BlobFile) of
                        true ->
                            ContentType = guess_content_type(Filename),
                            SafeName = shurbej_http_common:sanitize_filename(Filename),
                            Req = cowboy_req:reply(200, shurbej_http_common:maybe_backoff(#{
                                <<"content-type">> => ContentType,
                                <<"content-disposition">> =>
                                    <<"inline; filename=\"", SafeName/binary, "\"">>
                            }), {sendfile, 0, filelib:file_size(BlobFile), BlobFile}, Req0),
                            {ok, Req, State};
                        false ->
                            Req = shurbej_http_common:error_response(404,
                                <<"File not found on disk">>, Req0),
                            {ok, Req, State}
                    end;
                undefined ->
                    Req = shurbej_http_common:error_response(404,
                        <<"No file for this item">>, Req0),
                    {ok, Req, State}
            end;
        _ ->
            Req = shurbej_http_common:error_response(405, <<"Method not allowed">>, Req0),
            {ok, Req, State}
    end.

%% GET /items/:item_key/file/view/url — return URL to the file
handle_view_url(Req0, State) ->
    case cowboy_req:method(Req0) of
        <<"GET">> ->
            LibRef = shurbej_http_common:lib_ref(Req0),
            ItemKey = cowboy_req:binding(item_key, Req0),
            case shurbej_db:get_file_meta(LibRef, ItemKey) of
                {ok, _} ->
                    Base = shurbej_http_common:base_url(),
                    Prefix = shurbej_http_common:lib_path_prefix(LibRef),
                    Url = <<Base/binary, Prefix/binary,
                            "/items/", ItemKey/binary, "/file/view">>,
                    Req = shurbej_http_common:json_response(200, #{<<"url">> => Url}, Req0),
                    {ok, Req, State};
                undefined ->
                    Req = shurbej_http_common:error_response(404,
                        <<"No file for this item">>, Req0),
                    {ok, Req, State}
            end;
        _ ->
            Req = shurbej_http_common:error_response(405, <<"Method not allowed">>, Req0),
            {ok, Req, State}
    end.

%% Check If-None-Match / If-Match preconditions for file uploads.
check_file_preconditions(<<"*">>, _, undefined) ->
    ok; %% If-None-Match: * and no existing file — new upload
check_file_preconditions(<<"*">>, _, {ok, _}) ->
    {error, precondition_failed}; %% If-None-Match: * but file exists
check_file_preconditions(_, IfMatch, {ok, #shurbej_file_meta{md5 = ExistingMd5}})
        when is_binary(IfMatch) ->
    case IfMatch =:= ExistingMd5 of
        true -> ok;
        false -> {error, precondition_failed}
    end;
check_file_preconditions(_, IfMatch, undefined) when is_binary(IfMatch) ->
    {error, precondition_failed}; %% If-Match but no existing file
check_file_preconditions(undefined, undefined, _) ->
    {error, precondition_required}.

%% Classify a POST to /file as authorization or registration.
%% Zotero uses: upload=<key> for registration, md5+filename+filesize for authorization.
%% The "upload" param is "1" for auth in some clients, or the upload key for registration.
classify_file_post(_Upload, UploadKey, _Md5) when UploadKey =/= undefined ->
    {register, UploadKey};
classify_file_post(Upload, _, _Md5) when Upload =/= undefined, Upload =/= <<"1">> ->
    %% upload=<hex_key> — this is registration (Zotero sends upload=<uploadKey>)
    {register, Upload};
classify_file_post(_, _, Md5) when Md5 =/= undefined ->
    {authorize, Md5};
classify_file_post(<<"1">>, _, _) ->
    %% upload=1 with no md5 — malformed auth request
    bad_request;
classify_file_post(_, _, _) ->
    bad_request.

guess_content_type(Filename) ->
    case filename:extension(string:lowercase(Filename)) of
        <<".pdf">> -> <<"application/pdf">>;
        <<".html">> -> <<"text/html">>;
        <<".htm">> -> <<"text/html">>;
        <<".txt">> -> <<"text/plain">>;
        <<".png">> -> <<"image/png">>;
        <<".jpg">> -> <<"image/jpeg">>;
        <<".jpeg">> -> <<"image/jpeg">>;
        <<".gif">> -> <<"image/gif">>;
        <<".svg">> -> <<"image/svg+xml">>;
        <<".epub">> -> <<"application/epub+zip">>;
        _ -> <<"application/octet-stream">>
    end.
