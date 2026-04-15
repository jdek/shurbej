-module(shurbey_validate).

-export([item/1, collection/1, search/1, setting/2, key_format/1, item_types/0]).

item_types() ->
    shurbey_schema_data:item_types().

%% Validate an item map. Returns ok | {error, Reason}.
item(Item) when is_map(Item) ->
    checks([
        fun() -> require_field(<<"itemType">>, Item) end,
        fun() -> validate_item_type(Item) end,
        fun() -> validate_key_if_present(Item) end,
        fun() -> validate_tags(Item) end,
        fun() -> validate_creators(Item) end,
        fun() -> validate_collections_field(Item) end
    ]);
item(_) ->
    {error, <<"Item must be a JSON object">>}.

%% Validate a collection map.
collection(Coll) when is_map(Coll) ->
    checks([
        fun() -> require_field(<<"name">>, Coll) end,
        fun() -> validate_key_if_present(Coll) end,
        fun() -> validate_string_if_present(<<"name">>, Coll) end
    ]);
collection(_) ->
    {error, <<"Collection must be a JSON object">>}.

%% Validate a search map.
search(Search) when is_map(Search) ->
    checks([
        fun() -> require_field(<<"name">>, Search) end,
        fun() -> validate_key_if_present(Search) end
    ]);
search(_) ->
    {error, <<"Search must be a JSON object">>}.

%% Validate a setting key and value.
setting(Key, Value) when is_binary(Key) ->
    case byte_size(Key) of
        0 -> {error, <<"Setting key must not be empty">>};
        _ when is_map(Value) -> ok;
        _ when is_list(Value) -> ok;
        _ when is_binary(Value) -> ok;
        _ when is_number(Value) -> ok;
        _ when is_boolean(Value) -> ok;
        _ -> {error, <<"Invalid setting value">>}
    end;
setting(_, _) ->
    {error, <<"Setting key must be a string">>}.

%% Validate key format: 8 chars from Zotero charset.
key_format(Key) when is_binary(Key) ->
    Valid = <<"23456789ABCDEFGHIJKLMNPQRSTUVWXYZ">>,
    case byte_size(Key) of
        8 ->
            case lists:all(fun(C) -> binary:match(Valid, <<C>>) =/= nomatch end,
                           binary_to_list(Key)) of
                true -> ok;
                false -> {error, <<"Key contains invalid characters">>}
            end;
        _ ->
            {error, <<"Key must be exactly 8 characters">>}
    end.

%% Internal

checks([]) -> ok;
checks([Check | Rest]) ->
    case Check() of
        ok -> checks(Rest);
        {error, _} = Err -> Err
    end.

require_field(Field, Map) ->
    case maps:get(Field, Map, undefined) of
        undefined -> {error, <<"Missing required field: ", Field/binary>>};
        <<>> -> {error, <<"Field must not be empty: ", Field/binary>>};
        _ -> ok
    end.

validate_item_type(Item) ->
    Type = maps:get(<<"itemType">>, Item),
    case lists:member(Type, item_types()) of
        true -> ok;
        false -> {error, <<"Unknown item type: ", Type/binary>>}
    end.

validate_key_if_present(Map) ->
    case maps:get(<<"key">>, Map, undefined) of
        undefined -> ok;
        Key -> key_format(Key)
    end.

validate_tags(Item) ->
    case maps:get(<<"tags">>, Item, []) of
        Tags when is_list(Tags) ->
            case lists:all(fun is_valid_tag/1, Tags) of
                true -> ok;
                false -> {error, <<"Each tag must be an object with a 'tag' string field">>}
            end;
        _ ->
            {error, <<"'tags' must be an array">>}
    end.

is_valid_tag(Tag) when is_map(Tag) ->
    case maps:get(<<"tag">>, Tag, undefined) of
        T when is_binary(T) -> true;
        _ -> false
    end;
is_valid_tag(_) -> false.

validate_creators(Item) ->
    case maps:get(<<"creators">>, Item, []) of
        Creators when is_list(Creators) ->
            case lists:all(fun is_valid_creator/1, Creators) of
                true -> ok;
                false -> {error, <<"Each creator must have 'creatorType' and either 'name' or 'firstName'/'lastName'">>}
            end;
        _ ->
            {error, <<"'creators' must be an array">>}
    end.

is_valid_creator(C) when is_map(C) ->
    HasType = is_binary(maps:get(<<"creatorType">>, C, undefined)),
    HasName = is_binary(maps:get(<<"name">>, C, undefined)),
    HasFirst = is_binary(maps:get(<<"firstName">>, C, undefined)),
    HasLast = is_binary(maps:get(<<"lastName">>, C, undefined)),
    HasType andalso (HasName orelse (HasFirst andalso HasLast));
is_valid_creator(_) -> false.

validate_collections_field(Item) ->
    case maps:get(<<"collections">>, Item, []) of
        Colls when is_list(Colls) ->
            case lists:all(fun is_binary/1, Colls) of
                true -> ok;
                false -> {error, <<"'collections' must be an array of key strings">>}
            end;
        _ ->
            {error, <<"'collections' must be an array">>}
    end.

validate_string_if_present(Field, Map) ->
    case maps:get(Field, Map, undefined) of
        undefined -> ok;
        V when is_binary(V) -> ok;
        _ -> {error, <<"Field must be a string: ", Field/binary>>}
    end.
