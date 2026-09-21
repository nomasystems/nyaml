-module(nyaml_block_util_tests).

-include_lib("eunit/include/eunit.hrl").

%% anchor_value_position/1 detects end-of-line and comment positions after an anchor name
anchor_value_position_test_() ->
    [
        ?_assertEqual(empty_or_newline, nyaml_block_util:anchor_value_position(<<>>)),
        ?_assertEqual(empty_or_newline, nyaml_block_util:anchor_value_position(<<"\nrest">>)),
        ?_assertEqual(empty_or_newline, nyaml_block_util:anchor_value_position(<<"\r\nrest">>)),
        ?_assertEqual(empty_or_newline, nyaml_block_util:anchor_value_position(<<"  # c">>)),
        ?_assertEqual({inline, <<"value">>}, nyaml_block_util:anchor_value_position(<<" value">>))
    ].

%% collect_plain_scalar_lines/3 folds continuations and rejects malformed input
collect_plain_scalar_lines_test_() ->
    [
        ?_assertEqual(
            {error, tab_in_indentation},
            nyaml_block_util:collect_plain_scalar_lines(<<"foo">>, <<"\tbar">>, 1)
        ),
        ?_assertEqual(
            {error, {invalid_plain_scalar_start, $,}},
            nyaml_block_util:collect_plain_scalar_lines(<<",foo">>, <<>>, 0)
        ),
        ?_assertEqual(
            {ok, <<"foo bar">>, <<>>},
            nyaml_block_util:collect_plain_scalar_lines(<<"foo">>, <<"  bar">>, 1)
        )
    ].

%% collect_plain_scalar_lines/3 handles a trailing comment on a continuation line
collect_plain_scalar_comment_test_() ->
    [
        ?_assertEqual(
            {ok, <<"foo bar">>, <<>>},
            nyaml_block_util:collect_plain_scalar_lines(<<"foo">>, <<"  bar # c">>, 1)
        ),
        ?_assertEqual(
            {ok, <<"foo bar">>, <<"\n">>},
            nyaml_block_util:collect_plain_scalar_lines(<<"foo">>, <<"  bar # c\n\n">>, 1)
        ),
        ?_assertEqual(
            {ok, <<"foo bar">>, <<"\tq">>},
            nyaml_block_util:collect_plain_scalar_lines(<<"foo">>, <<"  bar # c\n\tq">>, 1)
        ),
        ?_assertEqual(
            {error, content_after_comment},
            nyaml_block_util:collect_plain_scalar_lines(<<"foo">>, <<"  bar # c\n  q">>, 1)
        )
    ].

%% collect_plain_scalar_lines/3 stops at a comment-only line unless content follows it
collect_plain_scalar_comment_line_test_() ->
    [
        ?_assertEqual(
            {ok, <<"foo">>, <<"# c">>},
            nyaml_block_util:collect_plain_scalar_lines(<<"foo">>, <<"# c">>, 1)
        ),
        ?_assertEqual(
            {ok, <<"foo">>, <<"# c\n\n">>},
            nyaml_block_util:collect_plain_scalar_lines(<<"foo">>, <<"# c\n\n">>, 1)
        ),
        ?_assertEqual(
            {ok, <<"foo">>, <<"# c\n# d">>},
            nyaml_block_util:collect_plain_scalar_lines(<<"foo">>, <<"# c\n# d">>, 1)
        ),
        ?_assertEqual(
            {ok, <<"foo">>, <<"# c\n\tbar">>},
            nyaml_block_util:collect_plain_scalar_lines(<<"foo">>, <<"# c\n\tbar">>, 1)
        ),
        ?_assertEqual(
            {error, plain_scalar_continuation_after_comment},
            nyaml_block_util:collect_plain_scalar_lines(<<"foo">>, <<"# c\n  bar">>, 1)
        )
    ].

