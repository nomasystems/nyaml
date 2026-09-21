-module(nyaml_complex_scalar).

-moduledoc """
Support for complex scalar types in YAML.

Handles ISO8601 timestamps, hex/octal integers, infinity, NaN, scientific
notation, and signed numbers. It also decodes the base64 content of a
`!!binary` node.
""".

%%%-----------------------------------------------------------------------------
%% API EXPORTS
%%%-----------------------------------------------------------------------------
-export([
    decode_base64/1,
    try_parse/1
]).

%%%-----------------------------------------------------------------------------
%% TYPE EXPORTS
%%%-----------------------------------------------------------------------------
-export_type([
    base64_error/0,
    complex_scalar/0
]).

%%%-----------------------------------------------------------------------------
%% TYPES
%%%-----------------------------------------------------------------------------
-type base64_error() :: {invalid_base64, binary()}.

-type complex_scalar() :: integer() | float() | calendar:datetime() | binary().

%%%-----------------------------------------------------------------------------
%% API FUNCTIONS
%%%-----------------------------------------------------------------------------

-doc """
Decodes the content of a `!!binary` node into its bytes.

The "Various Explicit Tags" example of the "Tags" section writes the type as a
block scalar, so its content carries line breaks and leading spaces. Every
space, tab, carriage return, and line feed is removed before the decode.

`base64:decode/1` raises on content that is not base64, so the raise becomes
`{error, {invalid_base64, Content}}`.
""".
-spec decode_base64(binary()) -> {ok, binary()} | {error, base64_error()}.
decode_base64(Content) ->
    try base64:decode(strip_base64_whitespace(Content)) of
        Bytes -> {ok, Bytes}
    catch
        error:_ -> {error, {invalid_base64, Content}}
    end.

-doc """
Attempts to parse a binary as a complex scalar type.

Handles ISO8601 timestamps, hex (0x), octal (0o), infinity, NaN, scientific
notation, and signed numbers.
""".
-spec try_parse(binary()) -> {ok, complex_scalar()} | {error, not_complex_scalar}.
try_parse(
    <<Y1, Y2, Y3, Y4, $-, M1, M2, $-, D1, D2, $T, H1, H2, $:, Min1, Min2, $:, S1, S2, _Rest/binary>>
) when
    Y1 >= $0,
    Y1 =< $9,
    Y2 >= $0,
    Y2 =< $9,
    Y3 >= $0,
    Y3 =< $9,
    Y4 >= $0,
    Y4 =< $9,
    M1 >= $0,
    M1 =< $9,
    M2 >= $0,
    M2 =< $9,
    D1 >= $0,
    D1 =< $9,
    D2 >= $0,
    D2 =< $9,
    H1 >= $0,
    H1 =< $9,
    H2 >= $0,
    H2 =< $9,
    Min1 >= $0,
    Min1 =< $9,
    Min2 >= $0,
    Min2 =< $9,
    S1 >= $0,
    S1 =< $9,
    S2 >= $0,
    S2 =< $9
->
    try
        Year = list_to_integer([Y1, Y2, Y3, Y4]),
        Month = list_to_integer([M1, M2]),
        Day = list_to_integer([D1, D2]),
        Hour = list_to_integer([H1, H2]),
        Minute = list_to_integer([Min1, Min2]),
        Second = list_to_integer([S1, S2]),
        case calendar:valid_date(Year, Month, Day) of
            true when
                Hour >= 0,
                Hour =< 23,
                Minute >= 0,
                Minute =< 59,
                Second >= 0,
                Second =< 59
            ->
                {ok, {{Year, Month, Day}, {Hour, Minute, Second}}};
            _ ->
                {error, not_complex_scalar}
        end
    catch
        error:badarg -> {error, not_complex_scalar}
    end;
try_parse(<<"0x", Hex/binary>>) ->
    try
        {ok, binary_to_integer(Hex, 16)}
    catch
        error:badarg -> {error, not_complex_scalar}
    end;
try_parse(<<"0o", Oct/binary>>) ->
    try
        {ok, binary_to_integer(Oct, 8)}
    catch
        error:badarg -> {error, not_complex_scalar}
    end;
try_parse(<<".inf">>) ->
    {ok, infinity};
try_parse(<<"+.inf">>) ->
    {ok, infinity};
try_parse(<<"-.inf">>) ->
    {ok, negative_infinity};
try_parse(<<".NaN">>) ->
    {ok, nan};
