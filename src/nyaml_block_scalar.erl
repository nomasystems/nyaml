-module(nyaml_block_scalar).

-moduledoc """
Block scalar parsing (literal `|` and folded `>`).

Handles YAML block scalar syntax with indentation, chomping indicators,
and line folding rules.
""".

%%%-----------------------------------------------------------------------------
%% API EXPORTS
%%%-----------------------------------------------------------------------------
-export([
    is_block_scalar_indicator/1,
    parse/2,
    parse/3
]).

%%%-----------------------------------------------------------------------------
%% TYPE EXPORTS
%%%-----------------------------------------------------------------------------
-export_type([
    chomping/0,
    parse_error/0,
    style/0
]).

%%%-----------------------------------------------------------------------------
%% TYPES
%%%-----------------------------------------------------------------------------
-type chomping() :: strip | clip | keep.

-type style() :: literal | folded.

-type parse_error() ::
    not_a_block_scalar
    | tab_in_indentation
    | {unexpected_char_in_block_scalar_header, byte()}
    | {invalid_block_scalar_indentation, non_neg_integer(), non_neg_integer()}.

-type fold_state() ::
    start | text | leading_break | first_break | break | more_indented | mi_first_break | mi_break.

%%%-----------------------------------------------------------------------------
%% API FUNCTIONS
%%%-----------------------------------------------------------------------------

-doc """
Checks if the binary starts with a block scalar indicator (`|` or `>`).
""".
-spec is_block_scalar_indicator(binary()) -> boolean().
is_block_scalar_indicator(<<"|", _/binary>>) -> true;
is_block_scalar_indicator(<<">", _/binary>>) -> true;
is_block_scalar_indicator(_) -> false.

-doc """
Parses a block scalar at the given base indentation level.
""".
-spec parse(binary(), non_neg_integer()) ->
    {ok, binary(), binary()} | {error, parse_error()}.
parse(Bin, BaseIndent) ->
    parse(Bin, BaseIndent, false).

-doc """
Parses a block scalar with optional column zero allowance.
""".
-spec parse(binary(), non_neg_integer(), boolean()) ->
    {ok, binary(), binary()} | {error, parse_error()}.
parse(Bin, BaseIndent, AllowColumnZero) ->
    case parse_header(Bin) of
        {ok, Style, IndentIndicator, Chomping, Rest} ->
            parse_content(Style, IndentIndicator, Chomping, Rest, BaseIndent, AllowColumnZero);
        {error, Reason} ->
            {error, Reason}
    end.

%%%-----------------------------------------------------------------------------
%% INTERNAL FUNCTIONS
%%%-----------------------------------------------------------------------------

-spec apply_chomping(binary(), chomping()) -> binary().
apply_chomping(<<>>, _Chomping) ->
    <<>>;
apply_chomping(Content, strip) ->
    strip_trailing_newlines(Content);
apply_chomping(Content, clip) ->
    clip_trailing_newlines(Content);
apply_chomping(Content, keep) ->
    Content.

-spec clip_trailing_newlines(binary()) -> binary().
clip_trailing_newlines(Bin) ->
    Stripped = strip_trailing_newlines(Bin),
    case Stripped of
        <<>> -> <<>>;
        _ -> <<Stripped/binary, "\n">>
    end.

-spec collect_content_lines(binary(), non_neg_integer()) ->
    {ok, [{non_neg_integer(), binary()}], binary()} | {error, parse_error()}.
collect_content_lines(Bin, ContentIndent) ->
    collect_content_lines(Bin, ContentIndent, []).

-spec collect_content_lines(binary(), non_neg_integer(), [{non_neg_integer(), binary()}]) ->
    {ok, [{non_neg_integer(), binary()}], binary()} | {error, parse_error()}.
collect_content_lines(<<>>, _ContentIndent, Acc) ->
    {ok, lists:reverse(Acc), <<>>};
