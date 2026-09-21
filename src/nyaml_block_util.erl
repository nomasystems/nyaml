-module(nyaml_block_util).

-moduledoc """
Pure utility functions for block-style YAML parsing.

Binary navigation (line splitting, indentation counting), whitespace and
comment stripping, mapping/block indicator detection, anchor/tag name
parsers, flow-spanning checks, and plain-scalar collection helpers.

These functions are stateless and have no dependency on `nyaml_parser`
state; they support the higher-level dispatch in `nyaml_block`,
`nyaml_block_mapping`, and `nyaml_block_sequence`.
""".

-export([
    anchor_value_position/1,
    block_entry_indent/1,
    collect_plain_scalar_lines/3,
    collect_scalar_lines/4,
    count_leading_ws/1,
    find_comment_start/1,
    flow_spans_lines/2,
    fold_scalar/1,
    get_first_line/1,
    get_indent_and_line/1,
    has_comment/1,
    has_flow_collection_key/1,
    has_mapping_indicator/1,
    has_mapping_indicator_after_anchor/1,
    is_block_indicator/1,
    is_comment_only_line/1,
    is_empty_line/1,
    is_multiline_plain_scalar/2,
    is_plain_scalar_with_mapping_indicator/1,
    is_quoted_mapping_key/2,
    make_indent/1,
    next_line/1,
    next_non_empty_line/1,
    parse_anchor_name/1,
    parse_scalar/1,
    parse_tag_name/1,
    skip_anchor_or_alias_prefix/1,
    skip_double_quoted/2,
    skip_empty_lines/1,
    skip_flow_collection/4,
    skip_local_or_named_tag/1,
    skip_single_quoted/2,
    skip_tag_chars/1,
    skip_to_next_line/1,
    skip_verbatim_tag/1,
    starts_with_scalar_anchor/2,
    strip_comment/1,
    strip_trailing_ws/1,
    strip_whitespace/1,
    tab_before_nested_block_entry/2,
    validate_flow_continuation_indent/2,
    validate_rest_of_line/1
]).

-doc """
Reports whether the text after an anchor or alias name is empty or at end of line, or holds an inline value.
""".
-spec anchor_value_position(binary()) -> empty_or_newline | {inline, binary()}.
anchor_value_position(<<>>) ->
    empty_or_newline;
anchor_value_position(<<"\n", _/binary>>) ->
    empty_or_newline;
anchor_value_position(<<"\r\n", _/binary>>) ->
    empty_or_newline;
anchor_value_position(<<C, Rest/binary>>) when C =:= $\s; C =:= $\t ->
    anchor_value_position(Rest);
anchor_value_position(<<"#", _/binary>>) ->
    empty_or_newline;
anchor_value_position(Content) ->
    {inline, Content}.

-doc """
Splits a block collection entry line into its indentation count and content.

Indentation is spaces and the entry that follows it opens with an `ns-char`, so
a tab on either side of the indentation is neither indentation nor content.
""".
-spec block_entry_indent(binary()) ->
    {ok, non_neg_integer(), binary()} | {error, tab_in_indentation}.
block_entry_indent(Line) ->
    case get_indent_and_line(Line) of
        {ok, _Indent, <<$\t, _/binary>>} -> {error, tab_in_indentation};
        Result -> Result
    end.

-spec collect_plain_scalar_content(
    binary(), binary(), binary(), non_neg_integer(), {binary(), non_neg_integer()}
) ->
    {ok, nyaml_parser:yaml_value(), binary()} | {error, nyaml_parser:parse_error()}.
collect_plain_scalar_content(Line, Bin, NextRest, MinIndent, {Acc, BlankCount}) ->
    case get_indent_and_line(Line) of
        {error, _} = Err ->
            Err;
        {ok, Indent, _} when Indent < MinIndent ->
            finish_plain_scalar(Acc, Bin);
        {ok, _, Content} ->
            TrimmedContent = strip_comment(strip_whitespace(Content)),
            case
                has_mapping_indicator(TrimmedContent) orelse
                    is_block_indicator(TrimmedContent)
            of
                true ->
                    finish_plain_scalar(Acc, Bin);
                false ->
                    NewAcc = extend_plain_scalar_acc(Acc, TrimmedContent, BlankCount),
                    case has_comment(Content) of
                        true ->
                            case has_more_content(NextRest, MinIndent) of
                                true -> {error, content_after_comment};
                                false -> finish_plain_scalar(NewAcc, NextRest)
                            end;
                        false ->
                            collect_plain_scalar_continuation(NextRest, MinIndent, NewAcc, 0)
                    end
            end
    end.
-spec collect_plain_scalar_continuation(binary(), non_neg_integer(), binary(), non_neg_integer()) ->
    {ok, nyaml_parser:yaml_value(), binary()} | {error, nyaml_parser:parse_error()}.
collect_plain_scalar_continuation(Bin, MinIndent, Acc, BlankCount) ->
    case next_line(Bin) of
        {no_more_lines, Rest} ->
            finish_plain_scalar(Acc, Rest);
        {line, Line, NextRest} ->
            State = {Acc, BlankCount},
            case is_empty_line(Line) of
                true -> collect_plain_scalar_empty(Line, Bin, NextRest, MinIndent, State);
                false -> collect_plain_scalar_content(Line, Bin, NextRest, MinIndent, State)
            end
    end.

-spec collect_plain_scalar_empty(
    binary(), binary(), binary(), non_neg_integer(), {binary(), non_neg_integer()}
) ->
    {ok, nyaml_parser:yaml_value(), binary()} | {error, nyaml_parser:parse_error()}.
