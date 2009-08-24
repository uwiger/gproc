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
%% @author Ulf Wiger <ulf.wiger@ericsson.com>
%%
%% @doc Extended process registry
%% <p>This module implements an extended process registry</p>
%% <p>For a detailed description, see gproc/doc/erlang07-wiger.pdf.</p>
%% @end
-module(gproc).
-behaviour(gen_server).

-export([start_link/0,
         reg/2, unreg/1,
         mreg/3,
         set_value/2,
         get_value/1,
         where/1,
         lookup_pid/1,
         lookup_pids/1,
         update_counter/2,
         send/2,
         info/1, info/2,
         select/1, select/2,
         first/1,
         next/2,
         prev/2,
         last/1,
         table/1, table/2]).

%%% internal exports
-export([init/1,
         handle_cast/2,
         handle_call/3,
         handle_info/2,
         code_change/3,
         terminate/2]).

-include("gproc.hrl").

-define(SERVER, ?MODULE).

-define(CHK_DIST,
        case whereis(gproc_dist) of
            undefined ->
                erlang:error(local_only);
            _ ->
                ok
        end).

-record(state, {}).

start_link() ->
    create_tabs(),
    gen_server:start({local, ?SERVER}, ?MODULE, [], []).


%%% @spec({Class,Scope, Key}, Value) -> true
%%% @doc
%%%    Class = n  - unique name
%%%          | p  - non-unique property
%%%          | c  - counter
%%%          | a  - aggregated counter
%%%    Scope = l | g (global or local)
%%%
reg({_,g,_} = Key, Value) ->
    %% anything global
    ?CHK_DIST,
    gproc_dist:reg(Key, Value);
reg({T,l,_} = Key, Value) when T==n; T==a ->
    %% local names and aggregated counters
    call({reg, Key, Value});
reg({c,l,_} = Key, Value) ->
    %% local counter
    if is_integer(Value) ->
            call({reg, Key, Value});
       true ->
            erlang:error(badarg)
    end;
reg({_,l,_} = Key, Value) ->
    %% local property
    local_reg(Key, Value);
reg(_, _) ->
    erlang:error(badarg).

mreg(T, g, KVL) ->
    ?CHK_DIST,
    gproc_dist:mreg(T, KVL);
mreg(T, l, KVL) when T==a; T==n ->
    if is_list(KVL) -> call({mreg, T, l, KVL});
       true -> erlang:error(badarg)
    end;
mreg(p, l, KVL) ->
    local_mreg(p, KVL);
mreg(_, _, _) ->
    erlang:error(badarg).

unreg(Key) ->
    case Key of
        {_, g, _} ->
            ?CHK_DIST,
            gproc_dist:unreg(Key);
        {T, l, _} when T == n;
                       T == a -> call({unreg, Key});
        {_, l, _} ->
            case ets:member(?TAB, {Key,self()}) of
                true ->
                    gproc_lib:remove_reg(Key, self());
                false ->
                    erlang:error(badarg)
            end
    end.

select(Pat) ->
    select(all, Pat).

select(Scope, Pat) ->
    ets:select(?TAB, pattern(Pat, Scope)).

select(Scope, Pat, NObjs) ->
    ets:select(?TAB, pattern(Pat, Scope), NObjs).


%%% Local properties can be registered in the local process, since
%%% no other process can interfere.
%%%
local_reg(Key, Value) ->
    case gproc_lib:insert_reg(Key, Value, self(), l) of
        false -> erlang:error(badarg);
        true  -> monitor_me()
    end.

local_mreg(_, []) -> true;
local_mreg(T, [_|_] = KVL) ->
    case gproc_lib:insert_many(T, l, KVL, self()) of
        false     -> erlang:error(badarg);
        {true,_}  -> monitor_me()
    end.





set_value({_,g,_} = Key, Value) ->
    ?CHK_DIST,
    gproc_dist:set_value(Key, Value);
set_value({a,l,_} = Key, Value) when is_integer(Value) ->
    call({set, Key, Value});
set_value({n,l,_} = Key, Value) ->
    %% we cannot do this locally, since we have to check that the object
    %% exists first - not an atomic update.
    call({set, Key, Value});
