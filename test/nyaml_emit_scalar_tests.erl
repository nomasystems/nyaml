-module(nyaml_emit_scalar_tests).

-include_lib("eunit/include/eunit.hrl").

%% ============================================================
%% nyaml_emit_scalar Coverage Tests
%% ============================================================

emit_binary_default_context_test_() ->
    [
        %% emit_binary/1 emits plain scalars unchanged
        ?_assertEqual(<<"plain">>, nyaml_emit_scalar:emit_binary(<<"plain">>)),
        %% emit_binary/1 quotes strings that resolve to non-strings
        ?_assertEqual(<<"'true'">>, nyaml_emit_scalar:emit_binary(<<"true">>)),
        %% emit_binary/1 defaults to block context: flow indicators stay plain
        ?_assertEqual(<<"a, b">>, nyaml_emit_scalar:emit_binary(<<"a, b">>)),
        %% emit_binary/1 quotes a leading flow indicator in block context too
        ?_assertEqual(<<"'{brace}'">>, nyaml_emit_scalar:emit_binary(<<"{brace}">>))
    ].

del_control_char_test_() ->
    [
        %% DEL (0x7F) forces quoting
        ?_assertEqual(true, nyaml_emit_scalar:needs_quoting(<<"a", 16#7F, "b">>)),
        %% DEL cannot appear in single-quoted style, escapes as \x7F
        ?_assertEqual(<<"\"a\\x7Fb\"">>, nyaml_emit_scalar:emit(<<"a", 16#7F, "b">>)),
        %% DEL as the first byte
        ?_assertEqual(<<"\"\\x7Fx\"">>, nyaml_emit_scalar:emit(<<16#7F, "x">>))
    ].

double_quoted_named_escapes_test_() ->
    [
        %% Backslash escapes as \\ in double-quoted style
        ?_assertEqual(<<"\"a\\\\b\\nc\"">>, nyaml_emit_scalar:emit(<<"a\\b\nc">>)),
        %% Double quote escapes as \" in double-quoted style
        ?_assertEqual(<<"\"a\\\"b\\nc\"">>, nyaml_emit_scalar:emit(<<"a\"b\nc">>)),
        %% Tab escapes as \t when double quoting is forced by a newline
        ?_assertEqual(<<"\"a\\tb\\nc\"">>, nyaml_emit_scalar:emit(<<"a\tb\nc">>)),
        %% NUL escapes as \0
        ?_assertEqual(<<"\"a\\0b\"">>, nyaml_emit_scalar:emit(<<"a", 0, "b">>)),
        %% BEL escapes as \a
        ?_assertEqual(<<"\"a\\ab\"">>, nyaml_emit_scalar:emit(<<"a", 7, "b">>)),
        %% Backspace escapes as \b
        ?_assertEqual(<<"\"a\\bb\"">>, nyaml_emit_scalar:emit(<<"a", 8, "b">>)),
        %% Vertical tab escapes as \v
        ?_assertEqual(<<"\"a\\vb\"">>, nyaml_emit_scalar:emit(<<"a", 11, "b">>)),
        %% Form feed escapes as \f
        ?_assertEqual(<<"\"a\\fb\"">>, nyaml_emit_scalar:emit(<<"a", 12, "b">>)),
        %% Escape char escapes as \e
        ?_assertEqual(<<"\"a\\eb\"">>, nyaml_emit_scalar:emit(<<"a", 27, "b">>))
    ].

double_quoted_hex_escapes_test_() ->
    [
        %% Control chars without a named escape use \xNN with uppercase hex
        ?_assertEqual(<<"\"a\\x01b\"">>, nyaml_emit_scalar:emit(<<"a", 1, "b">>)),
        %% Unit separator (0x1F) uses two uppercase hex digits
        ?_assertEqual(<<"\"a\\x1Fb\"">>, nyaml_emit_scalar:emit(<<"a", 16#1F, "b">>)),
        %% SYN (0x16) escapes as \x16
        ?_assertEqual(<<"\"a\\x16b\"">>, nyaml_emit_scalar:emit(<<"a", 16#16, "b">>))
    ].

single_quoted_apostrophe_escape_test_() ->
    [
        %% Leading quote indicator forces quoting, apostrophes double inside
        ?_assertEqual(<<"'''quoted'''">>, nyaml_emit_scalar:emit(<<"'quoted'">>)),
        %% Hash indicator forces quoting, embedded apostrophe doubles
        ?_assertEqual(<<"'#it''s'">>, nyaml_emit_scalar:emit(<<"#it's">>)),
        %% Colon-space combo forces quoting, embedded apostrophe doubles
        ?_assertEqual(<<"'a: b''c'">>, nyaml_emit_scalar:emit(<<"a: b'c">>))
    ].

dash_indicator_test_() ->
    [
        %% A lone dash is a sequence entry indicator and needs quoting
        ?_assertEqual(true, nyaml_emit_scalar:needs_quoting(<<"-">>)),
        %% A lone dash is emitted single-quoted
        ?_assertEqual(<<"'-'">>, nyaml_emit_scalar:emit(<<"-">>)),
        %% Dash followed by space looks like a sequence entry
        ?_assertEqual(<<"'- item'">>, nyaml_emit_scalar:emit(<<"- item">>)),
        %% Dash followed by tab looks like a sequence entry
        ?_assertEqual(<<"'-\tx'">>, nyaml_emit_scalar:emit(<<"-\tx">>))
    ].

encode_public_api_test_() ->
    [
        %% Lone dash reaches the emitter through nyaml:encode/1
        ?_assertEqual({ok, <<"'-'\n">>}, nyaml:encode(<<"-">>)),
        %% NUL byte reaches double-quoted emission through nyaml:encode/1
        ?_assertEqual({ok, <<"\"a\\0b\"\n">>}, nyaml:encode(<<"a", 0, "b">>))
    ].

escape_roundtrip_test_() ->
    Values = [
        <<"a", 16#7F, "b">>,
        <<"a", 0, "b">>,
        <<"a", 1, "b">>,
        <<"a", 7, "b">>,
        <<"a", 8, "b">>,
        <<"a", 11, "b">>,
        <<"a", 12, "b">>,
        <<"a", 27, "b">>,
        <<"a\\b\nc">>,
        <<"a\"b\nc">>,
        <<"a\tb\nc">>,
        <<"'quoted'">>,
        <<"#it's">>,
        <<"a: b'c">>,
        <<"-">>,
        <<"- item">>
    ],
    [
        {
            iolist_to_binary(io_lib:format("~p", [V])),
            ?_assertEqual({ok, V}, nyaml:decode(nyaml_emit_scalar:emit(V)))
        }
     || V <- Values
    ].
