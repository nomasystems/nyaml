-module(nyaml_parser).

-moduledoc """
Top-level YAML parsing orchestrator.

Detects input type (flow vs block, quoted vs plain) and dispatches to
appropriate modules. Handles document markers, directives, and anchors.
""".

%%%-----------------------------------------------------------------------------
%% API EXPORTS
%%%-----------------------------------------------------------------------------
-export([
    empty_node_value/2,
    kind_of/1,
    new_ctx/0,
    new_ctx/1,
    parse/1,
    parse_next/2,
    parse_scalar/1,
    parse_stream/1,
    parse_stream/2,
    parse_value_with_anchor/2,
    resolve_alias/2,
    resolve_tag/3,
    schema/1,
    set_anchor/3,
    skip_whitespace_and_comments/1,
    strip_comment/1,
    to_string/1
]).

%%%-----------------------------------------------------------------------------
%% TYPE EXPORTS
%%%-----------------------------------------------------------------------------
-export_type([
    anchors/0,
    ctx/0,
    node_kind/0,
    parse_error/0,
    tag_handles/0,
    yaml_value/0
]).

%%%-----------------------------------------------------------------------------
%% TYPES
%%%-----------------------------------------------------------------------------
-type yaml_value() :: nyaml:yaml_value().

-type anchors() :: #{binary() => yaml_value()}.

-type tag_handles() :: #{binary() => binary()}.

-type directive_state() :: #{seen_yaml := boolean()}.

-type node_kind() :: mapping | scalar | sequence.

-type stream_position() :: after_document | document_start.

-type parse_error() ::
    anchor_on_block_indicator
    | block_mapping_on_document_start_line
    | comment_without_separation
    | content_after_comment
    | directive_without_document
    | directive_without_document_end
    | duplicate_yaml_directive
    | invalid_content_after_document_end
    | invalid_tag_directive
    | invalid_yaml_directive
    | missing_tag_prefix
    | parse_error
    | unexpected_closing_brace
    | unexpected_closing_bracket
    | unterminated_verbatim_tag
    | {invalid_anchor_name, binary()}
    | {invalid_tag_character, byte()}
    | {invalid_tag_handle, binary()}
    | {invalid_tag_content, binary(), binary()}
    | {invalid_tag_handle_name, binary()}
    | {invalid_tag_name, binary()}
    | {mapping_indicator_in_plain_scalar, binary()}
    | {no_version_number, binary()}
    | {sequence_indicator_in_plain_scalar, binary()}
    | {tag_kind_mismatch, binary(), node_kind()}
    | {trailing_content_after_document, binary()}
    | {undefined_alias, binary()}
    | {undefined_tag_handle, binary()}
    | {unexpected_content, binary()}
    | nyaml_block:parse_error()
    | nyaml_block_scalar:parse_error()
    | nyaml_complex_scalar:base64_error()
    | nyaml_flow:parse_error()
    | nyaml_merge:merge_error()
    | nyaml_scalar:parse_error().
%%%-----------------------------------------------------------------------------
%% MACROS
%%%-----------------------------------------------------------------------------
-define(IS_SCALAR(Value), not is_map(Value), not is_list(Value)).

-define(IS_CORE_TAG(Tag),
    Tag =:= <<"bool">>;
    Tag =:= <<"float">>;
    Tag =:= <<"int">>;
    Tag =:= <<"map">>;
    Tag =:= <<"null">>;
    Tag =:= <<"seq">>;
    Tag =:= <<"str">>
).

%%%-----------------------------------------------------------------------------
%% RECORDS
%%%-----------------------------------------------------------------------------
-record(ctx, {
    anchors = #{} :: anchors(),
    schema = core :: nyaml:schema(),
    tag_handles = #{} :: tag_handles()
}).

-opaque ctx() :: #ctx{}.

%%%-----------------------------------------------------------------------------
%% API FUNCTIONS
%%%-----------------------------------------------------------------------------

-doc """
Gives the value of an empty node under a tag.

The "Empty Nodes" section reads a node with empty content as a plain scalar
with an empty value, and its "Empty Content" example gives `!!str` over such a
node the empty string. `binary` under the extended schema therefore gives empty
bytes. Every other tag gives the `null` that the same section calls the common
resolution.

`bool` is the one tag that refuses that resolution. "Recognized and Valid Tags"
holds the content of a node to the constraints of its tag, and `null` is no
token of the `bool` type, so an empty node under the tag is invalid content.
""".
-spec empty_node_value(binary(), ctx()) ->
    {ok, yaml_value()} | {error, {invalid_tag_content, binary(), binary()}}.
