-module(nyaml_flow).

-moduledoc """
Flow style collections parsing.

Handles JSON-like flow syntax for sequences `[]` and mappings `{}`.
""".

%%%-----------------------------------------------------------------------------
%% API EXPORTS
%%%-----------------------------------------------------------------------------
-export([
    parse_mapping/2,
    parse_sequence/2
]).

%%%-----------------------------------------------------------------------------
%% TYPE EXPORTS
%%%-----------------------------------------------------------------------------
-export_type([
    parse_error/0,
    parse_result/0,
    yaml_value/0
]).

%%%-----------------------------------------------------------------------------
%% TYPES
%%%-----------------------------------------------------------------------------
-type yaml_value() :: nyaml:yaml_value().

-type key_break() :: none | binary().

-type key_context() :: flow_in | flow_key.

-type parse_error() ::
    bare_dash_in_flow_sequence
    | consecutive_commas_in_sequence
    | empty_sequence_with_comma
    | implicit_key_spans_lines
    | invalid_comment_after_bracket
    | invalid_comment_after_comma
    | invalid_leading_comma_in_sequence
    | missing_comma_in_flow_mapping
    | missing_comma_in_flow_sequence
    | not_a_mapping
    | not_a_sequence
    | unexpected_mapping_key_in_flow
    | unterminated_mapping
    | unterminated_sequence
    | {expected_colon, binary()}
    | {invalid_anchor_name, binary()}
    | {invalid_tag_name, binary()}
    | nyaml_merge:merge_error().

-type parse_result() ::
    {ok, yaml_value(), Rest :: binary(), nyaml_parser:ctx()} | {error, parse_error()}.

%%%-----------------------------------------------------------------------------
%% API FUNCTIONS
%%%-----------------------------------------------------------------------------

-doc """
Parses a flow mapping (JSON-like object).
""".
-spec parse_mapping(binary(), nyaml_parser:ctx()) -> parse_result().
parse_mapping(<<"{", Rest/binary>>, Ctx) ->
    parse_mapping_items(Rest, nyaml_merge:new(#{}), 0, Ctx);
parse_mapping(_Other, _Ctx) ->
    {error, not_a_mapping}.

-doc """
Parses a flow sequence (JSON-like array).
""".
-spec parse_sequence(binary(), nyaml_parser:ctx()) -> parse_result().
parse_sequence(<<"[", Rest/binary>>, Ctx) ->
    parse_sequence_items(Rest, [], 0, Ctx);
parse_sequence(_Other, _Ctx) ->
    {error, not_a_sequence}.

%%%-----------------------------------------------------------------------------
%% INTERNAL FUNCTIONS
%%%-----------------------------------------------------------------------------

-spec check_after_whitespace(binary()) -> comment | flow_delimiter | continue.
check_after_whitespace(<<C, Rest/binary>>) when C =:= $\s; C =:= $\t ->
    check_after_whitespace(Rest);
check_after_whitespace(<<"#", _/binary>>) ->
    comment;
check_after_whitespace(<<C, _/binary>>) when C =:= $,; C =:= $}; C =:= $] ->
    flow_delimiter;
check_after_whitespace(_) ->
    continue.

-spec fold_key_line(binary(), binary(), key_context(), binary(), key_break(), boolean()) ->
    {ok, binary(), binary()} | {error, parse_error()}.
fold_key_line(Bin, Rest, KeyCtx, Acc, Break, Spans) ->
    Trimmed = strip_trailing_ws(Acc),
    Next = skip_leading_ws(Rest),
    case Trimmed of
        <<>> ->
            parse_scalar_key(Next, KeyCtx, <<>>, Break, Spans);
        _ ->
            parse_scalar_key(Next, KeyCtx, <<Trimmed/binary, " ">>, unread_break(Break, Bin), Spans)
    end.

-spec key_before_colon(key_context(), binary(), key_break(), boolean(), binary()) ->
    {ok, binary(), binary()} | {error, parse_error()}.
key_before_colon(flow_key, _Acc, _Break, true, _Rest) ->
    {error, implicit_key_spans_lines};
key_before_colon(_KeyCtx, Acc, Break, _Spans, Rest) ->
    {ok, strip_trailing_ws(Acc), unread_break(Break, Rest)}.

-spec looks_like_mapping_key(binary()) -> boolean().
looks_like_mapping_key(Bin) ->
    looks_like_mapping_key(Bin, <<>>).

-spec looks_like_mapping_key(binary(), binary()) -> boolean().
looks_like_mapping_key(<<C, _/binary>>, _Acc) when
    C =:= $,; C =:= $}; C =:= $]; C =:= $[; C =:= ${
->
    false;
looks_like_mapping_key(<<":">>, Acc) when byte_size(Acc) > 0 ->
    true;
looks_like_mapping_key(<<":", C, _/binary>>, Acc) when
    (C =:= $\s orelse C =:= $\t orelse C =:= $\r orelse C =:= $\n orelse
        C =:= $, orelse C =:= $} orelse C =:= $]) andalso byte_size(Acc) > 0
