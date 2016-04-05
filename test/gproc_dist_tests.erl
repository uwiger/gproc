%% -*- erlang-indent-level: 4; indent-tabs-mode: nil -*-
%% ``The contents of this file are subject to the Erlang Public License,
%% Version 1.1, (the "License"); you may not use this file except in
%% compliance with the License. You should have received a copy of the
%% Erlang Public License along with this software. If not, it can be
%% retrieved via the world wide web at http://www.erlang.org/.
%%
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and limitations
%% under the License.
%%
%% The Initial Developer of the Original Code is Ericsson Utvecklings AB.
%% Portions created by Ericsson are Copyright 1999, Ericsson Utvecklings
%% AB. All Rights Reserved.''
%%
%% @author Ulf Wiger <ulf@wiger.net>
%%
-module(gproc_dist_tests).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-export([t_spawn/1, t_spawn_reg/2]).

-define(f(E), fun() -> ?debugVal(E) end).

dist_test_() ->
    {timeout, 120,
     [
      %% {setup,
      %%  fun dist_setup/0,
      %%  fun dist_cleanup/1,
      %%  fun(skip) -> [];
      %%     (Ns) when is_list(Ns) ->
      %%          {inorder, basic_tests(Ns)}
      %%  end
      %% },
      {foreach,
       fun dist_setup/0,
       fun dist_cleanup/1,
       [
        fun(Ns) ->
                [{inorder, basic_tests(Ns)}]
        end,
        fun(Ns) ->
                [?f(t_sync_cand_dies(Ns))]
        end,
        fun(Ns) ->
                [?f(t_fail_node(Ns))]
        end,
        fun(Ns) ->
                [?f(t_master_dies(Ns))]
        end
       ]}
     ]}.

basic_tests(Ns) ->
    [
     ?f(t_simple_reg(Ns)),
     ?f(t_simple_reg_other(Ns)),
     ?f(t_simple_reg_or_locate(Ns)),
     ?f(t_simple_counter(Ns)),
     ?f(t_aggr_counter(Ns)),
     ?f(t_awaited_aggr_counter(Ns)),
     ?f(t_simple_resource_count(Ns)),
     ?f(t_awaited_resource_count(Ns)),
     ?f(t_resource_count_on_zero(Ns)),
     ?f(t_update_counters(Ns)),
     ?f(t_shared_counter(Ns)),
     ?f(t_prop(Ns)),
     ?f(t_mreg(Ns)),
     ?f(t_await_reg(Ns)),
     ?f(t_await_self(Ns)),
     ?f(t_await_reg_exists(Ns)),
     ?f(t_give_away(Ns)),
     ?f(t_sync(Ns)),
     ?f(t_monitor(Ns)),
     ?f(t_standby_monitor(Ns)),
     ?f(t_follow_monitor(Ns)),
     ?f(t_subscribe(Ns))
    ].

dist_setup() ->
    case run_dist_tests() of
        true ->
            Ns = start_slaves([dist_test_n1, dist_test_n2, dist_test_n3]),
            ?assertMatch({[ok,ok,ok],[]},
                         rpc:multicall(Ns, application, set_env,
                                       [gproc, gproc_dist, Ns])),
            ?assertMatch({[ok,ok,ok],[]},
                         rpc:multicall(
                           Ns, application, start, [gproc])),
            Ns;
        false ->
            skip
    end.

dist_cleanup(Ns) ->
    [slave:stop(N) || N <- Ns],
    ok.

run_dist_tests() ->
    case os:getenv("GPROC_DIST") of
        "true" -> true;
	"false" -> false;
	false ->
	    case code:ensure_loaded(gen_leader) of
		{error, nofile} ->
		    false;
		_ ->
		    true
	    end
    end.

-define(T_NAME, {n, g, {?MODULE, ?LINE, erlang:now()}}).
-define(T_KVL, [{foo, "foo"}, {bar, "bar"}]).
-define(T_COUNTER, {c, g, {?MODULE, ?LINE}}).
-define(T_RESOURCE, {r, g, {?MODULE, ?LINE}}).
-define(T_PROP, {p, g, ?MODULE}).

t_simple_reg([H|_] = Ns) ->
    Name = ?T_NAME,
    P = t_spawn_reg(H, Name),
    ?assertMatch(ok, t_lookup_everywhere(Name, Ns, P)),
    ?assertMatch(true, t_call(P, {apply, gproc, unreg, [Name]})),
    ?assertMatch(ok, t_lookup_everywhere(Name, Ns, undefined)),
    ?assertMatch(ok, t_call(P, die)).

