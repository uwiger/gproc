%%% File    : gproc_eqc.erl
%%% Author  : <Ulf.Wiger@erlang-consulting.com>  
%%%         : <John.Hughes@quviq.com>
%%% Description : 
%%% Created : 11 Dec 2008 by  <John Hughes@JTABLET2007>
-module(gproc_eqc).


-include_lib("eqc/include/eqc.hrl").
-include_lib("eqc/include/eqc_statem.hrl").

-compile(export_all).

-record(state,{pids=[],regs=[],killed=[]}).


run() ->
%%     eqc:quickcheck(prop_gproc()).
    run(200).


run(Num) ->
    eqc:quickcheck(eqc:numtests(Num, prop_gproc())).

%% Initialize the state
initial_state() ->
    #state{}.

%% Command generator, S is the state
command(S) ->
    oneof(
      [{call,?MODULE,spawn,[]}]++
      [{call,?MODULE,kill,[elements(S#state.pids)]} || S#state.pids/=[]] ++
      [{call,?MODULE,reg,[name(),elements(S#state.pids)]}
       || S#state.pids/=[]] ++
      [{call,?MODULE,unreg,[elements(S#state.regs)]} || S#state.regs/=[]] ++
      [{call,gproc,where,[{n,l,name()}]}]			       
     ).

name() ->
    elements([a,b,c,d]).

%% Next state transformation, S is the current state
next_state(S,V,{call,_,spawn,_}) ->
    S#state{pids=[V|S#state.pids]};
next_state(S,V,{call,_,kill,[Pid]}) ->
    S#state{killed=[Pid|S#state.killed],
	    pids=S#state.pids -- [Pid],
	    regs = [{Name,Pid2} || {Name,Pid2} <- S#state.regs,
				   Pid/=Pid2]};
next_state(S,_V,{call,_,reg,[Name,Pid]}) ->
    case register_ok(S,Name,Pid) of
	false ->
	    S;
	true ->
	    S#state{regs=[{Name,Pid}|S#state.regs]}
    end;
next_state(S,_V,{call,_,unreg,[{Name,_}]}) ->
    S#state{regs=lists:keydelete(Name,1,S#state.regs)};
next_state(S,_V,{call,_,_,_}) ->
    S.

%% Precondition, checked before command is added to the command sequence
%% precondition(S,{call,_,unreg,[Name]}) ->
%%
%% precondition(S,{call,_,reg,[Name,Pid]}) ->
%%     
precondition(_S,{call,_,_,_}) ->
    true.

unregister_ok(S,Name) ->
    lists:keymember(Name,1,S#state.regs).

register_ok(S,Name,Pid) ->
    not lists:keymember(Name,1,S#state.regs).

%% Postcondition, checked after command has been evaluated
%% OBS: S is the state before next_state(S,_,<command>) 
postcondition(S,{call,_,where,[{_,_,Name}]},Res) ->
    Res == proplists:get_value(Name,S#state.regs);
postcondition(S,{call,_,unreg,[{Name,_}]},Res) ->
    case Res of
	true ->
	    unregister_ok(S,Name);
	{'EXIT',_} ->
	    not unregister_ok(S,Name)
    end;
postcondition(S,{call,_,reg,[Name,Pid]},Res) ->
    case Res of
	true ->
	    register_ok(S,Name,Pid);
	{'EXIT',_} ->
	    not register_ok(S,Name,Pid)
    end;
postcondition(_S,{call,_,_,_},_Res) ->
    true.

prop_gproc() ->
    ?FORALL(Cmds,commands(?MODULE),
	    ?TRAPEXIT(
	    begin
		ok = start_app(),
		{H,S,Res} = run_commands(?MODULE,Cmds),
		kill_all_pids({H,S}),
		ok = stop_app(),
		?WHENFAIL(
		   io:format("History: ~p\nState: ~p\nRes: ~p\n",[H,S,Res]),
		   Res == ok)
	    end)).


seed() ->
    noshrink({largeint(),largeint(),largeint()}).

cleanup(Tabs,Server) ->
    unlink(Server),
    unlink(Tabs),
    exit(Server,kill),
    exit(Tabs,kill),
    catch unregister(proc_reg),
    catch unregister(proc_reg_tabs),
    delete_tables(),
    ok.%    timer:sleep(1).

start_app() ->
    case application:start(gproc) of
	{error, {already_started,_}} ->
	    stop_app(),
	    ok = application:start(gproc);
	ok ->
	    ok
    end.

stop_app() ->
    ok = application:stop(gproc).


delete_tables() ->
    catch ets:delete(proc_reg).

spawn() ->
    spawn(fun() ->
		  loop()
	  end).

loop() ->
    receive
	{From, Ref, F} ->
	    From ! {Ref, catch F()},
	    loop();
	stop -> ok
    end.

do(Pid, F) ->
    Ref = erlang:monitor(process, Pid),
    Pid ! {self(), Ref, F},
    receive
	{'DOWN', Ref, process, Pid, Reason} ->
	    {'EXIT', {'DOWN',Reason}};
	{Ref, Result} ->
	    erlang:demonitor(Ref),
	    Result
    after 3000 ->
	    {'EXIT', timeout}
    end.

kill(Pid) ->
    exit(Pid,foo),
    timer:sleep(10).

unreg({Name,Pid}) ->
    do(Pid,
       fun() ->
	       catch gproc:unreg({n,l,Name})
       end).

reg(Name,Pid) ->
    do(Pid,
       fun() ->
	       catch gproc:reg({n,l,Name},Pid)
       end).


%% If using the scheduler...
%% This code needs to run in a separate module, so it can be compiled
%% without instrumentation.

kill_all_pids(Pid) when is_pid(Pid) ->
    case is_process_alive(Pid) of
	true ->
	    exit(Pid,kill);
	false ->
	    ok
    end;
kill_all_pids(Tup) when is_tuple(Tup) ->
    kill_all_pids(tuple_to_list(Tup));
kill_all_pids([H|T]) ->
    kill_all_pids(H),
    kill_all_pids(T);
kill_all_pids(_) ->
    ok.