%% multi-line plain scalars with comments through the public API
decode_plain_scalar_comment_test_() ->
    [
        ?_assertEqual(
            {ok, #{<<"key">> => <<"foo bar">>}},
            nyaml:decode(<<"key: foo\n  bar # c\n">>)
        ),
        ?_assertEqual(
            {error, content_after_comment},
            nyaml:decode(<<"key: foo\n  bar # c\n  qux\n">>)
        ),
        ?_assertEqual(
            {error, plain_scalar_continuation_after_comment},
            nyaml:decode(<<"key: foo\n# c\n  bar\n">>)
        )
    ].

%% collect_scalar_lines/4 folds lines, joins onto an accumulator, and rejects tabs
collect_scalar_lines_test_() ->
    [
        ?_assertEqual(
            {error, tab_in_indentation},
            nyaml_block_util:collect_scalar_lines(<<"\tfoo">>, <<>>, 0, <<>>)
        ),
        ?_assertEqual(
            {<<"foo bar">>, <<>>},
            nyaml_block_util:collect_scalar_lines(<<"bar">>, <<>>, 0, <<"foo">>)
        ),
        ?_assertEqual(
            {error, tab_in_indentation},
            nyaml_block_util:collect_scalar_lines(<<"foo">>, <<"\tbar">>, 0, <<>>)
        ),
        ?_assertEqual(
            {<<"foo">>, <<"\n\tbar">>},
            nyaml_block_util:collect_scalar_lines(<<"foo">>, <<"\n\tbar">>, 0, <<>>)
        )
    ].

%% count_leading_ws/1 counts both spaces and tabs
count_leading_ws_test_() ->
    [
        ?_assertEqual(2, nyaml_block_util:count_leading_ws(<<"\t x">>)),
        ?_assertEqual(0, nyaml_block_util:count_leading_ws(<<"x">>))
    ].

%% find_comment_start/1 reports a comment at the very start of the line
find_comment_start_test_() ->
    [
        ?_assertEqual(0, nyaml_block_util:find_comment_start(<<"#foo">>)),
        ?_assertEqual(4, nyaml_block_util:find_comment_start(<<"foo #bar">>))
    ].

%% flow_spans_lines/2 detects open collections across newlines and quoted spans
flow_spans_lines_test_() ->
    [
        ?_assertEqual(true, nyaml_block_util:flow_spans_lines(<<"\nrest">>, 1)),
        ?_assertEqual(true, nyaml_block_util:flow_spans_lines(<<"\r\nrest">>, 1)),
        ?_assertEqual(false, nyaml_block_util:flow_spans_lines(<<"'a]'">>, 0)),
        ?_assertEqual(false, nyaml_block_util:flow_spans_lines(<<"\"a\\\"b\"]">>, 1)),
        ?_assertEqual(true, nyaml_block_util:flow_spans_lines(<<"\"abc">>, 1))
    ].

%% has_comment/1 recognizes a comment introduced by a tab
has_comment_test_() ->
    [
        ?_assertEqual(true, nyaml_block_util:has_comment(<<"a\t#b">>)),
        ?_assertEqual(false, nyaml_block_util:has_comment(<<"a#b">>))
    ].

%% has_mapping_indicator/1 treats a lone question mark as an explicit key indicator
has_mapping_indicator_test_() ->
    [
        ?_assertEqual(true, nyaml_block_util:has_mapping_indicator(<<"?">>)),
        ?_assertEqual(true, nyaml_block_util:has_mapping_indicator(<<"k: v">>)),
        ?_assertEqual(false, nyaml_block_util:has_mapping_indicator(<<"k:v">>))
    ].

%% has_mapping_indicator_after_anchor/1 is false when the anchor name is invalid
has_mapping_indicator_after_anchor_test_() ->
    [
        ?_assertEqual(false, nyaml_block_util:has_mapping_indicator_after_anchor(<<" x">>)),
        ?_assertEqual(true, nyaml_block_util:has_mapping_indicator_after_anchor(<<"a k: v">>))
    ].

%% is_block_indicator/1 recognizes lone and trailing-whitespace forms of - and ?
is_block_indicator_test_() ->
    [
        ?_assertEqual(true, nyaml_block_util:is_block_indicator(<<"-">>)),
        ?_assertEqual(true, nyaml_block_util:is_block_indicator(<<"- item">>)),
        ?_assertEqual(true, nyaml_block_util:is_block_indicator(<<"? key">>)),
        ?_assertEqual(true, nyaml_block_util:is_block_indicator(<<"?">>)),
        ?_assertEqual(false, nyaml_block_util:is_block_indicator(<<"-item">>))
    ].

%% is_multiline_plain_scalar/2 is false when the next line has tab indentation
is_multiline_plain_scalar_test_() ->
    [
        ?_assertEqual(false, nyaml_block_util:is_multiline_plain_scalar(<<"\tfoo">>, 0)),
        ?_assertEqual(true, nyaml_block_util:is_multiline_plain_scalar(<<"  foo">>, 1))
    ].

%% is_plain_scalar_with_mapping_indicator/1 matches a colon followed by a tab
is_plain_scalar_with_mapping_indicator_test_() ->
    [
        ?_assertEqual(true, nyaml_block_util:is_plain_scalar_with_mapping_indicator(<<"a:\tb">>)),
        ?_assertEqual(false, nyaml_block_util:is_plain_scalar_with_mapping_indicator(<<"a:b">>))
    ].

%% parse_anchor_name/1 rejects an empty anchor name
parse_anchor_name_test_() ->
    [
        ?_assertEqual(
            {error, {invalid_anchor_name, <<" x">>}},
            nyaml_block_util:parse_anchor_name(<<" x">>)
        ),
        ?_assertEqual({ok, <<"a">>, <<" rest">>}, nyaml_block_util:parse_anchor_name(<<"a rest">>))
    ].

%% parse_scalar/1 handles empty input and quoted forms, keeping unterminated quotes raw
parse_scalar_test_() ->
    [
        ?_assertEqual({ok, null}, nyaml_block_util:parse_scalar(<<"   ">>)),
        ?_assertEqual({ok, <<"\"abc">>}, nyaml_block_util:parse_scalar(<<"\"abc">>)),
        ?_assertEqual({ok, <<"abc">>}, nyaml_block_util:parse_scalar(<<"'abc'">>)),
        ?_assertEqual({ok, <<"'abc">>}, nyaml_block_util:parse_scalar(<<"'abc">>))
    ].

%% parse_tag_name/1 rejects an empty tag name
parse_tag_name_test_() ->
    [
        ?_assertEqual(
            {error, {invalid_tag_name, <<" x">>}},
            nyaml_block_util:parse_tag_name(<<" x">>)
        ),
        ?_assertEqual({ok, <<"str">>, <<" v">>}, nyaml_block_util:parse_tag_name(<<"str v">>))
    ].

%% skip_anchor_or_alias_prefix/1 returns 0 when the anchor or alias name is invalid
skip_anchor_or_alias_prefix_test_() ->
    [
        ?_assertEqual(0, nyaml_block_util:skip_anchor_or_alias_prefix(<<"& x">>)),
        ?_assertEqual(0, nyaml_block_util:skip_anchor_or_alias_prefix(<<"* x">>)),
        ?_assertEqual(2, nyaml_block_util:skip_anchor_or_alias_prefix(<<"&a rest">>)),
        ?_assertEqual(2, nyaml_block_util:skip_anchor_or_alias_prefix(<<"*a rest">>))
    ].

%% skip_empty_lines/1 returns the empty binary at end of input
skip_empty_lines_test_() ->
    [
        ?_assertEqual(<<>>, nyaml_block_util:skip_empty_lines(<<>>)),
        ?_assertEqual(<<"a: 1">>, nyaml_block_util:skip_empty_lines(<<"\n# c\na: 1">>))
    ].

%% skip_flow_collection/4 tracks nesting, quoted spans, and unterminated input
skip_flow_collection_test_() ->
    [
        ?_assertEqual(error, nyaml_block_util:skip_flow_collection(<<"[a">>, 1, $], 1)),
        ?_assertEqual({ok, 5}, nyaml_block_util:skip_flow_collection(<<"[{a}]x">>, 1, $], 1)),
        ?_assertEqual({ok, 6}, nyaml_block_util:skip_flow_collection(<<"{[a]b}">>, 1, $}, 1)),
        ?_assertEqual(error, nyaml_block_util:skip_flow_collection(<<"[\"abc">>, 1, $], 1)),
        ?_assertEqual(error, nyaml_block_util:skip_flow_collection(<<"['abc">>, 1, $], 1))
    ].

