%%% File        : gproc_eqc_tests.erl
%%% Author      : <norton@alum.mit.edu>
%%%             : <Ulf.Wiger@erlang-consulting.com>
%%%             : <John.Hughes@quviq.com>
%%% Description : QuickCheck test model for gproc
%%% Created     : 11 Dec 2008 by  <John Hughes@JTABLET2007>

-module(gproc_eqc_tests).

-ifdef(EQC).

-include_lib("eqc/include/eqc.hrl").
-include_lib("eqc/include/eqc_statem.hrl").
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-compile(export_all).

%%
%% QUESTIONS:
%%
%%  - does set_value for Class==a make sense?
%%  - shouldn't mreg return {true, keys()} rather than the {true,
%%    objects()} upon success?

%%
%% TODO:
%%
%%  - implement mreg
%%  - implement send
%%  - implement info
%%  - implement select
%%  - implement first/next/prev/last
%%  - implement table
%%

%% records
-record(key,
        {class          %% class()
         , scope        %% scope()
         , name         %% name()
        }).

-record(reg,
        {pid            %% pid()
         , key          %% key()
         , value        %% int()
        }).

-record(state,
        {pids=[]        %% [pid()]
         , killed=[]    %% [pid()]
         , regs=[]      %% [reg()]
         , waiters=[]   %% [{key(),pid()}]
        }).


%% external API

good_number_of_tests() ->
    3000.

%% hook to run from eunit. Note: a small number of tests.
%% I recommend running at least 3000 to get to interesting stuff.
%%
gproc_test_() ->
    {timeout, 60, [fun() -> run(100) end]}.

%% When run from eunit, we need to set the group leader so that EQC
%% reporting (the dots) are made visible - that is, if that's what we want.
verbose_run(N) ->
    erlang:group_leader(whereis(user), self()),
    run(N).

%% 3000 tests seems like a large number, but this seems to be needed
%% to reach enough variation in the tests.
all_tests() ->
    eqc:module({numtests, good_number_of_tests()}, ?MODULE).

run() ->
    run(good_number_of_tests()).

run(Num) ->
    error_logger:delete_report_handler(error_logger_tty_h),
    eqc:quickcheck(eqc:numtests(Num, prop_gproc())).

