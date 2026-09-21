-module(nyaml_parser_util).

-moduledoc """
Pure utility functions for top-level YAML parsing.

Binary navigation (line splitting, indentation counting), whitespace and
comment stripping, mapping/anchor/tag detection helpers, document-content
extraction, name parsers, scalar coercions, and plain-scalar collection
helpers.

These functions are stateless and have no dependency on `nyaml_parser`
state; they support the higher-level dispatch in `nyaml_parser`.
""".

-export([
    append_plain_scalar_continuation/5,
    block_starts_with_sequence_or_mapping/1,
    collect_plain_scalar/1,
    collect_plain_scalar_lines/4,
    count_leading_spaces_simple/1,
    count_leading_whitespace/1,
    detect_base_indent/1,
    ends_with_whitespace/1,
    extend_plain_scalar_lines_acc/3,
    extract_document_content/1,
    extract_document_content/3,
    extract_tag_handle/1,
    extract_tag_handle/2,
    get_first_line/1,
    has_continuation_content/1,
    has_directive_pattern/1,
    has_newline_before_content/1,
    has_same_line_content/1,
    has_same_line_mapping_indicator/1,
    has_same_line_mapping_indicator/2,
    is_anchor_in_mapping_key/1,
    is_empty_line/1,
    is_mapping_key_line/1,
    is_quoted_mapping_key/2,
    is_tagged_mapping_key/1,
    is_valid_document_marker/1,
    line_has_comment/1,
    line_has_comment/2,
    next_line/1,
    next_non_empty_line/1,
    parse_alias_name/1,
    parse_anchor_name/1,
    parse_directive_name/1,
    parse_name/2,
    parse_tag_handle_name/1,
    parse_tag_handle_name/2,
    parse_tag_name/1,
    parse_tag_name/2,
    parse_tag_prefix/1,
    parse_tag_prefix/2,
    parse_version_number/1,
    parse_version_number/2,
    parse_yaml_directive/1,
    parse_yaml_version/1,
    skip_empty_and_comment_lines/1,
    skip_empty_and_comment_lines/3,
    skip_leading_ws/1,
    skip_past_first_line/1,
    skip_same_line_quoted/2,
    skip_same_line_whitespace/1,
    skip_tag_chars/1,
    skip_to_content/1,
    skip_to_end_of_line/1,
    skip_to_eol/1,
    skip_to_newline_then_continue/1,
    skip_verbatim_tag/1,
    skip_verbatim_tag/2,
    skip_whitespace/1,
    skip_whitespace_inline/1,
    strip_trailing_whitespace/1,
    strip_trailing_ws/1,
    strip_whitespace/1,
    to_bool/2,
    to_float/1,
    to_int/1,
    validate_directive_end/1,
    validate_directive_end_after_space/1,
    validate_document_end_after_space/1,
    validate_document_end_line/1
]).

-doc """
Appends a plain-scalar continuation line to the accumulator, stopping with an error when content follows a comment.
""".
-spec append_plain_scalar_continuation(
    binary(), binary(), binary(), {binary(), non_neg_integer()}, non_neg_integer()
) ->
    {binary(), binary()} | {error, nyaml_parser:parse_error()}.
append_plain_scalar_continuation(CleanLine, Line, Bin, {Acc, EmptyCount}, BaseIndent) ->
    Rest = skip_past_first_line(Bin),
    case line_has_comment(Line) of
        true ->
            case has_continuation_content(Rest) of
                true ->
                    {error, content_after_comment};
                false ->
                    {extend_plain_scalar_lines_acc(Acc, CleanLine, EmptyCount), Rest}
            end;
        false ->
            NewAcc = extend_plain_scalar_lines_acc(Acc, CleanLine, EmptyCount),
            collect_plain_scalar_lines(Rest, NewAcc, 0, BaseIndent)
    end.

-doc """
Reports whether the first non-empty line opens a block sequence or mapping.
""".
-spec block_starts_with_sequence_or_mapping(binary()) -> boolean().
block_starts_with_sequence_or_mapping(Bin) ->
    case next_non_empty_line(Bin) of
        {no_more_lines, _} ->
            false;
        {line, Line, _} ->
            case strip_whitespace(Line) of
                <<"-", C, _/binary>> when C =:= $\s; C =:= $\t -> true;
                <<"-">> ->
                    true;
                <<"?", C, _/binary>> when C =:= $\s; C =:= $\t -> true;
                <<"?">> ->
                    true;
                Content ->
                    case binary:match(Content, <<":">>) of
                        nomatch -> false;
                        _ -> true
                    end
            end
    end.

-doc """
Collects a multi-line plain scalar from the input, folding continuation lines and returning the text and remaining input.
""".
-spec collect_plain_scalar(binary()) ->
    {binary(), binary()} | {error, nyaml_parser:parse_error()}.
collect_plain_scalar(Bin) ->
    FirstLine = get_first_line(Bin),
    BaseIndent = count_leading_spaces_simple(Bin),
    CleanLine = nyaml_parser:strip_comment(
        strip_trailing_whitespace(strip_whitespace(FirstLine))
    ),
    RestAfterFirst = skip_past_first_line(Bin),
    HasComment = line_has_comment(FirstLine),
    case HasComment of
        true ->
            case has_continuation_content(RestAfterFirst) of
                true -> {error, content_after_comment};
                false -> {CleanLine, RestAfterFirst}
            end;
        false ->
            collect_plain_scalar_lines(RestAfterFirst, CleanLine, 0, BaseIndent)
    end.