collect_content_lines(Bin, ContentIndent, Acc) ->
    SeenContent = has_content_line(Acc),
    case next_line(Bin) of
        {line, Line, Rest} ->
            LineIndent = count_leading_spaces(Line),
            case Line of
                <<>> ->
                    collect_content_lines(Rest, ContentIndent, [{0, <<>>} | Acc]);
                _ when LineIndent >= ContentIndent ->
                    Content = strip_n_leading_spaces(Line, ContentIndent),
                    case is_whitespace_only(Content) of
                        true when not SeenContent, LineIndent > ContentIndent ->
                            {error, {invalid_block_scalar_indentation, LineIndent, ContentIndent}};
                        _ ->
                            collect_content_lines(Rest, ContentIndent, [
                                {LineIndent - ContentIndent, Content} | Acc
                            ])
                    end;
                _ ->
                    case classify_line_below_content(Line) of
                        empty ->
                            collect_content_lines(Rest, ContentIndent, [{0, <<>>} | Acc]);
                        tab ->
                            {error, tab_in_indentation};
                        content ->
                            {ok, lists:reverse(Acc), Bin}
                    end
            end;
        eof ->
            {ok, lists:reverse(Acc), <<>>}
    end.

-spec classify_line_below_content(binary()) -> empty | tab | content.
classify_line_below_content(<<$\s, Rest/binary>>) ->
    classify_line_below_content(Rest);
classify_line_below_content(<<$\t, _/binary>>) ->
    tab;
classify_line_below_content(<<>>) ->
    empty;
classify_line_below_content(_) ->
    content.

-spec count_leading_spaces(binary()) -> non_neg_integer().
count_leading_spaces(Bin) ->
    count_leading_spaces(Bin, 0).

-spec count_leading_spaces(binary(), non_neg_integer()) -> non_neg_integer().
count_leading_spaces(<<$\s, Rest/binary>>, N) ->
    count_leading_spaces(Rest, N + 1);
count_leading_spaces(_, N) ->
    N.

-spec determine_content_indent(non_neg_integer() | auto, binary(), non_neg_integer(), boolean()) ->
    non_neg_integer().
determine_content_indent(auto, Bin, BaseIndent, AllowColumnZero) when is_integer(BaseIndent) ->
    case find_first_content_line_indent(Bin, BaseIndent, AllowColumnZero) of
        {ok, Indent} -> Indent;
        {none, LongestLine} -> max(BaseIndent + 1, LongestLine)
    end;
determine_content_indent(Indicator, _Bin, BaseIndent, _AllowColumnZero) when
    is_integer(Indicator), is_integer(BaseIndent)
->
    BaseIndent + Indicator.

-spec find_first_content_line_indent(binary(), non_neg_integer(), boolean()) ->
    {ok, non_neg_integer()} | {none, non_neg_integer()}.
find_first_content_line_indent(Bin, BaseIndent, AllowColumnZero) ->
    find_first_content_line_indent(Bin, BaseIndent, AllowColumnZero, 0).

-spec find_first_content_line_indent(binary(), non_neg_integer(), boolean(), non_neg_integer()) ->
    {ok, non_neg_integer()} | {none, non_neg_integer()}.
find_first_content_line_indent(<<>>, _BaseIndent, _AllowColumnZero, LongestLine) ->
    {none, LongestLine};
find_first_content_line_indent(Bin, BaseIndent, AllowColumnZero, LongestLine) ->
    case next_line(Bin) of
        {line, Line, Rest} ->
            case is_empty_or_whitespace(Line) of
                true ->
                    Widest = max(LongestLine, count_leading_spaces(Line)),
                    find_first_content_line_indent(Rest, BaseIndent, AllowColumnZero, Widest);
                false ->
                    Indent = count_leading_spaces(Line),
                    case (AllowColumnZero andalso Indent =:= 0) orelse Indent > BaseIndent of
                        true -> {ok, Indent};
                        false -> {none, LongestLine}
                    end
            end;
        eof ->
            {none, LongestLine}
    end.

