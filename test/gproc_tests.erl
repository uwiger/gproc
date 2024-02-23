%% -*- erlang-indent-level: 4;indent-tabs-mode: nil -*-
%% --------------------------------------------------
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%% --------------------------------------------------
%%
%% @author Ulf Wiger <ulf@wiger.net>
%%
-module(gproc_tests).

-ifdef(TEST).

-include_lib("eunit/include/eunit.hrl").
-include_lib("stdlib/include/qlc.hrl").

-define(T_NAME, {n, l, {?MODULE, ?LINE, erlang:timestamp()}}).

conf_test_() ->
    {foreach,
     fun() ->
             application:stop(gproc),
	     application:unload(gproc)
     end,
     fun(_) ->
	     application:stop(gproc)
     end,
     [?_test(t_server_opts()),
      ?_test(t_ets_opts())]}.

t_server_opts() ->
    H = 10000,
    application:set_env(gproc, server_options, [{min_heap_size, H}]),
    ?assertMatch(ok, application:start(gproc)),
    {min_heap_size, H1} = process_info(whereis(gproc), min_heap_size),
    ?assert(is_integer(H1) andalso H1 > H).

t_ets_opts() ->
    %% Cannot inspect the write_concurrency attribute on an ets table in
    %% any easy way, so trace on the ets:new/2 call and check the arguments.
    application:set_env(gproc, ets_options, [{write_concurrency, false}]),
    erlang:trace_pattern({ets,new, 2}, [{[gproc,'_'],[],[]}], [global]),
    erlang:trace(new, true, [call]),
    ?assert(ok == application:start(gproc)),
    erlang:trace(new, false, [call]),
    receive
	{trace,_,call,{ets,new,[gproc,Opts]}} ->
	    ?assertMatch({write_concurrency, false},
			 lists:keyfind(write_concurrency,1,Opts))
    after 3000 ->
	    error(timeout)
    end.



reg_test_() ->
    {setup,
     fun() ->
             application:start(gproc),
	     application:start(mnesia)
     end,
     fun(_) ->
             application:stop(gproc),
	     application:stop(mnesia)
     end,
     [
      {spawn, ?_test(?debugVal(t_simple_reg()))}
      , ?_test(t_is_clean())
      , {spawn, ?_test(?debugVal(t_simple_reg_other()))}
      , ?_test(t_is_clean())
      , ?_test(?debugVal(t_simple_ensure()))
      , ?_test(t_is_clean())
      , ?_test(?debugVal(t_simple_ensure_other()))
      , ?_test(t_is_clean())
      , ?_test(?debugVal(t_simple_ensure_prop()))
      , ?_test(t_is_clean())
      , {spawn, ?_test(?debugVal(t_simple_reg_or_locate()))}
      , ?_test(t_is_clean())
      , {spawn, ?_test(?debugVal(t_reg_or_locate2()))}
      , ?_test(t_is_clean())
      , {spawn, ?_test(?debugVal(t_reg_or_locate3()))}
      , ?_test(t_is_clean())
      , {spawn, ?_test(?debugVal(t_simple_counter()))}
      , ?_test(t_is_clean())
      , {spawn, ?_test(?debugVal(t_simple_aggr_counter()))}
      , ?_test(t_is_clean())
      , {spawn, ?_test(?debugVal(t_awaited_aggr_counter()))}
      , ?_test(t_is_clean())
      , {spawn, ?_test(?debugVal(t_simple_resource_count()))}
      , ?_test(t_is_clean())
      , {spawn, ?_test(?debugVal(t_wild_resource_count()))}
      , ?_test(t_is_clean())
      , {spawn, ?_test(?debugVal(t_wild_in_resource()))}
      , ?_test(t_is_clean())
      , {spawn, ?_test(?debugVal(t_awaited_resource_count()))}
      , ?_test(t_is_clean())
      , {spawn, ?_test(?debugVal(t_resource_count_on_zero_send()))}
      , ?_test(t_is_clean())
      , {spawn, ?_test(?debugVal(t_update_counters()))}
      , ?_test(t_is_clean())
      , {spawn, ?_test(?debugVal(t_update_r_counter()))}
      , ?_test(t_is_clean())
      , {spawn, ?_test(?debugVal(t_update_n_counter()))}
      , ?_test(t_is_clean())
      , {spawn, ?_test(?debugVal(t_simple_prop()))}
      , ?_test(t_is_clean())
      , {spawn, ?_test(?debugVal(t_await()))}
      , ?_test(t_is_clean())
      , {spawn, ?_test(?debugVal(t_await_self()))}
      , ?_test(t_is_clean())
      , {spawn, ?_test(?debugVal(t_await_crash()))}
      , ?_test(t_is_clean())
      , {spawn, ?_test(?debugVal(t_simple_mreg()))}
      , ?_test(t_is_clean())
      , {spawn, ?_test(?debugVal(t_mreg_props()))}
      , ?_test(t_is_clean())
      , {spawn, ?_test(?debugVal(t_gproc_crash()))}
      , ?_test(t_is_clean())
      , {spawn, ?_test(?debugVal(t_cancel_wait_and_register()))}
      , ?_test(t_is_clean())
      , {spawn, ?_test(?debugVal(t_give_away_to_pid()))}
      , ?_test(t_is_clean())
      , {spawn, ?_test(?debugVal(t_give_away_to_self()))}
      , ?_test(t_is_clean())
      , {spawn, ?_test(?debugVal(t_give_away_badarg()))}
      , ?_test(t_is_clean())
      , {spawn, ?_test(?debugVal(t_give_away_to_unknown()))}
      , ?_test(t_is_clean())
      , {spawn, ?_test(?debugVal(t_give_away_and_back()))}
      , ?_test(t_is_clean())
      , {spawn, ?_test(?debugVal(t_select()))}
      , ?_test(t_is_clean())
      , {spawn, ?_test(?debugVal(t_select_count()))}
      , ?_test(t_is_clean())
      , {spawn, ?_test(?debugVal(t_qlc()))}
      , ?_test(t_is_clean())
      , {spawn, ?_test(?debugVal(t_qlc_dead()))}
      , ?_test(t_is_clean())
      , {spawn, ?_test(?debugVal(t_get_env()))}
      , ?_test(t_is_clean())
      , {spawn, ?_test(?debugVal(t_get_set_env()))}
      , ?_test(t_is_clean())
      , {spawn, ?_test(?debugVal(t_set_env()))}
      , ?_test(t_is_clean())
      , {spawn, ?_test(?debugVal(t_get_env_inherit()))}
      , ?_test(t_is_clean())
      , {spawn, ?_test(?debugVal(t_monitor()))}
      , ?_test(t_is_clean())
      , {spawn, ?_test(?debugVal(t_monitor_give_away()))}
      , ?_test(t_is_clean())
      , {spawn, ?_test(?debugVal(t_monitor_standby()))}
      , ?_test(t_is_clean())
      , {spawn, ?_test(?debugVal(t_monitor_follow()))}
      , ?_test(t_is_clean())
      , {spawn, ?_test(?debugVal(t_two_monitoring_processes_one_dies()))}
      , ?_test(t_is_clean())
      , {spawn, ?_test(?debugVal(t_monitor_demonitor()))}
      , ?_test(t_is_clean())
      , {spawn, ?_test(?debugVal(t_subscribe()))}
      , ?_test(t_is_clean())
      , {spawn, ?_test(?debugVal(t_gproc_info()))}
      , ?_test(t_is_clean())
      , {spawn, ?_test(?debugVal(t_simple_pool()))}
      , ?_test(t_is_clean())
      , {spawn, ?_test(?debugVal(t_pool_add_worker_size_1_no_auto_size()))}
      , ?_test(t_is_clean())
      , {spawn, ?_test(?debugVal(t_pool_add_worker_size_2_no_auto_size()))}
      , ?_test(t_is_clean())
      , {spawn, ?_test(?debugVal(t_pool_round_robin_disconnect_worker()))}
      , ?_test(t_is_clean())
      , {spawn, ?_test(?debugVal(t_pubsub()))}
      , ?_test(t_is_clean())
      , {spawn, ?_test(?debugVal(t_singles()))}
      , ?_test(t_is_clean())
      , {spawn, ?_test(?debugVal(t_ps_cond()))}
      , ?_test(t_is_clean())
     ]}.