-doc """
Folds successive plain-scalar continuation lines into the accumulator until the scalar ends, tracking blank-line count and base indent.
""".
-spec collect_plain_scalar_lines(binary(), binary(), non_neg_integer(), non_neg_integer()) ->
    {binary(), binary()} | {error, nyaml_parser:parse_error()}.
collect_plain_scalar_lines(<<>>, Acc, _EmptyCount, _BaseIndent) ->
    {Acc, <<>>};
collect_plain_scalar_lines(Bin, Acc, EmptyCount, BaseIndent) ->
    case get_first_line(Bin) of
        <<>> ->
            Rest = skip_past_first_line(Bin),
            collect_plain_scalar_lines(Rest, Acc, EmptyCount + 1, BaseIndent);
        Line ->
            LineIndent = count_leading_spaces_simple(Line),
            TrimmedLine = strip_whitespace(Line),
            CleanLine = nyaml_parser:strip_comment(strip_trailing_whitespace(TrimmedLine)),
            case CleanLine of
                <<>> ->
                    Rest = skip_past_first_line(Bin),
                    collect_plain_scalar_lines(Rest, Acc, EmptyCount + 1, BaseIndent);
                <<"-", C, _/binary>> when C =:= $\s; C =:= $\t ->
                    case LineIndent > BaseIndent of
                        true -> {error, {sequence_indicator_in_plain_scalar, Line}};
                        false -> {Acc, Bin}
                    end;
                <<"---", _/binary>> ->
                    {Acc, Bin};
                <<"...", _/binary>> ->
                    {Acc, Bin};
                _ ->
                    case is_mapping_key_line(CleanLine) of
                        true when LineIndent > BaseIndent ->
                            {error, {mapping_indicator_in_plain_scalar, Line}};
                        true ->
                            {Acc, Bin};
                        false ->
                            append_plain_scalar_continuation(
                                CleanLine, Line, Bin, {Acc, EmptyCount}, BaseIndent
                            )
                    end
            end
    end.

-doc """
Counts leading space characters at the start of the binary.
""".
-spec count_leading_spaces_simple(binary()) -> non_neg_integer().
count_leading_spaces_simple(<<$\s, Rest/binary>>) ->
    1 + count_leading_spaces_simple(Rest);
count_leading_spaces_simple(_) ->
    0.

-doc """
Counts leading indentation width, treating each tab as eight columns.
""".
-spec count_leading_whitespace(binary()) -> non_neg_integer().
count_leading_whitespace(<<C, Rest/binary>>) when C =:= $\s ->
    1 + count_leading_whitespace(Rest);
count_leading_whitespace(<<C, Rest/binary>>) when C =:= $\t ->
    8 + count_leading_whitespace(Rest);
count_leading_whitespace(_) ->
    0.

-doc """
Returns the indentation width of the first non-empty line.
""".
-spec detect_base_indent(binary()) -> non_neg_integer().
detect_base_indent(Bin) ->
    case next_non_empty_line(Bin) of
        {no_more_lines, _} ->
            0;
        {line, Line, _} ->
            count_leading_whitespace(Line)
    end.

-doc """
Reports whether the binary ends with a space or tab.
""".
-spec ends_with_whitespace(binary()) -> boolean().
ends_with_whitespace(<<>>) ->
    true;
ends_with_whitespace(Bin) ->
    C = binary:last(Bin),
    C =:= $\s orelse C =:= $\t.

-doc """
Appends a continuation line to a plain-scalar accumulator, inserting line breaks for any preceding blank lines.
""".
-spec extend_plain_scalar_lines_acc(binary(), binary(), non_neg_integer()) -> binary().
extend_plain_scalar_lines_acc(Acc, CleanLine, EmptyCount) when EmptyCount > 0 ->
    Newlines = list_to_binary(lists:duplicate(EmptyCount, $\n)),
    <<Acc/binary, Newlines/binary, CleanLine/binary>>;
extend_plain_scalar_lines_acc(Acc, CleanLine, _EmptyCount) ->
    <<Acc/binary, " ", CleanLine/binary>>.

-doc """
Extracts the current document's content up to the next `---` or `...` marker, returning it and the remaining input.
""".
-spec extract_document_content(binary()) -> {binary(), binary()}.
extract_document_content(Bin) ->
    extract_document_content(Bin, <<>>, false).

-doc """
Extracts document content into the accumulator while tracking quoted spans, stopping at a document boundary.
""".
-spec extract_document_content(binary(), binary(), boolean() | double | single) ->
    {binary(), binary()}.
extract_document_content(<<>>, Acc, _InQuote) ->
    {Acc, <<>>};
extract_document_content(<<"\n---", Rest/binary>>, Acc, false) ->
    {Acc, <<"---", Rest/binary>>};
extract_document_content(<<"\n...", Rest/binary>>, Acc, false) ->
    {Acc, <<"...", Rest/binary>>};
extract_document_content(<<"\"", Rest/binary>>, Acc, false) ->
    extract_document_content(Rest, <<Acc/binary, "\"">>, double);
extract_document_content(<<"\\\"", Rest/binary>>, Acc, double) ->
    extract_document_content(Rest, <<Acc/binary, "\\\"">>, double);
extract_document_content(<<"\"", Rest/binary>>, Acc, double) ->
    extract_document_content(Rest, <<Acc/binary, "\"">>, false);