-spec fold_lines([{non_neg_integer(), binary()}]) -> binary().
fold_lines([]) ->
    <<>>;
fold_lines(Lines) ->
    fold_lines(Lines, <<>>, start).

-spec fold_lines([{non_neg_integer(), binary()}], binary(), fold_state()) -> binary().
fold_lines([], Acc, _State) ->
    <<Acc/binary, "\n">>;
fold_lines([{_Indent, <<>>} | Rest], Acc, start) ->
    fold_lines(Rest, <<Acc/binary, "\n">>, leading_break);
fold_lines([{Indent, Content} | Rest], Acc, start) ->
    case is_more_indented(Indent, Content) of
        true -> fold_lines(Rest, <<Acc/binary, Content/binary>>, more_indented);
        false -> fold_lines(Rest, <<Acc/binary, Content/binary>>, text)
    end;
fold_lines([{_Indent, <<>>} | Rest], Acc, leading_break) ->
    fold_lines(Rest, <<Acc/binary, "\n">>, leading_break);
fold_lines([{Indent, Content} | Rest], Acc, leading_break) ->
    case is_more_indented(Indent, Content) of
        true -> fold_lines(Rest, <<Acc/binary, Content/binary>>, more_indented);
        false -> fold_lines(Rest, <<Acc/binary, Content/binary>>, text)
    end;
fold_lines([{_Indent, <<>>} | Rest], Acc, text) ->
    fold_lines(Rest, <<Acc/binary, "\n">>, first_break);
fold_lines([{Indent, Content} | Rest], Acc, text) ->
    case is_more_indented(Indent, Content) of
        true -> fold_lines(Rest, <<Acc/binary, "\n", Content/binary>>, more_indented);
        false -> fold_lines(Rest, <<Acc/binary, " ", Content/binary>>, text)
    end;
fold_lines([{_Indent, <<>>} | Rest], Acc, first_break) ->
    fold_lines(Rest, <<Acc/binary, "\n">>, break);
fold_lines([{Indent, Content} | Rest], Acc, first_break) ->
    case is_more_indented(Indent, Content) of
        true -> fold_lines(Rest, <<Acc/binary, "\n", Content/binary>>, more_indented);
        false -> fold_lines(Rest, <<Acc/binary, Content/binary>>, text)
    end;
fold_lines([{_Indent, <<>>} | Rest], Acc, break) ->
    fold_lines(Rest, <<Acc/binary, "\n">>, break);
fold_lines([{Indent, Content} | Rest], Acc, break) ->
    case is_more_indented(Indent, Content) of
        true -> fold_lines(Rest, <<Acc/binary, "\n", Content/binary>>, more_indented);
        false -> fold_lines(Rest, <<Acc/binary, Content/binary>>, text)
    end;
fold_lines([{_Indent, <<>>} | Rest], Acc, more_indented) ->
    fold_lines(Rest, <<Acc/binary, "\n\n">>, mi_first_break);
fold_lines([{Indent, Content} | Rest], Acc, more_indented) ->
    case is_more_indented(Indent, Content) of
        true -> fold_lines(Rest, <<Acc/binary, "\n", Content/binary>>, more_indented);
        false -> fold_lines(Rest, <<Acc/binary, "\n", Content/binary>>, text)
    end;
fold_lines([{_Indent, <<>>} | Rest], Acc, mi_first_break) ->
    fold_lines(Rest, <<Acc/binary, "\n">>, mi_break);
fold_lines([{Indent, Content} | Rest], Acc, mi_first_break) ->
    case is_more_indented(Indent, Content) of
        true -> fold_lines(Rest, <<Acc/binary, Content/binary>>, more_indented);
        false -> fold_lines(Rest, <<Acc/binary, Content/binary>>, text)
    end;
fold_lines([{_Indent, <<>>} | Rest], Acc, mi_break) ->
    fold_lines(Rest, <<Acc/binary, "\n">>, mi_break);
