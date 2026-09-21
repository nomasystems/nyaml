-module(nyaml_scalar).

-moduledoc """
Scalar value parsing for YAML.

Handles null, booleans, numbers, and quoted strings with escape sequences.
""".

%%%-----------------------------------------------------------------------------
%% API EXPORTS
%%%-----------------------------------------------------------------------------
-export([
    parse/1,
    parse_key/1,
    parse_quoted/2,
    parse_quoted/3
]).

%%%-----------------------------------------------------------------------------
%% TYPE EXPORTS
%%%-----------------------------------------------------------------------------
-export_type([
    parse_error/0,
    quote_context/0,
    quote_type/0,
    scalar_value/0
]).

%%%-----------------------------------------------------------------------------
%% TYPES
%%%-----------------------------------------------------------------------------
-type scalar_value() ::
    null
    | boolean()
    | number()
    | binary().

-type quote_type() :: double | single.

-type quote_context() :: document_level | block_level.

-type parse_error() ::
    document_marker_in_quoted_string
    | not_a_quoted_string
    | tab_in_indentation
    | unindented_multiline_quoted_scalar
    | unterminated_double_quoted_string
    | unterminated_single_quoted_string
    | {invalid_escape_sequence, byte()}.

%%%-----------------------------------------------------------------------------
%% API FUNCTIONS
%%%-----------------------------------------------------------------------------

-doc """
Resolves a plain mapping key with the core schema.

An empty plain key resolves to `null`, the same resolution an empty plain
value gets.
""".
-spec parse_key(binary()) -> {ok, scalar_value()}.
parse_key(<<>>) ->
    {ok, null};
parse_key(Bin) ->
    parse(Bin).

-doc """
Parses a scalar value string into its appropriate Erlang representation.

Handles null, booleans, numbers, and falls back to string for unrecognized values.
""".
-spec parse(binary()) -> {ok, scalar_value()}.
parse(<<"null">>) ->
    {ok, null};
parse(<<"~">>) ->
    {ok, null};
parse(<<"true">>) ->
    {ok, true};
parse(<<"True">>) ->
    {ok, true};
parse(<<"TRUE">>) ->
    {ok, true};
parse(<<"false">>) ->
    {ok, false};
parse(<<"False">>) ->
    {ok, false};
parse(<<"FALSE">>) ->
    {ok, false};
parse(Bin) ->
    case parse_number(Bin) of
        {ok, Num} ->
            {ok, Num};
        error ->
            case nyaml_complex_scalar:try_parse(Bin) of
                {ok, Value} -> {ok, Value};
                {error, _} -> {ok, Bin}
            end
    end.

-doc """
Parses a quoted string at document level (column 0 allowed).
""".
-spec parse_quoted(binary(), quote_type()) ->
    {ok, binary(), Rest :: binary()} | {error, parse_error()}.
parse_quoted(Bin, QuoteType) ->
    parse_quoted(Bin, QuoteType, document_level).

-doc """
Parses a quoted string with context.

Context determines whether column 0 continuation is allowed:
- `document_level`: column 0 is allowed
- `block_level`: column 0 is not allowed
""".
-spec parse_quoted(binary(), quote_type(), quote_context()) ->
    {ok, binary(), Rest :: binary()} | {error, parse_error()}.
parse_quoted(<<"\"", Rest/binary>>, double, Context) ->
    parse_double_quoted(Rest, <<>>, Context);
parse_quoted(<<"'", Rest/binary>>, single, Context) ->
    parse_single_quoted(Rest, <<>>, Context);
parse_quoted(_, _, _) ->
    {error, not_a_quoted_string}.

%%%-----------------------------------------------------------------------------
%% INTERNAL FUNCTIONS
%%%-----------------------------------------------------------------------------

-spec all_hex([byte()]) -> boolean().
all_hex([]) ->
    true;
all_hex([C | Rest]) ->
    is_hex_digit(C) andalso all_hex(Rest).

-spec check_continuation_prefix(quote_context(), binary()) -> ok | {error, parse_error()}.
check_continuation_prefix(document_level, _Bin) ->
    ok;