->
    true;
looks_like_mapping_key(<<C, Rest/binary>>, Acc) when C =/= $\n, C =/= $\r ->
    looks_like_mapping_key(Rest, <<Acc/binary, C>>);
looks_like_mapping_key(_, _) ->
    false.

-spec parse_anchor_name(binary()) -> {ok, binary(), binary()} | {error, parse_error()}.
parse_anchor_name(Bin) ->
    parse_anchor_name(Bin, <<>>).

-spec parse_anchor_name(binary(), binary()) -> {ok, binary(), binary()} | {error, parse_error()}.
parse_anchor_name(<<C, Rest/binary>>, Acc) when
    C =/= $\s,
    C =/= $\t,
    C =/= $\n,
    C =/= $\r,
    C =/= $,,
    C =/= $[,
    C =/= $],
    C =/= ${,
    C =/= $}
->
    parse_anchor_name(Rest, <<Acc/binary, C>>);
parse_anchor_name(Rest, <<>>) ->
    {error, {invalid_anchor_name, Rest}};
parse_anchor_name(Rest, Acc) ->
    {ok, Acc, Rest}.

-spec parse_explicit_flow_key(binary()) -> {ok, binary(), binary()}.
parse_explicit_flow_key(Bin) ->
    parse_explicit_flow_key(Bin, <<>>).

-spec parse_explicit_flow_key(binary(), binary()) -> {ok, binary(), binary()}.
parse_explicit_flow_key(<<C, _/binary>> = Rest, Acc) when
    C =:= $,; C =:= $}; C =:= $]
->
    {ok, strip_trailing_ws(Acc), Rest};
parse_explicit_flow_key(<<":", C, _/binary>> = Rest, Acc) when
    C =:= $\s; C =:= $\t; C =:= $\r; C =:= $\n; C =:= $,; C =:= $}; C =:= $]
->
    {ok, strip_trailing_ws(Acc), Rest};
parse_explicit_flow_key(<<":">>, Acc) ->
    {ok, strip_trailing_ws(Acc), <<":">>};
parse_explicit_flow_key(<<"\n", Rest/binary>>, Acc) ->
    TrimmedAcc = strip_trailing_ws(Acc),
    Rest1 = skip_leading_ws(Rest),
    case TrimmedAcc of
        <<>> -> parse_explicit_flow_key(Rest1, <<>>);
        _ -> parse_explicit_flow_key(Rest1, <<TrimmedAcc/binary, " ">>)
    end;
parse_explicit_flow_key(<<"\r\n", Rest/binary>>, Acc) ->
    TrimmedAcc = strip_trailing_ws(Acc),
    Rest1 = skip_leading_ws(Rest),
    case TrimmedAcc of
        <<>> -> parse_explicit_flow_key(Rest1, <<>>);
        _ -> parse_explicit_flow_key(Rest1, <<TrimmedAcc/binary, " ">>)
    end;
parse_explicit_flow_key(<<C, Rest/binary>>, Acc) ->
    parse_explicit_flow_key(Rest, <<Acc/binary, C>>);
parse_explicit_flow_key(<<>>, Acc) ->
    {ok, strip_trailing_ws(Acc), <<>>}.

-spec parse_flow_key(binary(), nyaml_parser:ctx(), key_context()) ->
    {ok, nyaml_merge:key(), binary(), nyaml_parser:ctx()}
    | {error, parse_error()}
    | not_a_mapping.
parse_flow_key(<<"[", _/binary>> = Bin, Ctx, _KeyCtx) ->
    parse_sequence(Bin, Ctx);
parse_flow_key(<<"{", _/binary>> = Bin, Ctx, _KeyCtx) ->
    parse_mapping(Bin, Ctx);
parse_flow_key(<<"?", C, Rest/binary>>, Ctx, _KeyCtx) when
    C =:= $\s; C =:= $\t; C =:= $\n; C =:= $\r
->
    {ok, Plain, Rest1} = parse_explicit_flow_key(skip_whitespace(Rest)),
    {ok, Value} = nyaml_merge:resolve_key(Plain, Ctx),
    {ok, Value, Rest1, Ctx};
parse_flow_key(<<"\"", _/binary>> = Bin, Ctx, _KeyCtx) ->
    case nyaml_scalar:parse_quoted(Bin, double) of
        {ok, Value, Rest} -> {ok, Value, Rest, Ctx};
        {error, _} = Err -> Err
    end;
parse_flow_key(<<"'", _/binary>> = Bin, Ctx, _KeyCtx) ->
    case nyaml_scalar:parse_quoted(Bin, single) of
        {ok, Value, Rest} -> {ok, Value, Rest, Ctx};
        {error, _} = Err -> Err
    end;
