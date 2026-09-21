-module(nyaml_tab_tests).

-include_lib("eunit/include/eunit.hrl").

flow_line_prefix_test_() ->
    [
        {"Line Prefixes, Y79Y/003, a tab opens the first line of a flow sequence",
            ?_assertEqual(
                {error, tab_in_indentation},
                nyaml:decode(<<"- [\n\tfoo,\n foo\n ]\n">>)
            )},
        {"Line Prefixes, a tab opens a later line of the same flow sequence",
            ?_assertEqual(
                {error, tab_in_indentation},
                nyaml:decode(<<"- [\n foo,\n\tfoo\n ]\n">>)
            )},
        {"Line Prefixes, a tab opens a flow sequence under a mapping key",
            ?_assertEqual(
                {error, tab_in_indentation},
                nyaml:decode(<<"a: [\n\tfoo\n ]\n">>)
            )},
        {"Line Prefixes, Y79Y/002, a line of white space is an l-comment line",
            ?_assertEqual(
                {ok, [[<<"foo">>]]},
                nyaml:decode(<<"- [\n\t\n foo\n ]\n">>)
            )},
        {"Line Prefixes, a tab after s-indent(n) is s-separate-in-line",
            ?_assertEqual(
                {ok, [[<<"foo">>]]},
                nyaml:decode(<<"- [\n \tfoo\n ]\n">>)
            )}
    ].

flow_scalar_line_prefix_test_() ->
    [
        {"Line Prefixes, DK95/01, a tab continues a double-quoted scalar",
            ?_assertEqual(
                {error, tab_in_indentation},
                nyaml:decode(<<"foo: \"bar\n\tbaz\"\n">>)
            )},
        {"Line Prefixes, a tab continues a single-quoted scalar",
            ?_assertEqual(
                {error, tab_in_indentation},
                nyaml:decode(<<"foo: 'bar\n\tbaz'\n">>)
            )},
        {"Line Prefixes, a tab-only line is not l-empty inside a flow scalar",
            ?_assertEqual(
                {error, tab_in_indentation},
                nyaml:decode(<<"foo: \"bar\n\t\n baz\"\n">>)
            )},
        {"Line Prefixes, DK95/00, a space indents the continuation line",
            ?_assertEqual(
                {ok, #{<<"foo">> => <<"bar baz">>}},
                nyaml:decode(<<"foo: \"bar\n baz\"\n">>)
            )},
        {"Line Prefixes, the example line, s-indent(n) and then a tab",
            ?_assertEqual(
                {ok, #{<<"quoted">> => <<"text lines">>}},
                nyaml:decode(<<"quoted: \"text\n  \tlines\"\n">>)
            )},
        {"Line Prefixes, a tab inside a double-quoted scalar is content",
            ?_assertEqual(
                {ok, #{<<"foo">> => <<"a\tb">>}},
                nyaml:decode(<<"foo: \"a\tb\"\n">>)
            )}
    ].

block_entry_line_prefix_test_() ->
    [
        {"Indentation Spaces, DK95/06, a tab before a key of an indented mapping",
            ?_assertEqual(
                {error, tab_in_indentation},
                nyaml:decode(<<"foo:\n  a: 1\n  \tb: 2\n">>)
            )},
        {"Indentation Spaces, a tab before a key at the top level",
            ?_assertEqual(
                {error, tab_in_indentation},
                nyaml:decode(<<"a: 1\n\tb: 2\n">>)
            )},
        {"Indentation Spaces, a tab before a sequence entry indicator",
            ?_assertEqual(
                {error, tab_in_indentation},
                nyaml:decode(<<"foo:\n  - a\n  \t- b\n">>)
            )},
        {"Separation Spaces, a tab inside a plain scalar is content",
            ?_assertEqual(
                {ok, #{<<"foo">> => <<"a\tb">>}},
                nyaml:decode(<<"foo: a\tb\n">>)
            )},
        {"Separation Spaces, a tab inside a plain key is content",
            ?_assertEqual(
                {ok, #{<<"a\tb">> => 1}},
                nyaml:decode(<<"a\tb: 1\n">>)
            )},
        {"Separation Spaces, a tab separates a value from its comment",
            ?_assertEqual(
                {ok, #{<<"foo">> => <<"bar">>}},
                nyaml:decode(<<"foo: bar\t# comment\n">>)
            )}
    ].

block_scalar_content_indentation_test_() ->
    [
        {"Block Indentation Indicator, Y79Y/000, a tab below the content indentation",
            ?_assertEqual(
                {error, tab_in_indentation},
                nyaml:decode(<<"foo: |\n\t\nbar: 1\n">>)
            )},
        {"Block Indentation Indicator, the folded counterpart of Y79Y/000",
            ?_assertEqual(
                {error, tab_in_indentation},
                nyaml:decode(<<"foo: >\n\t\nbar: 1\n">>)
            )},
        {"Block Indentation Indicator, Y79Y/001, a tab at the content indentation",
            ?_assertEqual(
                {ok, #{<<"foo">> => <<"\t\n">>, <<"bar">> => 1}},
                nyaml:decode(<<"foo: |\n \t\nbar: 1\n">>)
            )},
        {"Block Indentation Indicator, a tab beyond the content indentation",
            ?_assertEqual(
                {ok, #{<<"foo">> => <<"a\tb\n">>}},
                nyaml:decode(<<"foo: |\n  a\tb\n">>)
            )}
    ].

nested_block_entry_after_a_tab_test_() ->
    [
        {"Block Sequences, Y79Y/004, a tab between `-` and a nested entry",
            ?_assertEqual(
                {error, tab_before_nested_block_entry},
                nyaml:decode(<<"-\t-\n">>)
            )},
        {"Block Sequences, Y79Y/005, a space and a tab in the same position",
            ?_assertEqual(
                {error, tab_before_nested_block_entry},
                nyaml:decode(<<"- \t-\n">>)
            )},
        {"Block Mappings, Y79Y/006, a tab between `?` and a nested entry",
            ?_assertEqual(
                {error, tab_before_nested_block_entry},
                nyaml:decode(<<"?\t-\n">>)
            )},
        {"Block Mappings, Y79Y/007, a tab between `:` and a nested entry",
            ?_assertEqual(
                {error, tab_before_nested_block_entry},
                nyaml:decode(<<"? -\n:\t-\n">>)
            )},
        {"Block Mappings, Y79Y/008, a tab between `?` and a compact mapping",
            ?_assertEqual(
                {error, tab_before_nested_block_entry},
                nyaml:decode(<<"?\tkey:\n">>)
            )},
        {"Block Mappings, Y79Y/009, a tab between `:` and a compact mapping",
            ?_assertEqual(
                {error, tab_before_nested_block_entry},
                nyaml:decode(<<"? key:\n:\tkey:\n">>)
            )}
    ].

flow_node_after_a_tab_test_() ->
    [
        {"Block Sequences, Y79Y/010, `-1` after the tab is a flow node",
            ?_assertEqual(
                {ok, [-1]},
                nyaml:decode(<<"-\t-1\n">>)
            )},
        {"Block Sequences, a plain scalar after the tab is a flow node",
            ?_assertEqual(
                {ok, [<<"foo">>]},
                nyaml:decode(<<"-\tfoo\n">>)
            )},
        {"Block Sequences, a flow sequence after the tab is a flow node",
            ?_assertEqual(
                {ok, [[<<"foo">>]]},
                nyaml:decode(<<"-\t[foo]\n">>)
            )}
    ].