collect_plain_scalar_empty(Line, Bin, NextRest, MinIndent, {Acc, BlankCount}) ->
    case is_comment_only_line(Line) of
        true ->
            case has_plain_continuation_after(NextRest, MinIndent) of
                true -> {error, plain_scalar_continuation_after_comment};
                false -> finish_plain_scalar(Acc, Bin)
            end;
        false ->
            collect_plain_scalar_continuation(NextRest, MinIndent, Acc, BlankCount + 1)
    end.
-doc """
Collects a multi-line plain scalar starting from `Initial`, folding continuation lines indented beyond `MinIndent` into a single parsed value.
""".
-spec collect_plain_scalar_lines(binary(), binary(), non_neg_integer()) ->
    {ok, nyaml:yaml_value(), binary()} | {error, nyaml_parser:parse_error()}.
collect_plain_scalar_lines(Initial, Rest, MinIndent) ->
    collect_plain_scalar_continuation(Rest, MinIndent, strip_whitespace(Initial), 0).

-spec collect_scalar_continuation(binary(), non_neg_integer(), binary()) ->
    {binary(), binary()} | {error, tab_in_indentation}.
collect_scalar_continuation(RestBin, Indent, Acc) ->
    case next_line(RestBin) of
        {no_more_lines, Rest} ->
            {fold_scalar(Acc), Rest};
        {line, NextLine, NextRest} ->
            case is_empty_line(NextLine) of
                true ->
                    case peek_next_content_indent(NextRest, Indent) of
                        continue ->
                            collect_scalar_continuation(NextRest, Indent, <<Acc/binary, "\n">>);
                        stop ->
                            {fold_scalar(Acc), RestBin}
                    end;
                false ->
                    collect_scalar_continuation_content(NextLine, RestBin, NextRest, Indent, Acc)
            end
    end.

-spec collect_scalar_continuation_content(
    binary(), binary(), binary(), non_neg_integer(), binary()
) ->
    {binary(), binary()} | {error, tab_in_indentation}.
collect_scalar_continuation_content(NextLine, RestBin, NextRest, Indent, Acc) ->
    case get_indent_and_line(NextLine) of
        {error, _} = Err ->
            Err;
        {ok, NextIndent, _} when NextIndent < Indent ->
            {fold_scalar(Acc), RestBin};
        {ok, _, NextContent} ->
            TrimmedNext = strip_comment(strip_whitespace(NextContent)),
            case has_mapping_indicator(TrimmedNext) orelse is_block_indicator(TrimmedNext) of
                true ->
                    {fold_scalar(Acc), RestBin};
                false ->
                    NewAcc = <<Acc/binary, " ", TrimmedNext/binary>>,
                    collect_scalar_continuation(NextRest, Indent, NewAcc)
            end
    end.
-doc """
Collects and folds a multi-line plain scalar from `CurrentLine` onward at the given indentation into a single binary.
""".
-spec collect_scalar_lines(binary(), binary(), non_neg_integer(), binary()) ->
    {binary(), binary()} | {error, nyaml_parser:parse_error()}.
collect_scalar_lines(CurrentLine, RestBin, Indent, Acc) ->
    case get_indent_and_line(CurrentLine) of
        {error, _} = Err ->
            Err;
        {ok, _LineIndent, LineContent} ->
            TrimmedContent = strip_comment(strip_whitespace(LineContent)),
            NewAcc =
                case Acc of
                    <<>> -> TrimmedContent;
                    _ -> <<Acc/binary, " ", TrimmedContent/binary>>
                end,
            collect_scalar_continuation(RestBin, Indent, NewAcc)
    end.

-spec count_flow_indent(binary(), non_neg_integer()) -> {non_neg_integer(), binary()}.
count_flow_indent(<<$\s, Rest/binary>>, Count) ->
    count_flow_indent(Rest, Count + 1);
count_flow_indent(Bin, Count) ->
    {Count, Bin}.

-spec count_leading_spaces(binary(), non_neg_integer()) ->
    {ok, non_neg_integer(), binary()} | {error, tab_in_indentation}.
count_leading_spaces(<<C, Rest/binary>>, Count) when C =:= $\s ->
    count_leading_spaces(Rest, Count + 1);
count_leading_spaces(<<$\t, _/binary>>, 0) ->
    {error, tab_in_indentation};
count_leading_spaces(Content, Count) ->
    {ok, Count, Content}.

-doc """
Counts the leading spaces and tabs at the start of the binary.
""".
-spec count_leading_ws(binary()) -> non_neg_integer().
count_leading_ws(<<$\s, Rest/binary>>) ->
    1 + count_leading_ws(Rest);
count_leading_ws(<<$\t, Rest/binary>>) ->
    1 + count_leading_ws(Rest);
count_leading_ws(_) ->
    0.
-spec extend_plain_scalar_acc(binary(), binary(), non_neg_integer()) -> binary().
extend_plain_scalar_acc(Acc, TrimmedContent, BlankCount) when BlankCount > 0 ->
    Breaks = list_to_binary(lists:duplicate(BlankCount, $\n)),
    <<Acc/binary, Breaks/binary, TrimmedContent/binary>>;
extend_plain_scalar_acc(Acc, TrimmedContent, _BlankCount) ->
    <<Acc/binary, " ", TrimmedContent/binary>>.

-doc """
Returns the byte offset where an unquoted `#` comment begins, or the line length when there is none.
""".
-spec find_comment_start(binary()) -> non_neg_integer().
find_comment_start(Line) ->
    find_comment_start(Line, 0, false).

-spec find_comment_start(binary(), non_neg_integer(), false | double | single) ->
    non_neg_integer().
find_comment_start(Line, Offset, _InQuote) when Offset >= byte_size(Line) ->
    byte_size(Line);