extract_document_content(<<"'", Rest/binary>>, Acc, false) ->
    extract_document_content(Rest, <<Acc/binary, "'">>, single);
extract_document_content(<<"''", Rest/binary>>, Acc, single) ->
    extract_document_content(Rest, <<Acc/binary, "''">>, single);
extract_document_content(<<"'", Rest/binary>>, Acc, single) ->
    extract_document_content(Rest, <<Acc/binary, "'">>, false);
extract_document_content(<<C, Rest/binary>>, Acc, InQuote) ->
    extract_document_content(Rest, <<Acc/binary, C>>, InQuote).

-doc """
Splits a tag shorthand into its handle and suffix, yielding a named or local tag.
""".
-spec extract_tag_handle(binary()) -> {named_tag, binary(), binary()} | {local_tag, binary()}.
extract_tag_handle(Bin) ->
    extract_tag_handle(Bin, <<>>).

-doc """
Accumulates tag handle characters, returning a named tag at the closing `!` or a local tag otherwise.
""".
-spec extract_tag_handle(binary(), binary()) ->
    {named_tag, binary(), binary()} | {local_tag, binary()}.
extract_tag_handle(<<"!", Rest/binary>>, Acc) when Acc =/= <<>> ->
    {named_tag, <<Acc/binary, "!">>, Rest};
extract_tag_handle(<<C, Rest/binary>>, Acc) when
    (C >= $a andalso C =< $z) orelse
        (C >= $A andalso C =< $Z) orelse
        (C >= $0 andalso C =< $9) orelse
        C =:= $-
->
    extract_tag_handle(Rest, <<Acc/binary, C>>);
extract_tag_handle(Rest, _Acc) ->
    {local_tag, Rest}.

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
Reports whether further scalar continuation content follows, skipping blanks and comments and stopping at document markers.
""".
-spec has_continuation_content(binary()) -> boolean().
has_continuation_content(Bin) ->
    case get_first_line(Bin) of
        <<>> ->
            false;
        Line ->
            Trimmed = strip_whitespace(Line),
            case Trimmed of
                <<>> -> has_continuation_content(skip_past_first_line(Bin));
                <<"---", _/binary>> -> false;
                <<"...", _/binary>> -> false;
                <<"#", _/binary>> -> has_continuation_content(skip_past_first_line(Bin));
                _ -> true
            end
    end.

-doc """
Reports whether the content contains a `%YAML` or `%TAG` directive on a later line.
""".
-spec has_directive_pattern(binary()) -> boolean().
has_directive_pattern(Content) ->
    case binary:match(Content, <<"\n%YAML ">>) of
        {_, _} ->
            true;
        nomatch ->
            case binary:match(Content, <<"\n%TAG ">>) of
                {_, _} -> true;
                nomatch -> false
            end
    end.

-doc """
Reports whether only whitespace precedes the next newline.
""".
-spec has_newline_before_content(binary()) -> boolean().
has_newline_before_content(<<>>) ->
    false;
has_newline_before_content(<<"\n", _/binary>>) ->
    true;
has_newline_before_content(<<"\r\n", _/binary>>) ->
    true;
has_newline_before_content(<<C, Rest/binary>>) when C =:= $\s; C =:= $\t ->
    has_newline_before_content(Rest);
has_newline_before_content(_) ->
    false.

-doc """
Reports whether non-whitespace content appears before the end of the current line.
""".
-spec has_same_line_content(binary()) -> boolean().
has_same_line_content(<<C, _/binary>>) when C =/= $\s, C =/= $\t, C =/= $\n, C =/= $\r ->
    true;
has_same_line_content(<<"\n", _/binary>>) ->
    false;
has_same_line_content(<<"\r\n", _/binary>>) ->
    false;
has_same_line_content(<<>>) ->
    false;
has_same_line_content(<<_, Rest/binary>>) ->
    has_same_line_content(Rest).

-doc """
Reports whether a `:` mapping indicator appears on the current line.

