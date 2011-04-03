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
-module(gproc_dist_tests).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-export([t_spawn/1, t_spawn_reg/2]).

dist_test_() ->
    {timeout, 90,
     [{setup,
       fun() ->
	       Ns = start_slaves([n1, n2]),
	       ?assertMatch({[ok,ok],[]},
			    rpc:multicall(Ns, application, start, [gproc])),
	       %% Without this trace output, the test times out on my Mac...
	       dbg:tracer(),
	       dbg:tpl(?MODULE, x),
	       dbg:p(all,[c]),
	       ?debugVal(Ns)
       end,
       fun(Ns) ->
	       [rpc:call(N, init, stop, []) || N <- Ns]
       end,
       fun(Ns) ->
	       {inorder,
		[
		 {inparallel, [fun() ->
				       ?debugVal(t_simple_reg(Ns))
			       end,
			       fun() ->
			       	       ?debugVal(t_await_reg(Ns))
			       end,
			       fun() ->
			       	       ?debugVal(t_await_reg_exists(Ns))
			       end,
			       fun() ->
				       ?debugVal(t_give_away(Ns))
			       end
			      ]
		 },
		 {timeout, 60, [fun() ->
					?debugVal(t_fail_node(Ns))
				end]}
		]}
       end
      }]}.

-define(T_NAME, {n, g, {?MODULE, ?LINE}}).

t_simple_reg([H|_] = Ns) ->
    ?debugMsg(t_simple_reg),
    Name = ?T_NAME,
    P = t_spawn_reg(H, Name),
    ?assertMatch(ok, t_lookup_everywhere(Name, Ns, P)),
    ?assertMatch(true, t_call(P, {apply, gproc, unreg, [Name]})),
    ?assertMatch(ok, t_lookup_everywhere(Name, Ns, undefined)),
    ?assertMatch(ok, t_call(P, die)).

t_await_reg([A,B|_]) ->
    ?debugMsg(t_await_reg),
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
    ?assertMatch(ok, t_call(P1, die)).

t_await_reg_exists([A,B|_]) ->
    ?debugMsg(t_await_reg_exists),
    Name = ?T_NAME,
    P = t_spawn(A),
    Ref = erlang:monitor(process, P),
     %% dbg:tracer(),
     %% [dbg:n(N) || N <- Ns],
     %% dbg:tpl(gproc_dist,x),
     %% dbg:tpl(gproc_lib,await,x),
     %% dbg:p(all,[c]),
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
    ?debugMsg(t_give_away),
    Na = ?T_NAME,
    Nb = ?T_NAME,
    Pa = t_spawn_reg(A, Na),
    Pb = t_spawn_reg(B, Nb),
    ?assertMatch(ok, t_lookup_everywhere(Na, Ns, Pa)),
    ?assertMatch(ok, t_lookup_everywhere(Nb, Ns, Pb)),
    ?assertMatch(Pb, t_call(Pa, {apply, {gproc, give_away, [Na, Nb]}})),
    ?assertMatch(ok, t_lookup_everywhere(Na, Ns, Pb)),
    ?assertMatch(Pa, t_call(Pa, {apply, {gproc, give_away, [Na, Pa]}})),
    ?assertMatch(ok, t_lookup_everywhere(Na, Ns, Pa)),
    ?assertMatch(ok, t_call(Pa, die)),
    ?assertMatch(ok, t_call(Pb, die)).

t_fail_node([A,B|_] = Ns) ->
    ?debugMsg(t_fail_node),
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
	    ?debugFmt("lookup ~p failed (~p), retrying...~n", [Key, Found]),
	    t_sleep(),
	    t_lookup_everywhere(Key, Nodes, Exp, I-1);
       true ->
	    ok
    end.
				  

t_spawn(Node) ->
    Me = self(),
    P = spawn(Node, fun() ->
			    Me ! {self(), ok},
			    t_loop()
		    end),
    receive
	{P, ok} -> P
    end.

t_spawn_reg(Node, Name) ->
    Me = self(),
    spawn(Node, fun() ->
			?assertMatch(true, gproc:reg(Name)),
			Me ! {self(), ok},
			t_loop()
		end),
    receive
	{P, ok} -> P
    end.

t_call(P, Req) ->
    Ref = erlang:monitor(process, P),
    P ! {self(), Ref, Req},
    receive
	{P, Ref, Res} ->
	    erlang:demonitor(Ref),
	    Res;
	{'DOWN', Ref, _, _, Error} ->
	    erlang:error({'DOWN', P, Error})
    end.

t_loop() ->
    receive
	{From, Ref, die} ->
	    From ! {self(), Ref, ok};
	{From, Ref, {apply, M, F, A}} ->
	    From ! {self(), Ref, apply(M, F, A)},
	    t_loop()
    end.

start_slaves(Ns) ->
    [H|T] = Nodes = [start_slave(N) || N <- Ns],
    _ = [{N, rpc:call(H, net, ping, [N])} || N <- T],
    Nodes.
	       
start_slave(Name) ->
    case node() of
        nonode@nohost ->
            os:cmd("epmd -daemon"),
            {ok, _} = net_kernel:start([gproc_master, longnames]);
        _ ->
            ok
    end,
    {ok, Node} = slave:start(
		   host(), Name,
		   "-pa . -pz ../ebin -pa ../deps/gen_leader/ebin "
		   "-gproc gproc_dist all"),
    %% io:fwrite(user, "Slave node: ~p~n", [Node]),
    Node.

host() ->
    [_Name, Host] = re:split(atom_to_list(node()), "@", [{return, list}]),
    list_to_atom(Host).

-endif.
