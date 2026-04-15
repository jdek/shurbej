-module(shurbey_http_upload).
-export([init/2]).

%% Handles the actual file upload at /upload/:upload_key.
%% Zotero may send as application/x-www-form-urlencoded (url-encoded bytes),
%% multipart/form-data (file in a "file" part), or raw octet-stream.
init(Req0, State) ->
    case cowboy_req:method(Req0) of
        <<"POST">> ->
            UploadKey = cowboy_req:binding(upload_key, Req0),
            case shurbey_files:get_pending(UploadKey) of
                {ok, Meta} ->
                    {Body, Req1} = read_file_data(Req0),
                    case shurbey_files:store(UploadKey, Meta, Body) of
                        ok ->
                            Req = cowboy_req:reply(201, #{}, <<>>, Req1),
                            {ok, Req, State};
                        {error, md5_mismatch} ->
                            Req = shurbey_http_common:error_response(412,
                                <<"Uploaded file MD5 does not match expected hash">>, Req1),
                            {ok, Req, State};
                        {error, Reason} ->
                            logger:error("File storage error: ~p", [Reason]),
                            Req = shurbey_http_common:error_response(500,
                                <<"File storage error">>, Req1),
                            {ok, Req, State}
                    end;
                {error, not_found} ->
                    Req = shurbey_http_common:error_response(404, <<"Unknown upload key">>, Req0),
                    {ok, Req, State}
            end;
        _ ->
            Req = shurbey_http_common:error_response(405, <<"Method not allowed">>, Req0),
            {ok, Req, State}
    end.

%% Read file data, handling different content-types.
%% Zotero sends raw bytes with Content-Type: application/x-www-form-urlencoded
%% (not actually url-encoded) when prefix/suffix are empty.
%% For multipart, extract the "file" part.
read_file_data(Req) ->
    case cowboy_req:header(<<"content-type">>, Req) of
        <<"multipart/form-data", _/binary>> ->
            read_multipart_file(Req);
        _ ->
            {ok, Body, Req1} = read_full_body(Req, []),
            {Body, Req1}
    end.

%% Read multipart body, extract the "file" part.
read_multipart_file(Req0) ->
    case cowboy_req:read_part(Req0) of
        {ok, Headers, Req1} ->
            case cow_multipart:form_data(Headers) of
                {file, <<"file">>, _Filename, _CT} ->
                    {ok, Body, Req2} = read_part_body(Req1, []),
                    {Body, Req2};
                _ ->
                    %% Skip non-file parts
                    {ok, _Skip, Req2} = read_part_body(Req1, []),
                    read_multipart_file(Req2)
            end;
        {done, Req1} ->
            {<<>>, Req1}
    end.

%% Accumulate chunks in a reversed list, flatten once at the end.
read_part_body(Req0, Acc) ->
    case cowboy_req:read_part_body(Req0) of
        {ok, Body, Req} -> {ok, iolist_to_binary(lists:reverse([Body | Acc])), Req};
        {more, Body, Req} -> read_part_body(Req, [Body | Acc])
    end.

read_full_body(Req0, Acc) ->
    case cowboy_req:read_body(Req0, #{length => 8_000_000, period => 30000}) of
        {ok, Body, Req} -> {ok, iolist_to_binary(lists:reverse([Body | Acc])), Req};
        {more, Body, Req} -> read_full_body(Req, [Body | Acc])
    end.
