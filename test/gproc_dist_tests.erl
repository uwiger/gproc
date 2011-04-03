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
    {timeout, 60,
     [{foreach,
       fun() ->
	       Ns = start_slaves([n1, n2]),
	       %% dbg:tracer(),
	       %% [dbg:n(N) || N <- Ns],
	       %% dbg:tpl(gproc_dist, x),
	       %% dbg:p(all,[c]),
	       Ns
       end,
       fun(Ns) ->
	       [rpc:call(N, init, stop, []) || N <- Ns]
       end,
       [
	{with, [fun(_) -> {in_parallel, [fun(X) ->
						 ?debugVal(t_simple_reg(X)) end,
					 fun(X) ->
						 ?debugVal(t_await_reg(X))
					 end,
					 fun(X) ->
						 ?debugVal(t_give_away(X))
					 end]
			  }
		end]}
       ]}
     ]}.

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
    P ! {self(), {apply, gproc, await, [Name]}},
    P1 = t_spawn_reg(B, Name),
    ?assert(P1 == receive
		      {P, Res} ->
			  element(1, Res)
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
    %% ?debugHere,
    ?assertMatch(Pb, t_call(Pa, {apply, {gproc, give_away, [Na, Nb]}})),
    ?assertMatch(ok, t_lookup_everywhere(Na, Ns, Pb)),
    %% ?debugHere,
    ?assertMatch(Pa, t_call(Pa, {apply, {gproc, give_away, [Na, Pa]}})),
    ?assertMatch(ok, t_lookup_everywhere(Na, Ns, Pa)),
    %% ?debugHere,
    ?assertMatch(ok, t_call(Pa, die)),
    ?assertMatch(ok, t_call(Pb, die)).
    
t_sleep() ->
    timer:sleep(1000).

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
    P ! {self(), Req},
    receive
	{P, Res} ->
	    Res
    end.

t_loop() ->
    receive
	{From, die} ->
	    From ! {self(), ok};
	{From, {apply, M, F, A}} ->
	    From ! {self(), apply(M, F, A)},
	    t_loop()
    end.

start_slaves(Ns) ->
    [start_slave(N) || N <- Ns].
	       
start_slave(Name) ->
    case node() of
        nonode@nohost ->
            os:cmd("epmd -daemon"),
            {ok, _} = net_kernel:start([gproc_master, shortnames]);
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
