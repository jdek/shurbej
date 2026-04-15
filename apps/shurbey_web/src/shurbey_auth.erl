-module(shurbey_auth).
-export([verify/1, key_info/1]).

verify(Key) ->
    shurbey_db:verify_key(Key).

key_info(Key) ->
    shurbey_db:get_key_info(Key).
