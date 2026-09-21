-module(nyaml_roundtrip_tests).

-include_lib("eunit/include/eunit.hrl").

-undef(LET).

-include_lib("proper/include/proper.hrl").

-define(NUM_TESTS, 500).
-define(MAX_DEPTH, 6).

%%%-----------------------------------------------------------------------------
%% EUNIT ENTRY POINTS
%%%-----------------------------------------------------------------------------

round_trip_test_() ->
    {timeout, 300, ?_assert(quickcheck(prop_round_trip()))}.

encode_total_test_() ->
    {timeout, 300, ?_assert(quickcheck(prop_encode_total()))}.

binary_round_trip_test_() ->
    {timeout, 300, ?_assert(quickcheck(prop_binary_round_trip()))}.

quickcheck(Prop) ->
    proper:quickcheck(Prop, [{numtests, ?NUM_TESTS}, {to_file, user}]).

%%%-----------------------------------------------------------------------------
%% PROPERTIES
%%%-----------------------------------------------------------------------------

prop_round_trip() ->
    ?FORALL(
        Term,
        yaml_value(reproducible),
        begin
            {ok, Yaml} = nyaml:encode(Term),
            Decoded = nyaml:decode(Yaml),
            ?WHENFAIL(
                io:format("term:    ~p~nyaml:    ~p~ndecoded: ~p~n", [Term, Yaml, Decoded]),
                Decoded =:= {ok, Term}
            )
        end
    ).