set_value({p,l,_} = Key, Value) ->
    %% we _can_ to this locally, since there is no race condition - no
    %% other process can update our properties.
    case gproc_lib:do_set_value(Key, Value, self()) of
        true -> true;
        false ->
            erlang:error(badarg)
    end;
set_value({c,l,_} = Key, Value) when is_integer(Value) ->
    gproc_lib:do_set_counter_value(Key, Value, self());
set_value(_, _) ->
    erlang:error(badarg).




%%% @spec (Key) -> Value
%%% @doc Read the value stored with a key registered to the current process.
%%%
get_value(Key) ->
    get_value(Key, self()).

get_value({T,_,_} = Key, Pid) when is_pid(Pid) ->
    if T==n orelse T==a ->
            case ets:lookup(?TAB, {Key, T}) of
                [{_, P, Value}] when P == Pid -> Value;
                _ -> erlang:error(badarg)
            end;
       true ->
            ets:lookup_element(?TAB, {Key, Pid}, 3)
    end;
get_value(_, _) ->
    erlang:error(badarg).


%%% @spec (Key) -> Pid
%%% @doc Lookup the Pid stored with a key.
%%%
lookup_pid({_T,_,_} = Key) ->
    case where(Key) of
        undefined -> erlang:error(badarg);
        P -> P
    end.


where({T,_,_}=Key) ->
    if T==n orelse T==a ->
            case ets:lookup(?TAB, {Key,T}) of
                [] ->
                    undefined;
                [{_, P, _Value}] ->
                    P
            end;
       true ->
            erlang:error(badarg)
    end.

lookup_pids({T,_,_} = Key) ->
    if T==n orelse T==a ->
            ets:select(?TAB, [{{{Key,T}, '$1', '_'},[],['$1']}]);
       T==c ->
            ets:select(?TAB, [{{{Key,'_'}, '$1', '_'},[],['$1']}]);
       true ->
            erlang:error(badarg)
    end.


update_counter({c,l,_} = Key, Incr) when is_integer(Incr) ->
    gproc_lib:update_counter(Key, Incr, self());
update_counter({c,g,_} = Key, Incr) when is_integer(Incr) ->
    ?CHK_DIST,
    gproc_dist:update_counter(Key, Incr);
update_counter(_, _) ->
    erlang:error(badarg).




send({T,C,_} = Key, Msg) when C==l; C==g ->
    if T == n orelse T == a ->
            case ets:lookup(?TAB, {Key, T}) of
                [{_, Pid, _}] ->
                    Pid ! Msg;
                [] ->
                    erlang:error(badarg)
            end;
       T==p orelse T==c ->
            %% BUG - if the key part contains select wildcards, we may end up
            %% sending multiple messages to the same pid
            Head = {{Key,'$1'},'_'},
            Pids = ets:select(?TAB, [{Head,[],['$1']}]),
            lists:foreach(fun(Pid) ->
                                  Pid ! Msg
                          end, Pids),
            Msg;
       true ->
            erlang:error(badarg)
    end;
send(_, _) ->
    erlang:error(badarg).


first(Scope) ->
    {HeadPat,_} = headpat(Scope, '_', '_', '_'),
    case ets:select(?TAB, [{HeadPat,[],[{element,1,'$_'}]}], 1) of
        {[First], _} ->
            First;
        _ ->
            '$end_of_table'
    end.

last(Scope) ->
    {C, T} = get_c_t(Scope),
    C1 = if C == '_'; C == l -> m;
            C == g -> h
         end,
    Beyond = {{T,C1,[]},[]},
    step(ets:prev(?TAB, Beyond), C, T).

next(Scope, K) ->
    {C,T} = get_c_t(Scope),
    step(ets:next(?TAB,K), C, T).

prev(Scope, K) ->
    {C, T} = get_c_t(Scope),
    step(ets:prev(?TAB, K), C, T).

step(Key, '_', '_') ->
    case Key of
        {{_,_,_},_} -> Key;
        _ -> '$end_of_table'
    end;
step(Key, '_', T) ->
    case Key of
        {{T,_,_},_} -> Key;
        _ -> '$end_of_table'
    end;
