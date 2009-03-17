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
-behaviour(gen_leader).

-export([start_link/0, start_link/1,
	 reg/2, unreg/1,
	 mreg/3,
	 set_value/2,
	 get_value/1,
	 update_counter/2,
	 send/2,
	 info/1, info/2,
	 select/1, select/2,
	 first/1,
	 next/2,
	 prev/2,
	 last/1,
	 table/1, table/2]).

-export([start_local/0, go_global/0, go_global/1]).

%%% internal exports
-export([init/1,
	 handle_cast/2,
	 handle_call/3,
	 handle_info/2,
	 handle_leader_call/4,
	 handle_leader_cast/3,
	 handle_DOWN/3,
	 elected/2,
	 surrendered/3,
	 from_leader/3,
	 code_change/4,
	 terminate/2]).

-define(TAB, ?MODULE).
-define(SERVER, ?MODULE).

-record(state, {mode, is_leader}).

start_local() ->
    create_tabs(),
    gen_leader:start(?SERVER, ?MODULE, [], []).

go_global() ->
    erlang:display({"calling go_global (Ns = ~p)~n", [node()|nodes()]}),
    go_global([node()|nodes()]).

go_global(Nodes) when is_list(Nodes) ->
    erlang:display({"calling go_global(~p)~n", [node()|nodes()]}),
    case whereis(?SERVER) of
	undefined ->
	    start_link(Nodes);
	Pid ->
	    link(Pid),
	    ok = call({go_global, Nodes}),
	    {ok, Pid}
    end.

start_link() ->
    start_link([node()|nodes()]).

start_link(Nodes) ->
    create_tabs(),
    gen_leader:start_link(
      ?SERVER, Nodes, [],?MODULE, [], [{debug,[trace]}]).

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
    leader_call({reg, Key, Value, self()});
reg({T,l,_} = Key, Value) when T==n; T==a ->
    %% local names and aggregated counters
    call({reg, Key, Value});
reg({c,l,_} = Key, Value) ->
    %% local counter
    if is_integer(Value) ->
	    local_reg(Key, Value);
       true ->
	    erlang:error(badarg)
    end;
reg({_,l,_} = Key, Value) ->
    %% local property
    local_reg(Key, Value);
reg(_, _) ->
    erlang:error(badarg).

mreg(T, g, KVL) ->
    if is_list(KVL) -> leader_call({mreg, T, g, KVL, self()});
       true -> erlang:error(badarg)
    end;
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
	{_, g, _} -> leader_call({unreg, Key, self()});
	{T, l, _} when T == n;
		       T == a -> call({unreg, Key});
	{_, l, _} ->
	    case ets:member(?TAB, {Key,self()}) of
		true ->
		    remove_reg(Key, self());
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
    case insert_reg(Key, Value, self(), l) of
	false -> erlang:error(badarg);
	true  -> monitor_me()
    end.

local_mreg(_, []) -> true;
local_mreg(T, [_|_] = KVL) ->
    case insert_many(T, l, KVL, self()) of
	false     -> erlang:error(badarg);
	{true,_}  -> monitor_me()
    end.


remove_reg(Key, Pid) ->
    remove_reg_1(Key, Pid),
    ets:delete(?TAB, {Pid,Key}).

remove_reg_1({c,_,_} = Key, Pid) ->
    remove_counter_1(Key, ets:lookup_element(?TAB, {Key,Pid}, 3), Pid);
remove_reg_1({T,_,_} = Key, _Pid) when T==a; T==n ->
    ets:delete(?TAB, {Key,T});
remove_reg_1({_,_,_} = Key, Pid) ->
    ets:delete(?TAB, {Key, Pid}).
    
remove_counter_1({c,C,N} = Key, Val, Pid) ->
    update_aggr_counter(C, N, -Val),
    ets:delete(?TAB, {Key, Pid}).


