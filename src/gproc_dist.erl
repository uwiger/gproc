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
%% @doc Extended process registry
%% <p>This module implements an extended process registry</p>
%% <p>For a detailed description, see gproc/doc/erlang07-wiger.pdf.</p>
%% @end
-module(gproc_dist).
-behaviour(gen_leader).

-export([start_link/0, start_link/1,
         reg/1, reg/2, unreg/1,
         mreg/2,
         munreg/2,
         set_value/2,
         give_away/2,
         update_counter/2]).

-export([leader_call/1,
         leader_cast/1,
         sync/0,
         get_leader/0]).

%%% internal exports
-export([init/1,
         handle_cast/3,
         handle_call/4,
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
          is_leader,
          sync_requests = []}).

%% ==========================================================
%% Start functions

start_link() ->
    start_link({[node()|nodes()], []}).

start_link(all) ->
    start_link({[node()|nodes()], [{bcast_type, all}]});
start_link(Nodes) when is_list(Nodes) ->
    start_link({Nodes, []});
start_link({Nodes, Opts}) ->
    SpawnOpts = gproc_lib:valid_opts(server_options, []),
    gen_leader:start_link(
      ?SERVER, Nodes, Opts, ?MODULE, [], [{spawn_opt, SpawnOpts}]).

%% ==========================================================
%% API

%% {@see gproc:reg/1}
%%
reg(Key) ->
    reg(Key, gproc:default(Key)).


%%% @spec({Class,Scope, Key}, Value) -> true
%%% @doc
%%%    Class = n  - unique name
%%%          | p  - non-unique property
%%%          | c  - counter
%%%          | a  - aggregated counter
%%%    Scope = l | g (global or local)
%%% @end
reg({_,g,_} = Key, Value) ->
    %% anything global
    leader_call({reg, Key, Value, self()});
reg(_, _) ->
    erlang:error(badarg).

mreg(T, KVL) ->
    if is_list(KVL) -> leader_call({mreg, T, g, KVL, self()});
       true -> erlang:error(badarg)
    end.

munreg(T, Keys) ->
    if is_list(Keys) -> leader_call({munreg, T, g, Keys, self()});
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

give_away({_,g,_} = Key, To) ->
    leader_call({give_away, Key, To, self()}).


update_counter({c,g,_} = Key, Incr) when is_integer(Incr) ->
    leader_call({update_counter, Key, Incr, self()});
update_counter(_, _) ->
    erlang:error(badarg).

%% @spec sync() -> true
%% @doc Synchronize with the gproc leader
%%
%% This function can be used to ensure that data has been replicated from the
%% leader to the current node. It does so by asking the leader to ping all
%% live participating nodes. The call will return `true' when all these nodes
%% have either responded or died. In the special case where the leader dies
%% during an ongoing sync, the call will fail with a timeout exception.
%% (Actually, it should be a `leader_died' exception; more study needed to find
%% out why gen_leader times out in this situation, rather than reporting that
%% the leader died.)
%% @end
%%
sync() ->
    leader_call(sync).

%% @spec get_leader() -> node()
%% @doc Returns the node of the current gproc leader.
%% @end
get_leader() ->
    gen_leader:call(?MODULE, get_leader).

%% ==========================================================
%% Server-side

handle_cast(_Msg, S, _) ->
    {stop, unknown_cast, S}.

handle_call(get_leader, _, S, E) ->
    {reply, gen_leader:leader_node(E), S};
handle_call(_, _, S, _) ->
    {reply, badarg, S}.

handle_info({'DOWN', _MRef, process, Pid, _}, S) ->
    leader_cast({pid_is_DOWN, Pid}),
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
    S1 = check_sync_requests(Node, S),
    Head = {{{'_',g,'_'},'_'},'$1','_'},
    Gs = [{'==', {node,'$1'},Node}],
    Globs = ets:select(?TAB, [{Head, Gs, [{{{element,1,{element,1,'$_'}},
                                            {element,2,'$_'}}}]}]),
    case process_globals(Globs) of
        [] ->
            {ok, S1};
        Broadcast ->
            {ok, Broadcast, S1}
    end.

