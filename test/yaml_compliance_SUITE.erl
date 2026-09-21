%%% yaml_compliance_SUITE.erl - YAML 1.2 specification compliance tests
%%% Uses the official yaml-test-suite from https://github.com/yaml/yaml-test-suite
-module(yaml_compliance_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([
    all/0,
    groups/0,
    init_per_suite/1,
    end_per_suite/1,
    init_per_group/2,
    end_per_group/2
]).

-export([
    discovery_is_total/1,
    discovery_rejects_a_broken_fixture/1,
    valid_tests/1,
    invalid_tests/1,
    round_trip_tests/1
]).

-export([
    parse_expected_json/1
]).

-define(SUITE_DIR, "test/fixtures/yaml-test-suite").
-define(FLOAT_EPSILON, 1.0e-10).

%% The fixture tree holds 333 cases at the first level and 69 one level down.
%% An unasserted count let the suite report success while it ran 333 of them.
-define(EXPECTED_CASE_COUNT, 402).

%% The split that `README.md`, the badge, and `CHANGELOG.md` publish.
-define(EXPECTED_VALID_COUNT, 308).
-define(EXPECTED_INVALID_COUNT, 94).

%% name/ and tags/ hold symbolic links back into the same cases under a
%% readable name and under a category. They are not cases.
-define(LINK_DIRS, ["name", "tags"]).

-type test_case() :: #{
    id := binary(),
    name := binary(),
    yaml := binary(),
    expected := term() | error | no_json,
    type := valid | invalid
}.

-type test_result() :: pass | {fail, term()}.

-type case_dir() :: {binary(), file:filename()}.

-type discovery_error() ::
    {list_dir_failed, file:filename(), file:posix() | badarg}
    | {load_failed, file:filename(), term()}.

%%% ============================================================
%%% CT Callbacks
%%% ============================================================

-spec all() -> [atom() | {group, atom()}].
all() ->
    [discovery_is_total, discovery_rejects_a_broken_fixture, {group, compliance}].

-spec groups() -> [{atom(), [atom()], [atom()]}].
groups() ->
    [{compliance, [sequence], [valid_tests, invalid_tests, round_trip_tests]}].

-spec init_per_suite(ct:config()) -> ct:config().
init_per_suite(Config) ->
    SuiteDir = get_suite_dir(Config),
    case filelib:is_dir(SuiteDir) of
        true -> init_with_tests(SuiteDir, Config);
        false -> ct:fail({test_suite_not_found, SuiteDir})
    end.

-spec init_with_tests(file:filename(), ct:config()) -> ct:config().
init_with_tests(SuiteDir, Config) ->
    case discover_tests(SuiteDir) of
        {error, Reason} ->
            ct:fail({discovery_failed, SuiteDir, Reason});
        {ok, Tests} when map_size(Tests) =/= ?EXPECTED_CASE_COUNT ->
            ct:fail({unexpected_case_count, map_size(Tests), expected, ?EXPECTED_CASE_COUNT});
        {ok, Tests} ->
            ct:pal("Discovered ~p compliance cases in ~s", [map_size(Tests), SuiteDir]),
            [{tests, Tests}, {suite_dir, SuiteDir} | Config]
    end.

-spec end_per_suite(ct:config()) -> ok.
end_per_suite(_Config) ->
    ok.

-spec init_per_group(atom(), ct:config()) -> ct:config().
init_per_group(_Group, Config) ->
    Config.

-spec end_per_group(atom(), ct:config()) -> ok.
end_per_group(_Group, _Config) ->
    ok.

%%% ============================================================
%%% Test Case Functions
%%% ============================================================

%% Discovery reaches both levels of the fixture tree and counts no symbolic link.
-spec discovery_is_total(ct:config()) -> ok.
discovery_is_total(Config) ->
    Tests = proplists:get_value(tests, Config),
    Ids = maps:keys(Tests),
    Nested = [Id || Id <- Ids, binary:match(Id, <<"/">>) =/= nomatch],
    ?assertEqual(?EXPECTED_CASE_COUNT, length(Ids)),
    ?assertEqual(69, length(Nested)),
    ?assert(maps:is_key(<<"MUS6/02">>, Tests)),
    ?assert(maps:is_key(<<"Y79Y/000">>, Tests)),
    ?assertEqual([], [Id || Id <- Ids, came_through_a_link(Id)]),
    ?assertEqual(?EXPECTED_VALID_COUNT, count_of_type(Tests, valid)),
    ?assertEqual(?EXPECTED_INVALID_COUNT, count_of_type(Tests, invalid)),
    ok.

