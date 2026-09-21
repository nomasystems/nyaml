-module(nyaml_emit).

-moduledoc """
Recursive YAML value emitter.

Walks a `nyaml:yaml_value()` and produces a YAML document body in block
style, falling back to flow style only for empty containers. Map entries
are emitted in `maps:to_list/1` iteration order.

Indentation is fixed at two spaces per level. Container values nested
under a mapping entry are placed on the next line at parent indent + 2.
Sequences of mappings use the compact form (first key on the dash line).
Sequences of sequences use the verbose form (`-` on its own line).

Scalar keys and empty-collection keys are emitted inline before the colon.
Sequence keys, mapping keys, and `{binary, Bytes}` keys use the explicit
form: `?` on its own line, the key in block style, then `:` with the value.
A key that carries a tag takes that form so that the tag never shares a line
with the `:` of the entry.

A `{binary, Bytes}` value is a scalar and is written as a `!!binary` node,
which `nyaml:decode/2` reads back under `#{schema => extended}`.
""".

%%%-----------------------------------------------------------------------------
%% API EXPORTS
%%%-----------------------------------------------------------------------------
-export([
    emit/1,
    emit/2
]).

%%%-----------------------------------------------------------------------------
%% TYPES
%%%-----------------------------------------------------------------------------
-type kind() :: scalar | empty_list | empty_map | list | map.

%%%-----------------------------------------------------------------------------
%% API FUNCTIONS
%%%-----------------------------------------------------------------------------

-doc """
Emits a YAML value as an iolist representing a complete document body.

The result always ends with a newline.
""".
-spec emit(nyaml:yaml_value()) -> iolist().
emit(Value) ->
    emit(Value, 0).

-doc """
Emits a YAML value at the given indentation level.
""".
-spec emit(nyaml:yaml_value(), non_neg_integer()) -> iolist().
emit(Value, Indent) ->
    Pad = pad(Indent),
    case classify(Value) of
        scalar -> [Pad, nyaml_emit_scalar:emit(Value), $\n];
        empty_list -> [Pad, "[]\n"];
        empty_map -> [Pad, "{}\n"];
        list -> emit_block_sequence(Value, Indent);
        map -> emit_block_mapping(Value, Indent)
    end.

%%%-----------------------------------------------------------------------------
%% INTERNAL FUNCTIONS
%%%-----------------------------------------------------------------------------

-spec classify(nyaml:yaml_value()) -> kind().
classify(null) ->
    scalar;
classify(true) ->
    scalar;
classify(false) ->
    scalar;
classify(infinity) ->
    scalar;
classify(negative_infinity) ->
    scalar;
classify(nan) ->
    scalar;
classify(N) when is_number(N) -> scalar;
classify({binary, B}) when is_binary(B) -> scalar;
classify({{Y, Mo, D}, {H, Mi, S}}) when
    is_integer(Y),
    is_integer(Mo),
    is_integer(D),
    is_integer(H),
    is_integer(Mi),
    is_integer(S)
->
    scalar;
classify(B) when is_binary(B) -> scalar;
classify([]) ->
    empty_list;
classify(L) when is_list(L) -> list;
classify(M) when is_map(M), map_size(M) =:= 0 -> empty_map;
classify(M) when is_map(M) -> map.
-spec emit_after_colon(nyaml:yaml_value(), non_neg_integer()) -> iodata().
emit_after_colon(Value, Indent) ->
    case classify(Value) of
        scalar -> [$\s, nyaml_emit_scalar:emit(Value), $\n];
        empty_list -> <<" []\n">>;
        empty_map -> <<" {}\n">>;
        list -> [$\n, emit_block_sequence(Value, Indent)];
        map -> [$\n, emit_block_mapping(Value, Indent)]
    end.
-spec emit_block_mapping(map(), non_neg_integer()) -> iolist().
emit_block_mapping(Map, Indent) ->
    [emit_map_item(K, V, Indent) || {K, V} <- maps:to_list(Map)].
-spec emit_block_sequence([nyaml:yaml_value()], non_neg_integer()) -> iolist().
emit_block_sequence(List, Indent) ->
    [emit_seq_item(Item, Indent) || Item <- List].

-spec emit_compact_map(map(), non_neg_integer()) -> iolist().
emit_compact_map(Map, Indent) ->
    [{K1, V1} | Rest] = maps:to_list(Map),
    First = [emit_simple_key(K1), $:, emit_after_colon(V1, Indent + 2)],
    RestLines = [emit_map_item(K, V, Indent) || {K, V} <- Rest],
    [First, RestLines].

-spec emit_explicit_key(nyaml:yaml_value(), nyaml:yaml_value(), non_neg_integer()) -> iolist().
emit_explicit_key(Key, Value, Indent) ->
    Pad = pad(Indent),
    [Pad, "?\n", emit(Key, Indent + 2), Pad, $:, emit_after_colon(Value, Indent + 2)].
-spec emit_map_item(nyaml:yaml_value(), nyaml:yaml_value(), non_neg_integer()) -> iolist().
emit_map_item(Key, Value, Indent) ->
    case is_simple_key(Key) of
        true ->
            [pad(Indent), emit_simple_key(Key), $:, emit_after_colon(Value, Indent + 2)];
        false ->
            emit_explicit_key(Key, Value, Indent)
    end.
-spec emit_seq_item(nyaml:yaml_value(), non_neg_integer()) -> iolist().
emit_seq_item(Item, Indent) ->
    Pad = pad(Indent),
    case classify(Item) of
        scalar ->
            [Pad, "- ", nyaml_emit_scalar:emit(Item), $\n];
        empty_list ->
            [Pad, "- []\n"];
        empty_map ->
            [Pad, "- {}\n"];
        list ->
            [Pad, "-\n", emit_block_sequence(Item, Indent + 2)];
        map ->
            case is_simple_key(first_key(Item)) of
                true -> [Pad, "- ", emit_compact_map(Item, Indent + 2)];
                false -> [Pad, "-\n", emit_block_mapping(Item, Indent + 2)]
            end
    end.

-spec emit_simple_key(nyaml:yaml_value()) -> binary().
emit_simple_key(Key) ->
    case classify(Key) of
        scalar -> nyaml_emit_scalar:emit(Key);
        empty_list -> <<"[]">>;
        empty_map -> <<"{}">>
    end.

-spec first_key(map()) -> nyaml:yaml_value().
first_key(Map) ->
    [{K, _} | _] = maps:to_list(Map),
    K.

-spec is_simple_key(nyaml:yaml_value()) -> boolean().
is_simple_key({binary, B}) when is_binary(B) ->
    false;
is_simple_key(Key) ->
    lists:member(classify(Key), [scalar, empty_list, empty_map]).

-spec pad(non_neg_integer()) -> binary().
pad(0) -> <<>>;
pad(N) -> binary:copy(<<" ">>, N).