A `:` inside a flow collection belongs to that collection, and a `:` between
quotes is scalar content, so neither marks the line as a mapping entry. The
"Flow Mappings" section makes the `:` of a flow pair part of the flow
collection, and the "Double-Quoted Style" and "Single-Quoted Style" sections
make the characters between the quotes content.
""".
-spec has_same_line_mapping_indicator(binary()) -> boolean().
has_same_line_mapping_indicator(Bin) ->
    has_same_line_mapping_indicator(Bin, 0).

-doc """
Reports whether a `:` mapping indicator appears on the current line, given the
flow nesting level that the scan has reached.
""".
-spec has_same_line_mapping_indicator(binary(), non_neg_integer()) -> boolean().
has_same_line_mapping_indicator(<<>>, _Depth) ->
    false;
has_same_line_mapping_indicator(<<"\n", _/binary>>, _Depth) ->
    false;
has_same_line_mapping_indicator(<<"\r\n", _/binary>>, _Depth) ->
    false;
has_same_line_mapping_indicator(<<": ", _/binary>>, 0) ->
    true;
has_same_line_mapping_indicator(<<":\t", _/binary>>, 0) ->
    true;
has_same_line_mapping_indicator(<<":\n", _/binary>>, 0) ->
    true;
has_same_line_mapping_indicator(<<":\r\n", _/binary>>, 0) ->
    true;
has_same_line_mapping_indicator(<<":">>, 0) ->
    true;
has_same_line_mapping_indicator(<<C, Rest/binary>>, Depth) when C =:= $[; C =:= ${ ->
    has_same_line_mapping_indicator(Rest, Depth + 1);
has_same_line_mapping_indicator(<<C, Rest/binary>>, Depth) when
    Depth > 0, C =:= $]; Depth > 0, C =:= $}
->
    has_same_line_mapping_indicator(Rest, Depth - 1);
has_same_line_mapping_indicator(<<C, Rest/binary>>, Depth) when C =:= $"; C =:= $' ->
    has_same_line_mapping_indicator(skip_same_line_quoted(Rest, C), Depth);
has_same_line_mapping_indicator(<<_, Rest/binary>>, Depth) ->
    has_same_line_mapping_indicator(Rest, Depth).

-doc """
Reports whether an anchor name is followed by a `:` on the same line, marking a mapping key.
""".
-spec is_anchor_in_mapping_key(binary()) -> boolean().
is_anchor_in_mapping_key(Bin) ->
    case parse_name(Bin, <<>>) of
        {ok, _Name, Rest} ->
            FirstLine = get_first_line(Rest),
            case binary:match(FirstLine, <<":">>) of
                nomatch -> false;
                _ -> true
            end;
        {error, _} ->
            false
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
Reports whether the line contains a `:` mapping key separator.
""".
-spec is_mapping_key_line(binary()) -> boolean().
is_mapping_key_line(<<>>) ->
    false;
is_mapping_key_line(<<":">>) ->
    true;
is_mapping_key_line(<<":", C, _/binary>>) when C =:= $\s; C =:= $\t ->
    true;
is_mapping_key_line(<<_, Rest/binary>>) ->
    is_mapping_key_line(Rest).

-doc """
Reports whether a quoted scalar of the given quote type is followed by a `:` mapping separator.
""".
-spec is_quoted_mapping_key(binary(), double | single) -> boolean().
is_quoted_mapping_key(Bin, QuoteType) ->
    case nyaml_scalar:parse_quoted(Bin, QuoteType) of
        {ok, _Value, Rest} ->
            TrimmedRest = skip_whitespace(Rest),
            case TrimmedRest of
                <<":", _/binary>> -> true;
                _ -> false
            end;
        {error, _} ->
            false
    end.

-doc """
Reports whether the first line carries a same-line mapping indicator after a tag.
""".
-spec is_tagged_mapping_key(binary()) -> boolean().
is_tagged_mapping_key(Bin) ->
    FirstLine = get_first_line(Bin),
    has_same_line_mapping_indicator(FirstLine).

-doc """
Reports whether a `---` or `...` marker is followed by whitespace or end of input.
""".
-spec is_valid_document_marker(binary()) -> boolean().
is_valid_document_marker(<<>>) -> true;
is_valid_document_marker(<<C, _/binary>>) when C =:= $\s; C =:= $\t; C =:= $\n; C =:= $\r -> true;
is_valid_document_marker(_) -> false.

-doc """
Reports whether the line contains a whitespace-preceded `#` comment outside quotes.
""".
-spec line_has_comment(binary()) -> boolean().
line_has_comment(Line) ->
    line_has_comment(Line, false).

-doc """
Reports whether a `#` comment follows, tracking the current quoting state.
""".
-spec line_has_comment(binary(), boolean() | double | single) -> boolean().
line_has_comment(<<>>, _InQuote) ->
    false;
line_has_comment(<<" #", _/binary>>, false) ->
    true;
line_has_comment(<<"\t#", _/binary>>, false) ->
    true;
line_has_comment(<<"\"", Rest/binary>>, false) ->
    line_has_comment(Rest, double);
line_has_comment(<<"'", Rest/binary>>, false) ->
    line_has_comment(Rest, single);
line_has_comment(<<"\\\"", Rest/binary>>, double) ->
    line_has_comment(Rest, double);
line_has_comment(<<"\"", Rest/binary>>, double) ->
    line_has_comment(Rest, false);
line_has_comment(<<"''", Rest/binary>>, single) ->
    line_has_comment(Rest, single);
line_has_comment(<<"'", Rest/binary>>, single) ->
    line_has_comment(Rest, false);
line_has_comment(<<_, Rest/binary>>, InQuote) ->
    line_has_comment(Rest, InQuote).

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

-doc """
Parses an alias name up to the first flow or whitespace delimiter.
""".
-spec parse_alias_name(binary()) -> {ok, binary(), binary()} | {error, nyaml_parser:parse_error()}.
parse_alias_name(Bin) ->
    parse_name(Bin, <<>>).

-doc """
Parses an anchor name up to the first flow or whitespace delimiter.
""".
-spec parse_anchor_name(binary()) -> {ok, binary(), binary()} | {error, nyaml_parser:parse_error()}.
parse_anchor_name(Bin) ->
    parse_name(Bin, <<>>).

-doc """
Parses a directive name, which runs to the first space, tab, or line break.
""".
-spec parse_directive_name(binary()) -> {binary(), binary()}.
parse_directive_name(Bin) ->
    parse_directive_name(Bin, <<>>).

-doc """
Accumulates directive name characters, which the specification makes any non-space character.
""".
-spec parse_directive_name(binary(), binary()) -> {binary(), binary()}.
parse_directive_name(<<C, Rest/binary>>, Acc) when
    C =/= $\s,
    C =/= $\t,
    C =/= $\n,
    C =/= $\r