t_simple_reg() ->
    ?assert(gproc:reg({n,l,name}) =:= true),
    ?assert(gproc:where({n,l,name}) =:= self()),
    ?assert(gproc:unreg({n,l,name}) =:= true),
    ?assert(gproc:where({n,l,name}) =:= undefined).

t_simple_reg_other() ->
    P = self(),
    P1 = spawn_link(fun() ->
                            receive
                                {P, goodbye} -> ok
                            end
                    end),
    Ref = erlang:monitor(process, P1),
    ?assert(gproc:reg_other({n,l,name}, P1) =:= true),
    ?assert(gproc:where({n,l,name}) =:= P1),
    ?assert(gproc:unreg_other({n,l,name}, P1) =:= true),
    ?assert(gproc:where({n,l,name}) =:= undefined),
    P1 ! {self(), goodbye},
    receive
        {'DOWN', Ref, _, _, _} ->
            ok
    end.

t_simple_ensure() ->
    P = self(),
    Key = {n,l,name},
    ?assert(gproc:reg(Key) =:= true),
    ?assert(gproc:where(Key) =:= P),
    ?assert(gproc:ensure_reg(Key, new_val, [{a,1}]) =:= updated),
    ?assert(gproc:get_attributes(Key) =:= [{a,1}]),
    ?assert(gproc:unreg(Key) =:= true),
    ?assert(gproc:where(Key) =:= undefined).

t_simple_ensure_other() ->
    P = self(),
    Key = {n,l,name},
    P1 = spawn_link(fun() ->
                            receive
                                {P, goodbye} -> ok
                            end
                    end),
    Ref = erlang:monitor(process, P1),
    ?assert(gproc:reg_other(Key, P1) =:= true),
    ?assert(gproc:where(Key) =:= P1),
    ?assert(gproc:ensure_reg_other(Key, P1, new_val, [{a,1}]) =:= updated),
    ?assert(gproc:get_value(Key, P1) =:= new_val),
    ?assert(gproc:get_attributes(Key, P1) =:= [{a,1}]),
    ?assert(gproc:unreg_other(Key, P1) =:= true),
    ?assert(gproc:where({n,l,name}) =:= undefined),
    P1 ! {self(), goodbye},
    receive
        {'DOWN', Ref, _, _, _} ->
            ok
    end.

t_simple_ensure_prop() ->
    Key = {p,l,?LINE},
    P = self(),
    Select = fun() ->
                     gproc:select({l,p}, [{ {Key,'_','_'},[],['$_'] }])
             end,
    ?assertMatch(new, gproc:ensure_reg(Key, first_val, [])),
    ?assertMatch([{Key,P,first_val}], Select()),
    ?assertMatch(updated, gproc:ensure_reg(Key, new_val, [{a,1}])),
    ?assertMatch([{Key,P,new_val}], Select()),
    ?assertMatch([{a,1}], gproc:get_attributes(Key)),
    ?assertMatch(true, gproc:unreg(Key)),
    ?assertMatch([], Select()).

t_simple_reg_or_locate() ->
    P = self(),
    ?assertMatch({P, undefined}, gproc:reg_or_locate({n,l,name})),
    ?assertMatch(P, gproc:where({n,l,name})),
    ?assertMatch({P, my_val}, gproc:reg_or_locate({n,l,name2}, my_val)),
    ?assertMatch(my_val, gproc:get_value({n,l,name2})).

t_reg_or_locate2() ->
    P = self(),
    {P1,R1} = spawn_monitor(fun() ->
				    Ref = erlang:monitor(process, P),
				    gproc:reg({n,l,foo}, the_value),
				    P ! {self(), ok},
				    receive
					{'DOWN',Ref,_,_,_} -> ok
				    end
			    end),
    receive {P1, ok} -> ok end,
    ?assertMatch({P1, the_value}, gproc:reg_or_locate({n,l,foo})),
    exit(P1, kill),
    receive
	{'DOWN',R1,_,_,_} ->
	    ok
    end.

t_reg_or_locate3() ->
    P = self(),
    {P1, Value} = gproc:reg_or_locate(
		     {n,l,foo}, the_value,
		     fun() ->
                             PRef = erlang:monitor(process, P),
			     P ! {self(), ok},
			     receive
				 {'DOWN',PRef,_,_,_} -> ok
			     end
		     end),
    ?assert(P =/= P1),
    ?assert(Value =:= the_value),
    ERef = erlang:monitor(process, P1),
    receive
	{P1, ok} -> ok;
	{'DOWN', ERef, _, _, _Reason} ->
	    ?assert(process_died_unexpectedly)
    end,
    ?assertMatch({P1, the_value}, gproc:reg_or_locate({n,l,foo})),
    exit(P1, kill),
    receive
	{'DOWN',_R1,_,_,_} ->
	    ok
    end.

t_simple_counter() ->
    ?assert(gproc:reg({c,l,c1}, 3) =:= true),
    ?assert(gproc:get_value({c,l,c1}) =:= 3),
    ?assert(gproc:update_counter({c,l,c1}, 4) =:= 7),
    ?assert(gproc:reset_counter({c,l,c1}) =:= {7, 3}).