-spec count_of_type(#{binary() => test_case()}, valid | invalid) -> non_neg_integer().
count_of_type(Tests, Type) ->
    map_size(maps:filter(fun(_Id, #{type := T}) -> T =:= Type end, Tests)).

%% A case id is four characters wide, or a parent and a child joined by a slash.
%% Anything else came through the readable names that name/ holds.
-spec came_through_a_link(binary()) -> boolean().
came_through_a_link(Id) ->
    byte_size(Id) =/= 4 andalso binary:match(Id, <<"/">>) =:= nomatch.

%% A fixture that cannot be loaded fails discovery instead of leaving the suite.
-spec discovery_rejects_a_broken_fixture(ct:config()) -> ok.
discovery_rejects_a_broken_fixture(Config) ->
    PrivDir = proplists:get_value(priv_dir, Config),
    Root = filename:join(PrivDir, "broken_fixture_tree"),
    CaseDir = filename:join(Root, "AAAA"),
    ok = filelib:ensure_path(CaseDir),
    ok = file:write_file(filename:join(CaseDir, "in.yaml"), <<"a: 1\n">>),
    ok = file:write_file(filename:join(CaseDir, "in.json"), <<"{oops">>),
    ?assertMatch({error, {load_failed, CaseDir, {json_parse_error, _}}}, discover_tests(Root)),
    ok.

-spec valid_tests(ct:config()) -> ok.
valid_tests(Config) ->
    Tests = proplists:get_value(tests, Config),
    ValidTests = maps:filter(fun(_K, #{type := T}) -> T =:= valid end, Tests),
    Results = maps:fold(
        fun(Id, TestCase, Acc) ->
            Result = run_valid_test(TestCase),
            [{Id, Result} | Acc]
        end,
        [],
        ValidTests
    ),
    generate_test_report(<<"Valid Tests">>, Results),
    check_results(Results).

-spec invalid_tests(ct:config()) -> ok.
invalid_tests(Config) ->
    Tests = proplists:get_value(tests, Config),
    InvalidTests = maps:filter(fun(_K, #{type := T}) -> T =:= invalid end, Tests),
    Results = maps:fold(
        fun(Id, TestCase, Acc) ->
            Result = run_invalid_test(TestCase),
            [{Id, Result} | Acc]
        end,
        [],
        InvalidTests
    ),
    generate_test_report(<<"Invalid Tests">>, Results),
    check_results(Results).

-spec round_trip_tests(ct:config()) -> ok.
round_trip_tests(Config) ->
    Tests = proplists:get_value(tests, Config),
    ValidTests = maps:filter(fun(_K, #{type := T}) -> T =:= valid end, Tests),
    Results = maps:fold(
        fun(Id, TestCase, Acc) ->
            Result = run_round_trip_test(TestCase),
            [{Id, Result} | Acc]
        end,
        [],
        ValidTests
    ),
    generate_test_report(<<"Round Trip Tests">>, Results),
    check_results(Results).

%%% ============================================================
%%% Test Execution
%%% ============================================================

-spec run_valid_test(test_case()) -> test_result().
run_valid_test(#{id := Id, yaml := Yaml, expected := Expected}) ->
    case run_with_timeout(fun() -> nyaml:decode_all(Yaml) end, 5000) of
        {ok, Documents} ->
            compare_documents(Id, Documents, Expected);
        {error, Reason} ->
            {fail, {Id, parse_failed, Reason}};
        timeout ->
            {fail, {Id, timeout}}
    end.

-spec run_invalid_test(test_case()) -> test_result().
run_invalid_test(#{id := Id, yaml := Yaml}) ->
    case run_with_timeout(fun() -> nyaml:decode(Yaml) end, 5000) of
        {error, _Reason} ->
            pass;
        {ok, Result} ->
            {fail, {Id, expected_error, got, Result}};
        timeout ->
            {fail, {Id, timeout}}
    end.

-spec run_round_trip_test(test_case()) -> test_result().
run_round_trip_test(#{id := Id, yaml := Yaml}) ->
    case run_with_timeout(fun() -> nyaml:decode_all(Yaml) end, 5000) of
        {ok, Documents} -> round_trip_documents(Id, Documents);
        {error, Reason} -> {fail, {Id, round_trip_input_did_not_decode, Reason}};
        timeout -> {fail, {Id, round_trip_decode_timeout}}
    end.

-spec round_trip_documents(binary(), [term()]) -> test_result().
round_trip_documents(_Id, []) ->
    pass;
round_trip_documents(Id, [Document | Rest]) ->
    case round_trip_document(Id, Document) of
        pass -> round_trip_documents(Id, Rest);
        Failure -> Failure
    end.

-spec round_trip_document(binary(), term()) -> test_result().
round_trip_document(Id, Document) ->
    case run_with_timeout(fun() -> encode_and_decode(Document) end, 5000) of
        {ok, Document, _Yaml} ->
            pass;
        {ok, Other, Yaml} ->
            {fail, {Id, round_trip_mismatch, term, Document, emitted, Yaml, got, Other}};
        {parse_error, Reason, Yaml} ->
            {fail, {Id, emitted_yaml_rejected, Reason, emitted, Yaml}};
        {emit_error, ClassReason, Stack} ->
            {fail, {Id, emit_crashed, ClassReason, Stack}};
        timeout ->
            {fail, {Id, round_trip_timeout}}
    end.

-spec encode_and_decode(term()) ->
    {ok, term(), binary()} | {parse_error, term(), binary()} | {emit_error, term(), term()}.
encode_and_decode(Document) ->
    try nyaml:encode(Document) of
        {ok, Yaml} ->
            case nyaml:decode(Yaml) of
                {ok, Decoded} -> {ok, Decoded, Yaml};
                {error, Reason} -> {parse_error, Reason, Yaml}
            end
    catch
        Class:Reason:Stack -> {emit_error, {Class, Reason}, Stack}
    end.

-spec run_with_timeout(fun(() -> term()), pos_integer()) -> term() | timeout.
run_with_timeout(Fun, TimeoutMs) ->
    Parent = self(),
    Ref = make_ref(),
    Pid = spawn(fun() -> Parent ! {Ref, Fun()} end),
    receive
        {Ref, Result} -> Result
    after TimeoutMs ->
        exit(Pid, kill),
        timeout
    end.

%%% ============================================================
%%% Test Discovery
%%% ============================================================

-spec discover_tests(file:filename()) ->
    {ok, #{binary() => test_case()}} | {error, discovery_error()}.
discover_tests(SuiteDir) ->
    maybe
        {ok, Cases} ?= case_dirs(SuiteDir),
        load_test_cases(Cases, #{})
    end.

-spec case_dirs(file:filename()) -> {ok, [case_dir()]} | {error, discovery_error()}.
case_dirs(SuiteDir) ->
    maybe
        {ok, Entries} ?= list_dir(SuiteDir),
        Candidates = [E || E <- Entries, not lists:member(E, ?LINK_DIRS)],
        collect_case_dirs(SuiteDir, Candidates, [])
    end.

%% A directory holding an in.yaml is a case, and a directory holding none is
%% scanned one level down. The walk stops there: name/ and tags/ hold symbolic
%% links back into the same cases, so a deeper walk counts every case again.
-spec collect_case_dirs(file:filename(), [file:filename()], [case_dir()]) ->
    {ok, [case_dir()]} | {error, discovery_error()}.
collect_case_dirs(_Parent, [], Acc) ->
    {ok, lists:reverse(Acc)};
collect_case_dirs(Parent, [Entry | Rest], Acc) ->
    Path = filename:join(Parent, Entry),
    case classify_dir(Path) of
        case_dir ->
            collect_case_dirs(Parent, Rest, [{list_to_binary(Entry), Path} | Acc]);
        parent_dir ->
            case nested_case_dirs(list_to_binary(Entry), Path) of
                {ok, Nested} -> collect_case_dirs(Parent, Rest, lists:reverse(Nested, Acc));
                {error, _} = Error -> Error
            end;
        not_a_dir ->
            collect_case_dirs(Parent, Rest, Acc)
    end.

-spec nested_case_dirs(binary(), file:filename()) ->
    {ok, [case_dir()]} | {error, discovery_error()}.
nested_case_dirs(ParentId, ParentPath) ->
    maybe
        {ok, Entries} ?= list_dir(ParentPath),
        {ok, [
            {nested_id(ParentId, Entry), filename:join(ParentPath, Entry)}
         || Entry <- Entries, classify_dir(filename:join(ParentPath, Entry)) =:= case_dir
        ]}
    end.

-spec nested_id(binary(), file:filename()) -> binary().
nested_id(ParentId, Entry) ->
    Child = list_to_binary(Entry),
    <<ParentId/binary, "/", Child/binary>>.

-spec classify_dir(file:filename()) -> case_dir | parent_dir | not_a_dir.
classify_dir(Path) ->
    case filelib:is_dir(Path) of
        false ->
            not_a_dir;
        true ->
            case filelib:is_regular(filename:join(Path, "in.yaml")) of
                true -> case_dir;
                false -> parent_dir
            end
    end.

-spec list_dir(file:filename()) -> {ok, [file:filename()]} | {error, discovery_error()}.
list_dir(Dir) ->
    case file:list_dir(Dir) of
        {ok, Entries} -> {ok, lists:sort(Entries)};
        {error, Reason} -> {error, {list_dir_failed, Dir, Reason}}
    end.

-spec load_test_cases([case_dir()], #{binary() => test_case()}) ->
    {ok, #{binary() => test_case()}} | {error, discovery_error()}.
load_test_cases([], Acc) ->
    {ok, Acc};
load_test_cases([{Id, Path} | Rest], Acc) ->
    case load_test_case(Id, Path) of
        {ok, TestCase} -> load_test_cases(Rest, Acc#{Id => TestCase});
        {error, Reason} -> {error, {load_failed, Path, Reason}}
    end.

-spec load_test_case(binary(), file:filename()) -> {ok, test_case()} | {error, term()}.
load_test_case(Id, TestDir) ->
    YamlFile = filename:join(TestDir, "in.yaml"),
    ErrorFile = filename:join(TestDir, "error"),
    DescFile = filename:join(TestDir, "==="),
    maybe
        {ok, Yaml} ?= file:read_file(YamlFile),
        Name = read_description(DescFile),
        case filelib:is_regular(ErrorFile) of
            true ->
                {ok, #{id => Id, name => Name, yaml => Yaml, expected => error, type => invalid}};
            false ->
                load_valid_case(Id, Name, Yaml, filename:join(TestDir, "in.json"))
        end
    end.

-spec load_valid_case(binary(), binary(), binary(), file:filename()) ->
    {ok, test_case()} | {error, term()}.
load_valid_case(Id, Name, Yaml, JsonFile) ->
    case file:read_file(JsonFile) of
        {ok, JsonBin} ->
            case parse_expected_json(JsonBin) of
                {ok, Expected} ->
                    {ok, #{
                        id => Id,
                        name => Name,
                        yaml => Yaml,
                        expected => Expected,
                        type => valid
                    }};
                {error, JsonErr} ->
                    {error, {json_parse_error, JsonErr}}
            end;
        {error, enoent} ->
            {ok, #{id => Id, name => Name, yaml => Yaml, expected => no_json, type => valid}};
        {error, Reason} ->
            {error, {read_failed, JsonFile, Reason}}
    end.

-spec read_description(file:filename()) -> binary().
read_description(DescFile) ->
    case file:read_file(DescFile) of
        {ok, Desc} -> string:trim(Desc);
        {error, _} -> <<"Unknown test">>
    end.

-spec parse_expected_json(binary()) -> {ok, term()} | {error, term()}.
parse_expected_json(JsonBin) ->
    case decode_json_stream(JsonBin, []) of
        {ok, [Document]} -> {ok, Document};
        {ok, Documents} -> {ok, Documents};
        {error, _} = Error -> Error
    end.

-spec decode_json_stream(binary(), [term()]) -> {ok, [term()]} | {error, term()}.
decode_json_stream(JsonBin, Documents) ->
    case skip_json_whitespace(JsonBin) of
        <<>> ->
            {ok, lists:reverse(Documents)};
        Rest ->
            try json:decode(Rest, ok, #{}) of
                {Document, ok, Remainder} ->
                    decode_json_stream(Remainder, [Document | Documents])
            catch
                _:Reason ->
                    {error, Reason}
            end
    end.

%% RFC 8259 permits space, tab, line feed, and carriage return between values.
-spec skip_json_whitespace(binary()) -> binary().
skip_json_whitespace(<<$\s, Rest/binary>>) -> skip_json_whitespace(Rest);
skip_json_whitespace(<<$\t, Rest/binary>>) -> skip_json_whitespace(Rest);
skip_json_whitespace(<<$\n, Rest/binary>>) -> skip_json_whitespace(Rest);
skip_json_whitespace(<<$\r, Rest/binary>>) -> skip_json_whitespace(Rest);
skip_json_whitespace(Bin) -> Bin.

%%% ============================================================
%%% Output Comparison
%%% ============================================================

-spec compare_output(binary(), term(), term()) -> test_result().
compare_output(_Id, _Result, no_json) ->
    pass;
compare_output(Id, Result, Expected) ->
    case deep_equal(Result, Expected) of
        true ->
            pass;
        false ->
            {fail, {Id, output_mismatch, expected, Expected, got, Result}}
    end.

-spec compare_documents(binary(), [term()], term()) -> test_result().
compare_documents(_Id, _Documents, no_json) ->
    pass;
compare_documents(Id, [Document], Expected) ->
    compare_output(Id, Document, Expected);
compare_documents(Id, Documents, Expected) when is_list(Expected) ->
    case deep_equal(Documents, Expected) of
        true ->
            pass;
        false ->
            {fail, {Id, output_mismatch, expected, Expected, got, Documents}}
    end;
compare_documents(Id, Documents, Expected) ->
    {fail, {Id, document_count_mismatch, expected, Expected, got, Documents}}.

-spec deep_equal(term(), term()) -> boolean().
deep_equal(A, A) ->
    true;
deep_equal(A, B) when is_map(A), is_map(B) ->
    maps_equal(A, B);
deep_equal(A, B) when is_list(A), is_list(B) ->
    lists_equal(A, B);
deep_equal(A, B) when is_float(A), is_float(B) ->
    abs(A - B) < ?FLOAT_EPSILON;
deep_equal(A, B) when is_float(A), is_integer(B) ->
    abs(A - float(B)) < ?FLOAT_EPSILON;
deep_equal(A, B) when is_integer(A), is_float(B) ->
    abs(float(A) - B) < ?FLOAT_EPSILON;
deep_equal({{Y, M, D}, {H, Mi, S}}, Bin) when is_binary(Bin) ->
    timestamp_matches({{Y, M, D}, {H, Mi, S}}, Bin);
deep_equal(infinity, Bin) when is_binary(Bin) ->
    Bin =:= <<".inf">> orelse Bin =:= <<"+.inf">> orelse Bin =:= <<".Inf">>;
deep_equal(negative_infinity, Bin) when is_binary(Bin) ->
    Bin =:= <<"-.inf">> orelse Bin =:= <<"-.Inf">>;
deep_equal(nan, Bin) when is_binary(Bin) ->
    Bin =:= <<".nan">> orelse Bin =:= <<".NaN">>;
deep_equal(_A, _B) ->
    false.

-spec maps_equal(map(), map()) -> boolean().
maps_equal(A, B) ->
    maps:size(A) =:= maps:size(B) andalso
        maps:fold(
            fun(K, V, Acc) ->
                Acc andalso
                    case find_key(K, B) of
                        {ok, V2} -> deep_equal(V, V2);
                        error -> false
                    end
            end,
            true,
            A
        ).

-spec find_key(term(), map()) -> {ok, term()} | error.
find_key(Key, Map) ->
    case maps:find(Key, Map) of
        {ok, _} = Found -> Found;
        error -> maps:find(json_key(Key), Map)
    end.

-spec json_key(term()) -> term().
json_key(null) -> <<"null">>;
json_key(true) -> <<"true">>;
json_key(false) -> <<"false">>;
json_key(Key) when is_integer(Key) -> integer_to_binary(Key);
json_key(Key) when is_float(Key) -> float_to_binary(Key, [short]);
json_key(Key) -> Key.

-spec lists_equal([term()], [term()]) -> boolean().
lists_equal([], []) ->
    true;
lists_equal([H1 | T1], [H2 | T2]) ->
    deep_equal(H1, H2) andalso lists_equal(T1, T2);
lists_equal(_, _) ->
    false.

-spec timestamp_matches(calendar:datetime(), binary()) -> boolean().
timestamp_matches({{Y, M, D}, {H, Mi, S}}, Bin) ->
    Pattern =
        "^" ++
            integer_to_list(Y) ++ "-" ++
            pad2(M) ++ "-" ++
            pad2(D) ++
            "[ T]" ++
            pad2(H) ++ ":" ++
            pad2(Mi) ++ ":" ++
            pad2(S),
    case re:run(Bin, Pattern) of
        {match, _} -> true;
        nomatch -> false
    end.

-spec pad2(integer()) -> string().
pad2(N) when N < 10 -> [$0 | integer_to_list(N)];
pad2(N) -> integer_to_list(N).

%%% ============================================================
%%% Path Resolution
%%% ============================================================

-spec get_suite_dir(ct:config()) -> file:filename().
get_suite_dir(Config) ->
    DataDir = proplists:get_value(data_dir, Config, ""),
    ProjectRoot = find_project_root(DataDir),
    filename:join(ProjectRoot, ?SUITE_DIR).

-spec find_project_root(file:filename()) -> file:filename().
find_project_root("") ->
    find_project_root_from_cwd();
find_project_root(DataDir) ->
    search_up_for_rebar(filename:dirname(DataDir)).

-spec find_project_root_from_cwd() -> file:filename().
find_project_root_from_cwd() ->
    {ok, Cwd} = file:get_cwd(),
    search_up_for_rebar(Cwd).

-spec search_up_for_rebar(file:filename()) -> file:filename().
search_up_for_rebar("/") ->
    error({could_not_find_project_root, no_rebar_config_found});
search_up_for_rebar(Dir) ->
    RebarConfig = filename:join(Dir, "rebar.config"),
    case filelib:is_regular(RebarConfig) of
        true -> Dir;
        false -> search_up_for_rebar(filename:dirname(Dir))
    end.

%%% ============================================================
%%% Reporting
%%% ============================================================

-spec generate_test_report(binary(), [{binary(), test_result()}]) -> ok.
generate_test_report(Title, Results) ->
    Total = length(Results),
    {Passed, Failed} = lists:foldl(
        fun({_Id, Result}, {P, F}) ->
            case Result of
                pass -> {P + 1, F};
                {fail, _} -> {P, F + 1}
            end
        end,
        {0, 0},
        Results
    ),
    FailedIds = [Id || {Id, {fail, _}} <- Results],
    Report = io_lib:format(
        "~n=== ~s ===~nTotal: ~p | Passed: ~p (~.1f%) | Failed: ~p (~.1f%)~n",
        [
            Title,
            Total,
            Passed,
            percentage(Passed, Total),
            Failed,
            percentage(Failed, Total)
        ]
    ),
    FailedReport =
        case FailedIds of
            [] -> "";
            _ -> io_lib:format("Failed: ~p~n", [FailedIds])
        end,
    write_report_file(Title, Report, FailedReport, Results),
    ct:pal("~s~s", [Report, FailedReport]),
    ok.

-spec write_report_file(binary(), iolist(), iolist(), [{binary(), test_result()}]) -> ok.
write_report_file(Title, Report, FailedReport, Results) ->
    FileName =
        case Title of
            <<"Valid Tests">> -> "/tmp/yaml_compliance_valid.txt";
            <<"Round Trip Tests">> -> "/tmp/yaml_compliance_round_trip.txt";
            <<"Invalid Tests">> -> "/tmp/yaml_compliance_invalid.txt";
            _ -> "/tmp/yaml_compliance_report.txt"
        end,
    Failures = [{Id, Reason} || {Id, {fail, Reason}} <- Results],
    Content = io_lib:format("~s~s~nDetailed failures:~n~p~n", [Report, FailedReport, Failures]),
    file:write_file(FileName, Content),
    ok.

-spec percentage(integer(), integer()) -> float().
percentage(_, 0) -> 0.0;
percentage(N, Total) -> (N / Total) * 100.

-spec check_results([{binary(), test_result()}]) -> ok.
check_results(Results) ->
    Failures = [Id || {Id, {fail, _}} <- Results],
    case Failures of
        [] ->
            ok;
        _ ->
            ct:fail({failed_tests, length(Failures), Failures})
    end.