->
    parse_directive_name(Rest, <<Acc/binary, C>>);
parse_directive_name(Rest, Acc) ->
    {Acc, Rest}.

-doc """
Accumulates anchor or alias name characters until a flow or whitespace delimiter, rejecting an empty name.
""".
-spec parse_name(binary(), binary()) ->
    {ok, binary(), binary()} | {error, nyaml_parser:parse_error()}.
parse_name(<<C, Rest/binary>>, Acc) when
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
    parse_name(Rest, <<Acc/binary, C>>);
parse_name(Rest, <<>>) ->
    {error, {invalid_anchor_name, Rest}};
parse_name(Rest, Acc) ->
    {ok, Acc, Rest}.

-doc """
Parses a tag handle, returning an empty handle at whitespace or a primary `!` handle.
""".
-spec parse_tag_handle_name(binary()) ->
    {ok, binary(), binary()} | {error, nyaml_parser:parse_error()}.
parse_tag_handle_name(<<" ", _/binary>> = Rest) ->
    {ok, <<>>, Rest};
parse_tag_handle_name(<<"\t", _/binary>> = Rest) ->
    {ok, <<>>, Rest};
parse_tag_handle_name(<<"!", Rest/binary>>) ->
    {ok, <<"!">>, Rest};
parse_tag_handle_name(Bin) ->
    parse_tag_handle_name(Bin, <<>>).

-doc """
Accumulates tag handle characters, closing the handle at the terminating `!`.
""".
-spec parse_tag_handle_name(binary(), binary()) ->
    {ok, binary(), binary()} | {error, nyaml_parser:parse_error()}.
parse_tag_handle_name(<<"!", Rest/binary>>, Acc) when Acc =/= <<>> ->
    {ok, <<Acc/binary, "!">>, Rest};
parse_tag_handle_name(<<C, Rest/binary>>, Acc) when
    (C >= $a andalso C =< $z) orelse
        (C >= $A andalso C =< $Z) orelse
        (C >= $0 andalso C =< $9) orelse
        C =:= $-
->
    parse_tag_handle_name(Rest, <<Acc/binary, C>>);
parse_tag_handle_name(_, <<>>) ->
    {error, invalid_tag_handle_name};
parse_tag_handle_name(_, _) ->
    {error, invalid_tag_handle_name}.

-doc """
Parses a tag shorthand name from the binary.
""".
-spec parse_tag_name(binary()) -> {ok, binary(), binary()} | {error, nyaml_parser:parse_error()}.
parse_tag_name(Bin) ->
    parse_tag_name(Bin, <<>>).

-doc """
Accumulates tag name characters until a delimiter, rejecting an empty name.
""".
-spec parse_tag_name(binary(), binary()) ->
    {ok, binary(), binary()} | {error, nyaml_parser:parse_error()}.
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

-doc """
Parses a tag prefix up to end of line, returning it and the remaining input.
""".
-spec parse_tag_prefix(binary()) -> {binary(), binary()}.
parse_tag_prefix(Bin) ->
    parse_tag_prefix(Bin, <<>>).

-doc """
Accumulates tag prefix characters until whitespace or newline ends the prefix.
""".
-spec parse_tag_prefix(binary(), binary()) -> {binary(), binary()}.
parse_tag_prefix(<<"\n", Rest/binary>>, Acc) ->
    {Acc, Rest};
parse_tag_prefix(<<"\r\n", Rest/binary>>, Acc) ->
    {Acc, Rest};
parse_tag_prefix(<<" ", Rest/binary>>, Acc) ->
    {Acc, skip_to_end_of_line(Rest)};
parse_tag_prefix(<<"\t", Rest/binary>>, Acc) ->
    {Acc, skip_to_end_of_line(Rest)};
parse_tag_prefix(<<>>, Acc) ->
    {Acc, <<>>};
parse_tag_prefix(<<C, Rest/binary>>, Acc) ->
    parse_tag_prefix(Rest, <<Acc/binary, C>>).

-doc """
Parses a decimal version number from the binary.
""".
-spec parse_version_number(binary()) ->
    {ok, non_neg_integer(), binary()} | {error, nyaml_parser:parse_error()}.
parse_version_number(Bin) ->
    parse_version_number(Bin, <<>>).

-doc """
Accumulates decimal digits into a version number, rejecting an empty number.
""".
-spec parse_version_number(binary(), binary()) ->
    {ok, non_neg_integer(), binary()} | {error, nyaml_parser:parse_error()}.
parse_version_number(<<C, Rest/binary>>, Acc) when C >= $0, C =< $9 ->
    parse_version_number(Rest, <<Acc/binary, C>>);
parse_version_number(Rest, <<>>) ->
    {error, {no_version_number, Rest}};
parse_version_number(Rest, Acc) ->
    {ok, binary_to_integer(Acc), Rest}.

-doc """
Parses the argument of a `%YAML` directive into its version.

The "Separation Spaces" section makes the separation before the version one or
more space or tab characters, so `%YAML  1.1` and `%YAML \t 1.1` both hold a
version.
""".
-spec parse_yaml_directive(binary()) -> {ok, binary()} | {error, nyaml_parser:parse_error()}.
parse_yaml_directive(<<C, _/binary>> = Bin) when C =:= $\s; C =:= $\t ->
    parse_yaml_version(skip_whitespace_inline(Bin));