t_simple_aggr_counter() ->
    ?assert(gproc:reg({c,l,c1}, 3) =:= true),
    ?assert(gproc:reg({a,l,c1}) =:= true),
    ?assert(gproc:get_value({a,l,c1}) =:= 3),
    P = self(),
    P1 = spawn_link(fun() ->
			    gproc:reg({c,l,c1}, 5),
			    P ! {self(), ok},
			    receive
				{P, goodbye} -> ok
			    end
		    end),
    receive {P1, ok} -> ok end,
    ?assert(gproc:get_value({a,l,c1}) =:= 8),
    ?assert(gproc:update_counter({c,l,c1}, 4) =:= 7),
    ?assert(gproc:get_value({a,l,c1}) =:= 12),
    P1 ! {self(), goodbye},
    R = erlang:monitor(process, P1),
    receive {'DOWN', R, _, _, _} ->
	    gproc:audit_process(P1)
    end,
    ?assert(gproc:get_value({a,l,c1}) =:= 7).

t_awaited_aggr_counter() ->
    ?assert(gproc:reg({c,l,c1}, 3) =:= true),
    gproc:nb_wait({a,l,c1}),
    ?assert(gproc:reg({a,l,c1}) =:= true),
    receive {gproc,_,registered,{{a,l,c1},_,_}} -> ok
    after 1000 ->
            error(timeout)
    end,
    ?assertMatch(3, gproc:get_value({a,l,c1})).

t_simple_resource_count() ->
    ?assert(gproc:reg({r,l,r1}, 1) =:= true),
    ?assert(gproc:reg({rc,l,r1}) =:= true),
    ?assert(gproc:get_value({rc,l,r1}) =:= 1),
    P = self(),
    P1 = spawn_link(fun() ->
                            gproc:reg({r,l,r1}, 1),
                            P ! {self(), ok},
                            receive
                                {P, goodbye} -> ok
                            end
                    end),
    receive {P1, ok} -> ok end,
    ?assert(gproc:get_value({rc,l,r1}) =:= 2),
    P1 ! {self(), goodbye},
    R = erlang:monitor(process, P1),
    receive {'DOWN', R, _, _, _} ->
            gproc:audit_process(P1)
    end,
    ?assert(gproc:get_value({rc,l,r1}) =:= 1).

t_wild_resource_count() ->
    ?assert(gproc:reg({r,l,{r1,1}}, 1) =:= true),
    ?assert(gproc:reg({rc,l,{r1,'\\_'}}) =:= true),
    ?assert(gproc:reg({rc,l,{r1,1}}) =:= true),
    ?assert(gproc:get_value({rc,l,{r1,'\\_'}}) =:= 1),
    ?assert(gproc:get_value({rc,l,{r1,1}}) =:= 1),
    P = self(),
    P1 = spawn_link(fun() ->
                            gproc:reg({r,l,{r1,2}}, 1),
                            P ! {self(), ok},
                            receive
                                {P, goodbye} -> ok
                            end
                    end),
    receive {P1, ok} -> ok end,
    ?assert(gproc:get_value({rc,l,{r1,1}}) =:= 1),
    ?assert(gproc:get_value({rc,l,{r1,'\\_'}}) =:= 2),
    P1 ! {self(), goodbye},
    R = erlang:monitor(process, P1),
    receive {'DOWN', R, _, _, _} ->
            gproc:audit_process(P1)
    end,
    ?assert(gproc:get_value({rc,l,{r1,1}}) =:= 1),
    ?assert(gproc:get_value({rc,l,{r1,'\\_'}}) =:= 1).

-define(FAILS(E), try
                      E,
                      error(unexpected)
                  catch error:badarg ->
                          ok
                  end).

t_wild_in_resource() ->
    ?FAILS(gproc:reg({r,l,{a,b,'\\_'}})),
    ?FAILS(gproc:mreg(r, l, [{{a,b,'\\_'}, 1}])).

t_awaited_resource_count() ->
    ?assert(gproc:reg({r,l,r1}, 3) =:= true),
    ?assert(gproc:reg({r,l,r2}, 3) =:= true),
    ?assert(gproc:reg({r,l,r3}, 3) =:= true),
    gproc:nb_wait({rc,l,r1}),
    ?assert(gproc:reg({rc,l,r1}) =:= true),
    receive {gproc,_,registered,{{rc,l,r1},_,_}} -> ok
    after 1000 ->
            error(timeout)
    end,
    ?assertMatch(1, gproc:get_value({rc,l,r1})).

t_resource_count_on_zero_send() ->
    Me = self(),
    ?assertMatch(true, gproc:reg({p,l,myp})),
    ?assertMatch(true, gproc:reg({r,l,r1})),
    ?assertMatch(true, gproc:reg({rc,l,r1}, 1, [{on_zero,
                                                 [{send, {p,l,myp}}]}])),
    ?assertMatch(1, gproc:get_value({rc,l,r1})),
    ?assertMatch(true, gproc:unreg({r,l,r1})),
    ?assertMatch(0, gproc:get_value({rc,l,r1})),
    receive
        {gproc, resource_on_zero, l, r1, Me} ->
            ok
    after 1000 ->
            error(timeout)
    end.

t_update_counters() ->
    ?assert(gproc:reg({c,l,c1}, 3) =:= true),
    ?assert(gproc:reg({a,l,c1}) =:= true),
    ?assert(gproc:get_value({a,l,c1}) =:= 3),
    P = self(),
    P1 = spawn_link(fun() ->
			    gproc:reg({c,l,c1}, 5),
			    P ! {self(), ok},
			    receive
				{P, goodbye} -> ok
			    end
		    end),
    receive {P1, ok} -> ok end,
    ?assert(gproc:get_value({a,l,c1}) =:= 8),
    Me = self(),
    ?assertEqual([{{c,l,c1},Me,7},
		  {{c,l,c1},P1,8}], gproc:update_counters(l, [{{c,l,c1}, Me, 4},
							      {{c,l,c1}, P1, 3}])),
    ?assert(gproc:get_value({a,l,c1}) =:= 15),
    P1 ! {self(), goodbye},
    R = erlang:monitor(process, P1),
    receive {'DOWN', R, _, _, _} ->
	    gproc:audit_process(P1)
    end,
    ?assert(gproc:get_value({a,l,c1}) =:= 7).

t_update_r_counter() ->
    K = {r,l,r1},
    ?assert(gproc:reg(K, 3) =:= true),
    ?assertEqual(5, gproc:update_counter(K, 2)),
    ?assert(gproc:get_value(K) =:= 5).

t_update_n_counter() ->
    K = {n,l,n1},
    ?assert(gproc:reg(K, 3) =:= true),
    ?assertEqual(5, gproc:update_counter(K, 2)),
    ?assert(gproc:get_value(K) =:= 5).

t_simple_prop() ->
    ?assert(gproc:reg({p,l,prop}) =:= true),
    ?assert(t_other_proc(fun() ->
                                 ?assert(gproc:reg({p,l,prop}) =:= true)
                         end) =:= ok),
    ?assert(gproc:unreg({p,l,prop}) =:= true).

t_other_proc(F) ->
    {_Pid,Ref} = spawn_monitor(fun() -> exit(F()) end),
    receive
        {'DOWN',Ref,_,_,R} ->
            R
    after 10000 ->
            erlang:error(timeout)
    end.

