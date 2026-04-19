-module(shurbej_http_upload).
-export([init/2]).

%% Handles the actual file upload at /upload/:upload_key.
%% Zotero may send as application/x-www-form-urlencoded (url-encoded bytes),
%% multipart/form-data (file in a "file" part), or raw octet-stream.
init(Req0, State) ->
    case cowboy_req:method(Req0) of
        <<"POST">> ->
            UploadKey = cowboy_req:binding(upload_key, Req0),
            case shurbej_files:get_pending(UploadKey) of
                {ok, Meta} ->
                    case read_file_data(Req0) of
                        {ok, Body, Req1} ->
                            handle_store(UploadKey, Meta, Body, Req1, State);
                        {error, too_large, Req1} ->
                            Req = shurbej_http_common:error_response(413,
                                <<"Uploaded file exceeds max size">>, Req1),
                            {ok, Req, State}
                    end;
                {error, not_found} ->
                    Req = shurbej_http_common:error_response(404, <<"Unknown upload key">>, Req0),
                    {ok, Req, State}
            end;
        _ ->
            Req = shurbej_http_common:error_response(405, <<"Method not allowed">>, Req0),
            {ok, Req, State}
    end.

handle_store(UploadKey, Meta, Body, Req1, State) ->
    case shurbej_files:store(UploadKey, Meta, Body) of
        ok ->
            Req = cowboy_req:reply(201, #{}, <<>>, Req1),
            {ok, Req, State};
        {error, md5_mismatch} ->
            Req = shurbej_http_common:error_response(412,
                <<"Uploaded file MD5 does not match expected hash">>, Req1),
            {ok, Req, State};
        {error, zip_too_large} ->
            Req = shurbej_http_common:error_response(413,
                <<"Decompressed upload exceeds max size">>, Req1),
            {ok, Req, State};
        {error, Reason} ->
            logger:error("File storage error: ~p", [Reason]),
            Req = shurbej_http_common:error_response(500,
                <<"File storage error">>, Req1),
            {ok, Req, State}
    end.

%% Read file data, handling different content-types.
%% Zotero sends raw bytes with Content-Type: application/x-www-form-urlencoded
%% (not actually url-encoded) when prefix/suffix are empty.
%% For multipart, extract the "file" part.
read_file_data(Req) ->
    Max = max_upload_bytes(),
    case cowboy_req:header(<<"content-type">>, Req) of
        <<"multipart/form-data", _/binary>> ->
            read_multipart_file(Req, Max);
        _ ->
            read_full_body(Req, [], 0, Max)
    end.

%% Read multipart body, extract the "file" part.
read_multipart_file(Req0, Max) ->
    case cowboy_req:read_part(Req0) of
        {ok, Headers, Req1} ->
            case cow_multipart:form_data(Headers) of
                {file, <<"file">>, _Filename, _CT} ->
                    read_part_body(Req1, [], 0, Max);
                _ ->
                    %% Skip non-file parts; still enforce the cap so an
                    %% attacker can't stream unbounded data in a junk part.
                    case read_part_body(Req1, [], 0, Max) of
                        {ok, _Skip, Req2} -> read_multipart_file(Req2, Max);
                        {error, _, _} = Err -> Err
                    end
            end;
        {done, Req1} ->
            {ok, <<>>, Req1}
    end.

%% Accumulate chunks, flatten once at the end. Reject if total exceeds Max.
read_part_body(Req0, Acc, Size, Max) ->
    case cowboy_req:read_part_body(Req0, #{length => 8_000_000, period => 30000}) of
        {ok, Body, Req} ->
            NewSize = Size + byte_size(Body),
            case NewSize > Max of
                true -> {error, too_large, Req};
                false -> {ok, iolist_to_binary(lists:reverse([Body | Acc])), Req}
            end;
        {more, Body, Req} ->
            NewSize = Size + byte_size(Body),
            case NewSize > Max of
                true -> {error, too_large, Req};
                false -> read_part_body(Req, [Body | Acc], NewSize, Max)
            end
    end.

read_full_body(Req0, Acc, Size, Max) ->
    case cowboy_req:read_body(Req0, #{length => 8_000_000, period => 30000}) of
        {ok, Body, Req} ->
            NewSize = Size + byte_size(Body),
            case NewSize > Max of
                true -> {error, too_large, Req};
                false -> {ok, iolist_to_binary(lists:reverse([Body | Acc])), Req}
            end;
        {more, Body, Req} ->
            NewSize = Size + byte_size(Body),
            case NewSize > Max of
                true -> {error, too_large, Req};
                false -> read_full_body(Req, [Body | Acc], NewSize, Max)
            end
    end.

max_upload_bytes() ->
    application:get_env(shurbej, max_upload_bytes, 100 * 1024 * 1024).
