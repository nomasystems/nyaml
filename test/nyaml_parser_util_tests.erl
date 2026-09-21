-module(nyaml_parser_util_tests).

-include_lib("eunit/include/eunit.hrl").

%% ============================================================
%% Plain scalar collection
%% ============================================================

append_plain_scalar_continuation_test_() ->
    [
        %% content after a commented continuation line is an error
        ?_assertEqual(
            {error, content_after_comment},
            nyaml_parser_util:append_plain_scalar_continuation(
                <<"foo">>, <<"foo # c">>, <<"foo # c\nbar">>, {<<"acc">>, 0}, 0
            )
        ),
        %% commented line with only trailing comment lines extends the accumulator
        ?_assertEqual(
            {<<"acc foo">>, <<"# tail">>},
            nyaml_parser_util:append_plain_scalar_continuation(
                <<"foo">>, <<"foo # c">>, <<"foo # c\n# tail">>, {<<"acc">>, 0}, 0
            )
        ),
        %% uncommented line continues collecting following lines
        ?_assertEqual(
            {<<"acc foo bar">>, <<>>},
            nyaml_parser_util:append_plain_scalar_continuation(
                <<"foo">>, <<"foo">>, <<"foo\nbar">>, {<<"acc">>, 0}, 0
            )
        ),
        %% content after a comment on a plain scalar is rejected end to end
        ?_assertEqual({error, content_after_comment}, nyaml:decode(<<"foo # c\nbar">>))
    ].

collect_plain_scalar_lines_test_() ->
    [
        %% a document start marker terminates the plain scalar
        ?_assertEqual(
            {<<"acc">>, <<"---\nnext">>},
            nyaml_parser_util:collect_plain_scalar_lines(<<"---\nnext">>, <<"acc">>, 0, 0)
        ),
        %% a document end marker terminates the plain scalar
        ?_assertEqual(
            {<<"acc">>, <<"... tail">>},
            nyaml_parser_util:collect_plain_scalar_lines(<<"... tail">>, <<"acc">>, 0, 0)
        ),
        %% a marker line stops collection started from collect_plain_scalar
        ?_assertEqual(
            {<<"foo">>, <<"...">>}, nyaml_parser_util:collect_plain_scalar(<<"foo\n...">>)
        )
    ].

extend_plain_scalar_lines_acc_test_() ->
    [
        %% zero preceding blank lines fold with a single space
        ?_assertEqual(
            <<"a b">>, nyaml_parser_util:extend_plain_scalar_lines_acc(<<"a">>, <<"b">>, 0)
        ),
        %% blank lines become explicit newlines
        ?_assertEqual(
            <<"a\n\nb">>, nyaml_parser_util:extend_plain_scalar_lines_acc(<<"a">>, <<"b">>, 2)
        )
    ].

%% ============================================================
%% Block structure detection
%% ============================================================

block_starts_with_sequence_or_mapping_test_() ->
    [
        %% empty input has no sequence or mapping
        ?_assertEqual(false, nyaml_parser_util:block_starts_with_sequence_or_mapping(<<>>)),
        %% blank and comment-only lines have no sequence or mapping
        ?_assertEqual(
            false, nyaml_parser_util:block_starts_with_sequence_or_mapping(<<"\n  \n# c\n">>)
        ),
        %% a dash item opens a block sequence
        ?_assertEqual(true, nyaml_parser_util:block_starts_with_sequence_or_mapping(<<"- item">>)),
        %% a lone question mark opens an explicit mapping key
        ?_assertEqual(true, nyaml_parser_util:block_starts_with_sequence_or_mapping(<<"?">>)),
        %% a colon on the line marks a mapping
        ?_assertEqual(true, nyaml_parser_util:block_starts_with_sequence_or_mapping(<<"k: v">>)),
        %% a plain scalar line is neither
        ?_assertEqual(false, nyaml_parser_util:block_starts_with_sequence_or_mapping(<<"plain">>))
    ].

