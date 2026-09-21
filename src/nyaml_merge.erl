-module(nyaml_merge).

-moduledoc """
The merge key of the YAML 1.1 type repository.

The `merge` entry of the repository gives `<<` the tag
`tag:yaml.org,2002:merge` and defines it: "The "<<" merge key is used to
indicate that all the keys of one or more specified maps should be inserted
into the current map. If the value associated with the key is a single mapping
node, each of its key/value pairs is inserted into the current mapping, unless
the key already exists in it. If the value associated with the merge key is a
sequence, then this sequence is expected to contain mapping nodes and each of
these nodes is merged in turn according to its order in the sequence. Keys in
mapping nodes earlier in the sequence override keys specified in later mapping
nodes."

`nyaml:decode/2` resolves the key under `#{schema => extended}` alone, and the
key resolves in the key position alone, because the merge tag has no native
value that a value position can hold.

A mapping accumulates into `acc()`. An entry whose key is the merge key goes to
the merge slot of the accumulator, and every other entry goes to the map.
`close/1` ends the mapping: it reads the slot, and it applies the keys of the
enclosing mapping over the merged ones, so an own key wins.
""".

%%%-----------------------------------------------------------------------------
%% API EXPORTS
%%%-----------------------------------------------------------------------------
-export([
    add_entry/3,
    close/1,
    new/1,
    resolve_key/2,
    unmark/1
]).

%%%-----------------------------------------------------------------------------
%% TYPE EXPORTS
%%%-----------------------------------------------------------------------------
-export_type([
    acc/0,
    key/0,
    merge_error/0,
    merge_key/0
]).

%%%-----------------------------------------------------------------------------
%% TYPES
%%%-----------------------------------------------------------------------------
-type yaml_map() :: #{nyaml:yaml_value() => nyaml:yaml_value()}.

-type merge_key() :: '$merge'.

-type key() :: nyaml:yaml_value() | merge_key().

-type merge_slot() :: none | {merge, nyaml:yaml_value()}.

-opaque acc() :: {yaml_map(), merge_slot()}.

-type merge_error() :: {merge_value_not_a_mapping, nyaml_parser:node_kind()}.

%%%-----------------------------------------------------------------------------
%% MACROS
%%%-----------------------------------------------------------------------------
-define(MERGE_KEY, '$merge').

%%%-----------------------------------------------------------------------------
%% API FUNCTIONS
%%%-----------------------------------------------------------------------------

-doc """
Adds one entry of a mapping to the accumulator.

The merge key goes to the merge slot. A second merge key in the same mapping
replaces the first, which is the binding that a duplicate key keeps.
""".
-spec add_entry(key(), nyaml:yaml_value(), acc()) -> acc().
add_entry(?MERGE_KEY, Value, {Map, _Slot}) ->
    {Map, {merge, Value}};
add_entry(Key, Value, {Map, Slot}) ->
    {Map#{Key => Value}, Slot}.

-doc """
Ends a mapping and gives the map that it holds.

The value of the merge key is a mapping, or a sequence of mappings. Every key
of it enters the map unless the map already holds that key, and a mapping
earlier in the sequence wins over a later one. Any other value returns
`{merge_value_not_a_mapping, Kind}`, where `Kind` is the kind of the node that
the key names.
""".
-spec close(acc()) -> {ok, yaml_map()} | {error, merge_error()}.
close({Map, none}) ->
    {ok, Map};
close({Map, {merge, Value}}) ->
    maybe
        {ok, Merged} ?= merged_mappings(Value),
        {ok, maps:merge(Merged, Map)}
    end.

-doc """
Gives an accumulator that holds `Map` and no merge key.
""".
-spec new(yaml_map()) -> acc().
new(Map) ->
    {Map, none}.

-doc """
Resolves a plain mapping key.

The extended schema gives the plain `<<` key the merge tag of the type
repository. Every other key resolves under the core rules, and so does `<<`
under the core schema. A quoted key carries the `str` tag, so `"<<"` never
reaches this function and stays a string key under every schema.
""".
-spec resolve_key(binary(), nyaml_parser:ctx()) -> {ok, key()}.
resolve_key(<<"<<">> = Key, Ctx) ->
    case nyaml_parser:schema(Ctx) of
        extended -> {ok, ?MERGE_KEY};
        core -> nyaml_scalar:parse_key(Key)
    end;
resolve_key(Key, _Ctx) ->
    nyaml_scalar:parse_key(Key).

-doc """
Gives the text that a merge key carries.

The merge tag has no native value, so a tag over the key resolves over the
text and an anchor binds the text. `!!str <<` is the string key `<<"<<">>`,
and `&a <<` binds `<<"<<">>` to the anchor.
""".
-spec unmark(key()) -> nyaml:yaml_value().
unmark(?MERGE_KEY) ->
    <<"<<">>;
unmark(Key) ->
    Key.

%%%-----------------------------------------------------------------------------
%% INTERNAL FUNCTIONS
%%%-----------------------------------------------------------------------------

-spec merged_mappings(nyaml:yaml_value()) -> {ok, yaml_map()} | {error, merge_error()}.
merged_mappings(Map) when is_map(Map) ->
    {ok, Map};
merged_mappings(Values) when is_list(Values) ->
    merged_sequence(Values, #{});
merged_mappings(Value) ->
    {error, {merge_value_not_a_mapping, nyaml_parser:kind_of(Value)}}.

-spec merged_sequence([nyaml:yaml_value()], yaml_map()) ->
    {ok, yaml_map()} | {error, merge_error()}.
merged_sequence([], Acc) ->
    {ok, Acc};
merged_sequence([Map | Rest], Acc) when is_map(Map) ->
    merged_sequence(Rest, maps:merge(Map, Acc));
merged_sequence([Value | _Rest], _Acc) ->
    {error, {merge_value_not_a_mapping, nyaml_parser:kind_of(Value)}}.