check_continuation_prefix(block_level, Bin) ->
    continuation_line_prefix(Bin).

-spec continuation_line_prefix(binary()) -> ok | {error, parse_error()}.
continuation_line_prefix(<<>>) ->
    ok;
continuation_line_prefix(<<$\t, _/binary>>) ->
    {error, tab_in_indentation};
continuation_line_prefix(<<$\n, Rest/binary>>) ->
    continuation_line_prefix(Rest);
continuation_line_prefix(<<$\r, Rest/binary>>) ->
    continuation_line_prefix(Rest);
continuation_line_prefix(<<$\s, Rest/binary>>) ->
    continuation_line_indented(Rest);
continuation_line_prefix(_) ->
    {error, unindented_multiline_quoted_scalar}.

-spec continuation_line_indented(binary()) -> ok | {error, parse_error()}.
continuation_line_indented(<<C, Rest/binary>>) when C =:= $\s; C =:= $\t ->
    continuation_line_indented(Rest);
continuation_line_indented(<<$\n, Rest/binary>>) ->
    continuation_line_prefix(Rest);
continuation_line_indented(<<$\r, Rest/binary>>) ->
    continuation_line_prefix(Rest);
continuation_line_indented(_) ->
    ok.

-spec fold_double_quoted_line(binary(), binary(), quote_context()) ->
    {ok, binary(), binary()} | {error, parse_error()}.
fold_double_quoted_line(Rest, Acc, Context) ->
    case starts_with_doc_marker(Rest) of
        true ->
            {error, document_marker_in_quoted_string};
        false ->
            case check_continuation_prefix(Context, Rest) of
                {error, _} = Err ->
                    Err;
                ok ->
                    {Folded, Rest1} = fold_double_quoted_newline(Rest),
                    parse_double_quoted(Rest1, <<Acc/binary, Folded/binary>>, Context)
            end
    end.

-spec fold_double_quoted_newline(binary()) -> {binary(), binary()}.
fold_double_quoted_newline(Bin) ->
    fold_double_quoted_newline(Bin, 0).

-spec fold_double_quoted_newline(binary(), non_neg_integer()) -> {binary(), binary()}.
fold_double_quoted_newline(<<"\n", Rest/binary>>, Count) ->
    fold_double_quoted_newline(Rest, Count + 1);
fold_double_quoted_newline(<<"\r\n", Rest/binary>>, Count) ->
    fold_double_quoted_newline(Rest, Count + 1);
fold_double_quoted_newline(<<C, Rest/binary>>, Count) when C =:= $\s; C =:= $\t ->
    fold_double_quoted_newline(Rest, Count);
fold_double_quoted_newline(Rest, 0) ->
    {<<" ">>, Rest};
fold_double_quoted_newline(Rest, Count) ->
    Newlines = list_to_binary(lists:duplicate(Count, $\n)),
    {Newlines, Rest}.

-spec fold_single_quoted_line(binary(), binary(), quote_context()) ->
    {ok, binary(), binary()} | {error, parse_error()}.
fold_single_quoted_line(Rest, Acc, Context) ->
    case starts_with_doc_marker(Rest) of
        true ->
            {error, document_marker_in_quoted_string};
        false ->
            case check_continuation_prefix(Context, Rest) of
                {error, _} = Err ->
                    Err;
                ok ->
                    TrimmedAcc = strip_trailing_whitespace(Acc),
                    {Folded, Rest1} = fold_single_quoted_newline(Rest),
                    parse_single_quoted(Rest1, <<TrimmedAcc/binary, Folded/binary>>, Context)
            end
    end.

-spec fold_single_quoted_newline(binary()) -> {binary(), binary()}.
fold_single_quoted_newline(Bin) ->
    fold_single_quoted_newline(Bin, 0).

-spec fold_single_quoted_newline(binary(), non_neg_integer()) -> {binary(), binary()}.
fold_single_quoted_newline(<<"\n", Rest/binary>>, Count) ->
    fold_single_quoted_newline(Rest, Count + 1);
