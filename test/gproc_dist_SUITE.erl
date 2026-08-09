%% -*- erlang-indent-level: 4; indent-tabs-mode: nil -*-
%%
%% Common Test port of gproc_dist_tests (locks_leader era).
%% Peer nodes get a per-node disk logger under the CT log dir so post-mortems
%% do not depend on the old error_logger / eunit console noise.
-module(gproc_dist_SUITE).

-export([all/0, groups/0, suite/0,
         init_per_suite/1, end_per_suite/1,
         init_per_group/2, end_per_group/2,
         init_per_testcase/2, end_per_testcase/2]).

-export([
         simple_reg/1,
         simple_reg_other/1,
         simple_ensure/1,
         simple_ensure_other/1,
         simple_reg_or_locate/1,
         simple_counter/1,
         simple_r_counter/1,
         simple_n_counter/1,
         aggr_counter/1,
         awaited_aggr_counter/1,
         simple_resource_count/1,
         wild_resource_count/1,
         wild_key_in_resource/1,
         awaited_resource_count/1,
         resource_count_on_zero/1,
         update_counters/1,
         update_r_counters/1,
         update_n_counters/1,
         shared_counter/1,
         prop/1,
         mreg/1,
         await_reg/1,
         await_self/1,
         await_reg_exists/1,
         give_away/1,
         sync/1,
         monitor/1,
         standby_monitor/1,
         standby_monitor_unreg/1,
         follow_monitor/1,
         monitor_demonitor/1,
         subscribe/1,
         sync_cand_dies/1,
         fail_node/1,
         master_dies/1
        ]).

-include_lib("common_test/include/ct.hrl").

-define(NODE_NAMES, [gproc_d1, gproc_d2, gproc_d3]).

suite() ->
    [{timetrap, {minutes, 5}}].

all() ->
    [{group, dist3}].

groups() ->
    %% sequence keeps registry state isolated between cases; the final
    %% fault-injection cases still run even if an earlier basic case flakes.
    [{dist3, [sequence],
      [simple_reg,
       simple_reg_other,
       simple_ensure,
       simple_ensure_other,
       simple_reg_or_locate,
       simple_counter,
       simple_r_counter,
       simple_n_counter,
       aggr_counter,
       awaited_aggr_counter,
       simple_resource_count,
       wild_resource_count,
       wild_key_in_resource,
       awaited_resource_count,
       resource_count_on_zero,
       update_counters,
       update_r_counters,
       update_n_counters,
       shared_counter,
       prop,
       mreg,
       await_reg,
       await_self,
       await_reg_exists,
       give_away,
       sync,
       monitor,
       standby_monitor,
       standby_monitor_unreg,
       follow_monitor,
       monitor_demonitor,
       subscribe,
       sync_cand_dies,
       fail_node,
       master_dies
      ]}].

init_per_suite(Config) ->
    gproc_test_lib:ensure_dist(),
    %% Prefer logger over legacy error_logger on the controller too.
    _ = logger:set_primary_config(level, info),
    Config.

end_per_suite(_Config) ->
    ok.