t_simple_reg_other([A, B|_] = Ns) ->
    Name = ?T_NAME,
    P1 = t_spawn(A),
    P2 = t_spawn(B),
    ?assertMatch(true, t_call(P1, {apply, gproc, reg_other, [Name, P2]})),
    ?assertMatch(ok, t_lookup_everywhere(Name, Ns, P2)),
    ?assertMatch(true, t_call(P1, {apply, gproc, unreg_other, [Name, P2]})),
    ?assertMatch(ok, t_lookup_everywhere(Name, Ns, undefined)),
    ?assertMatch(ok, t_call(P1, die)),
    ?assertMatch(ok, t_call(P2, die)).

t_simple_reg_or_locate([A,B|_] = _Ns) ->
    Name = ?T_NAME,
    P1 = t_spawn(A),
    Ref = erlang:monitor(process, P1),
    ?assertMatch({P1, the_value},
		 t_call(P1, {apply, gproc, reg_or_locate, [Name, the_value]})),
    P2 = t_spawn(B),
    Ref2 = erlang:monitor(process, P2),
    ?assertMatch({P1, the_value},
		 t_call(P2, {apply, gproc, reg_or_locate, [Name, other_value]})),
    ?assertMatch(ok, t_call(P1, die)),
    ?assertMatch(ok, t_call(P2, die)),
    flush_down(Ref),
    flush_down(Ref2).

flush_down(Ref) ->
    receive
        {'DOWN', Ref, _, _, _} ->
            ok
    after 1000 ->
            erlang:error({timeout, [flush_down, Ref]})
    end.


t_simple_counter([H|_] = Ns) ->
    Ctr = ?T_COUNTER,
    P = t_spawn_reg(H, Ctr, 3),
    ?assertMatch(ok, t_read_everywhere(Ctr, P, Ns, 3)),
    ?assertMatch(5, t_call(P, {apply, gproc, update_counter, [Ctr, 2]})),
    ?assertMatch(ok, t_read_everywhere(Ctr, P, Ns, 5)),
    ?assertMatch(ok, t_call(P, die)).

t_shared_counter([H|_] = Ns) ->
    Ctr = ?T_COUNTER,
    P = t_spawn_reg_shared(H, Ctr, 3),
    ?assertMatch(ok, t_read_everywhere(Ctr, shared, Ns, 3)),
    ?assertMatch(5, t_call(P, {apply, gproc, update_shared_counter, [Ctr, 2]})),
    ?assertMatch(ok, t_read_everywhere(Ctr, shared, Ns, 5)),
    ?assertMatch(ok, t_call(P, die)),
    ?assertMatch(ok, t_read_everywhere(Ctr, shared, Ns, 5)),
    ?assertMatch(ok, t_read_everywhere(Ctr, shared, Ns, 5)), % twice
    P1 = t_spawn(H),
    ?assertMatch(true, t_call(P1, {apply, gproc, unreg_shared, [Ctr]})),
    ?assertMatch(ok, t_read_everywhere(Ctr, shared, Ns, badarg)).


t_aggr_counter([H1,H2|_] = Ns) ->
    {c,g,Nm} = Ctr = ?T_COUNTER,
    Aggr = {a,g,Nm},
    Pc1 = t_spawn_reg(H1, Ctr, 3),
    Pa = t_spawn_reg(H2, Aggr),
    ?assertMatch(ok, t_read_everywhere(Ctr, Pc1, Ns, 3)),
    ?assertMatch(ok, t_read_everywhere(Aggr, Pa, Ns, 3)),
    Pc2 = t_spawn_reg(H2, Ctr, 3),
    ?assertMatch(ok, t_read_everywhere(Ctr, Pc2, Ns, 3)),
    ?assertMatch(ok, t_read_everywhere(Aggr, Pa, Ns, 6)),
    ?assertMatch(5, t_call(Pc1, {apply, gproc, update_counter, [Ctr, 2]})),
    ?assertMatch(ok, t_read_everywhere(Ctr, Pc1, Ns, 5)),
    ?assertMatch(ok, t_read_everywhere(Aggr, Pa, Ns, 8)),
    ?assertMatch(ok, t_call(Pc1, die)),
    ?assertMatch(ok, t_read_everywhere(Aggr, Pa, Ns, 3)),
    ?assertMatch(ok, t_call(Pc2, die)),
    ?assertMatch(ok, t_call(Pa, die)).