find_comment_start(Line, Offset, false) ->
    case binary:at(Line, Offset) of
        $" ->
            find_comment_start(Line, Offset + 1, double);
        $' ->
            find_comment_start(Line, Offset + 1, single);
        $# when Offset > 0 ->
            PrevChar = binary:at(Line, Offset - 1),
            case PrevChar =:= $\s orelse PrevChar =:= $\t of
                true -> Offset;
                false -> find_comment_start(Line, Offset + 1, false)
            end;
        $# ->
            Offset;
        _ ->
            find_comment_start(Line, Offset + 1, false)
    end;
find_comment_start(Line, Offset, double) ->
    case binary:at(Line, Offset) of
        $\\ when Offset + 1 < byte_size(Line) ->
            find_comment_start(Line, Offset + 2, double);
        $" ->
            find_comment_start(Line, Offset + 1, false);
        _ ->
            find_comment_start(Line, Offset + 1, double)
    end;
find_comment_start(Line, Offset, single) ->
    case binary:at(Line, Offset) of
        $' ->
            case Offset + 1 < byte_size(Line) andalso binary:at(Line, Offset + 1) =:= $' of
                true -> find_comment_start(Line, Offset + 2, single);
                false -> find_comment_start(Line, Offset + 1, false)
            end;
        _ ->
            find_comment_start(Line, Offset + 1, single)
    end.
-spec finish_plain_scalar(binary(), binary()) ->
    {ok, nyaml_parser:yaml_value(), binary()} | {error, nyaml_parser:parse_error()}.
finish_plain_scalar(Acc, Rest) ->
    case fold_plain_scalar_result(Acc) of
        {ok, Value} -> {ok, Value, Rest};
        {error, _} = Err -> Err
    end.

-doc """
Reports whether an open flow collection continues past the current line given the current bracket depth.
""".
-spec flow_spans_lines(binary(), integer()) -> boolean().
flow_spans_lines(<<>>, Depth) ->
    Depth > 0;
flow_spans_lines(<<"\n", _/binary>>, Depth) ->
    Depth > 0;
flow_spans_lines(<<"\r\n", _/binary>>, Depth) ->
    Depth > 0;
flow_spans_lines(<<"[", Rest/binary>>, Depth) ->
    flow_spans_lines(Rest, Depth + 1);
flow_spans_lines(<<"{", Rest/binary>>, Depth) ->
    flow_spans_lines(Rest, Depth + 1);
flow_spans_lines(<<"]", Rest/binary>>, Depth) ->
    flow_spans_lines(Rest, Depth - 1);
flow_spans_lines(<<"}", Rest/binary>>, Depth) ->
    flow_spans_lines(Rest, Depth - 1);