check_sync_requests(Node, #state{sync_requests = SReqs} = S) ->
    SReqs1 = lists:flatmap(
               fun({From, Ns}) ->
                       case Ns -- [Node] of
                           [] ->
                               gen_leader:reply(From, {leader, reply, true}),
                               [];
                           Ns1 ->
                               [{From, Ns1}]
                       end
               end, SReqs),
    S#state{sync_requests = SReqs1}.

handle_leader_call(sync, From, #state{sync_requests = SReqs} = S, E) ->
    case gen_leader:alive(E) -- [node()] of
        [] ->
            {reply, true, S};
        Alive ->
            gen_leader:broadcast({from_leader, {sync, From}}, Alive, E),
            {noreply, S#state{sync_requests = [{From, Alive}|SReqs]}}
    end;
handle_leader_call({reg, {C,g,Name} = K, Value, Pid}, _From, S, _E) ->
    case gproc_lib:insert_reg(K, Value, Pid, g) of
        false ->
            {reply, badarg, S};
        true ->
            _ = gproc_lib:ensure_monitor(Pid,g),
            Vals =
                if C == a ->
                        ets:lookup(?TAB, {K,a});
                   C == c ->
                        [{{K,Pid},Pid,Value} | ets:lookup(?TAB,{{a,g,Name},a})];
                   C == n ->
                        [{{K,n},Pid,Value}];
                   true ->
                        [{{K,Pid},Pid,Value}]
                end,
            {reply, true, [{insert, Vals}], S}
    end;
handle_leader_call({update_counter, {c,g,_Ctr} = Key, Incr, Pid}, _From, S, _E)
  when is_integer(Incr) ->
    try New = ets:update_counter(?TAB, {Key, Pid}, {3,Incr}),
        Vals = [{{Key,Pid},Pid,New} | update_aggr_counter(Key, Incr)],
        {reply, New, [{insert, Vals}], S}
    catch
        error:_ ->
            {reply, badarg, S}
    end;
handle_leader_call({unreg, {T,g,Name} = K, Pid}, _From, S, _E) ->
    Key = if T == n; T == a -> {K,T};
             true -> {K, Pid}
          end,
    case ets:member(?TAB, Key) of
        true ->
            _ = gproc_lib:remove_reg(K, Pid),
            if T == c ->
                    case ets:lookup(?TAB, {{a,g,Name},a}) of
                        [Aggr] ->
                            %% updated by remove_reg/2
                            {reply, true, [{delete,[Key, {Pid,K}]},
                                           {insert, [Aggr]}], S};
                        [] ->
                            {reply, true, [{delete, [Key, {Pid,K}]}], S}
                    end;
               true ->
                    {reply, true, [{delete, [Key]}], S}
            end;
        false ->
            {reply, badarg, S}
    end;
handle_leader_call({give_away, {T,g,_} = K, To, Pid}, _From, S, _E)
  when T == a; T == n ->
    Key = {K, T},
    case ets:lookup(?TAB, Key) of
        [{_, Pid, Value}] ->
            case pid_to_give_away_to(To) of
                Pid ->
                    {reply, Pid, S};
                ToPid when is_pid(ToPid) ->
                    ets:insert(?TAB, [{Key, ToPid, Value},
                                      {{ToPid,K}, r}]),
                    _ = gproc_lib:ensure_monitor(ToPid, g),
                    {reply, ToPid, [{delete, [Key, {Pid,K}]},
                                   {insert, [{Key, ToPid, Value}]}], S};
                undefined ->
                    ets:delete(?TAB, Key),
                    ets:delete(?TAB, {Pid, K}),
                    {reply, undefined, [{delete, [Key, {Pid,K}]}], S}
            end;
        _ ->
            {reply, badarg, S}
    end;
handle_leader_call({mreg, T, g, L, Pid}, _From, S, _E) ->
    if T==p; T==n ->
            try gproc_lib:insert_many(T, g, L, Pid) of
                {true,Objs} -> {reply, true, [{insert,Objs}], S};
                false       -> {reply, badarg, S}
            catch
                error:_     -> {reply, badarg, S}
            end;
       true -> {reply, badarg, S}
    end;
handle_leader_call({munreg, T, g, L, Pid}, _From, S, _E) ->
    try gproc_lib:remove_many(T, g, L, Pid) of
        [] ->
            {reply, true, S};
        Objs ->
            {reply, true, [{delete, Objs}], S}
    catch
        error:_ -> {reply, badarg, S}
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
handle_leader_call({await, Key, Pid}, {_,Ref} = From, S, _E) ->
    %% The pid in _From is of the gen_leader instance that forwarded the
    %% call - not of the client. This is why the Pid is explicitly passed.
    %% case gproc_lib:await(Key, {Pid,Ref}) of
    case gproc_lib:await(Key, Pid, From) of
        {reply, {Ref, {K, P, V}}} ->
            {reply, {Ref, {K, P, V}}, S};
        {reply, Reply, Insert} ->
            {reply, Reply, [{insert, Insert}], S}
    end;
handle_leader_call(_, _, S, _E) ->
    {reply, badarg, S}.

handle_leader_cast({sync_reply, Node, Ref}, S, _E) ->
    #state{sync_requests = SReqs} = S,
    case lists:keyfind(Ref, 1, SReqs) of
        false ->
            %% This should never happen, except perhaps if the leader who
            %% received the sync request died, and the new leader gets the
            %% sync reply. In that case, we trust that the client has been
	    %% notified anyway, and ignore the message.
            {ok, S};
        {_, Ns} ->
            case lists:delete(Node, Ns) of
                [] ->
                    gen_leader:reply(Ref, {leader, reply, true}),
                    {ok, S#state{sync_requests = lists:keydelete(Ref,1,SReqs)}};
                Ns1 ->
                    SReqs1 = lists:keyreplace(Ref, 1, SReqs, {Ref, Ns1}),
                    {ok, S#state{sync_requests = SReqs1}}
            end
    end;
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
    Globals = ets:select(?TAB, [{{{Pid,'$1'},r},
                                 [{'==',{element,2,'$1'},g}],[{{'$1',Pid}}]}]),
    ets:delete(?TAB, {Pid,g}),
    case process_globals(Globals) of
        [] ->
            {ok, S};
        Broadcast ->
            {ok, Broadcast, S}
    end.

process_globals(Globals) ->
    Modified =
        lists:foldl(
          fun({{T,_,_} = Key, Pid}, A) ->
                  A1 = case T of
                           c ->
                               Incr = ets:lookup_element(?TAB, {Key,Pid}, 3),
                               update_aggr_counter(Key, -Incr) ++ A;
                           _ ->
                               A
                       end,
                  K = ets_key(Key, Pid),
                  ets:delete(?TAB, K),
                  ets:delete(?TAB, {Pid,Key}),
                  A1
          end, [], Globals),
    [{Op,Objs} || {Op,Objs} <- [{insert,Modified},
                                {delete,Globals}], Objs =/= []].

code_change(_FromVsn, S, _Extra, _E) ->
    {ok, S}.

terminate(_Reason, _S) ->
    ok.

from_leader({sync, Ref}, S, _E) ->
    gen_leader:leader_cast(?MODULE, {sync_reply, node(), Ref}),
    {ok, S};
from_leader(Ops, S, _E) ->
    lists:foreach(
      fun({delete, Globals}) ->
              delete_globals(Globals);
         ({insert, Globals}) ->
              ets:insert(?TAB, Globals),
              lists:foreach(
                fun({{{_,g,_}=Key,_}, P, _}) ->
                        ets:insert(?TAB, {{P,Key},r}),
                        gproc_lib:ensure_monitor(P,g);
                   ({{P,_K},r}) ->
                        gproc_lib:ensure_monitor(P,g);
                   (_) ->
                        skip
                end, Globals)
      end, Ops),
    {ok, S}.

delete_globals(Globals) ->
    lists:foreach(
      fun({{_,g,_},T} = K) when is_atom(T) ->
              ets:delete(?TAB, K);
         ({Key, Pid}) when is_pid(Pid) ->
              K = ets_key(Key,Pid),
              ets:delete(?TAB, K),
              ets:delete(?TAB, {Pid, Key});
         ({Pid, K}) when is_pid(Pid) ->
              ets:delete(?TAB, {Pid, K})
      end, Globals).

ets_key({T,_,_} = K, _) when T==n; T==a ->
    {K, T};
ets_key(K, Pid) ->
    {K, Pid}.

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

update_aggr_counter({c,g,Ctr}, Incr) ->
    Key = {{a,g,Ctr},a},
    case ets:lookup(?TAB, Key) of
        [] ->
            [];
        [{K, Pid, Prev}] ->
            New = {K, Pid, Prev+Incr},
            ets:insert(?TAB, New),
            [New]
    end.

pid_to_give_away_to(P) when is_pid(P) ->
    P;
pid_to_give_away_to({T,g,_} = Key) when T==n; T==a ->
    case ets:lookup(?TAB, {Key, T}) of
        [{_, Pid, _}] ->
            Pid;
        _ ->
            undefined
    end.