t_awaited_aggr_counter([H1,H2|_] = Ns) ->
    {c,g,Nm} = Ctr = ?T_COUNTER,
    Aggr = {a,g,Nm},
    Pc1 = t_spawn_reg(H1, Ctr, 3),
    P = t_spawn(H2),
    Ref = erlang:monitor(process, P),
    P ! {self(), Ref, {apply, gproc, await, [Aggr]}},
    t_sleep(),
    P1 = t_spawn_reg(H2, Aggr),
    ?assert(P1 == receive
                      {P, Ref, Res} ->
                          element(1, Res);
                      {'DOWN', Ref, _, _, Reason} ->
                          erlang:error(Reason);
                      Other ->
                          erlang:error({received, Other})
                  end),
    ?assertMatch(ok, t_read_everywhere(Aggr, P1, Ns, 3)),
    ?assertMatch(ok, t_call(Pc1, die)),
    ?assertMatch(ok, t_call(P, die)),
    flush_down(Ref),
    ?assertMatch(ok, t_call(P1, die)).

t_simple_resource_count([H1,H2|_] = Ns) ->
    {r,g,Nm} = R = ?T_RESOURCE,
    RC = {rc,g,Nm},
    Pr1 = t_spawn_reg(H1, R, 3),
    Prc = t_spawn_reg(H2, RC),
    ?assertMatch(ok, t_read_everywhere(R, Pr1, Ns, 3)),
    ?assertMatch(ok, t_read_everywhere(RC, Prc, Ns, 1)),
    Pr2 = t_spawn_reg(H2, R, 4),
    ?assertMatch(ok, t_read_everywhere(R, Pr2, Ns, 4)),
    ?assertMatch(ok, t_read_everywhere(RC, Prc, Ns, 2)),
    ?assertMatch(ok, t_call(Pr1, die)),
    ?assertMatch(ok, t_read_everywhere(RC, Prc, Ns, 1)),
    ?assertMatch(ok, t_call(Pr2, die)),
    ?assertMatch(ok, t_call(Prc, die)).

t_awaited_resource_count([H1,H2|_] = Ns) ->
    {r,g,Nm} = R = ?T_RESOURCE,
    RC = {rc,g,Nm},
    Pr1 = t_spawn_reg(H1, R, 3),
    P = t_spawn(H2),
    Ref = erlang:monitor(process, P),
    P ! {self(), Ref, {apply, gproc, await, [RC]}},
    t_sleep(),
    P1 = t_spawn_reg(H2, RC),
    ?assert(P1 == receive
                      {P, Ref, Res} ->
                          element(1, Res);
                      {'DOWN', Ref, _, _, Reason} ->
                          erlang:error(Reason);
                      Other ->
                          erlang:error({received, Other})
                  end),
    ?assertMatch(ok, t_read_everywhere(RC, P1, Ns, 1)),
    ?assertMatch(ok, t_call(Pr1, die)),
    ?assertMatch(ok, t_call(P, die)),
    flush_down(Ref),
    ?assertMatch(ok, t_call(P1, die)).

t_resource_count_on_zero([H1,H2|_] = Ns) ->
    {r,g,Nm} = R = ?T_RESOURCE,
    Prop = ?T_PROP,
    RC = {rc,g,Nm},
    Pr1 = t_spawn_reg(H1, R, 3),
    Pp = t_spawn_reg(H2, Prop),
    ?assertMatch(ok, t_call(Pp, {selective, true})),
    Prc = t_spawn_reg(H2, RC, undefined, [{on_zero, [{send, Prop}]}]),
    ?assertMatch(ok, t_read_everywhere(R, Pr1, Ns, 3)),
    ?assertMatch(ok, t_read_everywhere(RC, Prc, Ns, 1)),
    ?assertMatch(ok, t_call(Pr1, die)),
    ?assertMatch(ok, t_read_everywhere(RC, Prc, Ns, 0)),
    ?assertMatch({gproc, resource_on_zero, g, Nm, Prc},
                 t_call(Pp, {apply_fun, fun() ->
                                                receive
                                                    {gproc, _, _, _, _} = M ->
                                                        M
                                                after 10000 ->
                                                        timeout
                                                end
                                        end})),
    ?assertMatch(ok, t_call(Pp, {selective, false})),
    ?assertMatch(ok, t_call(Pp, die)),
    ?assertMatch(ok, t_call(Prc, die)).