init_per_group(dist3, Config) ->
    LogDir = filename:join(?config(priv_dir, Config), "peer_logs"),
    ok = filelib:ensure_dir(filename:join(LogDir, "dummy")),
    ct:log("Peer disk logs under ~s", [LogDir]),
    Ns = gproc_test_lib:start_nodes(?NODE_NAMES, #{log_dir => LogDir}),
    ok = gproc_test_lib:start_gproc(Ns),
    Leader = gproc_test_lib:wait_gproc_leader(Ns),
    ct:log("gproc_dist leader = ~p on nodes ~p", [Leader, Ns]),
    [{nodes, Ns}, {peer_log_dir, LogDir} | Config];
init_per_group(_, Config) ->
    Config.

end_per_group(dist3, Config) ->
    case ?config(nodes, Config) of
        Ns when is_list(Ns) ->
            gproc_test_lib:stop_nodes(Ns);
        _ ->
            ok
    end,
    ok;
end_per_group(_, _) ->
    ok.

init_per_testcase(_Case, Config) ->
    Config.

end_per_testcase(Case, Config) ->
    case ?config(peer_log_dir, Config) of
        undefined -> ok;
        LogDir ->
            ct:log("Peer logs for ~p: ~s", [Case, LogDir])
    end,
    ok.

%% ---- cases (thin wrappers; bodies live in gproc_dist_tests) ----

simple_reg(Config) ->
    gproc_dist_tests:t_simple_reg(ns(Config)).
simple_reg_other(Config) ->
    gproc_dist_tests:t_simple_reg_other(ns(Config)).
simple_ensure(Config) ->
    gproc_dist_tests:t_simple_ensure(ns(Config)).
simple_ensure_other(Config) ->
    gproc_dist_tests:t_simple_ensure_other(ns(Config)).
simple_reg_or_locate(Config) ->
    gproc_dist_tests:t_simple_reg_or_locate(ns(Config)).
simple_counter(Config) ->
    gproc_dist_tests:t_simple_counter(ns(Config)).
simple_r_counter(Config) ->
    gproc_dist_tests:t_simple_r_counter(ns(Config)).
simple_n_counter(Config) ->
    gproc_dist_tests:t_simple_n_counter(ns(Config)).
aggr_counter(Config) ->
    gproc_dist_tests:t_aggr_counter(ns(Config)).
awaited_aggr_counter(Config) ->
    gproc_dist_tests:t_awaited_aggr_counter(ns(Config)).
simple_resource_count(Config) ->
    gproc_dist_tests:t_simple_resource_count(ns(Config)).
wild_resource_count(Config) ->
    gproc_dist_tests:t_wild_resource_count(ns(Config)).
wild_key_in_resource(Config) ->
    gproc_dist_tests:t_wild_key_in_resource(ns(Config)).
awaited_resource_count(Config) ->
    gproc_dist_tests:t_awaited_resource_count(ns(Config)).
resource_count_on_zero(Config) ->
    gproc_dist_tests:t_resource_count_on_zero(ns(Config)).
update_counters(Config) ->
    gproc_dist_tests:t_update_counters(ns(Config)).
update_r_counters(Config) ->
    gproc_dist_tests:t_update_r_counters(ns(Config)).
update_n_counters(Config) ->
    gproc_dist_tests:t_update_n_counters(ns(Config)).
shared_counter(Config) ->
    gproc_dist_tests:t_shared_counter(ns(Config)).
prop(Config) ->
    gproc_dist_tests:t_prop(ns(Config)).
mreg(Config) ->
    gproc_dist_tests:t_mreg(ns(Config)).
await_reg(Config) ->
    gproc_dist_tests:t_await_reg(ns(Config)).
await_self(Config) ->
    gproc_dist_tests:t_await_self(ns(Config)).
await_reg_exists(Config) ->
    gproc_dist_tests:t_await_reg_exists(ns(Config)).
give_away(Config) ->
    gproc_dist_tests:t_give_away(ns(Config)).
sync(Config) ->
    gproc_dist_tests:t_sync(ns(Config)).
monitor(Config) ->
    gproc_dist_tests:t_monitor(ns(Config)).
standby_monitor(Config) ->
    gproc_dist_tests:t_standby_monitor(ns(Config)).
standby_monitor_unreg(Config) ->
    gproc_dist_tests:t_standby_monitor_unreg(ns(Config)).
follow_monitor(Config) ->
    gproc_dist_tests:t_follow_monitor(ns(Config)).
monitor_demonitor(Config) ->
    gproc_dist_tests:t_monitor_demonitor(ns(Config)).
subscribe(Config) ->
    gproc_dist_tests:t_subscribe(ns(Config)).
sync_cand_dies(Config) ->
    gproc_dist_tests:t_sync_cand_dies(ns(Config)).
fail_node(Config) ->
    gproc_dist_tests:t_fail_node(ns(Config)).
master_dies(Config) ->
    gproc_dist_tests:t_master_dies(ns(Config)).

ns(Config) ->
    ?config(nodes, Config).
