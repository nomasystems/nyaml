-module(nyaml_block).

-moduledoc """
Block style collections parsing.

Parses indentation-based YAML structures: sequences (`- item`) and
mappings (`key: value`). Tracks indentation levels to determine nesting.
""".

%%%-----------------------------------------------------------------------------
%% API EXPORTS
%%%-----------------------------------------------------------------------------
-export([
    parse_block/3,
    parse_block_value/3,
    parse_entry_value/4
]).

%%%-----------------------------------------------------------------------------
%% TYPE EXPORTS
%%%-----------------------------------------------------------------------------
-export_type([
    parse_error/0,
    parse_result/0,
    yaml_value/0
]).

%%%-----------------------------------------------------------------------------
%% TYPES
%%%-----------------------------------------------------------------------------
-type yaml_value() :: nyaml:yaml_value().

-type parse_error() ::
    anchor_followed_by_alias
    | comment_without_whitespace
    | content_after_comment
    | flow_content_wrong_indentation
    | plain_scalar_continuation_after_comment
    | tab_before_nested_block_entry
    | tab_in_indentation
    | trailing_content_after_value
    | unterminated_verbatim_tag
    | {ambiguous_mapping_in_value, binary()}
    | {expected_value_indicator, binary()}
    | {explicit_key_missing_content, binary()}
    | {invalid_alias_key, binary()}
    | {invalid_anchor_name, binary()}
    | {invalid_explicit_key, binary()}
    | {invalid_indentation, integer(), expected, integer()}
    | {invalid_mapping_entry, binary()}
    | {invalid_plain_scalar_start, byte()}
    | {invalid_sequence_item, binary()}
    | {invalid_tag_character, byte()}
    | {invalid_tag_name, binary()}
    | {unknown_block_type, binary()}.

-type parse_result() ::
    {ok, yaml_value(), Rest :: binary(), nyaml_parser:ctx()} | {error, parse_error()}.

%%%-----------------------------------------------------------------------------
%% API FUNCTIONS
%%%-----------------------------------------------------------------------------

-doc """
Parses a block-style collection (sequence or mapping) at `BaseIndent`,
returning the parsed value, the unconsumed input, and the updated context.
""".
-spec parse_block(binary(), non_neg_integer(), nyaml_parser:ctx()) -> parse_result().
parse_block(<<>>, _BaseIndent, Ctx) ->
    {ok, [], <<>>, Ctx};
parse_block(Bin, BaseIndent, Ctx) ->
    case detect_block_type(Bin) of
        {sequence, Bin1} -> parse_block_sequence(Bin1, BaseIndent, Ctx);
        {mapping, Bin1} -> parse_block_mapping(Bin1, BaseIndent, Ctx);
        {empty, _} -> {ok, [], <<>>, Ctx};
        {error, Reason} -> {error, Reason}
    end.

%%%-----------------------------------------------------------------------------
%% INTERNAL FUNCTIONS
%%%-----------------------------------------------------------------------------

-spec collect_item_scalar(binary(), binary(), non_neg_integer()) ->
    {binary(), binary()} | {error, tab_in_indentation}.
collect_item_scalar(FirstLine, RestBin, ContentIndent) ->
    BaseIndent = ContentIndent - 2,
    collect_item_scalar_lines(RestBin, FirstLine, BaseIndent, 0).

-spec collect_item_scalar_content(
    binary(), binary(), binary(), {binary(), non_neg_integer()}, non_neg_integer()
) ->
    {binary(), binary()} | {error, tab_in_indentation}.
collect_item_scalar_content(Line, Bin, Rest, {Acc, EmptyCount}, BaseIndent) ->
    case nyaml_block_util:get_indent_and_line(Line) of
        {error, _} = Err ->
            Err;
        {ok, LineIndent, _} when LineIndent =< BaseIndent ->
            {Acc, Bin};
        {ok, LineIndent, Content} ->
            TrimmedContent = nyaml_block_util:strip_comment(
                nyaml_block_util:strip_trailing_ws(nyaml_block_util:strip_whitespace(Content))
            ),
            case should_stop_item_scalar(LineIndent, TrimmedContent, BaseIndent) of
                true ->
                    {Acc, Bin};
                false ->
                    NewAcc = extend_item_scalar_acc(Acc, TrimmedContent, EmptyCount),
                    collect_item_scalar_lines(Rest, NewAcc, BaseIndent, 0)
            end
    end.

-spec collect_item_scalar_lines(binary(), binary(), non_neg_integer(), non_neg_integer()) ->
    {binary(), binary()} | {error, tab_in_indentation}.
collect_item_scalar_lines(<<>>, Acc, _BaseIndent, _EmptyCount) ->
    {Acc, <<>>};
collect_item_scalar_lines(Bin, Acc, BaseIndent, EmptyCount) ->
    case nyaml_block_util:next_line(Bin) of
        {no_more_lines, Rest} ->
            {Acc, Rest};
        {line, Line, Rest} ->
            case nyaml_block_util:is_empty_line(Line) of
                true ->
                    collect_item_scalar_lines(Rest, Acc, BaseIndent, EmptyCount + 1);
                false ->
                    collect_item_scalar_content(Line, Bin, Rest, {Acc, EmptyCount}, BaseIndent)
            end
    end.

-spec detect_block_type(binary()) ->
    {sequence, binary()}
    | {mapping, binary()}
    | {empty, binary()}
    | {error, tab_in_indentation | {unknown_block_type, binary()}}.
detect_block_type(Bin) ->
    case nyaml_block_util:skip_empty_lines(Bin) of
        <<>> ->
            {empty, <<>>};
        Bin1 ->
            FirstLine = nyaml_block_util:get_first_line(Bin1),
            case nyaml_block_util:get_indent_and_line(FirstLine) of
                {error, _} = Err ->
                    Err;
                {ok, _LineIndent, Content} ->
                    case Content of
                        <<"-", C, _/binary>> when C =:= $\s; C =:= $\t ->
                            {sequence, Bin1};
                        <<"-">> ->
                            {sequence, Bin1};
                        <<"?", C, _/binary>> when C =:= $\s; C =:= $\t ->
                            {mapping, Bin1};
                        <<"?">> ->
                            {mapping, Bin1};
                        <<_/binary>> ->
                            case nyaml_block_util:has_mapping_indicator(Content) of
                                true -> {mapping, Bin1};
                                false -> {error, {unknown_block_type, Content}}
                            end
                    end
            end
    end.

-spec dispatch_block_value(
    binary(), non_neg_integer(), non_neg_integer(), binary(), binary(), nyaml_parser:ctx()
) ->
    {ok, yaml_value(), binary(), nyaml_parser:ctx()} | {error, term()}.
