-module(gproc_pt_tests).

-include_lib("eunit/include/eunit.hrl").

-compile({parse_transform, gproc_pt}).

reg_and_send_test_() ->
    {setup,
        fun() -> application:start(gproc) end,
        fun(_) -> application:stop(gproc) end,
        [{"gproc", fun gproc/0}]
    }.

gproc() ->
    gproc:reg({n, l, <<"test">>}),

    Msg = random:uniform(1000),
    {n, l, <<"test">>} ! Msg,

    Echo = receive
        V -> V
    end,

    ?assertEqual(Echo, Msg).