parse_flow_key(<<"!!", Rest/binary>>, Ctx, KeyCtx) ->
    case parse_tag_name(Rest) of
        {ok, Tag, Rest1} ->
            Rest2 = skip_whitespace(Rest1),
            case Rest2 of
                <<C, _/binary>> when C =:= $:; C =:= $,; C =:= $}; C =:= $] ->
                    maybe
                        {ok, Empty} ?= nyaml_parser:empty_node_value(Tag, Ctx),
                        {ok, Empty, Rest2, Ctx}
                    end;
                _ ->
                    maybe
                        {ok, InnerValue, Rest3, Ctx1} ?= parse_flow_key(Rest2, Ctx, KeyCtx),
                        {ok, Resolved} ?=
                            nyaml_parser:resolve_tag(
                                Tag, nyaml_merge:unmark(InnerValue), Ctx
                            ),
                        {ok, Resolved, Rest3, Ctx1}
                    end
            end;
        {error, _} = Err ->
            Err
    end;
parse_flow_key(<<"&", Rest/binary>>, Ctx, KeyCtx) ->
    case parse_anchor_name(Rest) of
        {ok, Name, Rest1} ->
            Rest2 = skip_whitespace(Rest1),
            case parse_flow_key(Rest2, Ctx, KeyCtx) of
                {ok, Value, Rest3, Ctx1} ->
                    Ctx2 = nyaml_parser:set_anchor(Name, nyaml_merge:unmark(Value), Ctx1),
                    {ok, Value, Rest3, Ctx2};
                Error ->
                    Error
            end;
        {error, _} = Err ->
            Err
    end;
parse_flow_key(<<"*", Rest/binary>>, Ctx, _KeyCtx) ->
    maybe
        {ok, Name, Rest1} ?= parse_anchor_name(Rest),
        {ok, Value} ?= nyaml_parser:resolve_alias(Name, Ctx),
        {ok, Value, Rest1, Ctx}
    end;
parse_flow_key(Bin, Ctx, KeyCtx) ->
    case parse_scalar_key(Bin, KeyCtx) of
        {ok, Plain, Rest} ->
            {ok, Value} = nyaml_merge:resolve_key(Plain, Ctx),
            {ok, Value, Rest, Ctx};
        {error, _} = Err ->
            Err
    end.

-spec parse_flow_mapping_entry(binary(), nyaml_parser:ctx()) ->
    {ok, nyaml_merge:key(), yaml_value(), binary(), nyaml_parser:ctx()}
    | {error, parse_error()}
    | not_a_mapping.
parse_flow_mapping_entry(Bin, Ctx) ->
    case parse_flow_key(Bin, Ctx, flow_in) of
        {ok, Key, Rest, Ctx1} ->
            parse_flow_mapping_value(Key, skip_whitespace_and_comments(Rest), Ctx1);
        Error ->
            Error
    end.

-spec parse_flow_mapping_key(binary(), nyaml_parser:ctx()) ->
    {ok, nyaml_merge:key(), binary(), nyaml_parser:ctx()}
    | {error, parse_error()}
    | not_a_mapping.
parse_flow_mapping_key(<<"[", _/binary>> = Bin, Ctx) ->
    parse_sequence(Bin, Ctx);
parse_flow_mapping_key(<<"{", _/binary>> = Bin, Ctx) ->
    parse_mapping(Bin, Ctx);
parse_flow_mapping_key(Bin, Ctx) ->
    case parse_flow_key(Bin, Ctx, flow_key) of
        {ok, <<>>, _, _} -> not_a_mapping;
        Result -> Result
    end.

-spec parse_flow_mapping_value(nyaml_merge:key(), binary(), nyaml_parser:ctx()) ->
    {ok, nyaml_merge:key(), yaml_value(), binary(), nyaml_parser:ctx()} | {error, parse_error()}.
parse_flow_mapping_value(Key, <<":">>, Ctx) ->
    {ok, Key, null, <<>>, Ctx};
parse_flow_mapping_value(Key, <<":", C, Rest/binary>>, Ctx) when C =:= $,; C =:= $} ->
    {ok, Key, null, <<C, Rest/binary>>, Ctx};
parse_flow_mapping_value(Key, <<":", Rest/binary>>, Ctx) ->
    ValueRest = skip_whitespace(Rest),
    case ValueRest of
        <<>> ->
            {ok, Key, null, <<>>, Ctx};
        <<C, _/binary>> when C =:= $,; C =:= $} ->
            {ok, Key, null, ValueRest, Ctx};
        _ ->
            case parse_flow_value(ValueRest, Ctx) of
                {ok, Value, NextRest, Ctx1} ->
                    {ok, Key, Value, NextRest, Ctx1};
                Error ->
                    Error
            end
    end;
parse_flow_mapping_value(Key, <<C, _/binary>> = Rest, Ctx) when C =:= $,; C =:= $} ->
    {ok, Key, null, Rest, Ctx};
