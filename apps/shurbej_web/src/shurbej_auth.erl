-module(shurbej_auth).
-export([verify/1, key_info/1]).

verify(Key) ->
    shurbej_db:verify_key(Key).

key_info(Key) ->
    shurbej_db:get_key_info(Key).