t_update_counters([H1,H2|_] = Ns) ->
    {c,g,N1} = C1 = ?T_COUNTER,
    A1 = {a,g,N1},
    C2 = ?T_COUNTER,
    P1 = t_spawn_reg(H1, C1, 2),
    P12 = t_spawn_reg(H2, C1, 2),
    P2 = t_spawn_reg(H2, C2, 1),
    Pa1 = t_spawn_reg(H2, A1),
    ?assertMatch(ok, t_read_everywhere(C1, P1, Ns, 2)),
    ?assertMatch(ok, t_read_everywhere(C1, P12, Ns, 2)),
    ?assertMatch(ok, t_read_everywhere(C2, P2, Ns, 1)),
    ?assertMatch(ok, t_read_everywhere(A1, Pa1, Ns, 4)),
    ?assertMatch([{C1,P1, 3},
		  {C1,P12,4},
		  {C2,P2, 0}], t_call(P1, {apply, gproc, update_counters,
					   [g, [{C1,P1,1},{C1,P12,2},{C2,P2,{-2,0,0}}]]})),
    ?assertMatch(ok, t_read_everywhere(C1, P1, Ns, 3)),
    ?assertMatch(ok, t_read_everywhere(C1, P12, Ns, 4)),
    ?assertMatch(ok, t_read_everywhere(C2, P2, Ns, 0)),
    ?assertMatch(ok, t_read_everywhere(A1, Pa1, Ns, 7)),
    ?assertMatch(ok, t_call(P1, die)),
    ?assertMatch(ok, t_call(P12, die)),
    ?assertMatch(ok, t_call(P2, die)).

t_prop([H1,H2|_] = Ns) ->
    {p, g, _} = P = ?T_PROP,
    P1 = t_spawn_reg(H1, P, 1),
    P2 = t_spawn_reg(H2, P, 2),
    ?assertMatch(ok, t_read_everywhere(P, P1, Ns, 1)),
    ?assertMatch(ok, t_read_everywhere(P, P2, Ns, 2)),
    ?assertMatch(ok, t_call(P1, die)),
    ?assertMatch(ok, t_read_everywhere(P, P1, Ns, badarg)),
    ?assertMatch(ok, t_call(P2, die)).

t_mreg([H|_] = Ns) ->
    Kvl = ?T_KVL,
    Keys = [K || {K,_} <- Kvl],
    P = t_spawn_mreg(H, Kvl),
    [?assertMatch(ok, t_lookup_everywhere({n,g,K}, Ns, P)) || K <- Keys],
    ?assertMatch(true, t_call(P, {apply, gproc, munreg, [n, g, Keys]})),
    [?assertMatch(ok, t_lookup_everywhere({n,g,K},Ns,undefined)) || K <- Keys],
    ?assertMatch(ok, t_call(P, die)).

t_await_reg([A,B|_] = Ns) ->
    Name = ?T_NAME,
    P = t_spawn(A),
    Ref = erlang:monitor(process, P),
    P ! {self(), Ref, {apply, gproc, await, [Name]}},
    t_sleep(),
    P1 = t_spawn_reg(B, Name),
    ?assert(P1 == receive
		      {P, Ref, Res} ->
			  element(1, Res);
		      {'DOWN', Ref, _, _, Reason} ->
			  erlang:error(Reason);
		      Other ->
			  erlang:error({received,Other})
		  end),
    ?assertMatch(ok, t_call(P, die)),
    flush_down(Ref),
    ?assertMatch(ok, t_lookup_everywhere(Name, Ns, P1)),
    ?assertMatch(ok, t_call(P1, die)).

t_await_self([A|_]) ->
    Name = ?T_NAME,
    P = t_spawn(A, false),  % don't buffer unknowns
    Ref = t_call(P, {apply, gproc, nb_wait, [Name]}),
    ?assertMatch(ok, t_call(P, {selective, true})),
    ?assertMatch(true, t_call(P, {apply, gproc, reg, [Name, some_value]})),
    ?assertMatch({registered, {Name, P, some_value}},
		 t_call(P, {apply_fun, fun() ->
					       receive
						   {gproc, Ref, R, Wh} ->
						       {R, Wh}
					       after 10000 ->
						       timeout
					       end
				       end})),
    ?assertMatch(ok, t_call(P, {selective, false})),
    ?assertMatch(true, t_call(P, {apply, gproc, unreg, [Name]})).