parse_flow_mapping_value(_Key, Other, _Ctx) ->
    {error, {expected_colon, Other}}.

-spec parse_flow_scalar_value(binary(), binary()) ->
    {ok, yaml_value(), binary()} | {error, unexpected_mapping_key_in_flow}.
parse_flow_scalar_value(<<C, _/binary>> = Rest, Acc) when C =:= $,; C =:= $}; C =:= $] ->
    {ok, resolve_scalar_value(strip_trailing_ws(Acc)), Rest};
parse_flow_scalar_value(<<":">>, Acc) ->
    {ok, resolve_scalar_value(strip_trailing_ws(Acc)), <<":">>};
parse_flow_scalar_value(<<":", C, _/binary>> = Rest, Acc) when
    C =:= $\s; C =:= $\t; C =:= $\r; C =:= $\n; C =:= $,; C =:= $}; C =:= $]
->
    case strip_trailing_ws(Acc) of
        <<>> -> {error, unexpected_mapping_key_in_flow};
        _ -> {ok, resolve_scalar_value(strip_trailing_ws(Acc)), Rest}
    end;
parse_flow_scalar_value(<<"\n", Rest/binary>>, Acc) ->
    TrimmedAcc = strip_trailing_ws(Acc),
    Rest1 = skip_leading_ws(Rest),
    case Rest1 of
        <<C, _/binary>> when C =:= $,; C =:= $}; C =:= $] ->
            {ok, resolve_scalar_value(TrimmedAcc), Rest1};
        <<"#", _/binary>> ->
            Rest2 = skip_ws_and_comments_flow(Rest),
            {ok, resolve_scalar_value(TrimmedAcc), Rest2};
        _ ->
            case looks_like_mapping_key(Rest1) of
                true ->
                    {ok, resolve_scalar_value(TrimmedAcc), Rest1};
                false ->
                    case TrimmedAcc of
                        <<>> -> parse_flow_scalar_value(Rest1, <<>>);
                        _ -> parse_flow_scalar_value(Rest1, <<TrimmedAcc/binary, " ">>)
                    end
            end
    end;
parse_flow_scalar_value(<<"\r\n", Rest/binary>>, Acc) ->
    parse_flow_scalar_value(<<"\n", Rest/binary>>, Acc);
parse_flow_scalar_value(<<C, Rest/binary>>, Acc) when C =:= $\s; C =:= $\t ->
    case check_after_whitespace(Rest) of
        comment ->
            {ok, resolve_scalar_value(strip_trailing_ws(Acc)), skip_to_comment_end(Rest)};
        flow_delimiter ->
            {ok, resolve_scalar_value(strip_trailing_ws(Acc)), skip_leading_ws(<<C, Rest/binary>>)};
        continue ->
            parse_flow_scalar_value(Rest, <<Acc/binary, C>>)
    end;
parse_flow_scalar_value(<<C, Rest/binary>>, Acc) ->
    parse_flow_scalar_value(Rest, <<Acc/binary, C>>);
parse_flow_scalar_value(<<>>, Acc) ->
    {ok, resolve_scalar_value(strip_trailing_ws(Acc)), <<>>}.

-spec parse_flow_value(binary(), nyaml_parser:ctx()) -> parse_result().
parse_flow_value(<<"[", _/binary>> = Bin, Ctx) ->
    parse_sequence(Bin, Ctx);
parse_flow_value(<<"{", _/binary>> = Bin, Ctx) ->
    parse_mapping(Bin, Ctx);
parse_flow_value(<<"\"", _/binary>> = Bin, Ctx) ->
    case nyaml_scalar:parse_quoted(Bin, double) of
        {ok, Value, Rest} -> {ok, Value, Rest, Ctx};
        {error, _} = Err -> Err
    end;
parse_flow_value(<<"'", _/binary>> = Bin, Ctx) ->
    case nyaml_scalar:parse_quoted(Bin, single) of
        {ok, Value, Rest} -> {ok, Value, Rest, Ctx};
        {error, _} = Err -> Err
    end;
parse_flow_value(<<"*", Rest/binary>>, Ctx) ->
    maybe
        {ok, Name, Rest1} ?= parse_anchor_name(Rest),
        {ok, Value} ?= nyaml_parser:resolve_alias(Name, Ctx),
        {ok, Value, Rest1, Ctx}
    end;
parse_flow_value(<<"&", Rest/binary>>, Ctx) ->
    maybe
        {ok, Name, Rest1} ?= parse_anchor_name(Rest),
        Rest2 = skip_whitespace_and_newlines(Rest1),
        {ok, Value, Rest3, Ctx1} ?= parse_flow_value(Rest2, Ctx),
        Ctx2 = nyaml_parser:set_anchor(Name, Value, Ctx1),
        {ok, Value, Rest3, Ctx2}
    end;