t_await() ->
    Me = self(),
    Name = {n,l,t_await},
    {_Pid,Ref} = spawn_monitor(
                   fun() ->
			   exit(?assert(
				   gproc:await(Name) =:= {Me,val}))
		   end),
    ?assert(gproc:reg(Name, val) =:= true),
    receive
        {'DOWN', Ref, _, _, R} ->
            ?assertEqual(R, ok)
    after 10000 ->
            erlang:error(timeout)
    end,
    ?assertMatch(Me, gproc:where(Name)),
    ok.

t_await_self() ->
    Me = self(),
    Ref = gproc:nb_wait({n, l, t_await_self}),
    ?assert(gproc:reg({n, l, t_await_self}, some_value) =:= true),
    ?assertEqual(true, receive
			   {gproc, Ref, R, Wh} ->
			       {registered, {{n, l, t_await_self},
					     Me, some_value}} = {R, Wh},
			       true
		       after 10000 ->
			       timeout
		       end).

t_await_crash() ->
    Name = {n,l,{dummy,?LINE}},
    {Pid,_} = spawn_regger(Name),
    ?assertEqual({Pid,undefined}, gproc:await(Name, 1000)),
    exit(Pid, kill),
    {NewPid,MRef} = spawn_regger(Name),
    ?assertEqual(false, is_process_alive(Pid)),
    ?assertEqual({NewPid,undefined}, gproc:await(Name, 1000)),
    exit(NewPid, kill),
    receive {'DOWN', MRef, _, _, _} -> ok end.

spawn_regger(Name) ->
    spawn_monitor(fun() ->
			  gproc:reg(Name),
			  timer:sleep(60000)
		  end).

t_is_clean() ->
    sys:get_status(gproc), % in order to synch
    sys:get_status(gproc_monitor),
    T = ets:tab2list(gproc),
    Tm = ets:tab2list(gproc_monitor),
    ?assertMatch([], Tm),
    ?assertMatch([], T -- [{{whereis(gproc_monitor), l}},
                           {{self(), l}}]).

t_simple_mreg() ->
    P = self(),
    ?assertEqual(true, gproc:mreg(n, l, [{foo, foo_val},
					 {bar, bar_val}])),
    ?assertEqual(P, gproc:where({n,l,foo})),
    ?assertEqual(P, gproc:where({n,l,bar})),
    ?assertEqual(true, gproc:munreg(n, l, [foo, bar])).

t_mreg_props() ->
    P = self(),
    ?assertEqual(true, gproc:mreg(p, l, [{p, v}])),
    ?assertEqual(v, gproc:get_value({p,l,p})),
    %% Force a context switch, since gproc:monitor_me() is asynchronous
    _ = sys:get_status(gproc),
    {monitors, Mons} = process_info(whereis(gproc), monitors),
    ?assertEqual(true, lists:keymember(P, 2, Mons)).