fold_lines([{Indent, Content} | Rest], Acc, mi_break) ->
    case is_more_indented(Indent, Content) of
        true -> fold_lines(Rest, <<Acc/binary, Content/binary>>, more_indented);
        false -> fold_lines(Rest, <<Acc/binary, Content/binary>>, text)
    end.

-spec format_content(style(), [{non_neg_integer(), binary()}], chomping()) -> binary().
format_content(literal, Lines, Chomping) ->
    format_literal(Lines, Chomping);
format_content(folded, Lines, Chomping) ->
    format_folded(Lines, Chomping).

-spec format_folded([{non_neg_integer(), binary()}], chomping()) -> binary().
format_folded(Lines, Chomping) ->
    Content = fold_lines(Lines),
    apply_chomping(Content, Chomping).

-spec format_literal([{non_neg_integer(), binary()}], chomping()) -> binary().
format_literal(Lines, Chomping) ->
    Content = join_lines_literal(Lines),
    apply_chomping(Content, Chomping).

-spec has_content_line([{non_neg_integer(), binary()}]) -> boolean().
has_content_line([]) ->
    false;
has_content_line([{_Indent, Content} | Rest]) ->
    case is_whitespace_only(Content) of
        true -> has_content_line(Rest);
        false -> true
    end.

-spec is_empty_or_whitespace(binary()) -> boolean().
is_empty_or_whitespace(<<>>) ->
    true;
is_empty_or_whitespace(<<C, Rest/binary>>) when C =:= $\s; C =:= $\t ->
    is_empty_or_whitespace(Rest);
is_empty_or_whitespace(_) ->
    false.

-spec is_more_indented(non_neg_integer(), binary()) -> boolean().
is_more_indented(Indent, _Content) when Indent > 0 -> true;
is_more_indented(_Indent, <<C, _/binary>>) when C =:= $\s; C =:= $\t -> true;
is_more_indented(_Indent, _Content) -> false.

-spec is_whitespace_only(binary()) -> boolean().
is_whitespace_only(<<>>) ->
    true;
is_whitespace_only(<<C, Rest/binary>>) when C =:= $\s; C =:= $\t ->
    is_whitespace_only(Rest);
is_whitespace_only(_) ->
    false.

-spec join_lines_literal([{non_neg_integer(), binary()}]) -> binary().
join_lines_literal([]) ->
    <<>>;
join_lines_literal(Lines) ->
    Parts = [
        case Content of
            <<>> -> <<"\n">>;
            _ -> <<Content/binary, "\n">>
        end
     || {_Indent, Content} <- Lines
    ],
    iolist_to_binary(Parts).

-spec next_line(binary()) -> {line, binary(), binary()} | eof.
next_line(<<>>) ->
    eof;
next_line(Bin) ->
    case binary:match(Bin, <<"\n">>) of
        {Pos, 1} ->
            Line = binary:part(Bin, 0, Pos),
            Rest = binary:part(Bin, Pos + 1, byte_size(Bin) - Pos - 1),
            {line, Line, Rest};
        nomatch ->
            {line, Bin, <<>>}
    end.

-spec parse_content(
    style(), non_neg_integer() | auto, chomping(), binary(), non_neg_integer(), boolean()
) ->
    {ok, binary(), binary()} | {error, parse_error()}.
parse_content(Style, IndentIndicator, Chomping, Bin, BaseIndent, AllowColumnZero) ->
    ContentIndent = determine_content_indent(IndentIndicator, Bin, BaseIndent, AllowColumnZero),
    case collect_content_lines(Bin, ContentIndent) of
        {ok, Lines, Rest} ->
            Content = format_content(Style, Lines, Chomping),
            {ok, Content, Rest};
        {error, _} = Err ->
            Err
    end.

-spec parse_header(binary()) ->
    {ok, style(), non_neg_integer() | auto, chomping(), binary()} | {error, parse_error()}.
parse_header(<<"|", Rest/binary>>) ->
    parse_header_modifiers(literal, Rest);