prop_binary_round_trip() ->
    ?FORALL(
        Term,
        extended_yaml_value(),
        begin
            {ok, Yaml} = nyaml:encode(Term),
            Decoded = nyaml:decode(Yaml, #{schema => extended}),
            ?WHENFAIL(
                io:format("term:    ~p~nyaml:    ~p~ndecoded: ~p~n", [Term, Yaml, Decoded]),
                Decoded =:= {ok, Term}
            )
        end
    ).

prop_encode_total() ->
    ?FORALL(
        Term,
        yaml_value(all),
        begin
            Result = encode_result(Term),
            ?WHENFAIL(
                io:format("term:   ~p~nresult: ~p~n", [Term, Result]),
                Result =:= ok
            )
        end
    ).

encode_result(Term) ->
    try nyaml:encode(Term) of
        {ok, Yaml} when is_binary(Yaml) ->
            case nyaml:decode(Yaml) of
                {ok, _} -> ok;
                {error, Reason} -> {decode_failed, Yaml, Reason}
            end
    catch
        Class:Reason:Stack -> {encode_crashed, Class, Reason, Stack}
    end.

%%%-----------------------------------------------------------------------------
%% GENERATORS
%%%-----------------------------------------------------------------------------

yaml_value(Keys) ->
    ?SIZED(Size, value(min(Size, ?MAX_DEPTH), Keys)).

value(Size, _Keys) when Size =< 0 ->
    scalar();
value(Size, Keys) ->
    frequency([
        {4, scalar()},
        {1, ?LAZY(resize(Size, list(value(Size div 2, Keys))))},
        {1, ?LAZY(mapping(Size, Keys))}
    ]).

mapping(Size, Keys) ->
    ?LET(
        Pairs,
        resize(Size, list({key(Size, Keys), value(Size div 2, Keys)})),
        maps:from_list(Pairs)
    ).

key(Size, Keys) ->
    frequency([
        {8, key_scalar(Keys)},
        {1, ?LAZY(resize(Size, list(value(Size div 2, Keys))))},
        {1, ?LAZY(mapping(Size div 2, Keys))}
    ]).

key_scalar(reproducible) -> yaml_string();
key_scalar(all) -> scalar().

scalar() ->
    frequency([
        {2, oneof([null, true, false, infinity, negative_infinity, nan])},
        {3, integer()},
        {1, ?LET(N, integer(), N * N * N * 1000000000)},
        {3, float()},
        {2, datetime()},
        {12, yaml_string()}
    ]).

binary_node() ->
    ?LET(Bytes, binary(), {binary, Bytes}).

extended_yaml_value() ->
    ?SIZED(Size, extended_value(min(Size, ?MAX_DEPTH))).

extended_value(Size) when Size =< 0 ->
    extended_scalar();
extended_value(Size) ->
    frequency([
        {4, extended_scalar()},
        {1, ?LAZY(resize(Size, list(extended_value(Size div 2))))},
        {1, ?LAZY(extended_mapping(Size))}
    ]).

extended_mapping(Size) ->
    ?LET(
        Pairs,
        resize(Size, list({extended_key(Size), extended_value(Size div 2)})),
        maps:from_list(Pairs)
    ).

extended_key(Size) ->
    frequency([
        {6, yaml_string()},
        {2, binary_node()},
        {1, ?LAZY(resize(Size, list(extended_value(Size div 2))))},
        {1, ?LAZY(extended_mapping(Size div 2))}
    ]).

extended_scalar() ->
    frequency([{2, binary_node()}, {3, scalar()}]).

datetime() ->
    ?LET(
        {Y, Mo, D, H, Mi, S},
        {range(1, 9999), range(1, 12), range(1, 28), range(0, 23), range(0, 59), range(0, 59)},
        {{Y, Mo, D}, {H, Mi, S}}
    ).

yaml_string() ->
    frequency([
        {2, oneof(indicator_strings())},
        {3, ?LET(Chars, list(yaml_char()), to_binary(Chars))}
    ]).

yaml_char() ->
    frequency([
        {10, range($a, $z)},
        {2, range($0, $9)},
        {8, oneof(indicator_chars())},
        {3, range(16#A0, 16#D7FF)},
        {1, range(16#E000, 16#FFFD)},
        {1, range(16#10000, 16#10FFFF)},
        {2, range(0, 16#1F)}
    ]).

indicator_chars() ->
    [
        $\s,
        $\t,
        $\n,
        $:,
        $-,
        $#,
        $',
        $",
        $\\,
        $,,
        $[,
        $],
        ${,
        $},
        $?,
        $*,
        $&,
        $|,
        $>,
        $%,
        $@,
        $`,
        $!,
        $.,
        16#85,
        16#FEFF
    ].

indicator_strings() ->
    [
        <<>>,
        <<"null">>,
        <<"~">>,
        <<"true">>,
        <<"false">>,
        <<"yes">>,
        <<"no">>,
        <<"on">>,
        <<"off">>,
        <<"Null">>,
        <<"NO">>,
        <<"0">>,
        <<"1.0">>,
        <<"0x10">>,
        <<"0o17">>,
        <<"-0">>,
        <<"1e3">>,
        <<".inf">>,
        <<"-.inf">>,
        <<".nan">>,
        <<"2001-12-14">>,
        <<"2001-12-14T21:59:43Z">>,
        <<"---">>,
        <<"--- x">>,
        <<"...">>,
        <<"...ellipsis">>,
        <<"[]">>,
        <<"{}">>,
        <<"[1, 2]">>,
        <<"{a: 1}">>,
        <<"- item">>,
        <<"a: b">>,
        <<"a:b">>,
        <<"x:">>,
        <<"# comment">>,
        <<"a # comment">>,
        <<"? key">>,
        <<"&anchor">>,
        <<"*alias">>,
        <<"!!str">>,
        <<"%YAML 1.2">>,
        <<"|literal">>,
        <<">folded">>,
        <<" leading">>,
        <<"trailing ">>,
        <<"\ttab">>,
        <<"multi\nline">>,
        <<"crlf\r\n">>,
        <<"'single'">>,
        <<"\"double\"">>,
        <<"back\\slash">>
    ].

to_binary(Chars) ->
    case unicode:characters_to_binary(Chars) of
        Bin when is_binary(Bin) -> Bin;
        {error, _, _} -> <<>>;
        {incomplete, _, _} -> <<>>
    end.
