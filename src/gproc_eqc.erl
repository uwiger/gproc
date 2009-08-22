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
      ++ [ {call,?MODULE,n_unreg,[name(),elements(S#state.pids)]}
           || S#state.pids/=[] ]
      %% counter - register
      ++ [ {call,?MODULE,c_reg,[counter(),elements(S#state.pids),int()]}
           || S#state.pids/=[] ]
      %% counter - unregister
      ++ [ {call,?MODULE,c_unreg,[counter(),elements(S#state.pids)]}
           || S#state.pids/=[] ]
      %% aggr counter - register
      ++ [ {call,?MODULE,a_reg,[aggr_counter(),elements(S#state.pids)]}
           || S#state.pids/=[] ]
      %% aggr counter - unregister
      ++ [ {call,?MODULE,a_unreg,[aggr_counter(),elements(S#state.pids)]}
           || S#state.pids/=[] ]

      %% counter - set_value
      ++ [ {call,?MODULE,c_set_value,[counter(),elements(S#state.pids),int()]}
           || S#state.pids/=[] ]

      %% aggr counter - get_value
      ++ [ {call,?MODULE,a_get_value,[aggr_counter(),elements(S#state.pids)]}
           || S#state.pids/=[] ]

      %% name - where
      ++ [{call,gproc,where,[{n,l,name()}]}]
      %% aggr counter - where
      ++ [{call,gproc,where,[{a,l,aggr_counter()}]}]

      %% TODO: postcondition fails ... need to investigate ?
      %% %% counter - lookup_pids
      %% ++ [ {call,gproc,lookup_pids,[{c,l,counter()}]} ]

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
next_state(S,_V,{call,_,n_reg,[Key,Pid]}) ->
    case is_n_register_ok(S,Key,Pid) of
        false ->
            S;
        true ->
            S#state{n_regs=[#n_reg{key=Key,pid=Pid}|S#state.n_regs]}
    end;
%% n_unreg
next_state(S,_V,{call,_,n_unreg,[Key,Pid]}) ->
    case is_n_unregister_ok(S,Key,Pid) of
        false ->
            S;
        true ->
            FunN = fun(#n_reg{key=Key1,pid=Pid1}) -> (Key==Key1 andalso Pid==Pid1) end,
            case lists:partition(FunN, S#state.n_regs) of
                {[_], NOthers} ->
                    S#state{n_regs=NOthers}
            end
    end;
%% c_reg
next_state(S,_V,{call,_,c_reg,[Key,Pid,Value]}) ->
    case is_c_register_ok(S,Key,Pid) of
        false ->
            S;
        true ->
            S1 = S#state{c_regs=[#c_reg{key=Key,pid=Pid,value=Value}|S#state.c_regs]},
            %% aggr counter update
            FunA = fun(#a_reg{key=Key1}) -> Key==Key1 end,
            case lists:partition(FunA, S#state.a_regs) of
                {[], _AOthers} ->
                    S1;
                {[AReg], AOthers} ->
                    S1#state{a_regs=[AReg#a_reg{value=AReg#a_reg.value+Value}|AOthers]}
            end
    end;
%% c_unreg
next_state(S,_V,{call,_,c_unreg,[Key,Pid]}) ->
    case is_c_unregister_ok(S,Key,Pid) of
        false ->
            S;
        true ->
            FunC = fun(#c_reg{key=Key1,pid=Pid1}) -> (Key==Key1 andalso Pid==Pid1) end,
            case lists:partition(FunC, S#state.c_regs) of
                {[#c_reg{value=Value}], COthers} ->
                    S1 = S#state{c_regs=COthers},
                    %% aggr counter update
                    FunA = fun(#a_reg{key=Key1}) -> Key==Key1 end,
                    case lists:partition(FunA, S#state.a_regs) of
                        {[], _AOthers} ->
                            S1;
                        {[AReg], AOthers} ->
                            S1#state{a_regs=[AReg#a_reg{value=AReg#a_reg.value-Value}|AOthers]}
                    end
            end
    end;
%% a_reg
next_state(S,_V,{call,_,a_reg,[Key,Pid]}) ->
    case is_a_register_ok(S,Key,Pid) of
        false ->
            S;
        true ->
            S#state{a_regs=[#a_reg{key=Key,pid=Pid,value=0}|S#state.a_regs]}
    end;
%% a_unreg
next_state(S,_V,{call,_,a_unreg,[Key,Pid]}) ->
    case is_a_unregister_ok(S,Key,Pid) of
        false ->
            S;
        true ->
            FunA = fun(#a_reg{key=Key1,pid=Pid1}) -> (Key==Key1 andalso Pid==Pid1) end,
            case lists:partition(FunA, S#state.a_regs) of
                {[_], AOthers} ->
                    S#state{a_regs=AOthers}
            end
    end;
%% set_value
next_state(S,_V,{call,_,c_set_value,[Key,Pid,Value]}) ->
    case is_c_registered_and_alive(S,Key,Pid) of
        false ->
            S;
        true ->
            FunC = fun(#c_reg{key=Key1,pid=Pid1}) -> (Key==Key1 andalso Pid==Pid1) end,
            case lists:partition(FunC, S#state.c_regs) of
                {[#c_reg{value=OldValue}=CReg], COthers} ->
                    S1 = S#state{c_regs=[CReg#c_reg{value=Value}|COthers]},
                    %% aggr counter update
                    FunA = fun(#a_reg{key=Key1}) -> Key==Key1 end,
                    case lists:partition(FunA, S#state.a_regs) of
                        {[], _AOthers} ->
                            S1;
                        {[AReg], AOthers} ->
                            S1#state{a_regs=[AReg#a_reg{value=AReg#a_reg.value-OldValue+Value}|AOthers]}
                    end
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
postcondition(S,{call,_,n_reg,[Key,Pid]},Res) ->
    case Res of
        true ->
            is_n_register_ok(S,Key,Pid);
        {'EXIT',_} ->
            not is_n_register_ok(S,Key,Pid)
    end;
%% n_unreg
postcondition(S,{call,_,n_unreg,[Key,Pid]},Res) ->
    case Res of
        true ->
            is_n_unregister_ok(S,Key,Pid);
        {'EXIT',_} ->
            not is_n_unregister_ok(S,Key,Pid)
    end;
%% c_reg
postcondition(S,{call,_,c_reg,[Key,Pid,_Value]},Res) ->
    case Res of
        true ->
            is_c_register_ok(S,Key,Pid);
        {'EXIT',_} ->
            not is_c_register_ok(S,Key,Pid)
    end;
%% c_unreg
postcondition(S,{call,_,c_unreg,[Key,Pid]},Res) ->
    case Res of
        true ->
            is_c_unregister_ok(S,Key,Pid);
        {'EXIT',_} ->
            not is_c_unregister_ok(S,Key,Pid)
    end;
%% a_reg
postcondition(S,{call,_,a_reg,[Key,Pid]},Res) ->
    case Res of
        true ->
            is_a_register_ok(S,Key,Pid);
        {'EXIT',_} ->
            not is_a_register_ok(S,Key,Pid)
    end;
%% a_unreg
postcondition(S,{call,_,a_unreg,[Key,Pid]},Res) ->
    case Res of
        true ->
            is_a_unregister_ok(S,Key,Pid);
        {'EXIT',_} ->
            not is_a_unregister_ok(S,Key,Pid)
    end;
%% set_value
postcondition(S,{call,_,c_set_value,[Key,Pid,_Value]},Res) ->
    case Res of
        true ->
            is_c_registered_and_alive(S,Key,Pid);
        {'EXIT',_} ->
            not is_c_registered_and_alive(S,Key,Pid)
    end;
%% get_value
postcondition(S,{call,_,a_get_value,[Key,Pid]},Res) ->
    case [ Value || #a_reg{key=Key1,pid=Pid1,value=Value} <- S#state.a_regs
                        , (Key==Key1 andalso Pid==Pid1) ] of
        [] ->
            case Res of {'EXIT',_} -> true; _ -> false end;
        [Value] ->
            Res == Value
    end;
%% where
postcondition(S,{call,_,where,[{n,l,Key}]},Res) ->
    case lists:keysearch(Key,#n_reg.key,S#state.n_regs) of
        {value, #n_reg{pid=Pid}} ->
            Res == Pid;
        false ->
            Res == undefined
    end;
postcondition(S,{call,_,where,[{a,l,Key}]},Res) ->
    case lists:keysearch(Key,#a_reg.key,S#state.a_regs) of
        {value, #a_reg{pid=Pid}} ->
            Res == Pid;
        false ->
            Res == undefined
    end;
%% lookup_pids
postcondition(S,{call,_,lookup_pids,[{c,l,Key}]},Res) ->
    lists:sort(Res) ==
        lists:sort([ Pid || #c_reg{key=Key1,pid=Pid} <- S#state.c_regs, Key==Key1 ]);
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

                   %% whenfail
                   ?WHENFAIL(
                      begin
                          io:format("~nHISTORY:"),
                          if
                              length(H) < 1 ->
                                  io:format(" none~n");
                              true ->
                                  CmdsH = eqc_statem:zip(Cmds,H),
                                  [ begin
                                        {Cmd,{State,Reply}} = lists:nth(N,CmdsH),
                                        io:format("~n #~p:~n\tCmd: ~p~n\tReply: ~p~n\tState: ~p~n",
                                                  [N,Cmd,Reply,State])
                                    end
                                    || N <- lists:seq(1,length(CmdsH)) ]
                          end,
                          io:format("~nRESULT:~n\t~p~n",[Res]),
                          io:format("~nSTATE:~n\t~p~n",[S])
                      end,
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
is_n_register_ok(S,Key,_Pid) ->
    [] == [ Pid1 || #n_reg{key=Key1,pid=Pid1}
                        <- S#state.n_regs, (Key==Key1) ].

is_n_unregister_ok(S,Key,Pid) ->
    [] /= [ Pid1 || #n_reg{key=Key1,pid=Pid1}
                        <- S#state.n_regs, (Key==Key1 andalso Pid==Pid1) ].

is_c_register_ok(S,Key,Pid) ->
    [] == [ Pid1 || #c_reg{key=Key1,pid=Pid1}
                        <- S#state.c_regs, (Key==Key1 andalso Pid==Pid1) ].

is_c_unregister_ok(S,Key,Pid) ->
    [] /= [ Pid1 || #c_reg{key=Key1,pid=Pid1}
                        <- S#state.c_regs, (Key==Key1 andalso Pid==Pid1) ].

is_a_register_ok(S,Key,_Pid) ->
    [] == [ Pid1 || #a_reg{key=Key1,pid=Pid1}
                        <- S#state.a_regs, (Key==Key1) ].

is_a_unregister_ok(S,Key,Pid) ->
    [] /= [ Pid1 || #a_reg{key=Key1,pid=Pid1}
                        <- S#state.a_regs, (Key==Key1 andalso Pid==Pid1) ].

is_c_registered_and_alive(S,Key,Pid) ->
    is_c_unregister_ok(S,Key,Pid)
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
n_reg(Key,Pid) ->
    do(Pid,
       fun() ->
               catch gproc:reg({n,l,Key},Pid)
       end).

%% n_unreg
n_unreg(Key,Pid) ->
    do(Pid,
       fun() ->
               catch gproc:unreg({n,l,Key})
       end).

%% c_reg
c_reg(Key,Pid,Value) ->
    do(Pid,
       fun() ->
               catch gproc:reg({c,l,Key},Value)
       end).

%% c_unreg
c_unreg(Key,Pid) ->
    do(Pid,
       fun() ->
               catch gproc:unreg({c,l,Key})
       end).

%% a_reg
a_reg(Key,Pid) ->
    do(Pid,
       fun() ->
               catch gproc:reg({a,l,Key},Pid)
       end).

%% a_unreg
a_unreg(Key,Pid) ->
    do(Pid,
       fun() ->
               catch gproc:unreg({a,l,Key})
       end).

%% c_set_value
c_set_value(Key,Pid,Value) ->
    do(Pid,
       fun() ->
               catch gproc:set_value({c,l,Key},Value)
       end).

%% a_get_value
a_get_value(Key,Pid) ->
    do(Pid,
       fun() ->
               catch gproc:get_value({a,l,Key})
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
