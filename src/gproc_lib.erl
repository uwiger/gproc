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
-module(gproc_lib).
-compile(export_all).

-include("gproc.hrl").

insert_reg({T,_,Name} = K, Value, Pid, C) when T==a; T==c; T==n ->
    %%% We want to store names and aggregated counters with the same
    %%% structure as properties, but at the same time, we must ensure
    %%% that the key is unique. We replace the Pid in the key part
    %%% with an atom. To know which Pid owns the object, we lug the
    %%% Pid around as payload as well. This is a bit redundant, but
    %%% symmetric.
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



ensure_monitor(Pid) when node(Pid) == node() ->
    case ets:insert_new(?TAB, {Pid}) of
        false -> ok;
        true  -> erlang:monitor(process, Pid)
    end;
ensure_monitor(_) ->
    true.

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


update_counter({c,l,Ctr} = Key, Incr) ->
    update_aggr_counter(l, Ctr, Incr),
    ets:update_counter(?TAB, Key, {3,Incr}).


update_aggr_counter(C, N, Val) ->
    catch ets:update_counter(?TAB, {{a,C,N},a}, {3, Val}).




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

scan_existing_counters(Ctxt, Name) ->
    Head = {{{c,Ctxt,Name},'_'},'_','$1'},
    Cs = ets:select(?TAB, [{Head, [], ['$1']}]),
    lists:sum(Cs).