empty_node_value(<<"str">>, _Ctx) -> {ok, <<>>};
empty_node_value(<<"binary">>, #ctx{schema = extended}) -> {ok, {binary, <<>>}};
empty_node_value(<<"bool">>, #ctx{schema = Schema}) -> resolve_bool(Schema, null);
empty_node_value(_Tag, _Ctx) -> {ok, null}.

-doc """
Gives the kind of a node.

"Recognized and Valid Tags" holds the content of a node to the constraints of
its tag, and every tag of the core schema names a kind, so the kind of a node
is what a tag is held against.
""".
-spec kind_of(yaml_value()) -> node_kind().
kind_of(Value) when is_map(Value) ->
    mapping;
kind_of(Value) when is_list(Value) ->
    sequence;
kind_of(_Value) ->
    scalar.

-doc """
Creates a new empty parse context under the core schema.
""".
-spec new_ctx() -> ctx().
new_ctx() ->
    new_ctx(core).

-doc """
Creates a new empty parse context under the given schema.

`nyaml:decode/2` refuses every value that `nyaml:schema()` does not name before
the parse starts.
""".
-spec new_ctx(nyaml:schema()) -> ctx().
new_ctx(Schema) ->
    #ctx{schema = Schema}.

-doc """
Parses a complete YAML document.

Returns the first document if multiple are present.
""".
-spec parse(binary()) -> {ok, yaml_value()} | {error, parse_error()}.
parse(Bin) when is_binary(Bin) ->
    case parse_stream(Bin) of
        {ok, []} -> {ok, null};
        {ok, [First | _]} -> {ok, First};
        {error, _} = Err -> Err
    end.

-doc """
Parses the next YAML value from input (anchor-aware).
""".
-spec parse_next(binary(), ctx()) -> {ok, yaml_value(), binary(), ctx()} | {error, parse_error()}.
parse_next(Bin, Ctx) ->
    case nyaml_parser_util:skip_whitespace(Bin) of
        <<"*", Rest/binary>> ->
            maybe
                {ok, Name, Rest1} ?= nyaml_parser_util:parse_alias_name(Rest),
                {ok, Value} ?= resolve_alias(Name, Ctx),
                {ok, Value, Rest1, Ctx}
            end;
        <<"&", Rest/binary>> ->
            maybe
                {ok, Name, Rest1} ?= nyaml_parser_util:parse_anchor_name(Rest),
                {ok, Value, Rest2, Ctx1} ?=
                    parse_next_value(nyaml_parser_util:skip_whitespace(Rest1), Ctx),
                Ctx2 = set_anchor(Name, Value, Ctx1),
                {ok, Value, Rest2, Ctx2}
            end;
        <<"!<", Rest/binary>> ->
            case nyaml_parser_util:skip_verbatim_tag(Rest) of
                {ok, Rest1} ->
                    parse_next(nyaml_parser_util:skip_whitespace(Rest1), Ctx);
                {error, _} = Err ->
                    Err
            end;
        <<"!!", Rest/binary>> ->
            case nyaml_parser_util:parse_tag_name(Rest) of
                {ok, Tag, Rest1} ->
                    Rest2 = nyaml_parser_util:skip_whitespace(Rest1),
                    case Rest2 of
                        <<C, _/binary>> when C =:= $,; C =:= $}; C =:= $]; C =:= $\n; C =:= $\r ->
                            maybe
                                {ok, Empty} ?= empty_node_value(Tag, Ctx),
                                {ok, Empty, Rest2, Ctx}
                            end;
                        <<>> ->
                            maybe
                                {ok, Empty} ?= empty_node_value(Tag, Ctx),
                                {ok, Empty, <<>>, Ctx}
                            end;
                        _ ->
                            maybe
                                {ok, Value, Rest3, Ctx1} ?= parse_next_value(Rest2, Ctx),
                                {ok, ResolvedValue} ?= resolve_tag(Tag, Value, Ctx),
                                {ok, ResolvedValue, Rest3, Ctx1}
                            end
                    end;
                {error, _} = Err ->
                    Err
            end;
        <<"! ", Rest/binary>> ->
            case parse_next_value(nyaml_parser_util:skip_whitespace(Rest), Ctx) of
                {ok, Value, Rest1, Ctx1} ->
                    {ok, to_string(Value), Rest1, Ctx1};
                {error, _} = Err ->
                    Err
            end;
        <<"!", Rest/binary>> ->
            case skip_local_or_named_tag(Rest, Ctx) of
                {ok, Rest1} ->
                    parse_next(nyaml_parser_util:skip_whitespace(Rest1), Ctx);
                {error, _} = Err ->
                    Err
            end;
        Other ->
            parse_next_value(Other, Ctx)
    end.

-doc """
Parses a scalar value from the given binary.
""".
-spec parse_scalar(binary()) -> {ok, yaml_value()}.
parse_scalar(Bin) ->
    TrimmedBin = nyaml_parser_util:strip_whitespace(Bin),
    case TrimmedBin of
        <<>> ->
            {ok, null};
        <<"null">> ->
            {ok, null};
        <<"true">> ->
            {ok, true};
        <<"false">> ->
            {ok, false};
        _ ->
            try
                {ok, binary_to_integer(TrimmedBin)}
            catch
                error:badarg ->
                    try
                        {ok, binary_to_float(TrimmedBin)}
                    catch
                        error:badarg ->
                            case nyaml_complex_scalar:try_parse(TrimmedBin) of
                                {ok, Value} -> {ok, Value};
                                {error, _} -> {ok, TrimmedBin}
                            end
                    end
            end
    end.

-doc """
Parses a YAML stream containing multiple documents.
""".
-spec parse_stream(binary()) -> {ok, [yaml_value()]} | {error, parse_error()}.
parse_stream(Bin) when is_binary(Bin) ->
    parse_stream(Bin, core).

-doc """
Parses a YAML stream containing multiple documents under the given schema.

The schema is stream scoped. Anchors are document scoped, so the context that
carries both is reset at every document boundary and keeps its schema.
""".
-spec parse_stream(binary(), nyaml:schema()) -> {ok, [yaml_value()]} | {error, parse_error()}.
parse_stream(Bin, Schema) when is_binary(Bin) ->
    parse_documents(
        nyaml_parser_util:skip_empty_and_comment_lines(Bin),
        document_start,
        [],
        new_ctx(Schema)
    ).

-doc """
Parses a value that may have an anchor prefix or be an alias.
""".
-spec parse_value_with_anchor(binary(), ctx()) ->
    {ok, yaml_value(), binary(), ctx()} | {error, parse_error()}.
parse_value_with_anchor(Bin, Ctx) ->
    case nyaml_parser_util:skip_whitespace(Bin) of
        <<"*", Rest/binary>> ->
            maybe
                {ok, Name, Rest1} ?= nyaml_parser_util:parse_alias_name(Rest),
                {ok, Value} ?= resolve_alias(Name, Ctx),
                {ok, Value, Rest1, Ctx}
            end;
        <<"&", Rest/binary>> ->
            maybe
                {ok, Name, Rest1} ?= nyaml_parser_util:parse_anchor_name(Rest),
                {ok, Value, Rest2, Ctx1} ?=
                    parse_anchored_value(nyaml_parser_util:skip_whitespace(Rest1), Ctx),
                Ctx2 = set_anchor(Name, Value, Ctx1),
                {ok, Value, Rest2, Ctx2}
            end;
        Other ->
            parse_next(Other, Ctx)
    end.

