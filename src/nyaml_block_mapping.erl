-module(nyaml_block_mapping).

-moduledoc """
Block-style YAML mapping parsing.

Handles `key: value` entries, explicit `?` keys (with multi-line keys
and block-scalar keys), key-value separator scanning that respects
quotes and flow collections, and key tag/anchor resolution.

Calls back into `nyaml_block` for `parse_block/3`, `parse_block_value/3`
and `parse_entry_value/4` when a key or value needs full block-level
parsing.
""".

-export([parse_mapping_entries/4, parse_mapping_from_content/4]).

-spec append_explicit_key_line(binary(), binary()) -> binary().
append_explicit_key_line(<<>>, TrimmedContent) ->
    TrimmedContent;
append_explicit_key_line(Acc, TrimmedContent) ->
    <<Acc/binary, " ", TrimmedContent/binary>>.
-spec close_mapping(
    {ok, nyaml_merge:acc(), binary(), nyaml_parser:ctx()} | {error, nyaml_parser:parse_error()}
) ->
    {ok, #{nyaml:yaml_value() => nyaml:yaml_value()}, binary(), nyaml_parser:ctx()}
    | {error, nyaml_parser:parse_error()}.
close_mapping({ok, Acc, Rest, Ctx}) ->
    maybe
        {ok, Map} ?= nyaml_merge:close(Acc),
        {ok, Map, Rest, Ctx}
    end;
close_mapping({error, _} = Err) ->
    Err.
-spec collect_explicit_key(binary(), binary(), non_neg_integer()) ->
    {ok, nyaml_parser:yaml_value(), binary(), boolean()} | {error, tab_in_indentation}.
collect_explicit_key(FirstLineKey, Rest, BaseIndent) ->
    TrimmedKey = nyaml_block_util:strip_whitespace(FirstLineKey),
    case nyaml_block_scalar:is_block_scalar_indicator(TrimmedKey) of
        true ->
            BlockScalarBin = <<TrimmedKey/binary, "\n", Rest/binary>>,
            case nyaml_block_scalar:parse(BlockScalarBin, BaseIndent) of
                {ok, Key, RestAfterScalar} ->
                    {ok, Key, RestAfterScalar, true};
                {error, _} ->
                    collect_explicit_key_plain(Rest, TrimmedKey, BaseIndent)
            end;
        false ->
            case split_inline_explicit_key_value(TrimmedKey) of
                {Key, ValuePart} ->
                    InlineRest = <<": ", ValuePart/binary, "\n", Rest/binary>>,
                    {ok, Key, InlineRest, false};
                no_inline_value ->
                    collect_explicit_key_plain(Rest, TrimmedKey, BaseIndent)
            end
    end.

-spec collect_explicit_key_at_base(binary(), binary(), binary(), binary(), non_neg_integer()) ->
    {binary(), binary()} | {error, tab_in_indentation}.
collect_explicit_key_at_base(<<":", _/binary>>, Bin, _Rest, Acc, _BaseIndent) ->
    {nyaml_block_util:strip_whitespace(Acc), Bin};
collect_explicit_key_at_base(<<"?", _/binary>>, Bin, _Rest, Acc, _BaseIndent) ->
    {nyaml_block_util:strip_whitespace(Acc), Bin};
collect_explicit_key_at_base(Content, Bin, Rest, Acc, BaseIndent) ->
    case nyaml_block_util:has_mapping_indicator(Content) of
        true ->
            {nyaml_block_util:strip_whitespace(Acc), Bin};
        false ->
            TrimmedContent = nyaml_block_util:strip_comment(
                nyaml_block_util:strip_whitespace(Content)
            ),
            NewAcc = <<Acc/binary, " ", TrimmedContent/binary>>,
            collect_explicit_key_lines(Rest, NewAcc, BaseIndent)
    end.
-spec collect_explicit_key_content(binary(), binary(), binary(), binary(), non_neg_integer()) ->
    {binary(), binary()} | {error, tab_in_indentation}.
collect_explicit_key_content(Line, Bin, Rest, Acc, BaseIndent) ->
    case nyaml_block_util:get_indent_and_line(Line) of
        {error, _} = Err ->
            Err;
        {ok, LineIndent, Content} when LineIndent > BaseIndent ->
            TrimmedContent = nyaml_block_util:strip_comment(
                nyaml_block_util:strip_whitespace(Content)
            ),
            NewAcc = append_explicit_key_line(Acc, TrimmedContent),
            collect_explicit_key_lines(Rest, NewAcc, BaseIndent);
        {ok, LineIndent, _Content} when LineIndent < BaseIndent ->
            {nyaml_block_util:strip_whitespace(Acc), Bin};
        {ok, _, Content} ->
            collect_explicit_key_at_base(Content, Bin, Rest, Acc, BaseIndent)
    end.
-spec collect_explicit_key_lines(binary(), binary(), non_neg_integer()) ->
    {binary(), binary()} | {error, tab_in_indentation}.
collect_explicit_key_lines(<<>>, Acc, _BaseIndent) ->
    {Acc, <<>>};
collect_explicit_key_lines(Bin, Acc, BaseIndent) ->
    case nyaml_block_util:next_line(Bin) of
        {no_more_lines, Rest} ->
            {Acc, Rest};
        {line, Line, Rest} ->
            case nyaml_block_util:is_empty_line(Line) of
                true -> collect_explicit_key_lines(Rest, Acc, BaseIndent);
                false -> collect_explicit_key_content(Line, Bin, Rest, Acc, BaseIndent)
            end
    end.
-spec collect_explicit_key_plain(binary(), binary(), non_neg_integer()) ->
    {ok, binary(), binary(), false} | {error, tab_in_indentation}.
collect_explicit_key_plain(Rest, TrimmedKey, BaseIndent) ->
    case collect_explicit_key_lines(Rest, TrimmedKey, BaseIndent) of
        {error, tab_in_indentation} = Err -> Err;
        {KeyPlain, RestPlain} -> {ok, KeyPlain, RestPlain, false}
    end.
-spec collect_mapping_entries(
    binary(), non_neg_integer(), nyaml_merge:acc(), nyaml_parser:ctx()
) ->
    {ok, nyaml_merge:acc(), binary(), nyaml_parser:ctx()}
    | {error, nyaml_parser:parse_error()}.
collect_mapping_entries(Bin, BaseIndent, Acc, Ctx) ->
    case nyaml_block_util:next_line(Bin) of
        {no_more_lines, Rest} ->
            {ok, Acc, Rest, Ctx};
        {line, Line, Rest} ->
            case nyaml_block_util:is_empty_line(Line) of
                true ->
                    collect_mapping_entries(Rest, BaseIndent, Acc, Ctx);
                false ->
                    collect_mapping_entries_content(Line, {Bin, Rest}, BaseIndent, Acc, Ctx)
            end
    end.

-spec collect_mapping_entries_content(
    binary(),
    {binary(), binary()},
    non_neg_integer(),
    nyaml_merge:acc(),
    nyaml_parser:ctx()
) ->
    {ok, nyaml_merge:acc(), binary(), nyaml_parser:ctx()}
    | {error, nyaml_parser:parse_error()}.
collect_mapping_entries_content(Line, {Bin, Rest}, BaseIndent, Acc, Ctx) ->
    case nyaml_block_util:block_entry_indent(Line) of
        {error, _} = Err ->
            Err;
        {ok, LineIndent, _} when LineIndent < BaseIndent ->
            {ok, Acc, Bin, Ctx};
        {ok, LineIndent, _} when LineIndent > BaseIndent ->
            {error, {invalid_indentation, LineIndent, expected, BaseIndent}};
        {ok, LineIndent, Content} ->
            maybe
                {ok, Key, Value, NextBin, Ctx1} ?=
                    parse_mapping_entry(Content, LineIndent, Rest, Ctx),
                NewAcc = nyaml_merge:add_entry(Key, Value, Acc),
                collect_mapping_entries(NextBin, BaseIndent, NewAcc, Ctx1)
            end
    end.
-spec find_explicit_value(binary(), non_neg_integer()) ->
    {ok, binary(), binary()}
    | {null_value, binary()}
    | {error,
        tab_before_nested_block_entry
        | tab_in_indentation
        | {expected_value_indicator, binary()}}.
find_explicit_value(Bin, BaseIndent) ->
    case nyaml_block_util:next_line(Bin) of
        {no_more_lines, Rest} ->
            {null_value, Rest};
        {line, Line, Rest} ->
            case nyaml_block_util:is_empty_line(Line) of
                true -> find_explicit_value(Rest, BaseIndent);
                false -> find_explicit_value_content(Line, Bin, Rest, BaseIndent)
            end
    end.

-spec find_explicit_value_content(binary(), binary(), binary(), non_neg_integer()) ->
    {ok, binary(), binary()}
    | {null_value, binary()}
    | {error,
        tab_before_nested_block_entry
        | tab_in_indentation
        | {expected_value_indicator, binary()}}.
find_explicit_value_content(Line, Bin, Rest, BaseIndent) ->
    case nyaml_block_util:get_indent_and_line(Line) of
        {error, _} = Err ->
            Err;
        {ok, _LineIndent, <<":", C, ValueRest/binary>>} when C =:= $\s; C =:= $\t ->
            case nyaml_block_util:tab_before_nested_block_entry(C, ValueRest) of
                true -> {error, tab_before_nested_block_entry};
                false -> {ok, nyaml_block_util:strip_whitespace(ValueRest), Rest}
            end;
        {ok, _LineIndent, <<":">>} ->
            {ok, <<>>, Rest};
        {ok, LineIndent, <<"?", _/binary>>} when LineIndent =< BaseIndent ->
            {null_value, Bin};
        {ok, LineIndent, _Content} when LineIndent < BaseIndent ->
            {null_value, Bin};
        {ok, LineIndent, Content} when LineIndent =:= BaseIndent ->
            case nyaml_block_util:has_mapping_indicator(Content) of
                true -> {null_value, Bin};
                false -> {error, {expected_value_indicator, Content}}
            end;
        {ok, _, Content} ->
            {error, {expected_value_indicator, Content}}
    end.

-spec find_key_value_separator(binary(), non_neg_integer()) -> {binary(), binary()} | error.
find_key_value_separator(Line, Offset) when Offset >= byte_size(Line) ->
    error;
find_key_value_separator(Line, Offset) ->
    CommentEnd = nyaml_block_util:find_comment_start(Line),
    find_key_value_separator(Line, Offset, CommentEnd, node_start).

-spec find_key_value_separator(
    binary(), non_neg_integer(), non_neg_integer(), node_start | in_plain
) ->
    {binary(), binary()} | error.
find_key_value_separator(Line, Offset, CommentEnd, _Position) when
    Offset >= byte_size(Line) orelse Offset >= CommentEnd
->
    error;
find_key_value_separator(Line, Offset, CommentEnd, in_plain) ->
    scan_for_separator(Line, Offset, CommentEnd);
find_key_value_separator(Line, Offset, CommentEnd, node_start) ->
    case binary:at(Line, Offset) of
        $' ->
            case nyaml_block_util:skip_single_quoted(Line, Offset + 1) of
                {ok, EndOffset} -> find_key_value_separator(Line, EndOffset, CommentEnd, in_plain);
                error -> error
            end;
        $" ->
            case nyaml_block_util:skip_double_quoted(Line, Offset + 1) of
                {ok, EndOffset} -> find_key_value_separator(Line, EndOffset, CommentEnd, in_plain);
                error -> error
            end;
        $[ ->
            case nyaml_block_util:skip_flow_collection(Line, Offset + 1, $], 1) of
                {ok, EndOffset} -> find_key_value_separator(Line, EndOffset, CommentEnd, in_plain);
                error -> error
            end;
        ${ ->
            case nyaml_block_util:skip_flow_collection(Line, Offset + 1, $}, 1) of
                {ok, EndOffset} -> find_key_value_separator(Line, EndOffset, CommentEnd, in_plain);
                error -> error
            end;
        _ ->
            scan_for_separator(Line, Offset, CommentEnd)
    end.

-spec scan_for_separator(binary(), non_neg_integer(), non_neg_integer()) ->
    {binary(), binary()} | error.
scan_for_separator(Line, Offset, CommentEnd) ->
    SearchEnd = min(CommentEnd, byte_size(Line)),
    case Offset < SearchEnd of
        true ->
            case binary:match(Line, <<":">>, [{scope, {Offset, SearchEnd - Offset}}]) of
                {Pos, 1} when Pos < CommentEnd ->
                    case binary:part(Line, Pos + 1, byte_size(Line) - Pos - 1) of
                        <<>> ->
                            Key = binary:part(Line, {0, Pos}),
                            {Key, <<>>};
                        <<C, _/binary>> when C =:= $\s; C =:= $\t ->
                            Key = binary:part(Line, {0, Pos}),
                            ValueStart = Pos + 1,
                            ValueLen = byte_size(Line) - ValueStart,
                            Value = binary:part(Line, {ValueStart, ValueLen}),
                            {Key, Value};
                        _ ->
                            find_key_value_separator(Line, Pos + 1, CommentEnd, in_plain)
                    end;
                _ ->
                    error
            end;
        false ->
            error
    end.
-spec finish_collected_explicit_key(
    boolean(), nyaml_parser:yaml_value(), binary(), non_neg_integer(), nyaml_parser:ctx()
) ->
    {ok, nyaml_merge:key(), nyaml_parser:yaml_value(), binary(), nyaml_parser:ctx()}
    | {error, nyaml_parser:parse_error()}.
finish_collected_explicit_key(true, FullKey, RestAfterKey, BaseIndent, Ctx) ->
    finish_explicit_key_entry(FullKey, RestAfterKey, BaseIndent, Ctx);
finish_collected_explicit_key(false, FullKey, RestAfterKey, BaseIndent, Ctx) ->
    maybe
        {ok, KeyBin, Ctx1} ?=
            resolve_key_tag(
                nyaml_block_util:strip_comment(nyaml_block_util:strip_whitespace(FullKey)), Ctx
            ),
        finish_explicit_key_entry(KeyBin, RestAfterKey, BaseIndent, Ctx1)
    end.

-spec finish_explicit_key_entry(
    nyaml_parser:yaml_value(), binary(), non_neg_integer(), nyaml_parser:ctx()
) ->
    {ok, nyaml_merge:key(), nyaml_parser:yaml_value(), binary(), nyaml_parser:ctx()}
    | {error, nyaml_parser:parse_error()}.
finish_explicit_key_entry(KeyValue, RestAfterKey, BaseIndent, Ctx) ->
    case find_explicit_value(RestAfterKey, BaseIndent) of
        {ok, ValueBin, NextRest} ->
            StrippedValue = nyaml_block_util:strip_comment(ValueBin),
            case nyaml_block_util:strip_whitespace(StrippedValue) of
                <<>> ->
                    maybe
                        {ok, ParsedValue, FinalRest, Ctx1} ?=
                            nyaml_block:parse_block_value(NextRest, BaseIndent, Ctx),
                        {ok, KeyValue, ParsedValue, FinalRest, Ctx1}
                    end;
                ActualValue ->
                    maybe
                        {ok, ParsedValue, FinalRest, Ctx1} ?=
                            nyaml_block:parse_entry_value(
                                ActualValue, BaseIndent, NextRest, Ctx
                            ),
                        {ok, KeyValue, ParsedValue, FinalRest, Ctx1}
                    end
            end;
        {null_value, NextRest} ->
            {ok, KeyValue, null, NextRest, Ctx};
        {error, _} = Err ->
            Err
    end.
-spec handle_explicit_key_above_base(
    binary(), binary(), non_neg_integer(), non_neg_integer(), nyaml_parser:ctx()
) ->
    {ok, nyaml_merge:key(), nyaml_parser:yaml_value(), binary(), nyaml_parser:ctx()}
    | {error, nyaml_parser:parse_error()}.
handle_explicit_key_above_base(Content, Bin1, KeyIndent, BaseIndent, Ctx) ->
    case nyaml_block_util:has_mapping_indicator(Content) of
        true ->
            parse_explicit_key_as_structure(Bin1, KeyIndent, BaseIndent, Ctx);
        false ->
            case
                collect_explicit_key(Content, nyaml_block_util:skip_to_next_line(Bin1), KeyIndent)
            of
                {ok, FullKey, RestAfterKey, IsBlockScalar} ->
                    finish_collected_explicit_key(
                        IsBlockScalar, FullKey, RestAfterKey, BaseIndent, Ctx
                    );
                {error, _} = Err ->
                    Err
            end
    end.
-spec parse_explicit_key_as_structure(
    binary(), non_neg_integer(), non_neg_integer(), nyaml_parser:ctx()
) ->
    {ok, nyaml_merge:key(), nyaml_parser:yaml_value(), binary(), nyaml_parser:ctx()}
    | {error, nyaml_parser:parse_error()}.
parse_explicit_key_as_structure(Bin, KeyIndent, BaseIndent, Ctx) ->
    case nyaml_block:parse_block(Bin, KeyIndent, Ctx) of
        {ok, KeyValue, RestAfterKey, Ctx1} ->
            finish_explicit_key_entry(KeyValue, RestAfterKey, BaseIndent, Ctx1);
        {error, _} = Err ->
            Err
    end.
-spec parse_explicit_key_entry(binary(), non_neg_integer(), binary(), nyaml_parser:ctx()) ->
    {ok, nyaml_merge:key(), nyaml_parser:yaml_value(), binary(), nyaml_parser:ctx()}
    | {error, nyaml_parser:parse_error()}.
parse_explicit_key_entry(KeyContent, LineIndent, Rest, Ctx) ->
    TrimmedKey = nyaml_block_util:strip_comment(nyaml_block_util:strip_whitespace(KeyContent)),
    case TrimmedKey of
        <<>> ->
            parse_explicit_key_from_next_lines(Rest, LineIndent, Ctx);
        _ ->
            case collect_explicit_key(KeyContent, Rest, LineIndent) of
                {ok, FullKey, RestAfterKey, true} ->
                    finish_explicit_key_entry(FullKey, RestAfterKey, LineIndent, Ctx);
                {ok, FullKey, RestAfterKey, false} ->
                    maybe
                        {ok, KeyBin, Ctx1} ?=
                            resolve_key_tag(
                                nyaml_block_util:strip_comment(
                                    nyaml_block_util:strip_whitespace(FullKey)
                                ),
                                Ctx
                            ),
                        finish_explicit_key_entry(KeyBin, RestAfterKey, LineIndent, Ctx1)
                    end;
                {error, _} = Err ->
                    Err
            end
    end.

-spec parse_explicit_key_from_next_lines(binary(), non_neg_integer(), nyaml_parser:ctx()) ->
    {ok, nyaml_merge:key(), nyaml_parser:yaml_value(), binary(), nyaml_parser:ctx()}
    | {error, nyaml_parser:parse_error()}.
parse_explicit_key_from_next_lines(Bin, BaseIndent, Ctx) ->
    case nyaml_block_util:skip_empty_lines(Bin) of
        <<>> ->
            {ok, null, null, <<>>, Ctx};
        Bin1 ->
            FirstLine = nyaml_block_util:get_first_line(Bin1),
            case nyaml_block_util:get_indent_and_line(FirstLine) of
                {error, _} = Err ->
                    Err;
                {ok, KeyIndent, Content} ->
                    case Content of
                        <<":", _/binary>> when KeyIndent =< BaseIndent ->
                            finish_explicit_key_entry(null, Bin1, BaseIndent, Ctx);
                        <<"-", C, _/binary>> when
                            (C =:= $\s orelse C =:= $\t), KeyIndent >= BaseIndent
                        ->
                            parse_explicit_key_as_structure(Bin1, KeyIndent, BaseIndent, Ctx);
                        <<"-">> when KeyIndent >= BaseIndent ->
                            parse_explicit_key_as_structure(Bin1, KeyIndent, BaseIndent, Ctx);
                        <<"?", _/binary>> when KeyIndent >= BaseIndent ->
                            parse_explicit_key_as_structure(Bin1, KeyIndent, BaseIndent, Ctx);
                        _ when KeyIndent > BaseIndent ->
                            handle_explicit_key_above_base(
                                Content, Bin1, KeyIndent, BaseIndent, Ctx
                            );
                        _ when KeyIndent =:= BaseIndent ->
                            case nyaml_block_util:has_mapping_indicator(Content) of
                                true ->
                                    parse_explicit_key_as_structure(
                                        Bin1, KeyIndent, BaseIndent, Ctx
                                    );
                                false ->
                                    {error, {explicit_key_missing_content, Content}}
                            end;
                        _ ->
                            {error, {explicit_key_missing_content, Content}}
                    end
            end
    end.

-spec parse_key_with_anchor(binary(), nyaml_parser:ctx()) ->
    {ok, nyaml_merge:key(), nyaml_parser:ctx()} | {error, nyaml_parser:parse_error()}.
parse_key_with_anchor(<<"&", Rest/binary>>, Ctx) ->
    case nyaml_block_util:parse_anchor_name(Rest) of
        {ok, AnchorName, KeyPart} ->
            KeyValue = nyaml_block_util:strip_whitespace(KeyPart),
            case KeyValue of
                <<"*", _/binary>> ->
                    {error, anchor_followed_by_alias};
                _ ->
                    maybe
                        {ok, ParsedKey, Ctx1} ?= parse_key_with_anchor(KeyValue, Ctx),
                        Ctx2 = nyaml_parser:set_anchor(
                            AnchorName, nyaml_merge:unmark(ParsedKey), Ctx1
                        ),
                        {ok, ParsedKey, Ctx2}
                    end
            end;
        {error, _} = Err ->
            Err
    end;
parse_key_with_anchor(<<"*", Rest/binary>>, Ctx) ->
    case nyaml_block_util:parse_anchor_name(Rest) of
        {ok, AliasName, <<>>} ->
            maybe
                {ok, Value} ?= nyaml_parser:resolve_alias(AliasName, Ctx),
                {ok, Value, Ctx}
            end;
        {ok, _, _} ->
            {error, {invalid_alias_key, <<"*", Rest/binary>>}};
        {error, _} = Err ->
            Err
    end;
parse_key_with_anchor(<<"!!", Rest/binary>>, Ctx) ->
    case nyaml_block_util:parse_tag_name(Rest) of
        {ok, Tag, KeyPart} ->
            KeyValue = nyaml_block_util:strip_whitespace(KeyPart),
            maybe
                {ok, ParsedKey, Ctx1} ?= parse_key_with_anchor(KeyValue, Ctx),
                {ok, Resolved} ?=
                    nyaml_parser:resolve_tag(
                        Tag, nyaml_merge:unmark(ParsedKey), Ctx
                    ),
                {ok, Resolved, Ctx1}
            end;
        {error, _} = Err ->
            Err
    end;
parse_key_with_anchor(<<"\"", _/binary>> = QuotedKey, Ctx) ->
    case nyaml_scalar:parse_quoted(QuotedKey, double, block_level) of
        {ok, Value, _Rest} -> {ok, Value, Ctx};
        {error, _} = Err -> Err
    end;
parse_key_with_anchor(<<"'", _/binary>> = QuotedKey, Ctx) ->
    case nyaml_scalar:parse_quoted(QuotedKey, single, block_level) of
        {ok, Value, _Rest} -> {ok, Value, Ctx};
        {error, _} = Err -> Err
    end;
parse_key_with_anchor(<<"[", _/binary>> = FlowKey, Ctx) ->
    case nyaml_flow:parse_sequence(FlowKey, Ctx) of
        {ok, Value, _Rest, Ctx1} -> {ok, Value, Ctx1};
        {error, _} = Err -> Err
    end;
parse_key_with_anchor(<<"{", _/binary>> = FlowKey, Ctx) ->
    case nyaml_flow:parse_mapping(FlowKey, Ctx) of
        {ok, Value, _Rest, Ctx1} -> {ok, Value, Ctx1};
        {error, _} = Err -> Err
    end;
parse_key_with_anchor(KeyBin, Ctx) ->
    {ok, Key} = nyaml_merge:resolve_key(KeyBin, Ctx),
    {ok, Key, Ctx}.
-doc """
Parses consecutive block mapping entries at `BaseIndent`, folding each
`key: value` (or explicit `?`/`:`) entry into `Map` and returning the
completed map, the unconsumed input, and the updated context.

A merge key is folded when the mapping ends, so the mapping's own keys win
over the merged ones.
""".
-spec parse_mapping_entries(
    binary(),
    non_neg_integer(),
    #{nyaml:yaml_value() => nyaml:yaml_value()},
    nyaml_parser:ctx()
) ->
    {ok, #{nyaml:yaml_value() => nyaml:yaml_value()}, binary(), nyaml_parser:ctx()}
    | {error, nyaml_parser:parse_error()}.
parse_mapping_entries(Bin, BaseIndent, Map, Ctx) ->
    close_mapping(collect_mapping_entries(Bin, BaseIndent, nyaml_merge:new(Map), Ctx)).

-spec parse_mapping_entry(binary(), non_neg_integer(), binary(), nyaml_parser:ctx()) ->
    {ok, nyaml_merge:key(), nyaml_parser:yaml_value(), binary(), nyaml_parser:ctx()}
    | {error, nyaml_parser:parse_error()}.
parse_mapping_entry(<<"?", C, KeyRest/binary>>, LineIndent, Rest, Ctx) when C =:= $\s; C =:= $\t ->
    case nyaml_block_util:tab_before_nested_block_entry(C, KeyRest) of
        true ->
            {error, tab_before_nested_block_entry};
        false ->
            parse_explicit_key_entry(
                nyaml_block_util:strip_whitespace(KeyRest), LineIndent, Rest, Ctx
            )
    end;
parse_mapping_entry(<<"?">>, LineIndent, Rest, Ctx) ->
    parse_explicit_key_entry(<<>>, LineIndent, Rest, Ctx);
parse_mapping_entry(Line, LineIndent, Rest, Ctx) ->
    case split_at_key_value_separator(Line) of
        {Key, Value} ->
            KeyBin = nyaml_block_util:strip_whitespace(Key),
            ValueWithComment = nyaml_block_util:strip_whitespace(Value),
            ValueBin = nyaml_block_util:strip_comment(ValueWithComment),
            case nyaml_block_util:is_plain_scalar_with_mapping_indicator(ValueBin) of
                true ->
                    {error, {ambiguous_mapping_in_value, ValueBin}};
                false ->
                    maybe
                        {ok, NormalizedKey, Ctx1} ?= parse_key_with_anchor(KeyBin, Ctx),
                        {ok, ParsedValue, NextRest, Ctx2} ?=
                            nyaml_block:parse_entry_value(ValueBin, LineIndent, Rest, Ctx1),
                        {ok, NormalizedKey, ParsedValue, NextRest, Ctx2}
                    end
            end;
        error ->
            {error, {invalid_mapping_entry, Line}}
    end.
-spec parse_mapping_from_content(binary(), non_neg_integer(), binary(), nyaml_parser:ctx()) ->
    {ok, #{nyaml:yaml_value() => nyaml:yaml_value()}, binary(), nyaml_parser:ctx()}
    | {error, nyaml_parser:parse_error()}.
parse_mapping_from_content(Content, BaseIndent, Rest, Ctx) ->
    maybe
        {ok, Key, Value, NextBin, Ctx1} ?=
            parse_mapping_entry(Content, BaseIndent, Rest, Ctx),
        Acc = nyaml_merge:add_entry(Key, Value, nyaml_merge:new(#{})),
        close_mapping(collect_mapping_entries(NextBin, BaseIndent, Acc, Ctx1))
    end.

-spec resolve_key_tag(binary(), nyaml_parser:ctx()) ->
    {ok, nyaml_merge:key(), nyaml_parser:ctx()} | {error, nyaml_parser:parse_error()}.
resolve_key_tag(<<"!!", Rest/binary>>, Ctx) ->
    case binary:match(Rest, <<" ">>) of
        {Pos, 1} ->
            Tag = binary:part(Rest, 0, Pos),
            Value = binary:part(Rest, Pos + 1, byte_size(Rest) - Pos - 1),
            maybe
                {ok, Content, Ctx1} ?=
                    resolve_key_tag(nyaml_block_util:strip_whitespace(Value), Ctx),
                {ok, Resolved} ?=
                    nyaml_parser:resolve_tag(
                        Tag, nyaml_merge:unmark(Content), Ctx1
                    ),
                {ok, Resolved, Ctx1}
            end;
        nomatch ->
            {ok, <<"!!", Rest/binary>>, Ctx}
    end;
resolve_key_tag(<<"&", Rest/binary>>, Ctx) ->
    case nyaml_block_util:parse_anchor_name(Rest) of
        {ok, AnchorName, KeyRest} ->
            Key = nyaml_block_util:strip_whitespace(KeyRest),
            Ctx1 = nyaml_parser:set_anchor(AnchorName, Key, Ctx),
            {ok, Key, Ctx1};
        {error, _} ->
            {ok, <<"&", Rest/binary>>, Ctx}
    end;
resolve_key_tag(<<"*", Rest/binary>> = Original, Ctx) ->
    maybe
        {ok, AliasName, _Rest} ?= nyaml_block_util:parse_anchor_name(Rest),
        {ok, Value} ?= nyaml_parser:resolve_alias(AliasName, Ctx),
        {ok, Value, Ctx}
    else
        {error, _} -> {ok, Original, Ctx}
    end;
resolve_key_tag(<<"\"", _/binary>> = QuotedKey, Ctx) ->
    case nyaml_scalar:parse_quoted(QuotedKey, double, block_level) of
        {ok, Value, _Rest} -> {ok, Value, Ctx};
        {error, _} -> {ok, QuotedKey, Ctx}
    end;
resolve_key_tag(<<"'", _/binary>> = QuotedKey, Ctx) ->
    case nyaml_scalar:parse_quoted(QuotedKey, single, block_level) of
        {ok, Value, _Rest} -> {ok, Value, Ctx};
        {error, _} -> {ok, QuotedKey, Ctx}
    end;
resolve_key_tag(Key, Ctx) ->
    {ok, Resolved} = nyaml_merge:resolve_key(Key, Ctx),
    {ok, Resolved, Ctx}.
-spec split_at_key_value_separator(binary()) -> {binary(), binary()} | error.
split_at_key_value_separator(Line) ->
    StartOffset = nyaml_block_util:skip_anchor_or_alias_prefix(Line),
    find_key_value_separator(Line, StartOffset).

-spec split_inline_explicit_key_value(binary()) -> {binary(), binary()} | no_inline_value.
split_inline_explicit_key_value(Bin) ->
    split_inline_explicit_key_value(Bin, <<>>).

-spec split_inline_explicit_key_value(binary(), binary()) ->
    {binary(), binary()} | no_inline_value.
split_inline_explicit_key_value(<<>>, _Acc) ->
    no_inline_value;
split_inline_explicit_key_value(<<" : ", Rest/binary>>, Acc) ->
    {nyaml_block_util:strip_whitespace(Acc), nyaml_block_util:strip_whitespace(Rest)};
split_inline_explicit_key_value(<<"\t: ", Rest/binary>>, Acc) ->
    {nyaml_block_util:strip_whitespace(Acc), nyaml_block_util:strip_whitespace(Rest)};
split_inline_explicit_key_value(<<" :", Rest/binary>>, Acc) when
    Rest =:= <<>> orelse Rest =:= <<"\t">>
->
    {nyaml_block_util:strip_whitespace(Acc), <<>>};
split_inline_explicit_key_value(<<C, Rest/binary>>, Acc) ->
    split_inline_explicit_key_value(Rest, <<Acc/binary, C>>).