dispatch_block_value(<<"&", AnchorRest/binary>>, LineIndent, Indent, _Line, Rest, Ctx) ->
    parse_block_anchor_value(AnchorRest, LineIndent, Indent, Rest, Ctx);
dispatch_block_value(<<"*", AliasRest/binary>>, LineIndent, _Indent, Line, Rest, Ctx) ->
    FullBin = <<Line/binary, "\n", Rest/binary>>,
    parse_block_alias_value(AliasRest, LineIndent, FullBin, Rest, Ctx);
dispatch_block_value(<<"!!", TagRest/binary>>, LineIndent, _Indent, Line, Rest, Ctx) ->
    FullBin = <<Line/binary, "\n", Rest/binary>>,
    parse_block_global_tag_value(TagRest, LineIndent, FullBin, Rest, Ctx);
dispatch_block_value(<<"!", TagRest/binary>>, LineIndent, Indent, _Line, Rest, Ctx) when
    TagRest =/= <<>>
->
    parse_block_local_tag_value(TagRest, LineIndent, Indent, Rest, Ctx);
dispatch_block_value(<<"[", _/binary>> = Content, LineIndent, _Indent, Line, Rest, Ctx) ->
    case nyaml_block_util:has_flow_collection_key(Content) of
        true -> parse_block_mapping(<<Line/binary, "\n", Rest/binary>>, LineIndent, Ctx);
        false -> parse_block_flow_seq_value(Content, Rest, Ctx)
    end;
dispatch_block_value(<<"{", _/binary>> = Content, LineIndent, _Indent, Line, Rest, Ctx) ->
    case nyaml_block_util:has_flow_collection_key(Content) of
        true -> parse_block_mapping(<<Line/binary, "\n", Rest/binary>>, LineIndent, Ctx);
        false -> parse_block_flow_map_value(Content, Rest, Ctx)
    end;
dispatch_block_value(<<"\"", _/binary>> = Content, LineIndent, _Indent, Line, Rest, Ctx) ->
    FullBin = <<Line/binary, "\n", Rest/binary>>,
    parse_block_double_quoted_value(Content, LineIndent, FullBin, Rest, Ctx);
dispatch_block_value(<<"'", _/binary>> = Content, LineIndent, _Indent, Line, Rest, Ctx) ->
    FullBin = <<Line/binary, "\n", Rest/binary>>,
    parse_block_single_quoted_value(Content, LineIndent, FullBin, Rest, Ctx);
dispatch_block_value(Content, LineIndent, Indent, Line, Rest, Ctx) ->
    FullBin = <<Line/binary, "\n", Rest/binary>>,
    parse_block_unquoted_value(Content, LineIndent, Indent, Line, FullBin, Rest, Ctx).

-spec extend_item_scalar_acc(binary(), binary(), non_neg_integer()) -> binary().
extend_item_scalar_acc(Acc, TrimmedContent, EmptyCount) when EmptyCount > 0 ->
    Newlines = list_to_binary(lists:duplicate(EmptyCount, $\n)),
    <<Acc/binary, Newlines/binary, TrimmedContent/binary>>;
extend_item_scalar_acc(Acc, TrimmedContent, _EmptyCount) ->
    <<Acc/binary, " ", TrimmedContent/binary>>.

-spec parse_anchored_inline_value(binary(), non_neg_integer(), binary(), nyaml_parser:ctx()) ->
    {ok, yaml_value(), binary(), nyaml_parser:ctx()} | {error, term()}.
parse_anchored_inline_value(Content, Indent, Rest, Ctx) ->
    case Content of
        <<"*", _/binary>> ->
            {error, anchor_followed_by_alias};
        <<"-", C, _/binary>> when C =:= $\s; C =:= $\t ->
            {error, anchor_on_block_indicator};
        <<"-">> ->
            {error, anchor_on_block_indicator};
        <<"[", _/binary>> ->
            FullBin = <<Content/binary, "\n", Rest/binary>>,
            case nyaml_flow:parse_sequence(FullBin, Ctx) of
                {ok, Value, FlowRest, Ctx1} ->
                    case nyaml_block_util:validate_rest_of_line(FlowRest) of
                        ok -> {ok, Value, nyaml_block_util:skip_to_next_line(FlowRest), Ctx1};
                        {error, _} = Err -> Err
                    end;
                {error, _} = Err ->
                    Err
            end;
        <<"{", _/binary>> ->
            FullBin = <<Content/binary, "\n", Rest/binary>>,
            case nyaml_flow:parse_mapping(FullBin, Ctx) of
                {ok, Value, FlowRest, Ctx1} ->
                    case nyaml_block_util:validate_rest_of_line(FlowRest) of
                        ok -> {ok, Value, nyaml_block_util:skip_to_next_line(FlowRest), Ctx1};
                        {error, _} = Err -> Err
                    end;
                {error, _} = Err ->
                    Err
            end;
        <<"-", C, _/binary>> when C =:= $\s; C =:= $\t ->
            IndentSpaces = nyaml_block_util:make_indent(Indent),
            FullBin = <<IndentSpaces/binary, Content/binary, "\n", Rest/binary>>,
            parse_block_sequence(FullBin, Indent, Ctx);
        _ ->
            case nyaml_block_util:has_mapping_indicator(Content) of
                true ->
                    IndentSpaces = nyaml_block_util:make_indent(Indent),
                    FullBin = <<IndentSpaces/binary, Content/binary, "\n", Rest/binary>>,
                    parse_block_mapping(FullBin, Indent, Ctx);
                false ->
                    case nyaml_block_util:parse_scalar(Content) of
                        {ok, Value} -> {ok, Value, Rest, Ctx};
                        {error, _} = Err -> Err
                    end
            end
    end.

-spec parse_block_alias_value(binary(), non_neg_integer(), binary(), binary(), nyaml_parser:ctx()) ->
    {ok, yaml_value(), binary(), nyaml_parser:ctx()} | {error, term()}.
parse_block_alias_value(AliasRest, LineIndent, FullBin, Rest, Ctx) ->
    case nyaml_block_util:parse_anchor_name(AliasRest) of
        {ok, Name, <<>>} ->
            maybe
                {ok, Value} ?= nyaml_parser:resolve_alias(Name, Ctx),
                {ok, Value, Rest, Ctx}
            end;
        {ok, _Name, AliasValueRest} ->
            TrimmedRest = nyaml_block_util:strip_whitespace(AliasValueRest),
            case TrimmedRest of
                <<":", _/binary>> ->
                    parse_block_mapping(FullBin, LineIndent, Ctx);
                _ ->
                    {error, {invalid_alias_syntax, AliasRest}}
            end;
        {error, _} = Err ->
            Err
    end.