fold_single_quoted_newline(<<"\r\n", Rest/binary>>, Count) ->
    fold_single_quoted_newline(Rest, Count + 1);
fold_single_quoted_newline(<<C, Rest/binary>>, Count) when C =:= $\s; C =:= $\t ->
    fold_single_quoted_newline(Rest, Count);
fold_single_quoted_newline(Rest, 0) ->
    {<<" ">>, Rest};
fold_single_quoted_newline(Rest, Count) ->
    Newlines = list_to_binary(lists:duplicate(Count, $\n)),
    {Newlines, Rest}.

-spec is_hex_digit(byte()) -> boolean().
is_hex_digit(C) ->
    (C >= $0 andalso C =< $9) orelse
        (C >= $a andalso C =< $f) orelse
        (C >= $A andalso C =< $F).

-spec parse_byte_hex_escape(binary(), [byte()], binary(), binary(), quote_context()) ->
    {ok, binary(), binary()} | {error, parse_error()}.
parse_byte_hex_escape(Bin, Digits, Rest, Acc, Context) ->
    case all_hex(Digits) of
        true ->
            Byte = list_to_integer(Digits, 16),
            parse_double_quoted(Rest, <<Acc/binary, Byte>>, Context);
        false ->
            parse_double_quoted(Bin, <<Acc/binary, "\\">>, Context)
    end.

-spec parse_codepoint_hex_escape(binary(), [byte()], binary(), binary(), quote_context()) ->
    {ok, binary(), binary()} | {error, parse_error()}.
parse_codepoint_hex_escape(Bin, Digits, Rest, Acc, Context) ->
    case all_hex(Digits) of
        true ->
            Code = list_to_integer(Digits, 16),
            Utf8 = unicode:characters_to_binary([Code], utf8),
            parse_double_quoted(Rest, <<Acc/binary, Utf8/binary>>, Context);
        false ->
            parse_double_quoted(Bin, <<Acc/binary, "\\">>, Context)
    end.

-spec parse_double_quoted(binary(), binary(), quote_context()) ->
    {ok, binary(), binary()} | {error, parse_error()}.
parse_double_quoted(<<"\"", Rest/binary>>, Acc, _Context) ->
    {ok, Acc, Rest};
parse_double_quoted(<<"\\", Rest/binary>>, Acc, Context) ->
    parse_double_quoted_escape(Rest, Acc, Context);
parse_double_quoted(<<"\n", Rest/binary>>, Acc, Context) ->
    fold_double_quoted_line(Rest, Acc, Context);
parse_double_quoted(<<"\r\n", Rest/binary>>, Acc, Context) ->
    fold_double_quoted_line(Rest, Acc, Context);
parse_double_quoted(<<C, _/binary>> = Bin, Acc, Context) when C =:= $\s; C =:= $\t ->
    {Run, Rest} = white_space_run(Bin, 0),
    case Rest of
        <<"\n", _/binary>> ->
            parse_double_quoted(Rest, Acc, Context);
        <<"\r\n", _/binary>> ->
            parse_double_quoted(Rest, Acc, Context);
        _ ->
            White = binary_part(Bin, 0, Run),
            parse_double_quoted(Rest, <<Acc/binary, White/binary>>, Context)
    end;
parse_double_quoted(<<C, Rest/binary>>, Acc, Context) ->
    parse_double_quoted(Rest, <<Acc/binary, C>>, Context);
parse_double_quoted(<<>>, _, _) ->
    {error, unterminated_double_quoted_string}.

-spec parse_double_quoted_escape(binary(), binary(), quote_context()) ->
    {ok, binary(), binary()} | {error, parse_error()}.
parse_double_quoted_escape(<<"\"", Rest/binary>>, Acc, Context) ->
    parse_double_quoted(Rest, <<Acc/binary, "\"">>, Context);
parse_double_quoted_escape(<<"\\", Rest/binary>>, Acc, Context) ->
    parse_double_quoted(Rest, <<Acc/binary, "\\">>, Context);
