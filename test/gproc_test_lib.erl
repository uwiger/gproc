-module(gproc_test_lib).

-export([t_spawn/1, t_spawn/2,
         t_spawn_reg/2, t_spawn_reg/3, t_spawn_reg/4,
         t_spawn_reg_shared/3,
         t_spawn_mreg/2,
         t_call/2,
         t_loop/0, t_loop/1,
	 t_pool_contains_atleast/2,
         got_msg/1, got_msg/2]).

-include_lib("eunit/include/eunit.hrl").

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
	{P, ok} -> P
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
	{P, ok} -> P
    after 1000 ->
            erlang:error({timeout, t_spawn_reg, [Node, Name, Value]})
    end.

t_spawn_mreg(Node, KVL) ->
    Me = self(),
    P = spawn(Node, fun() ->
                            ?assertMatch(true, gproc:mreg(n, g, KVL)),
                            Me ! {self(), ok},
                            t_loop()
                    end),
    receive
	{P, ok} -> P
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

t_pool_contains_atleast(Pool,N)->
    Existing = lists:foldl(fun({_X,_Y},Acc)->
                                   Acc+1;
                              (_,Acc) ->
                                   Acc
                           end, 0, gproc_pool:worker_pool(Pool) ),
    Existing >= N.
