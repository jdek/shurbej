-module(shurbey_admin).
-include_lib("shurbey_store/include/shurbey_records.hrl").
-include_lib("stdlib/include/ms_transform.hrl").

-export([create_user/2, create_user/3, list_users/0, delete_user/1]).

create_user(Username, Password) when is_binary(Username), is_binary(Password) ->
    UserId = next_user_id(),
    create_user(Username, Password, UserId).

create_user(Username, Password, UserId) when is_binary(Username), is_binary(Password) ->
    case shurbey_db:get_user(Username) of
        {ok, _} ->
            {error, already_exists};
        undefined ->
            ok = shurbey_db:create_user(Username, Password, UserId),
            logger:notice("created user ~s (user_id=~p)", [Username, UserId]),
            ok
    end.

list_users() ->
    MS = ets:fun2ms(
        fun(#shurbey_user{username = U, user_id = Id}) -> {U, Id} end),
    mnesia:dirty_select(shurbey_user, MS).

delete_user(Username) ->
    mnesia:dirty_delete({shurbey_user, Username}).

next_user_id() ->
    %% Find max existing user_id + 1, or start at 1
    MS = ets:fun2ms(fun(#shurbey_user{user_id = Id}) -> Id end),
    case mnesia:dirty_select(shurbey_user, MS) of
        [] -> 1;
        Ids -> lists:max(Ids) + 1
    end.