-doc """
Resolves an alias to its anchored value.
""".
-spec resolve_alias(binary(), ctx()) -> {ok, yaml_value()} | {error, {undefined_alias, binary()}}.
resolve_alias(Name, #ctx{anchors = Anchors}) ->
    case maps:find(Name, Anchors) of
        {ok, Value} -> {ok, Value};
        error -> {error, {undefined_alias, Name}}
    end.

-doc """
Resolves a tag by converting the value to the appropriate type.

The schema of the context selects the rules. The core schema uses the tags of the JSON schema, so `str`, `int`, `float`,
`bool`, and `null` convert. Every other tag leaves its node's value alone.

Every one of those tags carries a kind. The "Generic Mapping", "Generic
Sequence", and "Generic String" sections give `map` the mapping kind, `seq` the
sequence kind, and `str` the scalar kind, and the "JSON Schema" section gives
`null`, `bool`, `int`, and `float` the scalar kind. "Recognized and Valid Tags"
makes a node valid only when its content satisfies the constraints of its tag,
so a core-schema tag over a node of another kind is an error.

The extended schema adds the types of the YAML 1.1 type repository that this
library carries. `binary` is one of them: it takes a scalar node, decodes the
base64 content that the "Various Explicit Tags" example writes, and gives
`{binary, Bytes}`. The `bool` tag is another: it takes the `yes`, `no`, `on`,
and `off` tokens beside the six spellings of `true` and `false` that the core
schema resolves. Every other tag keeps the core rules.

The same section makes content that no token of the tag matches invalid, so
`!!bool` over such content returns
`{invalid_tag_content, <<"bool">>, Content}` under both schemas.
""".
-spec resolve_tag(binary(), yaml_value(), ctx()) ->
    {ok, yaml_value()}
    | {error,
        {tag_kind_mismatch, binary(), node_kind()}
        | {invalid_tag_content, binary(), binary()}
        | nyaml_complex_scalar:base64_error()}.
resolve_tag(Tag, Value, #ctx{schema = core}) ->
    resolve_core_tag(Tag, Value);
resolve_tag(Tag, Value, #ctx{schema = extended}) ->
    resolve_extended_tag(Tag, Value).

-doc """
Gives the schema that the context carries.

The schema is stream scoped, so every document of a stream reads it.
""".
-spec schema(ctx()) -> nyaml:schema().
schema(#ctx{schema = Schema}) ->
    Schema.

-doc """
Stores an anchor in the context and returns the updated context.
""".
-spec set_anchor(binary(), yaml_value(), ctx()) -> ctx().
set_anchor(Name, Value, #ctx{anchors = Anchors} = Ctx) ->
    Ctx#ctx{anchors = Anchors#{Name => Value}}.

-doc """
Skips whitespace and comment lines.
""".
-spec skip_whitespace_and_comments(binary()) -> binary().
skip_whitespace_and_comments(Bin) ->
    case nyaml_parser_util:skip_whitespace(Bin) of
        <<"#", Rest/binary>> ->
            skip_comment_line(Rest);
        Other ->
            Other
    end.

-doc """
Strips comments from end of line.
""".
-spec strip_comment(binary()) -> binary().
strip_comment(Bin) ->
    strip_comment(Bin, <<>>, false).

-doc """
Converts a value to its string representation.

A timestamp takes the `YYYY-MM-DDThh:mm:ss` form that the emitter writes, and a
`{binary, Bytes}` node takes its base64 text.
""".
-spec to_string(yaml_value()) -> binary().
to_string(Value) when is_binary(Value) -> Value;
to_string(Value) when is_integer(Value) -> integer_to_binary(Value);
to_string(Value) when is_float(Value) -> float_to_binary(Value);
to_string(true) ->
    <<"true">>;
to_string(false) ->
    <<"false">>;
to_string(null) ->
    <<"null">>;
to_string({{Y, Mo, D}, {H, Mi, S}}) ->
    iolist_to_binary(
        io_lib:format("~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0B", [Y, Mo, D, H, Mi, S])
    );
to_string({binary, Bytes}) ->
    base64:encode(Bytes);
to_string(Value) when is_list(Value) -> <<"[list]">>;
to_string(Value) when is_map(Value) -> <<"{map}">>.

%%%-----------------------------------------------------------------------------
%% INTERNAL FUNCTIONS
%%%-----------------------------------------------------------------------------

-spec apply_double_bang_tag(binary(), binary(), ctx()) ->
    {ok, yaml_value(), binary(), ctx()} | {error, parse_error()}.
apply_double_bang_tag(Tag, Trimmed, Ctx) ->
    maybe
        {ok, Value, Rest, Ctx1} ?= parse_document_value(Trimmed, Ctx),
        {ok, Resolved} ?= resolve_tag(Tag, Value, Ctx),
        {ok, Resolved, Rest, Ctx1}
    end.

-spec bind_anchored_value(binary(), binary(), binary(), ctx()) ->
    {ok, yaml_value(), binary(), ctx()} | {error, parse_error()}.
bind_anchored_value(_Name, <<"-", C, _/binary>>, _Rest1, _Ctx) when C =:= $\s; C =:= $\t ->
    {error, anchor_on_block_indicator};
bind_anchored_value(_Name, <<"-">>, _Rest1, _Ctx) ->
    {error, anchor_on_block_indicator};
bind_anchored_value(Name, _SameLinePart, Rest1, Ctx) ->
    maybe
        {ok, Value, Rest2, Ctx1} ?=
            parse_document_value(nyaml_parser_util:skip_whitespace(Rest1), Ctx),
        Ctx2 = set_anchor(Name, Value, Ctx1),
        {ok, Value, Rest2, Ctx2}
    end.

-spec check_post_document(binary()) -> {ok, binary()} | {error, parse_error()}.
check_post_document(<<"]", _/binary>>) ->
    {error, unexpected_closing_bracket};
check_post_document(<<"}", _/binary>>) ->
    {error, unexpected_closing_brace};
check_post_document(Bin) ->
    {ok, Bin}.

-spec continue_after_document(binary(), [yaml_value()], ctx()) ->
    {ok, [yaml_value()]} | {error, parse_error()}.
continue_after_document(Remaining, Acc, Ctx) ->
    case check_post_document(skip_whitespace_and_comments(Remaining)) of
        {ok, Next} -> parse_documents(Next, after_document, Acc, reset_ctx(Ctx));
        {error, _} = Err -> Err
    end.

-spec dispatch_double_bang_tagged_value(binary(), binary(), binary(), binary(), ctx()) ->
    {ok, yaml_value(), binary(), ctx()} | {error, parse_error()}.
dispatch_double_bang_tagged_value(_Bin, Tag, Rest1, <<":", C, _/binary>>, Ctx) when
    C =:= $\s; C =:= $\t
->
    nyaml_block:parse_block(<<"!!", Tag/binary, Rest1/binary>>, 0, Ctx);
dispatch_double_bang_tagged_value(_Bin, Tag, Rest1, <<":">>, Ctx) ->
    nyaml_block:parse_block(<<"!!", Tag/binary, Rest1/binary>>, 0, Ctx);
dispatch_double_bang_tagged_value(Bin, Tag, Rest1, Trimmed, Ctx) ->
    case nyaml_parser_util:has_newline_before_content(Rest1) of
        true ->
            apply_double_bang_tag(Tag, Trimmed, Ctx);
        false ->
            case nyaml_parser_util:is_tagged_mapping_key(Trimmed) of
                true -> nyaml_block:parse_block(Bin, 0, Ctx);
                false -> apply_double_bang_tag(Tag, Trimmed, Ctx)
            end
    end.

-spec fallback_to_scalar_value(binary(), ctx()) ->
    {ok, yaml_value(), binary(), ctx()} | {error, parse_error()}.
fallback_to_scalar_value(Bin, Ctx) ->
    case nyaml_parser_util:collect_plain_scalar(Bin) of
        {error, _} = Err ->
            Err;
        {Scalar, Rest} ->
            {ok, Value} = parse_scalar(Scalar),
            {ok, Value, Rest, Ctx}
    end.

-spec get_tag_handles(ctx()) -> tag_handles().
get_tag_handles(#ctx{tag_handles = Handles}) ->
    Handles.

-spec is_flow_mapping_key(binary(), sequence | mapping, ctx()) -> boolean().
is_flow_mapping_key(Bin, sequence, Ctx) ->
    case nyaml_flow:parse_sequence(Bin, reset_ctx(Ctx)) of
        {ok, _Value, Rest, _Ctx} ->
            TrimmedRest = nyaml_parser_util:skip_whitespace(Rest),
            case TrimmedRest of
                <<":", _/binary>> -> true;
                _ -> false
            end;
        {error, _} ->
            false
    end;
is_flow_mapping_key(Bin, mapping, Ctx) ->
    case nyaml_flow:parse_mapping(Bin, reset_ctx(Ctx)) of
        {ok, _Value, Rest, _Ctx} ->
            TrimmedRest = nyaml_parser_util:skip_whitespace(Rest),
            case TrimmedRest of
                <<":", _/binary>> -> true;
                _ -> false
            end;
        {error, _} ->
            false
    end.

-spec is_structural_detection_failure(nyaml_block:parse_error()) -> boolean().
is_structural_detection_failure({unknown_block_type, _}) -> true;
is_structural_detection_failure(_) -> false.

-spec is_tag_handle_registered(binary(), ctx()) -> boolean().
is_tag_handle_registered(Handle, Ctx) ->
    maps:is_key(Handle, get_tag_handles(Ctx)).

-spec parse_aliased_value(binary(), ctx()) ->
    {ok, yaml_value(), binary(), ctx()} | {error, parse_error()}.
parse_aliased_value(Rest, Ctx) ->
    maybe
        {ok, Name, Rest1} ?= nyaml_parser_util:parse_alias_name(Rest),
        {ok, Value} ?= resolve_alias(Name, Ctx),
        {ok, Value, Rest1, Ctx}
    end.

-spec parse_anchored_value(binary(), ctx()) ->
    {ok, yaml_value(), binary(), ctx()} | {error, parse_error()}.
parse_anchored_value(Bin, Ctx) ->
    parse_next(Bin, Ctx).

-spec parse_anchored_value(binary(), binary(), ctx()) ->
    {ok, yaml_value(), binary(), ctx()} | {error, parse_error()}.
parse_anchored_value(Bin, Rest, Ctx) ->
    case nyaml_parser_util:is_anchor_in_mapping_key(Rest) of
        true ->
            nyaml_block:parse_block(Bin, 0, Ctx);
        false ->
            parse_anchored_value_name(Rest, Ctx)
    end.

-spec parse_anchored_value_name(binary(), ctx()) ->
    {ok, yaml_value(), binary(), ctx()} | {error, parse_error()}.
parse_anchored_value_name(Rest, Ctx) ->
    maybe
        {ok, Name, Rest1} ?= nyaml_parser_util:parse_anchor_name(Rest),
        SameLinePart = nyaml_parser_util:skip_same_line_whitespace(Rest1),
        bind_anchored_value(Name, SameLinePart, Rest1, Ctx)
    end.

-spec parse_bang_tagged_value(binary(), ctx()) ->
    {ok, yaml_value(), binary(), ctx()} | {error, parse_error()}.
parse_bang_tagged_value(<<" ", Rest/binary>>, Ctx) ->
    maybe
        {ok, Value, Rest1, Ctx1} ?=
            parse_document_value(nyaml_parser_util:skip_whitespace(Rest), Ctx),
        {ok, to_string(Value), Rest1, Ctx1}
    end;
parse_bang_tagged_value(Rest, Ctx) ->
    maybe
        {ok, Rest1} ?= skip_local_or_named_tag(Rest, Ctx),
        parse_document_value(nyaml_parser_util:skip_whitespace(Rest1), Ctx)
    end.

-spec parse_bare_document(binary(), stream_position(), [yaml_value()], ctx()) ->
    {ok, [yaml_value()]} | {error, parse_error()}.
parse_bare_document(Bin, after_document, _Acc, _Ctx) ->
    {error, {trailing_content_after_document, Bin}};
parse_bare_document(<<C, _/binary>> = Bin, document_start, _Acc, _Ctx) when C =:= $]; C =:= $} ->
    {error, {unexpected_content, Bin}};
parse_bare_document(Bin, document_start, Acc, Ctx) ->
    maybe
        {ok, Value, Remaining, _Ctx1} ?= parse_document_content(Bin, Ctx),
        continue_after_document(Remaining, [Value | Acc], Ctx)
    end.

-spec parse_block_or_scalar_value(binary(), binary(), ctx()) ->
    {ok, yaml_value(), binary(), ctx()} | {error, parse_error()}.
parse_block_or_scalar_value(Bin, BlockBin, Ctx) ->
    case nyaml_parser_util:block_starts_with_sequence_or_mapping(BlockBin) of
        true ->
            BaseIndent = nyaml_parser_util:detect_base_indent(Bin),
            case nyaml_block:parse_block(Bin, BaseIndent, Ctx) of
                {ok, _, _, _} = Ok ->
                    Ok;
                {error, Reason} ->
                    case is_structural_detection_failure(Reason) of
                        true -> fallback_to_scalar_value(BlockBin, Ctx);
                        false -> {error, Reason}
                    end
            end;
        false ->
            fallback_to_scalar_value(BlockBin, Ctx)
    end.

-spec parse_block_scalar_value(binary(), ctx()) ->
    {ok, yaml_value(), binary(), ctx()} | {error, parse_error()}.
parse_block_scalar_value(BlockScalarBin, Ctx) ->
    case nyaml_block_scalar:parse(BlockScalarBin, 0, true) of
        {ok, Value, Rest} -> {ok, Value, Rest, Ctx};
        {error, _} = Err -> Err
    end.

-spec parse_directives(binary(), directive_state(), ctx()) ->
    {ok, binary(), ctx()} | {error, parse_error()}.
parse_directives(<<"%", Rest/binary>>, State, Ctx) ->
    {Name, AfterName} = nyaml_parser_util:parse_directive_name(Rest),
    parse_named_directive(Name, AfterName, State, Ctx);
parse_directives(<<"---", _/binary>> = Bin, _State, Ctx) ->
    {ok, Bin, Ctx};
parse_directives(<<"...", _/binary>>, State, Ctx) ->
    case maps:get(seen_yaml, State, false) of
        true -> {error, directive_without_document};
        false -> {ok, <<"...">>, Ctx}
    end;
parse_directives(<<>>, State, Ctx) ->
    case maps:get(seen_yaml, State, false) of
        true -> {error, directive_without_document};
        false -> {ok, <<>>, Ctx}
    end;
parse_directives(Bin, State, Ctx) ->
    case maps:get(seen_yaml, State, false) of
        true -> {error, directive_without_document};
        false -> {ok, Bin, Ctx}
    end.

-spec parse_named_directive(binary(), binary(), directive_state(), ctx()) ->
    {ok, binary(), ctx()} | {error, parse_error()}.
parse_named_directive(<<"YAML">>, AfterName, State, Ctx) ->
    maybe
        {ok, AfterDirective} ?= nyaml_parser_util:parse_yaml_directive(AfterName),
        false ?= maps:get(seen_yaml, State, false),
        parse_directives(
            skip_whitespace_and_comments(AfterDirective),
            State#{seen_yaml => true},
            Ctx
        )
    else
        true -> {error, duplicate_yaml_directive};
        {error, _} = Err -> Err
    end;
parse_named_directive(<<"TAG">>, AfterName, State, Ctx) ->
    case parse_tag_directive(AfterName, Ctx) of
        {ok, AfterDirective, Ctx1} ->
            parse_directives(skip_whitespace_and_comments(AfterDirective), State, Ctx1);
        {error, _} = Err ->
            Err
    end;
parse_named_directive(_Reserved, AfterName, State, Ctx) ->
    AfterLine = nyaml_parser_util:skip_to_end_of_line(AfterName),
    parse_directives(skip_whitespace_and_comments(AfterLine), State, Ctx).

-spec parse_document_content(binary(), ctx()) ->
    {ok, yaml_value(), binary(), ctx()} | {error, parse_error()}.
parse_document_content(<<>>, Ctx) ->
    {ok, null, <<>>, Ctx};
parse_document_content(<<"---", Rest/binary>> = Bin, Ctx) ->
    case nyaml_parser_util:is_valid_document_marker(Rest) of
        true ->
            {ok, null, Bin, Ctx};
        false ->
            {DocContent, DocRest} = nyaml_parser_util:extract_document_content(Bin),
            case validate_content_no_directive(DocContent, DocRest) of
                ok ->
                    case parse_document_value(DocContent, Ctx) of
                        {ok, Value, _InternalRest, Ctx1} -> {ok, Value, DocRest, Ctx1};
                        {error, _} = Err -> Err
                    end;
                {error, _} = Err ->
                    Err
            end
    end;
parse_document_content(<<"...", _/binary>> = Bin, Ctx) ->
    {ok, null, Bin, Ctx};
parse_document_content(Bin, Ctx) ->
    {DocContent, DocRest} = nyaml_parser_util:extract_document_content(Bin),
    case validate_content_no_directive(DocContent, DocRest) of
        ok ->
            case parse_document_value(DocContent, Ctx) of
                {ok, Value, InternalRest, Ctx1} ->
                    FullRest =
                        <<
                            (nyaml_parser_util:strip_whitespace(InternalRest))/binary,
                            DocRest/binary
                        >>,
                    {ok, Value, FullRest, Ctx1};
                {error, _} = Err ->
                    Err
            end;
        {error, _} = Err ->
            Err
    end.

-spec parse_document_value(binary(), ctx()) ->
    {ok, yaml_value(), binary(), ctx()} | {error, parse_error()}.
parse_document_value(<<>>, Ctx) ->
    {ok, null, <<>>, Ctx};
parse_document_value(Bin, Ctx) ->
    case nyaml_parser_util:skip_whitespace(Bin) of
        <<>> ->
            {ok, null, <<>>, Ctx};
        <<"&", Rest/binary>> ->
            parse_anchored_value(Bin, Rest, Ctx);
        <<"*", Rest/binary>> ->
            parse_aliased_value(Rest, Ctx);
        <<"!<", Rest/binary>> ->
            parse_verbatim_tagged_value(Rest, Ctx);
        <<"!!", Rest/binary>> ->
            parse_double_bang_tagged_value(Bin, Rest, Ctx);
        <<"!", Rest/binary>> ->
            parse_bang_tagged_value(Rest, Ctx);
        <<"[", _/binary>> = SeqBin ->
            parse_flow_sequence_value(SeqBin, Ctx);
        <<"{", _/binary>> = MapBin ->
            parse_flow_mapping_value(MapBin, Ctx);
        <<"\"", _/binary>> = QuotedBin ->
            parse_quoted_document_value(QuotedBin, double, Ctx);
        <<"'", _/binary>> = QuotedBin ->
            parse_quoted_document_value(QuotedBin, single, Ctx);
        <<"|", _/binary>> = BlockScalarBin ->
            parse_block_scalar_value(BlockScalarBin, Ctx);
        <<">", _/binary>> = BlockScalarBin ->
            parse_block_scalar_value(BlockScalarBin, Ctx);
        BlockBin ->
            parse_block_or_scalar_value(Bin, BlockBin, Ctx)
    end.

-spec parse_documents(binary(), stream_position(), [yaml_value()], ctx()) ->
    {ok, [yaml_value()]} | {error, parse_error()}.
parse_documents(<<>>, _Position, Acc, _Ctx) ->
    {ok, lists:reverse(Acc)};
parse_documents(<<"...", Rest/binary>>, _Position, Acc, Ctx) ->
    case nyaml_parser_util:validate_document_end_line(Rest) of
        {ok, AfterEnd} ->
            parse_documents(
                nyaml_parser_util:skip_empty_and_comment_lines(AfterEnd),
                document_start,
                Acc,
                reset_ctx(Ctx)
            );
        {error, _} = Err ->
            Err
    end;
parse_documents(<<"---", Rest/binary>> = Bin, Position, Acc, Ctx) ->
    case nyaml_parser_util:is_valid_document_marker(Rest) of
        true -> parse_explicit_document(Rest, Acc, Ctx);
        false -> parse_bare_document(Bin, Position, Acc, Ctx)
    end;
parse_documents(<<"%", _/binary>> = Bin, document_start, Acc, Ctx) ->
    case parse_directives(Bin, #{seen_yaml => false}, Ctx) of
        {ok, AfterDirectives, Ctx1} ->
            parse_documents(AfterDirectives, document_start, Acc, Ctx1);
        {error, _} = Err ->
            Err
    end;
parse_documents(Bin, Position, Acc, Ctx) ->
    parse_bare_document(Bin, Position, Acc, Ctx).

-spec parse_double_bang_tagged_value(binary(), binary(), ctx()) ->
    {ok, yaml_value(), binary(), ctx()} | {error, parse_error()}.
parse_double_bang_tagged_value(Bin, Rest, Ctx) ->
    maybe
        {ok, Tag, Rest1} ?= nyaml_parser_util:parse_tag_name(Rest),
        Trimmed = nyaml_parser_util:skip_whitespace(Rest1),
        dispatch_double_bang_tagged_value(Bin, Tag, Rest1, Trimmed, Ctx)
    end.

-spec parse_explicit_document(binary(), [yaml_value()], ctx()) ->
    {ok, [yaml_value()]} | {error, parse_error()}.
parse_explicit_document(Rest, Acc, Ctx) ->
    RestAfterMarker = nyaml_parser_util:skip_to_content(Rest),
    maybe
        ok ?= validate_same_line_content(Rest, RestAfterMarker),
        {ok, Value, Remaining, _Ctx1} ?= parse_document_content(RestAfterMarker, Ctx),
        continue_after_document(Remaining, [Value | Acc], Ctx)
    end.

-spec parse_flow_mapping_value(binary(), ctx()) ->
    {ok, yaml_value(), binary(), ctx()} | {error, parse_error()}.
parse_flow_mapping_value(MapBin, Ctx) ->
    case is_flow_mapping_key(MapBin, mapping, Ctx) of
        true -> nyaml_block:parse_block(MapBin, 0, Ctx);
        false -> nyaml_flow:parse_mapping(MapBin, Ctx)
    end.

-spec parse_flow_sequence_value(binary(), ctx()) ->
    {ok, yaml_value(), binary(), ctx()} | {error, parse_error()}.
parse_flow_sequence_value(SeqBin, Ctx) ->
    case is_flow_mapping_key(SeqBin, sequence, Ctx) of
        true -> nyaml_block:parse_block(SeqBin, 0, Ctx);
        false -> nyaml_flow:parse_sequence(SeqBin, Ctx)
    end.

-spec parse_next_value(binary(), ctx()) ->
    {ok, yaml_value(), binary(), ctx()} | {error, parse_error()}.
parse_next_value(Bin, Ctx) ->
    case Bin of
        <<"[", _/binary>> = SeqBin ->
            nyaml_flow:parse_sequence(SeqBin, Ctx);
        <<"{", _/binary>> = MapBin ->
            nyaml_flow:parse_mapping(MapBin, Ctx);
        <<"\"", _/binary>> = QuotedBin ->
            case nyaml_scalar:parse_quoted(QuotedBin, double) of
                {ok, Value, Rest} -> {ok, Value, Rest, Ctx};
                {error, _} = Err -> Err
            end;
        <<"'", _/binary>> = QuotedBin ->
            case nyaml_scalar:parse_quoted(QuotedBin, single) of
                {ok, Value, Rest} -> {ok, Value, Rest, Ctx};
                {error, _} = Err -> Err
            end;
        ScalarBin ->
            {ok, Value, Rest} = parse_scalar_until_delimiter(ScalarBin),
            {ok, Value, Rest, Ctx}
    end.

-spec parse_quoted_document_value(binary(), nyaml_scalar:quote_type(), ctx()) ->
    {ok, yaml_value(), binary(), ctx()} | {error, parse_error()}.
parse_quoted_document_value(QuotedBin, QuoteType, Ctx) ->
    case nyaml_parser_util:is_quoted_mapping_key(QuotedBin, QuoteType) of
        true ->
            nyaml_block:parse_block(QuotedBin, 0, Ctx);
        false ->
            case nyaml_scalar:parse_quoted(QuotedBin, QuoteType) of
                {ok, Value, Rest} -> {ok, Value, Rest, Ctx};
                {error, _} = Err -> Err
            end
    end.

-spec parse_scalar_until_delimiter(binary()) -> {ok, yaml_value(), binary()}.
parse_scalar_until_delimiter(Bin) ->
    parse_scalar_until_delimiter(Bin, <<>>).

-spec parse_scalar_until_delimiter(binary(), binary()) -> {ok, yaml_value(), binary()}.
parse_scalar_until_delimiter(<<C, Rest/binary>>, Acc) when
    C =:= $,; C =:= $]; C =:= $}
->
    TrimmedAcc = nyaml_parser_util:strip_trailing_ws(Acc),
    {ok, Value} = parse_scalar(TrimmedAcc),
    {ok, Value, <<C, Rest/binary>>};
parse_scalar_until_delimiter(<<"\n", Rest/binary>>, Acc) ->
    TrimmedAcc = nyaml_parser_util:strip_trailing_ws(Acc),
    Rest1 = nyaml_parser_util:skip_leading_ws(Rest),
    case TrimmedAcc of
        <<>> ->
            parse_scalar_until_delimiter(Rest1, <<>>);
        _ ->
            parse_scalar_until_delimiter(Rest1, <<TrimmedAcc/binary, " ">>)
    end;
parse_scalar_until_delimiter(<<"\r\n", Rest/binary>>, Acc) ->
    TrimmedAcc = nyaml_parser_util:strip_trailing_ws(Acc),
    Rest1 = nyaml_parser_util:skip_leading_ws(Rest),
    case TrimmedAcc of
        <<>> ->
            parse_scalar_until_delimiter(Rest1, <<>>);
        _ ->
            parse_scalar_until_delimiter(Rest1, <<TrimmedAcc/binary, " ">>)
    end;
parse_scalar_until_delimiter(<<"#", Rest/binary>>, Acc) ->
    case nyaml_parser_util:ends_with_whitespace(Acc) of
        true ->
            Rest1 = nyaml_parser_util:skip_to_eol(Rest),
            TrimmedAcc = nyaml_parser_util:strip_trailing_ws(Acc),
            case TrimmedAcc of
                <<>> ->
                    parse_scalar_until_delimiter(Rest1, <<>>);
                _ ->
                    parse_scalar_until_delimiter(Rest1, <<TrimmedAcc/binary, " ">>)
            end;
        false ->
            parse_scalar_until_delimiter(Rest, <<Acc/binary, $#>>)
    end;
parse_scalar_until_delimiter(<<C, Rest/binary>>, Acc) ->
    parse_scalar_until_delimiter(Rest, <<Acc/binary, C>>);
parse_scalar_until_delimiter(<<>>, Acc) ->
    TrimmedAcc = nyaml_parser_util:strip_trailing_ws(Acc),
    {ok, Value} = parse_scalar(TrimmedAcc),
    {ok, Value, <<>>}.

-spec parse_tag_directive(binary(), ctx()) -> {ok, binary(), ctx()} | {error, parse_error()}.
parse_tag_directive(<<" ", Rest/binary>>, Ctx) ->
    case parse_tag_handle_and_prefix(Rest) of
        {ok, Handle, _Prefix, Rest1} ->
            Ctx1 = register_tag_handle(Handle, <<>>, Ctx),
            {ok, Rest1, Ctx1};
        {error, _} = Err ->
            Err
    end;
parse_tag_directive(_, _Ctx) ->
    {error, invalid_tag_directive}.

-spec parse_tag_handle_and_prefix(binary()) ->
    {ok, binary(), binary(), binary()} | {error, parse_error()}.
parse_tag_handle_and_prefix(<<"!", Rest/binary>>) ->
    case nyaml_parser_util:parse_tag_handle_name(Rest) of
        {ok, Name, Rest1} ->
            Handle = <<"!", Name/binary>>,
            case nyaml_parser_util:skip_whitespace_inline(Rest1) of
                <<>> ->
                    {error, missing_tag_prefix};
                Rest2 ->
                    {Prefix, Rest3} = nyaml_parser_util:parse_tag_prefix(Rest2),
                    {ok, Handle, Prefix, Rest3}
            end;
        {error, _} = Err ->
            Err
    end;
parse_tag_handle_and_prefix(_) ->
    {error, invalid_tag_handle}.

-spec parse_verbatim_tagged_value(binary(), ctx()) ->
    {ok, yaml_value(), binary(), ctx()} | {error, parse_error()}.
parse_verbatim_tagged_value(Rest, Ctx) ->
    maybe
        {ok, Rest1} ?= nyaml_parser_util:skip_verbatim_tag(Rest),
        parse_document_value(nyaml_parser_util:skip_whitespace(Rest1), Ctx)
    end.

-spec register_tag_handle(binary(), binary(), ctx()) -> ctx().
register_tag_handle(Handle, Prefix, #ctx{tag_handles = Handles} = Ctx) ->
    Ctx#ctx{tag_handles = Handles#{Handle => Prefix}}.

-spec reset_ctx(ctx()) -> ctx().
reset_ctx(#ctx{schema = Schema}) ->
    new_ctx(Schema).

-spec resolve_bool(nyaml:schema(), yaml_value()) ->
    {ok, boolean()} | {error, {invalid_tag_content, binary(), binary()}}.
resolve_bool(Schema, Value) ->
    Content = to_string(Value),
    case nyaml_parser_util:to_bool(Schema, Content) of
        {ok, Bool} -> {ok, Bool};
        error -> {error, {invalid_tag_content, <<"bool">>, Content}}
    end.

-spec resolve_core_tag(binary(), yaml_value()) ->
    {ok, yaml_value()}
    | {error,
        {tag_kind_mismatch, binary(), node_kind()} | {invalid_tag_content, binary(), binary()}}.
resolve_core_tag(<<"map">>, Value) when is_map(Value) ->
    {ok, Value};
resolve_core_tag(<<"seq">>, Value) when is_list(Value) ->
    {ok, Value};
resolve_core_tag(<<"str">>, null) ->
    {ok, <<>>};
resolve_core_tag(<<"str">>, Value) when ?IS_SCALAR(Value) ->
    {ok, to_string(Value)};
resolve_core_tag(<<"int">>, Value) when ?IS_SCALAR(Value) ->
    {ok, nyaml_parser_util:to_int(Value)};
resolve_core_tag(<<"float">>, Value) when ?IS_SCALAR(Value) ->
    {ok, nyaml_parser_util:to_float(Value)};
resolve_core_tag(<<"bool">>, Value) when ?IS_SCALAR(Value) ->
    resolve_bool(core, Value);
resolve_core_tag(<<"null">>, Value) when ?IS_SCALAR(Value) ->
    {ok, null};
resolve_core_tag(Tag, Value) when ?IS_CORE_TAG(Tag) ->
    {error, {tag_kind_mismatch, Tag, kind_of(Value)}};
resolve_core_tag(_Tag, Value) ->
    {ok, Value}.

-spec resolve_extended_tag(binary(), yaml_value()) ->
    {ok, yaml_value()}
    | {error,
        {tag_kind_mismatch, binary(), node_kind()}
        | {invalid_tag_content, binary(), binary()}
        | nyaml_complex_scalar:base64_error()}.
resolve_extended_tag(<<"binary">>, Value) when is_list(Value); is_map(Value) ->
    {error, {tag_kind_mismatch, <<"binary">>, kind_of(Value)}};
resolve_extended_tag(<<"binary">>, null) ->
    {ok, {binary, <<>>}};
resolve_extended_tag(<<"binary">>, Value) ->
    case nyaml_complex_scalar:decode_base64(to_string(Value)) of
        {ok, Bytes} -> {ok, {binary, Bytes}};
        {error, _} = Err -> Err
    end;
resolve_extended_tag(<<"bool">>, Value) when ?IS_SCALAR(Value) ->
    resolve_bool(extended, Value);
resolve_extended_tag(Tag, Value) ->
    resolve_core_tag(Tag, Value).

-spec skip_comment_line(binary()) -> binary().
skip_comment_line(<<"\n", Rest/binary>>) ->
    skip_whitespace_and_comments(Rest);
skip_comment_line(<<"\r\n", Rest/binary>>) ->
    skip_whitespace_and_comments(Rest);
skip_comment_line(<<>>) ->
    <<>>;
skip_comment_line(<<_, Rest/binary>>) ->
    skip_comment_line(Rest).

-spec skip_local_or_named_tag(binary(), ctx()) -> {ok, binary()} | {error, parse_error()}.
skip_local_or_named_tag(Bin, Ctx) ->
    case nyaml_parser_util:extract_tag_handle(Bin) of
        {named_tag, Handle, Rest} ->
            case is_tag_handle_registered(<<"!", Handle/binary>>, Ctx) of
                true ->
                    nyaml_parser_util:skip_tag_chars(Rest);
                false ->
                    {error, {undefined_tag_handle, <<"!", Handle/binary>>}}
            end;
        {local_tag, Rest} ->
            nyaml_parser_util:skip_tag_chars(Rest)
    end.

-spec strip_comment(binary(), binary(), boolean() | double | single) -> binary().
strip_comment(<<>>, Acc, _InQuote) ->
    nyaml_parser_util:strip_trailing_whitespace(Acc);
strip_comment(<<" #", _/binary>>, Acc, false) ->
    nyaml_parser_util:strip_trailing_whitespace(Acc);
strip_comment(<<"\t#", _/binary>>, Acc, false) ->
    nyaml_parser_util:strip_trailing_whitespace(Acc);
strip_comment(<<"#", _/binary>>, <<>>, false) ->
    <<>>;
strip_comment(<<"\"", Rest/binary>>, Acc, false) ->
    strip_comment(Rest, <<Acc/binary, "\"">>, double);
strip_comment(<<"'", Rest/binary>>, Acc, false) ->
    strip_comment(Rest, <<Acc/binary, "'">>, single);
strip_comment(<<"\\\"", Rest/binary>>, Acc, double) ->
    strip_comment(Rest, <<Acc/binary, "\\\"">>, double);
strip_comment(<<"\"", Rest/binary>>, Acc, double) ->
    strip_comment(Rest, <<Acc/binary, "\"">>, false);
strip_comment(<<"''", Rest/binary>>, Acc, single) ->
    strip_comment(Rest, <<Acc/binary, "''">>, single);
strip_comment(<<"'", Rest/binary>>, Acc, single) ->
    strip_comment(Rest, <<Acc/binary, "'">>, false);
strip_comment(<<C, Rest/binary>>, Acc, InQuote) ->
    strip_comment(Rest, <<Acc/binary, C>>, InQuote).

-spec validate_content_no_directive(binary(), binary()) -> ok | {error, parse_error()}.
validate_content_no_directive(<<"%", _/binary>>, _Remaining) ->
    {error, directive_without_document_end};
validate_content_no_directive(Content, <<"---", _/binary>>) ->
    case nyaml_parser_util:has_directive_pattern(Content) of
        true -> {error, directive_without_document_end};
        false -> ok
    end;
validate_content_no_directive(_Content, _Remaining) ->
    ok.

-spec validate_same_line_content(binary(), binary()) -> ok | {error, parse_error()}.
validate_same_line_content(Rest, RestAfterMarker) ->
    case nyaml_parser_util:has_same_line_content(Rest) of
        false ->
            ok;
        true ->
            case RestAfterMarker of
                <<"&", AnchorRest/binary>> ->
                    case nyaml_parser_util:parse_anchor_name(AnchorRest) of
                        {ok, _Name, AfterAnchor} ->
                            SameLinePart =
                                nyaml_parser_util:skip_same_line_whitespace(AfterAnchor),
                            case nyaml_parser_util:has_same_line_mapping_indicator(SameLinePart) of
                                true ->
                                    {error, block_mapping_on_document_start_line};
                                false ->
                                    ok
                            end;
                        {error, _} ->
                            ok
                    end;
                _ ->
                    ok
            end
    end.
