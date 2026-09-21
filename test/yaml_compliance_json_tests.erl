-module(yaml_compliance_json_tests).

-include_lib("eunit/include/eunit.hrl").

-define(CONCATENATED_IDS, [
    "35KP",
    "5TYM",
    "6WLZ",
    "6XDY",
    "6ZKB",
    "7Z25",
    "8G76",
    "98YD",
    "9DXL",
    "9KAX",
    "9WXW",
    "AVM7",
    "HWV9",
    "JHB9",
    "KSS4",
    "L383",
    "M7A3",
    "PUW8",
    "QT73",
    "RZT7",
    "U9NS",
    "UT92",
    "W4TN"
]).

%% parse_expected_json/1 returns the value itself for a single JSON document
single_document_test_() ->
    [
        ?_assertEqual({ok, #{<<"a">> => 1}}, parse(<<"{\"a\": 1}\n">>)),
        ?_assertEqual({ok, [1, 2]}, parse(<<"[1, 2]\n">>)),
        ?_assertEqual({ok, null}, parse(<<"null\n">>))
    ].

%% parse_expected_json/1 returns the list of values for a stream of JSON documents
multi_document_test_() ->
    [
        ?_assertEqual({ok, [#{<<"a">> => 1}, [2, 3]]}, parse(<<"{\"a\": 1}\n[2, 3]\n">>)),
        ?_assertEqual(
            {ok, [<<"one">>, <<"two">>, <<"three">>]},
            parse(<<"\"one\"\n\"two\"\n\"three\"\n">>)
        ),
        ?_assertEqual({ok, [[1, 2], [3, 4]]}, parse(<<"[1, 2]\n[3, 4]\n">>))
    ].

%% parse_expected_json/1 reads an empty expectation as a stream of no documents
empty_stream_test_() ->
    [
        ?_assertEqual({ok, []}, parse(<<>>)),
        ?_assertEqual({ok, []}, parse(<<"\n  \t\r\n">>))
    ].

%% parse_expected_json/1 refuses a remainder that is neither whitespace nor a value
trailing_garbage_test_() ->
    [
        ?_assertMatch({error, _}, parse(<<"{\"a\": 1} oops">>)),
        ?_assertMatch({error, _}, parse(<<"[1, 2]\n{">>)),
        ?_assertMatch({error, _}, parse(<<"oops">>))
    ].

%% Every fixture whose in.json holds concatenated documents now loads
concatenated_fixtures_test_() ->
    [
        ?_assertMatch({Id, {ok, _}}, {Id, parse(read_expectation(Id))})
     || Id <- ?CONCATENATED_IDS
    ].

parse(JsonBin) ->
    yaml_compliance_SUITE:parse_expected_json(JsonBin).

read_expectation(Id) ->
    Path = filename:join([fixture_dir(), Id, "in.json"]),
    {ok, JsonBin} = file:read_file(Path),
    JsonBin.

fixture_dir() ->
    {ok, Cwd} = file:get_cwd(),
    filename:join(project_root(Cwd), "test/fixtures/yaml-test-suite").

project_root("/") ->
    erlang:error(no_rebar_config_found);
project_root(Dir) ->
    case filelib:is_regular(filename:join(Dir, "rebar.config")) of
        true -> Dir;
        false -> project_root(filename:dirname(Dir))
    end.