t_await_reg_exists([A,B|_]) ->
    Name = ?T_NAME,
    P = t_spawn(A),
    Ref = erlang:monitor(process, P),
    P1 = t_spawn_reg(B, Name),
    P ! {self(), Ref, {apply, gproc, await, [Name]}},
    ?assert(P1 == receive
		      {P, Ref, Res} ->
			  element(1, Res);
		      {'DOWN', Ref, _, _, Reason} ->
			  erlang:error(Reason);
		      Other ->
			  erlang:error({received,Other})
		  end),
    ?assertMatch(ok, t_call(P, die)),
    ?assertMatch(ok, t_call(P1, die)).

t_give_away([A,B|_] = Ns) ->
    Na = ?T_NAME,
    Nb = ?T_NAME,
    Pa = t_spawn_reg(A, Na),
    Pb = t_spawn_reg(B, Nb),
    ?assertMatch(ok, t_lookup_everywhere(Na, Ns, Pa)),
    ?assertMatch(ok, t_lookup_everywhere(Nb, Ns, Pb)),
    ?assertMatch(Pb, t_call(Pa, {apply, gproc, give_away, [Na, Nb]})),
    ?assertMatch(ok, t_lookup_everywhere(Na, Ns, Pb)),
    ?assertMatch(Pa, t_call(Pb, {apply, gproc, give_away, [Na, Pa]})),
    ?assertMatch(ok, t_lookup_everywhere(Na, Ns, Pa)),
    ?assertMatch(ok, t_call(Pa, die)),
    ?assertMatch(ok, t_call(Pb, die)).

t_sync(Ns) ->
    %% Don't really know how to test this...
    [?assertMatch(true, rpc:call(N, gproc_dist, sync, []))
     || N <- Ns].

t_monitor([A,B|_]) ->
    Na = ?T_NAME,
    Pa = t_spawn_reg(A, Na),
    Pb = t_spawn(B, _Selective = true),
    Ref = t_call(Pb, {apply, gproc, monitor, [Na]}),
    ?assert(is_reference(Ref)),
    ?assertMatch(ok, t_call(Pa, die)),
    ?assertMatch({gproc,unreg,Ref,Na}, got_msg(Pb, gproc)),
    Pc = t_spawn_reg(A, Na),
    Ref1 = t_call(Pb, {apply, gproc, monitor, [Na]}),
    ?assertMatch(true, t_call(Pc, {apply, gproc, unreg, [Na]})),
    ?assertMatch({gproc,unreg,Ref1,Na}, got_msg(Pb, gproc)).

t_standby_monitor([A,B|_] = Ns) ->
    Na = ?T_NAME,
    Pa = t_spawn_reg(A, Na),
    Pb = t_spawn(B, _Selective = true),
    Ref = t_call(Pb, {apply, gproc, monitor, [Na, standby]}),
    ?assert(is_reference(Ref)),
    ?assertMatch(ok, t_call(Pa, die)),
    ?assertMatch({gproc,{failover,Pb},Ref,Na}, got_msg(Pb, gproc)),
    ?assertMatch(ok, t_lookup_everywhere(Na, Ns, Pb)),
    Pc = t_spawn(A, true),
    Ref1 = t_call(Pc, {apply, gproc, monitor, [Na, standby]}),
    ?assertMatch(true, t_call(Pb, {apply, gproc, unreg, [Na]})),
    ?assertMatch({gproc,unreg,Ref1,Na}, got_msg(Pc, gproc)),
    ?assertMatch(ok, t_lookup_everywhere(Na, Ns, undefined)).

t_follow_monitor([A,B|_]) ->
    Na = ?T_NAME,
    Pa = t_spawn(A, _Selective = true),
    Ref = t_call(Pa, {apply, gproc, monitor, [Na, follow]}),
    {gproc,unreg,Ref,Na} = got_msg(Pa),
    Pb = t_spawn_reg(B, Na),
    {gproc,registered,Ref,Na} = got_msg(Pa),
    ok = t_call(Pb, die),
    ok = t_call(Pa, die).