%% Command generator, S is the state
command(S) ->
    oneof(
      %% spawn
      [ {call,?MODULE,spawn, []} ]

      %% where
      ++ [ {call,?MODULE,where, [key()]} ]

      ++ [ {call,?MODULE,await_new, [name_key()]} ]

      %% kill
      ++ [ oneof([
                  %% kill
                  {call,?MODULE,kill,             [elements(S#state.pids)]}
                  %% register
                  , {call,?MODULE,reg,            ?LET(Key, key(),[elements(S#state.pids), Key, reg_value(Key)])}
                  %% unregister
                  , {call,?MODULE,unreg,          [elements(S#state.pids), key()]}
                  %% many register
                  , {call, ?MODULE, mreg,         ?LET({Pid,Class,Scope}, {elements(S#state.pids),class(),scope()}, [Pid, Class, Scope, mreg_values(S, Class, Scope)])}
                  %%, {call,?MODULE,mreg,           [elements(S#state.pids), class(), scope()
                  %%                                 , list({name(), value()})]}

                  %% set_value
                  , {call,?MODULE,set_value,      ?LET(Key, key(),[elements(S#state.pids), Key, reg_value(Key)])}
                  %% update_counter
                  , {call,?MODULE,update_counter, [elements(S#state.pids), key(), value()]}

                  %% get_value
                  , {call,?MODULE,get_value,      [elements(S#state.pids), key()]}
                  %% lookup_pid
                  , {call,?MODULE,lookup_pid,     [key()]}
                  %% lookup_pids
                  , {call,?MODULE,lookup_pids,    [key()]}
                 ])
           || S#state.pids/=[] ]

      ++ [
          %% await on existing value
          {call,?MODULE,await_existing, [elements(S#state.regs)]}
          || S#state.regs/=[] ]


     ).

%% generator class
class() -> elements([n,p,c,a]).

%% generator scope
scope() -> l.

%% generator name
name() -> elements(names()).

names() -> [x,y,z,w].
    

%% generator key
key() -> key(class(), scope(), name()).

key(Class, Scope, Name) ->
    #key{class=Class, scope=Scope, name=Name}.

name_key() ->
    key(n, scope(), name()).
    

%% generator value
value() -> frequency([{8, int()}, {1, undefined}, {1, make_ref()}]).

%% value for reg and set_value
%% 'a' and 'c' should only have integers as values (reg: value is ignored for 'a') 
reg_value(#key{class=C}) when C == a; C == c -> int();
reg_value(_) -> value().


mreg_values(_S, Class, Scope) ->
    ?LET(Names, subset(names()),
         [?LET(K, key(Class, Scope, N), {K, reg_value(K)}) || N <- Names]).


%% Snipped from the TrapExit QuickCheck tutorials
%% http://trapexit.org/SubSetGenerator
subset(Generators) ->
   ?LET(Keep,[ {bool(),G} || G<-Generators],
	[ G || {true,G}<-Keep]).

%% helpers
is_register_ok(_S,_Pid,#key{class=c},Value) when not is_integer(Value) ->
    false;
is_register_ok(_S,_Pid,#key{class=a},Value) ->
    Value == undefined;
is_register_ok(S,Pid,Key,_Value) ->
    [] == [ Pid1 || #reg{pid=Pid1,key=Key1}
                        <- S#state.regs, is_register_eq(Pid,Key,Pid1,Key1) ].

is_mreg_ok(S, Pid, List) ->
    lists:all(fun({Key, Value}) ->
                      is_register_ok(S, Pid, Key, Value)
              end, List).

is_register_eq(_PidA,#key{class=Class}=KeyA,_PidB,KeyB)
  when Class == n; Class ==a ->
    KeyA==KeyB;
is_register_eq(PidA,KeyA,PidB,KeyB) ->
    PidA==PidB andalso KeyA==KeyB.

is_unregister_ok(S,Pid,Key) ->
    [] /= [ Pid1 || #reg{pid=Pid1,key=Key1}
                        <- S#state.regs, is_unregister_eq(Pid,Key,Pid1,Key1) ].

is_unregister_eq(PidA,KeyA,PidB,KeyB) ->
    KeyA==KeyB andalso PidA==PidB.

is_registered_and_alive(S,Pid,Key) ->
    is_unregister_ok(S,Pid,Key)
        andalso lists:member(Pid,S#state.pids).


%% Initialize the state
initial_state() ->
    #state{}.


%% Next state transformation, S is the current state
%% spawn
next_state(S,V,{call,_,spawn,_}) ->
    S#state{pids=[V|S#state.pids]};
%% kill
next_state(S,_V,{call,_,kill,[Pid]}) ->
    S#state{pids=S#state.pids -- [Pid]
            , killed=[Pid|S#state.killed]
            , regs=[ X || #reg{pid=Pid1}=X <- S#state.regs, Pid/=Pid1 ]
           };
%% reg
next_state(S,_V,{call,_,reg,[Pid,Key,Value]}) ->
    case is_register_ok(S,Pid,Key,Value) of
        false ->
            S;
        true ->
            update_state_reg(S, Pid, Key, Value)
    end;
next_state(S,_V,{call,_,mreg,[Pid, _Class, _Scope, List]}) ->
    case is_mreg_ok(S, Pid, List) of
        false ->
            S;
        true ->
            lists:foldl(
              fun({Key, Value}, Acc) ->
                      update_state_reg(Acc, Pid, Key, Value)
              end, S, List)
    end;
%% unreg
next_state(S,_V,{call,_,unreg,[Pid,Key]}) ->
    case is_unregister_ok(S,Pid,Key) of
        false ->
            S;
        true ->
            FunC = fun(#reg{pid=Pid1,key=Key1}) -> (Pid==Pid1 andalso Key==Key1) end,
            case lists:partition(FunC, S#state.regs) of
                {[#reg{value=Value}], Others} ->
                    S1 = S#state{regs=Others},
                    case Key of
                        #key{class=c,name=Name} ->
                            %% update aggr counter
                            FunA = fun(#reg{key=#key{class=Class1,name=Name1}}) -> (Class1 == a andalso Name==Name1) end,
                            case lists:partition(FunA, S1#state.regs) of
                                {[], _Others1} ->
                                    S1;
                                {[Reg], Others1} ->
                                    S1#state{regs=[Reg#reg{value=Reg#reg.value-Value}|Others1]}
                            end;
                        _ ->
                            S1
                    end
            end
    end;
%% set_value
next_state(S,_V,{call,_,set_value,[Pid,Key,Value]}) ->
    case is_registered_and_alive(S,Pid,Key) of
        false ->
            S;
        true ->
            FunC = fun(#reg{pid=Pid1,key=Key1}) -> (Pid==Pid1 andalso Key==Key1) end,
            case lists:partition(FunC, S#state.regs) of
                {[#reg{value=OldValue}=OldReg], Others} ->
                    S1 = S#state{regs=[OldReg#reg{value=Value}|Others]},
                    case Key of
                        #key{class=c,name=Name} ->
                            %% aggr counter update
                            FunA = fun(#reg{key=#key{class=Class1,name=Name1}}) -> (Class1 == a andalso Name==Name1) end,
                            case lists:partition(FunA, S1#state.regs) of
                                {[], _Others1} ->
                                    S1;
                                {[Reg], Others1} ->
                                    S1#state{regs=[Reg#reg{value=Reg#reg.value-OldValue+Value}|Others1]}
                            end;
                        _ ->
                            S1
                    end
            end
    end;
%% update_counter
next_state(S,_V,{call,_,update_counter,[Pid,#key{class=Class}=Key,Incr]})
  when Class == c, is_integer(Incr) ->
    case is_registered_and_alive(S,Pid,Key) of
        false ->
            S;
        true ->
            FunC = fun(#reg{pid=Pid1,key=Key1}) -> (Pid==Pid1 andalso Key==Key1) end,
            case lists:partition(FunC, S#state.regs) of
                {[#reg{value=OldValue}=OldReg], Others} ->
                    S1 = S#state{regs=[OldReg#reg{value=OldValue+Incr}|Others]},
                    case Key of
                        #key{class=c,name=Name} ->
                            %% aggr counter update
                            FunA = fun(#reg{key=#key{class=Class1,name=Name1}}) -> (Class1 == a andalso Name==Name1) end,
                            case lists:partition(FunA, S1#state.regs) of
                                {[], _Others1} ->
                                    S1;
                                {[Reg], Others1} ->
                                    S1#state{regs=[Reg#reg{value=Reg#reg.value+Incr}|Others1]}
                            end;
                        _ ->
                            S1
                    end
            end
    end;
next_state(S,V,{call,_,await_new,[Key]}) ->
    S#state{waiters = [{Key,V}|S#state.waiters]};
%% otherwise
next_state(S,_V,{call,_,_,_}) ->
    S.


update_state_reg(S, Pid, Key, Value) ->
    case Key of
        #key{class=a,name=Name} ->
            %% initialize aggr counter
            FunC = fun(#reg{key=#key{class=Class1,name=Name1}}) -> (Class1 == c andalso Name==Name1) end,
            {Regs, _Others} = lists:partition(FunC, S#state.regs),
            InitialValue = lists:sum([ V || #reg{value=V} <- Regs ]),
            S#state{regs=[#reg{pid=Pid,key=Key,value=InitialValue}|S#state.regs]};
        #key{class=c,name=Name} ->
            S1 = S#state{regs=[#reg{pid=Pid,key=Key,value=Value}|S#state.regs]},
            %% update aggr counter
            FunA = fun(#reg{key=#key{class=Class1,name=Name1}}) -> (Class1 == a andalso Name==Name1) end,
            case lists:partition(FunA, S1#state.regs) of
                {[Reg], Others} ->
                    S1#state{regs=[Reg#reg{value=Reg#reg.value+Value}|Others]};
                {[], _Others} ->
                    S1
            end;
        _ ->
            S#state{regs=[#reg{pid=Pid,key=Key,value=Value}|S#state.regs],
                    waiters = [W || {K,_} = W <- S#state.waiters,
                                    K =/= Key]}
    end.



%% Precondition, checked before command is added to the command
%% sequence
precondition(S, {call,_,reg, [Pid, _Key, _Value]}) ->
    lists:member(Pid, S#state.pids);
precondition(S, {call,_,unreg, [Pid, _Key]}) ->
    lists:member(Pid, S#state.pids);
precondition(S, {call,_,await_new,[#key{class=C}=Key]}) ->
    C == n andalso
        not lists:keymember(Key,#reg.key,S#state.regs);
precondition(S, {call,_,mreg,[Pid, Class, _Scope, List]}) ->
    %% TODO: lift this restriction to generate all classes mreg can handle
    Class == n andalso
	lists:member(Pid, S#state.pids) andalso
        lists:all(fun({#key{class=C},_}) -> C == n end, List);
precondition(S, {call,_,await_existing,[#reg{key=#key{class=C}=Key}]}) ->
    C == n andalso
	lists:keymember(Key, #reg.key, S#state.regs);
precondition(S,{call,_,get_value,[Pid,_]}) ->
	lists:member(Pid,S#state.pids);
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
%% where
postcondition(S,{call,_,where,[#key{class=Class}=Key]},Res) ->
    if Class == n orelse Class == a ->
            case lists:keysearch(Key,#reg.key,S#state.regs) of
                {value, #reg{pid=Pid}} ->
                    Res == Pid;
                false ->
                    Res == undefined
            end;
       true ->
            case Res of
                {'EXIT', {badarg, _}} ->
                    true;
                _ ->
                    false
            end
    end;
%% reg
postcondition(S,{call,_,reg,[Pid,Key,Value]},Res) ->
    case Res of
        true ->
            is_register_ok(S,Pid,Key,Value) andalso
                check_waiters(Pid, Key, Value, S#state.waiters);
        {'EXIT', {badarg, _}} ->
            is_unregister_ok(S,Pid,Key)
                orelse not is_register_ok(S,Pid,Key,Value)
    end;
postcondition(S,{call,_,mreg,[Pid,_Class,_Scope,List]},Res) ->
    case Res of
        true ->
            is_mreg_ok(S,Pid,List)
                andalso lists:all(fun({K,V}) ->
                                          check_waiters(Pid,K,V, S#state.waiters)
                                  end, List);
        {'EXIT', {badarg,_}} ->
            not is_mreg_ok(S,Pid,List)
    end;
    
%% unreg
postcondition(S,{call,_,unreg,[Pid,Key]},Res) ->
    case Res of
        true ->
            is_unregister_ok(S,Pid,Key);
        {'EXIT', {badarg, _}} ->
            not is_unregister_ok(S,Pid,Key)
    end;
%% set_value
postcondition(S,{call,_,set_value,[Pid,Key,_Value]},Res) ->
    case Res of
        true ->
            is_registered_and_alive(S,Pid,Key);
        {'EXIT', {badarg, _}} ->
            not is_registered_and_alive(S,Pid,Key)
                orelse (Key#key.class == c
                        andalso is_registered_and_alive(S, Pid, Key))
    end;
%% update_counter
postcondition(S,{call,_,update_counter,[Pid,#key{class=Class}=Key,Incr]},Res)
  when Class == c, is_integer(Incr) ->
    case [ Value1 || #reg{pid=Pid1,key=Key1,value=Value1} <- S#state.regs
                         , (Pid==Pid1 andalso Key==Key1) ] of
        [] ->
            case Res of {'EXIT', {badarg, _}} -> true; _ -> false end;
        [Value] when is_integer(Value) ->
            Res == Value+Incr;
		[_] ->
            case Res of {'EXIT', {badarg, _}} -> true; _ -> false end
    end;
postcondition(_S,{call,_,update_counter,[_Pid,_Key,_Incr]},Res) ->
    case Res of {'EXIT', {badarg, _}} -> true; _ -> false end;
%% get_value
postcondition(S,{call,_,get_value,[Pid,Key]},Res) ->
    case [ Value1 || #reg{pid=Pid1,key=Key1,value=Value1} <- S#state.regs
                         , (Pid==Pid1 andalso Key==Key1) ] of
        [] ->
            case Res of {'EXIT', {badarg, _}} -> true; _ -> false end;
        [Value] ->
            Res == Value
    end;
%% lookup_pid
postcondition(S,{call,_,lookup_pid,[#key{class=Class}=Key]},Res)
  when Class == n; Class == a ->
    case [ Pid1 || #reg{pid=Pid1,key=Key1} <- S#state.regs
                       , Key==Key1 ] of
        [] ->
            case Res of {'EXIT', {badarg, _}} -> true; _ -> false end;
        [Pid] ->
            Res == Pid
    end;
postcondition(_S,{call,_,lookup_pid,[_Key]},Res) ->
    case Res of {'EXIT', {badarg, _}} -> true; _ -> false end;
%% lookup_pids
postcondition(S,{call,_,lookup_pids,[#key{class=Class}=Key]},Res)
  when Class == n; Class == a; Class == c; Class == p ->
    Pids = [ Pid1 || #reg{pid=Pid1,key=Key1} <- S#state.regs
                         , Key==Key1 ],
    lists:sort(Res) == lists:sort(Pids);
postcondition(_S, {call,_,await_new,[#key{}]}, Pid) ->
    is_pid(Pid);
postcondition(S,{call,_,await_existing,[#reg{key=Key}]}, {P1,V1}) ->
    case lists:keyfind(Key, #reg.key, S#state.regs) of
        #reg{pid=P1, value = V1} -> true;
        _ -> false
    end;
%% postcondition(_S,{call,_,lookup_pids,[_Key]},Res) ->
%%     case Res of {'EXIT', {badarg, _}} -> true; _ -> false end;
%% otherwise
postcondition(_S,{call,_,_,_},_Res) ->
    false.


%%% Spec fixes
%%% 
%%% - added precondition for set_value must be integer (could be changed 
%%%   to neg. test)
%%% - updated postcondition for update_counter to check for non-integers
%%%
%%% It still crashes on lists:sum in next_state... Maybe we should change
%%% the generators instead!

prop_gproc() ->
    ?FORALL(Cmds,commands(?MODULE),
            ?TRAPEXIT(
               begin
                   ok = stop_app(),
                   ok = start_app(),
                   {H,S,Res} = run_commands(?MODULE,Cmds),
                   kill_all_pids({H,S}),

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

%% helpers
start_app() ->
    case application:start(gproc) of
        {error, {already_started,_}} ->
            stop_app(),
            ok = application:start(gproc);
        ok ->
            ok
    end.

stop_app() ->
    case application:stop(gproc) of
        {error, {not_started,_}} ->
            ok;
        ok ->
            ok
    end.

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


%% spawn
spawn() ->
    spawn(fun() -> loop() end).

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

%% where
where(#key{class=Class,scope=Scope,name=Name}) ->
    catch gproc:where({Class,Scope,Name}).

%% reg
reg(Pid,#key{class=Class,scope=Scope,name=Name},Value) ->
    do(Pid, fun() -> catch gproc:reg({Class,Scope,Name},Value) end).

mreg(Pid, Class, Scope, List) ->
    do(Pid, fun() -> catch gproc:mreg(Class,Scope,[{Name,Value} || {#key{name = Name}, Value} <- List]) end).
                     

%% unreg
unreg(Pid,#key{class=Class,scope=Scope,name=Name}) ->
    do(Pid, fun() -> catch gproc:unreg({Class,Scope,Name}) end).

%% set_value
set_value(Pid,#key{class=Class,scope=Scope,name=Name},Value) ->
    do(Pid, fun() -> catch gproc:set_value({Class,Scope,Name},Value) end).

%% update_counter
update_counter(Pid, #key{class=Class,scope=Scope,name=Name},Incr) ->
    do(Pid, fun() -> catch gproc:update_counter({Class,Scope,Name},Incr) end).

%% get_value
get_value(Pid,#key{class=Class,scope=Scope,name=Name}) ->
    do(Pid, fun() -> catch gproc:get_value({Class,Scope,Name}) end).

%% lookup_pid
lookup_pid(#key{class=Class,scope=Scope,name=Name}) ->
    catch gproc:lookup_pid({Class,Scope,Name}).

%% lookup_pids
lookup_pids(#key{class=Class,scope=Scope,name=Name}) ->
    catch gproc:lookup_pids({Class,Scope,Name}).

%% do
do(Pid, F) ->
    Ref = erlang:monitor(process, Pid),
    Pid ! {self(), Ref, F},
    receive
        {'DOWN', Ref, process, Pid, Reason} ->
            {'EXIT', {'DOWN', Reason}};
        {Ref, Result} ->
            erlang:demonitor(Ref),
            Result
    after 3000 ->
            {'EXIT', timeout}
    end.


await_existing(#reg{key = #key{class=Class,scope=Scope,name=Name}}) ->
    %% short timeout, this call is expected to work
    gproc:await({Class,Scope,Name}, 10000).

await_new(#key{class=Class,scope=Scope,name=Name}) ->
    spawn(
      fun() ->
              Res = (catch gproc:await({Class,Scope,Name})),
              receive
                  {From, send_result} ->
                      From ! {result, Res},
                      timer:sleep(1000)
              end
      end).

check_waiters(Pid, Key, Value, Waiters) ->
    case [W || {K, W} <- Waiters,
               K == Key] of
        [] ->
            true;
        WPids ->
            lists:all(fun(WPid) ->
                              check_waiter(WPid, Pid, Key, Value)
                      end, WPids)
    end.

check_waiter(WPid, Pid, _Key, Value) ->   
    MRef = erlang:monitor(process, WPid),
    WPid ! {self(), send_result},
    receive
        {result, Res} ->
            {Pid,Value} == Res;
        {'DOWN', MRef, _, _, R} ->
            erlang:error(R)
    after 1000 ->
            erlang:error(timeout)
    end.

-endif.
