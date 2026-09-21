-module(nyaml_emit_scalar).

-moduledoc """
Scalar emission for YAML.

Emits scalar values (null, boolean, number, datetime, binary) as YAML text,
choosing plain, single-quoted, or double-quoted style based on content so
that the result round-trips through `nyaml:decode/1`.

A `{binary, Bytes}` value is byte data rather than a string, so it is written
as a `!!binary` node with base64 content.
""".

%%%-----------------------------------------------------------------------------
%% API EXPORTS
%%%-----------------------------------------------------------------------------
-export([
    emit/1,
    emit_binary/1,
    emit_binary/2,
    needs_quoting/1,
    needs_quoting/2
]).

%%%-----------------------------------------------------------------------------
%% TYPE EXPORTS
%%%-----------------------------------------------------------------------------
-export_type([
    context/0,
    scalar_value/0
]).

%%%-----------------------------------------------------------------------------
%% TYPES
%%%-----------------------------------------------------------------------------
-type scalar_value() ::
    null
    | boolean()
    | integer()
    | float()
    | infinity
    | negative_infinity
    | nan
    | calendar:datetime()
    | binary()
    | {binary, binary()}.

-type context() :: block | flow.

%%%-----------------------------------------------------------------------------
%% API FUNCTIONS
%%%-----------------------------------------------------------------------------

-doc """
Emits a scalar value as a YAML binary.

For binaries, automatically chooses plain, single-quoted, or double-quoted
style based on whether the content can be safely emitted unquoted in block
context. A `{binary, Bytes}` value takes the `!!binary` tag and base64 content.
""".
-spec emit(scalar_value()) -> binary().
emit(null) ->
    <<"null">>;
emit(true) ->
    <<"true">>;
emit(false) ->
    <<"false">>;
emit(infinity) ->
    <<".inf">>;
emit(negative_infinity) ->
    <<"-.inf">>;
emit(nan) ->
    <<".nan">>;
emit(I) when is_integer(I) ->
    integer_to_binary(I);
emit(F) when is_float(F) ->
    float_to_binary(F, [short]);
emit({{Y, Mo, D}, {H, Mi, S}} = DateTime) when
    is_integer(Y),
    is_integer(Mo),
    is_integer(D),
    is_integer(H),
    is_integer(Mi),
    is_integer(S)
->
    emit_datetime(DateTime);
emit({binary, <<>>}) ->
    <<"!!binary \"\"">>;
emit({binary, Bytes}) ->
    <<"!!binary ", (base64:encode(Bytes))/binary>>;
emit(Bin) when is_binary(Bin) ->
    emit_binary(Bin, block).

-doc """
Emits a binary as a YAML scalar in block context.
""".
-spec emit_binary(binary()) -> binary().
emit_binary(Bin) ->
    emit_binary(Bin, block).

-doc """
Emits a binary as a YAML scalar in the given context.

Flow context applies stricter quoting rules to avoid clashing with `,`, `[`,
`]`, `{`, and `}`.
""".
-spec emit_binary(binary(), context()) -> binary().
emit_binary(Bin, Context) ->
    case needs_quoting(Bin, Context) of
        false ->
            Bin;
        true ->
            case can_use_single_quoted(Bin) of
                true -> emit_single_quoted(Bin);
                false -> emit_double_quoted(Bin)
            end
    end.

-doc """
Returns whether a binary must be quoted to round-trip through the YAML parser
in block context.
""".
-spec needs_quoting(binary()) -> boolean().
needs_quoting(Bin) ->
    needs_quoting(Bin, block).

-doc """
Returns whether a binary must be quoted to round-trip through the YAML parser
in the given context.
""".
-spec needs_quoting(binary(), context()) -> boolean().
needs_quoting(<<>>, _Context) ->
    true;
needs_quoting(Bin, Context) ->
    starts_with_indicator(Bin) orelse
        starts_with_document_marker(Bin) orelse
        starts_with_bom(Bin) orelse
        has_leading_or_trailing_whitespace(Bin) orelse
        contains_indicator_combo(Bin, Context) orelse
        contains_control_char(Bin) orelse
        resolves_to_non_string(Bin).

%%%-----------------------------------------------------------------------------
%% INTERNAL FUNCTIONS
%%%-----------------------------------------------------------------------------

-spec can_use_single_quoted(binary()) -> boolean().
can_use_single_quoted(Bin) ->
    not has_non_single_quotable(Bin).
-spec contains_control_char(binary()) -> boolean().
contains_control_char(<<>>) ->
    false;
contains_control_char(<<C, _/binary>>) when C < 16#20 ->
    true;
