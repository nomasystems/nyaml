-module(nyaml).

-moduledoc """
Public API for the nyaml YAML parser and emitter.

`decode/1,2` and `decode_all/1,2` read a YAML 1.2 stream into Erlang terms.
`encode/1` writes a term back as a block style document. The input encoding is
detected from the byte order mark or the byte pattern, so UTF-8, UTF-16, and
UTF-32 all decode.

Two schemas resolve tags. `core` is the default and covers the tags of the
JSON schema. `extended` adds the types of the YAML 1.1 type repository that
this library carries. See `decode/2`.

## Anchors and aliases

An anchor names a node, and an alias repeats it under every schema.

```yaml
defaults: &defaults
  timeout: 30
  retries: 3

production: *defaults
staging: *defaults
```

## Merge keys

The merge key `<<` belongs to the YAML 1.1 type repository. The extended
schema resolves it, and the core schema keeps it as an ordinary key.

```yaml
defaults: &defaults
  timeout: 30
  retries: 3

production:
  <<: *defaults
  timeout: 60
```

Under `#{schema => extended}` every key of the aliased mapping enters the
enclosing mapping. A key that the enclosing mapping holds wins, so `timeout`
stays 60 and `retries` comes from the merge. The value of the key is one
mapping, or a sequence of mappings. A mapping earlier in the sequence wins
over a later one, and any other value returns
`{error, {merge_value_not_a_mapping, Kind}}`.

Under the core schema `<<: *defaults` binds the aliased mapping under the key
`<<"<<">>` and merges nothing. A quoted `"<<"` is a string key under both
schemas.

## Type tags

A tag overrides the resolution that the content of the node gives.

```yaml
explicit_string: !!str 123
explicit_int: !!int "456"
explicit_float: !!float "3.14"
explicit_bool: !!bool "true"
explicit_null: !!null ""
```

nyaml resolves `!!str`, `!!int`, `!!float`, `!!bool`, `!!null`, `!!seq`, and
`!!map` under both schemas. Any other tag leaves its node alone, so `!!set`
keeps the value that the kind of the node gives. Content that no token of the
tag matches returns `{error, {invalid_tag_content, Tag, Content}}`.
""".

%%%-----------------------------------------------------------------------------
%% API EXPORTS
%%%-----------------------------------------------------------------------------
-export([
    decode/1,
    decode/2,
    decode_all/1,
    decode_all/2,
    decode_file/1,
    encode/1
]).

%%%-----------------------------------------------------------------------------
%% TYPE EXPORTS
%%%-----------------------------------------------------------------------------
-export_type([
    decode_error/0,
    decode_options/0,
    schema/0,
    yaml_value/0
]).

%%%-----------------------------------------------------------------------------
%% TYPES
%%%-----------------------------------------------------------------------------
-type yaml_value() ::
    null
    | boolean()
    | number()
    | infinity
    | negative_infinity
    | nan
    | calendar:datetime()
    | binary()
    | {binary, binary()}
    | [yaml_value()]
    | #{yaml_value() => yaml_value()}.

-type schema() :: core | extended.

-type decode_options() :: #{
    schema => schema()
}.

-type decode_error() ::
    {file_error, file:posix()}
    | {encoding_error, nyaml_encoding:encoding_error()}
    | {unknown_schema, term()}
    | nyaml_parser:parse_error().

%%%-----------------------------------------------------------------------------
%% API FUNCTIONS
%%%-----------------------------------------------------------------------------

-doc """
Decodes a YAML binary into an Erlang term.

Returns the first document if the input contains multiple YAML documents.
Returns `{ok, null}` for empty input.
""".
-spec decode(binary()) -> {ok, yaml_value()} | {error, decode_error()}.
decode(Bin) when is_binary(Bin) ->
    decode(Bin, #{}).

-doc """
Decodes a YAML binary with options.

Options:
- `schema`: the tag resolution rules. `core` is the default and resolves the
  tags of the JSON schema alone, so `!!binary` keeps its base64 text and
  `!!bool` takes `true` and `false` alone. `extended` adds the types of the
  YAML 1.1 type repository that this library carries, so `!!binary` decodes
  its content into `{binary, Bytes}` and `!!bool` takes the `y`, `yes`, `on`,
  and `off` tokens beside those two. `extended` also resolves the merge key,
  so a plain `<<` key merges the mapping that it names into the enclosing one.
  The option changes tag resolution alone, so a plain scalar in a value
  position resolves under the core rules whichever schema is named. Any other
  value returns `{error, {unknown_schema, Value}}` before the parse starts.
""".
-spec decode(binary(), decode_options()) -> {ok, yaml_value()} | {error, decode_error()}.
decode(Bin, Opts) when is_binary(Bin), is_map(Opts) ->
    case decode_all(Bin, Opts) of
        {ok, []} -> {ok, null};
        {ok, [First | _]} -> {ok, First};
        {error, _} = Err -> Err
    end.

-doc """
Decodes all YAML documents from a binary.

Returns a list of decoded values, one per document in the stream.
""".
-spec decode_all(binary()) -> {ok, [yaml_value()]} | {error, decode_error()}.
decode_all(Bin) when is_binary(Bin) ->
    decode_all(Bin, #{}).

-doc """
Decodes all YAML documents from a binary with options.

Takes the same options as `decode/2`. The schema is stream scoped, so every
document of the stream resolves its tags under it.
""".
-spec decode_all(binary(), decode_options()) -> {ok, [yaml_value()]} | {error, decode_error()}.
decode_all(Bin, Opts) when is_binary(Bin), is_map(Opts) ->
    maybe
        {ok, Schema} ?= schema_of(Opts),
        {ok, Utf8Bin} ?= to_utf8(Bin),
        nyaml_parser:parse_stream(Utf8Bin, Schema)
    end.

-doc """
Decodes a YAML file into an Erlang term.

Reads the file and decodes its contents. Returns the first document
if the file contains multiple YAML documents.
""".
-spec decode_file(file:name_all()) -> {ok, yaml_value()} | {error, decode_error()}.
decode_file(Filename) ->
    case file:read_file(Filename) of
        {ok, Bin} -> decode(Bin);
        {error, Reason} -> {error, {file_error, Reason}}
    end.

-doc """
Encodes an Erlang term into a YAML binary.

Map entries are emitted in `maps:to_list/1` iteration order. Block style is
used for non-empty collections; flow style (`[]`, `{}`) only for empty ones.
Sequence and mapping keys use the explicit `?` form. A `{binary, Bytes}` value
is written as a `!!binary` node with base64 content, which `decode/2` reads
back under `#{schema => extended}`.

The result always ends with a newline.
""".
-spec encode(yaml_value()) -> {ok, binary()}.
encode(Value) ->
    {ok, iolist_to_binary(nyaml_emit:emit(Value))}.

%%%-----------------------------------------------------------------------------
%% INTERNAL FUNCTIONS
%%%-----------------------------------------------------------------------------

-spec schema_of(decode_options()) -> {ok, schema()} | {error, {unknown_schema, term()}}.
schema_of(#{schema := core}) -> {ok, core};
schema_of(#{schema := extended}) -> {ok, extended};
schema_of(#{schema := Other}) -> {error, {unknown_schema, Other}};
schema_of(#{}) -> {ok, core}.

-spec to_utf8(binary()) ->
    {ok, binary()} | {error, {encoding_error, nyaml_encoding:encoding_error()}}.
to_utf8(Bin) ->
    case nyaml_encoding:detect_and_convert(Bin) of
        {ok, Utf8Bin} -> {ok, Utf8Bin};
        {error, Reason} -> {error, {encoding_error, Reason}}
    end.
