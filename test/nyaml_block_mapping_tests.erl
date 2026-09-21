-module(nyaml_block_mapping_tests).

-include_lib("eunit/include/eunit.hrl").

%% ============================================================
%% Mapping Entry Indentation Error Tests
%% ============================================================

nyaml_block_mapping_tab_indent_test_() ->
    [
        %% Tab-indented follow-up entry line is rejected
        ?_assertEqual(
            {error, tab_in_indentation},
            nyaml:decode(<<"a: 1\n\tb: 2">>)
        ),
        %% Tab-indented line after a lone explicit key indicator is rejected
        ?_assertEqual(
            {error, tab_in_indentation},
            nyaml:decode(<<"?\n\tk: v">>)
        ),
        %% Tab-indented value indicator line after a block scalar key is rejected
        ?_assertEqual(
            {error, tab_in_indentation},
            nyaml:decode(<<"? |\n  k\n\t: v">>)
        )
    ].

%% ============================================================
%% Explicit Key Null Forms Tests
%% ============================================================

nyaml_block_mapping_explicit_null_key_test_() ->
    [
        %% Lone explicit key indicator yields null key and null value
        ?_assertEqual(
            {ok, #{null => null}},
            nyaml:decode(<<"?">>)
        ),
        %% Lone explicit key indicator with trailing newline
        ?_assertEqual(
            {ok, #{null => null}},
            nyaml:decode(<<"?\n">>)
        ),
        %% Explicit key without value indicator at end of input is null-valued
        ?_assertEqual(
            {ok, #{<<"a">> => null}},
            nyaml:decode(<<"? a">>)
        ),
        %% Explicit key without value indicator followed by a sibling entry
        ?_assertEqual(
            {ok, #{<<"a">> => null, <<"b">> => 2}},
            nyaml:decode(<<"? a\nb: 2">>)
        ),
        %% Explicit key inside nested mapping closed by a dedented entry
        ?_assertEqual(
            {ok, #{<<"a">> => #{<<"k">> => null}, <<"b">> => 2}},
            nyaml:decode(<<"a:\n  ? k\nb: 2">>)
        )
    ].

%% ============================================================
%% Explicit Key Structure Tests
%% ============================================================

nyaml_block_mapping_explicit_structure_key_test_() ->
    [
        %% Sequence at the indicator indent becomes the key
        ?_assertEqual(
            {ok, #{[<<"a">>, <<"b">>] => <<"v">>}},
            nyaml:decode(<<"?\n- a\n- b\n: v">>)
        ),
        %% Bare dash sequence entry gives a null item key
        ?_assertEqual(
            {ok, #{[null] => <<"v">>}},
            nyaml:decode(<<"?\n-\n: v">>)
        ),
        %% Blank line between structure key and value indicator is skipped
        ?_assertEqual(
            {ok, #{[<<"a">>] => <<"v">>}},
            nyaml:decode(<<"?\n- a\n\n: v">>)
        ),
        %% A flow sequence in a structure key is refused at the line prefix
        ?_assertEqual(
            {error, flow_content_wrong_indentation},
            nyaml:decode(<<"?\n- [1,\n: v">>)
        ),
        %% Plain content at indicator indent is not a valid explicit key
        ?_assertEqual(
            {error, {explicit_key_missing_content, <<"foo">>}},
            nyaml:decode(<<"?\nfoo">>)
        )
    ].

%% ============================================================
%% Explicit Key Block Scalar Tests
%% ============================================================

nyaml_block_mapping_explicit_block_scalar_key_test_() ->
    [
        %% Block scalar on the line after the indicator becomes the key
        ?_assertEqual(
            {ok, #{<<"text\n">> => <<"v">>}},
            nyaml:decode(<<"?\n  |\n   text\n: v">>)
        ),
        %% Blank lines between block scalar key and value indicator are skipped
        ?_assertEqual(
            {ok, #{<<"k\n">> => <<"v">>}},
            nyaml:decode(<<"? |\n  k\n\n\n: v">>)
        ),
        %% Comment line between block scalar key and value indicator is skipped
        ?_assertEqual(
            {ok, #{<<"k\n">> => <<"v">>}},
            nyaml:decode(<<"? |\n  k\n# c\n: v">>)
        ),
        %% Plain content at base indent after a complete key needs a value indicator
        ?_assertEqual(
            {error, {expected_value_indicator, <<"plain">>}},
            nyaml:decode(<<"? |\n  k\nplain">>)
        ),
        %% Indented content after a complete key needs a value indicator
        ?_assertEqual(
            {error, {expected_value_indicator, <<"k">>}},
            nyaml:decode(<<"? |2\n k\n: v">>)
        )
    ].

%% ============================================================
%% Explicit Key Tag, Anchor and Quote Resolution Tests
%% ============================================================

nyaml_block_mapping_explicit_key_resolution_test_() ->
    [
        %% Tagged explicit key resolves the tag before use
        ?_assertEqual(
            {ok, #{<<"123">> => <<"v">>}},
            nyaml:decode(<<"? !!str 123\n: v">>)
        ),
        %% Alias explicit key resolves to the anchored value
        ?_assertEqual(
            {ok, #{<<"x">> => <<"foo">>, <<"foo">> => 2}},
            nyaml:decode(<<"x: &k foo\n? *k\n: 2">>)
        ),
        %% Single-quoted explicit key is unquoted
        ?_assertEqual(
            {ok, #{<<"a b">> => <<"v">>}},
            nyaml:decode(<<"? 'a b'\n: v">>)
        )
    ].

%% ============================================================
%% Implicit Key Separator Scanning Tests
%% ============================================================

nyaml_block_mapping_separator_test_() ->
    [
        %% Colon without following space stays part of the key
        ?_assertEqual(
            {ok, #{<<"a:b">> => <<"v">>}},
            nyaml:decode(<<"a:b: v">>)
        ),
        %% Line with only an alias is not a mapping entry
        ?_assertEqual(
            {error, {invalid_mapping_entry, <<"*x">>}},
            nyaml:decode(<<"k: v\n*x">>)
        ),
        %% Comment opening inside a flow key invalidates the entry
        ?_assertEqual(
            {error, {invalid_mapping_entry, <<"[a #b]: v">>}},
            nyaml:decode(<<"k: v\n[a #b]: v">>)
        ),
        %% Unterminated single-quoted key is not a mapping entry
        ?_assertEqual(
            {error, {invalid_mapping_entry, <<"'unclosed">>}},
            nyaml:decode(<<"k: v\n'unclosed">>)
        ),
        %% Unterminated double-quoted key is not a mapping entry
        ?_assertEqual(
            {error, {invalid_mapping_entry, <<"\"unclosed">>}},
            nyaml:decode(<<"k: v\n\"unclosed">>)
        ),
        %% Unterminated flow sequence is not a mapping entry
        ?_assertEqual(
            {error, {invalid_mapping_entry, <<"[1, 2">>}},
            nyaml:decode(<<"k: v\n[1, 2">>)
        ),
        %% Unterminated flow mapping is not a mapping entry
        ?_assertEqual(
            {error, {invalid_mapping_entry, <<"{a">>}},
            nyaml:decode(<<"k: v\n{a">>)
        )
    ].

%% ============================================================
%% Inline Explicit Key Value Tests
%% ============================================================

nyaml_block_mapping_inline_explicit_test_() ->
    [
        %% Inline explicit key with trailing colon has a null value
        ?_assertEqual(
            {ok, #{<<"a">> => null}},
            nyaml:decode(<<"? a :">>)
        )
    ].

%% ============================================================
%% Implicit Key Anchor, Alias and Tag Tests
%% ============================================================

nyaml_block_mapping_key_anchor_alias_test_() ->
    [
        %% Anchor directly followed by an alias key is rejected
        ?_assertEqual(
            {error, anchor_followed_by_alias},
            nyaml:decode(<<"&a *b: v">>)
        ),
        %% Anchor without a valid name in key position is rejected
        ?_assertEqual(
            {error, {invalid_anchor_name, <<"[a]">>}},
            nyaml:decode(<<"k: v\n&[a]: v">>)
        ),
        %% Alias without a valid name in key position is rejected
        ?_assertEqual(
            {error, {invalid_anchor_name, <<"[a]">>}},
            nyaml:decode(<<"k: v\n*[a]: v">>)
        ),
        %% Alias key resolves to the anchored value
        ?_assertEqual(
            {ok, #{<<"x">> => <<"foo">>, <<"foo">> => 2}},
            nyaml:decode(<<"x: &k foo\n*k : 2">>)
        ),
        %% Alias key with trailing content is rejected
        ?_assertEqual(
            {error, {invalid_alias_key, <<"*k extra">>}},
            nyaml:decode(<<"x: &k foo\n*k extra : v">>)
        ),
        %% Tag shorthand without a valid name in key position is rejected
        ?_assertEqual(
            {error, {invalid_tag_name, <<"{}">>}},
            nyaml:decode(<<"k: v\n!!{}: v">>)
        )
    ].

%% ============================================================
%% Implicit Quoted and Flow Key Tests
%% ============================================================

nyaml_block_mapping_quoted_flow_key_test_() ->
    [
        %% Invalid escape in a double-quoted key propagates the error
        ?_assertEqual(
            {error, {invalid_escape_sequence, $q}},
            nyaml:decode(<<"k: v\n\"a\\q\": v">>)
        ),
        %% Invalid flow sequence key propagates the flow error
        ?_assertEqual(
            {error, empty_sequence_with_comma},
            nyaml:decode(<<"k: v\n[,]: v">>)
        )
    ].

%% ============================================================
%% Explicit Key Tab Indentation Tests
%% ============================================================

nyaml_block_mapping_explicit_key_tab_test_() ->
    [
        %% Tab-indented explicit key continuation returns an error, never crashes
        ?_assertEqual(
            {error, tab_in_indentation},
            nyaml:decode(<<"? a\n\tb\n: v">>)
        )
    ].
