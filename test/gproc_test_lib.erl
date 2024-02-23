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
-module(gproc_test_lib).

-export([t_spawn/1, t_spawn/2,
         t_spawn_reg/2, t_spawn_reg/3, t_spawn_reg/4,
         t_spawn_reg_shared/3,
         t_spawn_mreg/2,
         t_spawn_mreg/3,
         t_call/2,
         t_loop/0, t_loop/1,
	 t_pool_contains_atleast/2,
         got_msg/1, got_msg/2,
         no_msg/2]).

-export([ensure_dist/0,
         start_nodes/1,
         start_node/1,
         stop_nodes/1,
         stop_node/1,
         node_name/1]).

-include_lib("eunit/include/eunit.hrl").


start_nodes(Ns) ->
    [H|T] = Nodes = [start_node(N) || N <- Ns],
    _ = [rpc:call(H, net_adm, ping, [N]) || N <- T],
    Nodes.

start_node(Name0) ->
    {Name, _} = eunit_lib:split_node(Name0),
    ensure_dist(),
    {Pa, Pz} = paths(),
    Paths = "-pa ./ -pz ../ebin" ++
        lists:flatten([[" -pa " ++ Path || Path <- Pa],
		       [" -pz " ++ Path || Path <- Pz]]),
    Args = "-kernel prevent_overlapping_partitions false " ++ Paths,
    {ok, Node} = slave:start(host(), Name, Args),
    Node.

stop_nodes(Ns) ->
    [stop_node(N) || N <- Ns],
    ok.

stop_node(N) ->
    slave:stop(N).

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
    list_to_atom(host_string()).

host_string() ->
    [_Name, Host] = re:split(atom_to_list(node()), "@", [{return, list}]),
    Host.

node_name(NamePart) ->
    ensure_dist(),
    list_to_atom(atom_to_list(NamePart) ++ "@" ++ host_string()).

ensure_dist() ->
    case node() of
        nonode@nohost ->
            os:cmd("epmd -daemon"),
            {ok, _} = net_kernel:start([gproc_master, shortnames]),
            true;
        _ ->
            false
    end.

t_spawn(Node) ->
    t_spawn(Node, false).

t_spawn(Node, Selective) when is_boolean(Selective) ->
    Me = self(),
    P = spawn(Node, fun() ->
			    Me ! {self(), ok},
			    t_loop(Selective)
		    end),
    receive
	{P, ok} -> P
    after 1000 ->
            erlang:error({timeout, t_spawn, [Node, Selective]})
    end.

t_spawn_reg(Node, Name) ->
    t_spawn_reg(Node, Name, default_value(Name)).

t_spawn_reg(Node, Name, Value) ->
    Me = self(),
    P = spawn(Node, fun() ->
                            ?assertMatch(true, gproc:reg(Name, Value)),
                            Me ! {self(), ok},
                            t_loop()
                    end),
    receive
	{P, ok} ->
            P
    after 1000 ->
            erlang:error({timeout, t_spawn_reg, [Node, Name, Value]})
    end.

t_spawn_reg(Node, Name, Value, Attrs) ->
    Me = self(),
    P = spawn(Node, fun() ->
                            ?assertMatch(true, gproc:reg(Name, Value, Attrs)),
                            Me ! {self(), ok},
                            t_loop()
                    end),
    receive
	{P, ok} ->
            P
    after 1000 ->
            erlang:error({timeout, t_spawn_reg, [Node, Name, Value]})
    end.

t_spawn_mreg(Node, KVL) ->
    t_spawn_mreg(Node, n, KVL).

t_spawn_mreg(Node, T, KVL) ->
    Me = self(),
    P = spawn(Node, fun() ->
                            ?assertMatch(true, gproc:mreg(T, g, KVL)),
                            Me ! {self(), ok},
                            t_loop()
                    end),
    receive
	{P, ok} ->
            P
    after 1000 ->
            error({timeout, t_spawn_mreg, [Node, T, KVL]})
    end.


t_spawn_reg_shared(Node, Name, Value) ->
    Me = self(),
    P = spawn(Node, fun() ->
                            ?assertMatch(true, gproc:reg_shared(Name, Value)),
                            Me ! {self(), ok},
                            t_loop()
                    end),
    receive
	{P, ok} -> P
    after 1000 ->
              erlang:error({timeout, t_spawn_reg_shared, [Node,Name,Value]})
    end.

default_value({c,_,_}) -> 0;
default_value(_) -> undefined.

t_call(P, Req) ->
    Ref = erlang:monitor(process, P),
    P ! {self(), Ref, Req},
    receive
	{P, Ref, Res} ->
	    erlang:demonitor(Ref, [flush]),
	    Res;
	{'DOWN', Ref, _, _, Error} ->
	    erlang:error({'DOWN', P, Error})
    after 1000 ->
            erlang:error({timeout,t_call,[P,Req]})
    end.

t_loop() ->
    t_loop(false).

t_loop(Selective) when is_boolean(Selective) ->
    receive
	{From, Ref, die} ->
	    From ! {self(), Ref, ok};
	{From, Ref, {selective, Bool}} when is_boolean(Bool) ->
	    From ! {self(), Ref, ok},
	    t_loop(Bool);
	{From, Ref, {apply, M, F, A}} ->
	    From ! {self(), Ref, apply(M, F, A)},
	    t_loop(Selective);
	{From, Ref, {apply_fun, F}} ->
	    From ! {self(), Ref, F()},
	    t_loop(Selective);
	Other when not Selective ->
	    ?debugFmt("got unknown msg: ~p~n", [Other]),
	    exit({unknown_msg, Other})
    end.

got_msg(Pb) ->
    t_call(Pb,
           {apply_fun,
            fun() ->
                    receive M -> M
                    after 1000 ->
                            erlang:error({timeout, got_msg, [Pb]})
                    end
            end}).

got_msg(Pb, Tag) ->
    t_call(Pb,
	   {apply_fun,
	    fun() ->
		    receive
			M when element(1, M) == Tag ->
			    M
		    after 1000 ->
			    erlang:error({timeout, got_msg, [Pb, Tag]})
		    end
	    end}).

no_msg(Pb, Timeout) ->
    t_call(Pb,
           {apply_fun,
            fun() ->
                    receive
                        M ->
                            erlang:error({unexpected_msg, M})
                    after Timeout ->
                            ok
                    end
            end}).

t_pool_contains_atleast(Pool,N)->
    Existing = lists:foldl(fun({_X,_Y},Acc)->
                                   Acc+1;
                              (_,Acc) ->
                                   Acc
                           end, 0, gproc_pool:worker_pool(Pool) ),
    Existing >= N.