insert_reg({T,_,Name} = K, Value, Pid, C) when T==a; T==n ->
    %%% We want to store names and aggregated counters with the same
    %%% structure as properties, but at the same time, we must ensure
    %%% that the key is unique. We replace the Pid in the key part with
    %%% an atom. To know which Pid owns the object, we lug the Pid around
    %%% as payload as well. This is a bit redundant, but symmetric.
    %%%
    case ets:insert_new(?TAB, [{{K, T}, Pid, Value}, {{Pid,K}}]) of
	true ->
	    if T == a ->
		    Initial = scan_existing_counters(C, Name),
		    ets:insert(?TAB, {{K,a}, Pid, Initial});
	       T == c ->
		    update_aggr_counter(l, Name, Value);
	       true ->
		    true
	    end,
	    true;
	false ->
	    false
    end;
insert_reg(Key, Value, Pid, _C) ->
    %% Non-unique keys; store Pid in the key part
    K = {Key, Pid},
    Kr = {Pid, Key},
    ets:insert_new(?TAB, [{K, Pid, Value}, {Kr}]).

insert_many(T, C, KVL, Pid) ->
    Objs = mk_reg_objs(T, C, Pid, KVL),
    case ets:insert_new(?TAB, Objs) of
	true ->
	    RevObjs = mk_reg_rev_objs(T, C, Pid, KVL),
	    ets:insert(?TAB, RevObjs),
	    {true, Objs};
	false ->
	    false
    end.

mk_reg_objs(T, C, _, L) when T == n; T == a ->
    lists:map(fun({K,V}) ->
		      {{{T,C,K},T}, V};
		 (_) ->
		      erlang:error(badarg)
	      end, L);
mk_reg_objs(p = T, C, Pid, L) ->
    lists:map(fun({K,V}) ->
		      {{{T,C,K},Pid}, V};
		 (_) ->
		      erlang:error(badarg)
	      end, L).

mk_reg_rev_objs(T, C, Pid, L) ->
    [{Pid,{T,C,K}} || {K,_} <- L].
			  

set_value({T,g,_} = Key, Value) when T==a; T==c ->
    if is_integer(Value) ->
	    leader_call({set, Key, Value});
       true ->
	    erlang:error(badarg)
    end;
set_value({_,g,_} = Key, Value) ->
    leader_call({set, Key, Value, self()});
set_value({a,l,_} = Key, Value) when is_integer(Value) ->
    call({set, Key, Value});
set_value({n,l,_} = Key, Value) ->
    %% we cannot do this locally, since we have to check that the object
    %% exists first - not an atomic update.
    call({set, Key, Value});
set_value({p,l,_} = Key, Value) ->
    %% we _can_ to this locally, since there is no race condition - no
    %% other process can update our properties.
    case do_set_value(Key, Value, self()) of
	true -> true;
	false ->
	    erlang:error(badarg)
    end;
set_value({c,l,_} = Key, Value) when is_integer(Value) ->
    do_set_counter_value(Key, Value, self());
set_value(_, _) ->
    erlang:error(badarg).


do_set_value({T,_,_} = Key, Value, Pid) ->
    K2 = if T==n -> T;
	    true -> Pid
	 end,
    case ets:member(?TAB, {Key, K2}) of
	true ->
	    ets:insert(?TAB, {{Key, K2}, Pid, Value});
	false ->
	    false
    end.

do_set_counter_value({_,C,N} = Key, Value, Pid) ->
    OldVal = ets:lookup_element(?TAB, {Key, Pid}, 3), % may fail with badarg
    update_aggr_counter(C, N, Value - OldVal),
    ets:insert(?TAB, {{Key, Pid}, Pid, Value}).




%%% @spec (Key) -> Value
%%% @doc Read the value stored with a key registered to the current process.
%%%
get_value(Key) ->
    get_value(Key, self()).

get_value({T,_,_} = Key, Pid) when is_pid(Pid) ->
    if T==n; T==a ->
	    case ets:lookup(?TAB, {Key, T}) of
		[{_, P, Value}] when P == Pid -> Value;
		_ -> erlang:error(badarg)
	    end;
       true ->
	    ets:lookup_element(?TAB, {Key, Pid}, 3)
    end;
get_value(_, _) ->
    erlang:error(badarg).