-spec parse_block_anchor_value(
    binary(), non_neg_integer(), non_neg_integer(), binary(), nyaml_parser:ctx()
) ->
    {ok, yaml_value(), binary(), nyaml_parser:ctx()} | {error, term()}.
parse_block_anchor_value(AnchorRest, LineIndent, Indent, Rest, Ctx) ->
    case nyaml_block_util:parse_anchor_name(AnchorRest) of
        {ok, Name, ValuePart} ->
            case nyaml_block_util:strip_comment(nyaml_block_util:strip_whitespace(ValuePart)) of
                <<>> ->
                    ContentMinIndent =
                        case LineIndent of
                            Indent -> LineIndent + 1;
                            _ -> Indent
                        end,
                    maybe
                        {ok, Value, NextRest, Ctx1} ?=
                            parse_block_value(Rest, ContentMinIndent, Ctx),
                        Ctx2 = nyaml_parser:set_anchor(Name, Value, Ctx1),
                        {ok, Value, NextRest, Ctx2}
                    end;
                TrimmedValue ->
                    maybe
                        {ok, Value, NextRest, Ctx1} ?=
                            parse_anchored_inline_value(TrimmedValue, LineIndent, Rest, Ctx),
                        Ctx2 = nyaml_parser:set_anchor(Name, Value, Ctx1),
                        {ok, Value, NextRest, Ctx2}
                    end
            end;
        {error, _} = Err ->
            Err
    end.

-spec parse_block_double_quoted_value(
    binary(), non_neg_integer(), binary(), binary(), nyaml_parser:ctx()
) ->
    {ok, yaml_value(), binary(), nyaml_parser:ctx()} | {error, term()}.
parse_block_double_quoted_value(Content, LineIndent, FullBin, Rest, Ctx) ->
    case nyaml_block_util:is_quoted_mapping_key(Content, double) of
        true ->
            parse_block_mapping(FullBin, LineIndent, Ctx);
        false ->
            QuotedFullBin = <<Content/binary, "\n", Rest/binary>>,
            case nyaml_scalar:parse_quoted(QuotedFullBin, double, block_level) of
                {ok, Value, QuotedRest} ->
                    case nyaml_block_util:validate_rest_of_line(QuotedRest) of
                        ok -> {ok, Value, nyaml_block_util:skip_to_next_line(QuotedRest), Ctx};
                        {error, _} = Err -> Err
                    end;
                {error, _} = Err ->
                    Err
            end
    end.
-spec parse_block_flow_map_value(binary(), binary(), nyaml_parser:ctx()) ->
    {ok, yaml_value(), binary(), nyaml_parser:ctx()} | {error, term()}.
parse_block_flow_map_value(Content, Rest, Ctx) ->
    FlowFullBin = <<Content/binary, "\n", Rest/binary>>,
    case nyaml_flow:parse_mapping(FlowFullBin, Ctx) of
        {ok, Value, FlowRest, Ctx1} ->
            case nyaml_block_util:validate_rest_of_line(FlowRest) of
                ok -> {ok, Value, nyaml_block_util:skip_to_next_line(FlowRest), Ctx1};
                {error, _} = Err -> Err
            end;
        {error, _} = Err ->
            Err
    end.
-spec parse_block_flow_seq_value(binary(), binary(), nyaml_parser:ctx()) ->
    {ok, yaml_value(), binary(), nyaml_parser:ctx()} | {error, term()}.
parse_block_flow_seq_value(Content, Rest, Ctx) ->
    FlowFullBin = <<Content/binary, "\n", Rest/binary>>,
    case nyaml_flow:parse_sequence(FlowFullBin, Ctx) of
        {ok, Value, FlowRest, Ctx1} ->
            case nyaml_block_util:validate_rest_of_line(FlowRest) of
                ok -> {ok, Value, nyaml_block_util:skip_to_next_line(FlowRest), Ctx1};
                {error, _} = Err -> Err
            end;
        {error, _} = Err ->
            Err
    end.
-spec parse_block_global_tag_value(
    binary(), non_neg_integer(), binary(), binary(), nyaml_parser:ctx()
) ->
    {ok, yaml_value(), binary(), nyaml_parser:ctx()} | {error, term()}.
parse_block_global_tag_value(TagRest, LineIndent, FullBin, Rest, Ctx) ->
    case nyaml_block_util:parse_tag_name(TagRest) of
        {ok, Tag, ValuePart} ->
            TrimmedValue = nyaml_block_util:strip_whitespace(ValuePart),
            case TrimmedValue of
                <<>> ->
                    maybe
                        {ok, Value, NextRest, Ctx1} ?= parse_block_value(Rest, LineIndent, Ctx),
                        {ok, Resolved} ?= nyaml_parser:resolve_tag(Tag, Value, Ctx),
                        {ok, Resolved, NextRest, Ctx1}
                    end;
                <<":", C, _/binary>> when C =:= $\s; C =:= $\t ->
                    parse_block_mapping(FullBin, LineIndent, Ctx);
                <<":">> ->
                    parse_block_mapping(FullBin, LineIndent, Ctx);
                _ ->
                    maybe
                        {ok, Value, NextRest, Ctx1} ?=
                            parse_value_content(TrimmedValue, LineIndent, Rest, Ctx),
                        {ok, Resolved} ?= nyaml_parser:resolve_tag(Tag, Value, Ctx),
                        {ok, Resolved, NextRest, Ctx1}
                    end
            end;
        {error, _} = Err ->
            Err
    end.

-spec parse_block_local_tag_value(
    binary(), non_neg_integer(), non_neg_integer(), binary(), nyaml_parser:ctx()
) ->
    {ok, yaml_value(), binary(), nyaml_parser:ctx()} | {error, term()}.
parse_block_local_tag_value(TagRest, LineIndent, Indent, Rest, Ctx) ->
    case nyaml_block_util:skip_local_or_named_tag(TagRest) of
        {ok, ValuePart} ->
            TrimmedValue = nyaml_block_util:strip_whitespace(ValuePart),
            case TrimmedValue of
                <<>> ->
                    parse_block_value(Rest, Indent, Ctx);
                _ ->
                    parse_value_content(TrimmedValue, LineIndent, Rest, Ctx)
            end;
        {error, _} = Err ->
            Err
    end.