%% skip_single_quoted/2 honors doubled-quote escapes
skip_single_quoted_test_() ->
    [
        ?_assertEqual({ok, 5}, nyaml_block_util:skip_single_quoted(<<"a''b'c">>, 0)),
        ?_assertEqual(error, nyaml_block_util:skip_single_quoted(<<"abc">>, 0))
    ].

%% skip_tag_chars/1 stops at flow delimiters and rejects [ and { inside a tag
skip_tag_chars_test_() ->
    [
        ?_assertEqual({ok, <<",bar">>}, nyaml_block_util:skip_tag_chars(<<"foo,bar">>)),
        ?_assertEqual(
            {error, {invalid_tag_character, $[}},
            nyaml_block_util:skip_tag_chars(<<"a[b">>)
        )
    ].

%% skip_to_next_line/1 handles CRLF line endings
skip_to_next_line_test_() ->
    [
        ?_assertEqual(<<"def">>, nyaml_block_util:skip_to_next_line(<<"abc\r\ndef">>)),
        ?_assertEqual(<<"def">>, nyaml_block_util:skip_to_next_line(<<"abc\ndef">>))
    ].

%% skip_verbatim_tag/1 reports a missing closing >
skip_verbatim_tag_test_() ->
    [
        ?_assertEqual(
            {error, unterminated_verbatim_tag},
            nyaml_block_util:skip_verbatim_tag(<<"abc">>)
        ),
        ?_assertEqual({ok, <<" v">>}, nyaml_block_util:skip_verbatim_tag(<<"tag:x> v">>))
    ].

%% starts_with_scalar_anchor/2 is false when the line has tab indentation
starts_with_scalar_anchor_test_() ->
    [
        ?_assertEqual(false, nyaml_block_util:starts_with_scalar_anchor(<<"\tfoo">>, 0)),
        ?_assertEqual(true, nyaml_block_util:starts_with_scalar_anchor(<<"&a v">>, 0))
    ].

%% strip_comment/1 keeps escaped quotes inside double-quoted spans
strip_comment_test_() ->
    [
        ?_assertEqual(<<"\"a\\\"b\"">>, nyaml_block_util:strip_comment(<<"\"a\\\"b\" #c">>)),
        ?_assertEqual(<<"v">>, nyaml_block_util:strip_comment(<<"v # c">>))
    ].

%% validate_flow_continuation_indent/2 reads its argument as continuation lines,
%% so the first line carries the s-flow-line-prefix(n) requirement too
validate_flow_continuation_indent_test_() ->
    [
        ?_assertEqual(
            ok, nyaml_block_util:validate_flow_continuation_indent(<<" a,\r\n  b]">>, 1)
        ),
        ?_assertEqual(
            ok, nyaml_block_util:validate_flow_continuation_indent(<<" {a: 1,\n  b: 2}">>, 1)
        ),
        ?_assertEqual(ok, nyaml_block_util:validate_flow_continuation_indent(<<" a,\n">>, 1)),
        ?_assertEqual(
            ok, nyaml_block_util:validate_flow_continuation_indent(<<" a,\n\n  b]">>, 1)
        ),
        ?_assertEqual(
            ok, nyaml_block_util:validate_flow_continuation_indent(<<" a,\r\n\r\n  b]">>, 1)
        ),
        ?_assertEqual(
            ok, nyaml_block_util:validate_flow_continuation_indent(<<" a,\n# c\n  b]">>, 1)
        ),
        ?_assertEqual(
            ok, nyaml_block_util:validate_flow_continuation_indent(<<" \"a\\\"b\"]">>, 1)
        ),
        ?_assertEqual(ok, nyaml_block_util:validate_flow_continuation_indent(<<" \"abc">>, 1)),
        %% A line of white space is an l-comment line and carries no prefix
        ?_assertEqual(
            ok, nyaml_block_util:validate_flow_continuation_indent(<<"\t\n b]">>, 1)
        ),
        ?_assertEqual(
            {error, flow_content_wrong_indentation},
            nyaml_block_util:validate_flow_continuation_indent(<<" a,\nb]">>, 1)
        ),
        %% A tab stands where s-indent(n) is required
        ?_assertEqual(
            {error, tab_in_indentation},
            nyaml_block_util:validate_flow_continuation_indent(<<"\tb]">>, 1)
        ),
        ?_assertEqual(
            {error, tab_in_indentation},
            nyaml_block_util:validate_flow_continuation_indent(<<" a,\n\tb]">>, 1)
        )
    ].

%% validate_rest_of_line/1 accepts a CRLF line ending
validate_rest_of_line_test_() ->
    [
        ?_assertEqual(ok, nyaml_block_util:validate_rest_of_line(<<"\r\nfoo">>)),
        ?_assertEqual(
            {error, trailing_content_after_value},
            nyaml_block_util:validate_rest_of_line(<<"x">>)
        )
    ].