flow_spans_lines(<<"\"", Rest/binary>>, Depth) ->
    skip_quoted_for_flow_check(Rest, $", Depth);
flow_spans_lines(<<"'", Rest/binary>>, Depth) ->
    skip_quoted_for_flow_check(Rest, $', Depth);
flow_spans_lines(<<_, Rest/binary>>, Depth) ->
    flow_spans_lines(Rest, Depth).
-spec fold_plain_scalar_result(binary()) ->
    {ok, nyaml_parser:yaml_value()} | {error, nyaml_parser:parse_error()}.
fold_plain_scalar_result(Bin) ->
    Trimmed = strip_whitespace(Bin),
    parse_scalar(Trimmed).

-doc """
Folds a collected multi-line scalar, normalizing whitespace runs on each line while preserving line breaks.
""".
-spec fold_scalar(binary()) -> binary().
fold_scalar(Bin) ->
    Parts = binary:split(Bin, <<"\n">>, [global]),
    Folded = lists:map(fun normalize_spaces/1, Parts),
    iolist_to_binary(lists:join(<<"\n">>, Folded)).

-doc """
Returns the first line of the binary, without its trailing newline.
""".
-spec get_first_line(binary()) -> binary().
get_first_line(Bin) ->
    case binary:match(Bin, <<"\n">>) of
        nomatch -> Bin;
        {Pos, _} -> binary:part(Bin, 0, Pos)
    end.

-doc """
Splits a line into its leading-space indentation count and remaining content, rejecting tab indentation.
""".
-spec get_indent_and_line(binary()) ->
    {ok, non_neg_integer(), binary()} | {error, tab_in_indentation}.
get_indent_and_line(Line) ->
    case count_leading_spaces(Line, 0) of
        {ok, Indent, Content} -> {ok, Indent, Content};
        {error, _} = Err -> Err
    end.

-spec has_colon_followed_by_whitespace(binary()) -> boolean().
has_colon_followed_by_whitespace(<<>>) ->
    false;
has_colon_followed_by_whitespace(<<":">>) ->
    true;
has_colon_followed_by_whitespace(<<":", C, _/binary>>) when C =:= $\s; C =:= $\t ->
    true;
has_colon_followed_by_whitespace(<<_, Rest/binary>>) ->
    has_colon_followed_by_whitespace(Rest).
-doc """
Reports whether the line contains a whitespace-preceded `#` comment.
""".
-spec has_comment(binary()) -> boolean().
has_comment(<<>>) -> false;
has_comment(<<" #", _/binary>>) -> true;
has_comment(<<"\t#", _/binary>>) -> true;
has_comment(<<_, Rest/binary>>) -> has_comment(Rest).

-doc """
Reports whether the line is a mapping entry whose key is a flow collection.
""".
-spec has_flow_collection_key(binary()) -> boolean().
has_flow_collection_key(<<C, _/binary>> = Line) when C =:= $[; C =:= ${ ->
    Close =
        case C of
            $[ -> $];
            ${ -> $}
        end,
    case skip_flow_collection(Line, 1, Close, 1) of
        {ok, Offset} ->
            After = binary:part(Line, Offset, byte_size(Line) - Offset),
            starts_with_mapping_indicator(strip_whitespace(After));
        error ->
            false
    end;
has_flow_collection_key(_Line) ->
    false.

-spec starts_with_mapping_indicator(binary()) -> boolean().
starts_with_mapping_indicator(<<":">>) ->
    true;
starts_with_mapping_indicator(<<":", C, _/binary>>) when C =:= $\s; C =:= $\t ->
    true;
starts_with_mapping_indicator(_) ->
    false.

-doc """
Reports whether the line carries a mapping indicator, either `? ` or a `:` followed by whitespace.
""".
-spec has_mapping_indicator(binary()) -> boolean().
has_mapping_indicator(Line) ->
    case Line of
        <<"?", C, _/binary>> when C =:= $\s; C =:= $\t -> true;
        <<"?">> -> true;
        _ -> has_colon_followed_by_whitespace(Line)
    end.

-doc """
Reports whether a mapping indicator follows an anchor name at the start of the binary.
""".
-spec has_mapping_indicator_after_anchor(binary()) -> boolean().
has_mapping_indicator_after_anchor(Bin) ->
    case parse_anchor_name(Bin) of
        {ok, _, Rest} ->
            has_mapping_indicator(strip_whitespace(Rest));
        {error, _} ->
            false
    end.

-spec has_more_content(binary(), non_neg_integer()) -> boolean().
has_more_content(Bin, MinIndent) ->
    case next_line(Bin) of
        {no_more_lines, _} ->
            false;
        {line, Line, Rest} ->
            case is_empty_line(Line) of
                true ->
                    has_more_content(Rest, MinIndent);
                false ->
                    case get_indent_and_line(Line) of
                        {error, _} ->
                            false;
                        {ok, Indent, Content} ->
                            case strip_whitespace(Content) of
                                <<"#", _/binary>> -> has_more_content(Rest, MinIndent);
                                <<>> -> has_more_content(Rest, MinIndent);
                                _ -> Indent >= MinIndent
                            end
                    end
            end
    end.

-spec has_plain_continuation_after(binary(), non_neg_integer()) -> boolean().
has_plain_continuation_after(Bin, MinIndent) ->
    case next_line(Bin) of
        {no_more_lines, _} ->
            false;
        {line, Line, Rest} ->
            Trimmed = strip_whitespace(Line),
            case Trimmed of
                <<>> ->
                    has_plain_continuation_after(Rest, MinIndent);
                <<"#", _/binary>> ->
                    has_plain_continuation_after(Rest, MinIndent);
                _ ->
                    case get_indent_and_line(Line) of
                        {error, _} ->
                            false;
                        {ok, Indent, Content} ->
                            case
                                has_mapping_indicator(Content) orelse is_block_indicator(Content)
                            of
                                true ->
                                    false;
                                false ->
                                    Indent >= MinIndent
                            end
                    end
            end
    end.

-doc """
Reports whether the content starts with a block sequence (`- `) or explicit-key (`? `) indicator.
""".
-spec is_block_indicator(binary()) -> boolean().
is_block_indicator(<<"-", C, _/binary>>) when C =:= $\s; C =:= $\t -> true;
is_block_indicator(<<"-">>) -> true;
is_block_indicator(<<"?", C, _/binary>>) when C =:= $\s; C =:= $\t -> true;
is_block_indicator(<<"?">>) -> true;
is_block_indicator(_) -> false.

-doc """
Reports whether the line holds only a comment once leading whitespace is stripped.
""".
-spec is_comment_only_line(binary()) -> boolean().
is_comment_only_line(Line) ->
    case strip_whitespace(Line) of
        <<"#", _/binary>> -> true;
        _ -> false
    end.

-doc """
Reports whether the line is blank or comment-only.
""".
-spec is_empty_line(binary()) -> boolean().
is_empty_line(Line) ->
    case strip_whitespace(Line) of
        <<>> -> true;
        <<"#", _/binary>> -> true;
        _ -> false
    end.

-doc """
Reports whether the next line continues a plain scalar at or beyond `MinIndent`.
""".
-spec is_multiline_plain_scalar(binary(), non_neg_integer()) -> boolean().
is_multiline_plain_scalar(Bin, MinIndent) ->
    case next_line(Bin) of
        {no_more_lines, _} ->
            false;
        {line, Line, _Rest} ->
            case is_empty_line(Line) of
                true ->
                    true;
                false ->
                    case get_indent_and_line(Line) of
                        {error, _} -> false;
                        {ok, Indent, _Content} -> Indent >= MinIndent
                    end
            end
    end.

-doc """
Reports whether a plain, unquoted, non-indicator scalar embeds a `: ` mapping indicator.
""".
-spec is_plain_scalar_with_mapping_indicator(binary()) -> boolean().
is_plain_scalar_with_mapping_indicator(<<>>) ->
    false;
is_plain_scalar_with_mapping_indicator(<<"[", _/binary>>) ->
    false;
is_plain_scalar_with_mapping_indicator(<<"{", _/binary>>) ->
    false;
is_plain_scalar_with_mapping_indicator(<<"\"", _/binary>>) ->
    false;
is_plain_scalar_with_mapping_indicator(<<"'", _/binary>>) ->
    false;
is_plain_scalar_with_mapping_indicator(<<"|", _/binary>>) ->
    false;
is_plain_scalar_with_mapping_indicator(<<">", _/binary>>) ->
    false;
is_plain_scalar_with_mapping_indicator(<<"-", C, _/binary>>) when C =:= $\s; C =:= $\t ->
    false;
is_plain_scalar_with_mapping_indicator(<<"*", _/binary>>) ->
    false;
is_plain_scalar_with_mapping_indicator(<<"&", _/binary>>) ->
    false;
is_plain_scalar_with_mapping_indicator(<<"!", _/binary>>) ->
    false;
is_plain_scalar_with_mapping_indicator(Bin) ->
    case binary:match(Bin, <<": ">>) of
        {_, _} ->
            true;
        nomatch ->
            case binary:match(Bin, <<":\t">>) of
                {_, _} -> true;
                nomatch -> false
            end
    end.

-doc """
Reports whether a quoted scalar of the given quote type is immediately followed by a `:` mapping separator.
""".
-spec is_quoted_mapping_key(binary(), nyaml_scalar:quote_type()) -> boolean().
is_quoted_mapping_key(Bin, QuoteType) ->
    case nyaml_scalar:parse_quoted(Bin, QuoteType, block_level) of
        {ok, _Value, Rest} ->
            TrimmedRest = strip_whitespace(Rest),
            case TrimmedRest of
                <<":", _/binary>> -> true;
                _ -> false
            end;
        {error, _} ->
            false
    end.

-doc """
Builds a binary of `N` space characters.
""".
-spec make_indent(non_neg_integer()) -> binary().
make_indent(N) ->
    list_to_binary(lists:duplicate(N, $\s)).

-doc """
Splits off the next line, returning `{line, Line, Rest}` or `{no_more_lines, Rest}` at end of input.
""".
-spec next_line(binary()) -> {line, binary(), binary()} | {no_more_lines, binary()}.
next_line(<<>>) ->
    {no_more_lines, <<>>};
next_line(Bin) ->
    case binary:match(Bin, <<"\n">>) of
        nomatch ->
            {line, Bin, <<>>};
        {Pos, 1} ->
            Line = binary:part(Bin, {0, Pos}),
            Rest = binary:part(Bin, {Pos + 1, byte_size(Bin) - (Pos + 1)}),
            {line, Line, Rest}
    end.

-doc """
Returns the next line that is neither blank nor comment-only, skipping empty lines.
""".
-spec next_non_empty_line(binary()) -> {line, binary(), binary()} | {no_more_lines, binary()}.
next_non_empty_line(Bin) ->
    case next_line(Bin) of
        {no_more_lines, Rest} ->
            {no_more_lines, Rest};
        {line, Line, Rest} ->
            case is_empty_line(Line) of
                true -> next_non_empty_line(Rest);
                false -> {line, Line, Rest}
            end
    end.

-spec normalize_spaces(binary()) -> binary().
normalize_spaces(Bin) ->
    Trimmed = strip_whitespace(Bin),
    normalize_spaces_inner(Trimmed, <<>>, false).

-spec normalize_spaces_inner(binary(), binary(), boolean()) -> binary().
normalize_spaces_inner(<<>>, Acc, _PrevSpace) ->
    Acc;
normalize_spaces_inner(<<C, Rest/binary>>, Acc, _PrevSpace) when C =:= $\s; C =:= $\t ->
    normalize_spaces_inner(Rest, Acc, true);
normalize_spaces_inner(<<C, Rest/binary>>, Acc, true) ->
    normalize_spaces_inner(Rest, <<Acc/binary, $\s, C>>, false);
normalize_spaces_inner(<<C, Rest/binary>>, Acc, false) ->
    normalize_spaces_inner(Rest, <<Acc/binary, C>>, false).

-doc """
Parses an anchor or alias name up to the first flow or whitespace delimiter, returning the name and remaining input.
""".
-spec parse_anchor_name(binary()) -> {ok, binary(), binary()} | {error, nyaml_parser:parse_error()}.
parse_anchor_name(Bin) ->
    parse_anchor_name(Bin, <<>>).

-spec parse_anchor_name(binary(), binary()) ->
    {ok, binary(), binary()} | {error, {invalid_anchor_name, binary()}}.
parse_anchor_name(<<C, Rest/binary>>, Acc) when
    C =/= $\s,
    C =/= $\t,
    C =/= $\n,
    C =/= $\r,
    C =/= $,,
    C =/= $[,
    C =/= $],
    C =/= ${,
    C =/= $}
->
    parse_anchor_name(Rest, <<Acc/binary, C>>);
parse_anchor_name(Rest, <<>>) ->
    {error, {invalid_anchor_name, Rest}};
parse_anchor_name(Rest, Acc) ->
    {ok, Acc, Rest}.

-doc """
Parses a trimmed plain or quoted scalar binary into its typed value, falling back to the raw binary.
""".
-spec parse_scalar(binary()) -> {ok, nyaml:yaml_value()} | {error, nyaml_parser:parse_error()}.
parse_scalar(Bin) ->
    TrimmedBin = strip_whitespace(Bin),
    case TrimmedBin of
        <<>> ->
            {ok, null};
        <<"\"", _/binary>> ->
            case nyaml_scalar:parse_quoted(TrimmedBin, double, block_level) of
                {ok, Value, _Rest} -> {ok, Value};
                {error, _} -> {ok, TrimmedBin}
            end;
        <<"'", _/binary>> ->
            case nyaml_scalar:parse_quoted(TrimmedBin, single, block_level) of
                {ok, Value, _Rest} -> {ok, Value};
                {error, _} -> {ok, TrimmedBin}
            end;
        <<"null">> ->
            {ok, null};
        <<"true">> ->
            {ok, true};
        <<"false">> ->
            {ok, false};
        <<C, _/binary>> when C =:= $,; C =:= $[; C =:= $]; C =:= ${; C =:= $} ->
            {error, {invalid_plain_scalar_start, C}};
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
Parses a tag shorthand name from the binary, returning the name and remaining input.
""".
-spec parse_tag_name(binary()) -> {ok, binary(), binary()} | {error, nyaml_parser:parse_error()}.
parse_tag_name(Bin) ->
    parse_tag_name(Bin, <<>>).

-spec parse_tag_name(binary(), binary()) ->
    {ok, binary(), binary()} | {error, {invalid_tag_name, binary()}}.
parse_tag_name(<<C, Rest/binary>>, Acc) when
    (C >= $a andalso C =< $z) orelse
        (C >= $A andalso C =< $Z) orelse
        (C >= $0 andalso C =< $9) orelse
        C =:= $- orelse C =:= $_
->
    parse_tag_name(Rest, <<Acc/binary, C>>);
parse_tag_name(Rest, <<>>) ->
    {error, {invalid_tag_name, Rest}};
parse_tag_name(Rest, Acc) ->
    {ok, Acc, Rest}.

-spec peek_next_content_indent(binary(), non_neg_integer()) -> continue | stop.
peek_next_content_indent(Bin, MinIndent) ->
    case next_line(Bin) of
        {no_more_lines, _} ->
            stop;
        {line, Line, Rest} ->
            case is_empty_line(Line) of
                true ->
                    peek_next_content_indent(Rest, MinIndent);
                false ->
                    case get_indent_and_line(Line) of
                        {error, _} ->
                            stop;
                        {ok, LineIndent, _Content} ->
                            case LineIndent >= MinIndent of
                                true -> continue;
                                false -> stop
                            end
                    end
            end
    end.

-doc """
Returns the byte length of a leading `&anchor` or `*alias` prefix, or `0` when none is present.
""".
-spec skip_anchor_or_alias_prefix(binary()) -> non_neg_integer().
skip_anchor_or_alias_prefix(<<"&", Rest/binary>>) ->
    case parse_anchor_name(Rest) of
        {ok, _Name, ValuePart} ->
            byte_size(<<"&", Rest/binary>>) - byte_size(ValuePart);
        {error, _} ->
            0
    end;
skip_anchor_or_alias_prefix(<<"*", Rest/binary>>) ->
    case parse_anchor_name(Rest) of
        {ok, _Name, ValuePart} ->
            byte_size(<<"*", Rest/binary>>) - byte_size(ValuePart);
        {error, _} ->
            0
    end;
skip_anchor_or_alias_prefix(_) ->
    0.

-doc """
Scans past a double-quoted string from `Offset`, returning the offset just after the closing quote.
""".
-spec skip_double_quoted(binary(), non_neg_integer()) -> {ok, non_neg_integer()} | error.
skip_double_quoted(Line, Offset) when Offset >= byte_size(Line) ->
    error;
skip_double_quoted(Line, Offset) ->
    case binary:at(Line, Offset) of
        $\\ ->
            skip_double_quoted(Line, Offset + 2);
        $" ->
            {ok, Offset + 1};
        _ ->
            skip_double_quoted(Line, Offset + 1)
    end.

-doc """
Drops leading blank and comment-only lines, returning the input at the first content line.
""".
-spec skip_empty_lines(binary()) -> binary().
skip_empty_lines(Bin) ->
    case next_line(Bin) of
        {no_more_lines, Rest} ->
            Rest;
        {line, Line, Rest} ->
            case is_empty_line(Line) of
                true -> skip_empty_lines(Rest);
                false -> Bin
            end
    end.

-doc """
Scans past a balanced flow collection from `Offset`, tracking nesting `Depth` until the matching close.
""".
-spec skip_flow_collection(binary(), non_neg_integer(), byte(), integer()) ->
    {ok, non_neg_integer()} | error.
skip_flow_collection(_Line, Offset, _CloseChar, 0) ->
    {ok, Offset};
skip_flow_collection(Line, Offset, _CloseChar, _Depth) when Offset >= byte_size(Line) ->
    error;
skip_flow_collection(Line, Offset, CloseChar, Depth) ->
    case binary:at(Line, Offset) of
        C when C =:= CloseChar ->
            skip_flow_collection(Line, Offset + 1, CloseChar, Depth - 1);
        $[ ->
            skip_flow_collection(Line, Offset + 1, CloseChar, Depth + 1);
        ${ ->
            skip_flow_collection(Line, Offset + 1, CloseChar, Depth + 1);
        $] ->
            skip_flow_collection(Line, Offset + 1, CloseChar, Depth - 1);
        $} ->
            skip_flow_collection(Line, Offset + 1, CloseChar, Depth - 1);
        $" ->
            case skip_double_quoted(Line, Offset + 1) of
                {ok, EndOffset} -> skip_flow_collection(Line, EndOffset, CloseChar, Depth);
                error -> error
            end;
        $' ->
            case skip_single_quoted(Line, Offset + 1) of
                {ok, EndOffset} -> skip_flow_collection(Line, EndOffset, CloseChar, Depth);
                error -> error
            end;
        _ ->
            skip_flow_collection(Line, Offset + 1, CloseChar, Depth)
    end.

-doc """
Skips a local or named tag shorthand, returning the input positioned after the tag.
""".
-spec skip_local_or_named_tag(binary()) -> {ok, binary()} | {error, nyaml_parser:parse_error()}.
skip_local_or_named_tag(Bin) ->
    skip_tag_chars(Bin).
-spec skip_quoted_for_flow_check(binary(), byte(), integer()) -> boolean().
skip_quoted_for_flow_check(<<$\\, _, Rest/binary>>, QuoteChar, Depth) ->
    skip_quoted_for_flow_check(Rest, QuoteChar, Depth);
skip_quoted_for_flow_check(<<C, Rest/binary>>, C, Depth) ->
    flow_spans_lines(Rest, Depth);
skip_quoted_for_flow_check(<<_, Rest/binary>>, QuoteChar, Depth) ->
    skip_quoted_for_flow_check(Rest, QuoteChar, Depth);
skip_quoted_for_flow_check(<<>>, _QuoteChar, _Depth) ->
    true.

-spec skip_quoted_string(binary(), byte(), non_neg_integer(), integer()) ->
    ok | {error, flow_content_wrong_indentation}.
skip_quoted_string(<<$\\, _, Rest/binary>>, QuoteChar, MinIndent, Depth) ->
    skip_quoted_string(Rest, QuoteChar, MinIndent, Depth);
skip_quoted_string(<<C, Rest/binary>>, C, MinIndent, Depth) ->
    validate_flow_continuation_indent(Rest, MinIndent, Depth);
skip_quoted_string(<<_, Rest/binary>>, QuoteChar, MinIndent, Depth) ->
    skip_quoted_string(Rest, QuoteChar, MinIndent, Depth);
skip_quoted_string(<<>>, _QuoteChar, _MinIndent, _Depth) ->
    ok.
-doc """
Scans past a single-quoted string from `Offset`, honoring `''` escapes, to the offset after the closing quote.
""".
-spec skip_single_quoted(binary(), non_neg_integer()) -> {ok, non_neg_integer()} | error.
skip_single_quoted(Line, Offset) when Offset >= byte_size(Line) ->
    error;
skip_single_quoted(Line, Offset) ->
    case binary:at(Line, Offset) of
        $' ->
            case Offset + 1 < byte_size(Line) andalso binary:at(Line, Offset + 1) =:= $' of
                true -> skip_single_quoted(Line, Offset + 2);
                false -> {ok, Offset + 1}
            end;
        _ ->
            skip_single_quoted(Line, Offset + 1)
    end.

-doc """
Skips tag characters up to a delimiter, rejecting `[` and `{` inside the tag.
""".
-spec skip_tag_chars(binary()) -> {ok, binary()} | {error, {invalid_tag_character, byte()}}.
skip_tag_chars(<<C, Rest/binary>>) when
    C =:= $\s; C =:= $\t; C =:= $\n; C =:= $\r
->
    {ok, <<C, Rest/binary>>};
skip_tag_chars(<<C, Rest/binary>>) when
    C =:= $,; C =:= $]; C =:= $}; C =:= $:
->
    {ok, <<C, Rest/binary>>};
skip_tag_chars(<<C, _Rest/binary>>) when
    C =:= $[; C =:= ${
->
    {error, {invalid_tag_character, C}};
skip_tag_chars(<<_, Rest/binary>>) ->
    skip_tag_chars(Rest);
skip_tag_chars(<<>>) ->
    {ok, <<>>}.

-doc """
Returns the input following the next newline.
""".
-spec skip_to_next_line(binary()) -> binary().
skip_to_next_line(<<"\n", Rest/binary>>) ->
    Rest;
skip_to_next_line(<<"\r\n", Rest/binary>>) ->
    Rest;
skip_to_next_line(<<_, Rest/binary>>) ->
    skip_to_next_line(Rest);
skip_to_next_line(<<>>) ->
    <<>>.

-doc """
Skips a verbatim `!<...>` tag, returning the input after the closing `>`.
""".
-spec skip_verbatim_tag(binary()) -> {ok, binary()} | {error, unterminated_verbatim_tag}.
skip_verbatim_tag(Bin) ->
    skip_verbatim_tag(Bin, <<>>).

-spec skip_verbatim_tag(binary(), binary()) ->
    {ok, binary()} | {error, unterminated_verbatim_tag}.
skip_verbatim_tag(<<">", Rest/binary>>, _Acc) ->
    {ok, Rest};
skip_verbatim_tag(<<C, Rest/binary>>, Acc) when C =/= $> ->
    skip_verbatim_tag(Rest, <<Acc/binary, C>>);
skip_verbatim_tag(<<>>, _Acc) ->
    {error, unterminated_verbatim_tag}.

-doc """
Reports whether the next content line at or beyond `MinIndent` begins with an anchor introducing a scalar.
""".
-spec starts_with_scalar_anchor(binary(), non_neg_integer()) -> boolean().
starts_with_scalar_anchor(Bin, MinIndent) ->
    case next_non_empty_line(Bin) of
        {no_more_lines, _} ->
            false;
        {line, Line, _Rest} ->
            case get_indent_and_line(Line) of
                {error, _} ->
                    false;
                {ok, Indent, Content} when Indent >= MinIndent ->
                    case Content of
                        <<"&", Rest/binary>> ->
                            not has_mapping_indicator_after_anchor(Rest);
                        _ ->
                            false
                    end;
                {ok, _, _} ->
                    false
            end
    end.

-doc """
Removes a trailing `#` comment from the line while respecting quoted spans.
""".
-spec strip_comment(binary()) -> binary().
strip_comment(Bin) ->
    strip_comment(Bin, <<>>, false).

-spec strip_comment(binary(), binary(), false | double | single) -> binary().
strip_comment(<<>>, Acc, _InQuote) ->
    strip_trailing_ws(Acc);
strip_comment(<<" #", _/binary>>, Acc, false) ->
    strip_trailing_ws(Acc);
strip_comment(<<"\t#", _/binary>>, Acc, false) ->
    strip_trailing_ws(Acc);
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

-doc """
Removes trailing whitespace from the binary.
""".
-spec strip_trailing_ws(binary()) -> binary().
strip_trailing_ws(Bin) ->
    iolist_to_binary(re:replace(Bin, "\\s+$", "", [{return, binary}])).

-doc """
Removes leading and trailing whitespace from the binary.
""".
-spec strip_whitespace(binary()) -> binary().
strip_whitespace(Bin) ->
    iolist_to_binary(re:replace(Bin, "^\\s+|\\s+$", "", [{return, binary}, global])).

-doc """
Reports whether a tab separates a block indicator from a nested block collection.

`Separator` is the white space character that follows the `-`, `?` or `:`
indicator and `AfterSeparator` is the rest of the line. A nested collection that
starts on the indicator's own line is reached through `s-indent(m)`, which is
spaces, so a tab leaves only a flow node as a legal continuation of the line.
""".
-spec tab_before_nested_block_entry(byte(), binary()) -> boolean().
tab_before_nested_block_entry(Separator, AfterSeparator) ->
    Content = strip_comment(strip_whitespace(AfterSeparator)),
    (Separator =:= $\t orelse leading_white_holds_tab(AfterSeparator)) andalso
        (is_block_indicator(Content) orelse has_mapping_indicator(Content)).

-spec leading_white_holds_tab(binary()) -> boolean().
leading_white_holds_tab(<<$\t, _/binary>>) -> true;
leading_white_holds_tab(<<$\s, Rest/binary>>) -> leading_white_holds_tab(Rest);
leading_white_holds_tab(_) -> false.

-doc """
Validates the line prefix of every flow-collection line that follows `Bin`.

`s-flow-line-prefix(n)` is `s-indent(n) s-separate-in-line?`, so a line that
carries content opens with `MinIndent` spaces. A tab before that count is
reached is not indentation. A line of white space is an `l-comment` line and
carries no prefix requirement.
""".
-spec validate_flow_continuation_indent(binary(), non_neg_integer()) ->
    ok | {error, flow_content_wrong_indentation | tab_in_indentation}.
validate_flow_continuation_indent(Bin, MinIndent) ->
    validate_flow_line_indent(Bin, MinIndent, 0).

-spec validate_flow_continuation_indent(binary(), non_neg_integer(), integer()) ->
    ok | {error, flow_content_wrong_indentation | tab_in_indentation}.
validate_flow_continuation_indent(<<>>, _MinIndent, _Depth) ->
    ok;
validate_flow_continuation_indent(_, _MinIndent, Depth) when Depth < 0 ->
    ok;
validate_flow_continuation_indent(<<"\n", Rest/binary>>, MinIndent, Depth) ->
    validate_flow_line_indent(Rest, MinIndent, Depth);
validate_flow_continuation_indent(<<"\r\n", Rest/binary>>, MinIndent, Depth) ->
    validate_flow_line_indent(Rest, MinIndent, Depth);
validate_flow_continuation_indent(<<"[", Rest/binary>>, MinIndent, Depth) ->
    validate_flow_continuation_indent(Rest, MinIndent, Depth + 1);
validate_flow_continuation_indent(<<"{", Rest/binary>>, MinIndent, Depth) ->
    validate_flow_continuation_indent(Rest, MinIndent, Depth + 1);
validate_flow_continuation_indent(<<"]", Rest/binary>>, MinIndent, Depth) ->
    validate_flow_continuation_indent(Rest, MinIndent, Depth - 1);
validate_flow_continuation_indent(<<"}", Rest/binary>>, MinIndent, Depth) ->
    validate_flow_continuation_indent(Rest, MinIndent, Depth - 1);
validate_flow_continuation_indent(<<"\"", Rest/binary>>, MinIndent, Depth) ->
    skip_quoted_string(Rest, $", MinIndent, Depth);
validate_flow_continuation_indent(<<"'", Rest/binary>>, MinIndent, Depth) ->
    skip_quoted_string(Rest, $', MinIndent, Depth);
validate_flow_continuation_indent(<<_, Rest/binary>>, MinIndent, Depth) ->
    validate_flow_continuation_indent(Rest, MinIndent, Depth).

-spec validate_flow_line_indent(binary(), non_neg_integer(), integer()) ->
    ok | {error, flow_content_wrong_indentation | tab_in_indentation}.
validate_flow_line_indent(Bin, MinIndent, Depth) ->
    case count_flow_indent(Bin, 0) of
        {Indent, Rest} when Indent < MinIndent ->
            validate_under_indented_flow_line(Rest, MinIndent, Depth);
        {_Indent, Rest} ->
            validate_flow_continuation_indent(Rest, MinIndent, Depth)
    end.

-spec validate_under_indented_flow_line(binary(), non_neg_integer(), integer()) ->
    ok | {error, flow_content_wrong_indentation | tab_in_indentation}.
validate_under_indented_flow_line(Bin, MinIndent, Depth) ->
    case skip_white(Bin) of
        <<>> -> ok;
        <<"]", _/binary>> -> ok;
        <<"}", _/binary>> -> ok;
        <<"\n", _/binary>> = Rest -> validate_flow_continuation_indent(Rest, MinIndent, Depth);
        <<"\r\n", _/binary>> = Rest -> validate_flow_continuation_indent(Rest, MinIndent, Depth);
        <<"#", _/binary>> = Rest -> validate_flow_continuation_indent(Rest, MinIndent, Depth);
        Bin -> {error, flow_content_wrong_indentation};
        _ -> {error, tab_in_indentation}
    end.

-spec skip_white(binary()) -> binary().
skip_white(<<C, Rest/binary>>) when C =:= $\s; C =:= $\t ->
    skip_white(Rest);
skip_white(Bin) ->
    Bin.

-doc """
Validates that only whitespace and an optional comment follow a value on its line.
""".
-spec validate_rest_of_line(binary()) -> ok | {error, nyaml_parser:parse_error()}.
validate_rest_of_line(Bin) ->
    validate_rest_of_line(Bin, false).

-spec validate_rest_of_line(binary(), boolean()) ->
    ok | {error, comment_without_whitespace | trailing_content_after_value}.
validate_rest_of_line(<<"\n", _/binary>>, _SeenWhitespace) ->
    ok;
validate_rest_of_line(<<"\r\n", _/binary>>, _SeenWhitespace) ->
    ok;
validate_rest_of_line(<<>>, _SeenWhitespace) ->
    ok;
validate_rest_of_line(<<C, Rest/binary>>, _SeenWhitespace) when C =:= $\s; C =:= $\t ->
    validate_rest_of_line(Rest, true);
validate_rest_of_line(<<"#", _/binary>>, true) ->
    ok;
validate_rest_of_line(<<"#", _/binary>>, false) ->
    {error, comment_without_whitespace};
validate_rest_of_line(_, _SeenWhitespace) ->
    {error, trailing_content_after_value}.