parse_double_quoted_escape(<<"n", Rest/binary>>, Acc, Context) ->
    parse_double_quoted(Rest, <<Acc/binary, "\n">>, Context);
parse_double_quoted_escape(<<"r", Rest/binary>>, Acc, Context) ->
    parse_double_quoted(Rest, <<Acc/binary, "\r">>, Context);
parse_double_quoted_escape(<<"t", Rest/binary>>, Acc, Context) ->
    parse_double_quoted(Rest, <<Acc/binary, "\t">>, Context);
parse_double_quoted_escape(<<"\t", Rest/binary>>, Acc, Context) ->
    parse_double_quoted(Rest, <<Acc/binary, "\t">>, Context);
parse_double_quoted_escape(<<"0", Rest/binary>>, Acc, Context) ->
    parse_double_quoted(Rest, <<Acc/binary, 0>>, Context);
parse_double_quoted_escape(<<"a", Rest/binary>>, Acc, Context) ->
    parse_double_quoted(Rest, <<Acc/binary, 7>>, Context);
parse_double_quoted_escape(<<"b", Rest/binary>>, Acc, Context) ->
    parse_double_quoted(Rest, <<Acc/binary, 8>>, Context);
parse_double_quoted_escape(<<"e", Rest/binary>>, Acc, Context) ->
    parse_double_quoted(Rest, <<Acc/binary, 27>>, Context);
parse_double_quoted_escape(<<"f", Rest/binary>>, Acc, Context) ->
    parse_double_quoted(Rest, <<Acc/binary, 12>>, Context);
parse_double_quoted_escape(<<"v", Rest/binary>>, Acc, Context) ->
    parse_double_quoted(Rest, <<Acc/binary, 11>>, Context);
parse_double_quoted_escape(<<"/", Rest/binary>>, Acc, Context) ->
    parse_double_quoted(Rest, <<Acc/binary, "/">>, Context);
parse_double_quoted_escape(<<" ", Rest/binary>>, Acc, Context) ->
    parse_double_quoted(Rest, <<Acc/binary, " ">>, Context);