try_parse(<<".nan">>) ->
    {ok, nan};
try_parse(<<"+", Rest/binary>>) ->
    try_parse_signed_number(Rest);
try_parse(<<".", Rest/binary>>) ->
    try_parse_leading_dot_float(Rest, <<>>);
try_parse(<<"-.", Rest/binary>>) ->
    try_parse_leading_dot_float(Rest, <<"-">>);
try_parse(Bin) ->
    case try_parse_scientific(Bin) of
        {ok, _} = Result -> Result;
        error -> {error, not_complex_scalar}
    end.

%%%-----------------------------------------------------------------------------
%% INTERNAL FUNCTIONS
%%%-----------------------------------------------------------------------------

-spec parse_exponent(binary()) -> integer().
parse_exponent(<<"+", Rest/binary>>) ->
    binary_to_integer(Rest);
parse_exponent(Bin) ->
    binary_to_integer(Bin).

-spec parse_mantissa(binary()) -> float().
parse_mantissa(<<".", Rest/binary>>) ->
    binary_to_float(<<"0.", Rest/binary>>);
parse_mantissa(<<"-.", Rest/binary>>) ->
    binary_to_float(<<"-0.", Rest/binary>>);
parse_mantissa(<<"+.", Rest/binary>>) ->
    binary_to_float(<<"0.", Rest/binary>>);
parse_mantissa(<<"+", Rest/binary>>) ->
    case binary:match(Rest, <<".">>) of
        nomatch -> float(binary_to_integer(Rest));
        _ -> binary_to_float(Rest)
    end;
parse_mantissa(Bin) ->
    case binary:match(Bin, <<".">>) of
        nomatch -> float(binary_to_integer(Bin));
        _ -> binary_to_float(Bin)
    end.

-spec parse_scientific_parts(binary(), binary()) -> {ok, float()} | error.
parse_scientific_parts(<<>>, _) ->
    error;
parse_scientific_parts(_, <<>>) ->
    error;
parse_scientific_parts(Mantissa, Exponent) ->
    try
        MantissaVal = parse_mantissa(Mantissa),
        ExponentVal = parse_exponent(Exponent),
        {ok, MantissaVal * math:pow(10, ExponentVal)}
    catch
        error:badarg -> error
    end.

-spec strip_base64_whitespace(binary()) -> binary().
strip_base64_whitespace(Content) ->
    case binary:match(Content, [<<" ">>, <<"\t">>, <<"\r">>, <<"\n">>]) of
        nomatch ->
            Content;
        _Found ->
            <<<<C>> || <<C>> <= Content, C =/= $\s, C =/= $\t, C =/= $\r, C =/= $\n>>
    end.

-spec try_parse_leading_dot_float(binary(), binary()) ->
    {ok, float()} | {error, not_complex_scalar}.
try_parse_leading_dot_float(<<>>, _Sign) ->
    {error, not_complex_scalar};
try_parse_leading_dot_float(Digits, Sign) ->
    FloatBin = <<Sign/binary, "0.", Digits/binary>>,
    try
        {ok, binary_to_float(FloatBin)}
    catch
        error:badarg ->
            case try_parse_scientific(FloatBin) of
                {ok, _} = Result -> Result;
                error -> {error, not_complex_scalar}
            end
    end.

-spec try_parse_scientific(binary()) -> {ok, float()} | error.
try_parse_scientific(Bin) ->
    case binary:match(Bin, [<<"e">>, <<"E">>]) of
        nomatch ->
            error;
        {Pos, 1} ->
            Mantissa = binary:part(Bin, 0, Pos),
            Exponent = binary:part(Bin, Pos + 1, byte_size(Bin) - Pos - 1),
            parse_scientific_parts(Mantissa, Exponent)
    end.

-spec try_parse_signed_number(binary()) -> {ok, complex_scalar()} | {error, not_complex_scalar}.
try_parse_signed_number(<<>>) ->
    {error, not_complex_scalar};
try_parse_signed_number(<<".", Rest/binary>>) ->
    try_parse_leading_dot_float(Rest, <<>>);
try_parse_signed_number(Bin) ->
    try
        {ok, binary_to_integer(Bin)}
    catch
        error:badarg ->
            try
                {ok, binary_to_float(Bin)}
            catch
                error:badarg ->
                    case try_parse_scientific(Bin) of
                        {ok, _} = Result -> Result;
                        error -> {error, not_complex_scalar}
                    end
            end
    end.