parse_header(<<">", Rest/binary>>) ->
    parse_header_modifiers(folded, Rest);
parse_header(_) ->
    {error, not_a_block_scalar}.

-spec parse_header_modifiers(style(), binary()) ->
    {ok, style(), non_neg_integer() | auto, chomping(), binary()} | {error, parse_error()}.
parse_header_modifiers(Style, Bin) ->
    {IndentIndicator, Chomping, Rest} = parse_modifiers(Bin, auto, clip),
    case skip_to_newline(Rest) of
        {ok, Rest2} ->
            {ok, Style, IndentIndicator, Chomping, Rest2};
        {error, Reason} ->
            {error, Reason}
    end.

-spec parse_modifiers(binary(), non_neg_integer() | auto, chomping()) ->
    {non_neg_integer() | auto, chomping(), binary()}.
parse_modifiers(<<C, Rest/binary>>, auto, Chomping) when C >= $1, C =< $9 ->
    parse_modifiers(Rest, C - $0, Chomping);
parse_modifiers(<<"-", Rest/binary>>, Indent, _Chomping) ->
    parse_modifiers(Rest, Indent, strip);
parse_modifiers(<<"+", Rest/binary>>, Indent, _Chomping) ->
    parse_modifiers(Rest, Indent, keep);
parse_modifiers(Rest, Indent, Chomping) ->
    {Indent, Chomping, Rest}.

-spec skip_comment_to_newline(binary()) -> {ok, binary()}.
skip_comment_to_newline(<<>>) ->
    {ok, <<>>};
skip_comment_to_newline(<<"\n", Rest/binary>>) ->
    {ok, Rest};
skip_comment_to_newline(<<"\r\n", Rest/binary>>) ->
    {ok, Rest};
skip_comment_to_newline(<<_, Rest/binary>>) ->
    skip_comment_to_newline(Rest).

-spec skip_to_newline(binary()) -> {ok, binary()} | {error, parse_error()}.
skip_to_newline(Bin) ->
    skip_to_newline(Bin, false).

-spec skip_to_newline(binary(), boolean()) -> {ok, binary()} | {error, parse_error()}.
skip_to_newline(<<>>, _SeenWhitespace) ->
    {ok, <<>>};
skip_to_newline(<<"\n", Rest/binary>>, _SeenWhitespace) ->
    {ok, Rest};
skip_to_newline(<<"\r\n", Rest/binary>>, _SeenWhitespace) ->
    {ok, Rest};
skip_to_newline(<<C, Rest/binary>>, _SeenWhitespace) when C =:= $\s; C =:= $\t ->
    skip_to_newline(Rest, true);
skip_to_newline(<<"#", Rest/binary>>, true) ->
    skip_comment_to_newline(Rest);
skip_to_newline(<<C, _/binary>>, _SeenWhitespace) ->
    {error, {unexpected_char_in_block_scalar_header, C}}.

-spec strip_n_leading_spaces(binary(), non_neg_integer()) -> binary().
strip_n_leading_spaces(Bin, 0) ->
    Bin;
strip_n_leading_spaces(<<$\s, Rest/binary>>, N) when N > 0 ->
    strip_n_leading_spaces(Rest, N - 1);
strip_n_leading_spaces(Bin, _N) ->
    Bin.

-spec strip_trailing(binary(), binary()) -> binary().
strip_trailing(Bin, Suffix) ->
    SuffixSize = byte_size(Suffix),
    BinSize = byte_size(Bin),
    case BinSize >= SuffixSize of
        true ->
            case binary:part(Bin, BinSize - SuffixSize, SuffixSize) of
                Suffix ->
                    strip_trailing(binary:part(Bin, 0, BinSize - SuffixSize), Suffix);
                _ ->
                    Bin
            end;
        false ->
            Bin
    end.

-spec strip_trailing_newlines(binary()) -> binary().
strip_trailing_newlines(Bin) ->
    strip_trailing(Bin, <<"\n">>).