t_subscribe([A,B|_] = Ns) ->
    Na = ?T_NAME,
    Pb = t_spawn(B, _Selective = true),
    ?assertEqual(ok, t_call(Pb, {apply, gproc_monitor, subscribe, [Na]})),
    ?assertMatch({gproc_monitor, Na, undefined}, got_msg(Pb, gproc_monitor)),
    Pa = t_spawn_reg(A, Na),
    ?assertMatch({gproc_monitor, Na, Pa}, got_msg(Pb, gproc_monitor)),
    Pc = t_spawn(A),
    t_call(Pa, {apply, gproc, give_away, [Na, Pc]}),
    ?assertMatch(ok, t_lookup_everywhere(Na, Ns, Pc)),
    ?assertEqual({gproc_monitor,Na,{migrated,Pc}}, got_msg(Pb, gproc_monitor)),
    ?assertEqual(ok, t_call(Pc, die)),
    ?assertEqual({gproc_monitor,Na,undefined}, got_msg(Pb, gproc_monitor)),
    ok.

%% got_msg(Pb, Tag) ->
%%     t_call(Pb,
%% 	   {apply_fun,
%% 	    fun() ->
%% 		    receive
%% 			M when element(1, M) == Tag ->
%% 			    M
%% 		    after 1000 ->
%% 			    erlang:error({timeout, got_msg, [Pb, Tag]})
%% 		    end
%% 	    end}).

%% Verify that the gproc_dist:sync() call returns true even if a candidate dies
%% while the sync is underway. This test makes use of sys:suspend() to ensure that
%% the other candidate doesn't respond too quickly.
t_sync_cand_dies([A,B|_]) ->
    Leader = rpc:call(A, gproc_dist, get_leader, []),
    Other = case Leader of
		A -> B;
		B -> A
	    end,
    ?assertMatch(ok, rpc:call(Other, sys, suspend, [gproc_dist])),
    P = rpc:call(Other, erlang, whereis, [gproc_dist]),
    Key = rpc:async_call(Leader, gproc_dist, sync, []),
    %% The overall timeout for gproc_dist:sync() is 5 seconds. Here, we should
    %% still be waiting.
    ?assertMatch(timeout, rpc:nb_yield(Key, 1000)),
    exit(P, kill),
    %% The leader should detect that the other candidate died and respond
    %% immediately. Therefore, we should have our answer well within 1 sec.
    ?assertMatch({value, true}, rpc:nb_yield(Key, 1000)).

t_fail_node([A,B|_] = Ns) ->
    Na = ?T_NAME,
    Nb = ?T_NAME,
    Pa = t_spawn_reg(A, Na),
    Pb = t_spawn_reg(B, Nb),
    ?assertMatch(ok, rpc:call(A, application, stop, [gproc])),
    ?assertMatch(ok, t_lookup_everywhere(Na, Ns -- [A], undefined)),
    ?assertMatch(ok, t_lookup_everywhere(Nb, Ns -- [A], Pb)),
    ?assertMatch(ok, rpc:call(A, application, start, [gproc])),
    ?assertMatch(ok, t_lookup_everywhere(Na, Ns, undefined)),
    ?assertMatch(ok, t_lookup_everywhere(Nb, Ns, Pb)),
    ?assertMatch(ok, t_call(Pa, die)),
    ?assertMatch(ok, t_call(Pb, die)).

t_master_dies([A,B,C] = Ns) ->
    Na = ?T_NAME,
    Nb = ?T_NAME,
    Nc = ?T_NAME,
    Pa = t_spawn_reg(A, Na),
    Pb = t_spawn_reg(B, Nb),
    Pc = t_spawn_reg(C, Nc),
    L = rpc:call(A, gproc_dist, get_leader, []),
    ?assertMatch(ok, t_lookup_everywhere(Na, Ns, Pa)),
    ?assertMatch(ok, t_lookup_everywhere(Nb, Ns, Pb)),
    ?assertMatch(ok, t_lookup_everywhere(Nc, Ns, Pc)),
    {Nl, Pl} = case L of
                   A -> {Na, Pa};
                   B -> {Nb, Pb};
                   C -> {Nc, Pc}
               end,
    ?assertMatch(true, rpc:call(A, gproc_dist, sync, [])),
    ?assertMatch(ok, rpc:call(L, application, stop, [gproc])),
    Names = [{Na,Pa}, {Nb,Pb}, {Nc,Pc}] -- [{Nl, Pl}],
    RestNs = Ns -- [L],
    ?assertMatch(true, rpc:call(hd(RestNs), gproc_dist, sync, [])),
    ?assertMatch(ok, t_lookup_everywhere(Nl, RestNs, undefined)),
    [?assertMatch(ok, t_lookup_everywhere(Nx, RestNs, Px))
     || {Nx, Px} <- Names],
    ok.

