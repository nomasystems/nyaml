-module(nyaml_doc_tests).

-include_lib("eunit/include/eunit.hrl").

-define(ANCHORS_HEADING, <<"## Anchors and aliases">>).
-define(MERGE_KEYS_HEADING, <<"## Merge keys">>).
-define(TYPE_TAGS_HEADING, <<"## Type tags">>).

%%% ============================================================
%%% Tests
%%% ============================================================

moduledoc_type_tags_example_test() ->
    Example = read_fenced_block(?TYPE_TAGS_HEADING),
    ?assertEqual(
        {ok, #{
            <<"explicit_string">> => <<"123">>,
            <<"explicit_int">> => 456,
            <<"explicit_float">> => 3.14,
            <<"explicit_bool">> => true,
            <<"explicit_null">> => null
        }},
        nyaml:decode(Example)
    ).

moduledoc_anchors_example_test() ->
    Example = read_fenced_block(?ANCHORS_HEADING),
    Defaults = #{<<"timeout">> => 30, <<"retries">> => 3},
    ?assertEqual(
        {ok, #{
            <<"defaults">> => Defaults,
            <<"production">> => Defaults,
            <<"staging">> => Defaults
        }},
        nyaml:decode(Example)
    ).

moduledoc_merge_keys_example_test_() ->
    Example = read_fenced_block(?MERGE_KEYS_HEADING),
    Defaults = #{<<"timeout">> => 30, <<"retries">> => 3},
    [
        ?_assertEqual(
            {ok, #{
                <<"defaults">> => Defaults,
                <<"production">> => #{<<"timeout">> => 60, <<"retries">> => 3}
            }},
            nyaml:decode(Example, #{schema => extended})
        ),
        ?_assertEqual(
            {ok, #{
                <<"defaults">> => Defaults,
                <<"production">> => #{<<"<<">> => Defaults, <<"timeout">> => 60}
            }},
            nyaml:decode(Example)
        )
    ].

%%% ============================================================
%%% Helpers
%%% ============================================================

read_fenced_block(Heading) ->
    {ok, Source} = file:read_file(filename:join([project_root(), "src", "nyaml.erl"])),
    Lines = binary:split(Source, <<"\n">>, [global]),
    take_block(drop_until(Heading, Lines)).

drop_until(Heading, [Heading | Rest]) ->
    Rest;
drop_until(Heading, [_ | Rest]) ->
    drop_until(Heading, Rest).

take_block([<<"```", _/binary>> | Rest]) ->
    collect_block(Rest, []);
take_block([_ | Rest]) ->
    take_block(Rest).

collect_block([<<"```", _/binary>> | _], Acc) ->
    iolist_to_binary(lists:reverse(Acc));
collect_block([Line | Rest], Acc) ->
    collect_block(Rest, [[Line, <<"\n">>] | Acc]).

project_root() ->
    {ok, Cwd} = file:get_cwd(),
    search_up_for_rebar(Cwd).

search_up_for_rebar("/") ->
    error({could_not_find_project_root, no_rebar_config_found});
search_up_for_rebar(Dir) ->
    case filelib:is_regular(filename:join(Dir, "rebar.config")) of
        true -> Dir;
        false -> search_up_for_rebar(filename:dirname(Dir))
    end.