detect_base_indent_test_() ->
    [
        %% no content lines yields zero indent
        ?_assertEqual(0, nyaml_parser_util:detect_base_indent(<<>>)),
        %% blank-only input yields zero indent
        ?_assertEqual(0, nyaml_parser_util:detect_base_indent(<<"   \n\n">>)),
        %% first content line determines the indent
        ?_assertEqual(2, nyaml_parser_util:detect_base_indent(<<"\n  foo">>))
    ].

count_leading_whitespace_test_() ->
    [
        %% a tab counts as eight columns
        ?_assertEqual(9, nyaml_parser_util:count_leading_whitespace(<<"\t x">>)),
        %% spaces count one column each
        ?_assertEqual(3, nyaml_parser_util:count_leading_whitespace(<<"   x">>))
    ].

%% ============================================================
%% Line predicates
%% ============================================================

ends_with_whitespace_test_() ->
    [
        %% the empty binary counts as ending in whitespace
        ?_assertEqual(true, nyaml_parser_util:ends_with_whitespace(<<>>)),
        %% a trailing space is whitespace
        ?_assertEqual(true, nyaml_parser_util:ends_with_whitespace(<<"a ">>)),
        %% a trailing tab is whitespace
        ?_assertEqual(true, nyaml_parser_util:ends_with_whitespace(<<"a\t">>)),
        %% a trailing letter is not whitespace
        ?_assertEqual(false, nyaml_parser_util:ends_with_whitespace(<<"a">>))
    ].

has_continuation_content_test_() ->
    [
        %% a blank line is skipped before finding content
        ?_assertEqual(true, nyaml_parser_util:has_continuation_content(<<"   \nnext">>)),
        %% a document start marker ends the scalar, no continuation
        ?_assertEqual(false, nyaml_parser_util:has_continuation_content(<<"--- doc">>)),
        %% a document end marker ends the scalar, no continuation
        ?_assertEqual(false, nyaml_parser_util:has_continuation_content(<<"...">>)),
        %% comment-only lines are skipped and yield no continuation
        ?_assertEqual(false, nyaml_parser_util:has_continuation_content(<<"# c\n">>)),
        %% content after a comment line is a continuation
        ?_assertEqual(true, nyaml_parser_util:has_continuation_content(<<"# c\nfoo">>))
    ].

has_directive_pattern_test_() ->
    [
        %% a %YAML directive on a later line is detected
        ?_assertEqual(true, nyaml_parser_util:has_directive_pattern(<<"a\n%YAML 1.2">>)),
        %% a %TAG directive on a later line is detected
        ?_assertEqual(true, nyaml_parser_util:has_directive_pattern(<<"a\n%TAG !e! t:">>)),
        %% content without directives has no pattern
        ?_assertEqual(false, nyaml_parser_util:has_directive_pattern(<<"a\nb">>))
    ].

has_newline_before_content_test_() ->
    [
        %% a CRLF before content counts as a newline
        ?_assertEqual(true, nyaml_parser_util:has_newline_before_content(<<"\r\nx">>)),
        %% whitespace before a newline still counts
        ?_assertEqual(true, nyaml_parser_util:has_newline_before_content(<<"  \nx">>)),
        %% immediate content means no newline first
        ?_assertEqual(false, nyaml_parser_util:has_newline_before_content(<<"x">>))
    ].