step(Key, C, '_') ->
    case Key of
        {{_, C, _}, _} -> Key;
        _ -> '$end_of_table'
    end;
step(Key, C, T) ->
    case Key of
        {{T,C,_},_} -> Key;
        _ -> '$end_of_table'
    end.



info(Pid) when is_pid(Pid) ->
    Items = [?MODULE | [ I || {I,_} <- process_info(self())]],
    [info(Pid,I) || I <- Items].

info(Pid, ?MODULE) ->
    Keys = ets:select(?TAB, [{ {{Pid,'$1'}}, [], ['$1'] }]),
    {?MODULE, lists:zf(
                fun(K) ->
                        try V = get_value(K, Pid),
                            {true, {K,V}}
                        catch
                            error:_ ->
                                false
                        end
                end, Keys)};
info(Pid, I) ->
    process_info(Pid, I).




%%% ==========================================================


handle_cast({monitor_me, Pid}, S) ->
    erlang:monitor(process, Pid),
    {noreply, S}.

handle_call({reg, {_T,l,_} = Key, Val}, {Pid,_}, S) ->
    case try_insert_reg(Key, Val, Pid) of
        true ->
            ensure_monitor(Pid),
            {reply, true, S};
        false ->
            {reply, badarg, S}
    end;
handle_call({unreg, {_,l,_} = Key}, {Pid,_}, S) ->
    case ets:member(?TAB, {Pid,Key}) of
        true ->
            gproc_lib:remove_reg(Key, Pid),
            {reply, true, S};
        false ->
            {reply, badarg, S}
    end;
handle_call({mreg, T, l, L}, {Pid,_}, S) ->
    try gproc_lib:insert_many(T, l, L, Pid) of
        {true,_} -> {reply, true, S};
        false    -> {reply, badarg, S}
    catch
        error:_  -> {reply, badarg, S}
    end;
handle_call({set, {_,l,_} = Key, Value}, {Pid,_}, S) ->
    case gproc_lib:do_set_value(Key, Value, Pid) of
        true ->
            {reply, true, S};
        false ->
            {reply, badarg, S}
    end;
handle_call(_, _, S) ->
    {reply, badarg, S}.

handle_info({'DOWN', _MRef, process, Pid, _}, S) ->
    process_is_down(Pid),
    {noreply, S};
handle_info(_, S) ->
    {noreply, S}.



code_change(_FromVsn, S, _Extra) ->
    {ok, S}.

terminate(_Reason, _S) ->
    ok.




call(Req) ->
    case gen_server:call(?MODULE, Req) of
        badarg -> erlang:error(badarg, Req);
        Reply  -> Reply
    end.

cast(Msg) ->
    gen_server:cast(?MODULE, Msg).




try_insert_reg({T,l,_} = Key, Val, Pid) ->
    case gproc_lib:insert_reg(Key, Val, Pid, l) of
        false ->
            case ets:lookup(?TAB, {Key,T}) of
                [{_, OtherPid, _}] ->
                    case is_process_alive(OtherPid) of
                        true ->
                            false;
                        false ->
                            process_is_down(Pid),
                            true = gproc_lib:insert_reg(Key, Val, Pid, l)
                    end;
                [] ->
                    false
            end;
        true ->
            true
    end.

process_is_down(Pid) ->
    Keys = ets:select(?TAB, [{{{Pid,'$1'}},
                              [{'==',{element,2,'$1'},l}], ['$1']}]),
    ets:select_delete(?TAB, [{{{Pid,{'_',l,'_'}}}, [], [true]}]),
    ets:delete(?TAB, Pid),
    lists:foreach(fun(Key) -> gproc_lib:remove_reg_1(Key, Pid) end, Keys).


create_tabs() ->
    ets:new(?MODULE, [ordered_set, public, named_table]).

