# nyaml

[![Hex.pm](https://img.shields.io/hexpm/v/nyaml.svg)](https://hex.pm/packages/nyaml)
[![CI](https://github.com/nomasystems/nyaml/actions/workflows/ci.yml/badge.svg)](https://github.com/nomasystems/nyaml/actions/workflows/ci.yml)
[![YAML Test Suite](https://img.shields.io/badge/YAML%20Test%20Suite-402%2F402-brightgreen)](https://github.com/yaml/yaml-test-suite)

Spec-compliant YAML 1.2 parser and emitter for Erlang/OTP 27+.

## Getting started

```erlang
%% rebar.config
{deps, [nyaml]}.
```

### Decoding

```erlang
{ok, #{<<"server">> := #{<<"port">> := 8080}}} =
    nyaml:decode(<<"server:\n  port: 8080\n">>),
{ok, [First, Second]} = nyaml:decode_all(<<"---\nfirst\n---\nsecond">>),
{ok, Config} = nyaml:decode_file("config.yaml").
```

`decode/1` gives the first document of the stream, `decode_all/1` gives every
one. Both take `#{schema => core | extended}` in their arity 2 form. The core
schema is the default and resolves the tags of the JSON schema alone. The
extended schema adds the types of the YAML 1.1 type repository that this
library carries: `!!binary` into `{binary, Bytes}`, the merge key `<<`, and
the `y`, `yes`, `on`, and `off` boolean tokens under an explicit `!!bool`.

### Encoding

```erlang
{ok, <<"a:\n  - 1\n  - 2\n">>} = nyaml:encode(#{<<"a">> => [1, 2]}).
```

`encode/1` writes block style for a collection with content and flow style for
an empty one. A property test round-trips every shape of
`t:nyaml:yaml_value/0` through `encode/1` and `decode/1`.

### Type mapping

| YAML | Erlang |
|------|--------|
| `null`, `~`, empty | `null` |
| `true`, `false` | `true`, `false` |
| `123`, `-45`, `0xFF`, `0o10` | `integer()` |
| `3.14` | `float()` |
| `.inf`, `-.inf`, `.nan` | `infinity`, `negative_infinity`, `nan` |
| `plain`, `"quoted"` | `binary()` |
| `[a, b]` | `list()` |
| `{a: 1}` | `map()` |
| `2024-01-15T10:30:00` | `calendar:datetime()` |

A key resolves under the same rules as a value, so `1: a` gives
`#{1 => <<"a">>}`. Quote a key to keep it a string.

## Features

- **Full YAML 1.2 syntax** block and flow collections, block scalars with every indentation and chomping indicator, multi-document streams, anchors, aliases, tags, and `%YAML` and `%TAG` directives
- **100% test suite compliance** 402 of 402 cases of the official [yaml-test-suite](https://github.com/yaml/yaml-test-suite), 308 valid cases parsed and 94 invalid cases rejected, none skipped
- **Two tag schemas** the JSON tags of the YAML 1.2 core schema, and the YAML 1.1 type repository under `#{schema => extended}`
- **Every encoding** UTF-8, UTF-16 (BE/LE), and UTF-32 (BE/LE), detected from the byte order mark or the byte pattern
- **Emitter** block style output, round-trip verified against the parser by a property test
- **Idiomatic Erlang** every function gives `{ok, Value}` or `{error, Reason}` and never throws
- **No dependencies** only OTP `kernel` and `stdlib`

## Documentation

[nyaml on HexDocs](https://hexdocs.pm/nyaml)

## Development

The compliance suite runs against the official yaml-test-suite, vendored as a
git submodule that is pinned to the `data-2022-01-17` tag. Clone with
`--recurse-submodules`, or run `git submodule update --init` before
`rebar3 compliance`.

## License

Apache License 2.0
