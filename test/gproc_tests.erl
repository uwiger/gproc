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
%% @author Ulf Wiger <ulf.wiger@erlang-solutions.com>
%%
-module(gproc_tests).

-ifdef(TEST).

-include_lib("eunit/include/eunit.hrl").
-include_lib("stdlib/include/qlc.hrl").

conf_test_() ->
    {foreach,
     fun() ->
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
    ?assert(ok == application:start(gproc)),
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
      , {spawn, ?_test(?debugVal(t_simple_counter()))}
      , ?_test(t_is_clean())
      , {spawn, ?_test(?debugVal(t_simple_aggr_counter()))}
      , ?_test(t_is_clean())
      , {spawn, ?_test(?debugVal(t_update_counters()))}
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
      , {spawn, ?_test(?debugVal(t_subscribe()))}
      , ?_test(t_is_clean())
      , {spawn, ?_test(?debugVal(t_gproc_info()))}
      , ?_test(t_is_clean())
     ]}.

t_simple_reg() ->
    ?assert(gproc:reg({n,l,name}) =:= true),
    ?assert(gproc:where({n,l,name}) =:= self()),
    ?assert(gproc:unreg({n,l,name}) =:= true),
    ?assert(gproc:where({n,l,name}) =:= undefined).

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
    {_Pid,Ref} = spawn_monitor(
                   fun() ->
			   exit(?assert(
				   gproc:await({n,l,t_await}) =:= {Me,val}))
		   end),
    ?assert(gproc:reg({n,l,t_await},val) =:= true),
    receive
        {'DOWN', Ref, _, _, R} ->
            ?assertEqual(R, ok)
    after 10000 ->
            erlang:error(timeout)
    end.

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
    ?assertMatch([], T -- [{{whereis(gproc_monitor), l}}]).

t_simple_mreg() ->
    P = self(),
    ?assertEqual(true, gproc:mreg(n, l, [{foo, foo_val},
					 {bar, bar_val}])),
    ?assertEqual(P, gproc:where({n,l,foo})),
    ?assertEqual(P, gproc:where({n,l,bar})),
    ?assertEqual(true, gproc:munreg(n, l, [foo, bar])).


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
    ?assertEqual(ok, t_call(P, die)).

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
    ?assertEqual(ok, t_call(P, {give_away, From})),
    ?assertEqual(Me, gproc:where(From)),
    ?assertEqual(ok, t_call(P, die)).

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
    ?assertEqual(ok, t_call(P, die)).

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
    ?assertEqual(ok, t_call(P, die)),
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
    ?assertEqual(ok, t_call(P, {give_away, {n,l,a}})),
    receive
	M ->
	    ?assertEqual({gproc,{migrated,Me},Ref,{n,l,a}}, M)
    end,
    ?assertEqual(ok, t_call(P, die)).

t_subscribe() ->
    Key = {n,l,a},
    ?assertEqual(ok, gproc_monitor:subscribe(Key)),
    ?assertEqual({gproc_monitor, Key, undefined}, get_msg()),
    P = spawn_link(fun() ->
			   gproc:reg({n,l,a}),
			   t_loop()
		   end),
    ?assertEqual({gproc_monitor, Key, P}, get_msg()),
    ?assertEqual(ok, t_call(P, {give_away, Key})),
    ?assertEqual({gproc_monitor, Key, {migrated,self()}}, get_msg()),
    gproc:give_away(Key, P),
    ?assertEqual({gproc_monitor, Key, {migrated,P}}, get_msg()),
    ?assertEqual(ok, t_call(P, die)),
    ?assertEqual({gproc_monitor, Key, undefined}, get_msg()),
    ?assertEqual(ok, gproc_monitor:unsubscribe(Key)).

get_msg() ->
    receive M ->
	    M
    after 1000 ->
	    timeout
    end.

t_loop() ->
    receive
	{From, {give_away, Key}} ->
	    ?assertEqual(From, gproc:give_away(Key, From)),
	    From ! {self(), ok},
	    t_loop();
	{From, die} ->
	    From ! {self(), ok}
    end.

t_call(P, Msg) ->
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
