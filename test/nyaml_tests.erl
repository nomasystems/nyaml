-module(nyaml_tests).

-include_lib("eunit/include/eunit.hrl").

%% ============================================================
%% nyaml_scalar Module Tests
%% ============================================================

nyaml_scalar_parse_test_() ->
    [
        ?_assertEqual({ok, null}, nyaml_scalar:parse(<<"null">>)),
        ?_assertEqual({ok, null}, nyaml_scalar:parse(<<"~">>)),
        ?_assertEqual({ok, true}, nyaml_scalar:parse(<<"true">>)),
        ?_assertEqual({ok, true}, nyaml_scalar:parse(<<"True">>)),
        ?_assertEqual({ok, true}, nyaml_scalar:parse(<<"TRUE">>)),
        ?_assertEqual({ok, false}, nyaml_scalar:parse(<<"false">>)),
        ?_assertEqual({ok, false}, nyaml_scalar:parse(<<"False">>)),
        ?_assertEqual({ok, false}, nyaml_scalar:parse(<<"FALSE">>)),
        ?_assertEqual({ok, 123}, nyaml_scalar:parse(<<"123">>)),
        ?_assertEqual({ok, -42}, nyaml_scalar:parse(<<"-42">>)),
        ?_assertEqual({ok, 3.14}, nyaml_scalar:parse(<<"3.14">>)),
        ?_assertEqual({ok, <<"simple string">>}, nyaml_scalar:parse(<<"simple string">>))
    ].

nyaml_scalar_quoted_test_() ->
    [
        ?_assertEqual(
            {ok, <<"simple">>, <<>>}, nyaml_scalar:parse_quoted(<<"\"simple\"">>, double)
        ),
        ?_assertEqual(
            {ok, <<"with\nnewline">>, <<>>},
            nyaml_scalar:parse_quoted(<<"\"with\\nnewline\"">>, double)
        ),
        ?_assertEqual(
            {ok, <<"with\ttab">>, <<>>}, nyaml_scalar:parse_quoted(<<"\"with\\ttab\"">>, double)
        ),
        ?_assertEqual(
            {ok, <<"with\\backslash">>, <<>>},
            nyaml_scalar:parse_quoted(<<"\"with\\\\backslash\"">>, double)
        ),
        ?_assertEqual(
            {ok, <<"with\"quote">>, <<>>},
            nyaml_scalar:parse_quoted(<<"\"with\\\"quote\"">>, double)
        ),
        ?_assertEqual(
            {ok, <<"unicode:", 226, 152, 131>>, <<>>},
            nyaml_scalar:parse_quoted(<<"\"unicode:\\u2603\"">>, double)
        ),
        ?_assertEqual({ok, <<"single">>, <<>>}, nyaml_scalar:parse_quoted(<<"'single'">>, single)),
        ?_assertEqual(
            {ok, <<"with'quote">>, <<>>}, nyaml_scalar:parse_quoted(<<"'with''quote'">>, single)
        ),
        ?_assertEqual(
            {error, unterminated_double_quoted_string},
            nyaml_scalar:parse_quoted(<<"\"unclosed">>, double)
        ),
        ?_assertEqual(
            {error, unterminated_single_quoted_string},
            nyaml_scalar:parse_quoted(<<"'unclosed">>, single)
        ),
        ?_assertEqual(
            {error, not_a_quoted_string}, nyaml_scalar:parse_quoted(<<"not quoted">>, double)
        ),
        ?_assertEqual(
            {error, {invalid_escape_sequence, $q}},
            nyaml_scalar:parse_quoted(<<"\"\\q\"">>, double)
        )
    ].

nyaml_scalar_multiline_quoted_test_() ->
    [
        ?_assertEqual(
            {ok, <<"line1 line2">>, <<>>},
            nyaml_scalar:parse_quoted(<<"\"line1\n  line2\"">>, double)
        ),
        ?_assertEqual(
            {ok, <<"line1 line2">>, <<>>},
            nyaml_scalar:parse_quoted(<<"'line1\n  line2'">>, single)
        ),
        ?_assertEqual(
            {ok, <<"line1\nline2">>, <<>>},
            nyaml_scalar:parse_quoted(<<"\"line1\n\n  line2\"">>, double)
        ),
        ?_assertEqual(
            {ok, <<"line1\n\nline2">>, <<>>},
            nyaml_scalar:parse_quoted(<<"\"line1\n\n\n  line2\"">>, double)
        ),
        ?_assertEqual(
            {ok, <<"line1 line2">>, <<>>},
            nyaml_scalar:parse_quoted(<<"\"line1\r\n  line2\"">>, double)
        ),
        ?_assertEqual(
            {ok, <<"line1 line2">>, <<>>},
            nyaml_scalar:parse_quoted(<<"'line1\r\n  line2'">>, single)
        ),
        ?_assertEqual(
            {ok, <<"line1line2">>, <<>>},
            nyaml_scalar:parse_quoted(<<"\"line1\\\n  line2\"">>, double)
        ),
        %% "Escaped Characters" makes the escaped space content, and the fold
        %% adds a space of its own
        ?_assertEqual(
            {ok, <<"line1  line2">>, <<>>},
            nyaml_scalar:parse_quoted(<<"\"line1\\ \n  line2\"">>, double)
        ),
        %% "Escaped Characters" gives ns-esc-horizontal-tab ::= 't' | x09, so this
        %% is the tab escape and a fold, never a line continuation
        ?_assertEqual(
            {ok, <<"line1\t line2">>, <<>>},
            nyaml_scalar:parse_quoted(<<"\"line1\\\t\n  line2\"">>, double)
        )
    ].

nyaml_scalar_block_level_context_test_() ->
    [
        ?_assertEqual(
            {ok, <<"value">>, <<>>},
            nyaml_scalar:parse_quoted(<<"\"value\"">>, double, block_level)
        ),
        ?_assertEqual(
            {ok, <<"line1 line2">>, <<>>},
            nyaml_scalar:parse_quoted(<<"\"line1\n  line2\"">>, double, block_level)
        ),
        ?_assertEqual(
            {error, unindented_multiline_quoted_scalar},
            nyaml_scalar:parse_quoted(<<"\"line1\na\"">>, double, block_level)
        ),
        ?_assertEqual(
            {error, unindented_multiline_quoted_scalar},
            nyaml_scalar:parse_quoted(<<"'line1\na'">>, single, block_level)
        ),
        ?_assertEqual(
            {ok, <<"line1 line2">>, <<>>},
            nyaml_scalar:parse_quoted(<<"'line1\r\n  line2'">>, single, block_level)
        )
    ].

nyaml_scalar_doc_marker_test_() ->
    [
        ?_assertEqual(
            {error, document_marker_in_quoted_string},
            nyaml_scalar:parse_quoted(<<"\"line1\n--- rest\"">>, double)
        ),
        ?_assertEqual(
            {error, document_marker_in_quoted_string},
            nyaml_scalar:parse_quoted(<<"'line1\n... rest'">>, single)
        ),
        ?_assertEqual(
            {error, document_marker_in_quoted_string},
            nyaml_scalar:parse_quoted(<<"\"line1\n---\trest\"">>, double)
        ),
        ?_assertEqual(
            {error, document_marker_in_quoted_string},
            nyaml_scalar:parse_quoted(<<"\"line1\n---\nrest\"">>, double)
        ),
        ?_assertEqual(
            {error, document_marker_in_quoted_string},
            nyaml_scalar:parse_quoted(<<"\"line1\r\n--- rest\"">>, double)
        ),
        ?_assertEqual(
            {error, document_marker_in_quoted_string},
            nyaml_scalar:parse_quoted(<<"'line1\r\n...\nrest'">>, single)
        )
    ].

nyaml_scalar_escape_sequences_test_() ->
    [
        ?_assertEqual({ok, <<0>>, <<>>}, nyaml_scalar:parse_quoted(<<"\"\\0\"">>, double)),
        ?_assertEqual({ok, <<7>>, <<>>}, nyaml_scalar:parse_quoted(<<"\"\\a\"">>, double)),
        ?_assertEqual({ok, <<8>>, <<>>}, nyaml_scalar:parse_quoted(<<"\"\\b\"">>, double)),
        ?_assertEqual({ok, <<27>>, <<>>}, nyaml_scalar:parse_quoted(<<"\"\\e\"">>, double)),
        ?_assertEqual({ok, <<12>>, <<>>}, nyaml_scalar:parse_quoted(<<"\"\\f\"">>, double)),
        ?_assertEqual({ok, <<11>>, <<>>}, nyaml_scalar:parse_quoted(<<"\"\\v\"">>, double)),
        ?_assertEqual({ok, <<"/">>, <<>>}, nyaml_scalar:parse_quoted(<<"\"\\/\"">>, double)),
        ?_assertEqual({ok, <<" ">>, <<>>}, nyaml_scalar:parse_quoted(<<"\"\\ \"">>, double)),
        ?_assertEqual({ok, <<"\r">>, <<>>}, nyaml_scalar:parse_quoted(<<"\"\\r\"">>, double)),
        ?_assertEqual({ok, <<65>>, <<>>}, nyaml_scalar:parse_quoted(<<"\"\\x41\"">>, double)),
        ?_assertEqual(
            {ok, <<195, 169>>, <<>>}, nyaml_scalar:parse_quoted(<<"\"\\u00e9\"">>, double)
        ),
        ?_assertEqual(
            {ok, <<240, 159, 152, 128>>, <<>>},
            nyaml_scalar:parse_quoted(<<"\"\\U0001F600\"">>, double)
        ),
        ?_assertEqual({ok, <<194, 133>>, <<>>}, nyaml_scalar:parse_quoted(<<"\"\\N\"">>, double)),
        ?_assertEqual({ok, <<194, 160>>, <<>>}, nyaml_scalar:parse_quoted(<<"\"\\_\"">>, double)),
        ?_assertEqual(
            {ok, <<226, 128, 168>>, <<>>}, nyaml_scalar:parse_quoted(<<"\"\\L\"">>, double)
        ),
        ?_assertEqual(
            {ok, <<226, 128, 169>>, <<>>}, nyaml_scalar:parse_quoted(<<"\"\\P\"">>, double)
        )
    ].

nyaml_scalar_escaped_tab_test_() ->
    [
        %% "Escaped Characters" gives ns-esc-horizontal-tab ::= 't' | x09, KH5V/00
        ?_assertEqual({ok, <<"a\tb">>}, nyaml:decode(<<"\"a\\tb\"">>)),
        %% "Escaped Characters" spells the same escape with a tab, KH5V/01
        ?_assertEqual({ok, <<"a\tb">>}, nyaml:decode(<<"\"a\\\tb\"">>)),
        %% "Double-Quoted Style" keeps a bare tab inside a line, KH5V/02
        ?_assertEqual({ok, <<"a\tb">>}, nyaml:decode(<<"\"a\tb\"">>)),
        %% "Escaped Characters" forces a leading tab into the content, 3RLN/00
        ?_assertEqual({ok, <<"a \tb">>}, nyaml:decode(<<"\"a\n  \\tb\"">>)),
        %% the same leading tab, spelled with a tab, 3RLN/01
        ?_assertEqual({ok, <<"a \tb">>}, nyaml:decode(<<"\"a\n  \\\tb\"">>)),
        %% "Flow Folding" discards the tab that opens a continuation line, 3RLN/02
        ?_assertEqual({ok, <<"a b">>}, nyaml:decode(<<"\"a\n  \tb\"">>)),
        %% "Escaped Characters" keeps what follows the escape, 3RLN/03 and 3RLN/04
        ?_assertEqual({ok, <<"a \t  b">>}, nyaml:decode(<<"\"a\n  \\t  b\"">>)),
        ?_assertEqual({ok, <<"a \t  b">>}, nyaml:decode(<<"\"a\n  \\\t  b\"">>)),
        %% "Escaped Characters" has no dot escape, 55WF
        ?_assertEqual({error, {invalid_escape_sequence, $.}}, nyaml:decode(<<"\"\\.\"">>)),
        %% "Escaped Characters" has no apostrophe escape, HRE5
        ?_assertEqual(
            {error, {invalid_escape_sequence, $'}},
            nyaml:decode(<<"double: \"quoted \\' scalar\"">>)
        )
    ].

nyaml_scalar_fold_keeps_what_an_escape_produced_test_() ->
    [
        %% "Flow Folding" discards the source tab before the break, DE56/04
        ?_assertEqual({ok, <<"a b">>}, nyaml:decode(<<"\"a\t\n  b\"">>)),
        %% and the source spaces that follow it, DE56/05
        ?_assertEqual({ok, <<"a b">>}, nyaml:decode(<<"\"a\t  \n  b\"">>)),
        %% "Escaped Characters" makes the escaped tab content, DE56/00
        ?_assertEqual({ok, <<"a\t b">>}, nyaml:decode(<<"\"a\\t\n  b\"">>)),
        %% the source spaces after it are still presentation, DE56/01
        ?_assertEqual({ok, <<"a\t b">>}, nyaml:decode(<<"\"a\\t  \n  b\"">>)),
        %% the same escape spelled with a tab, DE56/02
        ?_assertEqual({ok, <<"a\t b">>}, nyaml:decode(<<"\"a\\\t\n  b\"">>)),
        %% and with source spaces after it, DE56/03
        ?_assertEqual({ok, <<"a\t b">>}, nyaml:decode(<<"\"a\\\t  \n  b\"">>)),
        %% "Escaped Characters" makes the escaped space content too
        ?_assertEqual({ok, <<"a  b">>}, nyaml:decode(<<"\"a\\ \n  b\"">>)),
        %% "Double-Quoted Style" preserves the white space before an escaped break, NP9H
        ?_assertEqual({ok, <<"a\t b">>}, nyaml:decode(<<"\"a\t\\\n  \\ b\"">>)),
        %% "Double Quoted Lines" keeps the white space before the closing quote
        ?_assertEqual({ok, <<"a  ">>}, nyaml:decode(<<"\"a  \"">>))
    ].

%% ============================================================
%% nyaml_complex_scalar Module Tests
%% ============================================================

nyaml_complex_scalar_test_() ->
    [
        ?_assertEqual(
            {ok, {{2022, 5, 12}, {15, 30, 0}}},
            nyaml_complex_scalar:try_parse(<<"2022-05-12T15:30:00Z">>)
        ),
        ?_assertEqual({ok, 255}, nyaml_complex_scalar:try_parse(<<"0xFF">>)),
        ?_assertEqual({ok, 255}, nyaml_complex_scalar:try_parse(<<"0xff">>)),
        ?_assertEqual({ok, 83}, nyaml_complex_scalar:try_parse(<<"0o123">>)),
        ?_assertEqual({ok, 8}, nyaml_complex_scalar:try_parse(<<"0o10">>)),
        ?_assertEqual({ok, infinity}, nyaml_complex_scalar:try_parse(<<".inf">>)),
        ?_assertEqual({ok, infinity}, nyaml_complex_scalar:try_parse(<<"+.inf">>)),
        ?_assertEqual({ok, negative_infinity}, nyaml_complex_scalar:try_parse(<<"-.inf">>)),
        ?_assertEqual({ok, nan}, nyaml_complex_scalar:try_parse(<<".NaN">>)),
        ?_assertEqual({ok, nan}, nyaml_complex_scalar:try_parse(<<".nan">>)),
        ?_assertEqual({ok, 42}, nyaml_complex_scalar:try_parse(<<"+42">>)),
        ?_assertEqual({ok, 3.14}, nyaml_complex_scalar:try_parse(<<"+3.14">>)),
        ?_assertEqual({error, not_complex_scalar}, nyaml_complex_scalar:try_parse(<<"+">>)),
        ?_assertEqual({ok, 0.5}, nyaml_complex_scalar:try_parse(<<".5">>)),
        ?_assertEqual({ok, -0.25}, nyaml_complex_scalar:try_parse(<<"-.25">>)),
        ?_assertEqual({ok, 0.75}, nyaml_complex_scalar:try_parse(<<"+.75">>)),
        ?_assertEqual({error, not_complex_scalar}, nyaml_complex_scalar:try_parse(<<".">>)),
        ?_assertEqual({error, not_complex_scalar}, nyaml_complex_scalar:try_parse(<<"-.">>)),
        ?_assertEqual({ok, 1.5e10}, nyaml_complex_scalar:try_parse(<<"1.5e10">>)),
        ?_assertEqual({ok, 5.0e3}, nyaml_complex_scalar:try_parse(<<"5e3">>)),
        ?_assertEqual({ok, 50.0}, nyaml_complex_scalar:try_parse(<<".5e2">>)),
        ?_assertMatch({ok, _}, nyaml_complex_scalar:try_parse(<<"2.3E-4">>)),
        ?_assertMatch({ok, _}, nyaml_complex_scalar:try_parse(<<"1.5e+10">>)),
        ?_assertEqual(
            {error, not_complex_scalar}, nyaml_complex_scalar:try_parse(<<"2023-13-01T10:30:00Z">>)
        ),
        ?_assertEqual(
            {error, not_complex_scalar}, nyaml_complex_scalar:try_parse(<<"2023-01-32T10:30:00Z">>)
        ),
        ?_assertEqual(
            {error, not_complex_scalar}, nyaml_complex_scalar:try_parse(<<"2023-01-15T25:30:00Z">>)
        ),
        ?_assertEqual(
            {error, not_complex_scalar}, nyaml_complex_scalar:try_parse(<<"regular string">>)
        ),
        ?_assertEqual({error, not_complex_scalar}, nyaml_complex_scalar:try_parse(<<"0xinvalid">>)),
        ?_assertEqual({error, not_complex_scalar}, nyaml_complex_scalar:try_parse(<<"0o999">>))
    ].

%% ============================================================
%% nyaml_flow Module Tests
%% ============================================================

nyaml_flow_sequence_test_() ->
    Ctx = nyaml_parser:new_ctx(),
    [
        ?_assertMatch({ok, [], <<>>, _}, nyaml_flow:parse_sequence(<<"[]">>, Ctx)),
        ?_assertMatch({ok, [1, 2, 3], <<>>, _}, nyaml_flow:parse_sequence(<<"[1, 2, 3]">>, Ctx)),
        ?_assertMatch(
            {ok, [1, 2, 3], <<" trailing">>, _},
            nyaml_flow:parse_sequence(<<"[1, 2, 3] trailing">>, Ctx)
        ),
        ?_assertMatch(
            {ok, [true, <<"string">>, null], <<>>, _},
            nyaml_flow:parse_sequence(<<"[true, string, null]">>, Ctx)
        ),
        ?_assertMatch(
            {ok, [[1, 2], [3, 4]], <<>>, _},
            nyaml_flow:parse_sequence(<<"[[1, 2], [3, 4]]">>, Ctx)
        ),
        ?_assertEqual(
            {error, not_a_sequence}, nyaml_flow:parse_sequence(<<"not a sequence">>, Ctx)
        ),
        ?_assertEqual({error, unterminated_sequence}, nyaml_flow:parse_sequence(<<"[1, 2">>, Ctx)),
        ?_assertEqual(
            {error, invalid_leading_comma_in_sequence},
            nyaml_flow:parse_sequence(<<"[, 1]">>, Ctx)
        ),
        ?_assertEqual(
            {error, consecutive_commas_in_sequence},
            nyaml_flow:parse_sequence(<<"[1,, 2]">>, Ctx)
        ),
        ?_assertEqual(
            {error, empty_sequence_with_comma},
            nyaml_flow:parse_sequence(<<"[,]">>, Ctx)
        ),
        ?_assertEqual(
            {error, bare_dash_in_flow_sequence},
            nyaml_flow:parse_sequence(<<"[- item]">>, Ctx)
        ),
        ?_assertEqual(
            {error, bare_dash_in_flow_sequence},
            nyaml_flow:parse_sequence(<<"[-]">>, Ctx)
        ),
        ?_assertMatch(
            {ok, [1, 2], <<>>, _},
            nyaml_flow:parse_sequence(<<"[1, 2,]">>, Ctx)
        ),
        ?_assertMatch(
            {ok, [<<"a">>, <<"b">>], <<>>, _},
            nyaml_flow:parse_sequence(<<"[\n  a,\n  b\n]">>, Ctx)
        ),
        ?_assertMatch(
            {ok, [1, 2], <<>>, _},
            nyaml_flow:parse_sequence(<<"[1 # comment\n, 2]">>, Ctx)
        )
    ].

nyaml_flow_mapping_test_() ->
    Ctx = nyaml_parser:new_ctx(),
    [
        ?_assertMatch({ok, #{}, <<>>, _}, nyaml_flow:parse_mapping(<<"{}">>, Ctx)),
        ?_assertMatch(
            {ok, #{<<"key">> := <<"value">>}, <<>>, _},
            nyaml_flow:parse_mapping(<<"{key: value}">>, Ctx)
        ),
        ?_assertMatch(
            {ok, #{<<"a">> := 1, <<"b">> := 2}, <<>>, _},
            nyaml_flow:parse_mapping(<<"{a: 1, b: 2}">>, Ctx)
        ),
        ?_assertMatch(
            {ok, #{<<"nested">> := #{<<"map">> := <<"value">>}}, <<>>, _},
            nyaml_flow:parse_mapping(<<"{nested: {map: value}}">>, Ctx)
        ),
        ?_assertEqual({error, not_a_mapping}, nyaml_flow:parse_mapping(<<"not a mapping">>, Ctx)),
        ?_assertEqual({error, unterminated_mapping}, nyaml_flow:parse_mapping(<<"{a: 1">>, Ctx)),
        ?_assertMatch(
            {ok, #{<<"key">> := null}, <<>>, _},
            nyaml_flow:parse_mapping(<<"{key:}">>, Ctx)
        ),
        ?_assertMatch(
            {ok, #{<<"key">> := null}, <<>>, _},
            nyaml_flow:parse_mapping(<<"{key: }">>, Ctx)
        ),
        ?_assertMatch(
            {ok, #{<<"a">> := 1, <<"b">> := 2}, <<>>, _},
            nyaml_flow:parse_mapping(<<"{a: 1, b: 2,}">>, Ctx)
        ),
        ?_assertMatch(
            {ok, #{<<"key">> := <<"value">>}, <<>>, _},
            nyaml_flow:parse_mapping(<<"{\n  key: value\n}">>, Ctx)
        ),
        ?_assertMatch(
            {ok, #{<<"key">> := <<"value">>}, <<>>, _},
            nyaml_flow:parse_mapping(<<"{key: value # comment\n}">>, Ctx)
        )
    ].

nyaml_flow_implicit_mapping_test_() ->
    Ctx = nyaml_parser:new_ctx(),
    [
        ?_assertMatch(
            {ok, [#{<<"a">> := 1}], <<>>, _},
            nyaml_flow:parse_sequence(<<"[a: 1]">>, Ctx)
        ),
        ?_assertMatch(
            {ok, [#{<<"a">> := 1}, #{<<"b">> := 2}], <<>>, _},
            nyaml_flow:parse_sequence(<<"[a: 1, b: 2]">>, Ctx)
        ),
        ?_assertMatch(
            {ok, [#{null := <<"value">>}], <<>>, _},
            nyaml_flow:parse_sequence(<<"[: value]">>, Ctx)
        )
    ].

nyaml_flow_explicit_key_test_() ->
    Ctx = nyaml_parser:new_ctx(),
    [
        ?_assertMatch(
            {ok, #{<<"key">> := <<"value">>}, <<>>, _},
            nyaml_flow:parse_mapping(<<"{? key: value}">>, Ctx)
        ),
        ?_assertMatch(
            {ok, #{<<"multi word key">> := <<"value">>}, <<>>, _},
            nyaml_flow:parse_mapping(<<"{? multi word key: value}">>, Ctx)
        )
    ].

nyaml_flow_anchor_alias_test_() ->
    Ctx = nyaml_parser:new_ctx(),
    [
        ?_assertMatch(
            {ok, [1, 1], <<>>, _},
            nyaml_flow:parse_sequence(<<"[&a 1, *a]">>, Ctx)
        ),
        ?_assertMatch(
            {ok, #{<<"a">> := 5, <<"b">> := 5}, <<>>, _},
            nyaml_flow:parse_mapping(<<"{a: &v 5, b: *v}">>, Ctx)
        ),
        ?_assertMatch(
            {ok, #{<<"x">> := <<"val">>}, <<>>, _},
            nyaml_flow:parse_mapping(<<"{&k x: val}">>, Ctx)
        ),
        ?_assertMatch(
            {error, {undefined_alias, <<"missing">>}},
            nyaml_flow:parse_sequence(<<"[*missing]">>, Ctx)
        )
    ].

nyaml_flow_tags_test_() ->
    Ctx = nyaml_parser:new_ctx(),
    [
        ?_assertMatch(
            {ok, [<<"123">>], <<>>, _},
            nyaml_flow:parse_sequence(<<"[!!str 123]">>, Ctx)
        ),
        ?_assertMatch(
            {ok, #{<<"key">> := <<"42">>}, <<>>, _},
            nyaml_flow:parse_mapping(<<"{key: !!str 42}">>, Ctx)
        ),
        ?_assertMatch(
            {ok, [null], <<>>, _},
            nyaml_flow:parse_sequence(<<"[!!null]">>, Ctx)
        ),
        ?_assertMatch(
            {ok, [<<>>], <<>>, _},
            nyaml_flow:parse_sequence(<<"[!!str]">>, Ctx)
        ),
        ?_assertMatch(
            {ok, #{<<"key">> := <<"value">>}, <<>>, _},
            nyaml_flow:parse_mapping(<<"{!!str key: value}">>, Ctx)
        ),
        ?_assertMatch(
            {ok, [<<"value">>], <<>>, _},
            nyaml_flow:parse_sequence(<<"[!local value]">>, Ctx)
        )
    ].

nyaml_flow_quoted_keys_test_() ->
    Ctx = nyaml_parser:new_ctx(),
    [
        ?_assertMatch(
            {ok, #{<<"quoted key">> := <<"value">>}, <<>>, _},
            nyaml_flow:parse_mapping(<<"{\"quoted key\": value}">>, Ctx)
        ),
        ?_assertMatch(
            {ok, #{<<"single quoted">> := <<"value">>}, <<>>, _},
            nyaml_flow:parse_mapping(<<"{'single quoted': value}">>, Ctx)
        ),
        ?_assertMatch(
            {ok, [#{<<"q">> := 1}], <<>>, _},
            nyaml_flow:parse_sequence(<<"[\"q\": 1]">>, Ctx)
        )
    ].

nyaml_flow_nested_collections_test_() ->
    Ctx = nyaml_parser:new_ctx(),
    [
        ?_assertMatch(
            {ok, [#{<<"a">> := 1}], <<>>, _}, nyaml_flow:parse_sequence(<<"[{a: 1}]">>, Ctx)
        ),
        ?_assertMatch(
            {ok, #{<<"x">> := [1, 2]}, <<>>, _}, nyaml_flow:parse_mapping(<<"{x: [1, 2]}">>, Ctx)
        )
    ].

%% ============================================================
%% nyaml_block Module Tests
%% ============================================================

nyaml_block_sequence_test_() ->
    Ctx = nyaml_parser:new_ctx(),
    [
        ?_assertMatch(
            {ok, [], <<>>, _},
            nyaml_block:parse_block(<<>>, 0, Ctx)
        ),
        ?_assertMatch(
            {ok, [<<"item1">>, <<"item2">>], <<>>, _},
            nyaml_block:parse_block(<<"- item1\n- item2">>, 0, Ctx)
        ),
        ?_assertMatch(
            {ok, [<<"item1">>, <<"item2">>, <<"item3">>], <<>>, _},
            nyaml_block:parse_block(<<"- item1\n- item2\n- item3">>, 0, Ctx)
        ),
        ?_assertMatch(
            {ok, [<<"item1">>, [<<"nested1">>, <<"nested2">>]], <<>>, _},
            nyaml_block:parse_block(<<"- item1\n- \n  - nested1\n  - nested2">>, 0, Ctx)
        )
    ].

nyaml_block_mapping_test_() ->
    Ctx = nyaml_parser:new_ctx(),
    [
        ?_assertMatch(
            {ok, #{<<"key1">> := <<"value1">>, <<"key2">> := <<"value2">>}, <<>>, _},
            nyaml_block:parse_block(<<"key1: value1\nkey2: value2">>, 0, Ctx)
        ),
        ?_assertMatch(
            {ok, #{<<"key">> := [<<"item1">>, <<"item2">>]}, <<>>, _},
            nyaml_block:parse_block(<<"key:\n  - item1\n  - item2">>, 0, Ctx)
        ),
        ?_assertMatch(
            {ok, #{<<"key1">> := <<"value1">>, <<"key2">> := #{<<"nested">> := <<"value">>}}, <<>>,
                _},
            nyaml_block:parse_block(<<"key1: value1\nkey2:\n  nested: value">>, 0, Ctx)
        )
    ].

nyaml_block_nested_test_() ->
    Ctx = nyaml_parser:new_ctx(),
    [
        ?_assertMatch(
            {ok, #{<<"outer">> := #{<<"inner">> := <<"value">>}}, <<>>, _},
            nyaml_block:parse_block(<<"outer:\n  inner: value">>, 0, Ctx)
        ),
        ?_assertMatch(
            {ok, #{<<"list">> := [1, 2], <<"value">> := <<"test">>}, <<>>, _},
            nyaml_block:parse_block(<<"list:\n  - 1\n  - 2\nvalue: test">>, 0, Ctx)
        )
    ].

%% ============================================================
%% nyaml_block_scalar Module Tests
%% ============================================================

nyaml_block_scalar_test_() ->
    [
        ?_assertEqual(
            {ok, <<"hello\nworld\n">>, <<>>},
            nyaml_block_scalar:parse(<<"|\n  hello\n  world\n">>, 0)
        ),
        ?_assertEqual(
            {ok, <<"hello world\n">>, <<>>},
            nyaml_block_scalar:parse(<<">\n  hello\n  world\n">>, 0)
        ),
        ?_assertEqual(
            {ok, <<"hello\nworld">>, <<>>},
            nyaml_block_scalar:parse(<<"|-\n  hello\n  world\n">>, 0)
        ),
        ?_assertEqual(
            {ok, <<"hello\nworld\n\n">>, <<>>},
            nyaml_block_scalar:parse(<<"|+\n  hello\n  world\n\n">>, 0)
        ),
        ?_assertEqual(
            {ok, <<"line1\n  indented\nline2\n">>, <<>>},
            nyaml_block_scalar:parse(<<"|\n  line1\n    indented\n  line2\n">>, 0)
        ),
        ?_assertEqual(
            {ok, <<"line1\n\nline2\n">>, <<>>},
            nyaml_block_scalar:parse(<<"|\n  line1\n\n  line2\n">>, 0)
        ),
        ?_assertEqual(
            {ok, <<"hello world\nparagraph two\n">>, <<>>},
            nyaml_block_scalar:parse(<<">\n  hello\n  world\n\n  paragraph two\n">>, 0)
        ),
        ?_assertEqual(
            {ok, <<"  code\n  block\n">>, <<>>},
            nyaml_block_scalar:parse(<<">2\n    code\n    block\n">>, 0)
        ),
        ?_assertEqual(
            {ok, <<"hello\nworld\n">>, <<>>},
            nyaml_block_scalar:parse(<<"| # comment\n  hello\n  world\n">>, 0)
        )
    ].

nyaml_block_scalar_edge_test_() ->
    [
        ?_assertEqual({ok, <<>>, <<>>}, nyaml_block_scalar:parse(<<"|\n">>, 0)),
        ?_assertEqual(
            {ok, <<"indented\n">>, <<>>}, nyaml_block_scalar:parse(<<"|\n    indented">>, 0)
        ),
        ?_assertEqual({ok, <<>>, <<>>}, nyaml_block_scalar:parse(<<">-\n">>, 0)),
        ?_assertEqual({ok, <<"text">>, <<>>}, nyaml_block_scalar:parse(<<"|-\n  text">>, 0)),
        ?_assertEqual(
            {ok, <<"text\n">>, <<"next">>}, nyaml_block_scalar:parse(<<"|\n  text\nnext">>, 0)
        ),
        ?_assertEqual({ok, <<>>, <<>>}, nyaml_block_scalar:parse(<<">+\n">>, 0)),
        ?_assertEqual({ok, <<"\n">>, <<>>}, nyaml_block_scalar:parse(<<"|+\n\n">>, 0))
    ].

nyaml_block_scalar_chomping_test_() ->
    [
        ?_assertEqual(
            {ok, <<"text">>, <<>>},
            nyaml_block_scalar:parse(<<"|-\n  text\n">>, 0)
        ),
        ?_assertEqual(
            {ok, <<"text\n">>, <<>>},
            nyaml_block_scalar:parse(<<"|+\n  text\n">>, 0)
        ),
        ?_assertEqual(
            {ok, <<"text\n\n\n">>, <<>>},
            nyaml_block_scalar:parse(<<"|+\n  text\n\n\n">>, 0)
        ),
        ?_assertEqual(
            {ok, <<"text">>, <<>>},
            nyaml_block_scalar:parse(<<">-\n  text\n">>, 0)
        ),
        ?_assertEqual(
            {ok, <<"text\n">>, <<>>},
            nyaml_block_scalar:parse(<<">+\n  text\n">>, 0)
        ),
        ?_assertEqual(
            {ok, <<"text\n\n">>, <<>>},
            nyaml_block_scalar:parse(<<"|+\n  text\n\n">>, 0)
        )
    ].

nyaml_block_scalar_folded_advanced_test_() ->
    [
        ?_assertEqual(
            {ok, <<"paragraph one\nparagraph two\n">>, <<>>},
            nyaml_block_scalar:parse(<<">\n  paragraph one\n\n  paragraph two\n">>, 0)
        ),
        ?_assertEqual(
            {ok, <<"a b\n">>, <<>>},
            nyaml_block_scalar:parse(<<">\n  a\n  b\n">>, 0)
        ),
        ?_assertEqual(
            {ok, <<"a\nb\n">>, <<>>},
            nyaml_block_scalar:parse(<<">\n  a\n\n  b\n">>, 0)
        ),
        ?_assertEqual(
            {ok, <<"a\n\nb\n">>, <<>>},
            nyaml_block_scalar:parse(<<">\n  a\n\n\n  b\n">>, 0)
        )
    ].

nyaml_block_scalar_indicator_test_() ->
    [
        ?_assertEqual(true, nyaml_block_scalar:is_block_scalar_indicator(<<"|">>)),
        ?_assertEqual(true, nyaml_block_scalar:is_block_scalar_indicator(<<"|+">>)),
        ?_assertEqual(true, nyaml_block_scalar:is_block_scalar_indicator(<<">">>)),
        ?_assertEqual(true, nyaml_block_scalar:is_block_scalar_indicator(<<">-">>)),
        ?_assertEqual(false, nyaml_block_scalar:is_block_scalar_indicator(<<"text">>)),
        ?_assertEqual(false, nyaml_block_scalar:is_block_scalar_indicator(<<>>))
    ].

nyaml_block_scalar_error_test_() ->
    [
        ?_assertEqual(
            {error, not_a_block_scalar},
            nyaml_block_scalar:parse(<<"not a block scalar">>, 0)
        ),
        ?_assertEqual(
            {error, {unexpected_char_in_block_scalar_header, $x}},
            nyaml_block_scalar:parse(<<"|x\n  text">>, 0)
        )
    ].

nyaml_block_scalar_allow_column_zero_test_() ->
    [
        ?_assertMatch(
            {ok, <<"text\n">>, <<>>},
            nyaml_block_scalar:parse(<<"|\ntext\n">>, 0, true)
        )
    ].

%% "Block Indentation Indicator", when a block scalar holds no non-empty line,
%% the content indentation level is the number of spaces on the longest line.
%% A line of white space therefore never sets the level and never breaks it.
nyaml_block_scalar_whitespace_only_content_test_() ->
    [
        {"Block Indentation Indicator, JEF9/01, keep chomping over one space line",
            ?_assertEqual(
                {ok, [<<"\n">>]},
                nyaml:decode(<<"- |+\n   \n">>)
            )},
        {"Block Indentation Indicator, JEF9/02, the same body without a final break",
            ?_assertEqual(
                {ok, [<<"\n">>]},
                nyaml:decode(<<"- |+\n   ">>)
            )},
        {"Block Indentation Indicator, JEF9/00, keep chomping over two empty lines",
            ?_assertEqual(
                {ok, [<<"\n\n">>]},
                nyaml:decode(<<"- |+\n\n\n">>)
            )},
        {"Block Chomping Indicator, clip drops the trailing empty line",
            ?_assertEqual(
                {ok, [<<>>]},
                nyaml:decode(<<"- |\n   \n">>)
            )},
        {"Block Chomping Indicator, strip drops the trailing empty line",
            ?_assertEqual(
                {ok, [<<>>]},
                nyaml:decode(<<"- |-\n   \n">>)
            )},
        {"Block Indentation Indicator, a space line does not swallow the next entry",
            ?_assertEqual(
                {ok, [<<"\n">>, <<"next">>]},
                nyaml:decode(<<"- |+\n   \n- next\n">>)
            )},
        {"Block Indentation Indicator, a space line under a mapping key",
            ?_assertEqual(
                {ok, #{<<"a">> => <<"\n">>}},
                nyaml:decode(<<"a: |+\n   \n">>)
            )},
        {
            "Block Indentation Indicator, a leading space line wider than the first "
            "non-empty line is an error",
            ?_assertEqual(
                {error, {invalid_block_scalar_indentation, 2, 1}},
                nyaml:decode(<<"- |\n  \n text\n">>)
            )
        }
    ].

%% ============================================================
%% nyaml_parser Module Tests
%% ============================================================

nyaml_parser_test_() ->
    [
        ?_assertEqual({ok, [1, 2, 3]}, nyaml_parser:parse(<<"[1, 2, 3]">>)),
        ?_assertEqual({ok, []}, nyaml_parser:parse(<<"[]">>)),
        ?_assertEqual({ok, [[1, 2], 3]}, nyaml_parser:parse(<<"[[1, 2], 3]">>)),
        ?_assertMatch(
            {error, {trailing_content_after_document, _}}, nyaml_parser:parse(<<"[1, 2] extra">>)
        ),
        ?_assertEqual({ok, null}, nyaml_parser:parse(<<>>)),
        ?_assertEqual({ok, null}, nyaml_parser:parse(<<"   ">>))
    ].

nyaml_parser_block_test_() ->
    [
        ?_assertEqual(
            {ok, [<<"one">>, <<"two">>, <<"three">>]},
            nyaml_parser:parse(<<"- one\n- two\n- three">>)
        ),
        ?_assertEqual(
            {ok, #{<<"a">> => 1, <<"b">> => 2}},
            nyaml_parser:parse(<<"a: 1\nb: 2">>)
        ),
        ?_assertEqual(
            {ok, [#{<<"key">> => <<"value">>}, <<"item">>]},
            nyaml_parser:parse(<<"- key: value\n- item">>)
        ),
        ?_assertEqual(
            {ok, [
                #{<<"name">> => <<"first">>, <<"desc">> => <<"d1">>},
                #{<<"name">> => <<"second">>, <<"desc">> => <<"d2">>}
            ]},
            nyaml_parser:parse(<<"- name: first\n  desc: d1\n- name: second\n  desc: d2">>)
        ),
        ?_assertEqual(
            {ok, #{<<"tags">> => [#{<<"a">> => 1, <<"b">> => 2}], <<"other">> => <<"value">>}},
            nyaml_parser:parse(<<"tags:\n  - a: 1\n    b: 2\nother: value">>)
        )
    ].

nyaml_parser_scalar_test_() ->
    [
        ?_assertEqual({ok, null}, nyaml_parser:parse_scalar(<<"null">>)),
        ?_assertEqual({ok, null}, nyaml_parser:parse_scalar(<<>>)),
        ?_assertEqual({ok, null}, nyaml_parser:parse_scalar(<<"  ">>)),
        ?_assertEqual({ok, true}, nyaml_parser:parse_scalar(<<"true">>)),
        ?_assertEqual({ok, false}, nyaml_parser:parse_scalar(<<"false">>)),
        ?_assertEqual({ok, 123}, nyaml_parser:parse_scalar(<<"123">>)),
        ?_assertEqual({ok, 3.14}, nyaml_parser:parse_scalar(<<"3.14">>)),
        ?_assertEqual({ok, <<"text">>}, nyaml_parser:parse_scalar(<<"text">>))
    ].

nyaml_parser_next_test_() ->
    Ctx = nyaml_parser:new_ctx(),
    [
        ?_assertMatch({ok, [1], <<>>, _}, nyaml_parser:parse_next(<<"[1]">>, Ctx)),
        ?_assertMatch({ok, #{<<"a">> := 1}, <<>>, _}, nyaml_parser:parse_next(<<"{a: 1}">>, Ctx)),
        ?_assertMatch({ok, <<"hello">>, <<>>, _}, nyaml_parser:parse_next(<<"\"hello\"">>, Ctx)),
        ?_assertMatch({ok, <<"world">>, <<>>, _}, nyaml_parser:parse_next(<<"'world'">>, Ctx)),
        ?_assertMatch(
            {ok, <<"test">>, <<", rest">>, _}, nyaml_parser:parse_next(<<"test, rest">>, Ctx)
        )
    ].

nyaml_parser_block_scalar_test_() ->
    [
        ?_assertEqual({ok, <<"literal\n">>}, nyaml_parser:parse(<<"|\n  literal">>)),
        ?_assertEqual({ok, <<"folded\n">>}, nyaml_parser:parse(<<">\n  folded">>)),
        ?_assertMatch({error, _}, nyaml_parser:parse(<<"|badheader\n  content">>))
    ].

nyaml_parser_strip_comment_test_() ->
    [
        ?_assertEqual(<<"value">>, nyaml_parser:strip_comment(<<"value # comment">>)),
        ?_assertEqual(<<"value">>, nyaml_parser:strip_comment(<<"value">>)),
        ?_assertEqual(<<"\"str#with\"">>, nyaml_parser:strip_comment(<<"\"str#with\" # comment">>)),
        ?_assertEqual(<<"'str#with'">>, nyaml_parser:strip_comment(<<"'str#with' # comment">>)),
        ?_assertEqual(<<>>, nyaml_parser:strip_comment(<<"# only comment">>)),
        ?_assertEqual(<<"value">>, nyaml_parser:strip_comment(<<"value\t# tab comment">>)),
        ?_assertEqual(
            <<"\"escaped\\\"quote\"">>,
            nyaml_parser:strip_comment(<<"\"escaped\\\"quote\" # comment">>)
        ),
        ?_assertEqual(
            <<"'escaped''quote'">>,
            nyaml_parser:strip_comment(<<"'escaped''quote' # comment">>)
        )
    ].

nyaml_parser_to_string_test_() ->
    [
        ?_assertEqual(<<"hello">>, nyaml_parser:to_string(<<"hello">>)),
        ?_assertEqual(<<"123">>, nyaml_parser:to_string(123)),
        ?_assertMatch(<<_/binary>>, nyaml_parser:to_string(3.14)),
        ?_assertEqual(<<"true">>, nyaml_parser:to_string(true)),
        ?_assertEqual(<<"false">>, nyaml_parser:to_string(false)),
        ?_assertEqual(<<"null">>, nyaml_parser:to_string(null)),
        ?_assertEqual(<<"[list]">>, nyaml_parser:to_string([1, 2, 3])),
        ?_assertEqual(<<"{map}">>, nyaml_parser:to_string(#{a => 1}))
    ].

nyaml_parser_resolve_tag_test_() ->
    [
        ?_assertEqual(
            {ok, <<"123">>}, nyaml_parser:resolve_tag(<<"str">>, 123, nyaml_parser:new_ctx())
        ),
        ?_assertEqual(
            {ok, <<>>}, nyaml_parser:resolve_tag(<<"str">>, null, nyaml_parser:new_ctx())
        ),
        ?_assertEqual({ok, 123}, nyaml_parser:resolve_tag(<<"int">>, 123, nyaml_parser:new_ctx())),
        ?_assertEqual(
            {ok, 123.0}, nyaml_parser:resolve_tag(<<"float">>, 123, nyaml_parser:new_ctx())
        ),
        ?_assertEqual(
            {ok, true}, nyaml_parser:resolve_tag(<<"bool">>, true, nyaml_parser:new_ctx())
        ),
        ?_assertEqual(
            {ok, null}, nyaml_parser:resolve_tag(<<"null">>, <<"anything">>, nyaml_parser:new_ctx())
        ),
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml_parser:resolve_tag(<<"unknown">>, <<"value">>, nyaml_parser:new_ctx())
        ),
        ?_assertEqual(
            {ok, <<"aGVsbG8=">>},
            nyaml_parser:resolve_tag(<<"binary">>, <<"aGVsbG8=">>, nyaml_parser:new_ctx())
        ),
        ?_assertEqual(
            {ok, [1, 2]}, nyaml_parser:resolve_tag(<<"binary">>, [1, 2], nyaml_parser:new_ctx())
        ),
        ?_assertEqual({ok, #{}}, nyaml_parser:resolve_tag(<<"set">>, #{}, nyaml_parser:new_ctx()))
    ].

nyaml_parser_anchor_alias_test_() ->
    Ctx = nyaml_parser:new_ctx(),
    [
        ?_assertMatch(
            {ok, <<"value">>, _, _},
            nyaml_parser:parse_value_with_anchor(<<"&anchor value">>, Ctx)
        ),
        ?_assertMatch(
            {error, {undefined_alias, <<"missing">>}},
            nyaml_parser:parse_value_with_anchor(<<"*missing">>, Ctx)
        ),
        ?_assertEqual(
            {error, {undefined_alias, <<"test">>}},
            nyaml_parser:resolve_alias(<<"test">>, Ctx)
        )
    ].

nyaml_parser_skip_whitespace_and_comments_test_() ->
    [
        ?_assertEqual(<<"value">>, nyaml_parser:skip_whitespace_and_comments(<<"  value">>)),
        ?_assertEqual(<<"value">>, nyaml_parser:skip_whitespace_and_comments(<<"value">>)),
        ?_assertEqual(
            <<"value">>, nyaml_parser:skip_whitespace_and_comments(<<"# comment\nvalue">>)
        )
    ].

%% ============================================================
%% nyaml Module Tests (Public API)
%% ============================================================

nyaml_decode_test_() ->
    [
        ?_assertEqual({ok, [1, 2, 3]}, nyaml:decode(<<"[1, 2, 3]">>)),
        ?_assertEqual({ok, #{<<"a">> => 1}}, nyaml:decode(<<"{a: 1}">>)),
        ?_assertEqual({ok, <<"hello">>}, nyaml:decode(<<"\"hello\"">>)),
        ?_assertEqual({ok, <<"world">>}, nyaml:decode(<<"'world'">>)),
        ?_assertEqual({ok, <<"literal\n">>}, nyaml:decode(<<"|\n  literal">>)),
        ?_assertEqual({ok, <<"folded\n">>}, nyaml:decode(<<">\n  folded">>)),
        ?_assertEqual({ok, [<<"item">>]}, nyaml:decode(<<"- item">>)),
        ?_assertEqual({ok, #{<<"key">> => <<"value">>}}, nyaml:decode(<<"key: value">>)),
        ?_assertEqual({ok, null}, nyaml:decode(<<"null">>)),
        ?_assertEqual({ok, true}, nyaml:decode(<<"true">>)),
        ?_assertEqual({ok, 42}, nyaml:decode(<<"42">>)),
        ?_assertEqual({ok, <<"42\n">>}, nyaml:encode(42)),
        ?_assertEqual({ok, null}, nyaml:decode(<<>>)),
        ?_assertEqual({ok, null}, nyaml:decode(<<"  ">>))
    ].

nyaml_decode_options_test_() ->
    [
        ?_assertEqual({ok, 42}, nyaml:decode(<<"42">>, #{})),
        ?_assertEqual({ok, <<"hello">>}, nyaml:decode(<<"hello">>, #{schema => core})),
        ?_assertEqual({ok, [1, 2]}, nyaml:decode_all(<<"---\n1\n---\n2">>, #{})),
        ?_assertEqual({ok, [<<"test">>]}, nyaml:decode_all(<<"test">>, #{schema => core}))
    ].

nyaml_decode_file_test_() ->
    [
        ?_assertMatch(
            {error, {file_error, enoent}},
            nyaml:decode_file("/nonexistent/file.yaml")
        )
    ].

nyaml_decode_all_test_() ->
    [
        ?_assertEqual({ok, [#{<<"a">> => 1}]}, nyaml:decode_all(<<"a: 1">>)),
        ?_assertEqual(
            {ok, [#{<<"a">> => 1}, #{<<"b">> => 2}]},
            nyaml:decode_all(<<"---\na: 1\n---\nb: 2">>)
        ),
        ?_assertEqual(
            {ok, [#{<<"a">> => 1}, #{<<"b">> => 2}]},
            nyaml:decode_all(<<"---\na: 1\n...\n---\nb: 2">>)
        ),
        ?_assertEqual({ok, [null, #{<<"a">> => 1}]}, nyaml:decode_all(<<"---\n---\na: 1">>)),
        ?_assertEqual({ok, [#{<<"a">> => 1}]}, nyaml:decode_all(<<"---\na: 1\n...">>)),
        ?_assertEqual({ok, [1, 2, 3]}, nyaml:decode_all(<<"---\n1\n---\n2\n---\n3">>)),
        ?_assertEqual({ok, [1, 2]}, nyaml:decode_all(<<"---\n1\n# comment\n---\n2">>)),
        ?_assertEqual({ok, []}, nyaml:decode_all(<<>>)),
        ?_assertEqual({ok, [null]}, nyaml:decode_all(<<"---">>))
    ].

%% ============================================================
%% Document Structure Tests
%% ============================================================

nyaml_document_single_test_() ->
    [
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"---\nkey: value">>)
        ),
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"---\nkey: value\n...">>)
        ),
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"key: value">>)
        ),
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"# comment\n---\nkey: value">>)
        )
    ].

nyaml_document_anchor_reset_test_() ->
    [
        ?_assertMatch(
            {error, {undefined_alias, <<"x">>}},
            nyaml:decode_all(<<"---\na: &x 1\n---\nb: *x">>)
        )
    ].

%% ============================================================
%% Directive Tests
%% ============================================================

nyaml_directive_yaml_test_() ->
    [
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"%YAML 1.2\n---\nkey: value">>)
        ),
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"%YAML 1.1\n---\nkey: value">>)
        ),
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"%YAML 1.2\n%TAG ! tag:example.com,2000:\n---\nkey: value">>)
        ),
        ?_assertMatch(
            {error, duplicate_yaml_directive},
            nyaml:decode(<<"%YAML 1.2\n%YAML 1.1\n---\nkey: value">>)
        ),
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"%YAML 1.2 # comment\n---\nkey: value">>)
        ),
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"%YAML 1.2\t# comment\n---\nkey: value">>)
        ),
        %% "Separation Spaces" makes the separation one or more spaces, MUS6/02
        ?_assertEqual(
            {ok, null},
            nyaml:decode(<<"%YAML  1.1\n---\n">>)
        ),
        %% "Separation Spaces" admits a tab in the separation, MUS6/03
        ?_assertEqual(
            {ok, null},
            nyaml:decode(<<"%YAML \t 1.1\n---\n">>)
        ),
        %% "Comments" requires separation before a comment, MUS6/00
        ?_assertEqual(
            {error, comment_without_separation},
            nyaml:decode(<<"%YAML 1.1#...\n---\n">>)
        ),
        %% "Comments" keeps a separated comment on the directive line, MUS6/04
        ?_assertEqual(
            {ok, null},
            nyaml:decode(<<"%YAML 1.2 # a comment\n---\n">>)
        ),
        %% "YAML Directives" requires a version after the name
        ?_assertEqual(
            {error, invalid_yaml_directive},
            nyaml:decode(<<"%YAML\n---\nvalue">>)
        )
    ].

nyaml_directive_tag_test_() ->
    [
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"%TAG !e! tag:example.com,2000:\n---\nkey: value">>)
        ),
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"%TAG ! tag:example.com:\n---\nkey: value">>)
        )
    ].

nyaml_directive_unknown_test_() ->
    [
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"%UNKNOWN directive\n---\nkey: value">>)
        ),
        %% "Directives" reserves every name that is not YAML or TAG, MUS6/06
        ?_assertEqual(
            {ok, null},
            nyaml:decode(<<"%YAMLL 1.1\n---\n">>)
        ),
        %% a reserved directive changes nothing about the document, MUS6/06
        ?_assertEqual(
            nyaml:decode(<<"---\nkey: value">>),
            nyaml:decode(<<"%YAMLL 1.1\n---\nkey: value">>)
        ),
        %% "Directives" ignores a reserved name that a known name prefixes
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"%TAGS whatever\n---\nkey: value">>)
        ),
        %% "Directives" reserves a shorter name too, MUS6/05
        ?_assertEqual(
            {ok, null},
            nyaml:decode(<<"%YAM 1.1\n---\n">>)
        ),
        %% "Reserved Directives" ignores the parameters of a reserved directive
        ?_assertEqual(
            {ok, <<"foo">>},
            nyaml:decode(<<"%FOO  bar baz # ignored\n--- \"foo\"\n">>)
        )
    ].

%% ============================================================
%% Type Tag Tests
%% ============================================================

nyaml_type_tag_test_() ->
    [
        ?_assertEqual({ok, <<"123">>}, nyaml:decode(<<"!!str 123">>)),
        ?_assertEqual({ok, 123}, nyaml:decode(<<"!!int 123">>)),
        ?_assertEqual({ok, 1.0}, nyaml:decode(<<"!!float 1">>)),
        ?_assertEqual({ok, true}, nyaml:decode(<<"!!bool true">>)),
        ?_assertEqual({ok, null}, nyaml:decode(<<"!!null ''">>)),
        ?_assertEqual({ok, #{<<"key">> => <<"42">>}}, nyaml:decode(<<"key: !!str 42">>)),
        ?_assertEqual({ok, [<<"1">>, 2]}, nyaml:decode(<<"- !!str 1\n- 2">>))
    ].

%% ============================================================
%% Complex Mapping Keys Tests
%% ============================================================

nyaml_complex_key_test_() ->
    [
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"? key\n: value">>)
        ),
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"? key : value">>)
        )
    ].

%% ============================================================
%% Anchor and Alias Tests
%% ============================================================

nyaml_anchor_alias_test_() ->
    [
        ?_assertEqual(
            {ok, #{<<"a">> => <<"value">>, <<"b">> => <<"value">>}},
            nyaml:decode(<<"a: &anchor value\nb: *anchor">>)
        ),
        ?_assertEqual(
            {ok, #{<<"a">> => 42, <<"b">> => 42}},
            nyaml:decode(<<"a: &num 42\nb: *num">>)
        ),
        ?_assertEqual(
            {ok, #{<<"a">> => null, <<"b">> => null}},
            nyaml:decode(<<"a: &n null\nb: *n">>)
        ),
        ?_assertEqual(
            {ok, #{<<"a">> => <<"x">>, <<"b">> => <<"x">>, <<"c">> => <<"x">>}},
            nyaml:decode(<<"a: &x x\nb: *x\nc: *x">>)
        ),
        ?_assertEqual(
            {ok, #{<<"a">> => 1, <<"b">> => 2, <<"c">> => 1, <<"d">> => 2}},
            nyaml:decode(<<"a: &one 1\nb: &two 2\nc: *one\nd: *two">>)
        ),
        ?_assertEqual(
            {ok, #{<<"a">> => 1, <<"b">> => 2, <<"c">> => 2}},
            nyaml:decode(<<"a: &val 1\nb: &val 2\nc: *val">>)
        ),
        ?_assertMatch(
            {error, {undefined_alias, <<"missing">>}},
            nyaml:decode(<<"a: *missing">>)
        )
    ].

nyaml_anchor_sequence_test_() ->
    [
        ?_assertEqual(
            {ok, #{<<"a">> => [1, 2, 3], <<"b">> => [1, 2, 3]}},
            nyaml:decode(<<"a: &list\n  - 1\n  - 2\n  - 3\nb: *list">>)
        ),
        ?_assertEqual(
            {ok, [<<"x">>, <<"x">>]},
            nyaml:decode(<<"- &val x\n- *val">>)
        )
    ].

nyaml_anchor_mapping_test_() ->
    [
        ?_assertEqual(
            {ok, #{<<"a">> => #{<<"x">> => 1}, <<"b">> => #{<<"x">> => 1}}},
            nyaml:decode(<<"a: &map\n  x: 1\nb: *map">>)
        )
    ].

nyaml_anchor_flow_test_() ->
    [
        ?_assertEqual({ok, [1, 1]}, nyaml:decode(<<"[&a 1, *a]">>)),
        ?_assertEqual({ok, #{<<"a">> => 5, <<"b">> => 5}}, nyaml:decode(<<"{a: &v 5, b: *v}">>))
    ].

nyaml_merge_key_is_a_plain_key_test_() ->
    [
        ?_assertEqual(
            {ok, #{
                <<"defaults">> => #{<<"timeout">> => 30},
                <<"production">> => #{
                    <<"<<">> => #{<<"timeout">> => 30},
                    <<"timeout">> => 60
                }
            }},
            nyaml:decode(
                <<
                    "defaults: &defaults\n"
                    "  timeout: 30\n"
                    "production:\n"
                    "  <<: *defaults\n"
                    "  timeout: 60\n"
                >>
            )
        ),
        ?_assertEqual(
            {ok, #{<<"<<">> => <<"plain">>}},
            nyaml:decode(<<"<<: plain\n">>)
        )
    ].

nyaml_quoted_merge_key_is_a_string_test_() ->
    [
        ?_assertEqual(
            {ok, #{<<"<<">> => <<"plain">>}},
            nyaml:decode(<<"\"<<\": plain\n">>)
        ),
        ?_assertEqual(
            {ok, #{<<"<<">> => <<"plain">>}},
            nyaml:decode(<<"'<<': plain\n">>)
        )
    ].

nyaml_merge_key_holds_the_aliased_node_test() ->
    {ok, Decoded} = nyaml:decode(
        <<
            "defaults: &defaults\n"
            "  timeout: 30\n"
            "production:\n"
            "  <<: *defaults\n"
        >>
    ),
    Production = maps:get(<<"production">>, Decoded),
    ?assertEqual(#{<<"timeout">> => 30}, maps:get(<<"<<">>, Production)).

%% ============================================================
%% Comment Tests
%% ============================================================

nyaml_comment_test_() ->
    [
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"key: value # this is a comment">>)
        ),
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"# leading comment\nkey: value">>)
        ),
        ?_assertEqual(
            {ok, [<<"item1">>, <<"item2">>]},
            nyaml:decode(<<"- item1 # comment\n- item2">>)
        ),
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value with #hash">>}},
            nyaml:decode(<<"key: \"value with #hash\"">>)
        ),
        ?_assertEqual(
            {ok, #{<<"a">> => 1, <<"b">> => 2}},
            nyaml:decode(<<"a: 1 # first\n# full line comment\nb: 2">>)
        )
    ].

%% ============================================================
%% Encoding Tests
%% ============================================================

nyaml_encoding_test_() ->
    [
        ?_assertEqual({ok, <<"hello">>}, nyaml_encoding:detect_and_convert(<<"hello">>)),
        ?_assertEqual(
            {ok, <<"test">>},
            nyaml_encoding:detect_and_convert(<<16#EF, 16#BB, 16#BF, "test">>)
        ),
        ?_assertEqual(
            {ok, <<"hi">>},
            nyaml_encoding:detect_and_convert(<<16#FE, 16#FF, 0, $h, 0, $i>>)
        ),
        ?_assertEqual(
            {ok, <<"hi">>},
            nyaml_encoding:detect_and_convert(<<16#FF, 16#FE, $h, 0, $i, 0>>)
        ),
        ?_assertEqual(
            {ok, <<"a">>},
            nyaml_encoding:detect_and_convert(<<16#00, 16#00, 16#FE, 16#FF, 0, 0, 0, $a>>)
        ),
        ?_assertEqual(
            {ok, <<"a">>},
            nyaml_encoding:detect_and_convert(<<16#FF, 16#FE, 16#00, 16#00, $a, 0, 0, 0>>)
        )
    ].

nyaml_encoding_detection_without_bom_test_() ->
    [
        ?_assertEqual(
            {ok, <<"ab">>},
            nyaml_encoding:detect_and_convert(<<0, $a, 0, $b>>)
        ),
        ?_assertEqual(
            {ok, <<"ab">>},
            nyaml_encoding:detect_and_convert(<<$a, 0, $b, 0>>)
        ),
        ?_assertEqual(
            {ok, <<"ab">>},
            nyaml_encoding:detect_and_convert(<<0, 0, 0, $a, 0, 0, 0, $b>>)
        ),
        ?_assertEqual(
            {ok, <<"ab">>},
            nyaml_encoding:detect_and_convert(<<$a, 0, 0, 0, $b, 0, 0, 0>>)
        )
    ].

nyaml_encoding_error_test_() ->
    [
        ?_assertEqual(
            {error, incomplete_utf16},
            nyaml_encoding:detect_and_convert(<<16#FE, 16#FF, 0>>)
        ),
        ?_assertEqual(
            {error, incomplete_utf16},
            nyaml_encoding:detect_and_convert(<<16#FF, 16#FE, 0>>)
        ),
        ?_assertEqual(
            {error, incomplete_utf32},
            nyaml_encoding:detect_and_convert(<<16#00, 16#00, 16#FE, 16#FF, 0>>)
        ),
        ?_assertEqual(
            {error, incomplete_utf32},
            nyaml_encoding:detect_and_convert(<<16#FF, 16#FE, 16#00, 16#00, 0>>)
        )
    ].

nyaml_encoding_integration_test_() ->
    [
        ?_assertEqual(
            {ok, <<"hello">>},
            nyaml:decode(<<16#EF, 16#BB, 16#BF, "hello">>)
        ),
        ?_assertEqual(
            {ok, 42},
            nyaml:decode(<<16#FE, 16#FF, 0, $4, 0, $2>>)
        )
    ].

%% ============================================================
%% Number Tests
%% ============================================================

nyaml_scientific_notation_test_() ->
    [
        ?_assertEqual({ok, 1.5e10}, nyaml:decode(<<"1.5e10">>)),
        ?_assertEqual({ok, 1.5e10}, nyaml:decode(<<"1.5E10">>)),
        ?_assertEqual({ok, 2.3e-4}, nyaml:decode(<<"2.3e-4">>)),
        ?_assertEqual({ok, 2.3e-4}, nyaml:decode(<<"2.3E-4">>)),
        ?_assertEqual({ok, 1.5e10}, nyaml:decode(<<"1.5e+10">>)),
        ?_assertEqual({ok, 0.5e2}, nyaml:decode(<<".5e2">>)),
        ?_assertEqual({ok, 5.0e3}, nyaml:decode(<<"5e3">>))
    ].

nyaml_signed_numbers_test_() ->
    [
        ?_assertEqual({ok, 42}, nyaml:decode(<<"+42">>)),
        ?_assertEqual({ok, 0}, nyaml:decode(<<"+0">>)),
        ?_assertEqual({ok, 0}, nyaml:decode(<<"-0">>)),
        ?_assertEqual({ok, 3.14}, nyaml:decode(<<"+3.14">>))
    ].

nyaml_leading_dot_float_test_() ->
    [
        ?_assertEqual({ok, 0.5}, nyaml:decode(<<".5">>)),
        ?_assertEqual({ok, -0.25}, nyaml:decode(<<"-.25">>)),
        ?_assertEqual({ok, 0.75}, nyaml:decode(<<"+.75">>))
    ].

nyaml_infinity_nan_test_() ->
    [
        ?_assertEqual({ok, infinity}, nyaml:decode(<<".inf">>)),
        ?_assertEqual({ok, infinity}, nyaml:decode(<<"+.inf">>)),
        ?_assertEqual({ok, negative_infinity}, nyaml:decode(<<"-.inf">>)),
        ?_assertEqual({ok, nan}, nyaml:decode(<<".NaN">>)),
        ?_assertEqual({ok, nan}, nyaml:decode(<<".nan">>))
    ].

%% ============================================================
%% Block Scalar in Context Tests
%% ============================================================

nyaml_block_scalar_in_mapping_test_() ->
    [
        ?_assertEqual(
            {ok, #{<<"key">> => <<"literal\ncontent\n">>}},
            nyaml_parser:parse(<<"key: |\n  literal\n  content">>)
        ),
        ?_assertEqual(
            {ok, #{<<"key">> => <<"folded content\n">>}},
            nyaml_parser:parse(<<"key: >\n  folded\n  content">>)
        ),
        ?_assertEqual(
            {ok, #{<<"a">> => <<"text\n">>, <<"b">> => 2}},
            nyaml_parser:parse(<<"a: |\n  text\nb: 2">>)
        ),
        ?_assertEqual(
            {ok, #{<<"desc">> => <<"no trailing newline">>}},
            nyaml_parser:parse(<<"desc: |-\n  no trailing newline">>)
        )
    ].

nyaml_block_scalar_in_sequence_test_() ->
    [
        ?_assertEqual(
            {ok, [<<"first\nsecond\n">>, <<"item">>]},
            nyaml_parser:parse(<<"- |\n  first\n  second\n- item">>)
        ),
        ?_assertEqual(
            {ok, [<<"folded line\n">>]},
            nyaml_parser:parse(<<"- >\n  folded\n  line">>)
        )
    ].

%% ============================================================
%% Verbatim Tag Tests
%% ============================================================

nyaml_verbatim_tag_test_() ->
    [
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml:decode(<<"!<tag:example.com,2000:app/mytype> value">>)
        ),
        ?_assertMatch(
            {error, unterminated_verbatim_tag},
            nyaml:decode(<<"!<tag:unterminated value">>)
        )
    ].

%% ============================================================
%% Parser Edge Cases
%% ============================================================

nyaml_parser_edge_cases_test_() ->
    Ctx = nyaml_parser:new_ctx(),
    [
        ?_assertMatch(
            {ok, <<"value">>, <<>>, _},
            nyaml_parser:parse_next(<<"!!str value">>, Ctx)
        ),
        ?_assertMatch(
            {ok, null, <<",">>, _},
            nyaml_parser:parse_next(<<"!!null,">>, Ctx)
        ),
        ?_assertMatch(
            {ok, <<>>, <<",">>, _},
            nyaml_parser:parse_next(<<"!!str,">>, Ctx)
        ),
        ?_assertMatch(
            {ok, <<"value">>, <<>>, _},
            nyaml_parser:parse_next(<<"! value">>, Ctx)
        )
    ].

nyaml_set_anchor_test_() ->
    Ctx = nyaml_parser:new_ctx(),
    Ctx1 = nyaml_parser:set_anchor(<<"test">>, 42, Ctx),
    [
        ?_assertEqual({ok, 42}, nyaml_parser:resolve_alias(<<"test">>, Ctx1))
    ].

%% ============================================================
%% Block Explicit Key Tests
%% ============================================================

nyaml_block_explicit_key_test_() ->
    [
        %% Explicit key with value on next line
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"? key\n: value">>)
        ),
        %% Explicit key inline
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"? key : value">>)
        ),
        %% Explicit key with empty value
        ?_assertEqual(
            {ok, #{<<"key">> => null}},
            nyaml:decode(<<"? key\n:">>)
        ),
        %% Explicit key with nested mapping
        ?_assertEqual(
            {ok, #{<<"key">> => #{<<"nested">> => <<"value">>}}},
            nyaml:decode(<<"? key\n:\n  nested: value">>)
        ),
        %% Explicit key with nested sequence
        ?_assertEqual(
            {ok, #{<<"key">> => [1, 2]}},
            nyaml:decode(<<"? key\n:\n  - 1\n  - 2">>)
        ),
        %% Explicit key multiword as key
        ?_assertEqual(
            {ok, #{<<"a b">> => <<"value">>}},
            nyaml:decode(<<"? a b\n: value">>)
        ),
        %% Multiple explicit keys
        ?_assertEqual(
            {ok, #{<<"a">> => 1, <<"b">> => 2}},
            nyaml:decode(<<"? a\n: 1\n? b\n: 2">>)
        )
    ].

nyaml_block_explicit_key_complex_test_() ->
    [
        %% Explicit key followed by dedented value indicator
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"? key\n: value">>)
        ),
        %% Explicit key with null key and value
        ?_assertEqual(
            {ok, #{null => null}},
            nyaml:decode(<<"?\n:">>)
        ),
        %% Explicit key with inline sequence
        ?_assertEqual(
            {ok, #{[1, 2] => <<"value">>}},
            nyaml:decode(<<"?\n  - 1\n  - 2\n: value">>)
        )
    ].

%% ============================================================
%% Block Scalar Folded with More-Indented Lines Tests
%% ============================================================

nyaml_block_scalar_more_indented_test_() ->
    [
        %% Folded with uniform indentation
        ?_assertMatch(
            {ok, <<_/binary>>, <<>>},
            nyaml_block_scalar:parse(<<">\n  code\n  text\n">>, 0)
        ),
        %% Folded with more-indented in middle (extra indentation preserved)
        ?_assertMatch(
            {ok, <<_/binary>>, <<>>},
            nyaml_block_scalar:parse(<<">\n  normal\n    indented\n  normal\n">>, 0)
        ),
        %% Multiple more-indented lines
        ?_assertMatch(
            {ok, <<_/binary>>, <<>>},
            nyaml_block_scalar:parse(<<">\n  text\n    line1\n    line2\n  text\n">>, 0)
        ),
        %% More-indented with break before
        ?_assertMatch(
            {ok, <<_/binary>>, <<>>},
            nyaml_block_scalar:parse(<<">\n  text\n\n    code\n">>, 0)
        ),
        %% Tab in content line
        ?_assertMatch(
            {ok, <<_/binary>>, <<>>},
            nyaml_block_scalar:parse(<<">\n  \tcode\n  text\n">>, 0)
        ),
        %% Consistent indentation throughout
        ?_assertMatch(
            {ok, <<_/binary>>, <<>>},
            nyaml_block_scalar:parse(<<">\n    code\n    text\n">>, 0)
        )
    ].

nyaml_block_scalar_folded_breaks_test_() ->
    [
        %% Leading empty lines
        ?_assertMatch(
            {ok, <<_/binary>>, <<>>},
            nyaml_block_scalar:parse(<<">\n\n  text\n">>, 0)
        ),
        %% Multiple leading empty lines
        ?_assertMatch(
            {ok, <<_/binary>>, <<>>},
            nyaml_block_scalar:parse(<<">\n\n\n  text\n">>, 0)
        ),
        %% Break after text
        ?_assertMatch(
            {ok, <<_/binary>>, <<>>},
            nyaml_block_scalar:parse(<<">\n  a\n\n  b\n">>, 0)
        ),
        %% Multiple breaks in middle
        ?_assertMatch(
            {ok, <<_/binary>>, <<>>},
            nyaml_block_scalar:parse(<<">\n  a\n\n\n\n  b\n">>, 0)
        )
    ].

%% ============================================================
%% Block Plain Scalar Continuation Tests
%% ============================================================

nyaml_block_plain_scalar_multiline_test_() ->
    [
        %% Plain scalar continues on next line
        ?_assertEqual(
            {ok, #{<<"key">> => <<"line1 line2">>}},
            nyaml:decode(<<"key:\n  line1\n  line2">>)
        ),
        %% Plain scalar with empty lines
        ?_assertEqual(
            {ok, #{<<"key">> => <<"line1\nline2">>}},
            nyaml:decode(<<"key:\n  line1\n\n  line2">>)
        ),
        %% Scalar stops at mapping indicator
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>, <<"other">> => 1}},
            nyaml:decode(<<"key: value\nother: 1">>)
        ),
        %% Scalar stops at sequence indicator
        ?_assertMatch(
            {ok, [<<"item">>, <<"second">>]},
            nyaml:decode(<<"- item\n- second">>)
        )
    ].

%% ============================================================
%% Flow Collections Spanning Lines Tests
%% ============================================================

nyaml_flow_multiline_test_() ->
    [
        %% Sequence spanning lines
        ?_assertEqual(
            {ok, [1, 2, 3]},
            nyaml:decode(<<"[\n  1,\n  2,\n  3\n]">>)
        ),
        %% Mapping spanning lines
        ?_assertEqual(
            {ok, #{<<"a">> => 1, <<"b">> => 2}},
            nyaml:decode(<<"{\n  a: 1,\n  b: 2\n}">>)
        ),
        %% Nested flow spanning lines
        ?_assertEqual(
            {ok, [[1, 2], [3, 4]]},
            nyaml:decode(<<"[\n  [1, 2],\n  [3, 4]\n]">>)
        ),
        %% Flow in block value spanning lines
        ?_assertEqual(
            {ok, #{<<"key">> => [1, 2, 3]}},
            nyaml:decode(<<"key: [\n  1,\n  2,\n  3\n]">>)
        ),
        %% Quoted strings in multiline flow
        ?_assertEqual(
            {ok, [<<"hello">>, <<"world">>]},
            nyaml:decode(<<"[\n  \"hello\",\n  \"world\"\n]">>)
        )
    ].

%% ============================================================
%% Block Scalar Edge Cases
%% ============================================================

nyaml_block_scalar_content_edge_test_() ->
    [
        %% Empty content with clip chomping
        ?_assertEqual(
            {ok, <<>>, <<>>},
            nyaml_block_scalar:parse(<<"|\n">>, 0)
        ),
        %% Empty content with keep chomping
        ?_assertEqual(
            {ok, <<>>, <<>>},
            nyaml_block_scalar:parse(<<"|+\n">>, 0)
        ),
        %% Content ends at end of file
        ?_assertEqual(
            {ok, <<"text\n">>, <<>>},
            nyaml_block_scalar:parse(<<"|\n  text">>, 0)
        ),
        %% Only trailing newlines with keep
        ?_assertEqual(
            {ok, <<"\n\n">>, <<>>},
            nyaml_block_scalar:parse(<<"|+\n\n\n">>, 0)
        )
    ].

nyaml_block_scalar_indent_indicator_test_() ->
    [
        %% Explicit indent 1
        ?_assertEqual(
            {ok, <<"text\n">>, <<>>},
            nyaml_block_scalar:parse(<<"|1\n text\n">>, 0)
        ),
        %% Explicit indent 4
        ?_assertEqual(
            {ok, <<"text\n">>, <<>>},
            nyaml_block_scalar:parse(<<"|4\n    text\n">>, 0)
        ),
        %% Combined indent and chomping
        ?_assertEqual(
            {ok, <<"text">>, <<>>},
            nyaml_block_scalar:parse(<<"|2-\n  text\n">>, 0)
        ),
        %% Combined chomping and indent
        ?_assertEqual(
            {ok, <<"text">>, <<>>},
            nyaml_block_scalar:parse(<<"|-2\n  text\n">>, 0)
        )
    ].

%% ============================================================
%% Block Mapping with Quoted Keys
%% ============================================================

nyaml_block_quoted_key_test_() ->
    [
        %% Double quoted key
        ?_assertEqual(
            {ok, #{<<"key with space">> => <<"value">>}},
            nyaml:decode(<<"\"key with space\": value">>)
        ),
        %% Single quoted key
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"'key': value">>)
        ),
        %% Quoted key with colon
        ?_assertEqual(
            {ok, #{<<"key: colon">> => <<"value">>}},
            nyaml:decode(<<"\"key: colon\": value">>)
        ),
        %% Quoted key with nested value
        ?_assertEqual(
            {ok, #{<<"key">> => #{<<"nested">> => <<"val">>}}},
            nyaml:decode(<<"\"key\":\n  nested: val">>)
        )
    ].

%% ============================================================
%% Block Sequence Item with Anchors
%% ============================================================

nyaml_block_sequence_anchor_test_() ->
    [
        %% Anchor on sequence item
        ?_assertEqual(
            {ok, [<<"value">>, <<"value">>]},
            nyaml:decode(<<"- &a value\n- *a">>)
        ),
        %% Anchor on nested mapping in sequence
        ?_assertEqual(
            {ok, [#{<<"x">> => 1}, #{<<"x">> => 1}]},
            nyaml:decode(<<"- &m\n  x: 1\n- *m">>)
        ),
        %% Anchor with inline value in sequence
        ?_assertEqual(
            {ok, [42, 42]},
            nyaml:decode(<<"- &n 42\n- *n">>)
        )
    ].

%% ============================================================
%% Block Mapping Entry Value Tests
%% ============================================================

nyaml_block_entry_value_test_() ->
    [
        %% Entry value with anchor
        ?_assertEqual(
            {ok, #{<<"a">> => 1, <<"b">> => 1}},
            nyaml:decode(<<"a: &v 1\nb: *v">>)
        ),
        %% Entry value with tag
        ?_assertEqual(
            {ok, #{<<"key">> => <<"123">>}},
            nyaml:decode(<<"key: !!str 123">>)
        ),
        %% Entry value with flow sequence
        ?_assertEqual(
            {ok, #{<<"key">> => [1, 2, 3]}},
            nyaml:decode(<<"key: [1, 2, 3]">>)
        ),
        %% Entry value with flow mapping
        ?_assertEqual(
            {ok, #{<<"key">> => #{<<"a">> => 1}}},
            nyaml:decode(<<"key: {a: 1}">>)
        ),
        %% Entry value with block scalar
        ?_assertEqual(
            {ok, #{<<"key">> => <<"text\n">>}},
            nyaml:decode(<<"key: |\n  text">>)
        )
    ].

%% ============================================================
%% Block Inline Sequence Tests
%% ============================================================

nyaml_block_inline_sequence_test_() ->
    [
        %% Value starts with sequence indicator
        ?_assertEqual(
            {ok, #{<<"key">> => [1, 2]}},
            nyaml:decode(<<"key:\n  - 1\n  - 2">>)
        ),
        %% Nested sequences
        ?_assertEqual(
            {ok, [[1], [2]]},
            nyaml:decode(<<"- - 1\n- - 2">>)
        ),
        %% Empty sequence item
        ?_assertEqual(
            {ok, [null, <<"value">>]},
            nyaml:decode(<<"-\n- value">>)
        )
    ].

%% ============================================================
%% Complex Scalar Collection Tests
%% ============================================================

nyaml_complex_scalar_fractional_test_() ->
    [
        %% Leading zero scientific
        ?_assertEqual({ok, 0.5e2}, nyaml_complex_scalar:try_parse(<<".5e2">>)),
        %% Negative leading dot
        ?_assertEqual({ok, -0.5e1}, nyaml_complex_scalar:try_parse(<<"-.5e1">>)),
        %% Positive leading dot
        ?_assertEqual({ok, 0.5e3}, nyaml_complex_scalar:try_parse(<<"+.5e3">>))
    ].

%% ============================================================
%% Block Error Cases Tests
%% ============================================================

nyaml_block_error_test_() ->
    [
        %% Ambiguous mapping in value
        ?_assertMatch(
            {error, _},
            nyaml:decode(<<"key: a: b">>)
        )
    ].

%% ============================================================
%% Block Value with Type Tags
%% ============================================================

nyaml_block_value_tag_test_() ->
    [
        %% Tag on block value
        ?_assertEqual(
            {ok, #{<<"key">> => <<"42">>}},
            nyaml:decode(<<"key: !!str 42">>)
        ),
        %% Tag on block collection
        ?_assertEqual(
            {ok, #{<<"key">> => [1, 2]}},
            nyaml:decode(<<"key: !!seq\n  - 1\n  - 2">>)
        ),
        %% Tag on empty value
        ?_assertEqual(
            {ok, #{<<"key">> => null}},
            nyaml:decode(<<"key: !!null">>)
        ),
        %% Local tag
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"key: !local value">>)
        )
    ].

%% ============================================================
%% Block Mapping with Anchored Keys
%% ============================================================

nyaml_block_anchored_key_test_() ->
    [
        %% Anchor on key
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>, <<"ref">> => <<"key">>}},
            nyaml:decode(<<"&k key: value\nref: *k">>)
        ),
        %% Tagged key
        ?_assertMatch(
            {ok, #{<<"123">> := <<"value">>}},
            nyaml:decode(<<"!!str 123: value">>)
        )
    ].

%% ============================================================
%% Flow Value in Block Context Tests
%% ============================================================

nyaml_block_flow_value_test_() ->
    [
        %% Flow sequence in block
        ?_assertEqual(
            {ok, #{<<"key">> => [1, 2]}},
            nyaml:decode(<<"key: [1, 2]">>)
        ),
        %% Flow mapping in block
        ?_assertEqual(
            {ok, #{<<"key">> => #{<<"a">> => 1}}},
            nyaml:decode(<<"key: {a: 1}">>)
        )
    ].

%% ============================================================
%% Item Content Parsing Tests
%% ============================================================

nyaml_item_content_test_() ->
    [
        %% Item with anchor
        ?_assertEqual(
            {ok, [1, 1]},
            nyaml:decode(<<"- &a 1\n- *a">>)
        ),
        %% Item with tag
        ?_assertEqual(
            {ok, [<<"42">>]},
            nyaml:decode(<<"- !!str 42">>)
        ),
        %% Item with nested flow sequence
        ?_assertEqual(
            {ok, [[1, 2]]},
            nyaml:decode(<<"- [1, 2]">>)
        ),
        %% Item with nested flow mapping
        ?_assertEqual(
            {ok, [#{<<"a">> => 1}]},
            nyaml:decode(<<"- {a: 1}">>)
        ),
        %% Item with quoted string
        ?_assertEqual(
            {ok, [<<"hello">>]},
            nyaml:decode(<<"- \"hello\"">>)
        ),
        %% Item with single quoted string
        ?_assertEqual(
            {ok, [<<"world">>]},
            nyaml:decode(<<"- 'world'">>)
        ),
        %% Item with block scalar
        ?_assertEqual(
            {ok, [<<"text\n">>]},
            nyaml:decode(<<"- |\n  text">>)
        ),
        %% Item with nested mapping
        ?_assertEqual(
            {ok, [#{<<"key">> => <<"value">>}]},
            nyaml:decode(<<"- key: value">>)
        )
    ].

%% ============================================================
%% Validate Rest of Line Tests
%% ============================================================

nyaml_trailing_content_test_() ->
    [
        %% Valid trailing comment
        ?_assertEqual(
            {ok, [1, 2]},
            nyaml:decode(<<"[1, 2] # comment">>)
        ),
        %% Invalid trailing content
        ?_assertMatch(
            {error, _},
            nyaml:decode(<<"[1, 2] extra">>)
        )
    ].

%% ============================================================
%% Scalar Lines Collection Tests
%% ============================================================

nyaml_collect_scalar_lines_test_() ->
    [
        %% Multi-word scalar value
        ?_assertEqual(
            {ok, #{<<"key">> => <<"multi word value">>}},
            nyaml:decode(<<"key: multi word value">>)
        ),
        %% Scalar with comment
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"key: value # comment">>)
        )
    ].

%% ============================================================
%% Block Value Anchor with Inline Collection
%% ============================================================

nyaml_anchored_inline_value_test_() ->
    [
        %% Anchor on inline sequence
        ?_assertEqual(
            {ok, #{<<"a">> => [1, 2], <<"b">> => [1, 2]}},
            nyaml:decode(<<"a: &list [1, 2]\nb: *list">>)
        ),
        %% Anchor on inline mapping
        ?_assertEqual(
            {ok, #{<<"a">> => #{<<"x">> => 1}, <<"b">> => #{<<"x">> => 1}}},
            nyaml:decode(<<"a: &map {x: 1}\nb: *map">>)
        )
    ].

%% ============================================================
%% Key-Value Separator Edge Cases
%% ============================================================

nyaml_key_value_separator_test_() ->
    [
        %% Colon at end of line
        ?_assertEqual(
            {ok, #{<<"key">> => null}},
            nyaml:decode(<<"key:">>)
        ),
        %% Colon with only whitespace after
        ?_assertEqual(
            {ok, #{<<"key">> => null}},
            nyaml:decode(<<"key:   ">>)
        ),
        %% Colon with value on next line
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"key:\n  value">>)
        )
    ].

%% ============================================================
%% Skip Empty Lines Tests
%% ============================================================

nyaml_skip_empty_lines_test_() ->
    [
        %% Multiple empty lines before content
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"\n\n\nkey: value">>)
        ),
        %% Empty lines between entries
        ?_assertEqual(
            {ok, #{<<"a">> => 1, <<"b">> => 2}},
            nyaml:decode(<<"a: 1\n\n\nb: 2">>)
        )
    ].

%% ============================================================
%% Tag with Anchor Combination Tests
%% ============================================================

nyaml_tag_anchor_combination_test_() ->
    [
        %% Tag followed by anchor
        ?_assertEqual(
            {ok, [<<"42">>, <<"42">>]},
            nyaml:decode(<<"- !!str &v 42\n- *v">>)
        )
    ].

%% ============================================================
%% Alias in Mapping Value Tests
%% ============================================================

nyaml_alias_mapping_value_test_() ->
    [
        %% Alias as mapping value
        ?_assertEqual(
            {ok, #{<<"a">> => 1, <<"b">> => 1}},
            nyaml:decode(<<"a: &x 1\nb: *x">>)
        ),
        %% Alias to complex value
        ?_assertEqual(
            {ok, #{<<"a">> => [1, 2], <<"b">> => [1, 2]}},
            nyaml:decode(<<"a: &list\n  - 1\n  - 2\nb: *list">>)
        )
    ].

%% ============================================================
%% Block Scalar with Comments
%% ============================================================

nyaml_block_scalar_comment_test_() ->
    [
        %% Comment after indicator
        ?_assertEqual(
            {ok, <<"text\n">>, <<>>},
            nyaml_block_scalar:parse(<<"| # this is a comment\n  text\n">>, 0)
        ),
        %% Comment after chomping indicator
        ?_assertEqual(
            {ok, <<"text">>, <<>>},
            nyaml_block_scalar:parse(<<"|- # strip trailing\n  text\n">>, 0)
        )
    ].

%% ============================================================
%% Flow Collection in Block Anchored Value
%% ============================================================

nyaml_block_anchor_flow_test_() ->
    [
        %% Anchor before flow sequence
        ?_assertEqual(
            {ok, #{<<"a">> => [1, 2], <<"b">> => [1, 2]}},
            nyaml:decode(<<"a: &s [1, 2]\nb: *s">>)
        ),
        %% Anchor before flow mapping
        ?_assertEqual(
            {ok, #{<<"a">> => #{<<"x">> => 1}, <<"b">> => #{<<"x">> => 1}}},
            nyaml:decode(<<"a: &m {x: 1}\nb: *m">>)
        )
    ].

%% ============================================================
%% Block Scalar at Different Base Indents
%% ============================================================

nyaml_block_scalar_base_indent_test_() ->
    [
        %% Block scalar inside mapping
        ?_assertEqual(
            {ok, #{<<"key">> => <<"text\n">>}},
            nyaml:decode(<<"key: |\n  text">>)
        ),
        %% Block scalar inside nested mapping
        ?_assertEqual(
            {ok, #{<<"outer">> => #{<<"inner">> => <<"text\n">>}}},
            nyaml:decode(<<"outer:\n  inner: |\n    text">>)
        ),
        %% Block scalar in sequence item
        ?_assertEqual(
            {ok, [<<"line1\nline2\n">>]},
            nyaml:decode(<<"- |\n  line1\n  line2">>)
        )
    ].

%% ============================================================
%% Verbatim Tag in Entry Value
%% ============================================================

nyaml_verbatim_tag_entry_test_() ->
    [
        %% Verbatim tag on entry value
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"key: !<tag:example.com> value">>)
        ),
        %% Verbatim tag on item
        ?_assertEqual(
            {ok, [<<"value">>]},
            nyaml:decode(<<"- !<tag:yaml.org> value">>)
        )
    ].

%% ============================================================
%% Item Value with Complex Tags
%% ============================================================

nyaml_item_value_tag_test_() ->
    [
        %% Item with str tag
        ?_assertEqual(
            {ok, [<<"42">>]},
            nyaml:decode(<<"- !!str 42">>)
        ),
        %% Item with int tag
        ?_assertEqual(
            {ok, [123]},
            nyaml:decode(<<"- !!int 123">>)
        ),
        %% Item with local tag
        ?_assertEqual(
            {ok, [<<"value">>]},
            nyaml:decode(<<"- !local value">>)
        )
    ].

%% ============================================================
%% Plain Scalar with Trailing Content
%% ============================================================

nyaml_plain_scalar_edge_test_() ->
    [
        %% Plain scalar stopping at indicator
        ?_assertEqual(
            {ok, [<<"a">>, <<"b">>]},
            nyaml:decode(<<"- a\n- b">>)
        ),
        %% Plain scalar with mapping in same collection
        ?_assertEqual(
            {ok, [#{<<"key">> => <<"value">>}, <<"item">>]},
            nyaml:decode(<<"- key: value\n- item">>)
        )
    ].

%% ============================================================
%% Flow Context in Block Parser
%% ============================================================

nyaml_flow_in_block_test_() ->
    [
        %% Flow sequence as block value
        ?_assertEqual(
            {ok, #{<<"key">> => [1, 2, 3]}},
            nyaml:decode(<<"key: [1, 2, 3]">>)
        ),
        %% Flow mapping as block value
        ?_assertEqual(
            {ok, #{<<"key">> => #{<<"a">> => 1}}},
            nyaml:decode(<<"key: {a: 1}">>)
        ),
        %% Nested flow in block
        ?_assertEqual(
            {ok, #{<<"data">> => [[1, 2], [3, 4]]}},
            nyaml:decode(<<"data: [[1, 2], [3, 4]]">>)
        )
    ].

%% ============================================================
%% Complex Multiline Scalar Tests
%% ============================================================

nyaml_multiline_scalar_complex_test_() ->
    [
        %% Multiline plain scalar with empty line
        ?_assertEqual(
            {ok, #{<<"desc">> => <<"line1\nline2">>}},
            nyaml:decode(<<"desc:\n  line1\n\n  line2">>)
        )
    ].

%% ============================================================
%% Quoted Values in Block Context
%% ============================================================

nyaml_quoted_block_value_test_() ->
    [
        %% Double quoted value in mapping
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"key: \"value\"">>)
        ),
        %% Single quoted value in mapping
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"key: 'value'">>)
        ),
        %% Double quoted value in sequence
        ?_assertEqual(
            {ok, [<<"hello">>]},
            nyaml:decode(<<"- \"hello\"">>)
        ),
        %% Single quoted value in sequence
        ?_assertEqual(
            {ok, [<<"world">>]},
            nyaml:decode(<<"- 'world'">>)
        ),
        %% Multiline double quoted in block
        ?_assertEqual(
            {ok, #{<<"key">> => <<"line1 line2">>}},
            nyaml:decode(<<"key: \"line1\n  line2\"">>)
        )
    ].

%% ============================================================
%% Strip Comment Edge Cases
%% ============================================================

nyaml_strip_comment_edge_test_() ->
    [
        %% Hash inside quoted string preserved
        ?_assertEqual(
            {ok, #{<<"key">> => <<"val#ue">>}},
            nyaml:decode(<<"key: \"val#ue\"">>)
        ),
        %% Comment after quoted value
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"key: \"value\" # comment">>)
        )
    ].

%% ============================================================
%% Explicit Key Multiline Tests
%% ============================================================

nyaml_explicit_key_multiline_test_() ->
    [
        %% Explicit key with content on next lines
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"?\n  key\n: value">>)
        ),
        %% Explicit key with block scalar key
        ?_assertMatch(
            {ok, #{<<"literal key\n">> := <<"value">>}},
            nyaml:decode(<<"? |\n  literal key\n: value">>)
        ),
        %% Explicit null key
        ?_assertEqual(
            {ok, #{null => <<"value">>}},
            nyaml:decode(<<"?\n: value">>)
        )
    ].

%% ============================================================
%% Block Value Tag on Empty Tests
%% ============================================================

nyaml_block_tag_empty_test_() ->
    [
        %% Tag followed by block content
        ?_assertEqual(
            {ok, #{<<"key">> => [1, 2]}},
            nyaml:decode(<<"key: !!seq\n  - 1\n  - 2">>)
        ),
        %% Tag followed by mapping
        ?_assertEqual(
            {ok, #{<<"key">> => #{<<"a">> => 1}}},
            nyaml:decode(<<"key: !!map\n  a: 1">>)
        )
    ].

%% ============================================================
%% Anchor in Block Value Multiline
%% ============================================================

nyaml_anchor_block_value_test_() ->
    [
        %% Anchor on empty line, value on next
        ?_assertEqual(
            {ok, #{<<"a">> => <<"value">>, <<"b">> => <<"value">>}},
            nyaml:decode(<<"a: &x\n  value\nb: *x">>)
        ),
        %% Anchor with block sequence value
        ?_assertEqual(
            {ok, #{<<"a">> => [1, 2], <<"b">> => [1, 2]}},
            nyaml:decode(<<"a: &list\n  - 1\n  - 2\nb: *list">>)
        )
    ].

%% ============================================================
%% Alias in Block Contexts
%% ============================================================

nyaml_alias_block_test_() ->
    [
        %% Alias in sequence
        ?_assertEqual(
            {ok, [1, 1, 1]},
            nyaml:decode(<<"- &v 1\n- *v\n- *v">>)
        )
    ].

%% ============================================================
%% Tag Followed by Mapping Indicator
%% ============================================================

nyaml_tag_mapping_test_() ->
    [
        %% Tag on value followed by mapping
        ?_assertMatch(
            {ok, #{<<"key">> := #{<<"a">> := 1}}},
            nyaml:decode(<<"key: !!map\n  a: 1">>)
        )
    ].

%% ============================================================
%% Document Directive Tests
%% ============================================================

nyaml_document_directive_test_() ->
    [
        %% YAML directive with valid content
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml:decode(<<"%YAML 1.2\n---\nvalue">>)
        ),
        %% TAG directive
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml:decode(<<"%TAG ! tag:example.com,2000:\n---\nvalue">>)
        ),
        %% Multiple documents with directives
        ?_assertEqual(
            {ok, [1, 2]},
            nyaml:decode_all(<<"---\n1\n---\n2">>)
        ),
        %% Document end marker
        ?_assertEqual(
            {ok, [#{<<"a">> => 1}]},
            nyaml:decode_all(<<"a: 1\n...">>)
        )
    ].

%% ============================================================
%% Item with Tag and Mapping
%% ============================================================

nyaml_item_tag_mapping_test_() ->
    [
        %% Item with tag and nested mapping
        ?_assertMatch(
            {ok, [#{<<"a">> := 1}]},
            nyaml:decode(<<"- !!map\n  a: 1">>)
        )
    ].

%% ============================================================
%% Quoted Key as Mapping Key
%% ============================================================

nyaml_quoted_mapping_key_test_() ->
    [
        %% Double quoted as mapping key
        ?_assertEqual(
            {ok, #{<<"key with colon:">> => <<"value">>}},
            nyaml:decode(<<"\"key with colon:\": value">>)
        ),
        %% Single quoted as mapping key
        ?_assertEqual(
            {ok, #{<<"key: value">> => <<"x">>}},
            nyaml:decode(<<"'key: value': x">>)
        )
    ].

%% ============================================================
%% Flow Key in Block Mapping
%% ============================================================

nyaml_flow_key_block_test_() ->
    [
        %% Sequence as key
        ?_assertEqual(
            {ok, #{[1, 2] => <<"value">>}},
            nyaml:decode(<<"{[1, 2]: value}">>)
        ),
        %% Mapping as key
        ?_assertEqual(
            {ok, #{#{<<"a">> => 1} => <<"value">>}},
            nyaml:decode(<<"{{a: 1}: value}">>)
        )
    ].

%% ============================================================
%% Anchor with Tag Combination
%% ============================================================

nyaml_anchor_tag_block_test_() ->
    [
        %% Anchor and tag on same value
        ?_assertEqual(
            {ok, [<<"42">>, <<"42">>]},
            nyaml:decode(<<"- &v !!str 42\n- *v">>)
        ),
        %% Tag on key with anchor
        ?_assertMatch(
            {ok, #{<<"123">> := <<"value">>}},
            nyaml:decode(<<"&k !!str 123: value">>)
        )
    ].

%% ============================================================
%% Block Scalar in Nested Context
%% ============================================================

nyaml_block_scalar_nested_test_() ->
    [
        %% Block scalar in deeply nested mapping
        ?_assertEqual(
            {ok, #{<<"a">> => #{<<"b">> => #{<<"c">> => <<"text\n">>}}}},
            nyaml:decode(<<"a:\n  b:\n    c: |\n      text">>)
        ),
        %% Block scalar in sequence in mapping
        ?_assertEqual(
            {ok, #{<<"items">> => [<<"line\n">>]}},
            nyaml:decode(<<"items:\n  - |\n    line">>)
        )
    ].

%% ============================================================
%% Item with Anchor and Tag
%% ============================================================

nyaml_item_anchor_tag_test_() ->
    [
        %% Item with anchor
        ?_assertEqual(
            {ok, [42, 42]},
            nyaml:decode(<<"- &x 42\n- *x">>)
        ),
        %% Item with tag and anchor
        ?_assertEqual(
            {ok, [<<"42">>, <<"42">>]},
            nyaml:decode(<<"- !!str &v 42\n- *v">>)
        )
    ].

%% ============================================================
%% Plain Scalar Folding
%% ============================================================

nyaml_plain_scalar_fold_test_() ->
    [
        %% Plain scalar continues across lines
        ?_assertEqual(
            {ok, #{<<"desc">> => <<"word1 word2">>}},
            nyaml:decode(<<"desc:\n  word1\n  word2">>)
        ),
        %% Plain scalar with empty line becomes newline
        ?_assertEqual(
            {ok, #{<<"desc">> => <<"word1\nword2">>}},
            nyaml:decode(<<"desc:\n  word1\n\n  word2">>)
        )
    ].

%% ============================================================
%% Document Start and End
%% ============================================================

nyaml_document_markers_test_() ->
    [
        %% Document start with content
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml:decode(<<"---\nvalue">>)
        ),
        %% Document end after content
        ?_assertEqual(
            {ok, #{<<"a">> => 1}},
            nyaml:decode(<<"a: 1\n...">>)
        ),
        %% Multiple document starts
        ?_assertEqual(
            {ok, [1, 2, 3]},
            nyaml:decode_all(<<"---\n1\n---\n2\n---\n3">>)
        ),
        %% Document end followed by start
        ?_assertEqual(
            {ok, [<<"a">>, <<"b">>]},
            nyaml:decode_all(<<"---\na\n...\n---\nb">>)
        )
    ].

%% ============================================================
%% Block Scalar Trailing Newline Variations
%% ============================================================

nyaml_block_scalar_trailing_test_() ->
    [
        %% Keep chomping with multiple trailing newlines
        ?_assertEqual(
            {ok, <<"text\n\n\n">>, <<>>},
            nyaml_block_scalar:parse(<<"|+\n  text\n\n\n">>, 0)
        ),
        %% Strip chomping removes all trailing
        ?_assertEqual(
            {ok, <<"text">>, <<>>},
            nyaml_block_scalar:parse(<<"|-\n  text\n\n\n">>, 0)
        ),
        %% Clip keeps single newline
        ?_assertEqual(
            {ok, <<"text\n">>, <<>>},
            nyaml_block_scalar:parse(<<"|\n  text\n\n\n">>, 0)
        )
    ].

%% ============================================================
%% Sequence Item Content Variations
%% ============================================================

nyaml_sequence_item_variations_test_() ->
    [
        %% Empty sequence item
        ?_assertEqual(
            {ok, [null]},
            nyaml:decode(<<"-">>)
        ),
        %% Sequence item with nested sequence
        ?_assertEqual(
            {ok, [[1, 2]]},
            nyaml:decode(<<"- - 1\n  - 2">>)
        ),
        %% Sequence item with mapping
        ?_assertEqual(
            {ok, [#{<<"a">> => 1, <<"b">> => 2}]},
            nyaml:decode(<<"- a: 1\n  b: 2">>)
        )
    ].

%% ============================================================
%% Value on Same Line as Key
%% ============================================================

nyaml_key_value_same_line_test_() ->
    [
        %% Simple key-value
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"key: value">>)
        ),
        %% Key with numeric value
        ?_assertEqual(
            {ok, #{<<"num">> => 42}},
            nyaml:decode(<<"num: 42">>)
        ),
        %% Key with boolean value
        ?_assertEqual(
            {ok, #{<<"flag">> => true}},
            nyaml:decode(<<"flag: true">>)
        ),
        %% Key with null value
        ?_assertEqual(
            {ok, #{<<"empty">> => null}},
            nyaml:decode(<<"empty: null">>)
        )
    ].

%% ============================================================
%% Block Scalar with Base Indent Variations
%% ============================================================

nyaml_block_scalar_indent_var_test_() ->
    [
        %% Block scalar with base indent 2
        ?_assertMatch(
            {ok, #{<<"outer">> := #{<<"key">> := <<"line\n">>}}, <<>>, _},
            nyaml_block:parse_block(<<"outer:\n  key: |\n    line">>, 0, nyaml_parser:new_ctx())
        )
    ].

%% ============================================================
%% Multiline Values in Various Contexts
%% ============================================================

nyaml_multiline_value_test_() ->
    [
        %% Flow sequence spanning multiple lines
        ?_assertEqual(
            {ok, [1, 2, 3]},
            nyaml:decode(<<"[\n1,\n2,\n3\n]">>)
        ),
        %% Flow mapping spanning multiple lines
        ?_assertEqual(
            {ok, #{<<"a">> => 1, <<"b">> => 2}},
            nyaml:decode(<<"{\na: 1,\nb: 2\n}">>)
        )
    ].

%% ============================================================
%% Complex Type Tag Tests
%% ============================================================

nyaml_complex_type_tag_test_() ->
    [
        %% Int tag on string
        ?_assertEqual(
            {ok, 42},
            nyaml:decode(<<"!!int 42">>)
        ),
        %% Float tag on int
        ?_assertEqual(
            {ok, 42.0},
            nyaml:decode(<<"!!float 42">>)
        ),
        %% Bool tag
        ?_assertEqual(
            {ok, true},
            nyaml:decode(<<"!!bool true">>)
        ),
        %% Null tag
        ?_assertEqual(
            {ok, null},
            nyaml:decode(<<"!!null">>)
        )
    ].

%% ============================================================
%% Hexadecimal and Octal Numbers
%% ============================================================

nyaml_hex_octal_test_() ->
    [
        %% Hexadecimal
        ?_assertEqual(
            {ok, 255},
            nyaml:decode(<<"0xFF">>)
        ),
        %% Octal
        ?_assertEqual(
            {ok, 8},
            nyaml:decode(<<"0o10">>)
        ),
        %% Hex in mapping
        ?_assertEqual(
            {ok, #{<<"color">> => 16711680}},
            nyaml:decode(<<"color: 0xFF0000">>)
        )
    ].

%% ============================================================
%% Inline Anchor and Alias
%% ============================================================

nyaml_inline_anchor_alias_test_() ->
    [
        %% Anchor and immediate alias in flow
        ?_assertEqual(
            {ok, [1, 1]},
            nyaml:decode(<<"[&x 1, *x]">>)
        ),
        %% Anchor in flow mapping
        ?_assertEqual(
            {ok, #{<<"a">> => 1, <<"b">> => 1}},
            nyaml:decode(<<"{a: &v 1, b: *v}">>)
        )
    ].

%% ============================================================
%% Block Value Alias Variations
%% ============================================================

nyaml_block_alias_test_() ->
    [
        %% Alias as standalone value
        ?_assertEqual(
            {ok, #{<<"x">> => 1, <<"y">> => 1}},
            nyaml:decode(<<"x: &v 1\ny: *v">>)
        ),
        %% Alias to list
        ?_assertEqual(
            {ok, #{<<"a">> => [1], <<"b">> => [1]}},
            nyaml:decode(<<"a: &list\n  - 1\nb: *list">>)
        ),
        %% Alias to map
        ?_assertEqual(
            {ok, #{<<"a">> => #{<<"k">> => 1}, <<"b">> => #{<<"k">> => 1}}},
            nyaml:decode(<<"a: &map\n  k: 1\nb: *map">>)
        )
    ].

%% ============================================================
%% Empty Collection Tests
%% ============================================================

nyaml_empty_collection_test_() ->
    [
        %% Empty mapping value
        ?_assertEqual(
            {ok, #{<<"key">> => null}},
            nyaml:decode(<<"key:">>)
        ),
        %% Empty flow sequence
        ?_assertEqual(
            {ok, []},
            nyaml:decode(<<"[]">>)
        ),
        %% Empty flow mapping
        ?_assertEqual(
            {ok, #{}},
            nyaml:decode(<<"{}">>)
        )
    ].

%% ============================================================
%% Comment Position Tests
%% ============================================================

nyaml_comment_position_test_() ->
    [
        %% Comment at end of line
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"key: value # comment">>)
        ),
        %% Comment on its own line
        ?_assertEqual(
            {ok, #{<<"a">> => 1, <<"b">> => 2}},
            nyaml:decode(<<"a: 1\n# comment\nb: 2">>)
        ),
        %% Comment before first content
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml:decode(<<"# comment\nvalue">>)
        )
    ].

%% ============================================================
%% Sequence with Comments
%% ============================================================

nyaml_sequence_comment_test_() ->
    [
        %% Comment after sequence item
        ?_assertEqual(
            {ok, [1, 2]},
            nyaml:decode(<<"- 1 # one\n- 2">>)
        ),
        %% Comment between items
        ?_assertEqual(
            {ok, [1, 2]},
            nyaml:decode(<<"- 1\n# comment\n- 2">>)
        )
    ].

%% ============================================================
%% Mapping Value Continuation
%% ============================================================

nyaml_mapping_value_continuation_test_() ->
    [
        %% Value on next line
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"key:\n  value">>)
        ),
        %% Value with nested structure
        ?_assertEqual(
            {ok, #{<<"outer">> => #{<<"inner">> => <<"v">>}}},
            nyaml:decode(<<"outer:\n  inner: v">>)
        )
    ].

%% ============================================================
%% Additional Explicit Key Tests
%% ============================================================

nyaml_explicit_key_advanced_test_() ->
    [
        %% Explicit key with quoted key
        ?_assertEqual(
            {ok, #{<<"key: value">> => <<"result">>}},
            nyaml:decode(<<"? \"key: value\"\n: result">>)
        ),
        %% Explicit key with block scalar key
        ?_assertMatch(
            {ok, #{<<"block\n">> := <<"value">>}},
            nyaml:decode(<<"? |\n  block\n: value">>)
        ),
        %% Explicit key with inline value
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"? key : value">>)
        ),
        %% Empty explicit key (null key)
        ?_assertEqual(
            {ok, #{null => <<"value">>}},
            nyaml:decode(<<"? \n: value">>)
        ),
        %% Dedented sequence item is not the explicit key structure
        ?_assertEqual(
            {error, {explicit_key_missing_content, <<"- b">>}},
            nyaml:decode(<<"a:\n  ?\n- b\n">>)
        ),
        %% Same with tab separation after the dash
        ?_assertEqual(
            {error, {explicit_key_missing_content, <<"-\tb">>}},
            nyaml:decode(<<"a:\n  ?\n-\tb\n">>)
        )
    ].

%% ============================================================
%% Block Sequence Nested Test
%% ============================================================

nyaml_block_sequence_nested_test_() ->
    [
        %% Deeply nested sequences
        ?_assertEqual(
            {ok, [[[1]]]},
            nyaml:decode(<<"- - - 1">>)
        ),
        %% Sequence with nested mappings
        ?_assertEqual(
            {ok, [#{<<"a">> => 1}, #{<<"b">> => 2}]},
            nyaml:decode(<<"- a: 1\n- b: 2">>)
        ),
        %% Mixed sequence with empty item
        ?_assertEqual(
            {ok, [null, <<"item">>]},
            nyaml:decode(<<"-\n- item">>)
        ),
        %% Sequence item with comment
        ?_assertEqual(
            {ok, [<<"value">>]},
            nyaml:decode(<<"- value # comment">>)
        )
    ].

%% ============================================================
%% Block Mapping Nested Test
%% ============================================================

nyaml_block_mapping_nested_test_() ->
    [
        %% Three level nesting
        ?_assertEqual(
            {ok, #{<<"a">> => #{<<"b">> => #{<<"c">> => 1}}}},
            nyaml:decode(<<"a:\n  b:\n    c: 1">>)
        ),
        %% Mapping with empty value then sequence
        ?_assertEqual(
            {ok, #{<<"key">> => [1, 2]}},
            nyaml:decode(<<"key:\n  - 1\n  - 2">>)
        ),
        %% Multiple keys with different value types
        ?_assertEqual(
            {ok, #{<<"num">> => 42, <<"str">> => <<"text">>, <<"bool">> => true}},
            nyaml:decode(<<"num: 42\nstr: text\nbool: true">>)
        )
    ].

%% ============================================================
%% Block Scalar Folded with Multiple Paragraphs
%% ============================================================

nyaml_block_scalar_paragraphs_test_() ->
    [
        %% Multiple paragraphs in folded scalar
        ?_assertEqual(
            {ok, <<"para1\npara2\n">>, <<>>},
            nyaml_block_scalar:parse(<<">\n  para1\n\n  para2\n">>, 0)
        ),
        %% Three paragraphs
        ?_assertEqual(
            {ok, <<"a\nb\nc\n">>, <<>>},
            nyaml_block_scalar:parse(<<">\n  a\n\n  b\n\n  c\n">>, 0)
        )
    ].

%% ============================================================
%% Block Anchor on Empty Line Tests
%% ============================================================

nyaml_block_anchor_empty_test_() ->
    [
        %% Anchor followed by newline
        ?_assertEqual(
            {ok, #{<<"x">> => <<"val">>, <<"y">> => <<"val">>}},
            nyaml:decode(<<"x: &a\n  val\ny: *a">>)
        ),
        %% Anchor on sequence value that spans lines
        ?_assertEqual(
            {ok, #{<<"x">> => [1], <<"y">> => [1]}},
            nyaml:decode(<<"x: &s\n  - 1\ny: *s">>)
        )
    ].

%% ============================================================
%% Block Value with Local Tags
%% ============================================================

nyaml_block_local_tag_test_() ->
    [
        %% Local tag on value
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"key: !local value">>)
        ),
        %% Local tag on empty value
        ?_assertEqual(
            {ok, #{<<"key">> => null}},
            nyaml:decode(<<"key: !local\n">>)
        )
    ].

%% ============================================================
%% Plain Scalar Multiline Tests
%% ============================================================

nyaml_plain_multiline_test_() ->
    [
        %% Plain scalar continues on next line
        ?_assertEqual(
            {ok, #{<<"desc">> => <<"line1 line2">>}},
            nyaml:decode(<<"desc:\n  line1\n  line2">>)
        ),
        %% Plain scalar with empty line
        ?_assertEqual(
            {ok, #{<<"desc">> => <<"line1\nline2">>}},
            nyaml:decode(<<"desc:\n  line1\n\n  line2">>)
        ),
        %% Plain scalar stops at next key
        ?_assertEqual(
            {ok, #{<<"a">> => <<"value">>, <<"b">> => 1}},
            nyaml:decode(<<"a: value\nb: 1">>)
        )
    ].

%% ============================================================
%% Flow Collection Indentation Tests
%% ============================================================

nyaml_flow_indent_test_() ->
    [
        %% Flow sequence properly indented
        ?_assertEqual(
            {ok, #{<<"key">> => [1, 2, 3]}},
            nyaml:decode(<<"key: [\n    1,\n    2,\n    3\n  ]">>)
        ),
        %% Flow mapping properly indented
        ?_assertEqual(
            {ok, #{<<"key">> => #{<<"a">> => 1}}},
            nyaml:decode(<<"key: {\n    a: 1\n  }">>)
        )
    ].

%% ============================================================
%% Complex Scalar Number Tests
%% ============================================================

nyaml_complex_number_test_() ->
    [
        %% Scientific notation variations
        ?_assertMatch({ok, _}, nyaml_complex_scalar:try_parse(<<"1e10">>)),
        ?_assertMatch({ok, _}, nyaml_complex_scalar:try_parse(<<"1E10">>)),
        ?_assertMatch({ok, _}, nyaml_complex_scalar:try_parse(<<"1.5e-5">>)),
        ?_assertMatch({ok, _}, nyaml_complex_scalar:try_parse(<<"1.5E+5">>)),
        %% Leading dot variations
        ?_assertMatch({ok, _}, nyaml_complex_scalar:try_parse(<<".123">>)),
        ?_assertMatch({ok, _}, nyaml_complex_scalar:try_parse(<<"-.456">>)),
        ?_assertMatch({ok, _}, nyaml_complex_scalar:try_parse(<<"+.789">>))
    ].

%% ============================================================
%% Timestamp Parsing Tests
%% ============================================================

nyaml_timestamp_test_() ->
    [
        %% Full timestamp
        ?_assertMatch(
            {ok, {{2023, 5, 15}, {10, 30, 0}}},
            nyaml_complex_scalar:try_parse(<<"2023-05-15T10:30:00Z">>)
        ),
        %% Timestamp with timezone offset
        ?_assertMatch(
            {ok, _},
            nyaml_complex_scalar:try_parse(<<"2023-05-15T10:30:00+05:30">>)
        ),
        %% Timestamp with negative offset
        ?_assertMatch(
            {ok, _},
            nyaml_complex_scalar:try_parse(<<"2023-05-15T10:30:00-08:00">>)
        )
    ].

%% ============================================================
%% Block Document Structure
%% ============================================================

nyaml_block_document_test_() ->
    [
        %% Document with leading newlines
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"\n\nkey: value">>)
        ),
        %% Document with trailing newlines
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"key: value\n\n">>)
        ),
        %% Document with only comments
        ?_assertEqual(
            {ok, null},
            nyaml:decode(<<"# comment\n# another">>)
        )
    ].

%% ============================================================
%% Block Value Type Detection
%% ============================================================

nyaml_block_value_type_test_() ->
    [
        %% Empty content returns null
        ?_assertMatch(
            {ok, null},
            nyaml:decode(<<"  ">>)
        ),
        %% Just a dash (sequence item with null)
        ?_assertEqual(
            {ok, [null]},
            nyaml:decode(<<"-">>)
        ),
        %% Key with null value
        ?_assertEqual(
            {ok, #{<<"key">> => null}},
            nyaml:decode(<<"key:">>)
        )
    ].

%% ============================================================
%% Block Scalar from Mapping Value
%% ============================================================

nyaml_block_scalar_from_mapping_test_() ->
    [
        %% Literal scalar in mapping
        ?_assertEqual(
            {ok, #{<<"desc">> => <<"line1\nline2\n">>}},
            nyaml:decode(<<"desc: |\n  line1\n  line2">>)
        ),
        %% Folded scalar in mapping
        ?_assertEqual(
            {ok, #{<<"text">> => <<"line1 line2\n">>}},
            nyaml:decode(<<"text: >\n  line1\n  line2">>)
        ),
        %% Block scalar with strip chomping
        ?_assertEqual(
            {ok, #{<<"data">> => <<"content">>}},
            nyaml:decode(<<"data: |-\n  content\n">>)
        ),
        %% Block scalar with keep chomping
        ?_assertEqual(
            {ok, #{<<"data">> => <<"content\n\n">>}},
            nyaml:decode(<<"data: |+\n  content\n\n">>)
        )
    ].

%% ============================================================
%% Anchor on Various Value Types
%% ============================================================

nyaml_anchor_value_types_test_() ->
    [
        %% Anchor on integer
        ?_assertEqual(
            {ok, #{<<"a">> => 42, <<"b">> => 42}},
            nyaml:decode(<<"a: &n 42\nb: *n">>)
        ),
        %% Anchor on boolean
        ?_assertEqual(
            {ok, #{<<"a">> => true, <<"b">> => true}},
            nyaml:decode(<<"a: &flag true\nb: *flag">>)
        ),
        %% Anchor on null
        ?_assertEqual(
            {ok, #{<<"a">> => null, <<"b">> => null}},
            nyaml:decode(<<"a: &empty null\nb: *empty">>)
        ),
        %% Anchor on string
        ?_assertEqual(
            {ok, #{<<"a">> => <<"hello">>, <<"b">> => <<"hello">>}},
            nyaml:decode(<<"a: &s hello\nb: *s">>)
        )
    ].

%% ============================================================
%% Multiple Documents Test
%% ============================================================

nyaml_multi_doc_test_() ->
    [
        %% Two simple documents
        ?_assertEqual(
            {ok, [1, 2]},
            nyaml:decode_all(<<"---\n1\n---\n2">>)
        ),
        %% Three documents
        ?_assertEqual(
            {ok, [1, 2, 3]},
            nyaml:decode_all(<<"---\n1\n---\n2\n---\n3">>)
        ),
        %% Documents with end marker
        ?_assertEqual(
            {ok, [<<"a">>, <<"b">>]},
            nyaml:decode_all(<<"---\na\n...\n---\nb">>)
        ),
        %% Empty document
        ?_assertEqual(
            {ok, [null]},
            nyaml:decode_all(<<"---">>)
        )
    ].

%% ============================================================
%% Tag Resolution Tests
%% ============================================================

nyaml_tag_resolution_test_() ->
    [
        %% str tag converts to string
        ?_assertEqual(
            {ok, <<"42">>},
            nyaml_parser:resolve_tag(<<"str">>, 42, nyaml_parser:new_ctx())
        ),
        %% int tag converts to integer
        ?_assertEqual(
            {ok, 42},
            nyaml_parser:resolve_tag(<<"int">>, <<"42">>, nyaml_parser:new_ctx())
        ),
        %% float tag converts to float
        ?_assertEqual(
            {ok, 42.0},
            nyaml_parser:resolve_tag(<<"float">>, 42, nyaml_parser:new_ctx())
        ),
        %% null tag returns null
        ?_assertEqual(
            {ok, null},
            nyaml_parser:resolve_tag(<<"null">>, <<"anything">>, nyaml_parser:new_ctx())
        ),
        %% Unknown tag returns value as-is
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml_parser:resolve_tag(<<"custom">>, <<"value">>, nyaml_parser:new_ctx())
        )
    ].

%% ============================================================
%% Whitespace Handling Tests
%% ============================================================

nyaml_whitespace_test_() ->
    [
        %% Trailing whitespace on value
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"key: value   ">>)
        ),
        %% Leading whitespace preserved in quoted
        ?_assertEqual(
            {ok, #{<<"key">> => <<"  value">>}},
            nyaml:decode(<<"key: \"  value\"">>)
        ),
        %% Tab between key and colon (if valid)
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"key:\tvalue">>)
        )
    ].

%% ============================================================
%% Block Level Anchor Tests (parse_anchored_inline_value)
%% ============================================================

nyaml_block_level_anchor_test_() ->
    [
        %% Anchor at start of block value with flow sequence
        ?_assertEqual(
            {ok, #{<<"key">> => [1, 2, 3]}},
            nyaml:decode(<<"key:\n  &list [1, 2, 3]">>)
        ),
        %% Anchor at start of block value with flow mapping
        ?_assertEqual(
            {ok, #{<<"key">> => #{<<"a">> => 1}}},
            nyaml:decode(<<"key:\n  &map {a: 1}">>)
        ),
        %% Anchor at start of block value with plain scalar
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"key:\n  &val value">>)
        ),
        %% Block level anchor with mapping indicator
        ?_assertEqual(
            {ok, #{<<"outer">> => #{<<"inner">> => <<"value">>}}},
            nyaml:decode(<<"outer:\n  &m inner: value">>)
        ),
        %% Block level anchor followed by alias (error case)
        ?_assertMatch(
            {error, _},
            nyaml:decode(<<"key:\n  &a *b">>)
        ),
        %% Anchor with integer value at block level
        ?_assertEqual(
            {ok, #{<<"key">> => 42}},
            nyaml:decode(<<"key:\n  &n 42">>)
        ),
        %% Anchor with boolean at block level
        ?_assertEqual(
            {ok, #{<<"key">> => true}},
            nyaml:decode(<<"key:\n  &b true">>)
        ),
        %% Anchor with null at block level
        ?_assertEqual(
            {ok, #{<<"key">> => null}},
            nyaml:decode(<<"key:\n  &n null">>)
        )
    ].

%% ============================================================
%% Block Scalar More-Indented Folding Tests
%% ============================================================

nyaml_block_scalar_more_indented_folding_test_() ->
    [
        %% Literal with more indented content, less indented stops it
        ?_assertMatch(
            {ok, <<_/binary>>, _},
            nyaml_block_scalar:parse(<<"|\n    code\n  normal">>, 0)
        ),
        %% Folded with more indented line in middle
        ?_assertMatch(
            {ok, <<_/binary>>, _},
            nyaml_block_scalar:parse(<<">\n  line1\n    indented\n  line2">>, 0)
        ),
        %% Folded with multiple more-indented lines
        ?_assertMatch(
            {ok, <<_/binary>>, _},
            nyaml_block_scalar:parse(<<">\n  text\n    more1\n    more2\n  text2">>, 0)
        ),
        %% Literal with all content at same higher indent
        ?_assertMatch(
            {ok, <<_/binary>>, <<>>},
            nyaml_block_scalar:parse(<<"|\n    line1\n    line2\n    line3">>, 0)
        ),
        %% Folded with empty line then more-indented
        ?_assertMatch(
            {ok, <<_/binary>>, _},
            nyaml_block_scalar:parse(<<">\n  text\n\n    more-indented">>, 0)
        ),
        %% More indented at start, less indented continues
        ?_assertMatch(
            {ok, <<_/binary>>, _},
            nyaml_block_scalar:parse(<<">\n    indented\n  normal">>, 0)
        )
    ].

%% ============================================================
%% Block Scalar Indicator Edge Cases
%% ============================================================

nyaml_block_scalar_indicator_edge_test_() ->
    [
        %% Literal with explicit indent 1
        ?_assertMatch(
            {ok, <<_/binary>>, <<>>},
            nyaml_block_scalar:parse(<<"|1\n line">>, 0)
        ),
        %% Literal with explicit indent 2
        ?_assertMatch(
            {ok, <<_/binary>>, <<>>},
            nyaml_block_scalar:parse(<<"|2\n  line">>, 0)
        ),
        %% Strip chomping with content
        ?_assertMatch(
            {ok, <<"text">>, <<>>},
            nyaml_block_scalar:parse(<<"|-\n  text\n">>, 0)
        ),
        %% Keep chomping with trailing newlines
        ?_assertMatch(
            {ok, <<"text\n\n">>, <<>>},
            nyaml_block_scalar:parse(<<"|+\n  text\n\n">>, 0)
        ),
        %% Literal followed by less indented content
        ?_assertMatch(
            {ok, <<"content\n">>, <<"next: value">>},
            nyaml_block_scalar:parse(<<"|\n  content\nnext: value">>, 0)
        ),
        %% Empty literal block scalar
        ?_assertMatch(
            {ok, <<>>, <<>>},
            nyaml_block_scalar:parse(<<"|\n">>, 0)
        ),
        %% Empty folded block scalar
        ?_assertMatch(
            {ok, <<>>, <<>>},
            nyaml_block_scalar:parse(<<">\n">>, 0)
        )
    ].

%% ============================================================
%% Complex Scalar Parsing Tests
%% ============================================================

nyaml_complex_scalar_edge_test_() ->
    [
        %% Scientific notation lowercase
        ?_assertEqual(
            {ok, 1.5e10},
            nyaml_complex_scalar:try_parse(<<"1.5e10">>)
        ),
        %% Scientific notation uppercase
        ?_assertEqual(
            {ok, 1.5e10},
            nyaml_complex_scalar:try_parse(<<"1.5E10">>)
        ),
        %% Scientific with negative exponent
        ?_assertEqual(
            {ok, 1.5e-10},
            nyaml_complex_scalar:try_parse(<<"1.5e-10">>)
        ),
        %% Scientific with positive exponent
        ?_assertEqual(
            {ok, 1.5e10},
            nyaml_complex_scalar:try_parse(<<"+1.5e+10">>)
        ),
        %% Octal number
        ?_assertEqual(
            {ok, 8#755},
            nyaml_complex_scalar:try_parse(<<"0o755">>)
        ),
        %% Hex number lowercase
        ?_assertEqual(
            {ok, 16#ff},
            nyaml_complex_scalar:try_parse(<<"0xff">>)
        ),
        %% Hex number uppercase
        ?_assertEqual(
            {ok, 16#FF},
            nyaml_complex_scalar:try_parse(<<"0xFF">>)
        ),
        %% Positive infinity
        ?_assertEqual(
            {ok, infinity},
            nyaml_complex_scalar:try_parse(<<".inf">>)
        ),
        %% Negative infinity
        ?_assertEqual(
            {ok, negative_infinity},
            nyaml_complex_scalar:try_parse(<<"-.inf">>)
        ),
        %% NaN
        ?_assertEqual(
            {ok, nan},
            nyaml_complex_scalar:try_parse(<<".nan">>)
        ),
        %% Datetime with T separator
        ?_assertMatch(
            {ok, {{_, _, _}, {_, _, _}}},
            nyaml_complex_scalar:try_parse(<<"2024-01-15T10:30:00">>)
        ),
        %% Not a complex scalar
        ?_assertEqual(
            {error, not_complex_scalar},
            nyaml_complex_scalar:try_parse(<<"plain text">>)
        )
    ].

%% ============================================================
%% Alias Syntax Error Tests
%% ============================================================

nyaml_alias_error_test_() ->
    [
        %% Alias with extra content in sequence
        ?_assertMatch(
            {error, {invalid_alias_syntax, _}},
            nyaml:decode(<<"- *alias extra">>)
        ),
        %% Alias with extra content in mapping value
        ?_assertMatch(
            {error, {invalid_alias_syntax, _}},
            nyaml:decode(<<"key: *alias extra">>)
        ),
        %% Undefined alias
        ?_assertMatch(
            {error, {undefined_alias, _}},
            nyaml:decode(<<"key: *undefined">>)
        )
    ].

%% ============================================================
%% Local Tag Tests
%% ============================================================

nyaml_local_tag_test_() ->
    [
        %% Local tag on block value
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"key:\n  !local value">>)
        ),
        %% Local tag on sequence item
        ?_assertEqual(
            {ok, [<<"value">>]},
            nyaml:decode(<<"- !local value">>)
        ),
        %% Local tag with empty value
        ?_assertEqual(
            {ok, #{<<"key">> => null}},
            nyaml:decode(<<"key:\n  !local\n">>)
        )
    ].

%% ============================================================
%% Global Tag Block Value Tests
%% ============================================================

nyaml_global_tag_block_value_test_() ->
    [
        %% Global tag on block sequence
        ?_assertEqual(
            {ok, #{<<"key">> => [1, 2, 3]}},
            nyaml:decode(<<"key:\n  !!seq\n  - 1\n  - 2\n  - 3">>)
        ),
        %% Global tag on block mapping
        ?_assertEqual(
            {ok, #{<<"key">> => #{<<"a">> => 1}}},
            nyaml:decode(<<"key:\n  !!map\n  a: 1">>)
        ),
        %% Global tag str on integer
        ?_assertEqual(
            {ok, #{<<"key">> => <<"42">>}},
            nyaml:decode(<<"key: !!str 42">>)
        ),
        %% Global tag int on string
        ?_assertEqual(
            {ok, #{<<"key">> => 42}},
            nyaml:decode(<<"key: !!int 42">>)
        )
    ].

%% ============================================================
%% Flow Collection Rest of Line Validation
%% ============================================================

nyaml_flow_rest_of_line_test_() ->
    [
        %% Flow sequence with trailing content (invalid)
        ?_assertMatch(
            {error, _},
            nyaml:decode(<<"key: [1, 2] extra">>)
        ),
        %% Flow mapping with trailing content (invalid)
        ?_assertMatch(
            {error, _},
            nyaml:decode(<<"key: {a: 1} extra">>)
        ),
        %% Flow sequence with comment after
        ?_assertEqual(
            {ok, #{<<"key">> => [1, 2]}},
            nyaml:decode(<<"key: [1, 2] # comment">>)
        )
    ].

%% ============================================================
%% Document Start/End Handling Tests
%% ============================================================

nyaml_document_start_end_test_() ->
    [
        %% Document start with immediate content
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml:decode(<<"--- value">>)
        ),
        %% Document end marker
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml:decode(<<"value\n...">>)
        ),
        %% Document start with sequence
        ?_assertEqual(
            {ok, [1, 2]},
            nyaml:decode(<<"---\n- 1\n- 2">>)
        ),
        %% Document start with mapping
        ?_assertEqual(
            {ok, #{<<"a">> => 1}},
            nyaml:decode(<<"---\na: 1">>)
        ),
        %% Multiple document starts (decode returns first)
        ?_assertEqual(
            {ok, 1},
            nyaml:decode(<<"---\n1\n---\n2">>)
        )
    ].

%% ============================================================
%% Quoted String as Mapping Key with Colon
%% ============================================================

nyaml_quoted_key_colon_test_() ->
    [
        %% Double quoted key with colon inside
        ?_assertEqual(
            {ok, #{<<"key:with:colons">> => <<"value">>}},
            nyaml:decode(<<"\"key:with:colons\": value">>)
        ),
        %% Single quoted key with colon inside
        ?_assertEqual(
            {ok, #{<<"key:with:colons">> => <<"value">>}},
            nyaml:decode(<<"'key:with:colons': value">>)
        ),
        %% Double quoted key starting line
        ?_assertEqual(
            {ok, #{<<"quoted">> => <<"value">>}},
            nyaml:decode(<<"\"quoted\": value">>)
        ),
        %% Single quoted key starting line
        ?_assertEqual(
            {ok, #{<<"quoted">> => <<"value">>}},
            nyaml:decode(<<"'quoted': value">>)
        )
    ].

%% ============================================================
%% Nested Block Collections
%% ============================================================

nyaml_nested_block_test_() ->
    [
        %% Mapping in sequence in mapping
        ?_assertEqual(
            {ok, #{<<"outer">> => [#{<<"inner">> => 1}]}},
            nyaml:decode(<<"outer:\n- inner: 1">>)
        ),
        %% Sequence in mapping in sequence
        ?_assertEqual(
            {ok, [#{<<"key">> => [1, 2]}]},
            nyaml:decode(<<"- key:\n  - 1\n  - 2">>)
        ),
        %% Deep nesting
        ?_assertEqual(
            {ok, #{<<"a">> => #{<<"b">> => #{<<"c">> => <<"value">>}}}},
            nyaml:decode(<<"a:\n  b:\n    c: value">>)
        )
    ].

%% ============================================================
%% Plain Scalar Multiline Tests
%% ============================================================

nyaml_plain_scalar_multiline_test_() ->
    [
        %% Plain scalar continues on next line at same indent
        ?_assertEqual(
            {ok, #{<<"key">> => <<"line1 line2">>}},
            nyaml:decode(<<"key: line1\n  line2">>)
        ),
        %% Plain scalar with multiple continuation lines
        ?_assertEqual(
            {ok, #{<<"key">> => <<"a b c">>}},
            nyaml:decode(<<"key: a\n  b\n  c">>)
        )
    ].

%% ============================================================
%% Empty Input and Edge Cases
%% ============================================================

nyaml_empty_input_test_() ->
    [
        %% Empty input
        ?_assertEqual(
            {ok, null},
            nyaml:decode(<<>>)
        ),
        %% Only whitespace
        ?_assertEqual(
            {ok, null},
            nyaml:decode(<<"   ">>)
        ),
        %% Only newlines
        ?_assertEqual(
            {ok, null},
            nyaml:decode(<<"\n\n\n">>)
        ),
        %% Only comments
        ?_assertEqual(
            {ok, null},
            nyaml:decode(<<"# comment\n# another">>)
        )
    ].

%% ============================================================
%% Flow Style Anchors and Aliases
%% ============================================================

nyaml_flow_anchors_aliases_test_() ->
    [
        %% Anchor in flow sequence
        ?_assertEqual(
            {ok, [<<"a">>, <<"a">>]},
            nyaml:decode(<<"[&x a, *x]">>)
        ),
        %% Anchor in flow mapping value
        ?_assertEqual(
            {ok, #{<<"a">> => 1, <<"b">> => 1}},
            nyaml:decode(<<"{a: &n 1, b: *n}">>)
        ),
        %% Alias in flow sequence
        ?_assertEqual(
            {ok, #{<<"ref">> => <<"val">>, <<"list">> => [<<"val">>]}},
            nyaml:decode(<<"ref: &v val\nlist: [*v]">>)
        ),
        %% Nested flow with anchors
        ?_assertEqual(
            {ok, #{<<"a">> => [1, 2], <<"b">> => [1, 2]}},
            nyaml:decode(<<"a: &arr [1, 2]\nb: *arr">>)
        )
    ].

%% ============================================================
%% Verbatim and Named Tag Edge Cases
%% ============================================================

nyaml_verbatim_named_tag_test_() ->
    [
        %% Verbatim tag (parsed but ignored)
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml:decode(<<"!<tag:yaml.org,2002:str> value">>)
        ),
        %% Local tag on value
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"key: !mytag value">>)
        ),
        %% Tag on flow sequence
        ?_assertEqual(
            {ok, [1, 2]},
            nyaml:decode(<<"!mytag [1, 2]">>)
        )
    ].

%% ============================================================
%% Flow Collection Edge Cases
%% ============================================================

nyaml_flow_edge_cases_test_() ->
    [
        %% Empty flow sequence
        ?_assertEqual(
            {ok, []},
            nyaml:decode(<<"[]">>)
        ),
        %% Empty flow mapping
        ?_assertEqual(
            {ok, #{}},
            nyaml:decode(<<"{}">>)
        ),
        %% Flow sequence with trailing comma
        ?_assertEqual(
            {ok, [1, 2]},
            nyaml:decode(<<"[1, 2,]">>)
        ),
        %% Flow mapping with trailing comma
        ?_assertEqual(
            {ok, #{<<"a">> => 1}},
            nyaml:decode(<<"{a: 1,}">>)
        ),
        %% Nested empty collections
        ?_assertEqual(
            {ok, [[], #{}]},
            nyaml:decode(<<"[[], {}]">>)
        ),
        %% Flow sequence spanning lines
        ?_assertEqual(
            {ok, [1, 2, 3]},
            nyaml:decode(<<"[\n  1,\n  2,\n  3\n]">>)
        ),
        %% Flow mapping spanning lines
        ?_assertEqual(
            {ok, #{<<"a">> => 1, <<"b">> => 2}},
            nyaml:decode(<<"{\n  a: 1,\n  b: 2\n}">>)
        ),
        %% Deeply nested flow
        ?_assertEqual(
            {ok, [[[[1]]]]},
            nyaml:decode(<<"[[[[1]]]]">>)
        ),
        %% Mixed nested flow
        ?_assertEqual(
            {ok, [#{<<"a">> => [1]}]},
            nyaml:decode(<<"[{a: [1]}]">>)
        )
    ].

%% ============================================================
%% YAML Directive Tests
%% ============================================================

nyaml_directive_test_() ->
    [
        %% YAML 1.1 directive
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml:decode(<<"%YAML 1.1\n---\nvalue">>)
        ),
        %% YAML 1.2 directive
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml:decode(<<"%YAML 1.2\n---\nvalue">>)
        ),
        %% TAG directive (ignored)
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml:decode(<<"%TAG ! tag:\n---\nvalue">>)
        )
    ].

%% ============================================================
%% Parser Error Cases
%% ============================================================

nyaml_parser_error_test_() ->
    [
        %% Unexpected closing bracket in flow sequence
        ?_assertMatch(
            {error, _},
            nyaml:decode(<<"[1, ]extra">>)
        ),
        %% Invalid escape in double quoted string
        ?_assertMatch(
            {error, _},
            nyaml:decode(<<"\"\\q\"">>)
        ),
        %% Unterminated flow sequence
        ?_assertMatch(
            {error, _},
            nyaml:decode(<<"[1, 2">>)
        )
    ].

%% ============================================================
%% Block Indicator Variations
%% ============================================================

nyaml_block_indicator_test_() ->
    [
        %% Sequence with empty item
        ?_assertEqual(
            {ok, [null, 1]},
            nyaml:decode(<<"-\n- 1">>)
        ),
        %% Mapping with empty value
        ?_assertEqual(
            {ok, #{<<"key">> => null}},
            nyaml:decode(<<"key:\n">>)
        ),
        %% Sequence item with block scalar
        ?_assertMatch(
            {ok, [<<_/binary>>]},
            nyaml:decode(<<"- |\n  text">>)
        ),
        %% Mapping value with block scalar
        ?_assertMatch(
            {ok, #{<<"key">> := <<_/binary>>}},
            nyaml:decode(<<"key: |\n  text">>)
        )
    ].

%% ============================================================
%% Complex Nested Structures
%% ============================================================

nyaml_complex_nested_test_() ->
    [
        %% Deep mapping nesting
        ?_assertEqual(
            {ok, #{<<"a">> => #{<<"b">> => #{<<"c">> => #{<<"d">> => 1}}}}},
            nyaml:decode(<<"a:\n  b:\n    c:\n      d: 1">>)
        ),
        %% Mixed block and flow
        ?_assertEqual(
            {ok, #{<<"list">> => [1, 2], <<"map">> => #{<<"x">> => 1}}},
            nyaml:decode(<<"list: [1, 2]\nmap: {x: 1}">>)
        ),
        %% Sequence of mappings
        ?_assertEqual(
            {ok, [#{<<"name">> => <<"a">>}, #{<<"name">> => <<"b">>}]},
            nyaml:decode(<<"- name: a\n- name: b">>)
        ),
        %% Mapping with sequence values
        ?_assertEqual(
            {ok, #{<<"items">> => [1, 2, 3], <<"tags">> => [<<"a">>, <<"b">>]}},
            nyaml:decode(<<"items:\n- 1\n- 2\n- 3\ntags:\n- a\n- b">>)
        )
    ].

%% ============================================================
%% Scalar Type Coercion
%% ============================================================

nyaml_scalar_type_test_() ->
    [
        %% Integer variations
        ?_assertEqual({ok, 0}, nyaml:decode(<<"0">>)),
        ?_assertEqual({ok, -1}, nyaml:decode(<<"-1">>)),
        ?_assertEqual({ok, 1000000}, nyaml:decode(<<"1000000">>)),
        %% Float variations
        ?_assertEqual({ok, 0.0}, nyaml:decode(<<"0.0">>)),
        ?_assertEqual({ok, -1.5}, nyaml:decode(<<"-1.5">>)),
        %% Boolean (lowercase only at top level)
        ?_assertEqual({ok, true}, nyaml:decode(<<"true">>)),
        ?_assertEqual({ok, false}, nyaml:decode(<<"false">>)),
        %% Null variations
        ?_assertEqual({ok, null}, nyaml:decode(<<"null">>)),
        ?_assertEqual({ok, null}, nyaml:decode(<<"">>))
    ].

%% ============================================================
%% Comment Handling Edge Cases
%% ============================================================

nyaml_comment_edge_test_() ->
    [
        %% Comment after value
        ?_assertEqual(
            {ok, 42},
            nyaml:decode(<<"42 # comment">>)
        ),
        %% Comment on its own line
        ?_assertEqual(
            {ok, [1, 2]},
            nyaml:decode(<<"- 1\n# comment\n- 2">>)
        ),
        %% Comment after mapping entry
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"key: value # comment">>)
        ),
        %% Inline comment in flow
        ?_assertEqual(
            {ok, [1, 2]},
            nyaml:decode(<<"[1, 2] # comment">>)
        )
    ].

%% ============================================================
%% Multi-document decode_all Edge Cases
%% ============================================================

nyaml_decode_all_edge_test_() ->
    [
        %% Single document
        ?_assertEqual(
            {ok, [<<"value">>]},
            nyaml:decode_all(<<"---\nvalue">>)
        ),
        %% Multiple documents with different types
        ?_assertEqual(
            {ok, [1, <<"text">>, [1, 2]]},
            nyaml:decode_all(<<"---\n1\n---\ntext\n---\n- 1\n- 2">>)
        ),
        %% Empty document in middle
        ?_assertEqual(
            {ok, [1, null, 2]},
            nyaml:decode_all(<<"---\n1\n---\n---\n2">>)
        )
    ].

%% ============================================================
%% Folded Block Scalar State Machine Tests
%% ============================================================

nyaml_folded_state_machine_test_() ->
    [
        %% leading_break -> more_indented: empty lines then indented content
        ?_assertMatch(
            {ok, <<_/binary>>, _},
            nyaml_block_scalar:parse(<<">\n\n    indented\n  normal">>, 0)
        ),
        %% more_indented -> mi_first_break: indented line then empty
        ?_assertMatch(
            {ok, <<_/binary>>, _},
            nyaml_block_scalar:parse(<<">\n  text\n    indented\n\n  more">>, 0)
        ),
        %% mi_first_break -> mi_break: more empty lines after indented+empty
        ?_assertMatch(
            {ok, <<_/binary>>, _},
            nyaml_block_scalar:parse(<<">\n  text\n    indented\n\n\n  more">>, 0)
        ),
        %% mi_break -> text: multiple empties then normal
        ?_assertMatch(
            {ok, <<_/binary>>, _},
            nyaml_block_scalar:parse(<<">\n  text\n    indented\n\n\n\n  normal">>, 0)
        ),
        %% mi_break -> more_indented: multiple empties then indented again
        ?_assertMatch(
            {ok, <<_/binary>>, _},
            nyaml_block_scalar:parse(<<">\n  text\n    ind1\n\n\n    ind2">>, 0)
        ),
        %% break -> more_indented: empty lines then indented
        ?_assertMatch(
            {ok, <<_/binary>>, _},
            nyaml_block_scalar:parse(<<">\n  text\n\n\n    indented">>, 0)
        ),
        %% first_break -> more_indented: one empty then indented
        ?_assertMatch(
            {ok, <<_/binary>>, _},
            nyaml_block_scalar:parse(<<">\n  text\n\n    indented">>, 0)
        ),
        %% Complex: multiple state transitions
        ?_assertMatch(
            {ok, <<_/binary>>, _},
            nyaml_block_scalar:parse(<<">\n  a\n    b\n\n    c\n\n\n  d">>, 0)
        )
    ].

%% ============================================================
%% Explicit Key Tests
%% ============================================================

nyaml_explicit_key_test_() ->
    [
        %% Simple explicit key
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"? key\n: value">>)
        ),
        %% Explicit key with multiline value
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"? key\n:\n  value">>)
        ),
        %% Explicit key spanning lines (multiword)
        ?_assertEqual(
            {ok, #{<<"multi word">> => <<"value">>}},
            nyaml:decode(<<"? multi\n  word\n: value">>)
        ),
        %% Explicit null key
        ?_assertMatch(
            {ok, #{null := _}},
            nyaml:decode(<<"?\n: value">>)
        ),
        %% Explicit key with empty lines in between
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"? key\n\n: value">>)
        )
    ].

%% ============================================================
%% Anchor Value Position Edge Cases
%% ============================================================

nyaml_anchor_position_test_() ->
    [
        %% Anchor followed by newline
        ?_assertEqual(
            {ok, #{<<"key">> => <<"content">>}},
            nyaml:decode(<<"key: &a\n  content">>)
        ),
        %% Anchor followed by comment
        ?_assertEqual(
            {ok, #{<<"key">> => <<"content">>}},
            nyaml:decode(<<"key: &a # comment\n  content">>)
        ),
        %% Anchor followed by CRLF
        ?_assertEqual(
            {ok, #{<<"key">> => <<"content">>}},
            nyaml:decode(<<"key: &a\r\n  content">>)
        ),
        %% Anchor with only whitespace after
        ?_assertEqual(
            {ok, #{<<"key">> => <<"content">>}},
            nyaml:decode(<<"key: &a   \n  content">>)
        )
    ].

%% ============================================================
%% Encoding Invalid Sequence Tests
%% ============================================================

nyaml_encoding_invalid_test_() ->
    [
        %% Invalid UTF-16 BE (incomplete surrogate pair)
        ?_assertEqual(
            {error, incomplete_utf16},
            nyaml_encoding:detect_and_convert(<<16#FE, 16#FF, 16#D8, 16#00>>)
        ),
        %% Invalid UTF-16 LE (incomplete surrogate pair)
        ?_assertEqual(
            {error, incomplete_utf16},
            nyaml_encoding:detect_and_convert(<<16#FF, 16#FE, 16#00, 16#D8>>)
        ),
        %% Invalid UTF-32 BE (invalid codepoint)
        ?_assertEqual(
            {error, invalid_utf32},
            nyaml_encoding:detect_and_convert(<<0, 0, 16#FE, 16#FF, 16#FF, 16#FF, 16#FF, 16#FF>>)
        ),
        %% Invalid UTF-32 LE (invalid codepoint)
        ?_assertEqual(
            {error, invalid_utf32},
            nyaml_encoding:detect_and_convert(<<16#FF, 16#FE, 0, 0, 16#FF, 16#FF, 16#FF, 16#FF>>)
        )
    ].

%% ============================================================
%% Complex Scalar Mantissa Edge Cases
%% ============================================================

nyaml_complex_scalar_mantissa_test_() ->
    [
        %% Leading dot float .5
        ?_assertEqual(
            {ok, 0.5},
            nyaml_complex_scalar:try_parse(<<".5">>)
        ),
        %% Negative leading dot -.5
        ?_assertEqual(
            {ok, -0.5},
            nyaml_complex_scalar:try_parse(<<"-.5">>)
        ),
        %% Positive leading dot +.5
        ?_assertEqual(
            {ok, 0.5},
            nyaml_complex_scalar:try_parse(<<"+.5">>)
        ),
        %% Plus sign integer +42
        ?_assertEqual(
            {ok, 42},
            nyaml_complex_scalar:try_parse(<<"+42">>)
        ),
        %% Plus sign float +3.14
        ?_assertEqual(
            {ok, 3.14},
            nyaml_complex_scalar:try_parse(<<"+3.14">>)
        ),
        %% Scientific with plus mantissa
        ?_assertEqual(
            {ok, 15000000000.0},
            nyaml_complex_scalar:try_parse(<<"+1.5e10">>)
        ),
        %% Leading dot scientific .5e2
        ?_assertMatch(
            {ok, _},
            nyaml_complex_scalar:try_parse(<<".5e2">>)
        )
    ].

%% ============================================================
%% Item Scalar Continuation Tests
%% ============================================================

nyaml_item_scalar_continuation_test_() ->
    [
        %% Sequence item with continuation
        ?_assertEqual(
            {ok, [<<"line1 line2">>]},
            nyaml:decode(<<"- line1\n  line2">>)
        ),
        %% Sequence item stops at mapping indicator
        ?_assertEqual(
            {ok, [#{<<"a">> => <<"b">>}]},
            nyaml:decode(<<"- a:\n    b">>)
        ),
        %% Sequence item with empty lines
        ?_assertEqual(
            {ok, [<<"line1">>, <<"line2">>]},
            nyaml:decode(<<"- line1\n\n- line2">>)
        )
    ].

%% ============================================================
%% Block Scalar Indicator Edge Cases
%% ============================================================

nyaml_block_indicator_edge_test_() ->
    [
        %% Literal with indent indicator 1
        ?_assertMatch(
            {ok, <<_/binary>>, _},
            nyaml_block_scalar:parse(<<"|1\n x">>, 0)
        ),
        %% Literal ending at EOF
        ?_assertMatch(
            {ok, <<"text">>, <<>>},
            nyaml_block_scalar:parse(<<"|-\n  text">>, 0)
        ),
        %% Folded with clip chomping (default)
        ?_assertMatch(
            {ok, <<"text\n">>, <<>>},
            nyaml_block_scalar:parse(<<">\n  text\n">>, 0)
        ),
        %% Block scalar followed by dedented content
        ?_assertMatch(
            {ok, <<"inner\n">>, <<"outer: value">>},
            nyaml_block_scalar:parse(<<"|\n  inner\nouter: value">>, 0)
        )
    ].

%% ============================================================
%% Parser Flow Context Edge Cases
%% ============================================================

nyaml_parser_flow_context_test_() ->
    [
        %% Anchor in flow context
        ?_assertEqual(
            {ok, [<<"x">>, <<"x">>]},
            nyaml:decode(<<"[&a x, *a]">>)
        ),
        %% Tag in flow context
        ?_assertEqual(
            {ok, [<<"42">>]},
            nyaml:decode(<<"[!!str 42]">>)
        ),
        %% Nested flow with alias
        ?_assertEqual(
            {ok, #{<<"a">> => 1, <<"b">> => #{<<"c">> => 1}}},
            nyaml:decode(<<"{a: &x 1, b: {c: *x}}">>)
        )
    ].

%% ============================================================
%% Plain Scalar with Comment
%% ============================================================

nyaml_plain_scalar_comment_test_() ->
    [
        %% Plain scalar followed by comment
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml:decode(<<"value # this is a comment">>)
        ),
        %% Number followed by comment
        ?_assertEqual(
            {ok, 42},
            nyaml:decode(<<"42 # the answer">>)
        ),
        %% Boolean followed by comment
        ?_assertEqual(
            {ok, true},
            nyaml:decode(<<"true # yes">>)
        )
    ].

%% ============================================================
%% Flow Sequence Malformed Error Tests
%% ============================================================

nyaml_flow_sequence_malformed_test_() ->
    [
        %% Bare dash in flow sequence
        ?_assertEqual(
            {error, bare_dash_in_flow_sequence},
            nyaml:decode(<<"[- item]">>)
        ),
        %% Bare dash with space in flow sequence
        ?_assertEqual(
            {error, bare_dash_in_flow_sequence},
            nyaml:decode(<<"[- ]">>)
        ),
        %% Bare dash with tab
        ?_assertEqual(
            {error, bare_dash_in_flow_sequence},
            nyaml:decode(<<"[-\t]">>)
        ),
        %% Bare dash with newline
        ?_assertEqual(
            {error, bare_dash_in_flow_sequence},
            nyaml:decode(<<"[-\n]">>)
        ),
        %% Bare dash with comma
        ?_assertEqual(
            {error, bare_dash_in_flow_sequence},
            nyaml:decode(<<"[-,a]">>)
        ),
        %% Bare dash followed by close bracket
        ?_assertEqual(
            {error, bare_dash_in_flow_sequence},
            nyaml:decode(<<"[-]">>)
        ),
        %% Consecutive commas in sequence
        ?_assertEqual(
            {error, consecutive_commas_in_sequence},
            nyaml:decode(<<"[a,, b]">>)
        ),
        %% Comment right after bracket with value inside (not empty)
        ?_assertEqual(
            {error, invalid_comment_after_bracket},
            nyaml:decode(<<"[a]#comment">>)
        ),
        %% Comment right after comma with no space
        ?_assertEqual(
            {error, invalid_comment_after_comma},
            nyaml:decode(<<"[a,#comment\nb]">>)
        ),
        %% Leading comma in sequence
        ?_assertEqual(
            {error, invalid_leading_comma_in_sequence},
            nyaml:decode(<<"[,a]">>)
        ),
        %% Empty sequence with trailing comma
        ?_assertEqual(
            {error, empty_sequence_with_comma},
            nyaml:decode(<<"[,]">>)
        ),
        %% Unterminated flow sequence
        ?_assertEqual(
            {error, unterminated_sequence},
            nyaml:decode(<<"[a, b">>)
        )
    ].

%% ============================================================
%% Flow Mapping Malformed Error Tests
%% ============================================================

nyaml_flow_mapping_malformed_test_() ->
    [
        %% Unterminated flow mapping
        ?_assertEqual(
            {error, unterminated_mapping},
            nyaml:decode(<<"{a: 1">>)
        ),
        %% Missing comma in flow mapping
        ?_assertEqual(
            {error, missing_comma_in_flow_mapping},
            nyaml:decode(<<"{a: 1 b: 2}">>)
        ),
        %% Implicit key spans lines
        ?_assertEqual(
            {error, implicit_key_spans_lines},
            nyaml:decode(<<"[key\n: value]">>)
        ),
        %% Not a mapping error
        ?_assertEqual(
            {error, not_a_mapping},
            nyaml_flow:parse_mapping(<<"[a]">>, nyaml_parser:new_ctx())
        ),
        %% Not a sequence error
        ?_assertEqual(
            {error, not_a_sequence},
            nyaml_flow:parse_sequence(<<"{a: 1}">>, nyaml_parser:new_ctx())
        )
    ].

%% ============================================================
%% Directive Parsing Error Tests
%% ============================================================

nyaml_directive_error_test_() ->
    [
        %% "Directives" makes '%YAMLfoo' a reserved name, not the YAML directive
        ?_assertEqual(
            {ok, null},
            nyaml:decode(<<"%YAMLfoo\n---">>)
        ),
        %% Invalid YAML directive - no version
        ?_assertEqual(
            {error, invalid_yaml_directive},
            nyaml:decode(<<"%YAML \n---">>)
        ),
        %% Invalid YAML directive - incomplete version
        ?_assertEqual(
            {error, invalid_yaml_directive},
            nyaml:decode(<<"%YAML 1\n---">>)
        ),
        %% Invalid YAML directive - no minor version
        ?_assertEqual(
            {error, invalid_yaml_directive},
            nyaml:decode(<<"%YAML 1.\n---">>)
        ),
        %% Duplicate YAML directive
        ?_assertEqual(
            {error, duplicate_yaml_directive},
            nyaml:decode(<<"%YAML 1.2\n%YAML 1.1\n---">>)
        ),
        %% Directive without document start marker
        ?_assertEqual(
            {error, directive_without_document},
            nyaml:decode(<<"%YAML 1.2\nvalue">>)
        ),
        %% "Directives" makes '%TAGfoo' a reserved name, not the TAG directive
        ?_assertEqual(
            {ok, null},
            nyaml:decode(<<"%TAGfoo\n---">>)
        ),
        %% Invalid TAG handle (no leading !)
        ?_assertEqual(
            {error, invalid_tag_handle},
            nyaml:decode(<<"%TAG foo bar\n---">>)
        ),
        %% Invalid tag handle name (no content after !)
        ?_assertEqual(
            {error, invalid_tag_handle_name},
            nyaml:decode(<<"%TAG !\n---">>)
        )
    ].

%% ============================================================
%% Document Structure Error Tests
%% ============================================================

nyaml_document_error_test_() ->
    [
        %% Invalid content after document end
        ?_assertEqual(
            {error, invalid_content_after_document_end},
            nyaml:decode(<<"---\nvalue\n...invalid">>)
        ),
        %% Unexpected content after document end (closing bracket)
        ?_assertMatch(
            {error, {unexpected_content, _}},
            nyaml:decode(<<"value\n...\n]">>)
        ),
        %% Unexpected content after document end (closing brace)
        ?_assertMatch(
            {error, {unexpected_content, _}},
            nyaml:decode(<<"value\n...\n}">>)
        ),
        %% Anchor on block indicator
        ?_assertEqual(
            {error, anchor_on_block_indicator},
            nyaml:decode(<<"&anchor - item">>)
        ),
        %% Block mapping on document start line with anchor
        ?_assertEqual(
            {error, block_mapping_on_document_start_line},
            nyaml:decode(<<"--- &anchor key: value">>)
        )
    ].

%% The "Streams" section gives two stream positions. After a '...' suffix any
%% document may open. After a document that no '...' closed, only a further
%% suffix, a comment, or an explicit document may follow.

nyaml_bare_document_after_suffix_test_() ->
    [
        %% Bare Documents, 7Z25
        ?_assertEqual(
            {ok, [<<"scalar1">>, #{<<"key">> => <<"value">>}]},
            nyaml:decode_all(<<"---\nscalar1\n...\nkey: value\n">>)
        ),
        %% Bare Documents, M7A3, two suffixes and a comment-only region
        ?_assertEqual(
            {ok, [<<"Bare document">>, <<"%!PS-Adobe-2.0 # Not the first line\n">>]},
            nyaml:decode_all(
                <<"Bare\ndocument\n...\n# No document\n...\n|\n",
                    "%!PS-Adobe-2.0 # Not the first line\n">>
            )
        ),
        %% Document Prefix, a comment between the suffix and the next document
        ?_assertEqual(
            {ok, [<<"first">>, <<"second">>]},
            nyaml:decode_all(<<"first\n...\n# a comment\nsecond\n">>)
        )
    ].

nyaml_directives_document_after_suffix_test_() ->
    [
        %% Directives Documents, 6ZKB
        ?_assertEqual(
            {ok, [<<"Document">>, null, #{<<"matches %">> => 20}]},
            nyaml:decode_all(<<"Document\n---\n# Empty\n...\n%YAML 1.2\n---\nmatches %: 20\n">>)
        ),
        %% Directives Documents, 9DXL, the same stream over a mapping
        ?_assertEqual(
            {ok, [#{<<"Mapping">> => <<"Document">>}, null, #{<<"matches %">> => 20}]},
            nyaml:decode_all(
                <<"Mapping: Document\n---\n# Empty\n...\n%YAML 1.2\n---\nmatches %: 20\n">>
            )
        ),
        %% Document Markers, a '%TAG' block reopens after the suffix
        ?_assertEqual(
            {ok, [<<"first">>, <<"second">>]},
            nyaml:decode_all(
                <<"%TAG !e! tag:example.com,2000:\n---\nfirst\n...\n",
                    "%TAG !e! tag:example.com,2000:\n---\nsecond\n">>
            )
        )
    ].

nyaml_directive_without_suffix_test_() ->
    [
        %% Directives Documents, MUS6/01, a second '%YAML' that no '...' closed
        ?_assertEqual(
            {error, directive_without_document_end},
            nyaml:decode_all(<<"%YAML 1.2\n---\n%YAML 1.2\n---\n">>)
        ),
        %% Indicator Characters, '%' is c-directive and opens no plain scalar
        ?_assertEqual(
            {error, directive_without_document_end},
            nyaml:decode_all(<<"---\n%not-a-directive\n">>)
        )
    ].

nyaml_document_suffix_test_() ->
    [
        %% Document Markers, a suffix with nothing after it closes one document
        ?_assertEqual(
            {ok, [<<"only">>]},
            nyaml:decode_all(<<"only\n...\n">>)
        ),
        %% Document Markers, the same after an explicit document
        ?_assertEqual(
            {ok, [<<"only">>]},
            nyaml:decode_all(<<"---\nonly\n...\n">>)
        ),
        %% Document Markers, a comment after the suffix is not a document
        ?_assertEqual(
            {ok, [<<"only">>]},
            nyaml:decode_all(<<"---\nonly\n...\n# trailing\n">>)
        ),
        %% Streams, a suffix with no document before it yields no document
        ?_assertEqual(
            {ok, []},
            nyaml:decode_all(<<"...\n">>)
        ),
        %% Streams, an explicit document may follow with no suffix between
        ?_assertEqual(
            {ok, [<<"a">>, <<"b">>]},
            nyaml:decode_all(<<"a\n---\nb\n">>)
        ),
        %% Streams, a bare document may not follow without a suffix
        ?_assertEqual(
            {error, {trailing_content_after_document, <<"key: value">>}},
            nyaml:decode_all(<<"scalar\nkey: value">>)
        )
    ].

%% ============================================================
%% Tag Error Tests
%% ============================================================

nyaml_tag_error_test_() ->
    [
        %% Unterminated verbatim tag
        ?_assertEqual(
            {error, unterminated_verbatim_tag},
            nyaml:decode(<<"!<tag value">>)
        ),
        %% Invalid tag name (starts with invalid char)
        ?_assertMatch(
            {error, {invalid_tag_name, _}},
            nyaml:decode(<<"!! value">>)
        ),
        %% Undefined tag handle
        ?_assertMatch(
            {error, {undefined_tag_handle, _}},
            nyaml:decode(<<"!custom!name value">>)
        ),
        %% Invalid tag character
        ?_assertMatch(
            {error, {invalid_tag_character, _}},
            nyaml:decode(<<"!name[value">>)
        )
    ].

%% ============================================================
%% Anchor/Alias Error Tests
%% ============================================================

nyaml_anchor_alias_error_test_() ->
    [
        %% Undefined alias
        ?_assertMatch(
            {error, {undefined_alias, _}},
            nyaml:decode(<<"*undefined">>)
        ),
        %% Invalid anchor name (empty)
        ?_assertMatch(
            {error, {invalid_anchor_name, _}},
            nyaml:decode(<<"& value">>)
        ),
        %% Invalid anchor name in flow
        ?_assertMatch(
            {error, {invalid_anchor_name, _}},
            nyaml:decode(<<"[& value]">>)
        )
    ].

%% ============================================================
%% Plain Scalar Error Tests
%% ============================================================

nyaml_plain_scalar_error_test_() ->
    [
        %% Comment with continuation after
        ?_assertEqual(
            {error, content_after_comment},
            nyaml:decode(<<"value # comment\n  continuation">>)
        ),
        %% Mapping indicator in plain scalar continuation
        ?_assertMatch(
            {error, {mapping_indicator_in_plain_scalar, _}},
            nyaml:decode(<<"line1\n  key: value">>)
        ),
        %% Sequence indicator in plain scalar continuation
        ?_assertMatch(
            {error, {sequence_indicator_in_plain_scalar, _}},
            nyaml:decode(<<"line1\n  - item">>)
        )
    ].

%% ============================================================
%% Version Number Parsing Tests
%% ============================================================

nyaml_version_parsing_test_() ->
    [
        %% Valid YAML 1.2 directive
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml:decode(<<"%YAML 1.2\n---\nvalue">>)
        ),
        %% Valid YAML 1.1 directive
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml:decode(<<"%YAML 1.1\n---\nvalue">>)
        ),
        %% YAML directive with comment
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml:decode(<<"%YAML 1.2 # comment\n---\nvalue">>)
        ),
        %% YAML directive with tab after version
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml:decode(<<"%YAML 1.2\t\n---\nvalue">>)
        ),
        %% Unknown directive (should be ignored)
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml:decode(<<"%CUSTOM directive\n---\nvalue">>)
        )
    ].

%% ============================================================
%% Tag Directive Tests
%% ============================================================

nyaml_tag_directive_test_() ->
    [
        %% Valid TAG directive with secondary handle
        ?_assertEqual(
            {ok, 42},
            nyaml:decode(<<"%TAG !! tag:yaml.org,2002:\n---\n!!int 42">>)
        ),
        %% TAG directive with primary handle
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml:decode(<<"%TAG ! tag:example.com,2000:\n---\n!type value">>)
        )
    ].

%% ============================================================
%% Flow Key Edge Cases
%% ============================================================

nyaml_flow_key_edge_test_() ->
    [
        %% Explicit key in flow mapping
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"{? key : value}">>)
        ),
        %% Explicit key with newline
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"{?\n  key\n: value}">>)
        ),
        %% Empty key in flow resolves to null
        ?_assertEqual(
            {ok, #{null => <<"value">>}},
            nyaml:decode(<<"{: value}">>)
        ),
        %% Tagged key in flow
        ?_assertEqual(
            {ok, #{42 => <<"value">>}},
            nyaml:decode(<<"{!!int 42: value}">>)
        ),
        %% Anchored key in flow
        ?_assertEqual(
            {ok, #{<<"key">> => <<"key">>}},
            nyaml:decode(<<"{&a key: *a}">>)
        ),
        %% Aliased key in flow (alias needs space before colon)
        ?_assertEqual(
            {ok, [<<"first">>, #{<<"first">> => <<"value">>}]},
            nyaml:decode(<<"- &a first\n- {*a : value}">>)
        )
    ].

%% ============================================================
%% Document End Marker Tests
%% ============================================================

nyaml_document_end_test_() ->
    [
        %% Document end with space
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml:decode(<<"value\n... ">>)
        ),
        %% Document end with tab
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml:decode(<<"value\n...\t">>)
        ),
        %% Document end with comment
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml:decode(<<"value\n... # comment">>)
        ),
        %% Multiple document markers
        ?_assertEqual(
            {ok, <<"first">>},
            nyaml:decode(<<"---\nfirst\n...\n---\nsecond">>)
        ),
        %% Document end followed by new document
        ?_assertEqual(
            {ok, <<"first">>},
            nyaml:decode(<<"first\n...\n---\nsecond">>)
        )
    ].

%% ============================================================
%% Parser Internal Edge Cases
%% ============================================================

nyaml_parser_internal_edge_test_() ->
    [
        %% to_string with list
        ?_assertEqual(
            <<"[list]">>,
            nyaml_parser:to_string([1, 2, 3])
        ),
        %% to_string with map
        ?_assertEqual(
            <<"{map}">>,
            nyaml_parser:to_string(#{a => 1})
        ),
        %% resolve_tag with int
        ?_assertEqual(
            {ok, 42},
            nyaml_parser:resolve_tag(<<"int">>, <<"42">>, nyaml_parser:new_ctx())
        ),
        %% resolve_tag with float
        ?_assertEqual(
            {ok, 3.14},
            nyaml_parser:resolve_tag(<<"float">>, 3.14, nyaml_parser:new_ctx())
        ),
        %% resolve_tag with float from int
        ?_assertEqual(
            {ok, 42.0},
            nyaml_parser:resolve_tag(<<"float">>, 42, nyaml_parser:new_ctx())
        ),
        %% resolve_tag with bool true
        ?_assertEqual(
            {ok, true},
            nyaml_parser:resolve_tag(<<"bool">>, <<"true">>, nyaml_parser:new_ctx())
        ),
        %% resolve_tag with bool false
        ?_assertEqual(
            {ok, false},
            nyaml_parser:resolve_tag(<<"bool">>, <<"false">>, nyaml_parser:new_ctx())
        ),
        %% resolve_tag with unknown tag
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml_parser:resolve_tag(<<"unknown">>, <<"value">>, nyaml_parser:new_ctx())
        ),
        %% resolve_tag with null
        ?_assertEqual(
            {ok, null},
            nyaml_parser:resolve_tag(<<"null">>, <<"something">>, nyaml_parser:new_ctx())
        ),
        %% resolve_tag with str from null
        ?_assertEqual(
            {ok, <<>>},
            nyaml_parser:resolve_tag(<<"str">>, null, nyaml_parser:new_ctx())
        )
    ].

%% ============================================================
%% Flow Value Edge Cases
%% ============================================================

nyaml_flow_value_edge_test_() ->
    [
        %% Tagged value at end of flow sequence
        ?_assertEqual(
            {ok, [null]},
            nyaml:decode(<<"[!!null]">>)
        ),
        %% Tagged value at end of flow mapping
        ?_assertEqual(
            {ok, #{<<"key">> => null}},
            nyaml:decode(<<"{key: !!null}">>)
        ),
        %% Tagged str at end
        ?_assertEqual(
            {ok, [<<>>]},
            nyaml:decode(<<"[!!str]">>)
        ),
        %% Anchor in flow value
        ?_assertEqual(
            {ok, [1, 1]},
            nyaml:decode(<<"[&a 1, *a]">>)
        ),
        %% Local tag in flow
        ?_assertEqual(
            {ok, [<<"value">>]},
            nyaml:decode(<<"[!tag value]">>)
        )
    ].

%% ============================================================
%% Scalar Continuation Edge Cases
%% ============================================================

nyaml_scalar_continuation_edge_test_() ->
    [
        %% Scalar with CRLF continuation
        ?_assertEqual(
            {ok, <<"line1 line2">>},
            nyaml:decode(<<"line1\r\nline2">>)
        ),
        %% Scalar stops at document start
        ?_assertEqual(
            {ok, <<"line1">>},
            nyaml:decode(<<"line1\n---\nline2">>)
        ),
        %% Scalar stops at document end
        ?_assertEqual(
            {ok, <<"line1">>},
            nyaml:decode(<<"line1\n...">>)
        ),
        %% Hash not comment (no space before)
        ?_assertEqual(
            {ok, <<"value#notcomment">>},
            nyaml:decode(<<"value#notcomment">>)
        )
    ].

%% ============================================================
%% Block Explicit Key Additional Tests
%% ============================================================

nyaml_block_explicit_key_additional_test_() ->
    [
        %% Simple explicit key
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"? key\n: value">>)
        ),
        %% Explicit key with colon becomes multiword key
        ?_assertEqual(
            {ok, #{<<"key: value">> => null}},
            nyaml:decode(<<"? key: value">>)
        ),
        %% Explicit key with null value
        ?_assertEqual(
            {ok, #{<<"key">> => null}},
            nyaml:decode(<<"? key">>)
        ),
        %% Explicit key multiline
        ?_assertEqual(
            {ok, #{<<"key part1 part2">> => <<"value">>}},
            nyaml:decode(<<"? key part1\n  part2\n: value">>)
        ),
        %% Multiple explicit keys
        ?_assertEqual(
            {ok, #{<<"k1">> => <<"v1">>, <<"k2">> => <<"v2">>}},
            nyaml:decode(<<"? k1\n: v1\n? k2\n: v2">>)
        ),
        %% Explicit key at end of file
        ?_assertEqual(
            {ok, #{<<"key">> => null}},
            nyaml:decode(<<"? key\n">>)
        )
    ].

%% ============================================================
%% Block Indentation Error Tests
%% ============================================================

nyaml_block_indentation_error_test_() ->
    [
        %% Tab in indentation (in nested context)
        ?_assertEqual(
            {error, tab_in_indentation},
            nyaml:decode(<<"key:\n\tvalue">>)
        ),
        %% Tab in sequence indentation
        ?_assertEqual(
            {error, tab_in_indentation},
            nyaml:decode(<<"-\n\titem">>)
        )
    ].

%% ============================================================
%% Block Sequence Item Edge Cases
%% ============================================================

nyaml_block_sequence_item_test_() ->
    [
        %% Sequence item with empty value
        ?_assertEqual(
            {ok, [null]},
            nyaml:decode(<<"-">>)
        ),
        %% Sequence item with only newline
        ?_assertEqual(
            {ok, [null]},
            nyaml:decode(<<"-\n">>)
        ),
        %% Nested sequence
        ?_assertEqual(
            {ok, [[1, 2], [3, 4]]},
            nyaml:decode(<<"-\n  - 1\n  - 2\n-\n  - 3\n  - 4">>)
        ),
        %% Sequence with nested mapping
        ?_assertEqual(
            {ok, [#{<<"a">> => 1}, #{<<"b">> => 2}]},
            nyaml:decode(<<"- a: 1\n- b: 2">>)
        ),
        %% Sequence item with blank lines
        ?_assertEqual(
            {ok, [<<"value">>]},
            nyaml:decode(<<"-\n\n  value">>)
        )
    ].

%% ============================================================
%% Block Mapping Value Edge Cases
%% ============================================================

nyaml_block_mapping_value_test_() ->
    [
        %% Mapping with empty value
        ?_assertEqual(
            {ok, #{<<"key">> => null}},
            nyaml:decode(<<"key:">>)
        ),
        %% Mapping with only newline value
        ?_assertEqual(
            {ok, #{<<"key">> => null}},
            nyaml:decode(<<"key:\n">>)
        ),
        %% Nested mapping
        ?_assertEqual(
            {ok, #{<<"outer">> => #{<<"inner">> => <<"value">>}}},
            nyaml:decode(<<"outer:\n  inner: value">>)
        ),
        %% Mapping with deeply nested value
        ?_assertEqual(
            {ok, #{<<"a">> => #{<<"b">> => #{<<"c">> => <<"d">>}}}},
            nyaml:decode(<<"a:\n  b:\n    c: d">>)
        )
    ].

%% ============================================================
%% Block Anchor/Alias Edge Cases
%% ============================================================

nyaml_block_anchor_alias_test_() ->
    [
        %% Anchor on mapping key
        ?_assertEqual(
            {ok, #{<<"key">> => <<"key">>}},
            nyaml:decode(<<"&a key: *a">>)
        ),
        %% Anchor on nested value
        ?_assertEqual(
            {ok, #{<<"a">> => <<"value">>, <<"b">> => <<"value">>}},
            nyaml:decode(<<"a: &x value\nb: *x">>)
        ),
        %% Anchor on sequence item
        ?_assertEqual(
            {ok, [<<"item">>, <<"item">>]},
            nyaml:decode(<<"- &a item\n- *a">>)
        ),
        %% Anchor on mapping
        ?_assertEqual(
            {ok, #{<<"a">> => #{<<"k">> => <<"v">>}, <<"b">> => #{<<"k">> => <<"v">>}}},
            nyaml:decode(<<"a: &x\n  k: v\nb: *x">>)
        )
    ].

%% ============================================================
%% Block Scalar with Comment Additional Tests
%% ============================================================

nyaml_block_scalar_comment_additional_test_() ->
    [
        %% Mapping value followed by comment
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"key: value # comment">>)
        ),
        %% Sequence item followed by comment
        ?_assertEqual(
            {ok, [<<"value">>]},
            nyaml:decode(<<"- value # comment">>)
        ),
        %% Comment inside quotes is preserved
        ?_assertEqual(
            {ok, <<"value # not a comment">>},
            nyaml:decode(<<"\"value # not a comment\"">>)
        ),
        %% Single quoted with hash
        ?_assertEqual(
            {ok, <<"value # preserved">>},
            nyaml:decode(<<"'value # preserved'">>)
        )
    ].

%% ============================================================
%% Block Flow Collection Edge Cases
%% ============================================================

nyaml_block_flow_collection_test_() ->
    [
        %% Flow sequence as mapping value
        ?_assertEqual(
            {ok, #{<<"key">> => [1, 2, 3]}},
            nyaml:decode(<<"key: [1, 2, 3]">>)
        ),
        %% Flow mapping as mapping value
        ?_assertEqual(
            {ok, #{<<"key">> => #{<<"a">> => 1}}},
            nyaml:decode(<<"key: {a: 1}">>)
        ),
        %% Flow sequence as sequence item
        ?_assertEqual(
            {ok, [[1, 2]]},
            nyaml:decode(<<"- [1, 2]">>)
        ),
        %% Flow mapping as sequence item
        ?_assertEqual(
            {ok, [#{<<"a">> => 1}]},
            nyaml:decode(<<"- {a: 1}">>)
        ),
        %% Nested flow in block
        ?_assertEqual(
            {ok, #{<<"key">> => [#{<<"nested">> => [1]}]}},
            nyaml:decode(<<"key: [{nested: [1]}]">>)
        )
    ].

%% ============================================================
%% Block Quoted Key Additional Tests
%% ============================================================

nyaml_block_quoted_key_additional_test_() ->
    [
        %% Double quoted key
        ?_assertEqual(
            {ok, #{<<"key with space">> => <<"value">>}},
            nyaml:decode(<<"\"key with space\": value">>)
        ),
        %% Single quoted key
        ?_assertEqual(
            {ok, #{<<"key: with: colons">> => <<"value">>}},
            nyaml:decode(<<"'key: with: colons': value">>)
        ),
        %% Double quoted key with escape
        ?_assertEqual(
            {ok, #{<<"key\nwith\nnewlines">> => <<"value">>}},
            nyaml:decode(<<"\"key\\nwith\\nnewlines\": value">>)
        ),
        %% Flow sequence as key
        ?_assertEqual(
            {ok, #{[1, 2] => <<"value">>}},
            nyaml:decode(<<"[1, 2]: value">>)
        ),
        %% Flow mapping as key
        ?_assertEqual(
            {ok, #{#{<<"a">> => 1} => <<"value">>}},
            nyaml:decode(<<"{a: 1}: value">>)
        )
    ].

%% ============================================================
%% Block Empty and Whitespace Tests
%% ============================================================

nyaml_block_whitespace_test_() ->
    [
        %% Empty document
        ?_assertEqual(
            {ok, null},
            nyaml:decode(<<"">>)
        ),
        %% Only whitespace
        ?_assertEqual(
            {ok, null},
            nyaml:decode(<<"   ">>)
        ),
        %% Only newlines
        ?_assertEqual(
            {ok, null},
            nyaml:decode(<<"\n\n\n">>)
        ),
        %% Only comments
        ?_assertEqual(
            {ok, null},
            nyaml:decode(<<"# comment\n# another">>)
        ),
        %% Mapping with blank lines between
        ?_assertEqual(
            {ok, #{<<"a">> => 1, <<"b">> => 2}},
            nyaml:decode(<<"a: 1\n\nb: 2">>)
        )
    ].

%% ============================================================
%% Block Tag Edge Cases
%% ============================================================

nyaml_block_tag_test_() ->
    [
        %% Tagged mapping value
        ?_assertEqual(
            {ok, #{<<"key">> => 42}},
            nyaml:decode(<<"key: !!int 42">>)
        ),
        %% Tagged sequence item
        ?_assertEqual(
            {ok, [<<"42">>]},
            nyaml:decode(<<"- !!str 42">>)
        ),
        %% Verbatim tag
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml:decode(<<"!<tag:example.com:type> value">>)
        ),
        %% Local tag
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml:decode(<<"!custom value">>)
        ),
        %% Tagged null
        ?_assertEqual(
            {ok, null},
            nyaml:decode(<<"!!null null">>)
        )
    ].

%% ============================================================
%% Parser Scalar Until Delimiter Edge Cases
%% ============================================================

nyaml_parser_scalar_delimiter_test_() ->
    [
        %% Scalar with CRLF in flow
        ?_assertEqual(
            {ok, [<<"a b">>]},
            nyaml:decode(<<"[a\r\nb]">>)
        ),
        %% Hash not comment in flow scalar
        ?_assertEqual(
            {ok, [<<"a#b">>]},
            nyaml:decode(<<"[a#b]">>)
        ),
        %% Hash as comment with space in flow (needs newline before close)
        ?_assertEqual(
            {ok, [<<"a">>]},
            nyaml:decode(<<"[a # comment\n]">>)
        ),
        %% Empty flow sequence
        ?_assertEqual(
            {ok, []},
            nyaml:decode(<<"[]">>)
        ),
        %% Empty flow mapping
        ?_assertEqual(
            {ok, #{}},
            nyaml:decode(<<"{}">>)
        )
    ].

%% ============================================================
%% Anchor Followed by Alias Error Tests
%% ============================================================

nyaml_anchor_followed_by_alias_test_() ->
    [
        %% Anchor followed by alias in block value
        ?_assertEqual(
            {error, anchor_followed_by_alias},
            nyaml:decode(<<"key:\n  &anchor *alias">>)
        ),
        %% Anchor followed by alias at top level
        ?_assertEqual(
            {error, anchor_followed_by_alias},
            nyaml:decode(<<"key: &a *b">>)
        )
    ].

%% ============================================================
%% Anchor on Block Indicator Tests
%% ============================================================

nyaml_anchor_block_indicator_test_() ->
    [
        %% Anchor with bare dash (already tested in nyaml_document_error_test_)
        ?_assertEqual(
            {error, anchor_on_block_indicator},
            nyaml:decode(<<"&anchor - item">>)
        ),
        %% Anchor on sequence indicator in mapping value
        ?_assertEqual(
            {error, anchor_on_block_indicator},
            nyaml:decode(<<"key:\n  &anchor - item">>)
        )
    ].

%% ============================================================
%% Invalid Alias Syntax Tests
%% ============================================================

nyaml_invalid_alias_syntax_test_() ->
    [
        %% Alias with trailing content that's not colon
        ?_assertMatch(
            {error, {invalid_alias_syntax, _}},
            nyaml:decode(<<"key:\n  *alias extra">>)
        ),
        %% Alias with content after at block level
        ?_assertMatch(
            {error, {invalid_alias_syntax, _}},
            nyaml:decode(<<"outer:\n  *alias value">>)
        )
    ].

%% ============================================================
%% Block Explicit Value Indicator Tests
%% ============================================================

nyaml_explicit_value_indicator_test_() ->
    [
        %% Explicit key continuation treated as multiword key
        ?_assertEqual(
            {ok, #{<<"key notvalue">> => null}},
            nyaml:decode(<<"? key\nnotvalue">>)
        ),
        %% Explicit key with indented continuation
        ?_assertEqual(
            {ok, #{<<"key notvalue">> => null}},
            nyaml:decode(<<"? key\n  notvalue">>)
        )
    ].

%% ============================================================
%% Flow as Block Mapping Key Tests
%% ============================================================

nyaml_flow_as_block_key_test_() ->
    [
        %% Flow sequence as block mapping key at doc level
        ?_assertEqual(
            {ok, #{[1, 2] => <<"value">>}},
            nyaml:decode(<<"[1, 2]: value">>)
        ),
        %% Flow mapping as block mapping key at doc level
        ?_assertEqual(
            {ok, #{#{<<"a">> => 1} => <<"value">>}},
            nyaml:decode(<<"{a: 1}: value">>)
        ),
        %% Flow sequence key with nested mapping
        ?_assertEqual(
            {ok, #{[1] => #{<<"nested">> => <<"value">>}}},
            nyaml:decode(<<"[1]:\n  nested: value">>)
        )
    ].

%% ============================================================
%% Quoted Block Mapping Key at Doc Level Tests
%% ============================================================

nyaml_quoted_block_mapping_key_test_() ->
    [
        %% Double quoted as mapping key at document level
        ?_assertEqual(
            {ok, #{<<"quoted key">> => <<"value">>}},
            nyaml:decode(<<"\"quoted key\": value">>)
        ),
        %% Single quoted as mapping key at document level
        ?_assertEqual(
            {ok, #{<<"quoted: colon">> => <<"value">>}},
            nyaml:decode(<<"'quoted: colon': value">>)
        ),
        %% Double quoted followed by nested structure
        ?_assertEqual(
            {ok, #{<<"key">> => #{<<"nested">> => 1}}},
            nyaml:decode(<<"\"key\":\n  nested: 1">>)
        )
    ].

%% ============================================================
%% Global Tag with Mapping Indicator Tests
%% ============================================================

nyaml_tag_mapping_indicator_test_() ->
    [
        %% Global tag followed by colon-space
        ?_assertEqual(
            {ok, #{null => <<"value">>}},
            nyaml:decode(<<"!!null : value">>)
        ),
        %% Global tag as key
        ?_assertEqual(
            {ok, #{42 => <<"value">>}},
            nyaml:decode(<<"!!int 42: value">>)
        ),
        %% Tag with just colon at end
        ?_assertEqual(
            {ok, #{null => null}},
            nyaml:decode(<<"!!null :">>)
        )
    ].

%% ============================================================
%% Block Anchored Inline Flow Collection Tests
%% ============================================================

nyaml_anchored_inline_flow_test_() ->
    [
        %% Anchor with inline flow sequence
        ?_assertEqual(
            {ok, #{<<"key">> => [1, 2], <<"ref">> => [1, 2]}},
            nyaml:decode(<<"key: &a [1, 2]\nref: *a">>)
        ),
        %% Anchor with inline flow mapping
        ?_assertEqual(
            {ok, #{<<"key">> => #{<<"x">> => 1}, <<"ref">> => #{<<"x">> => 1}}},
            nyaml:decode(<<"key: &a {x: 1}\nref: *a">>)
        ),
        %% Anchor in block value then flow sequence
        ?_assertEqual(
            {ok, #{<<"key">> => [1, 2]}},
            nyaml:decode(<<"key:\n  &a [1, 2]">>)
        )
    ].

%% ============================================================
%% Local Tag in Block Value Tests
%% ============================================================

nyaml_local_tag_block_test_() ->
    [
        %% Local tag in block value
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"key:\n  !custom value">>)
        ),
        %% Local tag with nested content
        ?_assertEqual(
            {ok, #{<<"key">> => #{<<"nested">> => 1}}},
            nyaml:decode(<<"key:\n  !custom\n    nested: 1">>)
        )
    ].

%% ============================================================
%% Block Value Dispatch Edge Cases Tests
%% ============================================================

nyaml_block_value_dispatch_test_() ->
    [
        %% Double quoted value in block
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value with: colon">>}},
            nyaml:decode(<<"key:\n  \"value with: colon\"">>)
        ),
        %% Single quoted value in block
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"key:\n  'value'">>)
        ),
        %% Flow sequence value in block
        ?_assertEqual(
            {ok, #{<<"key">> => [1, 2, 3]}},
            nyaml:decode(<<"key:\n  [1, 2, 3]">>)
        ),
        %% Flow mapping value in block
        ?_assertEqual(
            {ok, #{<<"key">> => #{<<"a">> => 1}}},
            nyaml:decode(<<"key:\n  {a: 1}">>)
        )
    ].

%% ============================================================
%% Multiline Flow Collection Value Tests
%% ============================================================

nyaml_multiline_flow_test_() ->
    [
        %% Flow sequence spanning multiple lines as value
        ?_assertEqual(
            {ok, #{<<"key">> => [1, 2, 3]}},
            nyaml:decode(<<"key: [\n  1,\n  2,\n  3\n]">>)
        ),
        %% Flow mapping spanning multiple lines as value
        ?_assertEqual(
            {ok, #{<<"key">> => #{<<"a">> => 1, <<"b">> => 2}}},
            nyaml:decode(<<"key: {\n  a: 1,\n  b: 2\n}">>)
        )
    ].

%% ============================================================
%% Alias as Mapping Key in Block Tests
%% ============================================================

nyaml_alias_mapping_key_block_test_() ->
    [
        %% Alias used as block mapping key
        ?_assertEqual(
            {ok, #{<<"keyname">> => <<"value">>}},
            nyaml:decode(<<"&a keyname: value">>)
        ),
        %% Alias key followed by alias value
        ?_assertEqual(
            {ok, #{<<"x">> => <<"x">>}},
            nyaml:decode(<<"&a x: *a">>)
        )
    ].

%% ============================================================
%% Empty Line Handling in Block Scalar Tests
%% ============================================================

nyaml_empty_line_block_scalar_test_() ->
    [
        %% Sequence item with empty line collapses to single newline
        ?_assertEqual(
            {ok, [<<"line1\nline3">>]},
            nyaml:decode(<<"- line1\n\n  line3">>)
        ),
        %% Mapping value with empty line before content
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"key:\n\n  value">>)
        )
    ].

%% ============================================================
%% Comment Handling Edge Cases Additional Tests
%% ============================================================

nyaml_comment_edge_additional_test_() ->
    [
        %% Comment only lines between mappings
        ?_assertEqual(
            {ok, #{<<"a">> => 1, <<"b">> => 2}},
            nyaml:decode(<<"a: 1\n# comment\nb: 2">>)
        ),
        %% Comment only lines between sequence items
        ?_assertEqual(
            {ok, [1, 2]},
            nyaml:decode(<<"- 1\n# comment\n- 2">>)
        ),
        %% Multiple consecutive comments
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"# comment 1\n# comment 2\nkey: value">>)
        )
    ].

%% ============================================================
%% Flow Key with Tag Tests
%% ============================================================

nyaml_flow_key_tag_test_() ->
    [
        %% Tagged key at end in flow
        ?_assertEqual(
            {ok, #{null => null}},
            nyaml:decode(<<"{!!null: }">>)
        ),
        %% Tagged str key at end in flow
        ?_assertEqual(
            {ok, #{<<>> => null}},
            nyaml:decode(<<"{!!str: }">>)
        ),
        %% Tagged value resolution in flow key
        ?_assertEqual(
            {ok, #{42 => <<"value">>}},
            nyaml:decode(<<"{!!int 42: value}">>)
        )
    ].

%% ============================================================
%% Colon in Flow Scalar Edge Cases Tests
%% ============================================================

nyaml_flow_colon_edge_test_() ->
    [
        %% Colon at end of flow scalar
        ?_assertEqual(
            {ok, #{<<"key">> => null}},
            nyaml:decode(<<"{key:}">>)
        ),
        %% Colon with comma after
        ?_assertEqual(
            {ok, #{<<"key">> => null, <<"key2">> => <<"value">>}},
            nyaml:decode(<<"{key:, key2: value}">>)
        ),
        %% Colon with brace after
        ?_assertEqual(
            {ok, #{<<"key">> => null}},
            nyaml:decode(<<"{key:}">>)
        )
    ].

%% ============================================================
%% Parser Skip Functions Tests
%% ============================================================

nyaml_parser_skip_test_() ->
    [
        %% skip_whitespace_and_comments with nested comments
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml:decode(<<"  # comment\n  # another\nvalue">>)
        ),
        %% strip_comment strips the comment portion
        ?_assertEqual(
            <<"value">>,
            nyaml_parser:strip_comment(<<"value # stripped">>)
        )
    ].

%% ============================================================
%% Flow Value Empty After Tag Tests
%% ============================================================

nyaml_flow_value_empty_tag_test_() ->
    [
        %% Tag with comma immediately after
        ?_assertEqual(
            {ok, [null, <<"a">>]},
            nyaml:decode(<<"[!!null, a]">>)
        ),
        %% Tag with bracket immediately after
        ?_assertEqual(
            {ok, [null]},
            nyaml:decode(<<"[!!null]">>)
        ),
        %% str tag empty value
        ?_assertEqual(
            {ok, [<<>>]},
            nyaml:decode(<<"[!!str]">>)
        )
    ].

%% ============================================================
%% Implicit Null Key in Flow Tests
%% ============================================================

nyaml_implicit_null_flow_test_() ->
    [
        %% Null key with space after colon
        ?_assertEqual(
            {ok, [#{null => <<"value">>}]},
            nyaml:decode(<<"[: value]">>)
        ),
        %% Null key with tab after colon
        ?_assertEqual(
            {ok, [#{null => <<"value">>}]},
            nyaml:decode(<<"[:\tvalue]">>)
        )
    ].

%% ============================================================
%% Block Scalar with Continuation Tests
%% ============================================================

nyaml_block_continuation_test_() ->
    [
        %% Plain scalar stops at sequence indicator
        ?_assertEqual(
            {ok, #{<<"key">> => [<<"item">>]}},
            nyaml:decode(<<"key:\n  - item">>)
        ),
        %% Plain scalar stops at mapping indicator
        ?_assertEqual(
            {ok, #{<<"outer">> => #{<<"inner">> => <<"value">>}}},
            nyaml:decode(<<"outer:\n  inner: value">>)
        )
    ].

%% ============================================================
%% Document Marker Handling Tests
%% ============================================================

nyaml_document_marker_test_() ->
    [
        %% Document start not at beginning of line
        ?_assertEqual(
            {ok, <<"---value">>},
            nyaml:decode(<<"---value">>)
        ),
        %% Document end followed by newline
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml:decode(<<"value\n...\n">>)
        ),
        %% Document start with CRLF
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml:decode(<<"---\r\nvalue">>)
        )
    ].

%% ============================================================
%% Explicit Key with Block Scalar Tests
%% ============================================================

nyaml_explicit_key_block_scalar_test_() ->
    [
        %% Explicit key with literal block scalar
        ?_assertEqual(
            {ok, #{<<"line1\nline2\n">> => <<"value">>}},
            nyaml:decode(<<"? |\n  line1\n  line2\n: value">>)
        ),
        %% Explicit key with folded block scalar
        ?_assertEqual(
            {ok, #{<<"line1 line2\n">> => <<"value">>}},
            nyaml:decode(<<"? >\n  line1\n  line2\n: value">>)
        )
    ].

%% ============================================================
%% Block Parse With Less Indent Tests
%% ============================================================

nyaml_block_less_indent_test_() ->
    [
        %% Adjacent keys at same indent become nested
        ?_assertEqual(
            {ok, #{<<"outer">> => #{<<"sibling">> => <<"value">>}}},
            nyaml:decode(<<"outer:\nsibling: value">>)
        ),
        %% Nested mapping with dedented sibling
        ?_assertEqual(
            {ok, #{<<"a">> => #{<<"b">> => null}, <<"c">> => <<"d">>}},
            nyaml:decode(<<"a:\n  b:\nc: d">>)
        )
    ].

%% ============================================================
%% Flow Scalar Newline Edge Cases Tests
%% ============================================================

nyaml_flow_scalar_newline_test_() ->
    [
        %% Flow scalar with comment then newline then close
        ?_assertEqual(
            {ok, [<<"a">>]},
            nyaml:decode(<<"[a # comment\n]">>)
        ),
        %% Flow scalar mapping key appearance after newline
        ?_assertEqual(
            {ok, [<<"value">>]},
            nyaml:decode(<<"[value\n]">>)
        )
    ].

%% ============================================================
%% Missing Comma in Flow Sequence Tests
%% ============================================================

nyaml_missing_comma_flow_test_() ->
    [
        %% Missing comma between items triggers error (depends on items)
        ?_assertEqual(
            {error, missing_comma_in_flow_mapping},
            nyaml:decode(<<"{a: 1 b: 2}">>)
        )
    ].

%% ============================================================
%% Verbatim Tag Edge Cases Tests
%% ============================================================

nyaml_verbatim_tag_edge_test_() ->
    [
        %% Verbatim tag at document level
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml:decode(<<"!<tag:yaml.org,2002:str> value">>)
        ),
        %% Verbatim tag in block value
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"key: !<tag:example.com:type> value">>)
        )
    ].

%% ============================================================
%% Parse Document Value Anchor Edge Cases
%% ============================================================

nyaml_doc_value_anchor_test_() ->
    [
        %% Anchor in mapping key context
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"&a key: value">>)
        ),
        %% Anchor referring to later-defined value
        ?_assertEqual(
            {ok, #{<<"x">> => 1, <<"y">> => 1}},
            nyaml:decode(<<"x: &a 1\ny: *a">>)
        )
    ].

%% ============================================================
%% Directive After Document End Tests
%% ============================================================

nyaml_directive_after_doc_end_test_() ->
    [
        %% YAML directive after document end
        ?_assertEqual(
            {ok, <<"first">>},
            nyaml:decode(<<"first\n...\n%YAML 1.2\n---\nsecond">>)
        ),
        %% TAG directive after document end
        ?_assertEqual(
            {ok, <<"first">>},
            nyaml:decode(<<"first\n...\n%TAG !! tag:yaml.org,2002:\n---\nsecond">>)
        )
    ].

%% ============================================================
%% Skip Same Line Whitespace Tests
%% ============================================================

nyaml_same_line_whitespace_test_() ->
    [
        %% Anchor with spaces before value
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"key: &a   value">>)
        ),
        %% Anchor with tabs before value
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"key: &a\tvalue">>)
        )
    ].

%% ============================================================
%% Block Global Tag Empty Value Tests
%% ============================================================

nyaml_block_global_tag_empty_test_() ->
    [
        %% Global tag with newline before content
        ?_assertEqual(
            {ok, #{<<"key">> => 42}},
            nyaml:decode(<<"key: !!int\n  42">>)
        ),
        %% Global tag as value is parsed as scalar
        ?_assertEqual(
            {ok, #{<<"key">> => <<"42: value">>}},
            nyaml:decode(<<"key:\n  !!int 42: value">>)
        )
    ].

%% ============================================================
%% Collect Explicit Key Lines Edge Cases
%% ============================================================

nyaml_collect_explicit_key_test_() ->
    [
        %% Explicit key with continuation on same indent (becomes next key)
        ?_assertEqual(
            {ok, #{<<"key1">> => null, <<"key2">> => <<"value">>}},
            nyaml:decode(<<"? key1\n? key2\n: value">>)
        ),
        %% Explicit key with less indent ends collection
        ?_assertEqual(
            {ok, #{<<"key">> => null}},
            nyaml:decode(<<"  ? key\n">>)
        )
    ].

%% ============================================================
%% Flow Explicit Key Edge Cases
%% ============================================================

nyaml_flow_explicit_key_edge_test_() ->
    [
        %% Explicit key with colon at end
        ?_assertEqual(
            {ok, #{<<"key">> => null}},
            nyaml:decode(<<"{? key:}">>)
        ),
        %% Question mark without space is treated as key character
        ?_assertEqual(
            {ok, #{<<"?">> => <<"value">>}},
            nyaml:decode(<<"{?: value}">>)
        )
    ].

%% ============================================================
%% Quoted String in Flow Key Position
%% ============================================================

nyaml_flow_quoted_key_test_() ->
    [
        %% Double quoted key in flow mapping
        ?_assertEqual(
            {ok, #{<<"key: colon">> => <<"value">>}},
            nyaml:decode(<<"{\"key: colon\": value}">>)
        ),
        %% Single quoted key in flow mapping
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"{'key': value}">>)
        ),
        %% Quoted key in flow sequence mapping
        ?_assertEqual(
            {ok, [#{<<"key">> => <<"value">>}]},
            nyaml:decode(<<"[\"key\": value]">>)
        )
    ].

%% ============================================================
%% Block Alias as Value with Colon Tests
%% ============================================================

nyaml_block_alias_colon_test_() ->
    [
        %% Alias that appears to be key (triggers block mapping parse)
        ?_assertEqual(
            {ok, #{<<"a">> => #{<<"x">> => <<"value">>}, <<"b">> => #{<<"x">> => <<"value">>}}},
            nyaml:decode(<<"a: &ref\n  x: value\nb: *ref">>)
        )
    ].

%% ============================================================
%% Has More Content Edge Cases
%% ============================================================

nyaml_has_more_content_test_() ->
    [
        %% Empty lines before content
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"key:\n\n\n  value">>)
        ),
        %% Comment-only lines before content
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"key:\n  # comment\n  value">>)
        )
    ].

%% ============================================================
%% Flow Anchor in Value Position Tests
%% ============================================================

nyaml_flow_anchor_value_test_() ->
    [
        %% Anchor in flow mapping value
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>, <<"ref">> => <<"value">>}},
            nyaml:decode(<<"{key: &a value, ref: *a}">>)
        ),
        %% Anchor in nested flow
        ?_assertEqual(
            {ok, #{<<"outer">> => #{<<"inner">> => <<"val">>, <<"ref">> => <<"val">>}}},
            nyaml:decode(<<"{outer: {inner: &a val, ref: *a}}">>)
        )
    ].

%% ============================================================
%% Tag at Document Level with Newline
%% ============================================================

nyaml_tag_doc_level_newline_test_() ->
    [
        %% Tag with newline before content
        ?_assertEqual(
            {ok, 42},
            nyaml:decode(<<"!!int\n42">>)
        ),
        %% Tag with content on same line but mapping indicator after
        ?_assertEqual(
            {ok, #{42 => <<"value">>}},
            nyaml:decode(<<"!!int 42: value">>)
        )
    ].

%% ============================================================
%% Block Scalar Indicator in Explicit Key
%% ============================================================

nyaml_explicit_key_indicator_test_() ->
    [
        %% Explicit key followed by question at same indent
        ?_assertEqual(
            {ok, #{<<"key1">> => null, <<"key2">> => <<"value">>}},
            nyaml:decode(<<"? key1\n? key2\n: value">>)
        )
    ].

%% ============================================================
%% Parse Entry Value with Block Indicator
%% ============================================================

nyaml_entry_value_block_indicator_test_() ->
    [
        %% Mapping value is sequence
        ?_assertEqual(
            {ok, #{<<"key">> => [1, 2]}},
            nyaml:decode(<<"key:\n- 1\n- 2">>)
        ),
        %% Mapping value is nested mapping
        ?_assertEqual(
            {ok, #{<<"key">> => #{<<"nested">> => <<"value">>}}},
            nyaml:decode(<<"key:\n  nested: value">>)
        )
    ].

%% ============================================================
%% Find Key Value Separator Additional Edge Cases
%% ============================================================

nyaml_key_value_separator_additional_test_() ->
    [
        %% Key with colon at end of line
        ?_assertEqual(
            {ok, #{<<"key">> => null}},
            nyaml:decode(<<"key:">>)
        ),
        %% Key with colon and space at end
        ?_assertEqual(
            {ok, #{<<"key">> => null}},
            nyaml:decode(<<"key: ">>)
        ),
        %% Key with flow collection containing colon
        ?_assertEqual(
            {ok, #{[<<"a:b">>] => <<"value">>}},
            nyaml:decode(<<"[a:b]: value">>)
        )
    ].

%% ============================================================
%% Skip Quoted for Flow Check Tests
%% ============================================================

nyaml_skip_quoted_flow_test_() ->
    [
        %% Double quoted string with colon inside
        ?_assertEqual(
            {ok, #{<<"key:value">> => <<"x">>}},
            nyaml:decode(<<"\"key:value\": x">>)
        ),
        %% Single quoted string with colon inside
        ?_assertEqual(
            {ok, #{<<"key:value">> => <<"x">>}},
            nyaml:decode(<<"'key:value': x">>)
        )
    ].

%% ============================================================
%% Has Mapping Indicator After Anchor Tests
%% ============================================================

nyaml_mapping_indicator_after_anchor_test_() ->
    [
        %% Anchor followed by mapping indicator
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"&anchor key: value">>)
        ),
        %% Anchor followed by question mark
        ?_assertEqual(
            {ok, #{<<"key">> => null}},
            nyaml:decode(<<"&anchor ? key">>)
        )
    ].

%% ============================================================
%% Two Anchors on Same Node Error Tests
%% ============================================================

nyaml_two_anchors_error_test_() ->
    [
        %% Two anchors on same node in entry value
        ?_assertEqual(
            {error, two_anchors_on_same_node},
            nyaml:decode(<<"key: &a\n  &b value">>)
        ),
        %% Two anchors on consecutive lines in value position
        ?_assertEqual(
            {error, two_anchors_on_same_node},
            nyaml:decode(<<"key: &first\n  &second 42">>)
        )
    ].

%% ============================================================
%% Invalid Indentation Error Tests
%% ============================================================

nyaml_invalid_indentation_error_test_() ->
    [
        %% Mapping entry with wrong indentation in nested context
        ?_assertEqual(
            {error, {invalid_indentation, 6, expected, 4}},
            nyaml:decode(<<"outer:\n  inner:\n    deep: 1\n      wrong: 2">>)
        )
    ].

%% ============================================================
%% Ambiguous Mapping in Value Error Tests
%% ============================================================

nyaml_ambiguous_mapping_value_test_() ->
    [
        %% Plain scalar that looks like mapping indicator
        ?_assertEqual(
            {error, {ambiguous_mapping_in_value, <<"nested: value">>}},
            nyaml:decode(<<"key: nested: value">>)
        ),
        %% Colon-space in value triggers ambiguity
        ?_assertEqual(
            {error, {ambiguous_mapping_in_value, <<"a: b">>}},
            nyaml:decode(<<"outer: a: b">>)
        )
    ].

%% ============================================================
%% Invalid Alias Key Error Tests
%% ============================================================

nyaml_invalid_alias_key_test_() ->
    [
        %% Alias lookup fails first (undefined alias)
        ?_assertEqual(
            {error, {undefined_alias, <<"ref">>}},
            nyaml:decode(<<"*ref extra: value">>)
        )
    ].

%% ============================================================
%% Invalid Mapping Entry Error Tests
%% ============================================================

nyaml_invalid_mapping_entry_test_() ->
    [
        %% Line without key-value separator in mapping
        ?_assertEqual(
            {error, {invalid_mapping_entry, <<"no_colon_here">>}},
            nyaml:decode(<<"key: value\nno_colon_here">>)
        )
    ].

%% ============================================================
%% Duplicate YAML Directive Error Tests
%% ============================================================

nyaml_duplicate_yaml_directive_test_() ->
    [
        %% Two YAML directives
        ?_assertEqual(
            {error, duplicate_yaml_directive},
            nyaml:decode(<<"%YAML 1.2\n%YAML 1.1\n---\nvalue">>)
        )
    ].

%% ============================================================
%% Directive Without Document Error Tests
%% ============================================================

nyaml_directive_without_document_test_() ->
    [
        %% YAML directive without document start marker
        ?_assertEqual(
            {error, directive_without_document},
            nyaml:decode(<<"%YAML 1.2\nvalue">>)
        ),
        %% YAML directive followed by document end
        ?_assertEqual(
            {error, directive_without_document},
            nyaml:decode(<<"%YAML 1.2\n...">>)
        ),
        %% YAML directive with nothing after
        ?_assertEqual(
            {error, directive_without_document},
            nyaml:decode(<<"%YAML 1.2">>)
        )
    ].

%% ============================================================
%% Invalid YAML Directive Format Tests
%% ============================================================

nyaml_invalid_yaml_directive_test_() ->
    [
        %% Missing/invalid version number
        ?_assertEqual(
            {error, invalid_yaml_directive},
            nyaml:decode(<<"%YAML \n---\nvalue">>)
        ),
        %% Invalid version format
        ?_assertEqual(
            {error, invalid_yaml_directive},
            nyaml:decode(<<"%YAML abc\n---\nvalue">>)
        )
    ].

%% ============================================================
%% Unterminated Verbatim Tag Error Tests
%% ============================================================

nyaml_unterminated_verbatim_tag_test_() ->
    [
        %% Verbatim tag without closing >
        ?_assertEqual(
            {error, unterminated_verbatim_tag},
            nyaml:decode(<<"!<tag:yaml.org,2002:str value">>)
        )
    ].

%% ============================================================
%% Flow Sequence Error Tests
%% ============================================================

nyaml_flow_sequence_errors_test_() ->
    [
        %% Unterminated sequence
        ?_assertEqual(
            {error, unterminated_sequence},
            nyaml:decode(<<"[1, 2, 3">>)
        ),
        %% Consecutive commas
        ?_assertEqual(
            {error, consecutive_commas_in_sequence},
            nyaml:decode(<<"[1,, 2]">>)
        ),
        %% Leading comma in sequence
        ?_assertEqual(
            {error, invalid_leading_comma_in_sequence},
            nyaml:decode(<<"[, 1]">>)
        ),
        %% Empty sequence with comma
        ?_assertEqual(
            {error, empty_sequence_with_comma},
            nyaml:decode(<<"[,]">>)
        ),
        %% Bare dash in flow sequence
        ?_assertEqual(
            {error, bare_dash_in_flow_sequence},
            nyaml:decode(<<"[- item]">>)
        ),
        %% Dash followed by bracket
        ?_assertEqual(
            {error, bare_dash_in_flow_sequence},
            nyaml:decode(<<"[-]">>)
        )
    ].

%% ============================================================
%% Flow Mapping Error Tests
%% ============================================================

nyaml_flow_mapping_errors_test_() ->
    [
        %% Unterminated mapping
        ?_assertEqual(
            {error, unterminated_mapping},
            nyaml:decode(<<"{key: value">>)
        ),
        %% Trailing content after flow mapping
        ?_assertEqual(
            {error, {trailing_content_after_document, <<")">>}},
            nyaml:decode(<<"{key})">>)
        )
    ].

%% ============================================================
%% Implicit Key Spans Lines Error Tests
%% ============================================================

nyaml_implicit_key_spans_lines_test_() ->
    [
        {"Flow Mappings, 4MUZ/02, the colon opens the line after the key",
            ?_assertEqual(
                {ok, #{<<"foo">> => <<"bar">>}},
                nyaml:decode(<<"{foo\n: bar}\n">>)
            )},
        {"Flow Mappings, VJP3/01, the key, the colon, and the value on three lines",
            ?_assertEqual(
                {ok, #{<<"k">> => #{<<"k">> => <<"v">>}}},
                nyaml:decode(<<"k: {\n k\n :\n v\n }\n">>)
            )},
        {"Flow Mappings, the value opens the line after the colon",
            ?_assertEqual(
                {ok, #{<<"foo">> => <<"bar">>}},
                nyaml:decode(<<"{foo:\n bar}\n">>)
            )},
        {"Flow Mappings, the comma opens the line after the value",
            ?_assertEqual(
                {ok, #{<<"a">> => 1, <<"b">> => 2}},
                nyaml:decode(<<"{a: 1\n, b: 2}\n">>)
            )},
        {"Flow Mappings, one entry on one line is unchanged",
            ?_assertEqual(
                {ok, #{<<"foo">> => <<"bar">>}},
                nyaml:decode(<<"{foo: bar}">>)
            )},
        {"Flow Mappings, NJ66, a plain key of a flow mapping entry spans lines",
            ?_assertEqual(
                {ok, [#{<<"single line">> => <<"value">>}, #{<<"multi line">> => <<"value">>}]},
                nyaml:decode(<<"---\n- { single line: value}\n- { multi\n  line: value}\n">>)
            )},
        {"Flow Mappings, UT92, a plain key folds across the break before the colon",
            ?_assertEqual(
                {ok, #{<<"matches %">> => 20}},
                nyaml:decode(<<"---\n{ matches\n% : 20 }\n">>)
            )},
        {"Flow Mappings, an implicit key of a single pair spans lines",
            ?_assertEqual(
                {error, implicit_key_spans_lines},
                nyaml:decode(<<"[ foo\n bar: invalid ]">>)
            )},
        {"Flow Mappings, the colon of a single pair opens the next line",
            ?_assertEqual(
                {error, implicit_key_spans_lines},
                nyaml:decode(<<"[key\n: value]">>)
            )},
        {"Flow Mappings, a plain scalar of a flow sequence spans lines",
            ?_assertEqual(
                {ok, [<<"foo bar">>]},
                nyaml:decode(<<"[ foo\n bar ]">>)
            )}
    ].

%% ============================================================
%% Undefined Alias Error Tests
%% ============================================================

nyaml_undefined_alias_error_test_() ->
    [
        %% Reference to undefined anchor
        ?_assertEqual(
            {error, {undefined_alias, <<"missing">>}},
            nyaml:decode(<<"*missing">>)
        ),
        %% Undefined alias in value position
        ?_assertEqual(
            {error, {undefined_alias, <<"notdefined">>}},
            nyaml:decode(<<"key: *notdefined">>)
        )
    ].

%% ============================================================
%% Plain Scalar with Indicators Error Tests
%% ============================================================

nyaml_plain_scalar_indicator_error_test_() ->
    [
        %% Sequence indicator in plain scalar continuation
        ?_assertEqual(
            {error, {sequence_indicator_in_plain_scalar, <<"  - item">>}},
            nyaml:decode(<<"value\n  - item">>)
        ),
        %% Mapping indicator in plain scalar continuation
        ?_assertEqual(
            {error, {mapping_indicator_in_plain_scalar, <<"  key: value">>}},
            nyaml:decode(<<"scalar\n  key: value">>)
        )
    ].

%% ============================================================
%% Content After Comment Error Tests
%% ============================================================

nyaml_content_after_comment_error_test_() ->
    [
        %% Plain scalar with comment and then continuation
        ?_assertEqual(
            {error, content_after_comment},
            nyaml:decode(<<"value # comment\ncontinuation">>)
        )
    ].

%% ============================================================
%% Tab in Indentation Error Tests
%% ============================================================

nyaml_tab_in_indentation_error_test_() ->
    [
        %% Tab at beginning of indented line (block context)
        ?_assertEqual(
            {error, tab_in_indentation},
            nyaml:decode(<<"outer:\n  inner:\n\tdeep: value">>)
        )
    ].

%% ============================================================
%% Invalid Tag Name Error Tests
%% ============================================================

nyaml_invalid_tag_name_error_test_() ->
    [
        %% Empty global tag name
        ?_assertEqual(
            {error, {invalid_tag_name, <<" value">>}},
            nyaml:decode(<<"!! value">>)
        ),
        %% Invalid characters in tag name
        ?_assertEqual(
            {error, {invalid_tag_name, <<":invalid value">>}},
            nyaml:decode(<<"!!:invalid value">>)
        )
    ].

%% ============================================================
%% Invalid Anchor Name Error Tests
%% ============================================================

nyaml_invalid_anchor_name_error_test_() ->
    [
        %% Empty anchor name
        ?_assertEqual(
            {error, {invalid_anchor_name, <<" value">>}},
            nyaml:decode(<<"& value">>)
        ),
        %% Anchor name starts with invalid character
        ?_assertEqual(
            {error, {invalid_anchor_name, <<", value">>}},
            nyaml:decode(<<"&, value">>)
        )
    ].

%% ============================================================
%% Anchor Followed by Alias Error Tests
%% ============================================================

nyaml_anchor_followed_by_alias_error_test_() ->
    [
        %% Anchor immediately followed by alias
        ?_assertEqual(
            {error, anchor_followed_by_alias},
            nyaml:decode(<<"key: &a *ref">>)
        ),
        %% Anchor with alias (undefined alias triggers first)
        ?_assertEqual(
            {error, {undefined_alias, <<"alias">>}},
            nyaml:decode(<<"&anchor *alias">>)
        )
    ].

%% ============================================================
%% Unexpected Closing Delimiters Tests
%% ============================================================

nyaml_unexpected_closing_test_() ->
    [
        %% Indicator Characters: ']' is c-sequence-end, and Plain Style excludes
        %% every indicator from ns-plain-first, so no document begins with it
        ?_assertEqual(
            {error, {unexpected_content, <<"]">>}},
            nyaml:decode(<<"]">>)
        ),
        %% Indicator Characters: '}' is c-mapping-end, refused the same way
        ?_assertEqual(
            {error, {unexpected_content, <<"}">>}},
            nyaml:decode(<<"}">>)
        ),
        %% Plain Style: an indicator is only excluded in first position
        ?_assertEqual(
            {ok, <<"a]">>},
            nyaml:decode(<<"a]">>)
        )
    ].

%% ============================================================
%% Invalid Alias Syntax Error Tests
%% ============================================================

nyaml_invalid_alias_syntax_error_test_() ->
    [
        %% Alias with trailing content in sequence item
        ?_assertEqual(
            {error, {invalid_alias_syntax, <<"*ref extra">>}},
            nyaml:decode(<<"- *ref extra">>)
        )
    ].

%% ============================================================
%% Not a Sequence/Mapping Error Tests
%% ============================================================

nyaml_not_collection_error_test_() ->
    [
        %% Calling sequence parse on non-sequence
        ?_assertEqual(
            {error, not_a_sequence},
            nyaml_flow:parse_sequence(<<"{key: value}">>, nyaml_parser:new_ctx())
        ),
        %% Calling mapping parse on non-mapping
        ?_assertEqual(
            {error, not_a_mapping},
            nyaml_flow:parse_mapping(<<"[1, 2, 3]">>, nyaml_parser:new_ctx())
        )
    ].

%% ============================================================
%% Flow Plain Scalar with Colon Tests
%% ============================================================

nyaml_flow_plain_scalar_colon_test_() ->
    [
        %% Colon without space in flow value
        ?_assertEqual(
            {ok, [<<"http://example.com">>]},
            nyaml:decode(<<"[http://example.com]">>)
        ),
        %% Multiple colons without space
        ?_assertEqual(
            {ok, [<<"a:b:c">>]},
            nyaml:decode(<<"[a:b:c]">>)
        )
    ].

%% ============================================================
%% Explicit Key Edge Cases Tests
%% ============================================================

nyaml_explicit_key_edge_cases_test_() ->
    [
        %% Explicit key with sequence as key
        ?_assertEqual(
            {ok, #{[1, 2] => <<"value">>}},
            nyaml:decode(<<"?\n  - 1\n  - 2\n: value">>)
        ),
        %% Explicit key with mapping as key
        ?_assertEqual(
            {ok, #{#{<<"a">> => 1} => <<"value">>}},
            nyaml:decode(<<"?\n  a: 1\n: value">>)
        )
    ].

%% ============================================================
%% Block Scalar in Sequence Item Tests
%% ============================================================

nyaml_block_scalar_sequence_item_test_() ->
    [
        %% Literal block scalar as sequence item
        ?_assertEqual(
            {ok, [<<"line1\nline2\n">>]},
            nyaml:decode(<<"- |\n  line1\n  line2">>)
        ),
        %% Folded block scalar as sequence item
        ?_assertEqual(
            {ok, [<<"line1 line2\n">>]},
            nyaml:decode(<<"- >\n  line1\n  line2">>)
        )
    ].

%% ============================================================
%% Nested Sequence in Mapping Value Tests
%% ============================================================

nyaml_nested_sequence_mapping_test_() ->
    [
        %% Sequence immediately after colon on same line
        ?_assertEqual(
            {ok, #{<<"key">> => [1, 2]}},
            nyaml:decode(<<"key: [1, 2]">>)
        ),
        %% Nested sequence with inline continuation
        ?_assertEqual(
            {ok, #{<<"outer">> => #{<<"inner">> => [1, 2, 3]}}},
            nyaml:decode(<<"outer:\n  inner: [1, 2, 3]">>)
        )
    ].

%% ============================================================
%% Anchor with Block Value Additional Tests
%% ============================================================

nyaml_anchor_block_value_additional_test_() ->
    [
        %% Anchor with block sequence value
        ?_assertEqual(
            {ok, #{<<"key">> => [1, 2], <<"ref">> => [1, 2]}},
            nyaml:decode(<<"key: &a\n  - 1\n  - 2\nref: *a">>)
        ),
        %% Anchor with block mapping value
        ?_assertEqual(
            {ok, #{<<"key">> => #{<<"nested">> => 1}, <<"ref">> => #{<<"nested">> => 1}}},
            nyaml:decode(<<"key: &a\n  nested: 1\nref: *a">>)
        )
    ].

%% ============================================================
%% Global Tag with Block Value Additional Tests
%% ============================================================

nyaml_global_tag_block_value_additional_test_() ->
    [
        %% Global tag with sequence value on next line
        ?_assertEqual(
            {ok, #{<<"key">> => [1, 2]}},
            nyaml:decode(<<"key: !!seq\n  - 1\n  - 2">>)
        ),
        %% Global tag with mapping value on next line
        ?_assertEqual(
            {ok, #{<<"key">> => #{<<"nested">> => 1}}},
            nyaml:decode(<<"key: !!map\n  nested: 1">>)
        )
    ].

%% ============================================================
%% Flow Collection as Value with Newlines Tests
%% ============================================================

nyaml_flow_collection_newlines_test_() ->
    [
        %% Flow sequence with newlines before close
        ?_assertEqual(
            {ok, [1, 2, 3]},
            nyaml:decode(<<"[\n1,\n2,\n3\n]">>)
        ),
        %% Flow mapping with newlines
        ?_assertEqual(
            {ok, #{<<"a">> => 1, <<"b">> => 2}},
            nyaml:decode(<<"{\na: 1,\nb: 2\n}">>)
        )
    ].

%% ============================================================
%% Plain Scalar Continuation with Empty Lines Tests
%% ============================================================

nyaml_plain_scalar_empty_lines_test_() ->
    [
        %% Empty line in plain scalar continuation
        ?_assertEqual(
            {ok, <<"line1\nline2">>},
            nyaml:decode(<<"line1\n\nline2">>)
        ),
        %% Multiple empty lines collapse
        ?_assertEqual(
            {ok, <<"line1\n\nline3">>},
            nyaml:decode(<<"line1\n\n\nline3">>)
        )
    ].

%% ============================================================
%% Quoted String with Escapes in Flow Tests
%% ============================================================

nyaml_quoted_escape_flow_test_() ->
    [
        %% Double quoted with escape in flow
        ?_assertEqual(
            {ok, [<<"hello\nworld">>]},
            nyaml:decode(<<"[\"hello\\nworld\"]">>)
        ),
        %% Single quoted with escaped quote
        ?_assertEqual(
            {ok, [<<"it''s">>]},
            nyaml:decode(<<"['it''''s']">>)
        )
    ].

%% ============================================================
%% Tag Directive Additional Tests
%% ============================================================

nyaml_tag_directive_additional_test_() ->
    [
        %% Tag handle declared by %TAG resolves in the following document
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml:decode(<<"%TAG !e! tag:example.com,2000:\n---\n!e!type value">>)
        ),
        %% Multiple tag directives (tag handles not preserved across doc)
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml:decode(<<"%TAG !a! tag:a.com:\n%TAG !b! tag:b.com:\n---\nvalue">>)
        )
    ].

%% ============================================================
%% Invalid Plain Scalar Start Tests
%% ============================================================

nyaml_invalid_plain_scalar_start_test_() ->
    [
        %% Comma at start of block value (after parsing)
        ?_assertEqual(
            {ok, #{<<"key">> => <<",">>}},
            nyaml:decode(<<"key: \",\"">>)
        ),
        %% Bracket at start
        ?_assertEqual(
            {ok, [1, 2]},
            nyaml:decode(<<"[1, 2]">>)
        )
    ].

%% ============================================================
%% Multiline Plain Scalar Detection Tests
%% ============================================================

nyaml_multiline_plain_detection_test_() ->
    [
        %% Continuation line with same indent
        ?_assertEqual(
            {ok, <<"first second">>},
            nyaml:decode(<<"first\nsecond">>)
        ),
        %% Mapping indicator stops scalar continuation
        ?_assertEqual(
            {error, {trailing_content_after_document, <<"second:">>}},
            nyaml:decode(<<"first\nsecond:">>)
        )
    ].

%% ============================================================
%% Inline Sequence Continuation Tests
%% ============================================================

nyaml_inline_sequence_continuation_test_() ->
    [
        %% Multiple sequence items at same indent
        ?_assertEqual(
            {ok, [1, 2, 3]},
            nyaml:decode(<<"- 1\n- 2\n- 3">>)
        ),
        %% Sequence stops at different indent
        ?_assertEqual(
            {ok, #{<<"list">> => [1, 2], <<"key">> => <<"value">>}},
            nyaml:decode(<<"list:\n  - 1\n  - 2\nkey: value">>)
        )
    ].

%% ============================================================
%% Parse Item Value Edge Cases Tests
%% ============================================================

nyaml_parse_item_value_test_() ->
    [
        %% Sequence item with anchor and value
        ?_assertEqual(
            {ok, #{<<"items">> => [<<"value">>], <<"ref">> => <<"value">>}},
            nyaml:decode(<<"items:\n  - &a value\nref: *a">>)
        ),
        %% Sequence item with tag
        ?_assertEqual(
            {ok, [42]},
            nyaml:decode(<<"- !!int 42">>)
        ),
        %% Sequence item with ! non-specific tag
        ?_assertEqual(
            {ok, [<<"42">>]},
            nyaml:decode(<<"- ! 42">>)
        )
    ].

%% ============================================================
%% Collect Scalar Lines Edge Cases Additional Tests
%% ============================================================

nyaml_collect_scalar_lines_additional_test_() ->
    [
        %% Scalar stops at block indicator
        ?_assertEqual(
            {ok, #{<<"key">> => [<<"item">>]}},
            nyaml:decode(<<"key:\n- item">>)
        ),
        %% Scalar stops at mapping indicator
        ?_assertEqual(
            {ok, #{<<"outer">> => #{<<"inner">> => <<"val">>}}},
            nyaml:decode(<<"outer:\n  inner: val">>)
        )
    ].

%% ============================================================
%% Skip Whitespace and Comments Tests
%% ============================================================

nyaml_skip_whitespace_comments_test_() ->
    [
        %% Multiple whitespace types
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml:decode(<<"   \t  value">>)
        ),
        %% Comment line between content
        ?_assertEqual(
            {ok, #{<<"a">> => 1, <<"b">> => 2}},
            nyaml:decode(<<"a: 1\n# middle comment\nb: 2">>)
        )
    ].

%% ============================================================
%% Parse Key with Anchor Tests
%% ============================================================

nyaml_parse_key_anchor_test_() ->
    [
        %% Anchored key
        ?_assertEqual(
            {ok, #{<<"mykey">> => <<"value">>}},
            nyaml:decode(<<"&keyanchor mykey: value">>)
        ),
        %% Anchored key with tagged value
        ?_assertEqual(
            {ok, #{<<"key">> => 42}},
            nyaml:decode(<<"&k key: !!int 42">>)
        )
    ].

%% ============================================================
%% Flow Spans Lines Detection Tests
%% ============================================================

nyaml_flow_spans_lines_test_() ->
    [
        %% Flow sequence definitely spans
        ?_assertEqual(
            {ok, #{<<"key">> => [1, 2, 3]}},
            nyaml:decode(<<"key: [\n  1,\n  2,\n  3\n]">>)
        ),
        %% Flow mapping spans lines
        ?_assertEqual(
            {ok, #{<<"key">> => #{<<"a">> => 1}}},
            nyaml:decode(<<"key: {\n  a: 1\n}">>)
        )
    ].

%% ============================================================
%% Verbatim Tag in Block Value Tests
%% ============================================================

nyaml_verbatim_tag_block_value_test_() ->
    [
        %% Verbatim tag in entry value
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"key: !<tag:yaml.org,2002:str> value">>)
        ),
        %% Verbatim tag in sequence item
        ?_assertEqual(
            {ok, [<<"value">>]},
            nyaml:decode(<<"- !<tag:yaml.org,2002:str> value">>)
        )
    ].

%% ============================================================
%% Find Explicit Value Edge Cases Tests
%% ============================================================

nyaml_find_explicit_value_test_() ->
    [
        %% Explicit key with value at same indent
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"? key\n: value">>)
        ),
        %% Explicit key with null value (no colon found)
        ?_assertEqual(
            {ok, #{<<"key1">> => null, <<"key2">> => <<"val">>}},
            nyaml:decode(<<"? key1\n? key2\n: val">>)
        )
    ].

%% ============================================================
%% Split Inline Explicit Key Value Tests
%% ============================================================

nyaml_split_inline_explicit_key_test_() ->
    [
        %% Explicit key with colon becomes key with colon
        ?_assertEqual(
            {ok, #{<<"key: value">> => null}},
            nyaml:decode(<<"? key: value">>)
        )
    ].

%% ============================================================
%% Parse Flow Scalar Value Edge Cases Tests
%% ============================================================

nyaml_parse_flow_scalar_value_test_() ->
    [
        %% Scalar ending at comma
        ?_assertEqual(
            {ok, [<<"a">>, <<"b">>]},
            nyaml:decode(<<"[a, b]">>)
        ),
        %% Scalar ending at bracket
        ?_assertEqual(
            {ok, [<<"value">>]},
            nyaml:decode(<<"[value]">>)
        ),
        %% Scalar with whitespace before delimiter
        ?_assertEqual(
            {ok, [<<"value">>]},
            nyaml:decode(<<"[value   ]">>)
        )
    ].

%% ============================================================
%% Has Plain Continuation After Tests
%% ============================================================

nyaml_has_plain_continuation_test_() ->
    [
        %% No continuation after comment line
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml:decode(<<"value\n# comment">>)
        ),
        %% No continuation at end of file
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml:decode(<<"value">>)
        )
    ].

%% ============================================================
%% Resolve Key Tag Edge Cases Tests
%% ============================================================

nyaml_resolve_key_tag_test_() ->
    [
        %% Key with global tag and value
        ?_assertEqual(
            {ok, #{42 => <<"value">>}},
            nyaml:decode(<<"!!int 42: value">>)
        ),
        %% Key with anchor in explicit key
        ?_assertEqual(
            {ok, #{<<"mykey">> => <<"value">>}},
            nyaml:decode(<<"? &k mykey\n: value">>)
        ),
        %% Alias as explicit key with anchor
        ?_assertEqual(
            {ok, #{<<"keyval">> => <<"result">>}},
            nyaml:decode(<<"&k keyval: result">>)
        )
    ].

%% ============================================================
%% Parse Value Content Edge Cases Tests
%% ============================================================

nyaml_parse_value_content_test_() ->
    [
        %% Flow sequence as value with multiline
        ?_assertEqual(
            {ok, #{<<"key">> => [1, 2, 3]}},
            nyaml:decode(<<"key: [1,\n      2,\n      3]">>)
        ),
        %% Flow mapping as value with multiline
        ?_assertEqual(
            {ok, #{<<"key">> => #{<<"a">> => 1, <<"b">> => 2}}},
            nyaml:decode(<<"key: {a: 1,\n      b: 2}">>)
        ),
        %% Double quoted string as value
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value with spaces">>}},
            nyaml:decode(<<"key: \"value with spaces\"">>)
        ),
        %% Single quoted string as value
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"key: 'value'">>)
        ),
        %% Sequence indicator in value position triggers indentation error
        ?_assertEqual(
            {error, {invalid_indentation, 5, expected, 0}},
            nyaml:decode(<<"key: - 1\n     - 2">>)
        ),
        %% Block scalar as value
        ?_assertEqual(
            {ok, #{<<"key">> => <<"line1\nline2\n">>}},
            nyaml:decode(<<"key: |\n  line1\n  line2">>)
        )
    ].

%% ============================================================
%% Validate Flow Continuation Indent Tests
%% ============================================================

nyaml_flow_continuation_indent_test_() ->
    [
        %% Flow with proper continuation indent
        ?_assertEqual(
            {ok, #{<<"key">> => [1, 2, 3]}},
            nyaml:decode(<<"key: [\n  1,\n  2,\n  3\n]">>)
        ),
        %% Nested flow collections
        ?_assertEqual(
            {ok, #{<<"key">> => [[1, 2], [3, 4]]}},
            nyaml:decode(<<"key: [[1, 2],\n      [3, 4]]">>)
        ),
        %% Flow with quoted strings spanning lines
        ?_assertEqual(
            {ok, #{<<"key">> => [<<"value">>]}},
            nyaml:decode(<<"key: [\"value\"\n]">>)
        )
    ].

%% ============================================================
%% Skip Flow Collection Edge Cases Tests
%% ============================================================

nyaml_skip_flow_collection_test_() ->
    [
        %% Flow collection in mapping key
        ?_assertEqual(
            {ok, #{[1, 2] => <<"value">>}},
            nyaml:decode(<<"[1, 2]: value">>)
        ),
        %% Nested flow with quoted strings
        ?_assertEqual(
            {ok, #{#{<<"a">> => <<"b">>} => <<"value">>}},
            nyaml:decode(<<"{\"a\": \"b\"}: value">>)
        ),
        %% Flow with single quoted key
        ?_assertEqual(
            {ok, #{#{<<"key">> => <<"val">>} => <<"result">>}},
            nyaml:decode(<<"{'key': 'val'}: result">>)
        )
    ].

%% ============================================================
%% Explicit Key with Nested Structure Tests
%% ============================================================

nyaml_explicit_key_nested_test_() ->
    [
        %% Explicit key with nested sequence as key
        ?_assertEqual(
            {ok, #{[1, 2, 3] => <<"value">>}},
            nyaml:decode(<<"?\n  - 1\n  - 2\n  - 3\n: value">>)
        ),
        %% Explicit key with nested mapping as key
        ?_assertEqual(
            {ok, #{#{<<"nested">> => <<"key">>} => <<"value">>}},
            nyaml:decode(<<"?\n  nested: key\n: value">>)
        ),
        %% Multiple explicit keys
        ?_assertEqual(
            {ok, #{<<"key1">> => null, <<"key2">> => <<"val2">>}},
            nyaml:decode(<<"? key1\n? key2\n: val2">>)
        )
    ].

%% ============================================================
%% Sequence Item Edge Cases Tests
%% ============================================================

nyaml_sequence_item_edge_test_() ->
    [
        %% Bare dash item with nested content
        ?_assertEqual(
            {ok, [#{<<"nested">> => <<"value">>}]},
            nyaml:decode(<<"-\n  nested: value">>)
        ),
        %% Sequence item with flow collection
        ?_assertEqual(
            {ok, [[1, 2, 3]]},
            nyaml:decode(<<"- [1, 2, 3]">>)
        ),
        %% Sequence item with mapping
        ?_assertEqual(
            {ok, [#{<<"a">> => 1, <<"b">> => 2}]},
            nyaml:decode(<<"- {a: 1, b: 2}">>)
        ),
        %% Sequence item with tag
        ?_assertEqual(
            {ok, [42]},
            nyaml:decode(<<"- !!int 42">>)
        )
    ].

%% ============================================================
%% Invalid Sequence Item Tests
%% ============================================================

nyaml_invalid_sequence_item_test_() ->
    [
        %% Invalid item at sequence indent
        ?_assertEqual(
            {error, {invalid_sequence_item, <<"not_sequence_item">>}},
            nyaml:decode(<<"- first\nnot_sequence_item">>)
        )
    ].

%% ============================================================
%% Strip Comment Quoted Edge Cases Tests
%% ============================================================

nyaml_strip_comment_quoted_test_() ->
    [
        %% Comment after quoted string
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"key: \"value\" # comment">>)
        ),
        %% Comment after single quoted string
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"key: 'value' # comment">>)
        ),
        %% Hash inside double quoted not a comment
        ?_assertEqual(
            {ok, #{<<"key">> => <<"val#ue">>}},
            nyaml:decode(<<"key: \"val#ue\"">>)
        ),
        %% Hash inside single quoted not a comment
        ?_assertEqual(
            {ok, #{<<"key">> => <<"val#ue">>}},
            nyaml:decode(<<"key: 'val#ue'">>)
        )
    ].

%% ============================================================
%% Peek Next Content Indent Tests
%% ============================================================

nyaml_peek_next_content_test_() ->
    [
        %% Content continues at proper indent
        ?_assertEqual(
            {ok, #{<<"key">> => <<"line1 line2">>}},
            nyaml:decode(<<"key:\n  line1\n  line2">>)
        ),
        %% Empty lines between content
        ?_assertEqual(
            {ok, #{<<"key">> => <<"line1\nline3">>}},
            nyaml:decode(<<"key:\n  line1\n\n  line3">>)
        )
    ].

%% ============================================================
%% Split Inline Explicit Key Value Tests
%% ============================================================

nyaml_split_inline_explicit_test_() ->
    [
        %% Inline explicit key with value
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"? key : value">>)
        ),
        %% Inline explicit key with tab before colon
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"? key\t: value">>)
        )
    ].

%% ============================================================
%% Starts With Scalar Anchor Tests
%% ============================================================

nyaml_starts_with_scalar_anchor_test_() ->
    [
        %% Anchor on next line in value position
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>, <<"ref">> => <<"value">>}},
            nyaml:decode(<<"key:\n  &a value\nref: *a">>)
        )
    ].

%% ============================================================
%% Skip Verbatim Tag Tests
%% ============================================================

nyaml_skip_verbatim_tag_test_() ->
    [
        %% Verbatim tag at value position
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"key: !<tag:yaml.org,2002:str> value">>)
        ),
        %% Verbatim tag in entry
        ?_assertEqual(
            {ok, [<<"value">>]},
            nyaml:decode(<<"- !<customtag> value">>)
        )
    ].

%% ============================================================
%% Flow Quoted Key Position Tests
%% ============================================================

nyaml_flow_quoted_key_position_test_() ->
    [
        %% Quoted key followed by colon
        ?_assertEqual(
            {ok, #{<<"key with spaces">> => <<"value">>}},
            nyaml:decode(<<"\"key with spaces\": value">>)
        ),
        %% Single quoted key at document level
        ?_assertEqual(
            {ok, #{<<"key:colon">> => <<"value">>}},
            nyaml:decode(<<"'key:colon': value">>)
        )
    ].

%% ============================================================
%% Parse Flow Key Edge Cases Tests
%% ============================================================

nyaml_parse_flow_key_edge_test_() ->
    [
        %% Flow sequence as key in flow mapping
        ?_assertEqual(
            {ok, #{[1] => <<"value">>}},
            nyaml:decode(<<"{[1]: value}">>)
        ),
        %% Flow mapping as key in flow mapping
        ?_assertEqual(
            {ok, #{#{<<"a">> => 1} => <<"value">>}},
            nyaml:decode(<<"{  {a: 1}: value}">>)
        ),
        %% Explicit key in flow
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"{? key: value}">>)
        )
    ].

%% ============================================================
%% Anchor Value Position Tests
%% ============================================================

nyaml_anchor_value_position_test_() ->
    [
        %% Anchor with inline value
        ?_assertEqual(
            {ok, #{<<"key">> => <<"inline">>}},
            nyaml:decode(<<"key: &a inline">>)
        ),
        %% Anchor with newline before value
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"key: &a\n  value">>)
        ),
        %% Anchor with comment before newline
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"key: &a # comment\n  value">>)
        )
    ].

%% ============================================================
%% Find Comment Start Tests
%% ============================================================

nyaml_find_comment_start_test_() ->
    [
        %% Comment after plain scalar
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"key: value # comment">>)
        ),
        %% No comment (hash without space)
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value#tag">>}},
            nyaml:decode(<<"key: value#tag">>)
        ),
        %% Comment at start of line
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml:decode(<<"# line comment\nvalue">>)
        )
    ].

%% ============================================================
%% Has Colon Followed By Whitespace Tests
%% ============================================================

nyaml_colon_whitespace_test_() ->
    [
        %% Colon followed by space
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"key: value">>)
        ),
        %% Colon followed by tab
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"key:\tvalue">>)
        ),
        %% Colon at end of line
        ?_assertEqual(
            {ok, #{<<"key">> => null}},
            nyaml:decode(<<"key:">>)
        ),
        %% Colon followed by newline
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"key:\n  value">>)
        )
    ].

%% ============================================================
%% Normalize Spaces Tests
%% ============================================================

nyaml_normalize_spaces_test_() ->
    [
        %% Multiple spaces preserved in plain scalars
        ?_assertEqual(
            {ok, <<"word1   word2">>},
            nyaml:decode(<<"word1   word2">>)
        ),
        %% Tabs and spaces preserved
        ?_assertEqual(
            {ok, <<"word1\t  word2">>},
            nyaml:decode(<<"word1\t  word2">>)
        )
    ].

%% ============================================================
%% Parse Entry Value With Tags Tests
%% ============================================================

nyaml_parse_entry_value_tags_test_() ->
    [
        %% Entry value with global tag
        ?_assertEqual(
            {ok, #{<<"key">> => 42}},
            nyaml:decode(<<"key: !!int 42">>)
        ),
        %% Entry value with local tag
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"key: !custom value">>)
        ),
        %% Entry value with verbatim tag
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"key: !<tag:yaml.org,2002:str> value">>)
        )
    ].

%% ============================================================
%% Parse Item Value With Tags Tests
%% ============================================================

nyaml_parse_item_value_tags_test_() ->
    [
        %% Sequence item with global tag and anchor
        ?_assertEqual(
            {ok, [42]},
            nyaml:decode(<<"- !!int &a 42">>)
        ),
        %% Sequence item with verbatim tag
        ?_assertEqual(
            {ok, [<<"value">>]},
            nyaml:decode(<<"- !<customtag> value">>)
        ),
        %% Sequence item with ! non-specific tag
        ?_assertEqual(
            {ok, [<<"42">>]},
            nyaml:decode(<<"- ! 42">>)
        ),
        %% Sequence item with local tag
        ?_assertEqual(
            {ok, [<<"value">>]},
            nyaml:decode(<<"- !mytag value">>)
        )
    ].

%% ============================================================
%% Is Plain Scalar With Mapping Indicator Tests
%% ============================================================

nyaml_plain_scalar_mapping_indicator_test_() ->
    [
        %% Plain scalar without mapping indicator (URL)
        ?_assertEqual(
            {ok, #{<<"url">> => <<"http://example.com">>}},
            nyaml:decode(<<"url: http://example.com">>)
        ),
        %% Plain scalar that looks like mapping but is URL
        ?_assertEqual(
            {ok, #{<<"site">> => <<"https://test.com/path">>}},
            nyaml:decode(<<"site: https://test.com/path">>)
        )
    ].

%% ============================================================
%% Collect Item Scalar Lines Tests
%% ============================================================

nyaml_collect_item_scalar_lines_test_() ->
    [
        %% Multiline scalar in sequence item
        ?_assertEqual(
            {ok, [<<"line1 line2">>]},
            nyaml:decode(<<"- line1\n  line2">>)
        ),
        %% Scalar with empty line becomes newline
        ?_assertEqual(
            {ok, [<<"line1\nline3">>]},
            nyaml:decode(<<"- line1\n\n  line3">>)
        )
    ].

%% ============================================================
%% Flow Mapping Entry Tests
%% ============================================================

nyaml_flow_mapping_entry_test_() ->
    [
        %% Mapping entry with anchor on key
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"{&k key: value}">>)
        ),
        %% Mapping entry with alias as key
        ?_assertEqual(
            {ok, #{<<"x">> => <<"x">>}},
            nyaml:decode(<<"{&a x: *a}">>)
        )
    ].

%% ============================================================
%% Try Parse Implicit Mapping Tests
%% ============================================================

nyaml_try_parse_implicit_mapping_test_() ->
    [
        %% Implicit mapping in flow sequence
        ?_assertEqual(
            {ok, [#{<<"key">> => <<"value">>}]},
            nyaml:decode(<<"[key: value]">>)
        ),
        %% Multiple implicit mappings in sequence
        ?_assertEqual(
            {ok, [#{<<"a">> => 1}, #{<<"b">> => 2}]},
            nyaml:decode(<<"[a: 1, b: 2]">>)
        )
    ].

%% ============================================================
%% Skip Whitespace And Comments Flow Tests
%% ============================================================

nyaml_skip_ws_comments_flow_test_() ->
    [
        %% Comment in flow sequence
        ?_assertEqual(
            {ok, [1, 2]},
            nyaml:decode(<<"[1, # comment\n2]">>)
        ),
        %% Comment in flow mapping
        ?_assertEqual(
            {ok, #{<<"a">> => 1, <<"b">> => 2}},
            nyaml:decode(<<"{a: 1, # comment\nb: 2}">>)
        )
    ].

%% ============================================================
%% Document End Marker Tests
%% ============================================================

nyaml_document_end_marker_test_() ->
    [
        %% Document end marker
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml:decode(<<"value\n...">>)
        ),
        %% Document end with whitespace after
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml:decode(<<"value\n...  ">>)
        )
    ].

%% ============================================================
%% Parse Directives Edge Cases Tests
%% ============================================================

nyaml_parse_directives_edge_test_() ->
    [
        %% Unknown directive is ignored
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml:decode(<<"%CUSTOM directive\nvalue">>)
        ),
        %% TAG directive
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml:decode(<<"%TAG ! tag:yaml.org,2002:\n---\nvalue">>)
        )
    ].

%% ============================================================
%% Inline Mapping In Sequence Tests
%% ============================================================

nyaml_inline_mapping_sequence_test_() ->
    [
        %% Inline mapping as sequence item
        ?_assertEqual(
            {ok, [#{<<"key">> => <<"value">>}]},
            nyaml:decode(<<"- key: value">>)
        ),
        %% Multiple inline mappings
        ?_assertEqual(
            {ok, [#{<<"a">> => 1}, #{<<"b">> => 2}]},
            nyaml:decode(<<"- a: 1\n- b: 2">>)
        )
    ].

%% ============================================================
%% Flow Scalar CRLF Tests
%% ============================================================

nyaml_flow_scalar_crlf_test_() ->
    [
        %% CRLF in flow scalar
        ?_assertEqual(
            {ok, [<<"a b">>]},
            nyaml:decode(<<"[a\r\nb]">>)
        )
    ].

%% ============================================================
%% Block Key With Flow Collection Tests
%% ============================================================

nyaml_block_key_flow_collection_test_() ->
    [
        %% Flow sequence as block mapping key
        ?_assertEqual(
            {ok, #{[1, 2] => <<"value">>}},
            nyaml:decode(<<"[1, 2]: value">>)
        ),
        %% Flow mapping as block mapping key
        ?_assertEqual(
            {ok, #{#{<<"a">> => 1} => <<"value">>}},
            nyaml:decode(<<"{a: 1}: value">>)
        ),
        %% Nested flow as key
        ?_assertEqual(
            {ok, #{[[1]] => <<"value">>}},
            nyaml:decode(<<"[[1]]: value">>)
        )
    ].

%% ============================================================
%% Explicit Key Value Indicator Tests
%% ============================================================

nyaml_explicit_key_value_indicator_test_() ->
    [
        %% Value indicator with space
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"? key\n: value">>)
        ),
        %% Value indicator with tab
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"? key\n:\tvalue">>)
        ),
        %% Value indicator alone
        ?_assertEqual(
            {ok, #{<<"key">> => null}},
            nyaml:decode(<<"? key\n:">>)
        )
    ].

%% ============================================================
%% Flow Implicit Key Spans Lines Error Tests
%% ============================================================

nyaml_implicit_key_spans_lines_error_test_() ->
    [
        %% Multiline key in flow context folds to single key
        ?_assertEqual(
            {ok, #{<<"key value">> => <<"x">>}},
            nyaml:decode(<<"{key\nvalue: x}">>)
        )
    ].

%% ============================================================
%% Flow Comment Error Tests
%% ============================================================

nyaml_flow_comment_error_test_() ->
    [
        %% Comment directly after bracket
        ?_assertEqual(
            {error, invalid_comment_after_bracket},
            nyaml:decode(<<"[1, 2]#comment">>)
        ),
        %% Comment directly after comma
        ?_assertEqual(
            {error, invalid_comment_after_comma},
            nyaml:decode(<<"[1,#comment]">>)
        )
    ].

%% ============================================================
%% Flow Sequence Comma Error Tests
%% ============================================================

nyaml_flow_sequence_comma_error_test_() ->
    [
        %% Empty sequence with comma
        ?_assertEqual(
            {error, empty_sequence_with_comma},
            nyaml:decode(<<"[,]">>)
        ),
        %% Leading comma in sequence
        ?_assertEqual(
            {error, invalid_leading_comma_in_sequence},
            nyaml:decode(<<"[, 1]">>)
        ),
        %% Consecutive commas
        ?_assertEqual(
            {error, consecutive_commas_in_sequence},
            nyaml:decode(<<"[1,, 2]">>)
        )
    ].

%% ============================================================
%% Anchor on Block Indicator Error Tests
%% ============================================================

nyaml_anchor_on_block_indicator_error_test_() ->
    [
        %% Anchor on dash (sequence indicator)
        ?_assertEqual(
            {error, anchor_on_block_indicator},
            nyaml:decode(<<"&anchor -">>)
        ),
        %% Anchor on colon parses as a null key mapping
        ?_assertEqual(
            {ok, #{null => null}},
            nyaml:decode(<<"&anchor :">>)
        )
    ].

%% ============================================================
%% Tag Directive Error Tests
%% ============================================================

nyaml_tag_directive_error_test_() ->
    [
        %% Invalid tag directive format - triggers invalid_tag_handle
        ?_assertEqual(
            {error, invalid_tag_handle},
            nyaml:decode(<<"%TAG invalid\n---\nvalue">>)
        ),
        %% Missing tag prefix parses with default tag handling
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml:decode(<<"%TAG !e!\n---\nvalue">>)
        ),
        %% Invalid tag handle
        ?_assertEqual(
            {error, invalid_tag_handle},
            nyaml:decode(<<"%TAG @invalid tag:example\n---\nvalue">>)
        )
    ].

%% ============================================================
%% Verbatim Tag Error Tests
%% ============================================================

nyaml_verbatim_tag_error_test_() ->
    [
        %% Unterminated verbatim tag
        ?_assertEqual(
            {error, unterminated_verbatim_tag},
            nyaml:decode(<<"!<tag value">>)
        )
    ].

%% ============================================================
%% Content After Document End Error Tests
%% ============================================================

nyaml_content_after_document_end_error_test_() ->
    [
        %% Invalid content after document end
        ?_assertEqual(
            {error, invalid_content_after_document_end},
            nyaml:decode(<<"---\nvalue\n... invalid">>)
        )
    ].

%% ============================================================
%% Block Mapping on Document Start Line Error Tests
%% ============================================================

nyaml_block_mapping_on_start_line_error_test_() ->
    [
        %% Block mapping on document start line parses as mapping
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"--- key: value">>)
        )
    ].

%% ============================================================
%% Bare Dash in Flow Sequence Tests
%% ============================================================

nyaml_bare_dash_in_flow_test_() ->
    [
        %% Bare dash followed by space
        ?_assertEqual(
            {error, bare_dash_in_flow_sequence},
            nyaml:decode(<<"[- ]">>)
        ),
        %% Bare dash followed by comma
        ?_assertEqual(
            {error, bare_dash_in_flow_sequence},
            nyaml:decode(<<"[1, - , 2]">>)
        ),
        %% Bare dash followed by bracket
        ?_assertEqual(
            {error, bare_dash_in_flow_sequence},
            nyaml:decode(<<"[-]">>)
        )
    ].

%% ============================================================
%% Missing Comma in Flow Mapping Tests
%% ============================================================

nyaml_missing_comma_in_flow_mapping_test_() ->
    [
        %% Missing comma between entries
        ?_assertEqual(
            {error, missing_comma_in_flow_mapping},
            nyaml:decode(<<"{a: 1 b: 2}">>)
        )
    ].

%% ============================================================
%% Directive Without Document Error Tests
%% ============================================================

nyaml_directive_without_document_error_test_() ->
    [
        %% Directive without following document
        ?_assertEqual(
            {error, directive_without_document},
            nyaml:decode(<<"%YAML 1.2">>)
        ),
        %% TAG directive without document returns null
        ?_assertEqual(
            {ok, null},
            nyaml:decode(<<"%TAG !e! tag:example">>)
        )
    ].

%% ============================================================
%% Directive Without Document End Error Tests
%% ============================================================

nyaml_directive_without_document_end_test_() ->
    [
        %% New directive without document end
        ?_assertEqual(
            {error, directive_without_document_end},
            nyaml:decode(<<"---\nvalue\n%YAML 1.2\n---\nvalue2">>)
        )
    ].

%% ============================================================
%% Unexpected Content Error Tests
%% ============================================================

nyaml_unexpected_content_error_test_() ->
    [
        %% Invalid content after document end
        ?_assertEqual(
            {error, invalid_content_after_document_end},
            nyaml:decode(<<"value\n... extra\n!">>)
        )
    ].

%% ============================================================
%% Plain Scalar Indicator Error Extra Tests
%% ============================================================

nyaml_plain_scalar_indicator_error_extra_test_() ->
    [
        %% Sequence indicator after scalar triggers trailing content error
        ?_assertMatch(
            {error, {trailing_content_after_document, <<"- item">>}},
            nyaml:decode(<<"multi\n- item">>)
        ),
        %% Mapping indicator after scalar triggers trailing content error
        ?_assertMatch(
            {error, {trailing_content_after_document, <<"key: value">>}},
            nyaml:decode(<<"multi\nkey: value">>)
        )
    ].

%% ============================================================
%% Invalid Tag Character Error Tests
%% ============================================================

nyaml_invalid_tag_character_error_test_() ->
    [
        %% Tag with @ skips the tag and parses value
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml:decode(<<"!tag@invalid value">>)
        )
    ].

%% ============================================================
%% Content After Comment Error Extra Tests
%% ============================================================

nyaml_content_after_comment_error_extra_test_() ->
    [
        %% Content after inline comment
        ?_assertEqual(
            {error, content_after_comment},
            nyaml:decode(<<"value #comment\nextra">>)
        )
    ].

%% ============================================================
%% Invalid Anchor Name Error Extra Tests
%% ============================================================

nyaml_invalid_anchor_name_error_extra_test_() ->
    [
        %% Anchor with no name
        ?_assertMatch(
            {error, {invalid_anchor_name, _}},
            nyaml:decode(<<"& value">>)
        ),
        %% Anchor with @ parses as value
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml:decode(<<"&@ value">>)
        )
    ].

%% ============================================================
%% Invalid Tag Name Error Extra Tests
%% ============================================================

nyaml_invalid_tag_name_error_extra_test_() ->
    [
        %% Empty tag name
        ?_assertMatch(
            {error, {invalid_tag_name, _}},
            nyaml:decode(<<"!! value">>)
        )
    ].

%% ============================================================
%% Parse Number Edge Cases Tests
%% ============================================================

nyaml_parse_number_edge_test_() ->
    [
        %% Positive integer
        ?_assertEqual(
            {ok, 42},
            nyaml:decode(<<"+42">>)
        ),
        %% Negative integer
        ?_assertEqual(
            {ok, -42},
            nyaml:decode(<<"-42">>)
        ),
        %% Float with positive exponent
        ?_assertEqual(
            {ok, 1.0e10},
            nyaml:decode(<<"1e+10">>)
        ),
        %% Float with negative exponent
        ?_assertEqual(
            {ok, 1.0e-10},
            nyaml:decode(<<"1e-10">>)
        ),
        %% Float starting with dot
        ?_assertEqual(
            {ok, 0.5},
            nyaml:decode(<<".5">>)
        )
    ].

%% ============================================================
%% Block Scalar Chomping Extra Tests
%% ============================================================

nyaml_block_scalar_chomping_extra_test_() ->
    [
        %% Literal block with strip chomping
        ?_assertEqual(
            {ok, <<"line1\nline2">>},
            nyaml:decode(<<"|-\n  line1\n  line2\n">>)
        ),
        %% Literal block with keep chomping
        ?_assertEqual(
            {ok, <<"line1\nline2\n\n">>},
            nyaml:decode(<<"|+\n  line1\n  line2\n\n">>)
        ),
        %% Folded block with strip chomping
        ?_assertEqual(
            {ok, <<"line1 line2">>},
            nyaml:decode(<<">-\n  line1\n  line2\n">>)
        ),
        %% Folded block with keep chomping
        ?_assertEqual(
            {ok, <<"line1 line2\n\n">>},
            nyaml:decode(<<">+\n  line1\n  line2\n\n">>)
        )
    ].

%% ============================================================
%% Block Scalar Indentation Indicator Extra Tests
%% ============================================================

nyaml_block_scalar_indent_indicator_extra_test_() ->
    [
        %% Literal with explicit indent
        ?_assertEqual(
            {ok, <<"  text\n">>},
            nyaml:decode(<<"|2\n    text">>)
        ),
        %% Folded with explicit indent
        ?_assertEqual(
            {ok, <<"  text\n">>},
            nyaml:decode(<<">2\n    text">>)
        ),
        %% Combined indent and chomping
        ?_assertEqual(
            {ok, <<"  text">>},
            nyaml:decode(<<"|2-\n    text\n">>)
        )
    ].

%% ============================================================
%% Complex Scalar Type Tests
%% ============================================================

nyaml_complex_scalar_types_test_() ->
    [
        %% Positive infinity
        ?_assertEqual(
            {ok, infinity},
            nyaml:decode(<<".inf">>)
        ),
        %% Negative infinity
        ?_assertEqual(
            {ok, negative_infinity},
            nyaml:decode(<<"-.inf">>)
        ),
        %% Not a number
        ?_assertEqual(
            {ok, nan},
            nyaml:decode(<<".nan">>)
        ),
        %% Hexadecimal integer
        ?_assertEqual(
            {ok, 255},
            nyaml:decode(<<"0xff">>)
        ),
        %% Octal integer
        ?_assertEqual(
            {ok, 8},
            nyaml:decode(<<"0o10">>)
        )
    ].

%% ============================================================
%% Timestamp Parsing Tests
%% ============================================================

nyaml_timestamp_parsing_test_() ->
    [
        %% Date only (preserved as string)
        ?_assertEqual(
            {ok, <<"2024-01-15">>},
            nyaml:decode(<<"2024-01-15">>)
        ),
        %% Date and time (preserved as string)
        ?_assertEqual(
            {ok, <<"2024-01-15 10:30:00">>},
            nyaml:decode(<<"2024-01-15 10:30:00">>)
        ),
        %% ISO format with T separator (parsed as datetime)
        ?_assertEqual(
            {ok, {{2024, 1, 15}, {10, 30, 0}}},
            nyaml:decode(<<"2024-01-15T10:30:00">>)
        ),
        %% With timezone Z (parsed as datetime)
        ?_assertEqual(
            {ok, {{2024, 1, 15}, {10, 30, 0}}},
            nyaml:decode(<<"2024-01-15T10:30:00Z">>)
        )
    ].

%% ============================================================
%% Base64 Binary Tests
%% ============================================================

%% The "Core Schema" section, subsection "Tags", says that the core schema uses
%% the same tags as the JSON schema. "Available Tags" says that a node whose tag
%% has no native type composes but constructs nothing, so the node keeps the
%% value that its kind gives. Fixtures `565N`, `2XXW`, and `J7PZ`.
nyaml_out_of_core_schema_tag_test_() ->
    Block =
        <<
            "!!binary |\n"
            " R0lGODlhDAAMAIQAAP//9/X\n"
            " 56enmleECcgggoBADs=\n"
        >>,
    [
        ?_assertEqual({ok, <<"aGVsbG8=">>}, nyaml:decode(<<"!!binary aGVsbG8=">>)),
        ?_assertEqual(
            {ok, <<"R0lGODlhDAAMAIQAAP//9/X\n56enmleECcgggoBADs=\n">>}, nyaml:decode(Block)
        ),
        ?_assertEqual({ok, [<<"aGVsbG8=">>]}, nyaml:decode(<<"- !!binary aGVsbG8=\n">>)),
        ?_assertEqual({ok, [<<"aGVsbG8=">>]}, nyaml:decode(<<"[!!binary aGVsbG8=]">>)),
        ?_assertEqual(
            {ok, #{<<"aGVsbG8=">> => <<"v">>}}, nyaml:decode(<<"!!binary aGVsbG8=: v\n">>)
        ),
        ?_assertEqual(
            {ok, #{<<"a">> => null, <<"b">> => null}}, nyaml:decode(<<"--- !!set\n? a\n? b\n">>)
        ),
        ?_assertEqual(
            {ok, [#{<<"a">> => 1}, #{<<"b">> => 2}]},
            nyaml:decode(<<"--- !!omap\n- a: 1\n- b: 2\n">>)
        ),
        ?_assertEqual({ok, <<"bar">>}, nyaml:decode(<<"!foo bar">>)),
        ?_assertEqual({ok, <<"bar">>}, nyaml:decode(<<"!<tag:example.com,2000:x> bar">>))
    ].

%% The opposite verdict of `nyaml_out_of_core_schema_tag_test_`. A tag that the
%% core schema does carry converts its node.
nyaml_core_schema_tag_test_() ->
    [
        ?_assertEqual({ok, <<"42">>}, nyaml:decode(<<"!!str 42">>)),
        ?_assertEqual({ok, 42}, nyaml:decode(<<"!!int \"42\"">>)),
        ?_assertEqual({ok, 1.0}, nyaml:decode(<<"!!float 1">>)),
        ?_assertEqual({ok, true}, nyaml:decode(<<"!!bool true">>)),
        ?_assertEqual({ok, null}, nyaml:decode(<<"!!null anything">>))
    ].

%% ============================================================
%% The `binary' Tag Under the Extended Schema Tests
%% ============================================================

%% "Tag Resolution" asks a processor for a mechanism that lets the application
%% override and expand the default tag resolution rules, and "Core Schema"
%% calls the core schema the default "unless instructed otherwise". The
%% extended schema is that mechanism. It carries the `binary' type of the YAML
%% 1.1 type repository, which the "Various Explicit Tags" example of the "Tags"
%% section writes as a base64 block scalar.
nyaml_extended_binary_tag_test_() ->
    Extended = #{schema => extended},
    Block =
        <<
            "!!binary |\n"
            " R0lGODlhDAAMAIQAAP//9/X\n"
            " 17unp5WZmZgAAAOfn515eXv\n"
            " Pz7Y6OjuDg4J+fn5OTk6enp\n"
            " 56enmleECcgggoBADs=\n"
        >>,
    OneLine =
        <<
            "!!binary R0lGODlhDAAMAIQAAP//9/X17unp5WZmZgAAAOfn515eXv"
            "Pz7Y6OjuDg4J+fn5OTk6enp56enmleECcgggoBADs="
        >>,
    [
        ?_assertEqual(
            {ok, {binary, <<"hello">>}},
            nyaml:decode(<<"!!binary aGVsbG8=">>, Extended)
        ),
        ?_assertEqual({ok, <<"aGVsbG8=">>}, nyaml:decode(<<"!!binary aGVsbG8=">>)),
        ?_assertEqual(nyaml:decode(OneLine, Extended), nyaml:decode(Block, Extended)),
        ?_assertMatch({ok, {binary, <<"GIF89a", _/binary>>}}, nyaml:decode(Block, Extended)),
        ?_assertEqual(
            {ok, [{binary, <<"hi">>}]},
            nyaml:decode(<<"- !!binary aGk=\n">>, Extended)
        ),
        ?_assertEqual(
            {ok, #{<<"k">> => {binary, <<"hi">>}}},
            nyaml:decode(<<"k: !!binary aGk=\n">>, Extended)
        ),
        ?_assertEqual(
            {ok, #{{binary, <<"hi">>} => <<"v">>}},
            nyaml:decode(<<"!!binary aGk=: v\n">>, Extended)
        ),
        ?_assertEqual(
            {ok, [{binary, <<"hi">>}]},
            nyaml:decode_all(<<"--- !!binary aGk=\n">>, Extended)
        )
    ].

%% `base64:decode/1' requires the padding, so all three group widths decode.
nyaml_extended_binary_padding_test_() ->
    Extended = #{schema => extended},
    [
        ?_assertEqual({ok, {binary, <<"abc">>}}, nyaml:decode(<<"!!binary YWJj">>, Extended)),
        ?_assertEqual({ok, {binary, <<"hi">>}}, nyaml:decode(<<"!!binary aGk=">>, Extended)),
        ?_assertEqual({ok, {binary, <<"a">>}}, nyaml:decode(<<"!!binary YQ==">>, Extended)),
        ?_assertEqual({ok, {binary, <<>>}}, nyaml:decode(<<"!!binary">>, Extended)),
        ?_assertEqual({ok, [{binary, <<>>}]}, nyaml:decode(<<"- !!binary\n">>, Extended)),
        ?_assertEqual({ok, [{binary, <<>>}]}, nyaml:decode(<<"[!!binary]">>, Extended))
    ].

%% Every space, tab, carriage return, and line feed is removed before the
%% decode, so the block form and the flow form of the same content agree.
nyaml_extended_binary_whitespace_test_() ->
    Extended = #{schema => extended},
    [
        ?_assertEqual(
            {ok, {binary, <<"hello">>}},
            nyaml:decode(<<"!!binary \"aG Vs\tbG8=\"">>, Extended)
        ),
        ?_assertEqual(
            {ok, {binary, <<"hello">>}},
            nyaml:decode(<<"!!binary |\n aGVs\n bG8=\n">>, Extended)
        ),
        ?_assertEqual(
            {ok, {binary, <<"hello">>}},
            nyaml:decode(<<"!!binary >\n aGVs\n bG8=\n">>, Extended)
        )
    ].

%% `base64:decode/1' raises on content outside the alphabet, on a padding
%% character inside a group, and on a length that is not a multiple of four.
%% Every raise becomes an error tuple, so nothing leaves the API as an
%% exception.
nyaml_extended_binary_invalid_test_() ->
    Extended = #{schema => extended},
    [
        ?_assertEqual(
            {error, {invalid_base64, <<"zzz">>}},
            nyaml:decode(<<"!!binary zzz">>, Extended)
        ),
        ?_assertEqual(
            {error, {invalid_base64, <<"a=bc">>}},
            nyaml:decode(<<"!!binary \"a=bc\"">>, Extended)
        ),
        ?_assertEqual(
            {error, {invalid_base64, <<"%%%%">>}},
            nyaml:decode(<<"!!binary \"%%%%\"">>, Extended)
        ),
        ?_assertMatch({error, {invalid_base64, _}}, nyaml:decode(<<"!!binary ~">>, Extended))
    ].

%% "Recognized and Valid Tags" makes a node valid only when its content
%% satisfies the constraints of its tag. `binary' is a scalar type, so a
%% sequence or a mapping under it is invalid.
nyaml_extended_binary_kind_test_() ->
    Extended = #{schema => extended},
    [
        ?_assertEqual(
            {error, {tag_kind_mismatch, <<"binary">>, sequence}},
            nyaml:decode(<<"!!binary [1, 2]">>, Extended)
        ),
        ?_assertEqual(
            {error, {tag_kind_mismatch, <<"binary">>, mapping}},
            nyaml:decode(<<"!!binary {a: 1}">>, Extended)
        ),
        ?_assertEqual(
            {error, {tag_kind_mismatch, <<"binary">>, sequence}},
            nyaml:decode(<<"!!binary\n- 1\n">>, Extended)
        )
    ].

%% The tag is what constructs the type. A plain scalar that happens to look
%% like base64 carries no tag, so it stays the string that the core schema
%% gives it under both schemas.
nyaml_extended_binary_needs_the_tag_test_() ->
    Extended = #{schema => extended},
    [
        ?_assertEqual({ok, <<"aGVsbG8=">>}, nyaml:decode(<<"aGVsbG8=">>)),
        ?_assertEqual({ok, <<"aGVsbG8=">>}, nyaml:decode(<<"aGVsbG8=">>, Extended)),
        ?_assertEqual(
            {ok, #{<<"k">> => <<"YWJj">>}},
            nyaml:decode(<<"k: YWJj\n">>, Extended)
        ),
        ?_assertEqual({ok, <<"aGVsbG8=">>}, nyaml:decode(<<"!!str aGVsbG8=">>, Extended))
    ].

%% Every other tag keeps the core rules under the extended schema.
nyaml_extended_schema_keeps_core_tags_test_() ->
    Extended = #{schema => extended},
    [
        ?_assertEqual({ok, <<"42">>}, nyaml:decode(<<"!!str 42">>, Extended)),
        ?_assertEqual({ok, 42}, nyaml:decode(<<"!!int \"42\"">>, Extended)),
        ?_assertEqual({ok, true}, nyaml:decode(<<"!!bool true">>, Extended)),
        ?_assertEqual(
            {ok, #{<<"a">> => null, <<"b">> => null}},
            nyaml:decode(<<"--- !!set\n? a\n? b\n">>, Extended)
        ),
        ?_assertEqual(
            {error, {tag_kind_mismatch, <<"str">>, sequence}},
            nyaml:decode(<<"!!str [1]">>, Extended)
        )
    ].

%% S17: the round trip is value to value. The emitter writes the tuple as a
%% `!!binary' node, and the extended schema reads it back.
nyaml_extended_binary_round_trip_test_() ->
    Extended = #{schema => extended},
    Values = [
        {binary, <<"hello">>},
        {binary, <<>>},
        {binary, <<0, 1, 2, 255>>},
        [{binary, <<"hi">>}, 1],
        #{<<"k">> => {binary, <<"hi">>}},
        #{{binary, <<"hi">>} => <<"v">>},
        [[{binary, <<"a">>}]]
    ],
    [
        {
            iolist_to_binary(io_lib:format("round trip ~p", [V])),
            fun() ->
                {ok, Yaml} = nyaml:encode(V),
                ?assertEqual({ok, V}, nyaml:decode(Yaml, Extended))
            end
        }
     || V <- Values
    ].

%% The emitter writes byte data as a `!!binary' node and a string as a string,
%% so a string that reads like one keeps its quotes.
nyaml_extended_binary_encode_test_() ->
    [
        ?_assertEqual({ok, <<"!!binary aGVsbG8=\n">>}, nyaml:encode({binary, <<"hello">>})),
        ?_assertEqual({ok, <<"'!!binary aGVsbG8='\n">>}, nyaml:encode(<<"!!binary aGVsbG8=">>)),
        ?_assertEqual({ok, <<"aGVsbG8=\n">>}, nyaml:encode(<<"aGVsbG8=">>))
    ].

%% `to_string/1' covers every value that `nyaml:yaml_value()' carries, so a
%% core-schema tag over a timestamp answers rather than raises.
nyaml_str_tag_over_timestamp_test_() ->
    [
        ?_assertEqual(
            {ok, <<"2001-12-15T02:59:43">>},
            nyaml:decode(<<"!!str 2001-12-15T02:59:43">>)
        ),
        ?_assertEqual(
            {ok, {{2001, 12, 15}, {2, 59, 43}}},
            nyaml:decode(<<"2001-12-15T02:59:43">>)
        )
    ].

%% A tag over an explicit key resolves the content of the key as a scalar and
%% answers with an error rather than failing a match. "Recognized and Valid
%% Tags" makes the node invalid when its content does not satisfy the tag, and
%% S04 keeps that verdict inside a tuple.
nyaml_tagged_explicit_key_test_() ->
    Extended = #{schema => extended},
    [
        ?_assertEqual(
            {ok, #{<<"a">> => <<"v">>}},
            nyaml:decode(<<"?\n  !!str \"a\"\n: v\n">>)
        ),
        ?_assertEqual(
            {ok, #{<<"b">> => <<"v">>}},
            nyaml:decode(<<"?\n  !!str 'b'\n: v\n">>)
        ),
        ?_assertEqual(
            {ok, #{7 => <<"v">>}},
            nyaml:decode(<<"?\n  !!int \"7\"\n: v\n">>)
        ),
        ?_assertEqual(
            {error, {tag_kind_mismatch, <<"map">>, scalar}},
            nyaml:decode(<<"?\n  !!map x\n: v\n">>)
        ),
        ?_assertEqual(
            {ok, #{{binary, <<"hi">>} => <<"v">>}},
            nyaml:decode(<<"?\n  !!binary aGk=\n: v\n">>, Extended)
        ),
        ?_assertEqual(
            {ok, #{{binary, <<>>} => <<"v">>}},
            nyaml:decode(<<"?\n  !!binary \"\"\n: v\n">>, Extended)
        ),
        ?_assertEqual(
            {error, {invalid_base64, <<"zzz">>}},
            nyaml:decode(<<"?\n  !!binary zzz\n: v\n">>, Extended)
        ),
        ?_assertEqual(
            {ok, [#{{binary, <<"hi">>} => <<"v">>}]},
            nyaml:decode(<<"-\n  ?\n    !!binary aGk=\n  : v\n">>, Extended)
        )
    ].

%% ============================================================
%% Flow Collection Nesting Tests
%% ============================================================

nyaml_flow_nesting_test_() ->
    [
        %% Deeply nested sequences
        ?_assertEqual(
            {ok, [[[1]]]},
            nyaml:decode(<<"[[[1]]]">>)
        ),
        %% Deeply nested mappings
        ?_assertEqual(
            {ok, #{<<"a">> => #{<<"b">> => #{<<"c">> => 1}}}},
            nyaml:decode(<<"{a: {b: {c: 1}}}">>)
        ),
        %% Mixed nesting
        ?_assertEqual(
            {ok, [#{<<"a">> => [1, 2]}]},
            nyaml:decode(<<"[{a: [1, 2]}]">>)
        )
    ].

%% ============================================================
%% Multiple Documents Tests
%% ============================================================

nyaml_multiple_documents_test_() ->
    [
        %% Two simple documents
        ?_assertEqual(
            {ok, [1, 2]},
            nyaml:decode_all(<<"---\n1\n---\n2">>)
        ),
        %% Documents with different types
        ?_assertEqual(
            {ok, [<<"text">>, 42, [1, 2]]},
            nyaml:decode_all(<<"---\ntext\n---\n42\n---\n- 1\n- 2">>)
        ),
        %% Documents with explicit end
        ?_assertEqual(
            {ok, [1, 2]},
            nyaml:decode_all(<<"---\n1\n...\n---\n2">>)
        )
    ].

%% ============================================================
%% Unicode Content Tests
%% ============================================================

nyaml_unicode_content_test_() ->
    [
        %% UTF-8 string
        ?_assertEqual(
            {ok, <<"héllo"/utf8>>},
            nyaml:decode(<<"héllo"/utf8>>)
        ),
        %% Unicode in key
        ?_assertEqual(
            {ok, #{<<"键"/utf8>> => <<"值"/utf8>>}},
            nyaml:decode(<<"键: 值"/utf8>>)
        ),
        %% Emoji
        ?_assertEqual(
            {ok, <<"🎉"/utf8>>},
            nyaml:decode(<<"🎉"/utf8>>)
        )
    ].

%% ============================================================
%% Escape Sequence Tests
%% ============================================================

nyaml_escape_sequences_test_() ->
    [
        %% Tab escape
        ?_assertEqual(
            {ok, <<"a\tb">>},
            nyaml:decode(<<"\"a\\tb\"">>)
        ),
        %% Newline escape
        ?_assertEqual(
            {ok, <<"a\nb">>},
            nyaml:decode(<<"\"a\\nb\"">>)
        ),
        %% Carriage return escape
        ?_assertEqual(
            {ok, <<"a\rb">>},
            nyaml:decode(<<"\"a\\rb\"">>)
        ),
        %% Backslash escape
        ?_assertEqual(
            {ok, <<"a\\b">>},
            nyaml:decode(<<"\"a\\\\b\"">>)
        ),
        %% Quote escape
        ?_assertEqual(
            {ok, <<"a\"b">>},
            nyaml:decode(<<"\"a\\\"b\"">>)
        ),
        %% Unicode escape
        ?_assertEqual(
            {ok, <<"A">>},
            nyaml:decode(<<"\"\\x41\"">>)
        ),
        %% Unicode 4-digit escape
        ?_assertEqual(
            {ok, <<"A">>},
            nyaml:decode(<<"\"\\u0041\"">>)
        )
    ].

%% ============================================================
%% Single Quoted String Edge Cases Tests
%% ============================================================

nyaml_single_quoted_edge_test_() ->
    [
        %% Escaped single quote
        ?_assertEqual(
            {ok, <<"it's">>},
            nyaml:decode(<<"'it''s'">>)
        ),
        %% Multiple escaped quotes
        ?_assertEqual(
            {ok, <<"a''b">>},
            nyaml:decode(<<"'a''''b'">>)
        ),
        %% Empty single quoted
        ?_assertEqual(
            {ok, <<>>},
            nyaml:decode(<<"''">>)
        )
    ].

%% ============================================================
%% Complex Key Extra Tests
%% ============================================================

nyaml_complex_key_extra_test_() ->
    [
        %% Flow collections as key parsed as string
        ?_assertEqual(
            {ok, #{<<"[1, 2]">> => <<"value">>}},
            nyaml:decode(<<"? [1, 2]\n: value">>)
        ),
        %% Mapping syntax as key parsed as string
        ?_assertEqual(
            {ok, #{<<"{a: 1}">> => <<"value">>}},
            nyaml:decode(<<"? {a: 1}\n: value">>)
        ),
        %% Null key
        ?_assertEqual(
            {ok, #{null => <<"value">>}},
            nyaml:decode(<<"? \n: value">>)
        )
    ].

%% ============================================================
%% Whitespace Handling Tests
%% ============================================================

nyaml_whitespace_handling_test_() ->
    [
        %% Trailing whitespace in value
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml:decode(<<"value   ">>)
        ),
        %% Leading whitespace trimmed at top level
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml:decode(<<"   value">>)
        ),
        %% Multiple blank lines
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml:decode(<<"\n\n\nvalue">>)
        )
    ].

%% ============================================================
%% Comment Placement Tests
%% ============================================================

nyaml_comment_placement_test_() ->
    [
        %% Comment at start of document
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml:decode(<<"# comment\nvalue">>)
        ),
        %% Comment after value
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml:decode(<<"value # comment">>)
        ),
        %% Comment between entries
        ?_assertEqual(
            {ok, #{<<"a">> => 1, <<"b">> => 2}},
            nyaml:decode(<<"a: 1\n# comment\nb: 2">>)
        ),
        %% Comment in flow context
        ?_assertEqual(
            {ok, #{<<"a">> => 1}},
            nyaml:decode(<<"{a: 1 # comment\n}">>)
        )
    ].

%% ============================================================
%% Null Value Representations Tests
%% ============================================================

nyaml_null_representations_test_() ->
    [
        %% Explicit null
        ?_assertEqual(
            {ok, null},
            nyaml:decode(<<"null">>)
        ),
        %% Tilde not recognized as null
        ?_assertEqual(
            {ok, <<"~">>},
            nyaml:decode(<<"~">>)
        ),
        %% Empty value in mapping
        ?_assertEqual(
            {ok, #{<<"key">> => null}},
            nyaml:decode(<<"key:">>)
        ),
        %% Uppercase NULL not recognized
        ?_assertEqual(
            {ok, <<"NULL">>},
            nyaml:decode(<<"NULL">>)
        ),
        %% Capitalized Null not recognized
        ?_assertEqual(
            {ok, <<"Null">>},
            nyaml:decode(<<"Null">>)
        )
    ].

%% ============================================================
%% Boolean Representations Tests
%% ============================================================

nyaml_boolean_representations_test_() ->
    [
        %% Lowercase true/false
        ?_assertEqual(
            {ok, true},
            nyaml:decode(<<"true">>)
        ),
        ?_assertEqual(
            {ok, false},
            nyaml:decode(<<"false">>)
        ),
        %% Uppercase TRUE/FALSE not recognized
        ?_assertEqual(
            {ok, <<"TRUE">>},
            nyaml:decode(<<"TRUE">>)
        ),
        ?_assertEqual(
            {ok, <<"FALSE">>},
            nyaml:decode(<<"FALSE">>)
        ),
        %% Capitalized True/False not recognized
        ?_assertEqual(
            {ok, <<"True">>},
            nyaml:decode(<<"True">>)
        ),
        ?_assertEqual(
            {ok, <<"False">>},
            nyaml:decode(<<"False">>)
        )
    ].

%% ============================================================
%% Alias Resolution Tests
%% ============================================================

nyaml_alias_resolution_test_() ->
    [
        %% Simple alias
        ?_assertEqual(
            {ok, #{<<"a">> => 1, <<"b">> => 1}},
            nyaml:decode(<<"a: &ref 1\nb: *ref">>)
        ),
        %% Alias to complex value
        ?_assertEqual(
            {ok, #{<<"a">> => [1, 2], <<"b">> => [1, 2]}},
            nyaml:decode(<<"a: &ref\n  - 1\n  - 2\nb: *ref">>)
        ),
        %% Alias in sequence
        ?_assertEqual(
            {ok, [1, 1]},
            nyaml:decode(<<"- &ref 1\n- *ref">>)
        )
    ].

%% ============================================================
%% Mixed Indentation Tests
%% ============================================================

nyaml_mixed_indentation_test_() ->
    [
        %% Two-space indentation
        ?_assertEqual(
            {ok, #{<<"a">> => #{<<"b">> => 1}}},
            nyaml:decode(<<"a:\n  b: 1">>)
        ),
        %% Four-space indentation
        ?_assertEqual(
            {ok, #{<<"a">> => #{<<"b">> => 1}}},
            nyaml:decode(<<"a:\n    b: 1">>)
        ),
        %% Inconsistent but valid indentation
        ?_assertEqual(
            {ok, #{<<"a">> => #{<<"b">> => 1, <<"c">> => 2}}},
            nyaml:decode(<<"a:\n  b: 1\n  c: 2">>)
        )
    ].

%% ============================================================
%% Empty Collection Extra Tests
%% ============================================================

nyaml_empty_collection_extra_test_() ->
    [
        %% Empty flow sequence
        ?_assertEqual(
            {ok, []},
            nyaml:decode(<<"[]">>)
        ),
        %% Empty flow mapping
        ?_assertEqual(
            {ok, #{}},
            nyaml:decode(<<"{}">>)
        ),
        %% Empty flow with whitespace
        ?_assertEqual(
            {ok, []},
            nyaml:decode(<<"[  ]">>)
        ),
        ?_assertEqual(
            {ok, #{}},
            nyaml:decode(<<"{  }">>)
        )
    ].

%% ============================================================
%% Multiline Flow Collection Extra Tests
%% ============================================================

nyaml_multiline_flow_extra_test_() ->
    [
        %% Sequence across lines
        ?_assertEqual(
            {ok, [1, 2, 3]},
            nyaml:decode(<<"[\n  1,\n  2,\n  3\n]">>)
        ),
        %% Mapping across lines
        ?_assertEqual(
            {ok, #{<<"a">> => 1, <<"b">> => 2}},
            nyaml:decode(<<"{\n  a: 1,\n  b: 2\n}">>)
        )
    ].

%% ============================================================
%% Tag Resolution Extra Tests
%% ============================================================

nyaml_tag_resolution_extra_test_() ->
    [
        %% Explicit string tag
        ?_assertEqual(
            {ok, <<"123">>},
            nyaml:decode(<<"!!str 123">>)
        ),
        %% Explicit int tag
        ?_assertEqual(
            {ok, 123},
            nyaml:decode(<<"!!int 123">>)
        ),
        %% Explicit float tag
        ?_assertEqual(
            {ok, 1.0},
            nyaml:decode(<<"!!float 1">>)
        ),
        %% Explicit bool tag with 'yes', which is no token of the core schema
        ?_assertEqual(
            {error, {invalid_tag_content, <<"bool">>, <<"yes">>}},
            nyaml:decode(<<"!!bool yes">>)
        ),
        %% Explicit null tag
        ?_assertEqual(
            {ok, null},
            nyaml:decode(<<"!!null">>)
        )
    ].

%% ============================================================
%% Block in Flow Tests
%% ============================================================

nyaml_block_in_flow_test_() ->
    [
        %% Block sequence value in flow mapping
        ?_assertEqual(
            {ok, #{<<"key">> => [1, 2]}},
            nyaml:decode(<<"{key: [1, 2]}">>)
        ),
        %% Block mapping value in flow sequence
        ?_assertEqual(
            {ok, [#{<<"a">> => 1}]},
            nyaml:decode(<<"[{a: 1}]">>)
        )
    ].

%% ============================================================
%% Special Character Handling Tests
%% ============================================================

nyaml_special_chars_test_() ->
    [
        %% Colon in quoted string
        ?_assertEqual(
            {ok, <<"a:b">>},
            nyaml:decode(<<"\"a:b\"">>)
        ),
        %% Hash in quoted string
        ?_assertEqual(
            {ok, <<"a#b">>},
            nyaml:decode(<<"\"a#b\"">>)
        ),
        %% Brackets in quoted string
        ?_assertEqual(
            {ok, <<"[a]">>},
            nyaml:decode(<<"\"[a]\"">>)
        ),
        %% Braces in quoted string
        ?_assertEqual(
            {ok, <<"{a}">>},
            nyaml:decode(<<"\"{a}\"">>)
        )
    ].

%% ============================================================
%% Flow Sequence as Mapping Key Tests
%% ============================================================

nyaml_flow_key_as_mapping_key_test_() ->
    [
        %% Simple list as key
        ?_assertEqual(
            {ok, #{[1] => <<"value">>}},
            nyaml:decode(<<"[1]: value">>)
        ),
        %% Mapping as key
        ?_assertEqual(
            {ok, #{#{<<"a">> => 1} => <<"value">>}},
            nyaml:decode(<<"{a: 1}: value">>)
        )
    ].

%% ============================================================
%% Large Integer Tests
%% ============================================================

nyaml_large_integer_test_() ->
    [
        %% Large positive integer
        ?_assertEqual(
            {ok, 9999999999999999999},
            nyaml:decode(<<"9999999999999999999">>)
        ),
        %% Large negative integer
        ?_assertEqual(
            {ok, -9999999999999999999},
            nyaml:decode(<<"-9999999999999999999">>)
        )
    ].

%% ============================================================
%% Scientific Notation Extra Tests
%% ============================================================

nyaml_scientific_notation_extra_test_() ->
    [
        %% Uppercase E
        ?_assertEqual(
            {ok, 1.0e10},
            nyaml:decode(<<"1E10">>)
        ),
        %% Lowercase e
        ?_assertEqual(
            {ok, 1.0e10},
            nyaml:decode(<<"1e10">>)
        ),
        %% Explicit positive exponent
        ?_assertEqual(
            {ok, 1.0e10},
            nyaml:decode(<<"1E+10">>)
        )
    ].

%% ============================================================
%% Tab in Indentation Tests
%% ============================================================

nyaml_tab_in_indentation_test_() ->
    [
        %% Tab in indentation triggers error
        ?_assertEqual(
            {error, tab_in_indentation},
            nyaml:decode(<<"key:\n\tvalue">>)
        )
    ].

%% ============================================================
%% Nested Block Mapping Tests
%% ============================================================

nyaml_nested_block_mapping_test_() ->
    [
        %% Three levels deep mapping
        ?_assertEqual(
            {ok, #{<<"a">> => #{<<"b">> => #{<<"c">> => <<"value">>}}}},
            nyaml:decode(<<"a:\n  b:\n    c: value">>)
        ),
        %% Sibling mappings at different levels
        ?_assertEqual(
            {ok, #{<<"a">> => #{<<"b">> => #{<<"c">> => <<"v1">>}, <<"d">> => <<"v2">>}}},
            nyaml:decode(<<"a:\n  b:\n    c: v1\n  d: v2">>)
        ),
        %% Multiple nested siblings
        ?_assertEqual(
            {ok, #{<<"a">> => #{<<"b">> => 1}, <<"c">> => #{<<"d">> => 2}}},
            nyaml:decode(<<"a:\n  b: 1\nc:\n  d: 2">>)
        )
    ].

%% ============================================================
%% Nested Block Sequence Tests
%% ============================================================

nyaml_nested_block_sequence_test_() ->
    [
        %% Sequence of mappings
        ?_assertEqual(
            {ok, [#{<<"a">> => 1}, #{<<"b">> => 2}]},
            nyaml:decode(<<"- a: 1\n- b: 2">>)
        ),
        %% Mapping with sequence value
        ?_assertEqual(
            {ok, #{<<"items">> => [1, 2, 3]}},
            nyaml:decode(<<"items:\n  - 1\n  - 2\n  - 3">>)
        ),
        %% Nested sequences
        ?_assertEqual(
            {ok, [[1, 2], [3, 4]]},
            nyaml:decode(<<"-\n  - 1\n  - 2\n-\n  - 3\n  - 4">>)
        ),
        %% Sequence with nested mapping
        ?_assertEqual(
            {ok, [#{<<"a">> => #{<<"b">> => 1}}]},
            nyaml:decode(<<"- a:\n    b: 1">>)
        )
    ].

%% ============================================================
%% Mixed Block Collection Tests
%% ============================================================

nyaml_mixed_block_collection_test_() ->
    [
        %% Mapping containing sequence containing mapping
        ?_assertEqual(
            {ok, #{<<"outer">> => [#{<<"inner">> => <<"value">>}]}},
            nyaml:decode(<<"outer:\n  - inner: value">>)
        ),
        %% Sequence with flow mapping
        ?_assertEqual(
            {ok, [#{<<"a">> => 1, <<"b">> => 2}]},
            nyaml:decode(<<"- {a: 1, b: 2}">>)
        ),
        %% Mapping with flow sequence
        ?_assertEqual(
            {ok, #{<<"list">> => [1, 2, 3]}},
            nyaml:decode(<<"list: [1, 2, 3]">>)
        )
    ].

%% ============================================================
%% Explicit Key Block Tests
%% ============================================================

nyaml_explicit_key_block_test_() ->
    [
        %% Simple explicit key
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"? key\n: value">>)
        ),
        %% Explicit key with complex value
        ?_assertEqual(
            {ok, #{<<"key">> => [1, 2, 3]}},
            nyaml:decode(<<"? key\n:\n  - 1\n  - 2\n  - 3">>)
        ),
        %% Multiple explicit keys
        ?_assertEqual(
            {ok, #{<<"key1">> => <<"v1">>, <<"key2">> => <<"v2">>}},
            nyaml:decode(<<"? key1\n: v1\n? key2\n: v2">>)
        )
    ].

%% ============================================================
%% Anchor in Block Tests
%% ============================================================

nyaml_anchor_in_block_test_() ->
    [
        %% Anchor on scalar in mapping
        ?_assertEqual(
            {ok, #{<<"a">> => 1, <<"b">> => 1}},
            nyaml:decode(<<"a: &ref 1\nb: *ref">>)
        ),
        %% Anchor on mapping value
        ?_assertEqual(
            {ok, #{<<"original">> => #{<<"x">> => 1}, <<"copy">> => #{<<"x">> => 1}}},
            nyaml:decode(<<"original: &ref\n  x: 1\ncopy: *ref">>)
        ),
        %% Anchor on sequence value
        ?_assertEqual(
            {ok, #{<<"list">> => [1, 2], <<"copy">> => [1, 2]}},
            nyaml:decode(<<"list: &ref\n  - 1\n  - 2\ncopy: *ref">>)
        )
    ].

%% ============================================================
%% Block Scalar in Mapping Extra Tests
%% ============================================================

nyaml_block_scalar_in_mapping_extra_test_() ->
    [
        %% Literal scalar as mapping value
        ?_assertEqual(
            {ok, #{<<"text">> => <<"line1\nline2\n">>}},
            nyaml:decode(<<"text: |\n  line1\n  line2">>)
        ),
        %% Folded scalar as mapping value
        ?_assertEqual(
            {ok, #{<<"text">> => <<"line1 line2\n">>}},
            nyaml:decode(<<"text: >\n  line1\n  line2">>)
        ),
        %% Literal scalar in sequence
        ?_assertEqual(
            {ok, [<<"line1\nline2\n">>]},
            nyaml:decode(<<"- |\n  line1\n  line2">>)
        )
    ].

%% ============================================================
%% Empty Value Tests
%% ============================================================

nyaml_empty_value_test_() ->
    [
        %% Empty mapping value
        ?_assertEqual(
            {ok, #{<<"key">> => null}},
            nyaml:decode(<<"key:">>)
        ),
        %% Empty sequence item
        ?_assertEqual(
            {ok, [null, <<"value">>]},
            nyaml:decode(<<"-\n- value">>)
        ),
        %% Nested empty value
        ?_assertEqual(
            {ok, #{<<"outer">> => #{<<"inner">> => null}}},
            nyaml:decode(<<"outer:\n  inner:">>)
        )
    ].

%% ============================================================
%% Tag in Block Tests
%% ============================================================

nyaml_tag_in_block_test_() ->
    [
        %% Global tag on mapping value
        ?_assertEqual(
            {ok, #{<<"number">> => 123}},
            nyaml:decode(<<"number: !!int 123">>)
        ),
        %% Global tag on sequence item
        ?_assertEqual(
            {ok, [<<"123">>]},
            nyaml:decode(<<"- !!str 123">>)
        ),
        %% Local tag
        ?_assertEqual(
            {ok, #{<<"data">> => <<"value">>}},
            nyaml:decode(<<"data: !custom value">>)
        )
    ].

%% ============================================================
%% Complex Indentation Tests
%% ============================================================

nyaml_complex_indentation_test_() ->
    [
        %% Return to lower indent level
        ?_assertEqual(
            {ok, #{<<"a">> => #{<<"b">> => 1}, <<"c">> => 2}},
            nyaml:decode(<<"a:\n    b: 1\nc: 2">>)
        ),
        %% Deep nesting return
        ?_assertEqual(
            {ok, #{<<"x">> => #{<<"y">> => #{<<"z">> => 1}}, <<"top">> => 2}},
            nyaml:decode(<<"x:\n  y:\n    z: 1\ntop: 2">>)
        ),
        %% Four-space indentation
        ?_assertEqual(
            {ok, #{<<"root">> => #{<<"child">> => <<"value">>}}},
            nyaml:decode(<<"root:\n    child: value">>)
        )
    ].

%% ============================================================
%% Comment in Block Tests
%% ============================================================

nyaml_comment_in_block_test_() ->
    [
        %% Comment after key
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"key: value # comment">>)
        ),
        %% Comment line between entries
        ?_assertEqual(
            {ok, #{<<"a">> => 1, <<"b">> => 2}},
            nyaml:decode(<<"a: 1\n# middle comment\nb: 2">>)
        ),
        %% Comment at end of file
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml:decode(<<"value\n# end comment">>)
        )
    ].

%% ============================================================
%% Multiline Plain Scalar Tests
%% ============================================================

nyaml_multiline_plain_scalar_test_() ->
    [
        %% Plain scalar folded across lines
        ?_assertEqual(
            {ok, #{<<"key">> => <<"first second">>}},
            nyaml:decode(<<"key: first\n  second">>)
        ),
        %% Multiple continuation lines
        ?_assertEqual(
            {ok, #{<<"key">> => <<"a b c">>}},
            nyaml:decode(<<"key: a\n  b\n  c">>)
        )
    ].

%% ============================================================
%% Edge Cases for Block Parsing
%% ============================================================

nyaml_block_edge_cases_test_() ->
    [
        %% Empty document
        ?_assertEqual(
            {ok, null},
            nyaml:decode(<<>>)
        ),
        %% Whitespace only
        ?_assertEqual(
            {ok, null},
            nyaml:decode(<<"   \n  \n">>)
        ),
        %% Comment only
        ?_assertEqual(
            {ok, null},
            nyaml:decode(<<"# comment only">>)
        ),
        %% Dash not followed by space (not sequence)
        ?_assertEqual(
            {ok, <<"-notsequence">>},
            nyaml:decode(<<"-notsequence">>)
        ),
        %% Colon in value position
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value:with:colons">>}},
            nyaml:decode(<<"key: value:with:colons">>)
        )
    ].

%% ============================================================
%% Quoted Strings in Block Context Tests
%% ============================================================

nyaml_quoted_in_block_test_() ->
    [
        %% Double quoted key
        ?_assertEqual(
            {ok, #{<<"my key">> => <<"value">>}},
            nyaml:decode(<<"\"my key\": value">>)
        ),
        %% Single quoted value
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"key: 'value'">>)
        ),
        %% Quoted with special chars
        ?_assertEqual(
            {ok, #{<<"key:colon">> => <<"val#hash">>}},
            nyaml:decode(<<"\"key:colon\": \"val#hash\"">>)
        )
    ].

%% ============================================================
%% Document Markers Extra Tests
%% ============================================================

nyaml_document_markers_extra_test_() ->
    [
        %% Document start marker
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml:decode(<<"---\nvalue">>)
        ),
        %% Document end marker
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml:decode(<<"value\n...">>)
        ),
        %% Both markers
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml:decode(<<"---\nvalue\n...">>)
        )
    ].

%% ============================================================
%% Sequence Item Types Tests
%% ============================================================

nyaml_sequence_item_types_test_() ->
    [
        %% Integer items
        ?_assertEqual(
            {ok, [1, 2, 3]},
            nyaml:decode(<<"- 1\n- 2\n- 3">>)
        ),
        %% Float items
        ?_assertEqual(
            {ok, [1.5, 2.5]},
            nyaml:decode(<<"- 1.5\n- 2.5">>)
        ),
        %% Boolean items
        ?_assertEqual(
            {ok, [true, false]},
            nyaml:decode(<<"- true\n- false">>)
        ),
        %% Mixed items
        ?_assertEqual(
            {ok, [1, <<"text">>, true, null]},
            nyaml:decode(<<"- 1\n- text\n- true\n-">>)
        )
    ].

%% ============================================================
%% Mapping Value Types Tests
%% ============================================================

nyaml_mapping_value_types_test_() ->
    [
        %% Integer value
        ?_assertEqual(
            {ok, #{<<"count">> => 42}},
            nyaml:decode(<<"count: 42">>)
        ),
        %% Float value
        ?_assertEqual(
            {ok, #{<<"price">> => 19.99}},
            nyaml:decode(<<"price: 19.99">>)
        ),
        %% Boolean value
        ?_assertEqual(
            {ok, #{<<"enabled">> => true}},
            nyaml:decode(<<"enabled: true">>)
        ),
        %% Null value
        ?_assertEqual(
            {ok, #{<<"empty">> => null}},
            nyaml:decode(<<"empty: null">>)
        )
    ].

%% ============================================================
%% Compact Block Sequence Tests
%% ============================================================

nyaml_compact_block_sequence_test_() ->
    [
        %% Compact sequence notation
        ?_assertEqual(
            {ok, [#{<<"a">> => 1}, #{<<"b">> => 2}]},
            nyaml:decode(<<"- a: 1\n- b: 2">>)
        ),
        %% Compact with nested
        ?_assertEqual(
            {ok, [#{<<"outer">> => #{<<"inner">> => 1}}]},
            nyaml:decode(<<"- outer:\n    inner: 1">>)
        )
    ].

%% ============================================================
%% Value Indicator Edge Cases Tests
%% ============================================================

nyaml_value_indicator_edge_test_() ->
    [
        %% Value indicator with newline
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"? key\n: value">>)
        ),
        %% Value indicator with space
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"? key\n: value">>)
        )
    ].

%% ============================================================
%% Multiple Anchors Error Tests
%% ============================================================

nyaml_multiple_anchors_test_() ->
    [
        %% Two anchors should succeed (second defines same name)
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml:decode(<<"&a &b value">>)
        )
    ].

%% ============================================================
%% Flow in Block Context Tests
%% ============================================================

nyaml_flow_in_block_context_test_() ->
    [
        %% Flow sequence in block mapping
        ?_assertEqual(
            {ok, #{<<"items">> => [1, 2, 3]}},
            nyaml:decode(<<"items: [1, 2, 3]">>)
        ),
        %% Flow mapping in block sequence
        ?_assertEqual(
            {ok, [#{<<"a">> => 1}]},
            nyaml:decode(<<"- {a: 1}">>)
        ),
        %% Nested flow in block
        ?_assertEqual(
            {ok, #{<<"data">> => [#{<<"x">> => 1}]}},
            nyaml:decode(<<"data: [{x: 1}]">>)
        )
    ].

%% ============================================================
%% Anchor Reuse Tests
%% ============================================================

nyaml_anchor_reuse_test_() ->
    [
        %% Multiple uses of same anchor
        ?_assertEqual(
            {ok, #{<<"a">> => 1, <<"b">> => 1, <<"c">> => 1}},
            nyaml:decode(<<"a: &ref 1\nb: *ref\nc: *ref">>)
        ),
        %% Anchor redefine
        ?_assertEqual(
            {ok, #{<<"a">> => 1, <<"b">> => 2, <<"c">> => 2}},
            nyaml:decode(<<"a: &ref 1\nb: &ref 2\nc: *ref">>)
        )
    ].

%% ============================================================
%% Deep Nesting Performance Tests
%% ============================================================

nyaml_deep_nesting_test_() ->
    [
        %% Five levels deep
        ?_assertEqual(
            {ok, #{<<"l1">> => #{<<"l2">> => #{<<"l3">> => #{<<"l4">> => #{<<"l5">> => 1}}}}}},
            nyaml:decode(<<"l1:\n  l2:\n    l3:\n      l4:\n        l5: 1">>)
        )
    ].

%% ============================================================
%% Alias Without Anchor Error Tests
%% ============================================================

nyaml_alias_without_anchor_test_() ->
    [
        %% Alias referencing undefined anchor
        ?_assertEqual(
            {error, {undefined_alias, <<"undefined">>}},
            nyaml:decode(<<"value: *undefined">>)
        )
    ].

%% ============================================================
%% Invalid Mapping Entry Error Tests
%% ============================================================

nyaml_invalid_mapping_entry_error_test_() ->
    [
        %% Mapping entry missing colon
        ?_assertEqual(
            {error, {invalid_mapping_entry, <<"b 2">>}},
            nyaml:decode(<<"key:\n  a: 1\n  b 2">>)
        ),
        %% Invalid block scalar indent
        ?_assertEqual(
            {error, {invalid_mapping_entry, <<"value">>}},
            nyaml:decode(<<"key: >1\nvalue">>)
        )
    ].

%% ============================================================
%% Invalid Sequence Item Error Tests
%% ============================================================

nyaml_invalid_sequence_item_error_test_() ->
    [
        %% Non-item content in sequence
        ?_assertEqual(
            {error, {invalid_sequence_item, <<"  b">>}},
            nyaml:decode(<<"key:\n  - a\n  b">>)
        )
    ].

%% ============================================================
%% Nested Explicit Key Tests
%% ============================================================

nyaml_nested_explicit_key_test_() ->
    [
        %% Nested explicit key produces nested mapping
        ?_assertEqual(
            {ok, #{#{<<"key">> => null} => null}},
            nyaml:decode(<<"?\n? key">>)
        )
    ].

%% ============================================================
%% Block Scalar Edge Cases Tests
%% ============================================================

nyaml_block_scalar_edge_case_test_() ->
    [
        %% Literal block with no indent keeps content
        ?_assertEqual(
            {ok, #{<<"key">> => <<"no indent\n">>}},
            nyaml:decode(<<"key: |\n no indent">>)
        ),
        %% Folded block with content on same line
        ?_assertEqual(
            {ok, #{<<"key">> => <<"line1 line2\n">>}},
            nyaml:decode(<<"key: >\n  line1\n  line2">>)
        )
    ].

%% ============================================================
%% Anchor in Sequence Tests
%% ============================================================

nyaml_anchor_in_sequence_test_() ->
    [
        %% Anchor on sequence item
        ?_assertEqual(
            {ok, [1, 1]},
            nyaml:decode(<<"- &ref 1\n- *ref">>)
        ),
        %% Anchor on nested structure in sequence
        ?_assertEqual(
            {ok, [#{<<"a">> => 1}, #{<<"a">> => 1}]},
            nyaml:decode(<<"- &ref\n  a: 1\n- *ref">>)
        )
    ].

%% ============================================================
%% Comment Edge Cases Tests
%% ============================================================

nyaml_comment_edge_case_test_() ->
    [
        %% Hash in quoted string not a comment
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value#notcomment">>}},
            nyaml:decode(<<"key: \"value#notcomment\"">>)
        ),
        %% Hash at start of line is comment
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml:decode(<<"# comment\nvalue">>)
        ),
        %% Multiple consecutive comments
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml:decode(<<"# comment1\n# comment2\nvalue">>)
        )
    ].

%% ============================================================
%% Quoted Key Edge Cases Tests
%% ============================================================

nyaml_quoted_key_edge_case_test_() ->
    [
        %% Empty quoted key
        ?_assertEqual(
            {ok, #{<<>> => <<"value">>}},
            nyaml:decode(<<"\"\": value">>)
        ),
        %% Key with colon inside quotes
        ?_assertEqual(
            {ok, #{<<"a:b">> => <<"value">>}},
            nyaml:decode(<<"\"a:b\": value">>)
        ),
        %% Single quoted key with space
        ?_assertEqual(
            {ok, #{<<"key name">> => <<"value">>}},
            nyaml:decode(<<"'key name': value">>)
        )
    ].

%% ============================================================
%% Flow Collection in Block Mapping Value Tests
%% ============================================================

nyaml_flow_in_block_mapping_value_test_() ->
    [
        %% Nested flow sequence
        ?_assertEqual(
            {ok, #{<<"matrix">> => [[1, 2], [3, 4]]}},
            nyaml:decode(<<"matrix: [[1, 2], [3, 4]]">>)
        ),
        %% Nested flow mapping
        ?_assertEqual(
            {ok, #{<<"config">> => #{<<"a">> => #{<<"b">> => 1}}}},
            nyaml:decode(<<"config: {a: {b: 1}}">>)
        )
    ].

%% ============================================================
%% Indentation Sensitivity Tests
%% ============================================================

nyaml_indentation_sensitivity_test_() ->
    [
        %% Single space indent
        ?_assertEqual(
            {ok, #{<<"a">> => #{<<"b">> => 1}}},
            nyaml:decode(<<"a:\n b: 1">>)
        ),
        %% Eight space indent
        ?_assertEqual(
            {ok, #{<<"a">> => #{<<"b">> => 1}}},
            nyaml:decode(<<"a:\n        b: 1">>)
        ),
        %% Return to top level after deep nesting
        ?_assertEqual(
            {ok, #{<<"a">> => #{<<"b">> => #{<<"c">> => 1}}, <<"d">> => 2}},
            nyaml:decode(<<"a:\n  b:\n    c: 1\nd: 2">>)
        )
    ].

%% ============================================================
%% Multiline Value Extra Tests
%% ============================================================

nyaml_multiline_value_extra_test_() ->
    [
        %% Plain scalar continues on next indented line
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value continues">>}},
            nyaml:decode(<<"key: value\n  continues">>)
        ),
        %% Multiple continuation lines
        ?_assertEqual(
            {ok, #{<<"key">> => <<"a b c">>}},
            nyaml:decode(<<"key: a\n  b\n  c">>)
        )
    ].

%% ============================================================
%% Global Tag in Block Tests
%% ============================================================

nyaml_global_tag_in_block_test_() ->
    [
        %% Int tag converts string to int
        ?_assertEqual(
            {ok, #{<<"num">> => 42}},
            nyaml:decode(<<"num: !!int 42">>)
        ),
        %% Float tag converts to float
        ?_assertEqual(
            {ok, #{<<"val">> => 1.0}},
            nyaml:decode(<<"val: !!float 1">>)
        ),
        %% Str tag preserves as string
        ?_assertEqual(
            {ok, #{<<"txt">> => <<"42">>}},
            nyaml:decode(<<"txt: !!str 42">>)
        )
    ].

%% ============================================================
%% Sequence with Flow Items Tests
%% ============================================================

nyaml_sequence_with_flow_items_test_() ->
    [
        %% Sequence item is flow sequence
        ?_assertEqual(
            {ok, [[1, 2, 3]]},
            nyaml:decode(<<"- [1, 2, 3]">>)
        ),
        %% Sequence item is flow mapping
        ?_assertEqual(
            {ok, [#{<<"x">> => 1}]},
            nyaml:decode(<<"- {x: 1}">>)
        ),
        %% Mixed flow and block
        ?_assertEqual(
            {ok, [[1], #{<<"a">> => 2}]},
            nyaml:decode(<<"- [1]\n- a: 2">>)
        )
    ].

%% ============================================================
%% Mapping with Sequence Value Tests
%% ============================================================

nyaml_mapping_with_sequence_value_test_() ->
    [
        %% Mapping value is block sequence
        ?_assertEqual(
            {ok, #{<<"items">> => [1, 2, 3]}},
            nyaml:decode(<<"items:\n- 1\n- 2\n- 3">>)
        ),
        %% Multiple mappings with sequence values
        ?_assertEqual(
            {ok, #{<<"a">> => [1], <<"b">> => [2]}},
            nyaml:decode(<<"a:\n- 1\nb:\n- 2">>)
        )
    ].

%% ============================================================
%% Empty Sequence Tests
%% ============================================================

nyaml_empty_sequence_test_() ->
    [
        %% Flow empty sequence
        ?_assertEqual(
            {ok, []},
            nyaml:decode(<<"[]">>)
        ),
        %% Flow empty sequence with spaces
        ?_assertEqual(
            {ok, []},
            nyaml:decode(<<"[   ]">>)
        )
    ].

%% ============================================================
%% Single Item Collection Tests
%% ============================================================

nyaml_single_item_collection_test_() ->
    [
        %% Single item flow sequence
        ?_assertEqual(
            {ok, [1]},
            nyaml:decode(<<"[1]">>)
        ),
        %% Single item flow mapping
        ?_assertEqual(
            {ok, #{<<"a">> => 1}},
            nyaml:decode(<<"{a: 1}">>)
        ),
        %% Single item block sequence
        ?_assertEqual(
            {ok, [<<"value">>]},
            nyaml:decode(<<"- value">>)
        ),
        %% Single item block mapping
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"key: value">>)
        )
    ].

%% ============================================================
%% Tag on Collection Tests
%% ============================================================
%% The "Generic Mapping", "Generic Sequence", and "Generic String" sections give
%% the `map', `seq', and `str' tags a kind, and "Recognized and Valid Tags" makes
%% a node valid only when its content satisfies the constraints of its tag.
nyaml_tag_on_collection_test_() ->
    [
        ?_assertEqual(
            {ok, #{<<"a">> => 1}},
            nyaml:decode(<<"!!map {a: 1}">>)
        ),
        ?_assertEqual(
            {ok, [1, 2]},
            nyaml:decode(<<"!!seq [1, 2]">>)
        ),
        ?_assertEqual(
            {ok, #{<<"a">> => 1}},
            nyaml:decode(<<"!!map\na: 1\n">>)
        ),
        ?_assertEqual(
            {ok, [1, 2]},
            nyaml:decode(<<"!!seq\n- 1\n- 2\n">>)
        ),
        ?_assertEqual(
            {ok, #{<<"k">> => #{<<"a">> => 1}}},
            nyaml:decode(<<"k: !!map {a: 1}\n">>)
        ),
        ?_assertEqual(
            {ok, #{<<"k">> => [1, 2]}},
            nyaml:decode(<<"k: !!seq [1, 2]\n">>)
        )
    ].

nyaml_tag_kind_mismatch_test_() ->
    [
        ?_assertEqual(
            {error, {tag_kind_mismatch, <<"seq">>, mapping}},
            nyaml:decode(<<"!!seq {a: 1}">>)
        ),
        ?_assertEqual(
            {error, {tag_kind_mismatch, <<"map">>, sequence}},
            nyaml:decode(<<"!!map [1, 2]">>)
        ),
        ?_assertEqual(
            {error, {tag_kind_mismatch, <<"seq">>, mapping}},
            nyaml:decode(<<"!!seq\na: 1\n">>)
        ),
        ?_assertEqual(
            {error, {tag_kind_mismatch, <<"map">>, sequence}},
            nyaml:decode(<<"!!map\n- 1\n">>)
        ),
        ?_assertEqual(
            {error, {tag_kind_mismatch, <<"str">>, sequence}},
            nyaml:decode(<<"!!str [1, 2]">>)
        ),
        ?_assertEqual(
            {error, {tag_kind_mismatch, <<"str">>, mapping}},
            nyaml:decode(<<"!!str {a: 1}">>)
        ),
        ?_assertEqual(
            {error, {tag_kind_mismatch, <<"int">>, mapping}},
            nyaml:decode(<<"!!int {a: 1}">>)
        ),
        ?_assertEqual(
            {error, {tag_kind_mismatch, <<"float">>, sequence}},
            nyaml:decode(<<"!!float [1]">>)
        ),
        ?_assertEqual(
            {error, {tag_kind_mismatch, <<"bool">>, sequence}},
            nyaml:decode(<<"!!bool [1]">>)
        ),
        ?_assertEqual(
            {error, {tag_kind_mismatch, <<"null">>, sequence}},
            nyaml:decode(<<"!!null [1]">>)
        ),
        %% S27 keeps a tag outside the core schema off its node, kind and all.
        ?_assertEqual(
            {ok, [1, 2]},
            nyaml:decode(<<"!!binary [1, 2]">>)
        )
    ].

%% A `:' inside a flow collection belongs to the flow pair that the "Flow
%% Mappings" section defines, and a `:' between quotes is content, so neither
%% turns the tagged node into a mapping key.
nyaml_tagged_node_with_inner_colon_test_() ->
    [
        ?_assertEqual(
            {ok, <<"a: b">>},
            nyaml:decode(<<"!!str \"a: b\"">>)
        ),
        ?_assertEqual(
            {ok, <<"a: b">>},
            nyaml:decode(<<"!!str 'a: b'">>)
        ),
        ?_assertEqual(
            {ok, #{<<"foo">> => <<"bar">>}},
            nyaml:decode(<<"!!str foo: bar">>)
        ),
        ?_assertEqual(
            {ok, #{<<"k">> => [<<"a">>, <<"b">>]}},
            nyaml:decode(<<"!!map {\n  k: !!seq\n  [ a, !!str b]\n}\n">>)
        )
    ].

%% "Core Schema" gives the `bool' tag `true | True | TRUE | false | False |
%% FALSE' and nothing else, so a bare `yes' is a string and an explicit
%% `!!bool' over `yes' is invalid content under "Recognized and Valid Tags".
nyaml_bool_tag_test_() ->
    [
        ?_assertEqual({ok, true}, nyaml:decode(<<"!!bool \"true\"">>)),
        ?_assertEqual({ok, false}, nyaml:decode(<<"!!bool \"false\"">>)),
        ?_assertEqual({ok, true}, nyaml:decode(<<"!!bool True">>)),
        ?_assertEqual({ok, true}, nyaml:decode(<<"!!bool TRUE">>)),
        ?_assertEqual({ok, false}, nyaml:decode(<<"!!bool False">>)),
        ?_assertEqual({ok, false}, nyaml:decode(<<"!!bool FALSE">>)),
        ?_assertEqual({ok, <<"yes">>}, nyaml:decode(<<"yes">>)),
        ?_assertEqual(
            {error, {invalid_tag_content, <<"bool">>, <<"yes">>}},
            nyaml:decode(<<"!!bool \"yes\"">>)
        ),
        ?_assertEqual({ok, #{<<"k">> => <<"yes">>}}, nyaml:decode(<<"k: yes\n">>))
    ].

%% The `bool' type of the YAML 1.1 type repository lists `y', `yes', `true',
%% and `on' with their negatives, in the lower case, title case, and upper case
%% spellings. The extended schema takes them under an explicit `!!bool' tag.
%% The bare scalar does not move: the resolution table of "Core Schema" is not
%% what the schema option changes.
nyaml_extended_bool_tag_test_() ->
    Extended = #{schema => extended},
    True = [
        <<"y">>,
        <<"Y">>,
        <<"yes">>,
        <<"Yes">>,
        <<"YES">>,
        <<"on">>,
        <<"On">>,
        <<"ON">>,
        <<"true">>,
        <<"True">>,
        <<"TRUE">>
    ],
    False = [
        <<"n">>,
        <<"N">>,
        <<"no">>,
        <<"No">>,
        <<"NO">>,
        <<"off">>,
        <<"Off">>,
        <<"OFF">>,
        <<"false">>,
        <<"False">>,
        <<"FALSE">>
    ],
    Tagged = fun(Token) -> <<"!!bool ", Token/binary>> end,
    [
        [
            ?_assertEqual({ok, true}, nyaml:decode(Tagged(Token), Extended))
         || Token <- True
        ],
        [
            ?_assertEqual({ok, false}, nyaml:decode(Tagged(Token), Extended))
         || Token <- False
        ],
        [
            ?_assertEqual({ok, Token}, nyaml:decode(Token, Extended))
         || Token <- True ++ False, Token =/= <<"true">>, Token =/= <<"false">>
        ],
        ?_assertEqual(
            {ok, [true, false]}, nyaml:decode(<<"- !!bool yes\n- !!bool no\n">>, Extended)
        ),
        ?_assertEqual(
            {ok, #{<<"k">> => true}}, nyaml:decode(<<"k: !!bool on\n">>, Extended)
        ),
        ?_assertEqual({ok, [true, false]}, nyaml:decode(<<"[!!bool y, !!bool N]">>, Extended)),
        ?_assertEqual({ok, #{true => 1}}, nyaml:decode(<<"!!bool yes: 1\n">>, Extended)),
        ?_assertEqual({ok, true}, nyaml:decode(<<"!!bool \"yes\"">>, Extended)),
        ?_assertEqual({ok, [true]}, nyaml:decode_all(<<"--- !!bool on\n">>, Extended))
    ].

%% "Recognized and Valid Tags" makes a node valid only when its content
%% satisfies the constraints of its tag, so content that no token of the `bool'
%% type matches is an error under both schemas. The empty node is one of them:
%% the common resolution gives it `null', which is no boolean.
nyaml_bool_tag_invalid_content_test_() ->
    Extended = #{schema => extended},
    [
        ?_assertEqual(
            {error, {invalid_tag_content, <<"bool">>, <<"zzz">>}}, nyaml:decode(<<"!!bool zzz">>)
        ),
        ?_assertEqual(
            {error, {invalid_tag_content, <<"bool">>, <<"zzz">>}},
            nyaml:decode(<<"!!bool zzz">>, Extended)
        ),
        ?_assertEqual(
            {error, {invalid_tag_content, <<"bool">>, <<"42">>}}, nyaml:decode(<<"!!bool 42">>)
        ),
        ?_assertEqual(
            {error, {invalid_tag_content, <<"bool">>, <<"null">>}}, nyaml:decode(<<"a: !!bool\n">>)
        ),
        ?_assertEqual(
            {error, {invalid_tag_content, <<"bool">>, <<"null">>}}, nyaml:decode(<<"[!!bool]">>)
        ),
        ?_assertEqual(
            {error, {invalid_tag_content, <<"bool">>, <<"null">>}},
            nyaml:decode(<<"[!!bool]">>, Extended)
        ),
        ?_assertEqual(
            {error, {tag_kind_mismatch, <<"bool">>, sequence}}, nyaml:decode(<<"!!bool [a]">>)
        ),
        ?_assertEqual(
            {error, {tag_kind_mismatch, <<"bool">>, mapping}},
            nyaml:decode(<<"!!bool {a: 1}">>, Extended)
        )
    ].

%% ============================================================
%% Anchor on Collection Tests
%% ============================================================

nyaml_anchor_on_collection_test_() ->
    [
        %% Anchor on flow sequence
        ?_assertEqual(
            {ok, #{<<"list">> => [1, 2], <<"copy">> => [1, 2]}},
            nyaml:decode(<<"list: &ref [1, 2]\ncopy: *ref">>)
        ),
        %% Anchor on flow mapping
        ?_assertEqual(
            {ok, #{<<"map">> => #{<<"a">> => 1}, <<"copy">> => #{<<"a">> => 1}}},
            nyaml:decode(<<"map: &ref {a: 1}\ncopy: *ref">>)
        )
    ].

%% ============================================================
%% YAML 1.2 Directive Tests
%% ============================================================

nyaml_yaml_directive_test_() ->
    [
        %% YAML directive followed by document
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml:decode(<<"%YAML 1.2\n---\nvalue">>)
        )
    ].

%% ============================================================
%% Special Number Values Tests
%% ============================================================

nyaml_special_number_values_test_() ->
    [
        %% Positive zero
        ?_assertEqual(
            {ok, 0},
            nyaml:decode(<<"0">>)
        ),
        %% Negative zero - parser preserves -0.0
        ?_assertEqual(
            {ok, -0.0},
            nyaml:decode(<<"-0.0">>)
        ),
        %% Very small float
        ?_assertEqual(
            {ok, 0.001},
            nyaml:decode(<<"0.001">>)
        ),
        %% Very large float
        ?_assertEqual(
            {ok, 1.0e100},
            nyaml:decode(<<"1e100">>)
        )
    ].

%% ============================================================
%% Uncovered Error Path Tests - Round 3
%% ============================================================

nyaml_uncovered_errors_test_() ->
    [
        %% plain_scalar_continuation_after_comment - triggers content_after_comment
        ?_assertMatch(
            {error, content_after_comment},
            nyaml:decode(<<"value # comment\n  continuation">>)
        ),
        %% [1 2] parses "1 2" as a string value, not an error
        ?_assertEqual(
            {ok, [<<"1 2">>]},
            nyaml:decode(<<"[1 2]">>)
        ),
        %% ] at top level is not an ns-plain-first character
        ?_assertEqual(
            {error, {unexpected_content, <<"]">>}},
            nyaml:decode(<<"]">>)
        ),
        %% } at top level is not an ns-plain-first character
        ?_assertEqual(
            {error, {unexpected_content, <<"}">>}},
            nyaml:decode(<<"}">>)
        ),
        %% unterminated_single_quoted_string
        ?_assertMatch(
            {error, unterminated_single_quoted_string},
            nyaml:decode(<<"'unterminated">>)
        ),
        %% unterminated_verbatim_tag
        ?_assertMatch(
            {error, unterminated_verbatim_tag},
            nyaml:decode(<<"!<tag value">>)
        ),
        %% no_version_number in YAML directive
        ?_assertMatch(
            {error, invalid_yaml_directive},
            nyaml:decode(<<"%YAML\n---\nvalue">>)
        ),
        %% TAG directive with missing prefix is silently ignored
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml:decode(<<"%TAG !e!\n---\nvalue">>)
        ),
        %% Leading whitespace parses the content as plain scalar
        ?_assertEqual(
            {ok, <<"plain_value_no_structure">>},
            nyaml:decode(<<"  plain_value_no_structure">>)
        ),
        %% Comma at start of value is parsed as part of the value
        ?_assertEqual(
            {ok, #{<<"key">> => <<",value">>}},
            nyaml:decode(<<"key:\n  ,value">>)
        ),
        %% Unclosed bracket in sequence value returns unterminated_sequence
        ?_assertEqual(
            {error, unterminated_sequence},
            nyaml:decode(<<"- \n  [">>)
        ),
        %% Multiline scalar continuation is parsed as scalar
        ?_assertEqual(
            {ok, [<<"a notdash">>]},
            nyaml:decode(<<"- a\n  notdash">>)
        ),
        %% invalid_tag_name - empty tag name after !!
        ?_assertMatch(
            {error, {invalid_tag_name, _}},
            nyaml:decode(<<"!! value">>)
        ),
        %% Tab in indentation position triggers error
        ?_assertEqual(
            {error, tab_in_indentation},
            nyaml:decode(<<"a:\n\tb">>)
        ),
        %% invalid_anchor_name - anchor with empty name
        ?_assertMatch(
            {error, {invalid_anchor_name, _}},
            nyaml:decode(<<"& value">>)
        ),
        %% anchor_followed_by_alias - anchor pointing to alias
        ?_assertEqual(
            {error, anchor_followed_by_alias},
            nyaml:decode(<<"key: &ref *alias">>)
        ),
        %% anchor followed by dash is parsed as a scalar
        ?_assertEqual(
            {ok, #{<<"key">> => <<"-">>}},
            nyaml:decode(<<"key: &ref -">>)
        ),
        %% anchor followed by sequence is parsed as block sequence
        ?_assertEqual(
            {ok, #{<<"key">> => [<<"item">>]}},
            nyaml:decode(<<"key: &ref - item">>)
        ),
        %% two_anchors_on_same_node
        ?_assertEqual(
            {error, two_anchors_on_same_node},
            nyaml:decode(<<"key: &ref1\n  &ref2 value">>)
        ),
        %% unterminated_mapping
        ?_assertEqual(
            {error, unterminated_mapping},
            nyaml:decode(<<"{a: 1">>)
        ),
        %% missing_comma_in_flow_mapping
        ?_assertEqual(
            {error, missing_comma_in_flow_mapping},
            nyaml:decode(<<"{a: 1 b: 2}">>)
        ),
        %% trailing_content_after_value - content after flow value
        ?_assertEqual(
            {error, trailing_content_after_value},
            nyaml:decode(<<"key: [1] extra">>)
        ),
        %% invalid_comment_after_bracket - comment without space after bracket
        ?_assertEqual(
            {error, invalid_comment_after_bracket},
            nyaml:decode(<<"key: [1]#comment">>)
        )
    ].

nyaml_flow_errors_test_() ->
    [
        %% Flow sequence trailing content
        ?_assertMatch(
            {error, _},
            nyaml:decode(<<"[1, 2] extra">>)
        ),
        %% Flow mapping trailing content
        ?_assertMatch(
            {error, _},
            nyaml:decode(<<"{a: 1} extra">>)
        ),
        %% Deeply nested flow with error
        ?_assertMatch(
            {error, _},
            nyaml:decode(<<"[[[1, 2">>)
        ),
        %% Mixed flow collections with error
        ?_assertMatch(
            {error, _},
            nyaml:decode(<<"[{a: 1">>)
        ),
        %% Flow collection with unclosed quote
        ?_assertMatch(
            {error, _},
            nyaml:decode(<<"[\"unclosed]">>)
        ),
        %% Flow mapping with no value after colon
        ?_assertEqual(
            {ok, #{<<"key">> => null}},
            nyaml:decode(<<"{key:}">>)
        ),
        %% Flow sequence with space before bracket
        ?_assertEqual(
            {ok, [1]},
            nyaml:decode(<<" [1]">>)
        ),
        %% Flow mapping with space before brace
        ?_assertEqual(
            {ok, #{<<"a">> => 1}},
            nyaml:decode(<<" {a: 1}">>)
        ),
        %% Closing bracket at start is not an ns-plain-first character
        ?_assertEqual(
            {error, {unexpected_content, <<"]#comment">>}},
            nyaml:decode(<<"]#comment">>)
        ),
        %% Comment immediately after comma without space
        ?_assertEqual(
            {error, invalid_comment_after_comma},
            nyaml:decode(<<"[1,#comment]">>)
        ),
        %% Empty sequence with trailing comma
        ?_assertEqual(
            {error, empty_sequence_with_comma},
            nyaml:decode(<<"[,]">>)
        ),
        %% Leading comma in flow sequence
        ?_assertEqual(
            {error, invalid_leading_comma_in_sequence},
            nyaml:decode(<<"[,1]">>)
        ),
        %% Consecutive commas in flow sequence
        ?_assertEqual(
            {error, consecutive_commas_in_sequence},
            nyaml:decode(<<"[1,,2]">>)
        ),
        %% Bare dash in flow sequence with space
        ?_assertEqual(
            {error, bare_dash_in_flow_sequence},
            nyaml:decode(<<"[- item]">>)
        ),
        %% Bare dash in flow sequence with bracket
        ?_assertEqual(
            {error, bare_dash_in_flow_sequence},
            nyaml:decode(<<"[-]">>)
        ),
        %% Bare dash in flow sequence with comma
        ?_assertEqual(
            {error, bare_dash_in_flow_sequence},
            nyaml:decode(<<"[1, -,2]">>)
        ),
        %% Flow mapping key can span lines (whitespace folded)
        ?_assertEqual(
            {ok, #{<<"multi line">> => <<"value">>}},
            nyaml:decode(<<"{multi\nline: value}">>)
        ),
        %% Flow scalar value with newline and terminator
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"{key: value\n}">>)
        ),
        %% Flow mapping with explicit key - using ?
        ?_assertEqual(
            {ok, #{<<"explicit key">> => <<"value">>}},
            nyaml:decode(<<"{? explicit key : value}">>)
        ),
        %% Flow sequence value with newline
        ?_assertEqual(
            {ok, [<<"value">>]},
            nyaml:decode(<<"[value\n]">>)
        ),
        %% Flow scalar value ending with colon only
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"{key: value}">>)
        ),
        %% Flow mapping with comment after newline
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"{key: value\n# comment\n}">>)
        )
    ].

nyaml_block_edge_cases_additional_test_() ->
    [
        %% Block mapping with anchor on key
        ?_assertMatch(
            {ok, #{<<"key">> := <<"value">>}},
            nyaml:decode(<<"&anchor key: value">>)
        ),
        %% Alias as key returns error in this parser
        ?_assertMatch(
            {error, {invalid_mapping_entry, _}},
            nyaml:decode(<<"a: &ref key\n*ref: value">>)
        ),
        %% Nested block mapping with anchors
        ?_assertMatch(
            {ok, _},
            nyaml:decode(<<"outer:\n  &ref inner: value\nanother: *ref">>)
        ),
        %% Block scalar with explicit indentation
        ?_assertMatch(
            {ok, _},
            nyaml:decode(<<"|\n  line1\n  line2">>)
        ),
        %% Block sequence inside mapping value
        ?_assertEqual(
            {ok, #{<<"items">> => [1, 2, 3]}},
            nyaml:decode(<<"items:\n  - 1\n  - 2\n  - 3">>)
        ),
        %% Empty block mapping
        ?_assertEqual(
            {ok, #{}},
            nyaml:decode(<<"---\n{}">>)
        ),
        %% Block with comment before content
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml:decode(<<"# comment\nvalue">>)
        ),
        %% Tab at column 0 triggers tab_in_indentation error
        ?_assertEqual(
            {error, tab_in_indentation},
            nyaml:decode(<<"key:\n\tvalue">>)
        ),
        %% Plain content is parsed as scalar (no error)
        ?_assertEqual(
            {ok, <<"just_content_no_indicator">>},
            nyaml:decode(<<"\n\njust_content_no_indicator">>)
        ),
        %% Explicit key with continuation is multiline key
        ?_assertMatch(
            {ok, #{<<"key not_a_value_indicator">> := null}},
            nyaml:decode(<<"? key\n  not_a_value_indicator">>)
        ),
        %% @ is valid in plain scalar values
        ?_assertEqual(
            {ok, #{<<"key">> => <<"@invalid">>}},
            nyaml:decode(<<"key:\n  @invalid">>)
        ),
        %% Continuation after sequence item is multiline
        ?_assertEqual(
            {ok, [<<"item not_item">>]},
            nyaml:decode(<<"- item\n  not_item">>)
        ),
        %% Nested colon in value triggers ambiguous mapping error
        ?_assertMatch(
            {error, {ambiguous_mapping_in_value, _}},
            nyaml:decode(<<"key: value: nested">>)
        ),
        %% Comment with content is properly stripped
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"key: value # comment content">>)
        ),
        %% Anchored value with flow sequence
        ?_assertMatch(
            {ok, #{<<"key">> := [1, 2]}},
            nyaml:decode(<<"key: &ref [1, 2]">>)
        ),
        %% Anchored value with flow mapping
        ?_assertMatch(
            {ok, #{<<"key">> := #{<<"a">> := 1}}},
            nyaml:decode(<<"key: &ref {a: 1}">>)
        ),
        %% Anchor followed by comment
        ?_assertMatch(
            {ok, #{<<"key">> := _}},
            nyaml:decode(<<"key: &ref # comment\n  value">>)
        ),
        %% Windows line endings (CRLF) - parses both entries
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>, <<"key2">> => <<"value2">>}},
            nyaml:decode(<<"key: value\r\nkey2: value2">>)
        ),
        %% Empty document returns null
        ?_assertEqual(
            {ok, null},
            nyaml:decode(<<"">>)
        ),
        %% Only whitespace and newlines returns null
        ?_assertEqual(
            {ok, null},
            nyaml:decode(<<"   \n\n   ">>)
        ),
        %% Anchor with newline continuation
        ?_assertMatch(
            {ok, #{<<"key">> := _}},
            nyaml:decode(<<"key: &ref\n  value">>)
        ),
        %% Anchor with CRLF
        ?_assertMatch(
            {ok, #{<<"key">> := _}},
            nyaml:decode(<<"key: &ref\r\n  value">>)
        ),
        %% Scalar value only with CRLF
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml:decode(<<"value\r\n">>)
        ),
        %% Explicit key with flow mapping value
        ?_assertMatch(
            {ok, _},
            nyaml:decode(<<"? key\n: {a: 1}">>)
        ),
        %% Tab in content (not indentation) is valid
        ?_assertEqual(
            {ok, <<"value\twith\ttabs">>},
            nyaml:decode(<<"value\twith\ttabs">>)
        )
    ].

nyaml_multiline_scalar_test_() ->
    [
        %% Multiline plain scalar
        ?_assertMatch(
            {ok, _},
            nyaml:decode(<<"first line\n  second line">>)
        ),
        %% Multiline in block mapping value
        ?_assertMatch(
            {ok, _},
            nyaml:decode(<<"key: first\n  second">>)
        ),
        %% Plain scalar with multiple continuation lines
        ?_assertMatch(
            {ok, _},
            nyaml:decode(<<"line1\n  line2\n  line3">>)
        )
    ].

nyaml_explicit_key_errors_test_() ->
    [
        %% Explicit key with invalid content
        ?_assertMatch(
            {ok, _},
            nyaml:decode(<<"? key\n: value">>)
        ),
        %% Explicit key followed by block
        ?_assertMatch(
            {ok, _},
            nyaml:decode(<<"?\n  - item\n: value">>)
        ),
        %% Multiple explicit keys
        ?_assertMatch(
            {ok, _},
            nyaml:decode(<<"? key1\n: val1\n? key2\n: val2">>)
        )
    ].

nyaml_tag_edge_cases_test_() ->
    [
        %% Local tag without space
        ?_assertMatch(
            {ok, _},
            nyaml:decode(<<"!local value">>)
        ),
        %% Global tag on scalar
        ?_assertMatch(
            {ok, _},
            nyaml:decode(<<"!!str 123">>)
        ),
        %% Tag followed by flow collection
        ?_assertMatch(
            {ok, _},
            nyaml:decode(<<"!!seq [1, 2]">>)
        ),
        %% Named tag returns error without TAG directive
        ?_assertMatch(
            {error, {undefined_tag_handle, _}},
            nyaml:decode(<<"!custom!tag value">>)
        ),
        %% Tag shorthand in flow sequence
        ?_assertEqual(
            {ok, [<<"value">>]},
            nyaml:decode(<<"[!!str value]">>)
        ),
        %% Tag with empty value at end
        ?_assertEqual(
            {ok, null},
            nyaml:decode(<<"!!null">>)
        ),
        %% Tag str with empty value
        ?_assertEqual(
            {ok, <<>>},
            nyaml:decode(<<"!!str">>)
        ),
        %% Tag followed by terminator in flow
        ?_assertEqual(
            {ok, [null]},
            nyaml:decode(<<"[!!null]">>)
        ),
        %% Tag followed by comma in flow
        ?_assertEqual(
            {ok, [null, 1]},
            nyaml:decode(<<"[!!null, 1]">>)
        )
    ].

nyaml_anchor_edge_cases_test_() ->
    [
        %% Anchor with immediate scalar value (trailing content error)
        ?_assertMatch(
            {error, {trailing_content_after_document, _}},
            nyaml:decode(<<"&ref value\nalias: *ref">>)
        ),
        %% Anchor on sequence item - works correctly
        ?_assertMatch(
            {ok, _},
            nyaml:decode(<<"- &ref item\n- *ref">>)
        ),
        %% Anchor with flow sequence (trailing content error)
        ?_assertMatch(
            {error, {trailing_content_after_document, _}},
            nyaml:decode(<<"&ref [1, 2]\nalias: *ref">>)
        ),
        %% Anchor with flow mapping returns error in this parser
        ?_assertMatch(
            {error, {expected_colon, <<>>}},
            nyaml:decode(<<"&ref {a: 1}\nalias: *ref">>)
        ),
        %% Anchor in flow sequence value
        ?_assertEqual(
            {ok, [1]},
            nyaml:decode(<<"[&ref 1]">>)
        ),
        %% Alias in flow sequence value
        ?_assertMatch(
            {ok, [1, 1]},
            nyaml:decode(<<"[&ref 1, *ref]">>)
        ),
        %% Anchor in flow mapping value
        ?_assertEqual(
            {ok, #{<<"a">> => 1}},
            nyaml:decode(<<"{a: &ref 1}">>)
        ),
        %% Alias in flow mapping value
        ?_assertMatch(
            {ok, #{<<"a">> := 1, <<"b">> := 1}},
            nyaml:decode(<<"{a: &ref 1, b: *ref}">>)
        ),
        %% Anchor with no separate value in flow (anchor name consumes all)
        ?_assertEqual(
            {ok, [null]},
            nyaml:decode(<<"[&refvalue]">>)
        )
    ].

nyaml_document_boundary_test_() ->
    [
        %% Document start with comment
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml:decode(<<"# comment\n---\nvalue">>)
        ),
        %% Document start without newline is parsed as plain scalar
        ?_assertEqual(
            {ok, <<"---value">>},
            nyaml:decode(<<"---value">>)
        ),
        %% Multiple document starts (first only)
        ?_assertEqual(
            {ok, <<"first">>},
            nyaml:decode(<<"---\nfirst\n---\nsecond">>)
        ),
        %% Document end without content
        ?_assertEqual(
            {ok, null},
            nyaml:decode(<<"...\n">>)
        )
    ].

nyaml_indentation_edge_cases_test_() ->
    [
        %% Very deep nesting
        ?_assertMatch(
            {ok, _},
            nyaml:decode(<<"a:\n  b:\n    c:\n      d: value">>)
        ),
        %% Uneven indentation in sequence
        ?_assertMatch(
            {ok, _},
            nyaml:decode(<<"- item1\n- item2\n  continuation">>)
        ),
        %% Tab at start is treated as whitespace, not indentation error
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"\tkey: value">>)
        )
    ].

nyaml_scalar_parsing_test_() ->
    [
        %% Scientific notation variations
        ?_assertEqual({ok, 1.0e10}, nyaml:decode(<<"1e10">>)),
        ?_assertEqual({ok, 1.0e10}, nyaml:decode(<<"1E10">>)),
        ?_assertEqual({ok, 1.0e-10}, nyaml:decode(<<"1e-10">>)),
        ?_assertEqual({ok, 1.0e10}, nyaml:decode(<<"1e+10">>)),

        %% Octal numbers
        ?_assertEqual({ok, 8}, nyaml:decode(<<"0o10">>)),
        ?_assertEqual({ok, 63}, nyaml:decode(<<"0o77">>)),

        %% Hex numbers
        ?_assertEqual({ok, 255}, nyaml:decode(<<"0xFF">>)),
        ?_assertEqual({ok, 255}, nyaml:decode(<<"0xff">>)),
        ?_assertEqual({ok, 16}, nyaml:decode(<<"0x10">>)),

        %% Infinity and NaN - only lowercase recognized
        ?_assertEqual({ok, infinity}, nyaml:decode(<<".inf">>)),
        ?_assertEqual({ok, <<".Inf">>}, nyaml:decode(<<".Inf">>)),
        ?_assertEqual({ok, <<".INF">>}, nyaml:decode(<<".INF">>)),
        ?_assertEqual({ok, negative_infinity}, nyaml:decode(<<"-.inf">>)),
        ?_assertEqual({ok, nan}, nyaml:decode(<<".nan">>)),
        ?_assertEqual({ok, nan}, nyaml:decode(<<".NaN">>)),
        ?_assertEqual({ok, <<".NAN">>}, nyaml:decode(<<".NAN">>))
    ].

nyaml_complex_structures_test_() ->
    [
        %% Mapping with sequence value containing mapping
        ?_assertMatch(
            {ok, #{<<"items">> := [#{<<"name">> := <<"a">>}]}},
            nyaml:decode(<<"items:\n  - name: a">>)
        ),
        %% Sequence of mappings
        ?_assertMatch(
            {ok, [#{<<"a">> := 1}, #{<<"b">> := 2}]},
            nyaml:decode(<<"- a: 1\n- b: 2">>)
        ),
        %% Mapping with nested empty collections
        ?_assertEqual(
            {ok, #{<<"empty_list">> => [], <<"empty_map">> => #{}}},
            nyaml:decode(<<"empty_list: []\nempty_map: {}">>)
        ),
        %% Flow collection with different value types
        ?_assertEqual(
            {ok, [1, <<"string">>, true, null]},
            nyaml:decode(<<"[1, string, true, null]">>)
        )
    ].

nyaml_whitespace_trimming_test_() ->
    [
        %% Trailing whitespace on lines
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"key: value   ">>)
        ),
        %% Leading whitespace before flow
        ?_assertEqual(
            {ok, [1, 2]},
            nyaml:decode(<<"   [1, 2]">>)
        ),
        %% Multiple blank lines between items
        ?_assertMatch(
            {ok, [1, 2]},
            nyaml:decode(<<"- 1\n\n\n- 2">>)
        ),
        %% Whitespace only value
        ?_assertEqual(
            {ok, #{<<"key">> => null}},
            nyaml:decode(<<"key:   ">>)
        )
    ].

nyaml_quoted_string_edge_cases_test_() ->
    [
        %% Empty single quoted string
        ?_assertEqual({ok, <<"">>}, nyaml:decode(<<"''">>)),
        %% Empty double quoted string
        ?_assertEqual({ok, <<"">>}, nyaml:decode(<<"\"\"">>)),
        %% Single quote with escaped quote
        ?_assertEqual({ok, <<"it's">>}, nyaml:decode(<<"'it''s'">>)),
        %% Double quote with various escapes
        ?_assertEqual({ok, <<"a\tb">>}, nyaml:decode(<<"\"a\\tb\"">>)),
        ?_assertEqual({ok, <<"a\nb">>}, nyaml:decode(<<"\"a\\nb\"">>)),
        ?_assertEqual({ok, <<"a\\b">>}, nyaml:decode(<<"\"a\\\\b\"">>)),
        %% Quoted string as mapping key
        ?_assertEqual(
            {ok, #{<<"key with spaces">> => <<"value">>}},
            nyaml:decode(<<"\"key with spaces\": value">>)
        ),
        %% Single quoted key
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"'key': value">>)
        )
    ].

nyaml_comment_edge_cases_test_() ->
    [
        %% Comment at end of flow value
        ?_assertEqual(
            {ok, [1, 2]},
            nyaml:decode(<<"[1, 2] # comment">>)
        ),
        %% Comment at end of mapping entry
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"key: value # comment">>)
        ),
        %% Multiple comments
        ?_assertEqual(
            {ok, #{<<"a">> => 1}},
            nyaml:decode(<<"# first comment\na: 1 # second comment">>)
        ),
        %% Comment-only lines in block
        ?_assertMatch(
            {ok, #{<<"a">> := 1, <<"b">> := 2}},
            nyaml:decode(<<"a: 1\n# comment\nb: 2">>)
        )
    ].

nyaml_flow_spanning_lines_test_() ->
    [
        %% Flow sequence spanning lines
        ?_assertEqual(
            {ok, [1, 2, 3]},
            nyaml:decode(<<"[\n  1,\n  2,\n  3\n]">>)
        ),
        %% Flow mapping spanning lines
        ?_assertEqual(
            {ok, #{<<"a">> => 1, <<"b">> => 2}},
            nyaml:decode(<<"{\n  a: 1,\n  b: 2\n}">>)
        ),
        %% Nested flow spanning lines
        ?_assertMatch(
            {ok, _},
            nyaml:decode(<<"[\n  [1, 2],\n  [3, 4]\n]">>)
        )
    ].

nyaml_block_scalar_variations_test_() ->
    [
        %% Literal block scalar
        ?_assertMatch(
            {ok, _},
            nyaml:decode(<<"|\n  line1\n  line2">>)
        ),
        %% Folded block scalar
        ?_assertMatch(
            {ok, _},
            nyaml:decode(<<">\n  line1\n  line2">>)
        ),
        %% Block scalar with explicit indicator
        ?_assertMatch(
            {ok, _},
            nyaml:decode(<<"|+\n  line">>)
        ),
        %% Block scalar with strip indicator
        ?_assertMatch(
            {ok, _},
            nyaml:decode(<<"|-\n  line">>)
        ),
        %% Block scalar in mapping
        ?_assertMatch(
            {ok, #{<<"text">> := _}},
            nyaml:decode(<<"text: |\n  multiline\n  content">>)
        )
    ].

%% ============================================================
%% Coverage Round 4 - Deep Parser Edge Cases
%% ============================================================

nyaml_parser_dispatch_test_() ->
    [
        %% Anchor in mapping key context
        ?_assertMatch(
            {ok, _},
            nyaml:decode(<<"&anchor key: value">>)
        ),
        %% Tag on empty value
        ?_assertEqual(
            {ok, null},
            nyaml:decode(<<"!!null">>)
        ),
        %% Tag !!str on empty value
        ?_assertEqual(
            {ok, <<>>},
            nyaml:decode(<<"!!str">>)
        ),
        %% Flow sequence as mapping key
        ?_assertMatch(
            {ok, _},
            nyaml:decode(<<"[1, 2]: value">>)
        ),
        %% Flow mapping as mapping key
        ?_assertMatch(
            {ok, _},
            nyaml:decode(<<"{a: 1}: value">>)
        ),
        %% Double-quoted mapping key in block
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"\"key\": value">>)
        ),
        %% Single-quoted mapping key in block
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"'key': value">>)
        ),
        %% Comment at start of document
        ?_assertEqual(
            {ok, 42},
            nyaml:decode(<<"# comment\n42">>)
        ),
        %% Multiple comment lines
        ?_assertEqual(
            {ok, 42},
            nyaml:decode(<<"# comment 1\n# comment 2\n42">>)
        ),
        %% Verbatim tag
        ?_assertMatch(
            {ok, _},
            nyaml:decode(<<"!<tag:example.com,2000:custom> value">>)
        )
    ].

nyaml_flow_mixed_collections_test_() ->
    [
        %% Nested flow sequences
        ?_assertEqual(
            {ok, [[1, 2], [3, 4]]},
            nyaml:decode(<<"[[1, 2], [3, 4]]">>)
        ),
        %% Nested flow mappings
        ?_assertMatch(
            {ok, #{<<"outer">> := #{<<"inner">> := 1}}},
            nyaml:decode(<<"{outer: {inner: 1}}">>)
        ),
        %% Flow mapping in flow sequence
        ?_assertEqual(
            {ok, [#{<<"a">> => 1}, #{<<"b">> => 2}]},
            nyaml:decode(<<"[{a: 1}, {b: 2}]">>)
        ),
        %% Flow sequence in flow mapping
        ?_assertEqual(
            {ok, #{<<"items">> => [1, 2, 3]}},
            nyaml:decode(<<"{items: [1, 2, 3]}">>)
        ),
        %% Explicit key in flow mapping
        ?_assertMatch(
            {ok, _},
            nyaml:decode(<<"{? key: value}">>)
        ),
        %% Anchor in flow value
        ?_assertMatch(
            {ok, _},
            nyaml:decode(<<"[&ref 1, *ref]">>)
        ),
        %% Tag in flow value
        ?_assertEqual(
            {ok, [<<"test">>]},
            nyaml:decode(<<"[!!str test]">>)
        ),
        %% Flow with trailing newlines
        ?_assertEqual(
            {ok, [1, 2]},
            nyaml:decode(<<"[1, 2]\n\n">>)
        )
    ].

nyaml_block_mixed_collections_test_() ->
    [
        %% Nested block sequences
        ?_assertMatch(
            {ok, [[1, 2]]},
            nyaml:decode(<<"-\n  - 1\n  - 2">>)
        ),
        %% Block mapping with nested sequence
        ?_assertEqual(
            {ok, #{<<"items">> => [1, 2]}},
            nyaml:decode(<<"items:\n  - 1\n  - 2">>)
        ),
        %% Block sequence of mappings
        ?_assertMatch(
            {ok, [#{<<"name">> := <<"a">>}, #{<<"name">> := <<"b">>}]},
            nyaml:decode(<<"- name: a\n- name: b">>)
        ),
        %% Deeply nested block structure
        ?_assertMatch(
            {ok, _},
            nyaml:decode(<<"a:\n  b:\n    c:\n      d:\n        e: value">>)
        ),
        %% Block mapping with empty value
        ?_assertEqual(
            {ok, #{<<"key">> => null}},
            nyaml:decode(<<"key:">>)
        ),
        %% Block sequence with empty item
        ?_assertMatch(
            {ok, [null, <<"value">>]},
            nyaml:decode(<<"-\n- value">>)
        ),
        %% Block with flow value
        ?_assertEqual(
            {ok, #{<<"key">> => [1, 2]}},
            nyaml:decode(<<"key: [1, 2]">>)
        ),
        %% Block with quoted value
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value with spaces">>}},
            nyaml:decode(<<"key: \"value with spaces\"">>)
        )
    ].

nyaml_scalar_context_test_() ->
    [
        %% Multi-line plain scalar in block
        ?_assertMatch(
            {ok, _},
            nyaml:decode(<<"line1\nline2">>)
        ),
        %% Plain scalar with continuation
        ?_assertMatch(
            {ok, _},
            nyaml:decode(<<"first\n  second\n  third">>)
        ),
        %% Plain scalar in mapping value
        ?_assertMatch(
            {ok, _},
            nyaml:decode(<<"key: multi\n  line\n  value">>)
        ),
        %% Quoted scalar in mapping
        ?_assertEqual(
            {ok, #{<<"key">> => <<"quoted value">>}},
            nyaml:decode(<<"key: 'quoted value'">>)
        ),
        %% Scalar with special characters
        ?_assertEqual(
            {ok, <<"a:b:c">>},
            nyaml:decode(<<"a:b:c">>)
        ),
        %% Scalar starting with number
        ?_assertEqual(
            {ok, <<"123abc">>},
            nyaml:decode(<<"123abc">>)
        )
    ].

nyaml_yaml_tag_directive_test_() ->
    [
        %% YAML directive
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml:decode(<<"%YAML 1.2\n---\nvalue">>)
        ),
        %% TAG directive
        ?_assertMatch(
            {ok, _},
            nyaml:decode(<<"%TAG !e! tag:example.com,2000:\n---\nvalue">>)
        ),
        %% Multiple directives
        ?_assertMatch(
            {ok, _},
            nyaml:decode(<<"%YAML 1.2\n%TAG !e! tag:example.com,2000:\n---\nvalue">>)
        ),
        %% Document start marker
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml:decode(<<"---\nvalue">>)
        ),
        %% Document end marker
        ?_assertEqual(
            {ok, <<"value">>},
            nyaml:decode(<<"value\n...">>)
        ),
        %% Empty document with markers
        ?_assertEqual(
            {ok, null},
            nyaml:decode(<<"---\n...">>)
        )
    ].

nyaml_primitive_types_test_() ->
    [
        %% Different null representations
        ?_assertEqual({ok, null}, nyaml:decode(<<"null">>)),
        ?_assertEqual({ok, null}, nyaml:decode(<<>>)),
        ?_assertEqual({ok, null}, nyaml:decode(<<"---">>)),

        %% Boolean values
        ?_assertEqual({ok, true}, nyaml:decode(<<"true">>)),
        ?_assertEqual({ok, false}, nyaml:decode(<<"false">>)),

        %% Integer formats
        ?_assertEqual({ok, 42}, nyaml:decode(<<"42">>)),
        ?_assertEqual({ok, -42}, nyaml:decode(<<"-42">>)),
        ?_assertEqual({ok, 0}, nyaml:decode(<<"0">>)),

        %% Float formats
        ?_assertEqual({ok, 3.14}, nyaml:decode(<<"3.14">>)),
        ?_assertEqual({ok, -3.14}, nyaml:decode(<<"-3.14">>)),
        ?_assertEqual({ok, 1.0e5}, nyaml:decode(<<"1e5">>))
    ].

nyaml_anchor_reuse_patterns_test_() ->
    [
        %% Basic anchor and alias
        ?_assertEqual(
            {ok, #{<<"original">> => [1, 2, 3], <<"copy">> => [1, 2, 3]}},
            nyaml:decode(<<"original: &ref [1, 2, 3]\ncopy: *ref">>)
        ),
        %% Anchor on scalar
        ?_assertMatch(
            {ok, _},
            nyaml:decode(<<"a: &val 42\nb: *val">>)
        ),
        %% Anchor on block sequence
        ?_assertMatch(
            {ok, _},
            nyaml:decode(<<"a: &items\n  - 1\n  - 2\nb: *items">>)
        ),
        %% Anchor on block mapping
        ?_assertMatch(
            {ok, _},
            nyaml:decode(<<"a: &map\n  key: value\nb: *map">>)
        ),
        %% Multiple anchors
        ?_assertMatch(
            {ok, _},
            nyaml:decode(<<"a: &ref1 1\nb: &ref2 2\nc: *ref1\nd: *ref2">>)
        ),
        %% Anchor in sequence item
        ?_assertMatch(
            {ok, _},
            nyaml:decode(<<"- &a 1\n- &b 2\n- *a\n- *b">>)
        )
    ].

nyaml_type_conversion_test_() ->
    [
        %% Tag !!str converts to string
        ?_assertEqual(
            {ok, <<"42">>},
            nyaml:decode(<<"!!str 42">>)
        ),
        %% Tag !!int converts to integer
        ?_assertEqual(
            {ok, 42},
            nyaml:decode(<<"!!int 42">>)
        ),
        %% Tag !!float converts to float
        ?_assertEqual(
            {ok, 3.14},
            nyaml:decode(<<"!!float 3.14">>)
        ),
        %% Tag !!bool converts to boolean
        ?_assertEqual(
            {ok, true},
            nyaml:decode(<<"!!bool true">>)
        ),
        %% Tag !!null gives null
        ?_assertEqual(
            {ok, null},
            nyaml:decode(<<"!!null ~">>)
        ),
        %% Local tag (ignored)
        ?_assertMatch(
            {ok, _},
            nyaml:decode(<<"!custom value">>)
        )
    ].

nyaml_parse_error_test_() ->
    [
        %% Undefined alias
        ?_assertMatch(
            {error, {undefined_alias, _}},
            nyaml:decode(<<"*undefined">>)
        ),
        %% Unterminated flow sequence
        ?_assertEqual(
            {error, unterminated_sequence},
            nyaml:decode(<<"[1, 2">>)
        ),
        %% Unterminated flow mapping
        ?_assertEqual(
            {error, unterminated_mapping},
            nyaml:decode(<<"{a: 1">>)
        ),
        %% Unterminated double-quoted string
        ?_assertEqual(
            {error, unterminated_double_quoted_string},
            nyaml:decode(<<"\"unclosed">>)
        ),
        %% Unterminated single-quoted string
        ?_assertEqual(
            {error, unterminated_single_quoted_string},
            nyaml:decode(<<"'unclosed">>)
        ),
        %% Invalid escape sequence
        ?_assertMatch(
            {error, {invalid_escape_sequence, _}},
            nyaml:decode(<<"\"invalid \\q escape\"">>)
        ),
        %% Empty anchor name
        ?_assertMatch(
            {error, {invalid_anchor_name, _}},
            nyaml:decode(<<"& value">>)
        ),
        %% Empty alias name - returns invalid_anchor_name for empty name
        ?_assertMatch(
            {error, {invalid_anchor_name, _}},
            nyaml:decode(<<"* ">>)
        )
    ].

nyaml_multi_document_test_() ->
    [
        %% Multiple documents
        ?_assertEqual(
            {ok, [<<"doc1">>, <<"doc2">>]},
            nyaml:decode_all(<<"doc1\n---\ndoc2">>)
        ),
        %% Single document
        ?_assertEqual(
            {ok, [<<"value">>]},
            nyaml:decode_all(<<"value">>)
        ),
        %% Empty input
        ?_assertEqual(
            {ok, []},
            nyaml:decode_all(<<>>)
        ),
        %% Document with end marker
        ?_assertEqual(
            {ok, [<<"value">>]},
            nyaml:decode_all(<<"value\n...">>)
        )
    ].

%% ============================================================
%% Coverage Round 5 - Deep Block Edge Cases
%% ============================================================

nyaml_anchor_crlf_test_() ->
    [
        %% Anchor followed by CRLF then value on next line
        ?_assertMatch(
            {ok, #{<<"key">> := <<"value">>}},
            nyaml:decode(<<"key: &ref\r\n  value\ncopy: *ref">>)
        ),
        %% Anchor with CRLF in sequence
        ?_assertMatch(
            {ok, [<<"item">>]},
            nyaml:decode(<<"- &ref\r\n  item">>)
        )
    ].

nyaml_anchor_comment_test_() ->
    [
        %% Anchor followed by comment then value on next line
        ?_assertMatch(
            {ok, #{<<"key">> := <<"value">>}},
            nyaml:decode(<<"key: &ref # comment\n  value\ncopy: *ref">>)
        ),
        %% Anchor with comment in sequence
        ?_assertMatch(
            {ok, [<<"item">>]},
            nyaml:decode(<<"- &ref # anchor comment\n  item">>)
        )
    ].

nyaml_plain_scalar_comment_error_test_() ->
    [
        %% Plain scalar with comment followed by continuation should error
        ?_assertEqual(
            {error, plain_scalar_continuation_after_comment},
            nyaml:decode(<<"key: value\n  # comment in middle\n  continuation">>)
        )
    ].

nyaml_anchor_on_block_indicator_test_() ->
    [
        %% Anchor followed by inline sequence is valid
        ?_assertEqual(
            {ok, #{<<"key">> => [<<"item">>]}},
            nyaml:decode(<<"key: &ref - item">>)
        ),
        %% Anchor followed by just dash is parsed as scalar
        ?_assertEqual(
            {ok, #{<<"key">> => <<"-">>}},
            nyaml:decode(<<"key: &ref -">>)
        )
    ].

%% ============================================================
%% Coverage Round 6 - Explicit Key and Flow Edge Cases
%% ============================================================

nyaml_quoted_compact_mapping_in_sequence_test_() ->
    [
        %% Single-quoted compact mapping in a nested sequence item
        ?_assertEqual(
            {ok, #{<<"implicit block key">> => [#{<<"implicit flow key">> => <<"value">>}]}},
            nyaml:decode(<<"'implicit block key':\n- 'implicit flow key': value\n">>)
        ),
        %% Double-quoted compact mapping in a nested sequence item
        ?_assertEqual(
            {ok, #{<<"implicit block key">> => [#{<<"implicit flow key">> => <<"value">>}]}},
            nyaml:decode(<<"\"implicit block key\":\n- \"implicit flow key\": value\n">>)
        ),
        %% Compact mapping in a nested sequence item with same-item continuation
        ?_assertEqual(
            {ok, #{
                <<"implicit block key">> => [
                    #{
                        <<"implicit flow key">> => <<"value">>,
                        <<"other">> => <<"entry">>
                    }
                ]
            }},
            nyaml:decode(
                <<"\"implicit block key\":\n- \"implicit flow key\": value\n  other: entry\n">>
            )
        )
    ].

nyaml_explicit_key_structures_test_() ->
    [
        %% Explicit key with sequence as key value
        ?_assertEqual(
            {ok, #{[<<"item">>] => <<"value">>}},
            nyaml:decode(<<"?\n  - item\n: value">>)
        ),
        %% Explicit key with mapping as key value
        ?_assertEqual(
            {ok, #{#{<<"a">> => 1} => <<"value">>}},
            nyaml:decode(<<"?\n  a: 1\n: value">>)
        ),
        %% Explicit key with only comment becomes null
        ?_assertEqual(
            {ok, #{null => <<"value">>}},
            nyaml:decode(<<"?\n  # comment\n: value">>)
        ),
        %% Multiple explicit keys
        ?_assertMatch(
            {ok, #{null := _, <<"key">> := _}},
            nyaml:decode(<<"? key\n: value1\n?\n: value2">>)
        )
    ].

nyaml_nested_flow_with_anchors_test_() ->
    [
        %% Nested flow sequences with anchors (anchor on 1, alias resolves to 1)
        ?_assertMatch(
            {ok, [[1], 1]},
            nyaml:decode(<<"[[&ref 1], *ref]">>)
        ),
        %% Nested flow mappings with anchors
        ?_assertMatch(
            {ok, #{<<"outer">> := #{<<"inner">> := 1}}},
            nyaml:decode(<<"{outer: {inner: &ref 1}}">>)
        ),
        %% Flow mapping with anchored nested mapping
        ?_assertMatch(
            {ok, #{<<"a">> := #{<<"x">> := 1}, <<"b">> := #{<<"x">> := 1}}},
            nyaml:decode(<<"{a: &ref {x: 1}, b: *ref}">>)
        ),
        %% Flow sequence with anchored nested sequence
        ?_assertMatch(
            {ok, [[1, 2], [1, 2]]},
            nyaml:decode(<<"[&ref [1, 2], *ref]">>)
        )
    ].

nyaml_multiline_flow_edge_cases_test_() ->
    [
        %% Flow mapping with value on next line
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value">>}},
            nyaml:decode(<<"{\n  key:\n    value\n}">>)
        ),
        %% Flow sequence with items on separate lines
        ?_assertEqual(
            {ok, [1, 2, 3]},
            nyaml:decode(<<"[\n1\n,\n2\n,\n3\n]">>)
        ),
        %% Deep nesting in flow
        ?_assertMatch(
            {ok, #{<<"a">> := #{<<"b">> := #{<<"c">> := 1}}}},
            nyaml:decode(<<"{a: {b: {c: 1}}}">>)
        )
    ].

nyaml_scalar_boundary_cases_test_() ->
    [
        %% Plain scalar ending with colon (not key)
        ?_assertEqual(
            {ok, <<"http://example.com">>},
            nyaml:decode(<<"http://example.com">>)
        ),
        %% Plain scalar with embedded hash (not comment)
        ?_assertEqual(
            {ok, #{<<"key">> => <<"value#notcomment">>}},
            nyaml:decode(<<"key: value#notcomment">>)
        ),
        %% Plain scalar with multiple colons
        ?_assertEqual(
            {ok, #{<<"key">> => <<"a:b:c">>}},
            nyaml:decode(<<"key: a:b:c">>)
        )
    ].

%% ============================================================
%% nyaml_emit_scalar Module Tests
%% ============================================================

nyaml_emit_scalar_atoms_test_() ->
    [
        ?_assertEqual(<<"null">>, nyaml_emit_scalar:emit(null)),
        ?_assertEqual(<<"true">>, nyaml_emit_scalar:emit(true)),
        ?_assertEqual(<<"false">>, nyaml_emit_scalar:emit(false)),
        ?_assertEqual(<<".inf">>, nyaml_emit_scalar:emit(infinity)),
        ?_assertEqual(<<"-.inf">>, nyaml_emit_scalar:emit(negative_infinity)),
        ?_assertEqual(<<".nan">>, nyaml_emit_scalar:emit(nan))
    ].

nyaml_emit_scalar_numbers_test_() ->
    [
        ?_assertEqual(<<"0">>, nyaml_emit_scalar:emit(0)),
        ?_assertEqual(<<"42">>, nyaml_emit_scalar:emit(42)),
        ?_assertEqual(<<"-7">>, nyaml_emit_scalar:emit(-7)),
        ?_assertEqual(<<"0.0">>, nyaml_emit_scalar:emit(0.0)),
        ?_assertEqual(<<"3.14">>, nyaml_emit_scalar:emit(3.14)),
        ?_assertEqual(<<"-2.5">>, nyaml_emit_scalar:emit(-2.5))
    ].

nyaml_emit_scalar_datetime_test_() ->
    [
        ?_assertEqual(
            <<"2024-01-15T10:30:00">>,
            nyaml_emit_scalar:emit({{2024, 1, 15}, {10, 30, 0}})
        ),
        ?_assertEqual(
            <<"0001-01-01T00:00:00">>,
            nyaml_emit_scalar:emit({{1, 1, 1}, {0, 0, 0}})
        )
    ].

nyaml_emit_scalar_plain_string_test_() ->
    [
        ?_assertEqual(<<"hello">>, nyaml_emit_scalar:emit(<<"hello">>)),
        ?_assertEqual(<<"hello world">>, nyaml_emit_scalar:emit(<<"hello world">>)),
        ?_assertEqual(<<"don't">>, nyaml_emit_scalar:emit(<<"don't">>)),
        ?_assertEqual(<<"foo:bar">>, nyaml_emit_scalar:emit(<<"foo:bar">>)),
        ?_assertEqual(<<"foo#bar">>, nyaml_emit_scalar:emit(<<"foo#bar">>)),
        ?_assertEqual(<<"-foo">>, nyaml_emit_scalar:emit(<<"-foo">>)),
        ?_assertEqual(<<"http://example.com">>, nyaml_emit_scalar:emit(<<"http://example.com">>))
    ].

nyaml_emit_scalar_quoted_string_test_() ->
    [
        ?_assertEqual(<<"''">>, nyaml_emit_scalar:emit(<<"">>)),
        ?_assertEqual(<<"'true'">>, nyaml_emit_scalar:emit(<<"true">>)),
        ?_assertEqual(<<"'null'">>, nyaml_emit_scalar:emit(<<"null">>)),
        ?_assertEqual(<<"'~'">>, nyaml_emit_scalar:emit(<<"~">>)),
        ?_assertEqual(<<"'123'">>, nyaml_emit_scalar:emit(<<"123">>)),
        ?_assertEqual(<<"'1.5'">>, nyaml_emit_scalar:emit(<<"1.5">>)),
        ?_assertEqual(<<"'0xFF'">>, nyaml_emit_scalar:emit(<<"0xFF">>)),
        ?_assertEqual(<<"'.inf'">>, nyaml_emit_scalar:emit(<<".inf">>)),
        ?_assertEqual(<<"'#hash'">>, nyaml_emit_scalar:emit(<<"#hash">>)),
        ?_assertEqual(<<"'!bang'">>, nyaml_emit_scalar:emit(<<"!bang">>)),
        ?_assertEqual(<<"'a: b'">>, nyaml_emit_scalar:emit(<<"a: b">>)),
        ?_assertEqual(<<"'a #b'">>, nyaml_emit_scalar:emit(<<"a #b">>)),
        ?_assertEqual(<<"' foo'">>, nyaml_emit_scalar:emit(<<" foo">>)),
        ?_assertEqual(<<"'foo '">>, nyaml_emit_scalar:emit(<<"foo ">>)),
        ?_assertEqual(<<"'ends:'">>, nyaml_emit_scalar:emit(<<"ends:">>))
    ].

nyaml_emit_scalar_double_quoted_test_() ->
    [
        ?_assertEqual(<<"\"a\\nb\"">>, nyaml_emit_scalar:emit(<<"a\nb">>)),
        ?_assertEqual(<<"\"a\\rb\"">>, nyaml_emit_scalar:emit(<<"a\rb">>))
    ].

nyaml_emit_scalar_apostrophe_uses_double_test_() ->
    %% Strings with apostrophes that also contain newlines must use double quotes.
    [
        ?_assertEqual(
            <<"\"don't\\nstop\"">>,
            nyaml_emit_scalar:emit(<<"don't\nstop">>)
        )
    ].

nyaml_emit_scalar_flow_context_test_() ->
    [
        ?_assertEqual(
            <<"'a, b'">>,
            nyaml_emit_scalar:emit_binary(<<"a, b">>, flow)
        ),
        ?_assertEqual(
            <<"'[bracket]'">>,
            nyaml_emit_scalar:emit_binary(<<"[bracket]">>, flow)
        ),
        %% Same string is plain in block context
        ?_assertEqual(
            <<"a, b">>,
            nyaml_emit_scalar:emit_binary(<<"a, b">>, block)
        )
    ].

nyaml_emit_scalar_needs_quoting_test_() ->
    [
        ?_assertEqual(false, nyaml_emit_scalar:needs_quoting(<<"hello">>)),
        ?_assertEqual(true, nyaml_emit_scalar:needs_quoting(<<"">>)),
        ?_assertEqual(true, nyaml_emit_scalar:needs_quoting(<<"true">>)),
        ?_assertEqual(true, nyaml_emit_scalar:needs_quoting(<<"123">>)),
        ?_assertEqual(true, nyaml_emit_scalar:needs_quoting(<<"#foo">>)),
        ?_assertEqual(true, nyaml_emit_scalar:needs_quoting(<<" foo">>)),
        ?_assertEqual(true, nyaml_emit_scalar:needs_quoting(<<"foo ">>)),
        ?_assertEqual(true, nyaml_emit_scalar:needs_quoting(<<"foo: bar">>)),
        ?_assertEqual(true, nyaml_emit_scalar:needs_quoting(<<"foo\nbar">>))
    ].

%% ============================================================
%% nyaml:encode/1 (public API) Tests
%% ============================================================

nyaml_encode_returns_binary_test_() ->
    [
        ?_assertMatch({ok, <<_/binary>>}, nyaml:encode(null)),
        ?_assertMatch({ok, <<_/binary>>}, nyaml:encode([1, 2, 3])),
        ?_assertMatch({ok, <<_/binary>>}, nyaml:encode(#{<<"a">> => 1}))
    ].

nyaml_encode_trailing_newline_test_() ->
    [
        ?_assertEqual({ok, <<"42\n">>}, nyaml:encode(42)),
        ?_assertEqual({ok, <<"[]\n">>}, nyaml:encode([])),
        ?_assertEqual({ok, <<"a: 1\n">>}, nyaml:encode(#{<<"a">> => 1}))
    ].

nyaml_encode_decode_roundtrip_test_() ->
    Values = [
        null,
        true,
        false,
        infinity,
        negative_infinity,
        nan,
        42,
        -7,
        3.14,
        {{2024, 1, 15}, {10, 30, 0}},
        <<"hello">>,
        <<"with: colon">>,
        <<"with\nnewline">>,
        [],
        #{},
        [1, 2, 3],
        #{<<"name">> => <<"alice">>, <<"age">> => 30},
        #{<<"server">> => #{<<"host">> => <<"localhost">>, <<"port">> => 8080}},
        #{<<"items">> => [1, 2, 3]},
        [#{<<"a">> => 1}, #{<<"b">> => 2}],
        #{<<"a">> => #{<<"b">> => #{<<"c">> => [1, 2, #{<<"d">> => true}]}}}
    ],
    [
        {
            iolist_to_binary(io_lib:format("~p", [V])),
            ?_assertEqual(
                {ok, V},
                begin
                    {ok, Bin} = nyaml:encode(V),
                    nyaml:decode(Bin)
                end
            )
        }
     || V <- Values
    ].

%% ============================================================
%% nyaml_emit Module Tests
%% ============================================================

nyaml_emit_top_level_scalar_test_() ->
    [
        ?_assertEqual(<<"null\n">>, iolist_to_binary(nyaml_emit:emit(null))),
        ?_assertEqual(<<"true\n">>, iolist_to_binary(nyaml_emit:emit(true))),
        ?_assertEqual(<<"42\n">>, iolist_to_binary(nyaml_emit:emit(42))),
        ?_assertEqual(<<"3.14\n">>, iolist_to_binary(nyaml_emit:emit(3.14))),
        ?_assertEqual(<<"hello\n">>, iolist_to_binary(nyaml_emit:emit(<<"hello">>))),
        ?_assertEqual(<<"''\n">>, iolist_to_binary(nyaml_emit:emit(<<"">>)))
    ].

nyaml_emit_empty_container_test_() ->
    [
        ?_assertEqual(<<"[]\n">>, iolist_to_binary(nyaml_emit:emit([]))),
        ?_assertEqual(<<"{}\n">>, iolist_to_binary(nyaml_emit:emit(#{})))
    ].

nyaml_emit_block_sequence_test_() ->
    [
        ?_assertEqual(
            <<"- 1\n- 2\n- 3\n">>,
            iolist_to_binary(nyaml_emit:emit([1, 2, 3]))
        ),
        ?_assertEqual(
            <<"- 'true'\n- true\n">>,
            iolist_to_binary(nyaml_emit:emit([<<"true">>, true]))
        ),
        ?_assertEqual(
            <<"- []\n- {}\n">>,
            iolist_to_binary(nyaml_emit:emit([[], #{}]))
        )
    ].

nyaml_emit_block_mapping_test_() ->
    [
        ?_assertEqual(
            <<"a: 1\n">>,
            iolist_to_binary(nyaml_emit:emit(#{<<"a">> => 1}))
        ),
        ?_assertEqual(
            <<"a: hello\n">>,
            iolist_to_binary(nyaml_emit:emit(#{<<"a">> => <<"hello">>}))
        ),
        ?_assertEqual(
            <<"a: []\n">>,
            iolist_to_binary(nyaml_emit:emit(#{<<"a">> => []}))
        ),
        ?_assertEqual(
            <<"a: {}\n">>,
            iolist_to_binary(nyaml_emit:emit(#{<<"a">> => #{}}))
        ),
        %% Quoted key
        ?_assertEqual(
            <<"'true': 1\n">>,
            iolist_to_binary(nyaml_emit:emit(#{<<"true">> => 1}))
        )
    ].

nyaml_emit_nested_map_in_map_test_() ->
    [
        ?_assertEqual(
            <<"a:\n  b: 1\n">>,
            iolist_to_binary(nyaml_emit:emit(#{<<"a">> => #{<<"b">> => 1}}))
        )
    ].

nyaml_emit_sequence_in_map_test_() ->
    [
        ?_assertEqual(
            <<"a:\n  - 1\n  - 2\n">>,
            iolist_to_binary(nyaml_emit:emit(#{<<"a">> => [1, 2]}))
        )
    ].

nyaml_emit_map_in_sequence_compact_test_() ->
    [
        ?_assertEqual(
            <<"- a: 1\n">>,
            iolist_to_binary(nyaml_emit:emit([#{<<"a">> => 1}]))
        ),
        ?_assertEqual(
            <<"- a:\n    - 1\n    - 2\n">>,
            iolist_to_binary(nyaml_emit:emit([#{<<"a">> => [1, 2]}]))
        )
    ].

nyaml_emit_sequence_in_sequence_verbose_test_() ->
    [
        ?_assertEqual(
            <<"- 1\n-\n  - 2\n  - 3\n">>,
            iolist_to_binary(nyaml_emit:emit([1, [2, 3]]))
        )
    ].

nyaml_emit_roundtrip_test_() ->
    Values = [
        null,
        true,
        false,
        infinity,
        negative_infinity,
        nan,
        0,
        42,
        -7,
        3.14,
        -2.5,
        1.0e20,
        {{2024, 1, 15}, {10, 30, 0}},
        <<"hello">>,
        <<"hello world">>,
        <<"">>,
        <<"true">>,
        <<"123">>,
        <<"#hash">>,
        <<"a: b">>,
        <<"with\nnewline">>,
        [],
        #{},
        [1, 2, 3],
        [<<"a">>, <<"b">>, <<"c">>],
        [true, false, null],
        [1, 2.5, <<"three">>, true, null],
        #{<<"a">> => 1},
        #{<<"name">> => <<"alice">>, <<"age">> => 30},
        #{<<"server">> => #{<<"host">> => <<"localhost">>, <<"port">> => 8080}},
        #{<<"items">> => [1, 2, 3]},
        #{<<"items">> => []},
        [#{<<"a">> => 1}, #{<<"b">> => 2}],
        [#{<<"name">> => <<"x">>, <<"value">> => 1}],
        [[1, 2], [3, 4]],
        [1, [2, 3], 4],
        #{<<"empty_list">> => [], <<"empty_map">> => #{}},
        #{<<"a">> => #{<<"b">> => #{<<"c">> => [1, 2, #{<<"d">> => true}]}}},
        #{<<"true">> => <<"false">>, <<"null">> => <<"~">>},
        #{<<"a: b">> => <<"c: d">>},
        [
            #{<<"name">> => <<"alpha">>, <<"tags">> => [<<"x">>, <<"y">>]},
            #{<<"name">> => <<"beta">>, <<"tags">> => []}
        ]
    ],
    [
        {
            iolist_to_binary(io_lib:format("~p", [V])),
            ?_assertEqual(
                {ok, V},
                nyaml:decode(iolist_to_binary(nyaml_emit:emit(V)))
            )
        }
     || V <- Values
    ].

nyaml_emit_scalar_roundtrip_test_() ->
    Values = [
        null,
        true,
        false,
        infinity,
        negative_infinity,
        nan,
        0,
        42,
        -7,
        1000000,
        0.0,
        3.14,
        -2.5,
        1.0e20,
        {{2024, 1, 15}, {10, 30, 0}},
        {{1999, 12, 31}, {23, 59, 59}},
        <<"hello">>,
        <<"hello world">>,
        <<"don't">>,
        <<"foo:bar">>,
        <<"foo#bar">>,
        <<"-foo">>,
        <<"http://example.com">>,
        <<"">>,
        <<"true">>,
        <<"null">>,
        <<"~">>,
        <<"123">>,
        <<"3.14">>,
        <<"0xFF">>,
        <<".inf">>,
        <<"#starts">>,
        <<"!bang">>,
        <<"&anchor">>,
        <<"*alias">>,
        <<"|literal">>,
        <<">folded">>,
        <<"%directive">>,
        <<"@reserved">>,
        <<"`reserved">>,
        <<"a: b">>,
        <<"a #b">>,
        <<" leading">>,
        <<"trailing ">>,
        <<"ends:">>,
        <<"with\nnewline">>,
        <<"with\ttab">>,
        <<"with\"quote">>,
        <<"with\\backslash">>,
        <<"with'apos">>
    ],
    [
        {
            iolist_to_binary(io_lib:format("~p", [V])),
            ?_assertEqual({ok, V}, nyaml:decode(nyaml_emit_scalar:emit(V)))
        }
     || V <- Values
    ].

%% ============================================================
%% The `schema' Option Tests
%% ============================================================
%% "Tag Resolution" asks a processor for a mechanism that lets the application
%% override and expand the default rules, and "Core Schema" calls the core
%% schema the default "unless instructed otherwise". `core' and `extended' are
%% the two values that this release resolves.
nyaml_schema_option_test_() ->
    [
        ?_assertEqual(
            nyaml:decode(<<"a: 1">>),
            nyaml:decode(<<"a: 1">>, #{schema => core})
        ),
        ?_assertEqual(
            {ok, #{<<"a">> => 1}},
            nyaml:decode(<<"a: 1">>, #{schema => core})
        ),
        ?_assertEqual(
            {ok, #{<<"a">> => 1}},
            nyaml:decode(<<"a: 1">>, #{})
        ),
        ?_assertEqual(
            {error, {unknown_schema, json}},
            nyaml:decode(<<"a: 1">>, #{schema => json})
        ),
        ?_assertEqual(
            {ok, #{<<"a">> => 1}},
            nyaml:decode(<<"a: 1">>, #{schema => extended})
        ),
        ?_assertEqual(
            {error, {unknown_schema, <<"core">>}},
            nyaml:decode(<<"a: 1">>, #{schema => <<"core">>})
        ),
        ?_assertEqual(
            {error, {unknown_schema, json}},
            nyaml:decode(<<"]">>, #{schema => json})
        )
    ].

nyaml_schema_option_decode_all_test_() ->
    [
        ?_assertEqual(
            {ok, [1, 2]},
            nyaml:decode_all(<<"--- 1\n--- 2\n">>, #{schema => core})
        ),
        ?_assertEqual(
            {error, {unknown_schema, json}},
            nyaml:decode_all(<<"a: 1">>, #{schema => json})
        ),
        ?_assertEqual(
            {ok, [#{<<"a">> => 1}]},
            nyaml:decode_all(<<"a: 1">>, #{schema => extended})
        )
    ].

%% The schema is stream scoped and an anchor is document scoped, so the context
%% reset at a document boundary keeps the schema. A tag in the second document
%% resolves under it.
nyaml_schema_survives_document_boundary_test_() ->
    [
        ?_assertEqual(
            {ok, [<<"1">>, <<"2">>]},
            nyaml:decode_all(<<"--- !!str 1\n--- !!str 2\n">>, #{schema => core})
        ),
        ?_assertEqual(
            {ok, [<<"1">>, <<"2">>]},
            nyaml:decode_all(<<"--- !!str 1\n...\n--- !!str 2\n">>, #{schema => core})
        )
    ].

%% ============================================================
%% Merge Key Tests, extended schema
%% ============================================================

%% The `merge` entry of the YAML 1.1 type repository inserts every key of the
%% mapping that `<<` names, unless the enclosing mapping already holds the key.
nyaml_extended_merge_key_test_() ->
    Extended = #{schema => extended},
    Document = <<
        "defaults: &defaults\n"
        "  timeout: 30\n"
        "  retries: 3\n"
        "production:\n"
        "  <<: *defaults\n"
        "  timeout: 60\n"
    >>,
    Defaults = #{<<"timeout">> => 30, <<"retries">> => 3},
    [
        ?_assertEqual(
            {ok, #{
                <<"defaults">> => Defaults,
                <<"production">> => #{<<"timeout">> => 60, <<"retries">> => 3}
            }},
            nyaml:decode(Document, Extended)
        ),
        ?_assertEqual(
            {ok, #{
                <<"defaults">> => Defaults,
                <<"production">> => #{<<"<<">> => Defaults, <<"timeout">> => 60}
            }},
            nyaml:decode(Document, #{schema => core})
        ),
        ?_assertEqual(
            {ok, #{<<"a">> => #{<<"x">> => 1}, <<"b">> => #{<<"x">> => 1}}},
            nyaml:decode(<<"a: &a\n  x: 1\nb:\n  <<: *a\n">>, Extended)
        )
    ].

%% "each of these nodes is merged in turn according to its order in the
%% sequence. Keys in mapping nodes earlier in the sequence override keys
%% specified in later mapping nodes."
nyaml_extended_merge_sequence_test_() ->
    Extended = #{schema => extended},
    [
        ?_assertEqual(
            {ok, #{
                <<"a">> => #{<<"x">> => 1},
                <<"b">> => #{<<"x">> => 2, <<"y">> => 3},
                <<"c">> => #{<<"x">> => 1, <<"y">> => 3}
            }},
            nyaml:decode(
                <<"a: &a {x: 1}\nb: &b {x: 2, y: 3}\nc:\n  <<: [*a, *b]\n">>, Extended
            )
        ),
        ?_assertEqual(
            {ok, #{
                <<"a">> => #{<<"x">> => 1},
                <<"b">> => #{<<"x">> => 2, <<"y">> => 3},
                <<"c">> => #{<<"x">> => 9, <<"y">> => 3}
            }},
            nyaml:decode(
                <<"a: &a {x: 1}\nb: &b {x: 2, y: 3}\nc:\n  <<: [*a, *b]\n  x: 9\n">>, Extended
            )
        ),
        ?_assertEqual(
            {ok, #{<<"a">> => #{<<"x">> => 1}, <<"c">> => #{}}},
            nyaml:decode(<<"a: &a {x: 1}\nc:\n  <<: []\n">>, Extended)
        )
    ].

%% The four mappings of the "!!merge Examples" example of the type repository
%% are equal.
nyaml_extended_merge_repository_example_test() ->
    Document = <<
        "- &CENTER { x: 1, y: 2 }\n"
        "- &LEFT { x: 0, y: 2 }\n"
        "- &BIG { r: 10 }\n"
        "- &SMALL { r: 1 }\n"
        "\n"
        "- # Explicit keys\n"
        "  x: 1\n"
        "  y: 2\n"
        "  r: 10\n"
        "  label: center/big\n"
        "\n"
        "- # Merge one map\n"
        "  << : *CENTER\n"
        "  r: 10\n"
        "  label: center/big\n"
        "\n"
        "- # Merge multiple maps\n"
        "  << : [ *CENTER, *BIG ]\n"
        "  label: center/big\n"
        "\n"
        "- # Override\n"
        "  << : [ *BIG, *LEFT, *SMALL ]\n"
        "  x: 1\n"
        "  label: center/big\n"
    >>,
    {ok, Decoded} = nyaml:decode(Document, #{schema => extended}),
    [_Center, _Left, _Big, _Small | Equal] = Decoded,
    Expected = #{
        <<"x">> => 1, <<"y">> => 2, <<"r">> => 10, <<"label">> => <<"center/big">>
    },
    ?assertEqual([Expected, Expected, Expected, Expected], Equal).

%% A flow mapping merges as a block mapping does, and so does the implicit
%% mapping of a flow sequence entry.
nyaml_extended_merge_flow_test_() ->
    Extended = #{schema => extended},
    [
        ?_assertEqual(
            {ok, #{<<"a">> => #{<<"p">> => 1}, <<"m">> => #{<<"p">> => 1, <<"q">> => 2}}},
            nyaml:decode(<<"{a: &x {p: 1}, m: {<<: *x, q: 2}}">>, Extended)
        ),
        ?_assertEqual(
            {ok, #{<<"a">> => #{<<"p">> => 1}, <<"m">> => #{<<"p">> => 9}}},
            nyaml:decode(<<"{a: &x {p: 1}, m: {<<: *x, p: 9}}">>, Extended)
        ),
        ?_assertEqual(
            {ok, #{<<"a">> => #{<<"p">> => 1}, <<"m">> => [#{<<"p">> => 1, <<"q">> => 2}]}},
            nyaml:decode(<<"{a: &x {p: 1}, m: [{<<: *x, q: 2}]}">>, Extended)
        ),
        ?_assertEqual(
            {ok, #{<<"a">> => #{<<"p">> => 1}, <<"m">> => [#{<<"p">> => 1}]}},
            nyaml:decode(<<"a: &x {p: 1}\nm: [<<: *x]\n">>, Extended)
        ),
        ?_assertEqual(
            {ok, #{<<"a">> => #{<<"p">> => 1}, <<"m">> => #{<<"<<">> => #{<<"p">> => 1}}}},
            nyaml:decode(<<"{a: &x {p: 1}, m: {<<: *x}}">>, #{schema => core})
        )
    ].

%% An explicit `?` key carries no quote, so `? <<` is the merge key.
nyaml_extended_merge_explicit_key_test_() ->
    Extended = #{schema => extended},
    [
        ?_assertEqual(
            {ok, #{<<"d">> => #{<<"x">> => 1}, <<"m">> => #{<<"x">> => 1}}},
            nyaml:decode(<<"d: &d {x: 1}\nm:\n  ? <<\n  : *d\n">>, Extended)
        ),
        ?_assertEqual(
            {ok, #{<<"d">> => #{<<"x">> => 1}, <<"m">> => #{<<"<<">> => #{<<"x">> => 1}}}},
            nyaml:decode(<<"d: &d {x: 1}\nm:\n  ? <<\n  : *d\n">>, #{schema => core})
        )
    ].

%% A quoted key carries the `str` tag, so it is a string key under every
%% schema.
nyaml_extended_merge_quoted_key_test_() ->
    Extended = #{schema => extended},
    [
        ?_assertEqual(
            {ok, #{<<"d">> => #{<<"x">> => 1}, <<"m">> => #{<<"<<">> => #{<<"x">> => 1}}}},
            nyaml:decode(<<"d: &d {x: 1}\nm:\n  \"<<\": *d\n">>, Extended)
        ),
        ?_assertEqual(
            {ok, #{<<"d">> => #{<<"x">> => 1}, <<"m">> => #{<<"<<">> => #{<<"x">> => 1}}}},
            nyaml:decode(<<"d: &d {x: 1}\nm:\n  '<<': *d\n">>, Extended)
        ),
        ?_assertEqual(
            {ok, #{<<"a">> => #{<<"<<">> => 1}}},
            nyaml:decode(<<"a: {\"<<\": 1}">>, Extended)
        )
    ].

%% A tag over the key names the tag of the node, and an anchor binds the text
%% of the key. A `<<` in a value position is a string under every schema.
nyaml_extended_merge_key_text_test_() ->
    Extended = #{schema => extended},
    [
        ?_assertEqual(
            {ok, #{<<"<<">> => 1}},
            nyaml:decode(<<"!!str << : 1\n">>, Extended)
        ),
        ?_assertEqual(
            {ok, #{<<"d">> => #{<<"x">> => 1}, <<"x">> => 1, <<"k">> => <<"<<">>}},
            nyaml:decode(<<"d: &d {x: 1}\n&anchor <<: *d\nk: *anchor\n">>, Extended)
        ),
        ?_assertEqual(
            {ok, #{<<"a">> => <<"<<">>}},
            nyaml:decode(<<"a: <<\n">>, Extended)
        ),
        ?_assertEqual(
            {ok, [<<"<<">>]},
            nyaml:decode(<<"- <<\n">>, Extended)
        )
    ].

%% "this sequence is expected to contain mapping nodes". Anything else fails
%% the rule.
nyaml_extended_merge_invalid_value_test_() ->
    Extended = #{schema => extended},
    [
        ?_assertEqual(
            {error, {merge_value_not_a_mapping, scalar}},
            nyaml:decode(<<"a: &a 1\nb:\n  <<: *a\n">>, Extended)
        ),
        ?_assertEqual(
            {error, {merge_value_not_a_mapping, sequence}},
            nyaml:decode(<<"a: &a [1]\nb:\n  <<: [*a]\n">>, Extended)
        ),
        ?_assertEqual(
            {error, {merge_value_not_a_mapping, scalar}},
            nyaml:decode(<<"a: &a {x: 1}\nb: &b 2\nc:\n  <<: [*a, *b]\n">>, Extended)
        ),
        ?_assertEqual(
            {error, {merge_value_not_a_mapping, scalar}},
            nyaml:decode(<<"b:\n  <<:\n">>, Extended)
        ),
        ?_assertEqual(
            {error, {merge_value_not_a_mapping, scalar}},
            nyaml:decode(<<"{a: &a 1, b: {<<: *a}}">>, Extended)
        ),
        ?_assertEqual(
            {ok, #{<<"a">> => 1, <<"b">> => #{<<"<<">> => 1}}},
            nyaml:decode(<<"a: &a 1\nb:\n  <<: *a\n">>, #{schema => core})
        )
    ].

%% A mapping holds one binding per key, and a duplicate key keeps the last
%% binding, so a second merge key replaces the first.
nyaml_extended_merge_duplicate_key_test_() ->
    [
        ?_assertEqual(
            {ok, #{
                <<"a">> => #{<<"x">> => 1},
                <<"b">> => #{<<"x">> => 9},
                <<"c">> => #{<<"x">> => 9}
            }},
            nyaml:decode(
                <<"a: &a {x: 1}\nb: &b {x: 9}\nc:\n  <<: *a\n  <<: *b\n">>,
                #{schema => extended}
            )
        )
    ].