parse_flow_value(<<"!!", Rest/binary>>, Ctx) ->
    case parse_tag_name(Rest) of
        {ok, Tag, Rest1} ->
            Rest2 = skip_whitespace_and_newlines(Rest1),
            case Rest2 of
                <<C, _/binary>> when C =:= $,; C =:= $}; C =:= $] ->
                    maybe
                        {ok, Empty} ?= nyaml_parser:empty_node_value(Tag, Ctx),
                        {ok, Empty, Rest2, Ctx}
                    end;
                _ ->
                    maybe
                        {ok, InnerValue, Rest3, Ctx1} ?= parse_flow_value(Rest2, Ctx),
                        {ok, Resolved} ?= nyaml_parser:resolve_tag(Tag, InnerValue, Ctx),
                        {ok, Resolved, Rest3, Ctx1}
                    end
            end;
        {error, _} = Err ->
            Err
    end;
parse_flow_value(<<"!", Rest/binary>>, Ctx) when Rest =/= <<>> ->
    {ok, ValuePart} = skip_local_tag(Rest),
    Rest2 = skip_whitespace_and_newlines(ValuePart),
    parse_flow_value(Rest2, Ctx);
parse_flow_value(Bin, Ctx) ->
    case parse_flow_scalar_value(Bin, <<>>) of
        {ok, Value, Rest} -> {ok, Value, Rest, Ctx};
        {error, _} = Err -> Err
    end.

-spec parse_mapping_items(binary(), nyaml_merge:acc(), integer(), nyaml_parser:ctx()) ->
    parse_result().
parse_mapping_items(<<"}", Rest/binary>>, Acc, _Depth, Ctx) ->
    maybe
        {ok, Map} ?= nyaml_merge:close(Acc),
        {ok, Map, Rest, Ctx}
    end;
parse_mapping_items(<<C, Rest/binary>>, Acc, Depth, Ctx) when
    C =:= $\s; C =:= $\t; C =:= $\r; C =:= $\n
->
    parse_mapping_items(Rest, Acc, Depth, Ctx);
parse_mapping_items(<<",", Rest/binary>>, Acc, Depth, Ctx) ->
    parse_mapping_items(Rest, Acc, Depth, Ctx);
parse_mapping_items(<<"#", Rest/binary>>, Acc, Depth, Ctx) ->
    parse_mapping_items(skip_to_eol(Rest), Acc, Depth, Ctx);
parse_mapping_items(Bin, Acc, Depth, Ctx) ->
    case parse_flow_mapping_entry(Bin, Ctx) of
        {ok, Key, Value, Rest, Ctx1} ->
            NewAcc = nyaml_merge:add_entry(Key, Value, Acc),
            Rest1 = skip_whitespace_and_comments(Rest),
            case Rest1 of
                <<"}", _/binary>> ->
                    parse_mapping_items(Rest1, NewAcc, Depth, Ctx1);
                <<",", _/binary>> ->
                    parse_mapping_items(Rest1, NewAcc, Depth, Ctx1);
                <<>> ->
                    {error, unterminated_mapping};
                _ ->
                    {error, missing_comma_in_flow_mapping}
            end;
        {error, _} = Error ->
            Error
    end.

-spec parse_scalar_key(binary(), key_context()) ->
    {ok, binary(), binary()} | {error, parse_error()}.
parse_scalar_key(Bin, KeyCtx) ->
    parse_scalar_key(Bin, KeyCtx, <<>>, none, false).

-spec parse_scalar_key(binary(), key_context(), binary(), key_break(), boolean()) ->
    {ok, binary(), binary()} | {error, parse_error()}.