has_same_line_mapping_indicator_test_() ->
    [
        %% a newline ends the line before any indicator
        ?_assertEqual(
            false, nyaml_parser_util:has_same_line_mapping_indicator(<<"key\nx: y">>)
        ),
        %% a CRLF ends the line before any indicator
        ?_assertEqual(
            false, nyaml_parser_util:has_same_line_mapping_indicator(<<"key\r\nx: y">>)
        ),
        %% a colon at end of input is an indicator
        ?_assertEqual(true, nyaml_parser_util:has_same_line_mapping_indicator(<<"k:">>)),
        %% a colon followed by tab is an indicator
        ?_assertEqual(true, nyaml_parser_util:has_same_line_mapping_indicator(<<"k:\tv">>)),
        %% a colon at end of line is an indicator
        ?_assertEqual(true, nyaml_parser_util:has_same_line_mapping_indicator(<<"k:\nx">>)),
        %% a colon before CRLF is an indicator
        %% a colon before CRLF is an indicator
        ?_assertEqual(true, nyaml_parser_util:has_same_line_mapping_indicator(<<"k:\r\nx">>)),
        %% a colon inside a flow mapping belongs to the flow pair
        ?_assertEqual(false, nyaml_parser_util:has_same_line_mapping_indicator(<<"{a: 1}">>)),
        %% a colon inside a flow sequence belongs to the flow pair
        ?_assertEqual(false, nyaml_parser_util:has_same_line_mapping_indicator(<<"[{a: 1}]">>)),
        %% a colon after a closed flow collection is an indicator
        ?_assertEqual(true, nyaml_parser_util:has_same_line_mapping_indicator(<<"{a: 1}: v">>)),
        %% an unbalanced closing bracket leaves the level at zero
        ?_assertEqual(true, nyaml_parser_util:has_same_line_mapping_indicator(<<"}: v">>)),
        %% a colon inside a double-quoted scalar is content
        ?_assertEqual(false, nyaml_parser_util:has_same_line_mapping_indicator(<<"\"a: b\"">>)),
        %% a colon inside a single-quoted scalar is content
        ?_assertEqual(false, nyaml_parser_util:has_same_line_mapping_indicator(<<"'a: b'">>)),
        %% a colon after a closed quoted scalar is an indicator
        ?_assertEqual(true, nyaml_parser_util:has_same_line_mapping_indicator(<<"\"a\": b">>)),
        %% an escaped quote does not close a double-quoted scalar
        ?_assertEqual(
            false, nyaml_parser_util:has_same_line_mapping_indicator(<<"\"a\\\": b\"">>)
        ),
        %% a doubled quote does not close a single-quoted scalar
        ?_assertEqual(false, nyaml_parser_util:has_same_line_mapping_indicator(<<"'a'': b'">>)),
        %% an unterminated quoted scalar ends with its line
        ?_assertEqual(false, nyaml_parser_util:has_same_line_mapping_indicator(<<"\"a">>)),
        %% an escaped line break does not carry the scan onto the next line
        ?_assertEqual(
            false, nyaml_parser_util:has_same_line_mapping_indicator(<<"\"a\\\nb: c">>)
        )
    ].