-spec parse_block_mapping(binary(), non_neg_integer(), nyaml_parser:ctx()) -> parse_result().
parse_block_mapping(Bin, BaseIndent, Ctx) ->
    nyaml_block_mapping:parse_mapping_entries(Bin, BaseIndent, #{}, Ctx).

-spec parse_block_sequence(binary(), non_neg_integer(), nyaml_parser:ctx()) -> parse_result().
parse_block_sequence(Bin, BaseIndent, Ctx) ->
    parse_sequence_items(Bin, BaseIndent, [], Ctx).

-spec parse_block_single_quoted_value(
    binary(), non_neg_integer(), binary(), binary(), nyaml_parser:ctx()
) ->
    {ok, yaml_value(), binary(), nyaml_parser:ctx()} | {error, term()}.
parse_block_single_quoted_value(Content, LineIndent, FullBin, Rest, Ctx) ->
    case nyaml_block_util:is_quoted_mapping_key(Content, single) of
        true ->
            parse_block_mapping(FullBin, LineIndent, Ctx);
        false ->
            QuotedFullBin = <<Content/binary, "\n", Rest/binary>>,
            case nyaml_scalar:parse_quoted(QuotedFullBin, single, block_level) of
                {ok, Value, QuotedRest} ->
                    case nyaml_block_util:validate_rest_of_line(QuotedRest) of
                        ok -> {ok, Value, nyaml_block_util:skip_to_next_line(QuotedRest), Ctx};
                        {error, _} = Err -> Err
                    end;
                {error, _} = Err ->
                    Err
            end
    end.

-spec parse_block_structure_or_scalar(
    binary(), non_neg_integer(), binary(), binary(), binary(), nyaml_parser:ctx()
) ->
    {ok, yaml_value(), binary(), nyaml_parser:ctx()} | {error, term()}.
parse_block_structure_or_scalar(<<"-", C, _/binary>>, LineIndent, _Line, FullBin, _Rest, Ctx) when
    C =:= $\s; C =:= $\t
->
    parse_block_sequence(FullBin, LineIndent, Ctx);
parse_block_structure_or_scalar(<<"-">>, LineIndent, _Line, FullBin, _Rest, Ctx) ->
    parse_block_sequence(FullBin, LineIndent, Ctx);
parse_block_structure_or_scalar(Content, LineIndent, Line, FullBin, Rest, Ctx) ->
    case nyaml_block_util:has_mapping_indicator(Content) of
        true ->
            parse_block_mapping(FullBin, LineIndent, Ctx);
        false ->
            {Value, NextRest} = nyaml_block_util:collect_scalar_lines(Line, Rest, LineIndent, <<>>),
            {ok, Value, NextRest, Ctx}
    end.
-spec parse_block_unquoted_value(
    binary(), non_neg_integer(), non_neg_integer(), binary(), binary(), binary(), nyaml_parser:ctx()
) ->
    {ok, yaml_value(), binary(), nyaml_parser:ctx()} | {error, term()}.
parse_block_unquoted_value(Content, LineIndent, Indent, Line, FullBin, Rest, Ctx) ->
    case nyaml_block_scalar:is_block_scalar_indicator(Content) of
        true ->
            BlockScalarBin = <<Content/binary, "\n", Rest/binary>>,
            case nyaml_block_scalar:parse(BlockScalarBin, Indent) of
                {ok, Value, ScalarRest} -> {ok, Value, ScalarRest, Ctx};
                {error, _} = Err -> Err
            end;
        false ->
            parse_block_structure_or_scalar(Content, LineIndent, Line, FullBin, Rest, Ctx)
    end.
-doc """
Parses the value on the next non-empty line at or beyond `Indent`,
dispatching on anchors, aliases, tags, flow collections, quoted and plain
scalars. Yields `null` when nothing at the required indentation follows.
""".
-spec parse_block_value(binary(), non_neg_integer(), nyaml_parser:ctx()) ->
    {ok, yaml_value(), binary(), nyaml_parser:ctx()} | {error, term()}.
parse_block_value(Bin, Indent, Ctx) ->
    case nyaml_block_util:next_non_empty_line(Bin) of
        {no_more_lines, Rest} ->
            {ok, null, Rest, Ctx};
        {line, Line, Rest} ->
            case nyaml_block_util:get_indent_and_line(Line) of
                {error, _} = Err ->
                    Err;
                {ok, LineIndent, _LineContent} when LineIndent < Indent ->
                    {ok, null, Bin, Ctx};
                {ok, LineIndent, LineContent} ->
                    dispatch_block_value(LineContent, LineIndent, Indent, Line, Rest, Ctx)
            end
    end.

-doc """
Parses the value of a mapping entry from its inline text `ValueBin` plus
any following lines, resolving anchors, aliases, tags, and scalar or
nested block content at `LineIndent`.
""".
-spec parse_entry_value(binary(), non_neg_integer(), binary(), nyaml_parser:ctx()) ->
    {ok, yaml_value(), binary(), nyaml_parser:ctx()} | {error, term()}.
parse_entry_value(<<>>, LineIndent, Rest, Ctx) ->
    ContentIndent = LineIndent,
    parse_block_value(Rest, ContentIndent, Ctx);
parse_entry_value(<<"*", AliasRest/binary>>, _LineIndent, Rest, Ctx) ->
    case nyaml_block_util:parse_anchor_name(AliasRest) of
        {ok, Name, <<>>} ->
            maybe
                {ok, Value} ?= nyaml_parser:resolve_alias(Name, Ctx),
                {ok, Value, Rest, Ctx}
            end;
        {ok, _, _} ->
            {error, {invalid_alias_syntax, <<"*", AliasRest/binary>>}};
        {error, _} = Err ->
            Err
    end;
parse_entry_value(<<"&", AnchorRest/binary>>, LineIndent, Rest, Ctx) ->
    case nyaml_block_util:parse_anchor_name(AnchorRest) of
        {ok, Name, ValuePart} ->
            case nyaml_block_util:anchor_value_position(ValuePart) of
                empty_or_newline ->
                    case nyaml_block_util:starts_with_scalar_anchor(Rest, LineIndent + 1) of
                        true ->
                            {error, two_anchors_on_same_node};
                        false ->
                            ContentIndent = LineIndent + 1,
                            maybe
                                {ok, Value, NextRest, Ctx1} ?=
                                    parse_block_value(Rest, ContentIndent, Ctx),
                                Ctx2 = nyaml_parser:set_anchor(Name, Value, Ctx1),
                                {ok, Value, NextRest, Ctx2}
                            end
                    end;
                {inline, <<"*", _/binary>>} ->
                    {error, anchor_followed_by_alias};
                {inline, TrimmedValue} ->
                    maybe
                        {ok, Value, NextRest, Ctx1} ?=
                            parse_value_content(TrimmedValue, LineIndent, Rest, Ctx),
                        Ctx2 = nyaml_parser:set_anchor(Name, Value, Ctx1),
                        {ok, Value, NextRest, Ctx2}
                    end
            end;
        {error, _} = Err ->
            Err
    end;
parse_entry_value(<<"!<", TagRest/binary>>, LineIndent, Rest, Ctx) ->
    case nyaml_block_util:skip_verbatim_tag(TagRest) of
        {ok, ValuePart} ->
            parse_entry_value(nyaml_block_util:strip_whitespace(ValuePart), LineIndent, Rest, Ctx);
        {error, _} = Err ->
            Err
    end;
parse_entry_value(<<"!!", TagRest/binary>>, LineIndent, Rest, Ctx) ->
    case nyaml_block_util:parse_tag_name(TagRest) of
        {ok, Tag, ValuePart} ->
            case nyaml_block_util:strip_whitespace(ValuePart) of
                <<>> ->
                    maybe
                        {ok, Value, NextRest, Ctx1} ?= parse_block_value(Rest, LineIndent, Ctx),
                        {ok, Resolved} ?= nyaml_parser:resolve_tag(Tag, Value, Ctx),
                        {ok, Resolved, NextRest, Ctx1}
                    end;
                TrimmedValue ->
                    maybe
                        {ok, Value, NextRest, Ctx1} ?=
                            parse_value_content(TrimmedValue, LineIndent, Rest, Ctx),
                        {ok, Resolved} ?= nyaml_parser:resolve_tag(Tag, Value, Ctx),
                        {ok, Resolved, NextRest, Ctx1}
                    end
            end;
        {error, _} = Err ->
            Err
    end;
parse_entry_value(<<"!", TagRest/binary>>, LineIndent, Rest, Ctx) ->
    case nyaml_block_util:skip_local_or_named_tag(TagRest) of
        {ok, ValuePart} ->
            parse_entry_value(nyaml_block_util:strip_whitespace(ValuePart), LineIndent, Rest, Ctx);
        {error, _} = Err ->
            Err
    end;
parse_entry_value(ValueBin, LineIndent, Rest, Ctx) ->
    parse_value_content(ValueBin, LineIndent, Rest, Ctx).

-spec parse_flow_mapping_value(binary(), binary(), nyaml_parser:ctx()) ->
    {ok, yaml_value(), binary(), nyaml_parser:ctx()} | {error, term()}.
parse_flow_mapping_value(ValueBin, Rest, Ctx) ->
    FullBin = <<ValueBin/binary, "\n", Rest/binary>>,
    case nyaml_flow:parse_mapping(FullBin, Ctx) of
        {ok, Value, FlowRest, Ctx1} ->
            case nyaml_block_util:validate_rest_of_line(FlowRest) of
                ok -> {ok, Value, nyaml_block_util:skip_to_next_line(FlowRest), Ctx1};
                {error, _} = Err -> Err
            end;
        {error, _} = Err ->
            Err
    end.

-spec parse_flow_sequence_value(binary(), binary(), nyaml_parser:ctx()) ->
    {ok, yaml_value(), binary(), nyaml_parser:ctx()} | {error, term()}.
parse_flow_sequence_value(ValueBin, Rest, Ctx) ->
    FullBin = <<ValueBin/binary, "\n", Rest/binary>>,
    case nyaml_flow:parse_sequence(FullBin, Ctx) of
        {ok, Value, FlowRest, Ctx1} ->
            case nyaml_block_util:validate_rest_of_line(FlowRest) of
                ok -> {ok, Value, nyaml_block_util:skip_to_next_line(FlowRest), Ctx1};
                {error, _} = Err -> Err
            end;
        {error, _} = Err ->
            Err
    end.

-spec parse_inline_sequence_continuation(
    binary(), non_neg_integer(), [yaml_value()], nyaml_parser:ctx()
) ->
    {ok, [yaml_value()], binary(), nyaml_parser:ctx()} | {error, term()}.
-spec parse_inline_sequence_content(
    binary(), {binary(), binary()}, non_neg_integer(), [yaml_value()], nyaml_parser:ctx()
) ->
    {ok, [yaml_value()], binary(), nyaml_parser:ctx()} | {error, term()}.
parse_inline_sequence_content(Line, {Bin, Rest}, BaseIndent, Acc, Ctx) ->
    case nyaml_block_util:get_indent_and_line(Line) of
        {error, _} = Err ->
            Err;
        {ok, LineIndent, _} when LineIndent =/= BaseIndent ->
            {ok, lists:reverse(Acc), Bin, Ctx};
        {ok, _, <<"-", C, ItemContent/binary>>} when C =:= $\s; C =:= $\t ->
            ContentIndent = BaseIndent + 2,
            recurse_inline_sequence(
                parse_item_content(ItemContent, ContentIndent, Rest, Ctx), BaseIndent, Acc
            );
        {ok, _, <<"-">>} ->
            ContentIndent = BaseIndent + 1,
            recurse_inline_sequence(
                parse_item_content(<<>>, ContentIndent, Rest, Ctx), BaseIndent, Acc
            );
        {ok, _, _} ->
            {ok, lists:reverse(Acc), Bin, Ctx}
    end.

parse_inline_sequence_continuation(Bin, BaseIndent, Acc, Ctx) ->
    case nyaml_block_util:next_line(Bin) of
        {no_more_lines, Rest} ->
            {ok, lists:reverse(Acc), Rest, Ctx};
        {line, Line, Rest} ->
            case nyaml_block_util:is_empty_line(Line) of
                true ->
                    parse_inline_sequence_continuation(Rest, BaseIndent, Acc, Ctx);
                false ->
                    parse_inline_sequence_content(Line, {Bin, Rest}, BaseIndent, Acc, Ctx)
            end
    end.

-spec parse_item_content(binary(), non_neg_integer(), binary(), nyaml_parser:ctx()) ->
    {ok, yaml_value(), binary(), nyaml_parser:ctx()} | {error, term()}.
parse_item_content(FirstLine, Indent, RestBin, Ctx) ->
    LeadingSpaces = nyaml_block_util:count_leading_ws(FirstLine),
    case nyaml_block_util:strip_whitespace(FirstLine) of
        <<>> ->
            parse_block_value(RestBin, Indent, Ctx);
        ContentWithComment ->
            Content = nyaml_block_util:strip_comment(ContentWithComment),
            case Content of
                <<>> ->
                    MinIndent = max(0, Indent - 1),
                    parse_block_value(RestBin, MinIndent, Ctx);
                <<"-", C, _/binary>> when C =:= $\s; C =:= $\t ->
                    AdjustedIndent = Indent + LeadingSpaces,
                    parse_item_value(Content, ContentWithComment, AdjustedIndent, RestBin, Ctx);
                _ ->
                    parse_item_value(Content, ContentWithComment, Indent, RestBin, Ctx)
            end
    end.

-spec parse_item_value(binary(), binary(), non_neg_integer(), binary(), nyaml_parser:ctx()) ->
    {ok, yaml_value(), binary(), nyaml_parser:ctx()} | {error, term()}.
parse_item_value(<<"*", AliasRest/binary>>, _ContentWithComment, _Indent, RestBin, Ctx) ->
    case nyaml_block_util:parse_anchor_name(AliasRest) of
        {ok, Name, <<>>} ->
            maybe
                {ok, Value} ?= nyaml_parser:resolve_alias(Name, Ctx),
                {ok, Value, RestBin, Ctx}
            end;
        {ok, _, _} ->
            {error, {invalid_alias_syntax, <<"*", AliasRest/binary>>}};
        {error, _} = Err ->
            Err
    end;
parse_item_value(<<"&", AnchorRest/binary>>, _ContentWithComment, Indent, RestBin, Ctx) ->
    case nyaml_block_util:parse_anchor_name(AnchorRest) of
        {ok, Name, ValuePart} ->
            case nyaml_block_util:strip_whitespace(ValuePart) of
                <<>> ->
                    maybe
                        {ok, Value, NextRest, Ctx1} ?=
                            parse_block_value(RestBin, Indent, Ctx),
                        Ctx2 = nyaml_parser:set_anchor(Name, Value, Ctx1),
                        {ok, Value, NextRest, Ctx2}
                    end;
                TrimmedValue ->
                    maybe
                        {ok, Value, NextRest, Ctx1} ?=
                            parse_item_value(TrimmedValue, TrimmedValue, Indent, RestBin, Ctx),
                        Ctx2 = nyaml_parser:set_anchor(Name, Value, Ctx1),
                        {ok, Value, NextRest, Ctx2}
                    end
            end;
        {error, _} = Err ->
            Err
    end;
parse_item_value(<<"!<", TagRest/binary>>, ContentWithComment, Indent, RestBin, Ctx) ->
    case nyaml_block_util:skip_verbatim_tag(TagRest) of
        {ok, ValuePart} ->
            TrimmedValue = nyaml_block_util:strip_whitespace(ValuePart),
            parse_item_value(TrimmedValue, ContentWithComment, Indent, RestBin, Ctx);
        {error, _} = Err ->
            Err
    end;
parse_item_value(<<"!!", TagRest/binary>> = FullContent, _ContentWithComment, Indent, RestBin, Ctx) ->
    case nyaml_block_util:parse_tag_name(TagRest) of
        {ok, Tag, ValuePart} ->
            TrimmedValue = nyaml_block_util:strip_whitespace(ValuePart),
            case TrimmedValue of
                <<>> ->
                    MinIndent = max(0, Indent - 1),
                    maybe
                        {ok, Value, NextRest, Ctx1} ?= parse_block_value(RestBin, MinIndent, Ctx),
                        {ok, Resolved} ?= nyaml_parser:resolve_tag(Tag, Value, Ctx),
                        {ok, Resolved, NextRest, Ctx1}
                    end;
                <<":", C, _/binary>> when C =:= $\s; C =:= $\t ->
                    FullBin = <<FullContent/binary, "\n", RestBin/binary>>,
                    parse_block_mapping(FullBin, Indent - 2, Ctx);
                <<":">> ->
                    FullBin = <<FullContent/binary, "\n", RestBin/binary>>,
                    parse_block_mapping(FullBin, Indent - 2, Ctx);
                <<"&", _/binary>> = AnchorValue ->
                    maybe
                        {ok, Name, ValuePart2} ?=
                            nyaml_block_util:parse_anchor_name(
                                binary:part(AnchorValue, 1, byte_size(AnchorValue) - 1)
                            ),
                        TrimmedValue2 = nyaml_block_util:strip_whitespace(ValuePart2),
                        {ok, ParsedValue} ?= nyaml_block_util:parse_scalar(TrimmedValue2),
                        {ok, ResolvedValue} ?= nyaml_parser:resolve_tag(Tag, ParsedValue, Ctx),
                        Ctx1 = nyaml_parser:set_anchor(Name, ResolvedValue, Ctx),
                        {ok, ResolvedValue, RestBin, Ctx1}
                    end;
                _ ->
                    maybe
                        {ok, ParsedValue} ?= nyaml_block_util:parse_scalar(TrimmedValue),
                        {ok, Resolved} ?= nyaml_parser:resolve_tag(Tag, ParsedValue, Ctx),
                        {ok, Resolved, RestBin, Ctx}
                    end
            end;
        {error, _} = Err ->
            Err
    end;
parse_item_value(<<"! ", ValueRest/binary>>, _ContentWithComment, _Indent, RestBin, Ctx) ->
    TrimmedValue = nyaml_block_util:strip_whitespace(ValueRest),
    case nyaml_block_util:parse_scalar(TrimmedValue) of
        {ok, ParsedValue} ->
            {ok, nyaml_parser:to_string(ParsedValue), RestBin, Ctx};
        {error, _} = Err ->
            Err
    end;
parse_item_value(<<"!", TagRest/binary>>, ContentWithComment, Indent, RestBin, Ctx) ->
    case nyaml_block_util:skip_local_or_named_tag(TagRest) of
        {ok, ValuePart} ->
            TrimmedValue = nyaml_block_util:strip_whitespace(ValuePart),
            parse_item_value(TrimmedValue, ContentWithComment, Indent, RestBin, Ctx);
        {error, _} = Err ->
            Err
    end;
parse_item_value(Content, ContentWithComment, Indent, RestBin, Ctx) ->
    parse_plain_item_value(Content, ContentWithComment, Indent, RestBin, Ctx).

-spec parse_plain_item_block_or_scalar(binary(), non_neg_integer(), binary(), nyaml_parser:ctx()) ->
    {ok, yaml_value(), binary(), nyaml_parser:ctx()} | {error, term()}.
parse_plain_item_block_or_scalar(<<"-", C, _/binary>> = Content, Indent, RestBin, Ctx) when
    C =:= $\s; C =:= $\t
->
    IndentSpaces = nyaml_block_util:make_indent(Indent),
    FullBin = <<IndentSpaces/binary, Content/binary, "\n", RestBin/binary>>,
    parse_block_sequence(FullBin, Indent, Ctx);
parse_plain_item_block_or_scalar(Content, Indent, RestBin, Ctx) ->
    case nyaml_block_util:has_mapping_indicator(Content) of
        true ->
            IndentSpaces = nyaml_block_util:make_indent(Indent),
            FullBin = <<IndentSpaces/binary, Content/binary, "\n", RestBin/binary>>,
            parse_block_mapping(FullBin, Indent, Ctx);
        false ->
            {ScalarBin, FinalRest} = collect_item_scalar(Content, RestBin, Indent),
            case nyaml_block_util:parse_scalar(ScalarBin) of
                {ok, ParsedValue} -> {ok, ParsedValue, FinalRest, Ctx};
                {error, _} = Err -> Err
            end
    end.

-spec parse_plain_item_fallback(
    binary(), binary(), non_neg_integer(), binary(), nyaml_parser:ctx()
) ->
    {ok, yaml_value(), binary(), nyaml_parser:ctx()} | {error, term()}.
parse_plain_item_fallback(Content, ContentWithComment, Indent, RestBin, Ctx) ->
    case nyaml_block_scalar:is_block_scalar_indicator(Content) of
        true ->
            BlockScalarBin = <<ContentWithComment/binary, "\n", RestBin/binary>>,
            case nyaml_block_scalar:parse(BlockScalarBin, Indent - 2) of
                {ok, Value, ScalarRest} -> {ok, Value, ScalarRest, Ctx};
                {error, _} = Err -> Err
            end;
        false ->
            parse_plain_item_block_or_scalar(Content, Indent, RestBin, Ctx)
    end.

-spec parse_plain_item_value(binary(), binary(), non_neg_integer(), binary(), nyaml_parser:ctx()) ->
    {ok, yaml_value(), binary(), nyaml_parser:ctx()} | {error, term()}.
parse_plain_item_value(Content, ContentWithComment, Indent, RestBin, Ctx) ->
    case Content of
        <<>> ->
            parse_block_value(RestBin, Indent, Ctx);
        <<"[", _/binary>> ->
            case nyaml_block_util:has_flow_collection_key(Content) of
                true ->
                    parse_item_flow_collection_key(Content, Indent, RestBin, Ctx);
                false ->
                    FullBin = <<Content/binary, "\n", RestBin/binary>>,
                    maybe
                        ok ?= validate_item_flow_indent(Content, Indent, RestBin),
                        {ok, Value, FlowRest, Ctx1} ?= nyaml_flow:parse_sequence(FullBin, Ctx),
                        ok ?= nyaml_block_util:validate_rest_of_line(FlowRest),
                        {ok, Value, nyaml_block_util:skip_to_next_line(FlowRest), Ctx1}
                    end
            end;
        <<"{", _/binary>> ->
            case nyaml_block_util:has_flow_collection_key(Content) of
                true ->
                    parse_item_flow_collection_key(Content, Indent, RestBin, Ctx);
                false ->
                    FullBin = <<Content/binary, "\n", RestBin/binary>>,
                    maybe
                        ok ?= validate_item_flow_indent(Content, Indent, RestBin),
                        {ok, Value, FlowRest, Ctx1} ?= nyaml_flow:parse_mapping(FullBin, Ctx),
                        ok ?= nyaml_block_util:validate_rest_of_line(FlowRest),
                        {ok, Value, nyaml_block_util:skip_to_next_line(FlowRest), Ctx1}
                    end
            end;
        <<"\"", _/binary>> ->
            parse_plain_quoted_item_value(Content, double, Indent, RestBin, Ctx);
        <<"'", _/binary>> ->
            parse_plain_quoted_item_value(Content, single, Indent, RestBin, Ctx);
        _ ->
            parse_plain_item_fallback(Content, ContentWithComment, Indent, RestBin, Ctx)
    end.
-spec validate_item_flow_indent(binary(), non_neg_integer(), binary()) ->
    ok | {error, flow_content_wrong_indentation | tab_in_indentation}.
validate_item_flow_indent(Content, Indent, RestBin) ->
    case nyaml_block_util:flow_spans_lines(Content, 0) of
        true -> nyaml_block_util:validate_flow_continuation_indent(RestBin, max(1, Indent - 1));
        false -> ok
    end.

-spec parse_item_flow_collection_key(
    binary(), non_neg_integer(), binary(), nyaml_parser:ctx()
) ->
    {ok, yaml_value(), binary(), nyaml_parser:ctx()} | {error, term()}.
parse_item_flow_collection_key(Content, Indent, RestBin, Ctx) ->
    IndentSpaces = nyaml_block_util:make_indent(Indent),
    FullBin = <<IndentSpaces/binary, Content/binary, "\n", RestBin/binary>>,
    parse_block_mapping(FullBin, Indent, Ctx).

-spec parse_plain_quoted_item_value(
    binary(), nyaml_scalar:quote_type(), non_neg_integer(), binary(), nyaml_parser:ctx()
) ->
    {ok, yaml_value(), binary(), nyaml_parser:ctx()} | {error, term()}.
parse_plain_quoted_item_value(Content, QuoteType, Indent, RestBin, Ctx) ->
    case nyaml_block_util:is_quoted_mapping_key(Content, QuoteType) of
        true ->
            nyaml_block_mapping:parse_mapping_from_content(Content, Indent, RestBin, Ctx);
        false ->
            FullBin = <<Content/binary, "\n", RestBin/binary>>,
            maybe
                {ok, Value, QuotedRest} ?=
                    nyaml_scalar:parse_quoted(FullBin, QuoteType, block_level),
                ok ?= nyaml_block_util:validate_rest_of_line(QuotedRest),
                {ok, Value, nyaml_block_util:skip_to_next_line(QuotedRest), Ctx}
            end
    end.

-spec parse_sequence_items(binary(), non_neg_integer(), [yaml_value()], nyaml_parser:ctx()) ->
    {ok, [yaml_value()], binary(), nyaml_parser:ctx()} | {error, term()}.
parse_sequence_items(Bin, BaseIndent, Acc, Ctx) ->
    case nyaml_block_util:next_line(Bin) of
        {no_more_lines, Rest} ->
            {ok, lists:reverse(Acc), Rest, Ctx};
        {line, Line, Rest} ->
            case nyaml_block_util:is_empty_line(Line) of
                true ->
                    parse_sequence_items(Rest, BaseIndent, Acc, Ctx);
                false ->
                    parse_sequence_items_content(Line, {Bin, Rest}, BaseIndent, Acc, Ctx)
            end
    end.

-spec parse_sequence_items_content(
    binary(), {binary(), binary()}, non_neg_integer(), [yaml_value()], nyaml_parser:ctx()
) ->
    {ok, [yaml_value()], binary(), nyaml_parser:ctx()} | {error, term()}.
parse_sequence_items_content(Line, {Bin, Rest}, BaseIndent, Acc, Ctx) ->
    case nyaml_block_util:block_entry_indent(Line) of
        {error, _} = Err ->
            Err;
        {ok, LineIndent, _} when LineIndent < BaseIndent ->
            {ok, lists:reverse(Acc), Bin, Ctx};
        {ok, LineIndent, <<"-", C, ItemContent/binary>>} when
            (C =:= $\s orelse C =:= $\t) andalso LineIndent =:= BaseIndent
        ->
            case nyaml_block_util:tab_before_nested_block_entry(C, ItemContent) of
                true ->
                    {error, tab_before_nested_block_entry};
                false ->
                    ContentIndent = LineIndent + 2,
                    recurse_sequence_item(
                        parse_item_content(ItemContent, ContentIndent, Rest, Ctx), BaseIndent, Acc
                    )
            end;
        {ok, LineIndent, <<"-">>} when LineIndent =:= BaseIndent ->
            ContentIndent = LineIndent + 1,
            recurse_sequence_item(
                parse_item_content(<<>>, ContentIndent, Rest, Ctx), BaseIndent, Acc
            );
        {ok, LineIndent, Content} when LineIndent =:= BaseIndent ->
            case nyaml_block_util:has_mapping_indicator(Content) of
                true -> {ok, lists:reverse(Acc), Bin, Ctx};
                false -> {error, {invalid_sequence_item, Line}}
            end;
        {ok, _, _} ->
            {error, {invalid_sequence_item, Line}}
    end.

-spec parse_value_content(binary(), non_neg_integer(), binary(), nyaml_parser:ctx()) ->
    {ok, yaml_value(), binary(), nyaml_parser:ctx()} | {error, term()}.
parse_value_content(ValueBin, LineIndent, Rest, Ctx) ->
    case ValueBin of
        <<"[", _/binary>> ->
            case nyaml_block_util:flow_spans_lines(ValueBin, 0) of
                true ->
                    case nyaml_block_util:validate_flow_continuation_indent(Rest, LineIndent + 1) of
                        ok ->
                            parse_flow_sequence_value(ValueBin, Rest, Ctx);
                        {error, _} = Err ->
                            Err
                    end;
                false ->
                    parse_flow_sequence_value(ValueBin, Rest, Ctx)
            end;
        <<"{", _/binary>> ->
            case nyaml_block_util:flow_spans_lines(ValueBin, 0) of
                true ->
                    case nyaml_block_util:validate_flow_continuation_indent(Rest, LineIndent + 1) of
                        ok ->
                            parse_flow_mapping_value(ValueBin, Rest, Ctx);
                        {error, _} = Err ->
                            Err
                    end;
                false ->
                    parse_flow_mapping_value(ValueBin, Rest, Ctx)
            end;
        <<"\"", _/binary>> ->
            FullBin = <<ValueBin/binary, "\n", Rest/binary>>,
            case nyaml_scalar:parse_quoted(FullBin, double, block_level) of
                {ok, Value, QuotedRest} ->
                    case nyaml_block_util:validate_rest_of_line(QuotedRest) of
                        ok -> {ok, Value, nyaml_block_util:skip_to_next_line(QuotedRest), Ctx};
                        {error, _} = Err -> Err
                    end;
                {error, _} = Err ->
                    Err
            end;
        <<"'", _/binary>> ->
            FullBin = <<ValueBin/binary, "\n", Rest/binary>>,
            case nyaml_scalar:parse_quoted(FullBin, single, block_level) of
                {ok, Value, QuotedRest} ->
                    case nyaml_block_util:validate_rest_of_line(QuotedRest) of
                        ok -> {ok, Value, nyaml_block_util:skip_to_next_line(QuotedRest), Ctx};
                        {error, _} = Err -> Err
                    end;
                {error, _} = Err ->
                    Err
            end;
        <<"-", C, ItemContent/binary>> when C =:= $\s; C =:= $\t ->
            SequenceBaseIndent = LineIndent + 2,
            ContentIndent = SequenceBaseIndent + 2,
            case parse_item_content(ItemContent, ContentIndent, Rest, Ctx) of
                {ok, FirstValue, AfterFirst, Ctx1} ->
                    parse_inline_sequence_continuation(
                        AfterFirst, SequenceBaseIndent, [FirstValue], Ctx1
                    );
                {error, _} = Err ->
                    Err
            end;
        _ ->
            case nyaml_block_scalar:is_block_scalar_indicator(ValueBin) of
                true ->
                    BlockScalarBin = <<ValueBin/binary, "\n", Rest/binary>>,
                    case nyaml_block_scalar:parse(BlockScalarBin, LineIndent) of
                        {ok, Value, ScalarRest} ->
                            {ok, Value, ScalarRest, Ctx};
                        {error, _} = Err ->
                            Err
                    end;
                false ->
                    case nyaml_block_util:is_multiline_plain_scalar(Rest, LineIndent + 1) of
                        true ->
                            case
                                nyaml_block_util:collect_plain_scalar_lines(
                                    ValueBin, Rest, LineIndent + 1
                                )
                            of
                                {ok, Value, ScalarRest} ->
                                    {ok, Value, ScalarRest, Ctx};
                                {error, _} = Err ->
                                    Err
                            end;
                        false ->
                            case nyaml_block_util:parse_scalar(ValueBin) of
                                {ok, ParsedValue} ->
                                    {ok, ParsedValue, Rest, Ctx};
                                {error, _} = Err ->
                                    Err
                            end
                    end
            end
    end.

-spec recurse_inline_sequence(
    {ok, yaml_value(), binary(), nyaml_parser:ctx()} | {error, term()},
    non_neg_integer(),
    [yaml_value()]
) ->
    {ok, [yaml_value()], binary(), nyaml_parser:ctx()} | {error, term()}.
recurse_inline_sequence({ok, Value, NextRest, Ctx1}, BaseIndent, Acc) ->
    parse_inline_sequence_continuation(NextRest, BaseIndent, [Value | Acc], Ctx1);
recurse_inline_sequence({error, _} = Err, _BaseIndent, _Acc) ->
    Err.

-spec recurse_sequence_item(
    {ok, yaml_value(), binary(), nyaml_parser:ctx()} | {error, term()},
    non_neg_integer(),
    [yaml_value()]
) ->
    {ok, [yaml_value()], binary(), nyaml_parser:ctx()} | {error, term()}.
recurse_sequence_item({ok, Value, NextBin, Ctx1}, BaseIndent, Acc) ->
    parse_sequence_items(NextBin, BaseIndent, [Value | Acc], Ctx1);
recurse_sequence_item({error, _} = Err, _BaseIndent, _Acc) ->
    Err.

-spec should_stop_item_scalar(non_neg_integer(), binary(), non_neg_integer()) -> boolean().
should_stop_item_scalar(LineIndent, TrimmedContent, BaseIndent) ->
    ContentIndent = BaseIndent + 2,
    case LineIndent >= ContentIndent of
        true ->
            nyaml_block_util:has_mapping_indicator(TrimmedContent) orelse
                nyaml_block_util:is_block_indicator(TrimmedContent);
        false ->
            nyaml_block_util:has_mapping_indicator(TrimmedContent)
    end.