init([]) ->
    {ok, #state{}}.




ensure_monitor(Pid) when node(Pid) == node() ->
    case ets:insert_new(?TAB, {Pid}) of
        false -> ok;
        true  -> erlang:monitor(process, Pid)
    end;
ensure_monitor(_) ->
    true.

monitor_me() ->
    case ets:insert_new(?TAB, {self()}) of
        false -> true;
        true  ->
            cast({monitor_me,self()}),
            true
    end.




pattern([{'_', Gs, As}], T) ->
    {HeadPat, Vs} = headpat(T, '$1', '$2', '$3'),
    [{HeadPat, rewrite(Gs,Vs), rewrite(As,Vs)}];
pattern([{{A,B,C},Gs,As}], Scope) ->
    {HeadPat, Vars} = headpat(Scope, A,B,C),
    [{HeadPat, rewrite(Gs,Vars), rewrite(As,Vars)}];
pattern([{Head, Gs, As}], Scope) ->
    case is_var(Head) of
        {true,N} ->
            {A,B,C} = vars(N),
            {HeadPat, Vs} = headpat(Scope, A,B,C),
            %% the headpat function should somehow verify that Head is
            %% consistent with Scope (or should we add a guard?)
            [{HeadPat, rewrite(Gs, Vs), rewrite(As, Vs)}];
        false ->
            erlang:error(badarg)
    end.

headpat({C, T}, V1,V2,V3) when C==global; C==local; C==all ->
    headpat(type(T), ctxt(C), V1,V2,V3);
headpat(T, V1, V2, V3) when is_atom(T) ->
    headpat(type(T), l, V1, V2, V3);
headpat(_, _, _, _) -> erlang:error(badarg).

headpat(T, C, V1,V2,V3) ->
    Rf = fun(Pos) ->
                 {element,Pos,{element,1,{element,1,'$_'}}}
         end,
    K2 = if T==n orelse T==a -> T;
            true -> '_'
         end,
    {Kp,Vars} = case V1 of
                    {Vt,Vc,Vn} ->
                        {T1,Vs1} = subst(T,Vt,fun() -> Rf(1) end,[]),
                        {C1,Vs2} = subst(C,Vc,fun() -> Rf(2) end,Vs1),
                        {{T1,C1,Vn}, Vs2};
                    '_' ->
                        {{T,C,'_'}, []};
                    _ ->
                        case is_var(V1) of
                            true ->
                                {{T,C,'_'}, [{V1, {element,1,
                                                   {element,1,'$_'}}}]};
                            false ->
                                erlang:error(badarg)
                        end
                end,
    {{{Kp,K2},V2,V3}, Vars}.


subst(X, '_', _F, Vs) ->
    {X, Vs};
subst(X, V, F, Vs) ->
    case is_var(V) of
        true ->
            {X, [{V,F()}|Vs]};
        false ->
            {V, Vs}
    end.

ctxt(all)    -> '_';
ctxt(global) -> g;
ctxt(local)  -> l.

type(all)   -> '_';
type(names) -> n;
type(props) -> p;
type(counters) -> c;
type(aggr_counters) -> a.

keypat(Scope) ->
    {C,T} = get_c_t(Scope),
    {{T,C,'_'},'_'}.



get_c_t({C,T}) -> {ctxt(C), type(T)};
get_c_t(T) when is_atom(T) ->
    {l, type(T)}.

is_var('$1') -> true;
is_var('$2') -> true;
is_var('$3') -> true;
is_var('$4') -> true;
is_var('$5') -> true;
is_var('$6') -> true;
is_var('$7') -> true;
is_var('$8') -> true;
is_var('$9') -> true;
is_var(X) when is_atom(X) ->
    case atom_to_list(X) of
        "$" ++ Tl ->
            try N = list_to_integer(Tl),
                {true,N}
            catch
                error:_ ->
                    false
            end;
        _ ->
            false
    end;
is_var(_) -> false.

vars(N) when N > 3 ->
    {'$1','$2','$3'};
vars(_) ->
    {'$4','$5','$6'}.


rewrite(Gs, R) ->
    [rewrite1(G, R) || G <- Gs].

rewrite1('$_', _) ->
    {{ {element,1,{element,1,'$_'}},
       {element,2,'$_'},
       {element,3,'$_'} }};
rewrite1('$$', _) ->
    [ {element,1,{element,1,'$_'}},
      {element,2,'$_'},
      {element,3,'$_'} ];
rewrite1(Guard, R) when is_tuple(Guard) ->
    list_to_tuple([rewrite1(G, R) || G <- tuple_to_list(Guard)]);
rewrite1(Exprs, R) when is_list(Exprs) ->
    [rewrite1(E, R) || E <- Exprs];
rewrite1(V, R) when is_atom(V) ->
    case is_var(V) of
        true ->
            case lists:keysearch(V, 1, R) of
                {value, {_, V1}} ->
                    V1;
                false ->
                    V
            end;
        false ->
            V
    end;
rewrite1(Expr, _) ->
    Expr.


table(Scope) ->
    table(Scope, []).

table(T, Opts) ->
    [Traverse, NObjs] = [proplists:get_value(K,Opts,Def) ||
                            {K,Def} <- [{traverse,select}, {n_objects,100}]],
    TF = case Traverse of
             first_next ->
                 fun() -> qlc_next(T, first(T)) end;
             last_prev -> fun() -> qlc_prev(T, last(T)) end;
             select ->
                 fun(MS) -> qlc_select(select(T,MS,NObjs)) end;
             {select,MS} ->
                 fun() -> qlc_select(select(T,MS,NObjs)) end;
             _ ->
                 erlang:error(badarg, [T,Opts])
         end,
    InfoFun = fun(indices) -> [2];
                 (is_unique_objects) -> is_unique(T);
                 (keypos) -> 1;
                 (is_sorted_key) -> true;
                 (num_of_objects) ->
                      %% this is just a guesstimate.
                      trunc(ets:info(?TAB,size) / 2.5)
              end,
    LookupFun =
        case Traverse of
            {select, _MS} -> undefined;
            _ -> fun(Pos, Ks) -> qlc_lookup(T, Pos, Ks) end
        end,
    qlc:table(TF, [{info_fun, InfoFun},
                   {lookup_fun, LookupFun}] ++ [{K,V} || {K,V} <- Opts,
                                                         K =/= traverse,
                                                         K =/= n_objects]).
qlc_lookup(_Scope, 1, Keys) ->
    lists:flatmap(
      fun(Key) ->
              ets:select(?TAB, [{ {{Key,'_'},'_','_'}, [],
                                  [{{ {element,1,{element,1,'$_'}},
                                      {element,2,'$_'},
                                      {element,3,'$_'} }}] }])
      end, Keys);
qlc_lookup(Scope, 2, Pids) ->
    lists:flatmap(fun(Pid) ->
                          Found =
                              ets:select(?TAB, [{ {{Pid,keypat(Scope)}},
                                                  [], ['$_']}]),
                          lists:flatmap(
                            fun({{_,{T,_,_}=K}}) ->
                                    K2 = if T==n orelse T==a -> T;
                                            true -> Pid
                                         end,
                                    case ets:lookup(?TAB, {K,K2}) of
                                        [{{Key,_},_,Value}] ->
                                            [{Key, Pid, Value}];
                                        [] ->
                                            []
                                    end
                            end, Found)
                  end, Pids).


qlc_next(_, '$end_of_table') -> [];
qlc_next(Scope, K) ->
    case ets:lookup(?TAB, K) of
        [{{Key,_}, Pid, V}] ->
            [{Key,Pid,V} | fun() -> qlc_next(Scope, next(Scope, K)) end];
        [] ->
            qlc_next(Scope, next(Scope, K))
    end.

qlc_prev(_, '$end_of_table') -> [];
qlc_prev(Scope, K) ->
    case ets:lookup(?TAB, K) of
        [{{Key,_},Pid,V}] ->
            [{Key,Pid,V} | fun() -> qlc_prev(Scope, prev(Scope, K)) end];
        [] ->
            qlc_prev(Scope, prev(Scope, K))
    end.

qlc_select('$end_of_table') ->
    [];
qlc_select({Objects, Cont}) ->
    Objects ++ fun() -> qlc_select(ets:select(Cont)) end.


is_unique(names) -> true;
is_unique(aggr_counters) -> true;
is_unique({_, names}) -> true;
is_unique({_, aggr_counters}) -> true;
is_unique(n) -> true;
is_unique(a) -> true;
is_unique({_,n}) -> true;
is_unique({_,a}) -> true;
is_unique(_) -> false.


