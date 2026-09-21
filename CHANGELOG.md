# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-09-21

Initial public release.

### Added

- `nyaml:decode/1,2` reads a YAML 1.2 stream into Erlang terms and gives the
  first document of it. `nyaml:decode_all/1,2` gives every document of the
  stream, and `nyaml:decode_file/1` reads a file. Empty input gives
  `{ok, null}`.
- `nyaml:encode/1` writes a term back as a block style document. Flow style
  serves the empty collections alone, a sequence or a mapping key takes the
  explicit `?` form, and the result ends with a newline.
- Block and flow collections, multi-document streams, and the `%YAML` and
  `%TAG` directives.
- Block scalars: literal (`|`) and folded (`>`), with every indentation and
  chomping indicator.
- Anchors and aliases.
- Type tags. A tag overrides the resolution that the content of the node
  gives, and content that the tag does not admit is an error rather than the
  raw text: `nyaml:decode(<<"!!bool zzz">>)` gives
  `{error, {invalid_tag_content, <<"bool">>, <<"zzz">>}}`.
- Scalar resolution for null, booleans, integers, floats, and strings, beside
  ISO8601 timestamps, hex (`0x`) and octal (`0o`) integers, infinity, NaN,
  scientific notation, and signed numbers. A key resolves under the same rules
  as a value, so a quoted key is the way to keep it a string.
- Two tag schemas, named by the `schema` option of `decode/2` and
  `decode_all/2`. `core` is the default and resolves the tags of the YAML 1.2
  core schema alone. `extended` adds the types of the YAML 1.1 type repository
  that this library carries. Any other value returns
  `{error, {unknown_schema, Value}}` before the parse starts. The schema is
  stream scoped, and it moves tag resolution alone: a plain scalar resolves
  under the core rules whichever schema is named.
- The merge key under `#{schema => extended}`. A plain `<<` key merges the
  mapping that it names into the enclosing one, in a block mapping and in a
  flow mapping alike. A key that the enclosing mapping holds wins over a
  merged one. The value of the key is one mapping, or a sequence of mappings
  where an earlier one wins over a later one, and any other value returns
  `{error, {merge_value_not_a_mapping, Kind}}`. Under `core` the plain `<<`
  stays an ordinary key, and a quoted `"<<"` is a string key under both
  schemas.
- The YAML 1.1 boolean tokens under `#{schema => extended}`. An explicit
  `!!bool` tag takes `y`, `yes`, and `on` with their negatives, in the lower
  case, title case, and upper case spellings that the type repository lists,
  beside the six spellings of `true` and `false` that the core schema
  resolves. A plain scalar does not move: a bare `yes` is the string
  `<<"yes">>` under every schema.
- The `binary` tag under `#{schema => extended}`. `!!binary` decodes its
  base64 content into `{binary, Bytes}`, and `encode/1` writes that term back
  as a `!!binary` node. Content that is not base64 returns
  `{error, {invalid_base64, Content}}`, and a sequence or a mapping under the
  tag returns `{error, {tag_kind_mismatch, <<"binary">>, Kind}}`. Under `core`
  the tag keeps its base64 text.
- Encoding detection for UTF-8, UTF-16 (BE/LE), and UTF-32 (BE/LE), from the
  byte order mark or from the byte pattern.
- An API where every function gives `{ok, Value}` or `{error, Reason}` and
  none of them throws, over the OTP `kernel` and `stdlib` applications and no
  other dependency.
- A full run of `rebar3 compliance` against the `data-2022-01-17` fixture tag
  of the official yaml-test-suite gives 402 of 402 cases: 308 valid documents
  parsed and 94 invalid documents rejected, with an empty skip list. The
  fixture is vendored as a git submodule.