contains_control_char(<<16#7F, _/binary>>) ->
    true;
contains_control_char(<<_, Rest/binary>>) ->
    contains_control_char(Rest).
-spec contains_indicator_combo(binary(), context()) -> boolean().
contains_indicator_combo(Bin, Context) ->
    binary:match(Bin, [<<": ">>, <<":\t">>, <<":\n">>, <<":\r">>, <<" #">>, <<"\t#">>]) =/=
        nomatch orelse
        ends_with_colon(Bin) orelse
        (Context =:= flow andalso
            binary:match(Bin, [<<",">>, <<"[">>, <<"]">>, <<"{">>, <<"}">>]) =/= nomatch).
-spec emit_datetime(calendar:datetime()) -> binary().
emit_datetime({{Y, Mo, D}, {H, Mi, S}}) ->
    iolist_to_binary(
        io_lib:format(
            "~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0B",
            [Y, Mo, D, H, Mi, S]
        )
    ).

-spec emit_double_quoted(binary()) -> binary().
emit_double_quoted(Bin) ->
    Body = escape_double(Bin, <<>>),
    <<$", Body/binary, $">>.
-spec emit_single_quoted(binary()) -> binary().
emit_single_quoted(Bin) ->
    Body = escape_single(Bin, <<>>),
    <<$', Body/binary, $'>>.

-spec ends_with_colon(binary()) -> boolean().
ends_with_colon(<<>>) ->
    false;
ends_with_colon(Bin) ->
    binary:last(Bin) =:= $:.
-spec escape_double(binary(), binary()) -> binary().
escape_double(<<>>, Acc) ->
    Acc;
escape_double(<<$\\, Rest/binary>>, Acc) ->
    escape_double(Rest, <<Acc/binary, "\\\\">>);
escape_double(<<$", Rest/binary>>, Acc) ->
    escape_double(Rest, <<Acc/binary, "\\\"">>);
escape_double(<<$\n, Rest/binary>>, Acc) ->
    escape_double(Rest, <<Acc/binary, "\\n">>);
escape_double(<<$\r, Rest/binary>>, Acc) ->
    escape_double(Rest, <<Acc/binary, "\\r">>);
escape_double(<<$\t, Rest/binary>>, Acc) ->
    escape_double(Rest, <<Acc/binary, "\\t">>);
escape_double(<<0, Rest/binary>>, Acc) ->
    escape_double(Rest, <<Acc/binary, "\\0">>);
escape_double(<<7, Rest/binary>>, Acc) ->
    escape_double(Rest, <<Acc/binary, "\\a">>);
escape_double(<<8, Rest/binary>>, Acc) ->
    escape_double(Rest, <<Acc/binary, "\\b">>);
escape_double(<<11, Rest/binary>>, Acc) ->
    escape_double(Rest, <<Acc/binary, "\\v">>);
escape_double(<<12, Rest/binary>>, Acc) ->
    escape_double(Rest, <<Acc/binary, "\\f">>);
escape_double(<<27, Rest/binary>>, Acc) ->
    escape_double(Rest, <<Acc/binary, "\\e">>);
escape_double(<<C, Rest/binary>>, Acc) when C < 16#20 ->
    Hex = list_to_binary(io_lib:format("\\x~2.16.0B", [C])),
    escape_double(Rest, <<Acc/binary, Hex/binary>>);
escape_double(<<16#7F, Rest/binary>>, Acc) ->
    escape_double(Rest, <<Acc/binary, "\\x7F">>);
escape_double(<<C, Rest/binary>>, Acc) ->
    escape_double(Rest, <<Acc/binary, C>>).
-spec escape_single(binary(), binary()) -> binary().
escape_single(<<>>, Acc) ->
    Acc;
escape_single(<<$', Rest/binary>>, Acc) ->
    escape_single(Rest, <<Acc/binary, "''">>);
escape_single(<<C, Rest/binary>>, Acc) ->
    escape_single(Rest, <<Acc/binary, C>>).

-spec has_leading_or_trailing_whitespace(binary()) -> boolean().
has_leading_or_trailing_whitespace(<<>>) ->
    false;
has_leading_or_trailing_whitespace(<<C, _/binary>>) when C =:= $\s; C =:= $\t ->
    true;
has_leading_or_trailing_whitespace(Bin) ->
    Last = binary:last(Bin),
    Last =:= $\s orelse Last =:= $\t.

-spec has_non_single_quotable(binary()) -> boolean().
has_non_single_quotable(<<>>) ->
    false;
has_non_single_quotable(<<$\t, Rest/binary>>) ->
    has_non_single_quotable(Rest);
has_non_single_quotable(<<C, _/binary>>) when C < 16#20 ->
    true;
has_non_single_quotable(<<16#7F, _/binary>>) ->
    true;
has_non_single_quotable(<<_, Rest/binary>>) ->
    has_non_single_quotable(Rest).
-spec resolves_to_non_string(binary()) -> boolean().
resolves_to_non_string(Bin) ->
    case nyaml_scalar:parse(Bin) of
        {ok, Bin} -> false;
        {ok, _Other} -> true
    end.
-spec starts_with_bom(binary()) -> boolean().
starts_with_bom(<<16#EF, 16#BB, 16#BF, _/binary>>) ->
    true;
starts_with_bom(_) ->
    false.
-spec starts_with_document_marker(binary()) -> boolean().
starts_with_document_marker(<<"---", _/binary>>) ->
    true;
starts_with_document_marker(<<"...", _/binary>>) ->
    true;
starts_with_document_marker(_) ->
    false.
-spec starts_with_indicator(binary()) -> boolean().
starts_with_indicator(<<C, _/binary>>) when
    C =:= $#;
    C =:= $&;
    C =:= $*;
    C =:= $!;
    C =:= $|;
    C =:= $>;
    C =:= $';
    C =:= $";
    C =:= $%;
    C =:= $@;
    C =:= $`;
    C =:= $?;
    C =:= $:;
    C =:= $,;
    C =:= $[;
    C =:= $];
    C =:= ${;
    C =:= $}
->
    true;
starts_with_indicator(<<$->>) ->
    true;
starts_with_indicator(<<$-, Next, _/binary>>) when
    Next =:= $\s;
    Next =:= $\t;
    Next =:= $\n;
    Next =:= $\r
->
    true;
starts_with_indicator(_) ->
    false.