t_sleep() ->
    timer:sleep(500).

t_lookup_everywhere(Key, Nodes, Exp) ->
    t_lookup_everywhere(Key, Nodes, Exp, 3).

t_lookup_everywhere(Key, _, Exp, 0) ->
    {lookup_failed, Key, Exp};
t_lookup_everywhere(Key, Nodes, Exp, I) ->
    Expected = [{N, Exp} || N <- Nodes],
    Found = [{N,rpc:call(N, gproc, where, [Key])} || N <- Nodes],
    if Expected =/= Found ->
	    ?debugFmt("lookup ~p failed~n"
		      "(Expected: ~p;~n"
		      " Found   : ~p), retrying...~n",
		      [Key, Expected, Found]),
	    t_sleep(),
	    t_lookup_everywhere(Key, Nodes, Exp, I-1);
       true ->
	    ok
    end.

t_read_everywhere(Key, Pid, Nodes, Exp) ->
    t_read_everywhere(Key, Pid, Nodes, Exp, 3).

t_read_everywhere(Key, _, _, Exp, 0) ->
    {read_failed, Key, Exp};
t_read_everywhere(Key, Pid, Nodes, Exp, I) ->
    Expected = [{N, Exp} || N <- Nodes],
    Found = [{N, read_result(rpc:call(N, gproc, get_value, [Key, Pid]))}
	     || N <- Nodes],
    if Expected =/= Found ->
	    ?debugFmt("read ~p failed~n"
		      "(Expected: ~p;~n"
		      " Found   : ~p), retrying...~n",
		      [{Key, Pid}, Expected, Found]),
	    t_sleep(),
	    t_read_everywhere(Key, Pid, Nodes, Exp, I-1);
       true ->
	    ok
    end.

read_result({badrpc, {'EXIT', {badarg, _}}}) -> badarg;
read_result(R) -> R.

t_spawn(Node) -> gproc_test_lib:t_spawn(Node).
t_spawn(Node, Selective) -> gproc_test_lib:t_spawn(Node, Selective).
t_spawn_mreg(Node, KVL) -> gproc_test_lib:t_spawn_mreg(Node, KVL).
t_spawn_reg(Node, N) -> gproc_test_lib:t_spawn_reg(Node, N).
t_spawn_reg(Node, N, V) -> gproc_test_lib:t_spawn_reg(Node, N, V).
t_spawn_reg(Node, N, V, As) -> gproc_test_lib:t_spawn_reg(Node, N, V, As).
t_spawn_reg_shared(Node, N, V) -> gproc_test_lib:t_spawn_reg_shared(Node, N, V).
got_msg(P) -> gproc_test_lib:got_msg(P).
got_msg(P, Tag) -> gproc_test_lib:got_msg(P, Tag).

t_call(P, Req) ->
    gproc_test_lib:t_call(P, Req).

start_slaves(Ns) ->
    [H|T] = Nodes = [start_slave(N) || N <- Ns],
    _ = [rpc:call(H, net_adm, ping, [N]) || N <- T],
    Nodes.

start_slave(Name) ->
    case node() of
        nonode@nohost ->
            os:cmd("epmd -daemon"),
            {ok, _} = net_kernel:start([gproc_master, shortnames]);
        _ ->
            ok
    end,
    {Pa, Pz} = paths(),
    Paths = "-pa ./ -pz ../ebin" ++
        lists:flatten([[" -pa " ++ Path || Path <- Pa],
		       [" -pz " ++ Path || Path <- Pz]]),
    {ok, Node} = slave:start(host(), Name, Paths),
    Node.

paths() ->
    Path = code:get_path(),
    {ok, [[Root]]} = init:get_argument(root),
    {Pas, Rest} = lists:splitwith(fun(P) ->
					  not lists:prefix(Root, P)
				  end, Path),
    {_, Pzs} = lists:splitwith(fun(P) ->
				       lists:prefix(Root, P)
			       end, Rest),
    {Pas, Pzs}.


host() ->
    [_Name, Host] = re:split(atom_to_list(node()), "@", [{return, list}]),
    list_to_atom(Host).

-endif.