skip_same_line_quoted_test_() ->
    [
        %% the empty input has nothing left to return
        ?_assertEqual(<<>>, nyaml_parser_util:skip_same_line_quoted(<<>>, $")),
        %% a closing quote hands back what follows it
        ?_assertEqual(<<" rest">>, nyaml_parser_util:skip_same_line_quoted(<<"a\" rest">>, $")),
        %% an unterminated scalar stops at the line break
        ?_assertEqual(<<"\nb">>, nyaml_parser_util:skip_same_line_quoted(<<"a\nb">>, $")),
        %% a backslash escapes the quote that would otherwise close the scalar
        ?_assertEqual(<<"c">>, nyaml_parser_util:skip_same_line_quoted(<<"a\\\"b\"c">>, $")),
        %% a doubled quote stands for one quote inside a single-quoted scalar
        ?_assertEqual(<<"c">>, nyaml_parser_util:skip_same_line_quoted(<<"a''b'c">>, $')),
        %% a backslash is content in a single-quoted scalar
        ?_assertEqual(<<"b">>, nyaml_parser_util:skip_same_line_quoted(<<"a\\'b">>, $'))
    ].

is_empty_line_test_() ->
    [
        %% whitespace-only lines are empty
        ?_assertEqual(true, nyaml_parser_util:is_empty_line(<<"   ">>)),
        %% the empty binary is empty
        ?_assertEqual(true, nyaml_parser_util:is_empty_line(<<>>)),
        %% comment-only lines are empty
        ?_assertEqual(true, nyaml_parser_util:is_empty_line(<<"# c">>)),
        %% content lines are not empty
        ?_assertEqual(false, nyaml_parser_util:is_empty_line(<<"x">>))
    ].

line_has_comment_test_() ->
    [
        %% a tab before the hash starts a comment
        ?_assertEqual(true, nyaml_parser_util:line_has_comment(<<"key\t# c">>)),
        %% an escaped quote does not close a double-quoted span
        ?_assertEqual(true, nyaml_parser_util:line_has_comment(<<"\"a\\\"b\" # c">>)),
        %% a hash inside double quotes is not a comment
        ?_assertEqual(false, nyaml_parser_util:line_has_comment(<<"\"a # b\"">>)),
        %% a doubled quote does not close a single-quoted span
        ?_assertEqual(true, nyaml_parser_util:line_has_comment(<<"'a''b' # c">>)),
        %% a hash inside single quotes is not a comment
        ?_assertEqual(false, nyaml_parser_util:line_has_comment(<<"'a # b'">>))
    ].

%% ============================================================
%% Line navigation
%% ============================================================

next_line_test_() ->
    [
        %% empty input has no more lines
        ?_assertEqual({no_more_lines, <<>>}, nyaml_parser_util:next_line(<<>>)),
        %% a newline splits line from rest
        ?_assertEqual({line, <<"a">>, <<"b">>}, nyaml_parser_util:next_line(<<"a\nb">>)),
        %% a final line without newline is returned whole
        ?_assertEqual({line, <<"a">>, <<>>}, nyaml_parser_util:next_line(<<"a">>))
    ].

next_non_empty_line_test_() ->
    [
        %% empty input has no more lines
        ?_assertEqual({no_more_lines, <<>>}, nyaml_parser_util:next_non_empty_line(<<>>)),
        %% blank and comment lines are skipped
        ?_assertEqual(
            {line, <<"foo">>, <<>>}, nyaml_parser_util:next_non_empty_line(<<"\n# c\nfoo">>)
        )
    ].

skip_leading_ws_test_() ->
    [
        %% leading spaces and tabs are dropped
        ?_assertEqual(<<"foo">>, nyaml_parser_util:skip_leading_ws(<<" \tfoo">>)),
        %% input without leading whitespace is unchanged
        ?_assertEqual(<<"foo">>, nyaml_parser_util:skip_leading_ws(<<"foo">>))
    ].

skip_empty_and_comment_lines_test_() ->
    [
        %% a CRLF blank line is skipped and indent restored
        ?_assertEqual(
            <<"  foo">>, nyaml_parser_util:skip_empty_and_comment_lines(<<"\r\n  foo">>)
        ),
        %% comment lines are skipped up to content
        ?_assertEqual(
            <<"foo">>, nyaml_parser_util:skip_empty_and_comment_lines(<<"# c\n\nfoo">>)
        )
    ].

skip_to_content_test_() ->
    [
        %% inline tabs and spaces are skipped to content
        ?_assertEqual(<<"x">>, nyaml_parser_util:skip_to_content(<<"\t x">>)),
        %% comment lines after the newline are skipped
        ?_assertEqual(<<"foo">>, nyaml_parser_util:skip_to_content(<<"  \n# c\nfoo">>))
    ].

skip_to_end_of_line_test_() ->
    [
        %% a CRLF terminates the line
        ?_assertEqual(<<"cd">>, nyaml_parser_util:skip_to_end_of_line(<<"ab\r\ncd">>)),
        %% input without a newline is consumed entirely
        ?_assertEqual(<<>>, nyaml_parser_util:skip_to_end_of_line(<<"ab">>))
    ].

skip_to_eol_test_() ->
    [
        %% the next line loses its leading whitespace
        ?_assertEqual(<<"cd">>, nyaml_parser_util:skip_to_eol(<<"ab\n  cd">>)),
        %% CRLF line endings are handled
        ?_assertEqual(<<"cd">>, nyaml_parser_util:skip_to_eol(<<"ab\r\n\tcd">>)),
        %% input without a newline is consumed entirely
        ?_assertEqual(<<>>, nyaml_parser_util:skip_to_eol(<<"ab">>))
    ].

skip_to_newline_then_continue_test_() ->
    [
        %% a CRLF ends the skipped line before continuing
        ?_assertEqual(
            <<"foo">>, nyaml_parser_util:skip_to_newline_then_continue(<<"junk\r\nfoo">>)
        ),
        %% blank lines after the newline are also skipped
        ?_assertEqual(
            <<"foo">>, nyaml_parser_util:skip_to_newline_then_continue(<<"junk\n\nfoo">>)
        )
    ].

skip_whitespace_inline_test_() ->
    [
        %% tabs and spaces are dropped, newlines are kept
        ?_assertEqual(<<"x y">>, nyaml_parser_util:skip_whitespace_inline(<<"\t \tx y">>)),
        %% a newline stops inline skipping
        ?_assertEqual(<<"\nx">>, nyaml_parser_util:skip_whitespace_inline(<<" \nx">>))
    ].

strip_trailing_ws_test_() ->
    [
        %% the empty binary is unchanged
        ?_assertEqual(<<>>, nyaml_parser_util:strip_trailing_ws(<<>>)),
        %% trailing spaces and tabs are removed
        ?_assertEqual(<<"ab">>, nyaml_parser_util:strip_trailing_ws(<<"ab \t ">>)),
        %% input without trailing whitespace is unchanged
        ?_assertEqual(<<"ab">>, nyaml_parser_util:strip_trailing_ws(<<"ab">>))
    ].

%% ============================================================
%% Tags and directives
%% ============================================================

parse_tag_handle_name_test_() ->
    [
        %% a tab yields the empty primary handle
        ?_assertEqual({ok, <<>>, <<"\tx">>}, nyaml_parser_util:parse_tag_handle_name(<<"\tx">>)),
        %% a named handle closes at the second bang
        ?_assertEqual(
            {ok, <<"e!">>, <<"suffix">>}, nyaml_parser_util:parse_tag_handle_name(<<"e!suffix">>)
        ),
        %% an invalid character after handle characters is rejected
        ?_assertEqual(
            {error, invalid_tag_handle_name},
            nyaml_parser_util:parse_tag_handle_name(<<"ab$rest">>)
        ),
        %% an invalid leading character is rejected
        ?_assertEqual(
            {error, invalid_tag_handle_name}, nyaml_parser_util:parse_tag_handle_name(<<"$x">>)
        )
    ].

parse_tag_prefix_test_() ->
    [
        %% a CRLF terminates the prefix
        ?_assertEqual(
            {<<"tag:x">>, <<"rest">>}, nyaml_parser_util:parse_tag_prefix(<<"tag:x\r\nrest">>)
        ),
        %% a space ends the prefix and skips the rest of the line
        ?_assertEqual(
            {<<"pfx">>, <<"rest">>}, nyaml_parser_util:parse_tag_prefix(<<"pfx trailing\nrest">>)
        ),
        %% a tab ends the prefix and skips the rest of the line
        ?_assertEqual(
            {<<"pfx">>, <<"rest">>}, nyaml_parser_util:parse_tag_prefix(<<"pfx\tt\nrest">>)
        ),
        %% end of input terminates the prefix
        ?_assertEqual({<<"pfx">>, <<>>}, nyaml_parser_util:parse_tag_prefix(<<"pfx">>))
    ].

skip_tag_chars_test_() ->
    [
        %% a comma delimits the tag
        ?_assertEqual({ok, <<",rest">>}, nyaml_parser_util:skip_tag_chars(<<"tag,rest">>)),
        %% end of input terminates the tag
        ?_assertEqual({ok, <<>>}, nyaml_parser_util:skip_tag_chars(<<"tag">>)),
        %% an opening bracket inside a tag is invalid
        ?_assertEqual(
            {error, {invalid_tag_character, $[}}, nyaml_parser_util:skip_tag_chars(<<"tag[">>)
        ),
        %% whitespace delimits the tag
        ?_assertEqual({ok, <<" rest">>}, nyaml_parser_util:skip_tag_chars(<<"tag rest">>))
    ].

parse_directive_name_test_() ->
    [
        %% "Directives" ends the name at the first space
        ?_assertEqual(
            {<<"YAML">>, <<" 1.2\n">>}, nyaml_parser_util:parse_directive_name(<<"YAML 1.2\n">>)
        ),
        %% a tab ends the name too
        ?_assertEqual(
            {<<"YAML">>, <<"\t1.2\n">>}, nyaml_parser_util:parse_directive_name(<<"YAML\t1.2\n">>)
        ),
        %% a line break ends a name that carries no parameter
        ?_assertEqual({<<"YAML">>, <<"\n">>}, nyaml_parser_util:parse_directive_name(<<"YAML\n">>)),
        %% a longer name is a name of its own, not the YAML directive, MUS6/06
        ?_assertEqual(
            {<<"YAMLL">>, <<" 1.1\n">>}, nyaml_parser_util:parse_directive_name(<<"YAMLL 1.1\n">>)
        )
    ].

parse_yaml_directive_test_() ->
    [
        %% "Separation Spaces" admits more than one space, MUS6/02
        ?_assertEqual({ok, <<"x">>}, nyaml_parser_util:parse_yaml_directive(<<"  1.1\nx">>)),
        %% "Separation Spaces" admits a tab, MUS6/03
        ?_assertEqual({ok, <<"x">>}, nyaml_parser_util:parse_yaml_directive(<<" \t 1.1\nx">>)),
        %% the separation is not optional
        ?_assertEqual(
            {error, invalid_yaml_directive}, nyaml_parser_util:parse_yaml_directive(<<"1.1\n">>)
        )
    ].

validate_directive_end_test_() ->
    [
        %% a CRLF ends the directive line
        ?_assertEqual({ok, <<"x">>}, nyaml_parser_util:validate_directive_end(<<"\r\nx">>)),
        %% "Comments" requires separation before a comment, MUS6/00
        ?_assertEqual(
            {error, comment_without_separation},
            nyaml_parser_util:validate_directive_end(<<"# c\nx">>)
        ),
        %% trailing content is invalid
        ?_assertEqual(
            {error, invalid_yaml_directive}, nyaml_parser_util:validate_directive_end(<<"z">>)
        ),
        %% a comment after the version is accepted end to end
        ?_assertEqual({ok, <<"foo">>}, nyaml:decode(<<"%YAML 1.2 # note\n---\nfoo">>))
    ].

validate_directive_end_after_space_test_() ->
    [
        %% a CRLF ends the directive line
        ?_assertEqual(
            {ok, <<"x">>}, nyaml_parser_util:validate_directive_end_after_space(<<"\r\nx">>)
        ),
        %% mixed spaces and tabs before a comment are accepted
        ?_assertEqual(
            {ok, <<"x">>}, nyaml_parser_util:validate_directive_end_after_space(<<" \t# c\nx">>)
        ),
        %% end of input ends the directive line
        ?_assertEqual({ok, <<>>}, nyaml_parser_util:validate_directive_end_after_space(<<>>)),
        %% trailing content is invalid
        ?_assertEqual(
            {error, invalid_yaml_directive},
            nyaml_parser_util:validate_directive_end_after_space(<<"z">>)
        )
    ].

validate_document_end_after_space_test_() ->
    [
        %% a newline ends the document-end line
        ?_assertEqual(
            {ok, <<"x">>}, nyaml_parser_util:validate_document_end_after_space(<<"\nx">>)
        ),
        %% a CRLF ends the document-end line
        ?_assertEqual(
            {ok, <<"x">>}, nyaml_parser_util:validate_document_end_after_space(<<"\r\nx">>)
        ),
        %% tabs before the newline are accepted
        ?_assertEqual(
            {ok, <<>>}, nyaml_parser_util:validate_document_end_after_space(<<"\t\n">>)
        ),
        %% trailing content is invalid
        ?_assertEqual(
            {error, invalid_content_after_document_end},
            nyaml_parser_util:validate_document_end_after_space(<<"z">>)
        )
    ].

validate_document_end_line_test_() ->
    [
        %% a CRLF ends the document-end line
        ?_assertEqual({ok, <<"x">>}, nyaml_parser_util:validate_document_end_line(<<"\r\nx">>)),
        %% trailing content is invalid
        ?_assertEqual(
            {error, invalid_content_after_document_end},
            nyaml_parser_util:validate_document_end_line(<<"z">>)
        )
    ].

%% ============================================================
%% Scalar coercions
%% ============================================================

%% The "Core Schema" section gives the `bool' tag
%% `true | True | TRUE | false | False | FALSE' and nothing else, so those six
%% spellings read under every schema and every other token reads under the
%% extended schema alone.
to_bool_test_() ->
    [
        ?_assertEqual({ok, true}, nyaml_parser_util:to_bool(core, <<"true">>)),
        ?_assertEqual({ok, true}, nyaml_parser_util:to_bool(core, <<"True">>)),
        ?_assertEqual({ok, true}, nyaml_parser_util:to_bool(core, <<"TRUE">>)),
        ?_assertEqual({ok, false}, nyaml_parser_util:to_bool(core, <<"false">>)),
        ?_assertEqual({ok, false}, nyaml_parser_util:to_bool(core, <<"False">>)),
        ?_assertEqual({ok, false}, nyaml_parser_util:to_bool(core, <<"FALSE">>)),
        ?_assertEqual(error, nyaml_parser_util:to_bool(core, <<"yes">>)),
        ?_assertEqual(error, nyaml_parser_util:to_bool(core, <<"off">>)),
        ?_assertEqual({ok, true}, nyaml_parser_util:to_bool(extended, <<"yes">>)),
        ?_assertEqual({ok, false}, nyaml_parser_util:to_bool(extended, <<"off">>)),
        ?_assertEqual({ok, true}, nyaml_parser_util:to_bool(extended, <<"true">>)),
        ?_assertEqual(error, nyaml_parser_util:to_bool(core, <<"zzz">>)),
        ?_assertEqual(error, nyaml_parser_util:to_bool(extended, <<"zzz">>))
    ].

to_float_test_() ->
    [
        %% a float binary parses to a float
        ?_assertEqual(2.5, nyaml_parser_util:to_float(<<"2.5">>)),
        %% an integer binary falls back to integer parsing
        ?_assertEqual(7.0, nyaml_parser_util:to_float(<<"7">>)),
        %% a non-numeric binary is left unchanged
        ?_assertEqual(<<"abc">>, nyaml_parser_util:to_float(<<"abc">>)),
        %% an integer is widened
        ?_assertEqual(3.0, nyaml_parser_util:to_float(3)),
        %% a non-numeric term is left unchanged
        ?_assertEqual(null, nyaml_parser_util:to_float(null))
    ].

to_int_test_() ->
    [
        %% an integer binary parses to an integer
        ?_assertEqual(5, nyaml_parser_util:to_int(<<"5">>)),
        %% a non-numeric binary is left unchanged
        ?_assertEqual(<<"abc">>, nyaml_parser_util:to_int(<<"abc">>)),
        %% a non-integer term is left unchanged
        ?_assertEqual(null, nyaml_parser_util:to_int(null))
    ].