parse_double_quoted_escape(<<"N", Rest/binary>>, Acc, Context) ->
    Utf8 = unicode:characters_to_binary([16#0085], utf8),
    parse_double_quoted(Rest, <<Acc/binary, Utf8/binary>>, Context);
parse_double_quoted_escape(<<"_", Rest/binary>>, Acc, Context) ->
    Utf8 = unicode:characters_to_binary([16#00A0], utf8),
    parse_double_quoted(Rest, <<Acc/binary, Utf8/binary>>, Context);
parse_double_quoted_escape(<<"L", Rest/binary>>, Acc, Context) ->
    Utf8 = unicode:characters_to_binary([16#2028], utf8),
    parse_double_quoted(Rest, <<Acc/binary, Utf8/binary>>, Context);
parse_double_quoted_escape(<<"P", Rest/binary>>, Acc, Context) ->
    Utf8 = unicode:characters_to_binary([16#2029], utf8),
    parse_double_quoted(Rest, <<Acc/binary, Utf8/binary>>, Context);
parse_double_quoted_escape(<<"\n", Rest/binary>>, Acc, Context) ->
    Rest1 = skip_leading_whitespace(Rest),
    parse_double_quoted(Rest1, Acc, Context);
parse_double_quoted_escape(<<"x", A, B, Rest/binary>> = Bin, Acc, Context) ->
    parse_byte_hex_escape(Bin, [A, B], Rest, Acc, Context);
parse_double_quoted_escape(<<"u", H1, H2, H3, H4, Rest/binary>> = Bin, Acc, Context) ->
    parse_codepoint_hex_escape(Bin, [H1, H2, H3, H4], Rest, Acc, Context);
parse_double_quoted_escape(
    <<"U", H1, H2, H3, H4, H5, H6, H7, H8, Rest/binary>> = Bin, Acc, Context
) ->
    parse_codepoint_hex_escape(Bin, [H1, H2, H3, H4, H5, H6, H7, H8], Rest, Acc, Context);
parse_double_quoted_escape(<<C, _/binary>> = Bin, Acc, Context) when
    C =:= $x; C =:= $u; C =:= $U
->
    parse_double_quoted(Bin, <<Acc/binary, "\\">>, Context);
parse_double_quoted_escape(<<C, _/binary>>, _Acc, _Context) ->
    {error, {invalid_escape_sequence, C}};
parse_double_quoted_escape(<<>>, _Acc, _Context) ->
    {error, unterminated_double_quoted_string}.

-spec parse_number(binary()) -> {ok, number()} | error.
parse_number(Bin) ->
    try
        Int = binary_to_integer(Bin),
        {ok, Int}
    catch
        error:badarg ->
            try
                Float = binary_to_float(Bin),
                {ok, Float}
            catch
                error:badarg -> error
            end
    end.

-spec parse_single_quoted(binary(), binary(), quote_context()) ->
    {ok, binary(), binary()} | {error, parse_error()}.
parse_single_quoted(<<"''", Rest/binary>>, Acc, Context) ->
    parse_single_quoted(Rest, <<Acc/binary, "'">>, Context);
parse_single_quoted(<<"'", Rest/binary>>, Acc, _Context) ->
    {ok, Acc, Rest};
parse_single_quoted(<<"\n", Rest/binary>>, Acc, Context) ->
    fold_single_quoted_line(Rest, Acc, Context);
parse_single_quoted(<<"\r\n", Rest/binary>>, Acc, Context) ->
    fold_single_quoted_line(Rest, Acc, Context);
parse_single_quoted(<<C, Rest/binary>>, Acc, Context) ->
    parse_single_quoted(Rest, <<Acc/binary, C>>, Context);
parse_single_quoted(<<>>, _, _) ->
    {error, unterminated_single_quoted_string}.

-spec skip_leading_whitespace(binary()) -> binary().
skip_leading_whitespace(<<C, Rest/binary>>) when C =:= $\s; C =:= $\t ->
    skip_leading_whitespace(Rest);
skip_leading_whitespace(Bin) ->
    Bin.

-spec starts_with_doc_marker(binary()) -> boolean().
starts_with_doc_marker(<<"---">>) -> true;
starts_with_doc_marker(<<"---\n", _/binary>>) -> true;
starts_with_doc_marker(<<"---\r\n", _/binary>>) -> true;
starts_with_doc_marker(<<"--- ", _/binary>>) -> true;
starts_with_doc_marker(<<"---\t", _/binary>>) -> true;
starts_with_doc_marker(<<"...">>) -> true;
starts_with_doc_marker(<<"...\n", _/binary>>) -> true;
starts_with_doc_marker(<<"...\r\n", _/binary>>) -> true;
starts_with_doc_marker(<<"... ", _/binary>>) -> true;
starts_with_doc_marker(<<"...\t", _/binary>>) -> true;
starts_with_doc_marker(_) -> false.

-spec strip_trailing_whitespace(binary()) -> binary().
strip_trailing_whitespace(<<>>) ->
    <<>>;
strip_trailing_whitespace(Bin) ->
    strip_trailing_whitespace_rev(Bin, byte_size(Bin) - 1).

-spec strip_trailing_whitespace_rev(binary(), integer()) -> binary().
strip_trailing_whitespace_rev(_Bin, -1) ->
    <<>>;
strip_trailing_whitespace_rev(Bin, Pos) ->
    case binary:at(Bin, Pos) of
        C when C =:= $\s; C =:= $\t ->
            strip_trailing_whitespace_rev(Bin, Pos - 1);
        _ ->
            binary:part(Bin, 0, Pos + 1)
    end.

-spec white_space_run(binary(), non_neg_integer()) -> {non_neg_integer(), binary()}.
white_space_run(<<C, Rest/binary>>, Count) when C =:= $\s; C =:= $\t ->
    white_space_run(Rest, Count + 1);
white_space_run(Bin, Count) ->
    {Count, Bin}.