parse_yaml_directive(_) ->
    {error, invalid_yaml_directive}.

-doc """
Parses a `major.minor` YAML version and validates the directive line ending.
""".
-spec parse_yaml_version(binary()) -> {ok, binary()} | {error, nyaml_parser:parse_error()}.
parse_yaml_version(Bin) ->
    maybe
        {ok, _Major, <<".", Rest2/binary>>} ?= parse_version_number(Bin),
        {ok, _Minor, Rest3} ?= parse_version_number(Rest2),
        validate_directive_end(Rest3)
    else
        _ -> {error, invalid_yaml_directive}
    end.

-doc """
Skips leading blank and comment lines, returning the input re-indented at the first content line.
""".
-spec skip_empty_and_comment_lines(binary()) -> binary().
skip_empty_and_comment_lines(Bin) ->
    skip_empty_and_comment_lines(Bin, 0, false).

-doc """
Skips blank and comment lines while tracking indentation, restoring leading spaces before content.
""".
-spec skip_empty_and_comment_lines(binary(), non_neg_integer(), boolean()) -> binary().
skip_empty_and_comment_lines(<<>>, _, _) ->
    <<>>;
skip_empty_and_comment_lines(<<"\n", Rest/binary>>, _Indent, _HasTab) ->
    skip_empty_and_comment_lines(Rest, 0, false);
skip_empty_and_comment_lines(<<"\r\n", Rest/binary>>, _Indent, _HasTab) ->
    skip_empty_and_comment_lines(Rest, 0, false);
skip_empty_and_comment_lines(<<$\s, Rest/binary>>, Indent, HasTab) ->
    skip_empty_and_comment_lines(Rest, Indent + 1, HasTab);
skip_empty_and_comment_lines(<<$\t, Rest/binary>>, Indent, _HasTab) ->
    skip_empty_and_comment_lines(Rest, Indent + 1, true);
skip_empty_and_comment_lines(<<"#", Rest/binary>>, _Indent, _HasTab) ->
    skip_to_newline_then_continue(Rest);
skip_empty_and_comment_lines(Bin, Indent, _HasTab) ->
    Spaces = list_to_binary(lists:duplicate(Indent, $\s)),
    <<Spaces/binary, Bin/binary>>.

-doc """
Drops leading spaces and tabs.
""".
-spec skip_leading_ws(binary()) -> binary().
skip_leading_ws(<<C, Rest/binary>>) when C =:= $\s; C =:= $\t ->
    skip_leading_ws(Rest);
skip_leading_ws(Bin) ->
    Bin.

-doc """
Returns the input following the first newline.
""".
-spec skip_past_first_line(binary()) -> binary().
skip_past_first_line(Bin) ->
    case binary:match(Bin, <<"\n">>) of
        nomatch -> <<>>;
        {Pos, 1} -> binary:part(Bin, Pos + 1, byte_size(Bin) - Pos - 1)
    end.

-doc """
Returns the input that follows a quoted scalar opened by `Quote`, stopping at a
line break when the scalar is not closed on the line.

The scan honours the escapes that close a quoted scalar: a backslash escapes
the next character of a double-quoted scalar, and a doubled quote stands for
one quote inside a single-quoted scalar. The "Double-Quoted Style" and
"Single-Quoted Style" sections define both.
""".
-spec skip_same_line_quoted(binary(), byte()) -> binary().
skip_same_line_quoted(<<>>, _Quote) ->
    <<>>;
skip_same_line_quoted(<<"\n", _/binary>> = Bin, _Quote) ->
    Bin;