t_gproc_crash() ->
    P = spawn_helper(),
    ?assert(gproc:where({n,l,P}) =:= P),
    exit(whereis(gproc), kill),
    give_gproc_some_time(100),
    ?assert(whereis(gproc) =/= undefined),
    %%
    %% Check that the registration is still there using an ets:lookup(),
    %% Once we've killed the process, gproc will always return undefined
    %% if the process is not alive, regardless of whether the registration
    %% is still there. So, here, the lookup should find something...
    %%
    ?assert(ets:lookup(gproc,{{n,l,P},n}) =/= []),
    ?assert(gproc:where({n,l,P}) =:= P),
    exit(P, kill),
    %% ...and here, it shouldn't.
    %% (sleep for a while first to let gproc handle the EXIT
    give_gproc_some_time(10),
    ?assert(ets:lookup(gproc,{{n,l,P},n}) =:= []).

t_cancel_wait_and_register() ->
    Alias = {n, l, foo},
    Me = self(),
    P = spawn(fun() ->
		      {'EXIT',_} = (catch gproc:await(Alias, 100)),
		      ?assert(element(1,sys:get_status(gproc)) == status),
		      Me ! {self(), go_ahead},
		      timer:sleep(infinity)
	      end),
    receive
	{P, go_ahead} ->
	    ?assertEqual(gproc:reg(Alias, undefined), true),
	    exit(P, kill),
	    timer:sleep(500),
	    ?assert(element(1,sys:get_status(gproc)) == status)
    end.


t_give_away_to_pid() ->
    From = {n, l, foo},
    Me = self(),
    P = spawn_link(fun t_loop/0),
    ?assertEqual(true, gproc:reg(From, undefined)),
    ?assertEqual(Me, gproc:where(From)),
    ?assertEqual(P, gproc:give_away(From, P)),
    ?assertEqual(P, gproc:where(From)),
    ?assertEqual(ok, t_lcall(P, die)).

t_give_away_to_self() ->
    From = {n, l, foo},
    Me = self(),
    ?assertEqual(true, gproc:reg(From, undefined)),
    ?assertEqual(Me, gproc:where(From)),
    ?assertEqual(Me, gproc:give_away(From, Me)),
    ?assertEqual(Me, gproc:where(From)),
    ?assertEqual(true, gproc:unreg(From)).

t_give_away_badarg() ->
    From = {n, l, foo},
    Me = self(),
    ?assertEqual(undefined, gproc:where(From)),
    ?assertError(badarg, gproc:give_away(From, Me)).

t_give_away_to_unknown() ->
    From = {n, l, foo},
    Unknown = {n, l, unknown},
    Me = self(),
    ?assertEqual(true, gproc:reg(From, undefined)),
    ?assertEqual(Me, gproc:where(From)),
    ?assertEqual(undefined, gproc:where(Unknown)),
    ?assertEqual(undefined, gproc:give_away(From, Unknown)),
    ?assertEqual(undefined, gproc:where(From)).

t_give_away_and_back() ->
    From = {n, l, foo},
    Me = self(),
    P = spawn_link(fun t_loop/0),
    ?assertEqual(true, gproc:reg(From, undefined)),
    ?assertEqual(Me, gproc:where(From)),
    ?assertEqual(P, gproc:give_away(From, P)),
    ?assertEqual(P, gproc:where(From)),
    ?assertEqual(ok, t_lcall(P, {give_away, From})),
    ?assertEqual(Me, gproc:where(From)),
    ?assertEqual(ok, t_lcall(P, die)).

t_select() ->
    ?assertEqual(true, gproc:reg({n, l, {n,1}}, x)),
    ?assertEqual(true, gproc:reg({n, l, {n,2}}, y)),
    ?assertEqual(true, gproc:reg({p, l, {p,1}}, x)),
    ?assertEqual(true, gproc:reg({p, l, {p,2}}, y)),
    ?assertEqual(true, gproc:reg({c, l, {c,1}}, 1)),
    ?assertEqual(true, gproc:reg({a, l, {c,1}}, undefined)),
    %% local names
    ?assertEqual(
       [{{n,l,{n,1}},self(),x},
	{{n,l,{n,2}},self(),y}], gproc:select(
				   {local,names},
				   [{{{n,l,'_'},'_','_'},[],['$_']}])),
    %% mactch local names on value
    ?assertEqual(
       [{{n,l,{n,1}},self(),x}], gproc:select(
				   {local,names},
				   [{{{n,l,'_'},'_',x},[],['$_']}])),
    %% match all on value
    ?assertEqual(
       [{{n,l,{n,1}},self(),x},
	{{p,l,{p,1}},self(),x}], gproc:select(
				   {all,all},
				   [{{{'_',l,'_'},'_',x},[],['$_']}])),
    %% match all on pid
    ?assertEqual(
       [{{a,l,{c,1}},self(),1},
	{{c,l,{c,1}},self(),1},
	{{n,l,{n,1}},self(),x},
	{{n,l,{n,2}},self(),y},
	{{p,l,{p,1}},self(),x},
	{{p,l,{p,2}},self(),y}
       ], gproc:select(
	    {all,all},
	    [{{'_',self(),'_'},[],['$_']}])).

t_select_count() ->
    ?assertEqual(true, gproc:reg({n, l, {n,1}}, x)),
    ?assertEqual(true, gproc:reg({n, l, {n,2}}, y)),
    ?assertEqual(true, gproc:reg({p, l, {p,1}}, x)),
    ?assertEqual(true, gproc:reg({p, l, {p,2}}, y)),
    ?assertEqual(true, gproc:reg({c, l, {c,1}}, 1)),
    ?assertEqual(true, gproc:reg({a, l, {c,1}}, undefined)),
    %% local names
    ?assertEqual(2, gproc:select_count(
		      {local,names}, [{{{n,l,'_'},'_','_'},[],[true]}])),
    %% mactch local names on value
    ?assertEqual(1, gproc:select_count(
		      {local,names}, [{{{n,l,'_'},'_',x},[],[true]}])),
    %% match all on value
    ?assertEqual(2, gproc:select_count(
		      {all,all}, [{{{'_',l,'_'},'_',x},[],[true]}])),
    %% match all on pid
    ?assertEqual(6, gproc:select_count(
		      {all,all}, [{{'_',self(),'_'},[],[true]}])).

t_qlc() ->
    ?assertEqual(true, gproc:reg({n, l, {n,1}}, x)),
    ?assertEqual(true, gproc:reg({n, l, {n,2}}, y)),
    ?assertEqual(true, gproc:reg({p, l, {p,1}}, x)),
    ?assertEqual(true, gproc:reg({p, l, {p,2}}, y)),
    ?assertEqual(true, gproc:reg({c, l, {c,1}}, 1)),
    ?assertEqual(true, gproc:reg({a, l, {c,1}}, undefined)),
    %% local names
    Exp1 = [{{n,l,{n,1}},self(),x},
	    {{n,l,{n,2}},self(),y}],
    ?assertEqual(Exp1,
		 qlc:e(qlc:q([N || N <- gproc:table(names)]))),
    ?assertEqual(Exp1,
		 qlc:e(qlc:q([N || {{n,l,_},_,_} = N <- gproc:table(names)]))),

    %% mactch local names on value
    Exp2 = [{{n,l,{n,1}},self(),x}],
    ?assertEqual(Exp2,
		 qlc:e(qlc:q([N || {{n,l,_},_,x} = N <- gproc:table(names)]))),

    %% match all on value
    Exp3 = [{{n,l,{n,1}},self(),x},
	    {{p,l,{p,1}},self(),x}],
    ?assertEqual(Exp3,
		 qlc:e(qlc:q([N || {_,_,x} = N <- gproc:table(all)]))),

    %% match all
    Exp4 = [{{a,l,{c,1}},self(),1},
	    {{c,l,{c,1}},self(),1},
	    {{n,l,{n,1}},self(),x},
	    {{n,l,{n,2}},self(),y},
	    {{p,l,{p,1}},self(),x},
	    {{p,l,{p,2}},self(),y}
	   ],
    ?assertEqual(Exp4,
		 qlc:e(qlc:q([X || X <- gproc:table(all)]))),
    %% match on pid
    ?assertEqual(Exp4,
		 qlc:e(qlc:q([{K,P,V} || {K,P,V} <-
					     gproc:table(all), P =:= self()]))),
    ?assertEqual(Exp4,
		 qlc:e(qlc:q([{K,P,V} || {K,P,V} <-
					     gproc:table(all), P == self()]))).

t_qlc_dead() ->
    P0 = self(),
    ?assertEqual(true, gproc:reg({n, l, {n,1}}, x)),
    ?assertEqual(true, gproc:reg({p, l, {p,1}}, x)),
    P1 = spawn(fun() ->
		       Ref = erlang:monitor(process, P0),
		       gproc:reg({n, l, {n,2}}, y),
		       gproc:reg({p, l, {p,2}}, y),
		       P0 ! {self(), ok},
		       receive
			   {_P, goodbye} -> ok;
			   {'DOWN', Ref, _, _, _} ->
			       ok
		       end
	       end),
    receive {P1, ok} -> ok end,
    %% now, suspend gproc so it doesn't do cleanup
    try  sys:suspend(gproc),
	 exit(P1, kill),
	 %% local names
	 Exp1 = [{{n,l,{n,1}},self(),x}],
	 ?assertEqual(Exp1,
		      qlc:e(qlc:q([N || N <-
					    gproc:table(names, [check_pids])]))),
	 ?assertEqual(Exp1,
		      qlc:e(qlc:q([N || {{n,l,_},_,_} = N <-
					    gproc:table(names, [check_pids])]))),
	 %% match local names on value
	 Exp2 = [{{n,l,{n,1}},self(),x}],
	 ?assertEqual(Exp2,
		      qlc:e(qlc:q([N || {{n,l,_},_,x} = N <-
					    gproc:table(names, [check_pids])]))),
	 ?assertEqual([],
		      qlc:e(qlc:q([N || {{n,l,_},_,y} = N <-
					    gproc:table(names, [check_pids])]))),
	 %% match all on value
	 Exp3 = [{{n,l,{n,1}},self(),x},
		 {{p,l,{p,1}},self(),x}],
	 ?assertEqual(Exp3,
		      qlc:e(qlc:q([N || {_,_,x} = N <-
					    gproc:table(all, [check_pids])]))),
	 ?assertEqual([],
		      qlc:e(qlc:q([N || {_,_,y} = N <-
					    gproc:table(all, [check_pids])]))),
	 Exp3b = [{{n,l,{n,2}},P1,y},
		  {{p,l,{p,2}},P1,y}],
	 ?assertEqual(Exp3b,
		      qlc:e(qlc:q([N || {_,_,y} = N <-
					    gproc:table(all)]))),

	 %% match all
	 Exp4 = [{{n,l,{n,1}},self(),x},
		 {{p,l,{p,1}},self(),x}],
	 ?assertEqual(Exp4,
		      qlc:e(qlc:q([X || X <-
					    gproc:table(all, [check_pids])]))),
	 %% match on pid
	 ?assertEqual(Exp4,
		 qlc:e(qlc:q([{K,P,V} || {K,P,V} <-
					     gproc:table(all, [check_pids]),
					 P =:= self()]))),
	 ?assertEqual([],
		 qlc:e(qlc:q([{K,P,V} || {K,P,V} <-
					     gproc:table(all, [check_pids]),
					 P =:= P1]))),
	 Exp4b = [{{n,l,{n,2}},P1,y},
		  {{p,l,{p,2}},P1,y}],
	 ?assertEqual(Exp4b,
		 qlc:e(qlc:q([{K,P,V} || {K,P,V} <-
					     gproc:table(all),
					 P =:= P1])))
    after
	sys:resume(gproc)
    end.


t_get_env() ->
    ?assertEqual(ok, application:set_env(gproc, ssss, "s1")),
    ?assertEqual(true, os:putenv("SSSS", "s2")),
    ?assertEqual(true, os:putenv("TTTT", "s3")),
    ?assertEqual(ok, application:set_env(gproc, aaaa, a)),
    ?assertEqual(undefined, gproc:get_env(l, gproc, ssss, [])),
    %%
    ?assertEqual("s1", gproc:get_env(l, gproc, ssss, [app_env])),
    ?assertEqual("s2", gproc:get_env(l, gproc, ssss, [os_env])),
    ?assertEqual("s1", gproc:get_env(l, gproc, ssss, [app_env, os_env])),
    ?assertEqual("s3", gproc:get_env(l, gproc, ssss, [{os_env,"TTTT"}])),
    ?assertEqual("s4", gproc:get_env(l, gproc, ssss, [{default,"s4"}])),
    %%
    ?assertEqual({atomic,ok}, mnesia:create_table(t, [{ram_copies, [node()]}])),
    ?assertEqual(ok, mnesia:dirty_write({t, foo, bar})),
    ?assertEqual(bar, gproc:get_env(l, gproc, some_env, [{mnesia,transaction,
							  {t, foo}, 3}])),
    ?assertEqual("erl", gproc:get_env(l, gproc, progname, [init_arg])).

t_get_set_env() ->
    ?assertEqual(ok, application:set_env(gproc, aaaa, a)),
    ?assertEqual(a, gproc:get_set_env(l, gproc, aaaa, [app_env])),
    ?assertEqual(ok, application:set_env(gproc, aaaa, undefined)),
    ?assertEqual(a, gproc:get_env(l, gproc, aaaa, [error])).

t_set_env() ->
    ?assertEqual(ok, application:set_env(gproc, aaaa, a)),
    ?assertEqual(a, gproc:get_set_env(l, gproc, aaaa, [app_env])),
    ?assertEqual(ok, application:set_env(gproc, aaaa, undefined)),
    ?assertEqual(b, gproc:set_env(l, gproc, aaaa, b, [app_env])),
    ?assertEqual({ok,b}, application:get_env(gproc, aaaa)),
    %%
    ?assertEqual(true, os:putenv("SSSS", "s0")),
    ?assertEqual("s0", gproc:get_env(l, gproc, ssss, [os_env])),
    ?assertEqual("s1", gproc:set_env(l, gproc, ssss, "s1", [os_env])),
    ?assertEqual("s1", os:getenv("SSSS")),
    ?assertEqual(true, os:putenv("SSSS", "s0")),
    ?assertEqual([{self(),"s1"}],
		 gproc:lookup_values({p,l,{gproc_env,gproc,ssss}})),
    %%
    ?assertEqual({atomic,ok}, mnesia:create_table(t_set_env,
						  [{ram_copies,[node()]}])),
    ?assertEqual(ok, mnesia:dirty_write({t_set_env, a, 1})),
    ?assertEqual(2, gproc:set_env(l, gproc, a, 2, [{mnesia,async_dirty,
						    {t_set_env,a},3}])),
    ?assertEqual([{t_set_env,a,2}], mnesia:dirty_read({t_set_env,a})),
    %% non-existing mnesia obj
    ?assertEqual(3, gproc:set_env(l, gproc, b, 3, [{mnesia,async_dirty,
						    {t_set_env,b},3}])),
    ?assertEqual([{t_set_env,b,3}], mnesia:dirty_read({t_set_env,b})).

t_get_env_inherit() ->
    P = spawn_link(fun() ->
			   ?assertEqual(bar, gproc:set_env(l,gproc,foo,bar,[])),
			   gproc:reg({n,l,get_env_p}),
			   t_loop()
		   end),
    ?assertEqual({P,undefined}, gproc:await({n,l,get_env_p},1000)),
    ?assertEqual(bar, gproc:get_env(l, gproc, foo, [{inherit, P}])),
    ?assertEqual(bar, gproc:get_env(l, gproc, foo,
				    [{inherit, {n,l,get_env_p}}])),
    ?assertEqual(ok, t_lcall(P, die)).

%% What we test here is that we return the same current_function as the
%% process_info() BIF. As we parse the backtrace dump, we check with some
%% weirdly named functions.
t_gproc_info() ->
    {A,B} = '-t1-'(),
    ?assertEqual(A,B),
    {C,D} = '\'t2'(),
    ?assertEqual(C,D),
    {E,F} = '\'t3\''(),
    ?assertEqual(E,F),
    {G,H} = t4(),
    ?assertEqual(G,H).

'-t1-'() ->
    {_, I0} = process_info(self(), current_function),
    {_, I} = gproc:info(self(), current_function),
    {I0, I}.

'\'t2'() ->
    {_, I0} = process_info(self(), current_function),
    {_, I} = gproc:info(self(), current_function),
    {I0, I}.

'\'t3\''() ->
    {_, I0} = process_info(self(), current_function),
    {_, I} = gproc:info(self(), current_function),
    {I0, I}.


t4() ->
    {_, I0} = process_info(self(), current_function),
    {_, I} = gproc:info(self(), current_function),
    {I0, I}.

t_monitor() ->
    Me = self(),
    P = spawn_link(fun() ->
			   gproc:reg({n,l,a}),
			   Me ! continue,
			   t_loop()
		   end),
    receive continue ->
	    ok
    end,
    Ref = gproc:monitor({n,l,a}),
    ?assertEqual(ok, t_lcall(P, die)),
    receive
	M ->
	    ?assertEqual({gproc,unreg,Ref,{n,l,a}}, M)
    end.

t_monitor_give_away() ->
    Me = self(),
    P = spawn_link(fun() ->
			   gproc:reg({n,l,a}),
			   Me ! continue,
			   t_loop()
		   end),
    receive continue ->
	    ok
    end,
    Ref = gproc:monitor({n,l,a}),
    ?assertEqual(ok, t_lcall(P, {give_away, {n,l,a}})),
    receive
	M ->
	    ?assertEqual({gproc,{migrated,Me},Ref,{n,l,a}}, M)
    end,
    ?assertEqual(ok, t_lcall(P, die)).

t_monitor_standby() ->
    Me = self(),
    P = spawn(fun() ->
                      gproc:reg({n,l,a}),
                      Me ! continue,
                      t_loop()
              end),
    receive continue ->
	    ok
    end,
    Ref = gproc:monitor({n,l,a}, standby),
    exit(P, kill),
    receive
	M ->
	    ?assertEqual({gproc,{failover,Me},Ref,{n,l,a}}, M)
    end,
    gproc:unreg({n,l,a}),
    ok.

t_monitor_follow() ->
    Name = ?T_NAME,
    P1 = t_spawn(_Selective = true),
    Ref = t_call(P1, {apply, gproc, monitor, [Name, follow]}),
    {gproc,unreg,Ref,Name} = got_msg(P1),
    %% gproc_lib:dbg([gproc,gproc_lib]),
    P2 = t_spawn_reg(Name),
    {gproc,registered,Ref,Name} = got_msg(P1),
    exit(P2, kill),
    {gproc,unreg,Ref,Name} = got_msg(P1),
    P3 = t_spawn(true),
    Ref3 = t_call(P3, {apply, gproc, monitor, [Name, standby]}),
    {gproc,{failover,P3},Ref,Name} = got_msg(P1),
    {gproc,{failover,P3},Ref3,Name} = got_msg(P3),
    [exit(P,kill) || P <- [P1,P3]],
    ok.

t_two_monitoring_processes_one_dies() ->
  Name = ?T_NAME,
  P = t_spawn_reg(Name),
  Ref = gproc:monitor(Name),
  {P2, R2} = spawn_monitor(fun() -> gproc:monitor(Name) end),
  receive
    {'DOWN', R2, process, P2, normal} -> ok
  end,
  exit(P, kill),
  receive
    M ->
      ?assertEqual({gproc, unreg, Ref, Name}, M)
  after 1000 ->
    error(timeout)
  end
.

t_monitor_demonitor() ->
    Name = ?T_NAME,
    P1 = t_spawn(Selective = true),
    Ref = t_call(P1, {apply, gproc, monitor, [Name, follow]}),
    {gproc, unreg, Ref, Name} = got_msg(P1),
    ok = t_call(P1, {apply, gproc, demonitor, [Name, Ref]}),
    P2 = t_spawn(Selective),
    Ref2 = t_call(P2, {apply, gproc, monitor, [Name, follow]}),
    {gproc, unreg, Ref2, Name} = got_msg(P2),
    P3 = t_spawn_reg(Name),
    {gproc, registered, Ref2, Name} = got_msg(P2),
    ok = gproc_test_lib:no_msg(P1, 300),
    [exit(P, kill) || P <- [P1, P2, P3]],
    ok.

t_subscribe() ->
    Key = {n,l,a},
    ?assertEqual(ok, gproc_monitor:subscribe(Key)),
    ?assertEqual({gproc_monitor, Key, undefined}, get_msg()),
    P = spawn_link(fun() ->
			   gproc:reg({n,l,a}),
			   t_loop()
		   end),
    ?assertEqual({gproc_monitor, Key, P}, get_msg()),
    ?assertEqual(ok, t_lcall(P, {give_away, Key})),
    ?assertEqual({gproc_monitor, Key, {migrated,self()}}, get_msg()),
    gproc:give_away(Key, P),
    ?assertEqual({gproc_monitor, Key, {migrated,P}}, get_msg()),
    ?assertEqual(ok, t_lcall(P, die)),
    ?assertEqual({gproc_monitor, Key, undefined}, get_msg()),
    ?assertEqual(ok, gproc_monitor:unsubscribe(Key)).

t_simple_pool()->
    Key = p1w1,
    From = {n,l,Key},
    _P = t_spawn_reg(From),
    
    %% create a new pool
    ?assertEqual(gproc_pool:new(p1), ok),

    %% add a worker to it
    ?assertEqual(gproc_pool:add_worker(p1,Key) , 1 ),
    ?assertEqual( length(gproc_pool:worker_pool(p1) ), 1),
    %% but it should not be active as yet
    ?assertEqual( length( gproc_pool:active_workers(p1)), 0),

    ?assert( gproc_pool:pick(p1) =:= false ),

    %% connect to make the worker active
    ?assertEqual(gproc_pool:connect_worker(p1,Key) , true ),

    %% it should be active now
    ?assertEqual( length( gproc_pool:active_workers(p1)), 1),
    ?assertEqual( gproc_pool:pick(p1) , {n,l,[gproc_pool,p1,1,Key]}),

    Ref = erlang:make_ref(),
    gproc:send(From, {self(), Ref, die}),
    receive
        {_, Ref, Returned} ->
            ?assertEqual(Returned, ok)
    after 1000 ->
            %% the next 3 tests should fail if the worker is still alive
            ok
    end,

    %% disconnect the worker from the pool.
    ?assertEqual(gproc_pool:disconnect_worker(p1,Key), true),
    %%  there should be no active workers now
    ?assertEqual( length( gproc_pool:active_workers(p1)), 0),

    %% remove the worker from the pool
    ?assertEqual(gproc_pool:remove_worker(p1,Key), true),
    %% there should be no workers now
    %% NOTE: value of worker_pool seems to vary after removing workers
    %%       sometimes [1,2] , sometimes [1], and then []
    %%       so relying on defined_workers
    ?assertEqual( length(gproc_pool:defined_workers(p1)), 0 ),
    ?assertEqual( length(gproc_pool:worker_pool(p1)), 0 ),
    ?assertEqual( false, gproc_test_lib:t_pool_contains_atleast(p1,1) ),

    %% should be able to delete the pool now
    ?assertEqual( gproc_pool:delete(p1), ok).

%% verifying #167 - Removing a worker from a pool does not make room
%% for a new worker (size was erroneously adjusted down, though auto_size = false)
t_pool_add_worker_size_1_no_auto_size() ->
    ok = gproc_pool:new(p2, direct, [{size, 1}, {auto_size, false}]),
    [] = gproc_pool:defined_workers(p2),
    Pos1 = gproc_pool:add_worker(p2, worker1),
    [{worker1, Pos1, 0}] = gproc_pool:defined_workers(p2),
    io:fwrite("G = ~p~n", [ets:tab2list(gproc)]),
    true = gproc_pool:remove_worker(p2, worker1),
    [] = gproc_pool:defined_workers(p2), %% the pool seems to be empty
    Pos2 = gproc_pool:add_worker(p2, worker2), %% throws error:pool_full
    true = is_integer(Pos2),
    true = gproc_pool:force_delete(p2).

t_pool_add_worker_size_2_no_auto_size() ->
    gproc_pool:new(p3, direct, [{size, 2}, {auto_size, false}]),
    gproc_pool:add_worker(p3, worker1),
    gproc_pool:add_worker(p3, worker2),
    gproc_pool:remove_worker(p3, worker2),
    gproc_pool:add_worker(p3, worker3),
    gproc_pool:force_delete(p3).

t_pool_round_robin_disconnect_worker() ->
    gproc_pool:new(p),
    gproc_pool:add_worker(p, w1),
    gproc_pool:add_worker(p, w2),
    gproc_pool:add_worker(p, w3),
    Work = fun(W) -> spawn(fun() -> gproc_pool:connect_worker(p, W), fun F() -> F() end() end) end,

    %% disc first
    W1 = Work(w1),
    W2 = Work(w2),
    W3 = Work(w3),
    timer:sleep(10),
    ?assertEqual([W1, W2, W3], [ P || {_, P} <- gproc_pool:active_workers(p)]),
    ?assertEqual([W1, W2, W3, W1, W2, W3, W1, W2, W3], [gproc_pool:pick_worker(p) || _ <- lists:seq(1, 9)]),
    exit(W1, die),
    timer:sleep(10),
    ?assertEqual([W2, W3], [ P || {_, P} <- gproc_pool:active_workers(p)]),
    ?assertEqual([W2, W3, W2, W3, W2, W3, W2, W3, W2], [gproc_pool:pick_worker(p) || _ <- lists:seq(1, 9)]),

    %% disc middle
    W11 = Work(w1),
    timer:sleep(10),
    ?assertEqual([W11, W2, W3], [ P || {_, P} <- gproc_pool:active_workers(p)]),
    ?assertEqual([W3, W11, W2, W3, W11, W2, W3, W11, W2], [gproc_pool:pick_worker(p) || _ <- lists:seq(1, 9)]),
    exit(W2, die),
    timer:sleep(10),
    ?assertEqual([W11, W3], [ P || {_, P} <- gproc_pool:active_workers(p)]),
    ?assertEqual([W3, W11, W3, W11, W3, W11, W3, W11, W3], [gproc_pool:pick_worker(p) || _ <- lists:seq(1, 9)]),

    %% disc last
    W22 = Work(w2),
    timer:sleep(10),
    ?assertEqual([W11, W22, W3], [ P || {_, P} <- gproc_pool:active_workers(p)]),
    ?assertEqual([W11, W22, W3, W11, W22, W3, W11, W22, W3], [gproc_pool:pick_worker(p) || _ <- lists:seq(1, 9)]),
    exit(W3, die),
    timer:sleep(10),
    ?assertEqual([W11, W22], [ P || {_, P} <- gproc_pool:active_workers(p)]),
    ?assertEqual([W11, W22, W11, W22, W11, W22, W11, W22, W11], [gproc_pool:pick_worker(p) || _ <- lists:seq(1, 9)]),

    %% restore
    W33 = Work(w3),
    timer:sleep(10),
    ?assertEqual([W11, W22, W33], [ P || {_, P} <- gproc_pool:active_workers(p)]),
    ?assertEqual([W22, W33, W11, W22, W33, W11, W22, W33, W11], [gproc_pool:pick_worker(p) || _ <- lists:seq(1, 9)]),

    gproc_pool:force_delete(p).

t_pubsub() ->
    true = gproc_ps:subscribe(l, my_event),
    {gproc_ps_event, my_event, foo1} = Msg = gproc_ps:publish(l, my_event, foo1),
    Msg = get_msg(),
    true = gproc_ps:unsubscribe(l, my_event),
    gproc_ps:publish(l, my_event, foo2),
    timeout = get_msg(100),
    ok.

t_singles() ->
    Me = self(),
    true = gproc_ps:create_single(l, my_single),
    [Me] = gproc_ps:tell_singles(l, my_single, foo1),
    {gproc_ps_event, my_single, foo1} = get_msg(),
    [] = gproc_ps:tell_singles(l, my_single, foo2),
    timeout = get_msg(100),
    0 = gproc_ps:enable_single(l, my_single),
    [Me] = gproc_ps:tell_singles(l, my_single, foo3),
    {gproc_ps_event, my_single, foo3} = get_msg(),
    0 = gproc_ps:enable_single(l, my_single),
    1 = gproc_ps:disable_single(l, my_single),
    0 = gproc_ps:enable_single(l, my_single),
    1 = gproc_ps:enable_single(l, my_single),
    true = gproc_ps:delete_single(l, my_single),
    ok.

t_ps_cond() ->
    Pat1 = [{'$1',[{'==',1,{'rem','$1',2}}], [true]}],  % odd numbers
    Pat2 = [{'$1',[{'==',0,{'rem','$1',2}}], [true]}],  % even numbers
    P1 = t_spawn(_Selective = true),
    P2 = t_spawn(true),
    true = t_call(P1, {apply, gproc_ps, subscribe_cond, [l, my_cond, Pat1]}),
    true = t_call(P2, {apply, gproc_ps, subscribe_cond, [l, my_cond, Pat2]}),
    Msg = gproc_ps:publish_cond(l, my_cond, 1),
    Msg = got_msg(P1),
    ok = no_msg(P2),
    Msg2 = gproc_ps:publish_cond(l, my_cond, 2),
    Msg2 = got_msg(P2),
    ok = no_msg(P1),
    true = t_call(P1, {apply, gproc_ps, unsubscribe, [l, my_cond]}),
    true = t_call(P2, {apply, gproc_ps, unsubscribe, [l, my_cond]}),
    [exit(P, kill) || P <- [P1, P2]],
    ok.

get_msg() ->
    get_msg(1000).

get_msg(Timeout) ->
    receive M ->
	    M
    after Timeout ->
	    timeout
    end.

%% t_spawn()      -> gproc_test_lib:t_spawn(node()).
t_spawn(Sel)   -> gproc_test_lib:t_spawn(node(), Sel).
t_spawn_reg(N) -> gproc_test_lib:t_spawn_reg(node(), N).
t_call(P, Req) -> gproc_test_lib:t_call(P, Req).
%% got_msg(P, M)  -> gproc_test_lib:got_msg(P, M).
got_msg(P)     -> gproc_test_lib:got_msg(P).
no_msg(P)      -> gproc_test_lib:no_msg(P, 100).

t_loop() ->
    receive
	{From, {give_away, Key}} ->
	    ?assertEqual(From, gproc:give_away(Key, From)),
	    From ! {self(), ok},
	    t_loop();
	{From, die} ->
	    From ! {self(), ok};
	{From, {reg, Name}} ->
	    From ! {self(), gproc:reg(Name,undefined)},
   	    t_loop();
 	{From, {unreg, Name}} ->
   	    From ! {self(), gproc:unreg(Name)},
   	    t_loop()
    end.

t_lcall(P, Msg) ->
    P ! {self(), Msg},
    receive
	{P, Reply} ->
	    Reply
    end.

spawn_helper() ->
    Parent = self(),
    P = spawn(fun() ->
		      ?assert(gproc:reg({n,l,self()}) =:= true),
		      Ref = erlang:monitor(process, Parent),
		      Parent ! {ok,self()},
		      receive
			  {'DOWN', Ref, _, _, _} ->
			      ok
		      end
	      end),
    receive
	{ok,P} ->
	     P
    end.

give_gproc_some_time(T) ->
    timer:sleep(T),
    sys:get_status(gproc).

-endif.