parse_scalar_key(<<C, _/binary>> = Rest, _KeyCtx, Acc, Break, _Spans) when
    C =:= $,; C =:= $}; C =:= $]; C =:= $[; C =:= ${
->
    {ok, strip_trailing_ws(Acc), unread_break(Break, Rest)};
parse_scalar_key(<<":", C, _/binary>> = Rest, KeyCtx, Acc, Break, Spans) when
    C =:= $\s; C =:= $\t; C =:= $\r; C =:= $\n; C =:= $,; C =:= $}; C =:= $]; C =:= $[; C =:= ${
->
    key_before_colon(KeyCtx, Acc, Break, Spans, Rest);
parse_scalar_key(<<":">> = Rest, KeyCtx, Acc, Break, Spans) ->
    key_before_colon(KeyCtx, Acc, Break, Spans, Rest);
parse_scalar_key(<<C, Rest/binary>> = Bin, KeyCtx, Acc, Break, Spans) when
    C =:= $\s; C =:= $\t
->
    case skip_ws_check_colon(Rest) of
        colon_sep ->
            key_before_colon(KeyCtx, Acc, Break, Spans, Bin);
        not_sep ->
            parse_scalar_key(Rest, KeyCtx, <<Acc/binary, C>>, Break, Spans)
    end;
parse_scalar_key(<<"\r\n", Rest/binary>> = Bin, KeyCtx, Acc, Break, Spans) ->
    fold_key_line(Bin, Rest, KeyCtx, Acc, Break, Spans);
parse_scalar_key(<<"\n", Rest/binary>> = Bin, KeyCtx, Acc, Break, Spans) ->
    fold_key_line(Bin, Rest, KeyCtx, Acc, Break, Spans);
parse_scalar_key(<<C, Rest/binary>>, KeyCtx, Acc, Break, Spans) ->
    parse_scalar_key(Rest, KeyCtx, <<Acc/binary, C>>, none, Spans orelse Break =/= none);
parse_scalar_key(<<>>, _KeyCtx, Acc, Break, _Spans) ->
    {ok, strip_trailing_ws(Acc), unread_break(Break, <<>>)}.

-spec parse_sequence_items(binary(), [yaml_value()], integer(), nyaml_parser:ctx()) ->
    parse_result().
parse_sequence_items(<<>>, _Acc, _Depth, _Ctx) ->
    {error, unterminated_sequence};
parse_sequence_items(<<"]", Rest/binary>>, [], _Depth, Ctx) ->
    {ok, [], Rest, Ctx};
parse_sequence_items(<<C, Rest/binary>>, Acc, Depth, Ctx) when
    C =:= $\s; C =:= $\t; C =:= $\r; C =:= $\n
->
    parse_sequence_items(Rest, Acc, Depth, Ctx);
parse_sequence_items(<<"]#", _/binary>>, _Acc, _Depth, _Ctx) ->
    {error, invalid_comment_after_bracket};
parse_sequence_items(<<"]", Rest/binary>>, Acc, _Depth, Ctx) ->
    {ok, lists:reverse(Acc), Rest, Ctx};
parse_sequence_items(<<",", "#", _/binary>>, _Acc, _Depth, _Ctx) ->
    {error, invalid_comment_after_comma};
parse_sequence_items(<<",", Rest/binary>>, [], _Depth, _Ctx) ->
    case skip_whitespace(Rest) of
        <<"]", _/binary>> ->
            {error, empty_sequence_with_comma};
        _ ->
            {error, invalid_leading_comma_in_sequence}
    end;
parse_sequence_items(<<",", Rest/binary>>, Acc, Depth, Ctx) ->
    Rest1 = skip_whitespace_and_comments(Rest),
    case Rest1 of
        <<",", _/binary>> ->
            {error, consecutive_commas_in_sequence};
        <<"]", _/binary>> ->
            parse_sequence_items(Rest1, Acc, Depth, Ctx);
        _ ->
            parse_sequence_items(Rest1, Acc, Depth, Ctx)
    end;
parse_sequence_items(<<"[", _/binary>> = Bin, Acc, Depth, Ctx) ->
    case parse_sequence(Bin, Ctx) of
        {ok, Value, Rest, Ctx1} ->
            parse_sequence_items(Rest, [Value | Acc], Depth, Ctx1);
        Error ->
            Error
    end;
parse_sequence_items(<<"{", _/binary>> = Bin, Acc, Depth, Ctx) ->
    case parse_mapping(Bin, Ctx) of
        {ok, Value, Rest, Ctx1} ->
            parse_sequence_items(Rest, [Value | Acc], Depth, Ctx1);
        Error ->
            Error
    end;
parse_sequence_items(<<"-", C, _/binary>>, _Acc, _Depth, _Ctx) when
    C =:= $]; C =:= $,; C =:= $\s; C =:= $\t; C =:= $\n; C =:= $\r
->
    {error, bare_dash_in_flow_sequence};
parse_sequence_items(<<"-]", _/binary>>, _Acc, _Depth, _Ctx) ->
    {error, bare_dash_in_flow_sequence};
parse_sequence_items(Bin, Acc, Depth, Ctx) ->
    case try_parse_implicit_mapping(Bin, Ctx) of
        {ok, Map, Rest, Ctx1} ->
            validate_flow_sequence_continuation(Map, Rest, Acc, Depth, Ctx1);
        {error, _} = Error ->
            Error;
        not_a_mapping ->
            case parse_flow_value(Bin, Ctx) of
                {ok, Value, Rest, Ctx1} ->
                    validate_flow_sequence_continuation(Value, Rest, Acc, Depth, Ctx1);
                Error ->
                    Error
            end
    end.

-spec parse_tag_name(binary()) -> {ok, binary(), binary()} | {error, parse_error()}.
parse_tag_name(Bin) ->
    parse_tag_name(Bin, <<>>).

-spec parse_tag_name(binary(), binary()) -> {ok, binary(), binary()} | {error, parse_error()}.
parse_tag_name(<<C, Rest/binary>>, Acc) when
    (C >= $a andalso C =< $z) orelse
        (C >= $A andalso C =< $Z) orelse
        (C >= $0 andalso C =< $9) orelse
        C =:= $- orelse C =:= $_
->
    parse_tag_name(Rest, <<Acc/binary, C>>);
parse_tag_name(Rest, <<>>) ->
    {error, {invalid_tag_name, Rest}};
parse_tag_name(Rest, Acc) ->
    {ok, Acc, Rest}.

-spec resolve_scalar_value(binary()) -> nyaml_scalar:scalar_value().
resolve_scalar_value(<<>>) ->
    null;
resolve_scalar_value(Bin) ->
    {ok, Value} = nyaml_scalar:parse(Bin),
    Value.

-spec single_entry_mapping(nyaml_merge:key(), yaml_value(), binary(), nyaml_parser:ctx()) ->
    {ok, #{yaml_value() => yaml_value()}, binary(), nyaml_parser:ctx()}
    | {error, nyaml_merge:merge_error()}.
single_entry_mapping(Key, Value, Rest, Ctx) ->
    Acc = nyaml_merge:add_entry(Key, Value, nyaml_merge:new(#{})),
    maybe
        {ok, Map} ?= nyaml_merge:close(Acc),
        {ok, Map, Rest, Ctx}
    end.

-spec skip_comment_content(binary()) -> binary().
skip_comment_content(<<"\n", Rest/binary>>) -> <<"\n", Rest/binary>>;
skip_comment_content(<<"\r\n", Rest/binary>>) -> <<"\r\n", Rest/binary>>;
skip_comment_content(<<_, Rest/binary>>) -> skip_comment_content(Rest);
skip_comment_content(<<>>) -> <<>>.

-spec skip_leading_ws(binary()) -> binary().
skip_leading_ws(<<C, Rest/binary>>) when C =:= $\s; C =:= $\t ->
    skip_leading_ws(Rest);
skip_leading_ws(Bin) ->
    Bin.

-spec skip_local_tag(binary()) -> {ok, binary()}.
skip_local_tag(Bin) ->
    skip_local_tag(Bin, <<>>).

-spec skip_local_tag(binary(), binary()) -> {ok, binary()}.
skip_local_tag(<<C, Rest/binary>>, _Acc) when C =:= $\s; C =:= $\t; C =:= $\n; C =:= $\r ->
    {ok, Rest};
skip_local_tag(<<C, _/binary>> = Rest, _Acc) when
    C =:= $,; C =:= $}; C =:= $]; C =:= $[; C =:= ${
->
    {ok, Rest};
skip_local_tag(<<C, Rest/binary>>, Acc) ->
    skip_local_tag(Rest, <<Acc/binary, C>>);
skip_local_tag(<<>>, _Acc) ->
    {ok, <<>>}.

-spec skip_to_comment_end(binary()) -> binary().
skip_to_comment_end(<<"\n", Rest/binary>>) -> <<"\n", Rest/binary>>;
skip_to_comment_end(<<"\r\n", Rest/binary>>) -> <<"\r\n", Rest/binary>>;
skip_to_comment_end(<<"#", Rest/binary>>) -> skip_comment_content(Rest);
skip_to_comment_end(<<_, Rest/binary>>) -> skip_to_comment_end(Rest);
skip_to_comment_end(<<>>) -> <<>>.

-spec skip_to_eol(binary()) -> binary().
skip_to_eol(<<"\n", Rest/binary>>) -> skip_whitespace(Rest);
skip_to_eol(<<"\r\n", Rest/binary>>) -> skip_whitespace(Rest);
skip_to_eol(<<>>) -> <<>>;
skip_to_eol(<<_, Rest/binary>>) -> skip_to_eol(Rest).

-spec skip_to_next_line(binary()) -> binary().
skip_to_next_line(<<"\n", Rest/binary>>) -> Rest;
skip_to_next_line(<<"\r\n", Rest/binary>>) -> Rest;
skip_to_next_line(<<_, Rest/binary>>) -> skip_to_next_line(Rest);
skip_to_next_line(<<>>) -> <<>>.

-spec skip_whitespace(binary()) -> binary().
skip_whitespace(<<C, Rest/binary>>) when C =:= $\s; C =:= $\t; C =:= $\r; C =:= $\n ->
    skip_whitespace(Rest);
skip_whitespace(Bin) ->
    Bin.

-spec skip_whitespace_and_comments(binary()) -> binary().
skip_whitespace_and_comments(Bin) ->
    case skip_whitespace(Bin) of
        <<"#", Rest/binary>> ->
            skip_whitespace_and_comments(skip_to_eol(Rest));
        Other ->
            Other
    end.

-spec skip_whitespace_and_newlines(binary()) -> binary().
skip_whitespace_and_newlines(<<C, Rest/binary>>) when C =:= $\s; C =:= $\t; C =:= $\n; C =:= $\r ->
    skip_whitespace_and_newlines(Rest);
skip_whitespace_and_newlines(Bin) ->
    Bin.

-spec skip_whitespace_check_newline(binary()) -> {newline, binary()} | {no_newline, binary()}.
skip_whitespace_check_newline(Bin) ->
    skip_whitespace_check_newline(Bin, false).

-spec skip_whitespace_check_newline(binary(), boolean()) ->
    {newline, binary()} | {no_newline, binary()}.
skip_whitespace_check_newline(<<C, Rest/binary>>, SeenNewline) when C =:= $\s; C =:= $\t ->
    skip_whitespace_check_newline(Rest, SeenNewline);
skip_whitespace_check_newline(<<"\r\n", Rest/binary>>, _SeenNewline) ->
    skip_whitespace_check_newline(Rest, true);
skip_whitespace_check_newline(<<"\n", Rest/binary>>, _SeenNewline) ->
    skip_whitespace_check_newline(Rest, true);
skip_whitespace_check_newline(Rest, true) ->
    {newline, Rest};
skip_whitespace_check_newline(Rest, false) ->
    {no_newline, Rest}.

-spec skip_ws_and_comments_flow(binary()) -> binary().
skip_ws_and_comments_flow(Bin) ->
    Bin1 = skip_leading_ws(Bin),
    case Bin1 of
        <<"#", Rest/binary>> ->
            skip_ws_and_comments_flow(skip_to_next_line(Rest));
        <<"\n", Rest/binary>> ->
            skip_ws_and_comments_flow(Rest);
        <<"\r\n", Rest/binary>> ->
            skip_ws_and_comments_flow(Rest);
        _ ->
            Bin1
    end.

-spec skip_ws_check_colon(binary()) -> colon_sep | not_sep.
skip_ws_check_colon(<<C, Rest/binary>>) when C =:= $\s; C =:= $\t ->
    skip_ws_check_colon(Rest);
skip_ws_check_colon(<<":", C, _/binary>>) when
    C =:= $\s; C =:= $\t; C =:= $\r; C =:= $\n; C =:= $,; C =:= $}; C =:= $]; C =:= $[; C =:= ${
->
    colon_sep;
skip_ws_check_colon(<<":">>) ->
    colon_sep;
skip_ws_check_colon(_) ->
    not_sep.

-spec strip_trailing_ws(binary()) -> binary().
strip_trailing_ws(<<>>) ->
    <<>>;
strip_trailing_ws(Bin) ->
    case binary:last(Bin) of
        C when C =:= $\s; C =:= $\t ->
            strip_trailing_ws(binary:part(Bin, 0, byte_size(Bin) - 1));
        _ ->
            Bin
    end.

-spec try_parse_implicit_mapping(binary(), nyaml_parser:ctx()) ->
    {ok, #{yaml_value() => yaml_value()}, binary(), nyaml_parser:ctx()}
    | {error, parse_error()}
    | not_a_mapping.
try_parse_implicit_mapping(<<":", C, Rest/binary>>, Ctx) when C =:= $\s; C =:= $\t ->
    case parse_flow_value(skip_whitespace(Rest), Ctx) of
        {ok, Value, NextRest, Ctx1} ->
            {ok, #{null => Value}, NextRest, Ctx1};
        _Error ->
            not_a_mapping
    end;
try_parse_implicit_mapping(Bin, Ctx) ->
    case parse_flow_mapping_key(Bin, Ctx) of
        {ok, Key, Rest, Ctx1} ->
            case skip_whitespace_check_newline(Rest) of
                {newline, <<":", _/binary>>} ->
                    {error, implicit_key_spans_lines};
                {newline, _Rest1} ->
                    not_a_mapping;
                {no_newline, <<":", ValueRest/binary>>} ->
                    case parse_flow_value(skip_whitespace(ValueRest), Ctx1) of
                        {ok, Value, NextRest, Ctx2} ->
                            single_entry_mapping(Key, Value, NextRest, Ctx2);
                        _Error ->
                            not_a_mapping
                    end;
                {no_newline, _} ->
                    not_a_mapping
            end;
        {error, implicit_key_spans_lines} = Err ->
            Err;
        _ ->
            not_a_mapping
    end.

-spec unread_break(key_break(), binary()) -> binary().
unread_break(none, Bin) ->
    Bin;
unread_break(Break, _Bin) ->
    Break.

-spec validate_flow_sequence_continuation(
    yaml_value(), binary(), [yaml_value()], integer(), nyaml_parser:ctx()
) ->
    parse_result().
validate_flow_sequence_continuation(Value, Rest, Acc, Depth, Ctx) ->
    Rest1 = skip_whitespace_and_comments(Rest),
    case Rest1 of
        <<"]", _/binary>> ->
            parse_sequence_items(Rest1, [Value | Acc], Depth, Ctx);
        <<",", _/binary>> ->
            parse_sequence_items(Rest1, [Value | Acc], Depth, Ctx);
        <<>> ->
            {error, unterminated_sequence};
        _ ->
            {error, missing_comma_in_flow_sequence}
    end.