skip_same_line_quoted(<<$\\, C, Rest/binary>>, $") when C =/= $\n, C =/= $\r ->
    skip_same_line_quoted(Rest, $");
skip_same_line_quoted(<<$', $', Rest/binary>>, $') ->
    skip_same_line_quoted(Rest, $');
skip_same_line_quoted(<<Quote, Rest/binary>>, Quote) ->
    Rest;
skip_same_line_quoted(<<_, Rest/binary>>, Quote) ->
    skip_same_line_quoted(Rest, Quote).

-doc """
Drops leading spaces and tabs on the current line.
""".
-spec skip_same_line_whitespace(binary()) -> binary().
skip_same_line_whitespace(<<C, Rest/binary>>) when C =:= $\s; C =:= $\t ->
    skip_same_line_whitespace(Rest);
skip_same_line_whitespace(Bin) ->
    Bin.

-doc """
Skips tag characters up to a delimiter, rejecting `[` and `{` inside the tag.
""".
-spec skip_tag_chars(binary()) -> {ok, binary()} | {error, nyaml_parser:parse_error()}.
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
Skips inline whitespace and any following blank or comment lines to the next content.
""".
-spec skip_to_content(binary()) -> binary().
skip_to_content(<<"\n", Rest/binary>>) ->
    nyaml_parser:skip_whitespace_and_comments(Rest);
skip_to_content(<<"\r\n", Rest/binary>>) ->
    nyaml_parser:skip_whitespace_and_comments(Rest);
skip_to_content(<<" ", Rest/binary>>) ->
    skip_to_content(Rest);
skip_to_content(<<"\t", Rest/binary>>) ->
    skip_to_content(Rest);
skip_to_content(Bin) ->
    nyaml_parser:skip_whitespace_and_comments(Bin).

-doc """
Returns the input following the next newline.
""".
-spec skip_to_end_of_line(binary()) -> binary().
skip_to_end_of_line(<<"\n", Rest/binary>>) ->
    Rest;
skip_to_end_of_line(<<"\r\n", Rest/binary>>) ->
    Rest;
skip_to_end_of_line(<<>>) ->
    <<>>;
skip_to_end_of_line(<<_, Rest/binary>>) ->
    skip_to_end_of_line(Rest).

-doc """
Returns the input after the next newline with leading whitespace on the following line removed.
""".
-spec skip_to_eol(binary()) -> binary().
skip_to_eol(<<"\n", Rest/binary>>) ->
    skip_leading_ws(Rest);
skip_to_eol(<<"\r\n", Rest/binary>>) ->
    skip_leading_ws(Rest);
skip_to_eol(<<>>) ->
    <<>>;
skip_to_eol(<<_, Rest/binary>>) ->
    skip_to_eol(Rest).

-doc """
Skips to the next newline, then drops following blank and comment lines.
""".
-spec skip_to_newline_then_continue(binary()) -> binary().
skip_to_newline_then_continue(<<"\n", Rest/binary>>) ->
    skip_empty_and_comment_lines(Rest, 0, false);
skip_to_newline_then_continue(<<"\r\n", Rest/binary>>) ->
    skip_empty_and_comment_lines(Rest, 0, false);
skip_to_newline_then_continue(<<>>) ->
    <<>>;
skip_to_newline_then_continue(<<_, Rest/binary>>) ->
    skip_to_newline_then_continue(Rest).

-doc """
Skips a verbatim `!<...>` tag, returning the input after the closing `>`.
""".
-spec skip_verbatim_tag(binary()) -> {ok, binary()} | {error, nyaml_parser:parse_error()}.
skip_verbatim_tag(Bin) ->
    skip_verbatim_tag(Bin, <<>>).

-doc """
Accumulates verbatim tag characters until the closing `>`, erroring if unterminated.
""".
-spec skip_verbatim_tag(binary(), binary()) ->
    {ok, binary()} | {error, nyaml_parser:parse_error()}.
skip_verbatim_tag(<<">", Rest/binary>>, _Acc) ->
    {ok, Rest};
skip_verbatim_tag(<<C, Rest/binary>>, Acc) when C =/= $> ->
    skip_verbatim_tag(Rest, <<Acc/binary, C>>);
skip_verbatim_tag(<<>>, _Acc) ->
    {error, unterminated_verbatim_tag}.

-doc """
Drops leading spaces, tabs, carriage returns, and newlines.
""".
-spec skip_whitespace(binary()) -> binary().
skip_whitespace(<<C, Rest/binary>>) when C =:= $\s; C =:= $\t; C =:= $\r; C =:= $\n ->
    skip_whitespace(Rest);
skip_whitespace(Bin) ->
    Bin.

-doc """
Drops leading spaces and tabs only.
""".
-spec skip_whitespace_inline(binary()) -> binary().
skip_whitespace_inline(<<" ", Rest/binary>>) ->
    skip_whitespace_inline(Rest);
skip_whitespace_inline(<<"\t", Rest/binary>>) ->
    skip_whitespace_inline(Rest);
skip_whitespace_inline(Bin) ->
    Bin.

-doc """
Removes trailing whitespace from the binary.
""".
-spec strip_trailing_whitespace(binary()) -> binary().
strip_trailing_whitespace(Bin) ->
    iolist_to_binary(re:replace(Bin, "\\s+$", "", [{return, binary}])).

-doc """
Removes trailing spaces and tabs from the binary.
""".
-spec strip_trailing_ws(binary()) -> binary().
strip_trailing_ws(<<>>) ->
    <<>>;
strip_trailing_ws(Bin) ->
    case binary:last(Bin) of
        C when C =:= $\s; C =:= $\t ->
            strip_trailing_ws(binary:part(Bin, 0, byte_size(Bin) - 1));
        _ ->
            Bin
    end.

-doc """
Removes leading and trailing whitespace from the binary.
""".
-spec strip_whitespace(binary()) -> binary().
strip_whitespace(Bin) ->
    iolist_to_binary(re:replace(Bin, "^\\s+|\\s+$", "", [{return, binary}, global])).

-doc """
Reads the content of a `bool` node as a boolean under the given schema.

The "Core Schema" section gives the `bool` tag the regular expression
`true | True | TRUE | false | False | FALSE`, and every schema takes those six
spellings. The extended schema adds the tokens that the `bool` type of the YAML
1.1 type repository lists, which are `y`, `yes`, and `on` with their negatives,
in the lower case, title case, and upper case spellings that the repository
writes. Content that no token matches gives `error`.
""".
-spec to_bool(nyaml:schema(), binary()) -> {ok, boolean()} | error.
to_bool(_Schema, <<"true">>) -> {ok, true};
to_bool(_Schema, <<"True">>) -> {ok, true};
to_bool(_Schema, <<"TRUE">>) -> {ok, true};
to_bool(_Schema, <<"false">>) -> {ok, false};
to_bool(_Schema, <<"False">>) -> {ok, false};
to_bool(_Schema, <<"FALSE">>) -> {ok, false};
to_bool(extended, <<"y">>) -> {ok, true};
to_bool(extended, <<"Y">>) -> {ok, true};
to_bool(extended, <<"yes">>) -> {ok, true};
to_bool(extended, <<"Yes">>) -> {ok, true};
to_bool(extended, <<"YES">>) -> {ok, true};
to_bool(extended, <<"on">>) -> {ok, true};
to_bool(extended, <<"On">>) -> {ok, true};
to_bool(extended, <<"ON">>) -> {ok, true};
to_bool(extended, <<"n">>) -> {ok, false};
to_bool(extended, <<"N">>) -> {ok, false};
to_bool(extended, <<"no">>) -> {ok, false};
to_bool(extended, <<"No">>) -> {ok, false};
to_bool(extended, <<"NO">>) -> {ok, false};
to_bool(extended, <<"off">>) -> {ok, false};
to_bool(extended, <<"Off">>) -> {ok, false};
to_bool(extended, <<"OFF">>) -> {ok, false};
to_bool(_Schema, _Content) -> error.

-doc """
Coerces a numeric value or its string form to a float, leaving other values unchanged.
""".
-spec to_float(nyaml_parser:yaml_value()) -> float() | nyaml_parser:yaml_value().
to_float(Value) when is_float(Value) -> Value;
to_float(Value) when is_integer(Value) -> float(Value);
to_float(Value) when is_binary(Value) ->
    try
        binary_to_float(Value)
    catch
        error:badarg ->
            try
                float(binary_to_integer(Value))
            catch
                error:badarg -> Value
            end
    end;
to_float(Value) ->
    Value.

-doc """
Coerces an integer or its string form to an integer, leaving other values unchanged.
""".
-spec to_int(nyaml_parser:yaml_value()) -> integer() | nyaml_parser:yaml_value().
to_int(Value) when is_integer(Value) -> Value;
to_int(Value) when is_binary(Value) ->
    try
        binary_to_integer(Value)
    catch
        error:badarg -> Value
    end;
to_int(Value) ->
    Value.

-doc """
Validates that a directive line ends with whitespace or a line break.

The "Comments" section requires a comment to be separated from the token before
it, so a `#` that follows the version with no separation is an error.
""".
-spec validate_directive_end(binary()) -> {ok, binary()} | {error, nyaml_parser:parse_error()}.
validate_directive_end(<<"\n", Rest/binary>>) ->
    {ok, Rest};
validate_directive_end(<<"\r\n", Rest/binary>>) ->
    {ok, Rest};
validate_directive_end(<<" ", Rest/binary>>) ->
    validate_directive_end_after_space(Rest);
validate_directive_end(<<"\t", Rest/binary>>) ->
    validate_directive_end_after_space(Rest);
validate_directive_end(<<"#", _/binary>>) ->
    {error, comment_without_separation};
validate_directive_end(<<>>) ->
    {ok, <<>>};
validate_directive_end(_) ->
    {error, invalid_yaml_directive}.

-doc """
Validates the remainder of a directive line after whitespace, allowing a comment or line break.
""".
-spec validate_directive_end_after_space(binary()) ->
    {ok, binary()} | {error, nyaml_parser:parse_error()}.
validate_directive_end_after_space(<<"#", Rest/binary>>) ->
    {ok, skip_to_end_of_line(Rest)};
validate_directive_end_after_space(<<"\n", Rest/binary>>) ->
    {ok, Rest};
validate_directive_end_after_space(<<"\r\n", Rest/binary>>) ->
    {ok, Rest};
validate_directive_end_after_space(<<" ", Rest/binary>>) ->
    validate_directive_end_after_space(Rest);
validate_directive_end_after_space(<<"\t", Rest/binary>>) ->
    validate_directive_end_after_space(Rest);
validate_directive_end_after_space(<<>>) ->
    {ok, <<>>};
validate_directive_end_after_space(_) ->
    {error, invalid_yaml_directive}.

-doc """
Validates the remainder of a document-end line after whitespace, allowing a comment or line break.
""".
-spec validate_document_end_after_space(binary()) ->
    {ok, binary()} | {error, nyaml_parser:parse_error()}.
validate_document_end_after_space(<<"#", Rest/binary>>) ->
    {ok, skip_to_end_of_line(Rest)};
validate_document_end_after_space(<<"\n", Rest/binary>>) ->
    {ok, Rest};
validate_document_end_after_space(<<"\r\n", Rest/binary>>) ->
    {ok, Rest};
validate_document_end_after_space(<<" ", Rest/binary>>) ->
    validate_document_end_after_space(Rest);
validate_document_end_after_space(<<"\t", Rest/binary>>) ->
    validate_document_end_after_space(Rest);
validate_document_end_after_space(<<>>) ->
    {ok, <<>>};
validate_document_end_after_space(_) ->
    {error, invalid_content_after_document_end}.

-doc """
Validates that a `...` document-end marker is followed only by whitespace, a comment, or a line break.
""".
-spec validate_document_end_line(binary()) ->
    {ok, binary()} | {error, nyaml_parser:parse_error()}.
validate_document_end_line(<<>>) ->
    {ok, <<>>};
validate_document_end_line(<<"\n", Rest/binary>>) ->
    {ok, Rest};
validate_document_end_line(<<"\r\n", Rest/binary>>) ->
    {ok, Rest};
validate_document_end_line(<<" ", Rest/binary>>) ->
    validate_document_end_after_space(Rest);
validate_document_end_line(<<"\t", Rest/binary>>) ->
    validate_document_end_after_space(Rest);
validate_document_end_line(_) ->
    {error, invalid_content_after_document_end}.