update_counter({c,l,Ctr} = Key, Incr) when is_integer(Incr) ->
    update_aggr_counter(l, Ctr, Incr),
    ets:update_counter(?TAB, Key, {3,Incr});
update_counter({c,g,_} = Key, Incr) when is_integer(Incr) ->
    leader_call({update_counter, Key, Incr, self()});
update_counter(_, _) ->
    erlang:error(badarg).


update_aggr_counter(C, N, Val) ->
    catch ets:update_counter(?TAB, {{a,C,N},a}, {3, Val}).



send({T,C,_} = Key, Msg) when C==l; C==g ->
    if T == n; T == a ->
	    case ets:lookup(?TAB, {Key, T}) of
		[{_, Pid, _}] ->
		    Pid ! Msg;
		[] ->
		    erlang:error(badarg)
	    end;
       T==p; T==c ->
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
    {ok, S}.

handle_call({go_global, Nodes}, _, S) ->
    erlang:display({"got go_global (~p)~n", [Nodes]}),
    case S#state.mode of
	local ->
	    {activate, Nodes, [], ok, S#state{mode = global}};
	global ->
	    {reply, badarg, S}
    end;
handle_call({reg, {_,l,_} = Key, Val}, {Pid,_}, S) ->
    case insert_reg(Key, Val, Pid, l) of
	false ->
	    {reply, badarg, S};
	true ->
	    ensure_monitor(Pid),
	    {reply, true, S}
    end;
handle_call({unreg, {_,l,_} = Key}, {Pid,_}, S) ->
    case ets:member(?TAB, {Pid,Key}) of
	true ->
	    remove_reg(Key, Pid),
	    {reply, true, S};
	false ->
	    {reply, badarg, S}
    end;
handle_call({mreg, T, l, L}, {Pid,_}, S) ->
    try	insert_many(T, l, L, Pid) of
	{true,_} -> {reply, true, S};
	false    -> {reply, badarg, S}
    catch
	error:_  -> {reply, badarg, S}
    end;
handle_call({set, {_,l,_} = Key, Value}, {Pid,_}, S) ->
    case do_set_value(Key, Value, Pid) of
	true ->
	    {reply, true, S};
	false ->
	    {reply, badarg, S}
    end;
handle_call(_, _, S) ->
    {reply, badarg, S}.

handle_info({'DOWN', _MRef, process, Pid, _}, S) ->
    Keys = ets:select(?TAB, [{{{Pid,'$1'}}, [], ['$1']}]),
    case lists:keymember(g, 2, Keys) of
	true ->
	    leader_cast({pid_is_DOWN, Pid});
	false ->
	    ok
    end,
    ets:select_delete(?TAB, [{{{Pid,'_'}}, [], [true]}]),
    ets:delete(?TAB, Pid),
    lists:foreach(fun(Key) -> remove_reg_1(Key, Pid) end, Keys),
    {ok, S};
handle_info(_, S) ->
    {ok, S}.


elected(S, _E) ->
    Globs = ets:select(?TAB, [{{{{'_',g,'_'},'_'},'_','_'},[],['$_']}]),
    {ok, {globals, Globs}, S#state{is_leader = true}}.

surrendered(S, {globals, Globs}, _E) ->
    %% globals from this node should be more correct in our table than
    %% in the leader's
    surrendered_1(Globs),
    {ok, S#state{is_leader = false}}.


handle_DOWN(Node, S, _E) ->
    Head = {{{'_',g,'_'},'_'},'$1','_'},
    Gs = [{'==', {node,'$1'},Node}],
    Globs = ets:select(?TAB, [{Head, Gs, [{element,1,'$_'}]}]),
    ets:select_delete(?TAB, [{Head, Gs, [true]}]),
    {ok, [{delete, Globs}], S}.

handle_leader_call(_, _, #state{mode = local} = S, _) ->
    {reply, badarg, S};
handle_leader_call({reg, {C,g,Name} = K, Value, Pid}, _From, S, _E) ->
    case insert_reg(K, Value, Pid, g) of
	false ->
	    {reply, badarg, S};
	true ->
	    ensure_monitor(Pid),
	    Vals =
		if C == a ->
			ets:lookup(?TAB, {K,a});
		   C == c ->
			case ets:lookup(?TAB, {{a,g,Name},a}) of
			    [] ->
				ets:lookup(?TAB, {K,Pid});
			    [AC] ->
				[AC | ets:lookup(?TAB, {K,Pid})]
			end;
		   C == n ->
			[{{K,n},Pid,Value}];
		   true ->
			[{{K,Pid},Pid,Value}]
		end,
	    {reply, true, [{insert, Vals}], S}
    end;
handle_leader_call({unreg, {T,g,Name} = K, Pid}, _From, S, _E) ->
    Key = if T == n; T == a -> {K,T};
	     true -> {K, Pid}
	  end,
    case ets:member(?TAB, Key) of
	true ->
	    remove_reg(K, Pid),
	    if T == c ->
		    case ets:lookup(?TAB, {{a,g,Name},a}) of
			[Aggr] ->
			    %% updated by remove_reg/2
			    {reply, true, [{delete,[{Key,Pid}]},
					   {insert, [Aggr]}], S};
			[] ->
			    {reply, true, [{delete, [{Key, Pid}]}], S}
		    end;
	       true ->
		    {reply, true, [{delete, [{Key,Pid}]}], S}
	    end;
	false ->
	    {reply, badarg, S}
    end;
handle_leader_call({mreg, T, g, L, Pid}, _From, S, _E) ->
    if T==p; T==n ->
	    try insert_many(T, g, Pid, L) of
		{true,Objs} -> {reply, true, [{insert,Objs}], S};
		false       -> {reply, badarg, S}
	    catch
		error:_     -> {reply, badarg, S}
	    end;
       true -> {reply, badarg, S}
    end;
handle_leader_call({set,{T,g,N} =K,V,Pid}, _From, S, _E) ->
    if T == a ->
	    if is_integer(V) ->
		    case do_set_value(K, V, Pid) of
			true  -> {reply, true, [{insert,[{{K,T},Pid,V}]}], S};
			false -> {reply, badarg, S}
		    end
	    end;
       T == c ->
	    try do_set_counter_value(K, V, Pid),
		AKey = {{a,g,N},a},
		Aggr = ets:lookup(?TAB, AKey),  % may be []
		{reply, true, [{insert, [{{K,Pid},Pid,V} | Aggr]}], S}
	    catch
		error:_ ->
		    {reply, badarg, S}
	    end;
       true ->
	    case do_set_value(K, V, Pid) of
		true ->
		    Obj = if T==n -> {{K, T}, Pid, V};
			     true -> {{K, Pid}, Pid, V}
			  end,
		    {reply, true, [{insert,[Obj]}], S};
		false ->
		    {reply, badarg, S}
	    end
    end;
handle_leader_call(_, _, S, _E) ->
    {reply, badarg, S}.

handle_leader_cast(_, #state{mode = local} = S, _E) ->
    {ok, S};
handle_leader_cast({add_globals, Missing}, S, _E) ->
    %% This is an audit message: a peer (non-leader) had info about granted
    %% global resources that we didn't know of when we became leader.
    %% This could happen due to a race condition when the old leader died.
    ets:insert(?TAB, Missing),
    {ok, [{insert, Missing}], S};
handle_leader_cast({remove_globals, Globals}, S, _E) ->
    delete_globals(Globals),
    {ok, S};
handle_leader_cast({pid_is_DOWN, Pid}, S, _E) ->
    Keys = ets:select(?TAB, [{{{Pid,'$1'}},[],['$1']}]),
    Globals = if node(Pid) =/= node() ->
		      Keys;
		 true ->
		      [K || K <- Keys, element(2,K) == g]
	      end,
    ets:select_delete(?TAB, [{{{Pid,'_'}},[],[true]}]),
    ets:delete(?TAB, Pid),
    Modified = 
	lists:foldl(
	  fun({T,_,_}=K,A) when T==a;T==n -> ets:delete(?TAB, {K,T}), A;
	     ({c,_,_}=K,A) -> cleanup_counter(K, Pid, A);
	     (K,A) -> ets:delete(?TAB, {K,Pid}), A
	  end, [], Keys),
    case [{Op,Objs} || {Op,Objs} <- [{insert,Modified},
				     {remove,Globals}], Objs =/= []] of
	[] ->
	    {ok, S};
	Broadcast ->
	    {ok, Broadcast, S}
    end.

code_change(_FromVsn, S, _Extra, _E) ->
    {ok, S}.

terminate(_Reason, _S) ->
    ok.




cleanup_counter({c,g,N}=K, Pid, Acc) ->
    remove_reg(K,Pid),
    case ets:lookup(?TAB, {{a,g,N},a}) of
	[Aggr] ->
	    [Aggr|Acc];
	[] ->
	    Acc
    end;
cleanup_counter(K, Pid, Acc) ->
    remove_reg(K,Pid),
    Acc.

from_leader(Ops, S, _E) ->
    lists:foreach(
      fun({delete, Globals}) ->
	      delete_globals(Globals);
	 ({insert, Globals}) ->
	      ets:insert(?TAB, Globals),
	      lists:foreach(
		fun({{{_,g,_}=Key,_}, P, _}) ->
			ets:insert(?TAB, {{P,Key}}),
			ensure_monitor(P)
		end, Globals)
      end, Ops),
    {ok, S}.

delete_globals(Globals) ->
    lists:foreach(
      fun({{Key,_}=K, Pid}) ->
	      ets:delete(?TAB, K),
	      ets:delete(?TAB, {{Pid, Key}})
      end, Globals).
    


call(Req) ->
    case gen_leader:call(?MODULE, Req) of
	badarg -> erlang:error(badarg, Req);
	Reply  -> Reply
    end.

cast(Msg) ->
    gen_leader:cast(?MODULE, Msg).

leader_call(Req) ->
    case gen_leader:leader_call(?MODULE, Req) of
	badarg -> erlang:error(badarg, Req);
	Reply  -> Reply
    end.

leader_cast(Msg) ->
    gen_leader:leader_cast(?MODULE, Msg).
	     


create_tabs() ->
    ets:new(?MODULE, [ordered_set, public, named_table]).

init({local_only,[]}) ->
    {ok, #state{mode = local}};
init([]) ->
    {ok, #state{mode = global}}.


surrendered_1(Globs) ->
    My_local_globs =
	ets:select(?TAB, [{{{{'_',g,'_'},'_'},'$1', '_'},
			   [{'==', {node,'$1'}, node()}],
			   ['$_']}]),
    %% remove all remote globals - we don't have monitors on them.
    ets:select_delete(?TAB, [{{{{'_',g,'_'},'_'}, '$1', '_'},
			      [{'=/=', {node,'$1'}, node()}],
			      [true]}]),
    %% insert new non-local globals, collect the leader's version of
    %% what my globals are
    Ldr_local_globs =
	lists:foldl(
	  fun({{Key,_}=K, Pid, V}, Acc) when node(Pid) =/= node() ->
		  ets:insert(?TAB, [{K, Pid, V}, {{Pid,Key}}]),
		  Acc;
	     ({_, Pid, _} = Obj, Acc) when node(Pid) == node() ->
		  [Obj|Acc]
	  end, [], Globs),
    case [{K,P,V} || {K,P,V} <- My_local_globs,
		   not(lists:keymember(K, 1, Ldr_local_globs))] of
	[] ->
	    %% phew! We have the same picture
	    ok;
	[_|_] = Missing ->
	    %% This is very unlikely, I think
	    leader_cast({add_globals, Missing})
    end,
    case [{K,P} || {K,P,_} <- Ldr_local_globs,
		   not(lists:keymember(K, 1, My_local_globs))] of
	[] ->
	    ok;
	[_|_] = Remove ->
	    leader_cast({remove_globals, Remove})
    end.


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


scan_existing_counters(Ctxt, Name) ->
    Head = {{{c,Ctxt,Name},'_'},'_','$1'},
    Cs = ets:select(?TAB, [{Head, [], ['$1']}]),
    lists:sum(Cs).



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
    K2 = if T==n; T==a -> T;
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
				    K2 = if T==n; T==a -> T;
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
     
