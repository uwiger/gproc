%%% File        : gproc_eqc.erl
%%% Author      : <norton@alum.mit.edu>
%%%             : <Ulf.Wiger@erlang-consulting.com>
%%%             : <John.Hughes@quviq.com>
%%% Description : QuickCheck test model for gproc
%%% Created     : 11 Dec 2008 by  <John Hughes@JTABLET2007>

-module(gproc_eqc).


-include("eqc.hrl").
-include("eqc_statem.hrl").

-compile(export_all).


%% records
-record(n_reg,
        {key           %% atom() ... only in this model
         , pid          %% pid()
        }).

-record(c_reg,
        {key           %% atom() ... only in this model
         , pid          %% pid()
         , value=0      %% int()
        }).

-record(a_reg,
        {key           %% atom() ... only in this model
         , pid          %% pid()
         , value=0      %% int()
        }).

-record(state,
        {pids=[]        %% [pid()]
         , killed=[]    %% [pid()]
         , n_regs=[]    %% [n_reg()]
         , c_regs=[]    %% [c_reg()]
         , a_regs=[]    %% [a_reg()]
        }).


%% external API
start_test() ->
    eqc:module({numtests, 500}, ?MODULE).

run() ->
    run(500).

run(Num) ->
    eqc:quickcheck(eqc:numtests(Num, prop_gproc())).


%% Command generator, S is the state

%% NOTE: These are the only use cases that make sense to me so far.
%% Other APIs seem possible but I'm not sure why/how/when they can be
%% useful.

