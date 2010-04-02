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
-module(gproc_dist).
-behaviour(gen_leader).

-export([start_link/0, start_link/1,
	 reg/2, unreg/1,
	 mreg/2,
	 set_value/2,
	 update_counter/2]).

%%% internal exports
-export([init/1,
	 handle_cast/2,
	 handle_call/3,
	 handle_info/2,
	 handle_leader_call/4,
	 handle_leader_cast/3,
	 handle_DOWN/3,
         elected/2,  % original version
	 elected/3,  
	 surrendered/3,
	 from_leader/3,
	 code_change/4,
	 terminate/2]).

-include("gproc.hrl").

-define(SERVER, ?MODULE).

-record(state, {
          always_broadcast = false,
          is_leader}).


start_link() ->
    start_link({[node()|nodes()], []}).

start_link(Nodes) when is_list(Nodes) ->
    start_link({Nodes, []});
start_link({Nodes, Opts}) ->
    gen_leader:start_link(
      ?SERVER, Nodes, Opts, ?MODULE, [], []).
    
%%       ?SERVER, Nodes, [],?MODULE, [], [{debug,[trace]}]).

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
reg(_, _) ->
    erlang:error(badarg).

mreg(T, KVL) ->
    if is_list(KVL) -> leader_call({mreg, T, g, KVL, self()});
       true -> erlang:error(badarg)
    end.


unreg({_,g,_} = Key) ->
    leader_call({unreg, Key, self()});
unreg(_) ->
    erlang:error(badarg).


set_value({T,g,_} = Key, Value) when T==a; T==c ->
    if is_integer(Value) ->
	    leader_call({set, Key, Value});
       true ->
	    erlang:error(badarg)
    end;
set_value({_,g,_} = Key, Value) ->
    leader_call({set, Key, Value, self()});
set_value(_, _) ->
    erlang:error(badarg).




update_counter({c,g,_} = Key, Incr) when is_integer(Incr) ->
    leader_call({update_counter, Key, Incr, self()});
update_counter(_, _) ->
    erlang:error(badarg).



%%% ==========================================================


handle_cast(_Msg, S) ->
    {stop, unknown_cast, S}.

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
    lists:foreach(fun(Key) -> gproc_lib:remove_reg_1(Key, Pid) end, Keys),
    {ok, S};
handle_info(_, S) ->
    {ok, S}.


elected(S, _E) ->
    {ok, {globals,globs()}, S#state{is_leader = true}}.

elected(S, _E, undefined) ->
    %% I have become leader; full synch
    {ok, {globals, globs()}, S#state{is_leader = true}};
elected(S, _E, _Node) ->
    Synch = {globals, globs()},
    if not S#state.always_broadcast ->
            %% Another node recognized us as the leader.
            %% Don't broadcast all data to everyone else
            {reply, Synch, S};
       true ->
            %% Main reason for doing this is if we are using a gen_leader
            %% that doesn't support the 'reply' return value
            {ok, Synch, S}
    end.

globs() ->
    ets:select(?TAB, [{{{{'_',g,'_'},'_'},'_','_'},[],['$_']}]).

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

handle_leader_call({reg, {C,g,Name} = K, Value, Pid}, _From, S, _E) ->
    case gproc_lib:insert_reg(K, Value, Pid, g) of
	false ->
	    {reply, badarg, S};
	true ->
	    gproc_lib:ensure_monitor(Pid),
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
	    gproc_lib:remove_reg(K, Pid),
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
	    try gproc_lib:insert_many(T, g, Pid, L) of
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
		    case gproc_lib:do_set_value(K, V, Pid) of
			true  -> {reply, true, [{insert,[{{K,T},Pid,V}]}], S};
			false -> {reply, badarg, S}
		    end
	    end;
       T == c ->
	    try gproc_lib:do_set_counter_value(K, V, Pid),
		AKey = {{a,g,N},a},
		Aggr = ets:lookup(?TAB, AKey),  % may be []
		{reply, true, [{insert, [{{K,Pid},Pid,V} | Aggr]}], S}
	    catch
		error:_ ->
		    {reply, badarg, S}
	    end;
       true ->
	    case gproc_lib:do_set_value(K, V, Pid) of
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
    Globals = ets:select(?TAB, [{{{Pid,'$1'}},
				 [{'==',{element,2,'$1'},g}],['$1']}]),
    ets:select_delete(?TAB, [{{{Pid,{'_',g,'_'}}},[],[true]}]),
    ets:delete(?TAB, Pid),
    Modified = 
	lists:foldl(
	  fun({T,_,_}=K,A) when T==a;T==n -> ets:delete(?TAB, {K,T}), A;
	     ({c,_,_}=K,A) -> gproc_lib:cleanup_counter(K, Pid, A);
	     (K,A) -> ets:delete(?TAB, {K,Pid}), A
	  end, [], Globals),
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




from_leader(Ops, S, _E) ->
    lists:foreach(
      fun({delete, Globals}) ->
	      delete_globals(Globals);
	 ({insert, Globals}) ->
	      ets:insert(?TAB, Globals),
	      lists:foreach(
		fun({{{_,g,_}=Key,_}, P, _}) ->
			ets:insert(?TAB, {{P,Key}}),
			gproc_lib:ensure_monitor(P)
		end, Globals)
      end, Ops),
    {ok, S}.

delete_globals(Globals) ->
    lists:foreach(
      fun({{Key,_}=K, Pid}) ->
	      ets:delete(?TAB, K),
	      ets:delete(?TAB, {{Pid, Key}})
      end, Globals).
    

leader_call(Req) ->
    case gen_leader:leader_call(?MODULE, Req) of
	badarg -> erlang:error(badarg, Req);
	Reply  -> Reply
    end.

leader_cast(Msg) ->
    gen_leader:leader_cast(?MODULE, Msg).
	     


init(Opts) ->
    S0 = #state{},
    AlwaysBcast = proplists:get_value(always_broadcast, Opts,
                                      S0#state.always_broadcast),
    {ok, #state{always_broadcast = AlwaysBcast}}.


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