command(S) ->
    oneof(
      %% spawn
      [ {call,?MODULE,spawn,[]} ]
      %% kill
      ++ [ {call,?MODULE,kill,[elements(S#state.pids)]}
           || S#state.pids/=[] ]

      %% name - register
      ++ [ {call,?MODULE,n_reg,[name(),elements(S#state.pids)]}
           || S#state.pids/=[] ]
      %% name - unregister
      ++ [ {call,?MODULE,n_unreg,[elements(S#state.n_regs)]}
           || S#state.n_regs/=[] ]
      %% counter - register
      ++ [ {call,?MODULE,c_reg,[counter(),elements(S#state.pids),int()]}
           || S#state.pids/=[] ]
      %% counter - unregister
      ++ [ {call,?MODULE,c_unreg,[elements(S#state.c_regs)]}
           || S#state.c_regs/=[] ]
      %% aggr counter - register
      ++ [ {call,?MODULE,a_reg,[aggr_counter(),elements(S#state.pids)]}
           || S#state.pids/=[] ]
      %% aggr counter - unregister
      ++ [ {call,?MODULE,a_unreg,[elements(S#state.a_regs)]}
           || S#state.a_regs/=[] ]

      %% counter - set_value
      ++ [ {call,?MODULE,set_value,[elements(S#state.c_regs),int()]}
           || S#state.c_regs/=[] ]

      %% aggr counter - get_value
      ++ [{call,?MODULE,get_value,[elements(S#state.c_regs)]}
          || S#state.c_regs/=[] ]
      ++ [{call,?MODULE,get_value,[elements(S#state.a_regs)]}
          || S#state.a_regs/=[] ]

      %% name - where
      ++ [{call,gproc,where,[{n,l,name()}]}]
      %% aggr counter - where
      ++ [{call,gproc,where,[{a,l,aggr_counter()}]}]
      %% counter - lookup_pids
      ++ [ {call,gproc,lookup_pids,[{c,l,counter()}]}
           || S#state.c_regs/=[] ]

     ).

%% name generator
name() ->
    elements([n1,n2,n3,n4]).

%% counter generator
counter() ->
    elements([c1,c2,c3,c4]).

%% aggr counter generator
aggr_counter() ->
    elements([a1,a2,a3,a4]).


%% Initialize the state
initial_state() ->
    #state{}.


%% Next state transformation, S is the current state

%% spawn
next_state(S,V,{call,_,spawn,_}) ->
    S#state{pids=[V|S#state.pids]};
%% kill
next_state(S,_V,{call,_,kill,[Pid]}) ->
    S#state{killed=[Pid|S#state.killed]
            , pids=S#state.pids -- [Pid]
            , n_regs=[ X || #n_reg{pid=Pid1}=X <- S#state.n_regs, Pid/=Pid1 ]
            , c_regs=[ X || #c_reg{pid=Pid1}=X <- S#state.c_regs, Pid/=Pid1 ]
            , a_regs=[ X || #a_reg{pid=Pid1}=X <- S#state.a_regs, Pid/=Pid1 ]
           };
%% n_reg
next_state(S,_V,{call,_,n_reg,[Name,Pid]}) ->
    case is_n_register_ok(S,Name,Pid) of
        false ->
            S;
        true ->
            S#state{n_regs=[#n_reg{key=Name,pid=Pid}|S#state.n_regs]}
    end;
%% n_unreg
next_state(S,_V,{call,_,n_unreg,[#n_reg{key=Name}]}) ->
    S#state{n_regs=[ X || #n_reg{key=Name1}=X <- S#state.n_regs
                              , Name/=Name1 ]};
%% c_reg
next_state(S,_V,{call,_,c_reg,[Counter,Pid,Value]}) ->
    case is_c_register_ok(S,Counter,Pid) of
        false ->
            S;
        true ->
            S#state{c_regs=[#c_reg{key=Counter,pid=Pid,value=Value}|S#state.c_regs]}
    end;
%% c_unreg
next_state(S,_V,{call,_,c_unreg,[#c_reg{key=Counter,pid=Pid}]}) ->
    S#state{c_regs=[ X || #c_reg{key=Counter1,pid=Pid1}=X <- S#state.c_regs
                              , Counter/=Counter1 andalso Pid/=Pid1 ]};
%% a_reg
next_state(S,_V,{call,_,a_reg,[AggrCounter,Pid]}) ->
    case is_a_register_ok(S,AggrCounter,Pid) of
        false ->
            S;
        true ->
            S#state{a_regs=[#a_reg{key=AggrCounter,pid=Pid,value=0}|S#state.a_regs]}
    end;
%% a_unreg
next_state(S,_V,{call,_,a_unreg,[#a_reg{key=AggrCounter}]}) ->
    S#state{a_regs=[ X || #a_reg{key=AggrCounter1}=X <- S#state.a_regs
                              , AggrCounter/=AggrCounter1 ]};
%% set_value
next_state(S,_V,{call,_,set_value,[#c_reg{key=Counter,pid=Pid},Value]}) ->
    case is_c_registered_and_alive(S,Counter,Pid) of
        false ->
            S;
        true ->
            Fun = fun(#c_reg{key=Counter1,pid=Pid1}) -> Counter==Counter1 andalso Pid==Pid1 end,
            case lists:splitwith(Fun, S#state.c_regs) of
                {[#c_reg{key=Counter,pid=Pid,value=_OldValue}], Others} ->
                    S#state{c_regs=[#c_reg{key=Counter,pid=Pid,value=Value}|Others]}
            end
    end;
%% otherwise
next_state(S,_V,{call,_,_,_}) ->
    S.


%% Precondition, checked before command is added to the command
%% sequence
precondition(_S,{call,_,_,_}) ->
    true.


%% Postcondition, checked after command has been evaluated.  S is the
%% state before next_state(S,_,<command>)

%% spawn
postcondition(_S,{call,_,spawn,_},_Res) ->
    true;
%% kill
postcondition(_S,{call,_,kill,_},_Res) ->
    true;
%% n_reg
postcondition(S,{call,_,n_reg,[Name,Pid]},Res) ->
    case Res of
        true ->
            is_n_register_ok(S,Name,Pid);
        {'EXIT',_} ->
            not is_n_register_ok(S,Name,Pid)
    end;
%% n_unreg
postcondition(S,{call,_,n_unreg,[#n_reg{key=Name,pid=Pid}]},Res) ->
    case Res of
        true ->
            is_n_unregister_ok(S,Name,Pid);
        {'EXIT',_} ->
            not is_n_unregister_ok(S,Name,Pid)
    end;
%% c_reg
postcondition(S,{call,_,c_reg,[Counter,Pid,_Value]},Res) ->
    case Res of
        true ->
            is_c_register_ok(S,Counter,Pid);
        {'EXIT',_} ->
            not is_c_register_ok(S,Counter,Pid)
    end;
%% c_unreg
postcondition(S,{call,_,c_unreg,[#c_reg{key=Counter,pid=Pid}]},Res) ->
    case Res of
        true ->
            is_c_unregister_ok(S,Counter,Pid);
        {'EXIT',_} ->
            not is_c_unregister_ok(S,Counter,Pid)
    end;
%% a_reg
postcondition(S,{call,_,a_reg,[AggrCounter,Pid]},Res) ->
    case Res of
        true ->
            is_a_register_ok(S,AggrCounter,Pid);
        {'EXIT',_} ->
            not is_a_register_ok(S,AggrCounter,Pid)
    end;
%% a_unreg
postcondition(S,{call,_,a_unreg,[#a_reg{key=AggrCounter,pid=Pid}]},Res) ->
    case Res of
        true ->
            is_a_unregister_ok(S,AggrCounter,Pid);
        {'EXIT',_} ->
            not is_a_unregister_ok(S,AggrCounter,Pid)
    end;
%% set_value
postcondition(S,{call,_,set_value,[#c_reg{key=Counter,pid=Pid},_Value]},Res) ->
    case Res of
        true ->
            is_c_registered_and_alive(S,Counter,Pid);
        {'EXIT',_} ->
            not is_c_registered_and_alive(S,Counter,Pid)
    end;
%% get_value
postcondition(S,{call,_,get_value,[#c_reg{key=Counter,pid=Pid}]},Res) ->
    case [ Value1 || #c_reg{key=Counter1,pid=Pid1,value=Value1} <- S#state.c_regs
                         , Counter==Counter1 andalso Pid==Pid1 ] of
        [] ->
            case Res of {'EXIT',_} -> true; _ -> false end;
        [Value] ->
            Res == Value
    end;
%% get_value
postcondition(S,{call,_,get_value,[#a_reg{key=AggrCounter,pid=Pid}]},Res) ->
    case [ Value1 || #a_reg{key=AggrCounter1,pid=Pid1,value=Value1} <- S#state.a_regs
                         , AggrCounter==AggrCounter1 andalso Pid==Pid1 ] of
        [] ->
            case Res of {'EXIT',_} -> true; _ -> false end;
        [Value] ->
            Res == Value
    end;
%% where
postcondition(S,{call,_,where,[{n,l,Name}]},Res) ->
    case lists:keysearch(Name,#n_reg.key,S#state.n_regs) of
        {value, #n_reg{pid=Pid}} ->
            Res == Pid;
        false ->
            Res == undefined
    end;
postcondition(S,{call,_,where,[{a,l,AggrCounter}]},Res) ->
    case lists:keysearch(AggrCounter,#a_reg.key,S#state.a_regs) of
        {value, #a_reg{pid=Pid}} ->
            Res == Pid;
        false ->
            Res == undefined
    end;
%% lookup_pids
postcondition(S,{call,_,lookup_pids,[{c,l,Counter}]},Res) ->
    lists:usort(Res) ==
        [ Pid || #c_reg{key=Counter1,pid=Pid} <- S#state.c_regs, Counter==Counter1 ];
%% otherwise
postcondition(_S,{call,_,_,_},_Res) ->
    false.

%% property
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


%% If using the scheduler... This code needs to run in a separate
%% module, so it can be compiled without instrumentation.

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


%% helpers
is_n_register_ok(S,Name,Pid) ->
    not is_n_unregister_ok(S,Name,Pid).

is_n_unregister_ok(S,Name,_Pid) ->
    lists:keymember(Name,#n_reg.key,S#state.n_regs).

is_c_register_ok(S,Counter,Pid) ->
    not is_c_unregister_ok(S,Counter,Pid).

is_c_unregister_ok(S,Counter,_Pid) ->
    [] /= [ Pid1 || #c_reg{key=Counter1,pid=Pid1} <- S#state.c_regs, Counter==Counter1 ].

is_a_register_ok(S,AggrCounter,Pid) ->
    not is_a_unregister_ok(S,AggrCounter,Pid).

is_a_unregister_ok(S,AggrCounter,_Pid) ->
    lists:keymember(AggrCounter,#a_reg.key,S#state.a_regs).

is_c_registered_and_alive(S,Counter,Pid) ->
    [Pid] == [ Pid1 || #c_reg{key=Counter1,pid=Pid1} <- S#state.c_regs, Counter==Counter1 ]
        andalso lists:member(Pid,S#state.pids)
        andalso not lists:member(Pid,S#state.killed).

%% spawn
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

%% kill
kill(Pid) ->
    exit(Pid,foo),
    timer:sleep(10).

%% n_reg
n_reg(Name,Pid) ->
    do(Pid,
       fun() ->
               catch gproc:reg({n,l,Name},Pid)
       end).

%% n_unreg
n_unreg(#n_reg{key=Name,pid=Pid}) ->
    do(Pid,
       fun() ->
               catch gproc:unreg({n,l,Name})
       end).

%% c_reg
c_reg(Counter,Pid,Value) ->
    do(Pid,
       fun() ->
               catch gproc:reg({c,l,Counter},Value)
       end).

%% c_unreg
c_unreg(#c_reg{key=Counter,pid=Pid}) ->
    do(Pid,
       fun() ->
               catch gproc:unreg({c,l,Counter})
       end).

%% a_reg
a_reg(AggrCounter,Pid) ->
    do(Pid,
       fun() ->
               catch gproc:reg({a,l,AggrCounter},Pid)
       end).

%% a_unreg
a_unreg(#a_reg{key=AggrCounter,pid=Pid}) ->
    do(Pid,
       fun() ->
               catch gproc:unreg({a,l,AggrCounter})
       end).

%% set_value
set_value(#c_reg{key=Counter,pid=Pid},Value) ->
    do(Pid,
       fun() ->
               catch gproc:set_value({c,l,Counter},Value)
       end).

%% get_value
get_value(#c_reg{key=Counter,pid=Pid}) ->
    do(Pid,
       fun() ->
               catch gproc:get_value({c,l,Counter})
       end);
get_value(#a_reg{key=AggrCounter,pid=Pid}) ->
    do(Pid,
       fun() ->
               catch gproc:get_value({a,l,AggrCounter})
       end).


%% do
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
