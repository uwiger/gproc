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

-export([await/3,
         do_set_counter_value/3,
         do_set_value/3,
         ensure_monitor/2,
         insert_many/4,
         insert_reg/4,
         remove_many/4,
         remove_reg/2,
         update_aggr_counter/3,
         update_counter/3,
	 valid_opts/2]).

-include("gproc.hrl").

%% We want to store names and aggregated counters with the same
%% structure as properties, but at the same time, we must ensure
%% that the key is unique. We replace the Pid in the key part
%% with an atom. To know which Pid owns the object, we lug the
%% Pid around as payload as well. This is a bit redundant, but
%% symmetric.
%%
-spec insert_reg(key(), any(), pid(), scope()) -> boolean().

insert_reg({T,_,Name} = K, Value, Pid, Scope) when T==a; T==n ->
    MaybeScan = fun() ->
                        if T==a ->
                                Initial = scan_existing_counters(Scope, Name),
                                ets:insert(?TAB, {{K,a}, Pid, Initial});
                           true ->
                                true
                        end
                end,
    Info = [{{K, T}, Pid, Value}, {{Pid,K},r}],
    case ets:insert_new(?TAB, Info) of
        true ->
            MaybeScan();
        false ->
            if T==n ->
                    maybe_waiters(K, Pid, Value, T, Info);
               true ->
                    false
            end
    end;
insert_reg({c,Scope,Ctr} = Key, Value, Pid, Scope) when Scope==l; Scope==g ->
    %% Non-unique keys; store Pid in the key part
    K = {Key, Pid},
    Kr = {Pid, Key},
    Res = ets:insert_new(?TAB, [{K, Pid, Value}, {Kr,r}]),
    case Res of
        true ->
            update_aggr_counter(Scope, Ctr, Value);
        false ->
            ignore
    end,
    Res;
insert_reg({_,_,_} = Key, Value, Pid, _Scope) when is_pid(Pid) ->
    %% Non-unique keys; store Pid in the key part
    K = {Key, Pid},
    Kr = {Pid, Key},
    ets:insert_new(?TAB, [{K, Pid, Value}, {Kr,r}]).



-spec insert_many(type(), scope(), [{key(),any()}], pid()) ->
          {true,list()} | false.

insert_many(T, Scope, KVL, Pid) ->
    Objs = mk_reg_objs(T, Scope, Pid, KVL),
    case ets:insert_new(?TAB, Objs) of
        true ->
            RevObjs = mk_reg_rev_objs(T, Scope, Pid, KVL),
            ets:insert(?TAB, RevObjs),
            _ = gproc_lib:ensure_monitor(Pid, Scope),
            {true, Objs};
        false ->
            Existing = [{Obj, ets:lookup(?TAB, K)} || {K,_,_} = Obj <- Objs],
            case lists:any(fun({_, [{_, _, _}]}) ->
                                   true;
                              (_) ->
                                   %% (not found), or waiters registered
                                   false
                           end, Existing) of
                true ->
                    %% conflict; return 'false', indicating failure
                    false;
                false ->
                    %% possibly waiters, but they are handled in next step
                    insert_objects(Existing),
                    _ = gproc_lib:ensure_monitor(Pid, Scope),
                    {true, Objs}
            end
    end.

-spec insert_objects([{key(), pid(), any()}]) -> ok.

insert_objects(Objs) ->
    lists:foreach(
      fun({{{Id,_} = _K, Pid, V} = Obj, Existing}) ->
              ets:insert(?TAB, [Obj, {{Pid, Id}, r}]),
              case Existing of
                  [] -> ok;
                  [{_, Waiters}] ->
                      notify_waiters(Waiters, Id, Pid, V)
              end
      end, Objs).


await({T,C,_} = Key, WPid, {_Pid, Ref} = From) ->
    Rev = {{WPid,Key}, r},
    case ets:lookup(?TAB, {Key,T}) of
        [{_, P, Value}] ->
            %% for symmetry, we always reply with Ref and then send a message
            if C == g ->
                    %% in the global case, we bundle the reply, since otherwise
                    %% the messages can pass each other
                    {reply, {Ref, {Key, P, Value}}};
               true ->
                    gen_server:reply(From, Ref),
                    WPid ! {gproc, Ref, registered, {Key, P, Value}},
                    noreply
            end;
        [{K, Waiters}] ->
            NewWaiters = [{WPid,Ref} | Waiters],
            W = {K, NewWaiters},
            ets:insert(?TAB, [W, Rev]),
            _ = gproc_lib:ensure_monitor(WPid,C),
            {reply, Ref, [W,Rev]};
        [] ->
            W = {{Key,T}, [{WPid,Ref}]},
            ets:insert(?TAB, [W, Rev]),
            _ = gproc_lib:ensure_monitor(WPid,C),
            {reply, Ref, [W,Rev]}
    end.



maybe_waiters(K, Pid, Value, T, Info) ->
    case ets:lookup(?TAB, {K,T}) of
        [{_, Waiters}] when is_list(Waiters) ->
            ets:insert(?TAB, Info),
            notify_waiters(Waiters, K, Pid, Value),
            true;
        [_] ->
            false
    end.


-spec notify_waiters([{pid(), reference()}], key(), pid(), any()) -> ok.

notify_waiters(Waiters, K, Pid, V) ->
    _ = [begin
             P ! {gproc, Ref, registered, {K, Pid, V}},
             case P of 
		 Pid -> ignore;
		 _ ->
		     ets:delete(?TAB, {P, K})
	     end
         end || {P, Ref} <- Waiters],
    ok.



mk_reg_objs(T, Scope, Pid, L) when T==n; T==a ->
    lists:map(fun({K,V}) ->
                      {{{T,Scope,K},T}, Pid, V};
                 (_) ->
                      erlang:error(badarg)
              end, L);
mk_reg_objs(p = T, Scope, Pid, L) ->
    lists:map(fun({K,V}) ->
                      {{{T,Scope,K},Pid}, Pid, V};
                 (_) ->
                      erlang:error(badarg)
              end, L).

mk_reg_rev_objs(T, Scope, Pid, L) ->
    [{{Pid,{T,Scope,K}},r} || {K,_} <- L].


ensure_monitor(Pid, Scope) when Scope==g; Scope==l ->
    case node(Pid) == node() andalso ets:insert_new(?TAB, {{Pid, Scope}}) of
        false -> ok;
        true  -> erlang:monitor(process, Pid)
    end.

remove_reg(Key, Pid) ->
    Reg = remove_reg_1(Key, Pid),
    ets:delete(?TAB, Rev = {Pid,Key}),
    [Reg, Rev].

remove_many(T, Scope, L, Pid) ->
    lists:flatmap(fun(K) ->
                          Key = {T, Scope, K},
                          remove_reg(Key, Pid)
                  end, L).

remove_reg_1({c,_,_} = Key, Pid) ->
    remove_counter_1(Key, ets:lookup_element(?TAB, Reg = {Key,Pid}, 3), Pid),
    Reg;
remove_reg_1({a,_,_} = Key, _Pid) ->
    ets:delete(?TAB, Reg = {Key,a}),
    Reg;
remove_reg_1({n,_,_} = Key, _Pid) ->
    ets:delete(?TAB, Reg = {Key,n}),
    Reg;
remove_reg_1({_,_,_} = Key, Pid) ->
    ets:delete(?TAB, Reg = {Key, Pid}),
    Reg.

remove_counter_1({c,C,N} = Key, Val, Pid) ->
    Res = ets:delete(?TAB, {Key, Pid}),
    update_aggr_counter(C, N, -Val),
    Res.

do_set_value({T,_,_} = Key, Value, Pid) ->
    K2 = if T==n orelse T==a -> T;
            true -> Pid
         end,
    case (catch ets:lookup_element(?TAB, {Key,K2}, 2)) of
        {'EXIT', {badarg, _}} ->
            false;
        Pid ->
            ets:insert(?TAB, {{Key, K2}, Pid, Value});
        _ ->
            false
    end.

do_set_counter_value({_,C,N} = Key, Value, Pid) ->
    OldVal = ets:lookup_element(?TAB, {Key, Pid}, 3), % may fail with badarg
    Res = ets:insert(?TAB, {{Key, Pid}, Pid, Value}),
    update_aggr_counter(C, N, Value - OldVal),
    Res.

update_counter({c,l,Ctr} = Key, Incr, Pid) ->
    Res = ets:update_counter(?TAB, {Key, Pid}, {3,Incr}),
    update_aggr_counter(l, Ctr, Incr),
    Res.

update_aggr_counter(C, N, Val) ->
    catch ets:update_counter(?TAB, {{a,C,N},a}, {3, Val}).

scan_existing_counters(Ctxt, Name) ->
    Head = {{{c,Ctxt,Name},'_'},'_','$1'},
    Cs = ets:select(?TAB, [{Head, [], ['$1']}]),
    lists:sum(Cs).


valid_opts(Type, Default) ->
    Opts = get_app_env(Type, Default),
    check_opts(Type, Opts).

check_opts(Type, Opts) when is_list(Opts) ->
    Check = check_option_f(Type),
    lists:map(fun(X) ->
		      case Check(X) of
			  true -> X;
			  false ->
			      erlang:error({illegal_option, X}, [Type, Opts])
		      end
	      end, Opts);
check_opts(Type, Other) ->
    erlang:error(invalid_options, [Type, Other]).

check_option_f(ets_options)    -> fun check_ets_option/1;
check_option_f(server_options) -> fun check_server_option/1.

check_ets_option({read_concurrency , B}) -> is_boolean(B);
check_ets_option({write_concurrency, B}) -> is_boolean(B);
check_ets_option(_) -> false.

check_server_option({priority, P}) ->
    %% Forbid setting priority to 'low' since that would
    %% surely cause problems. Unsure about 'max'...
    lists:member(P, [normal, high, max]);
check_server_option(_) ->
    %% assume it's a valid spawn option
    true.

get_app_env(Key, Default) ->
    case application:get_env(Key) of
	undefined       -> Default;
	{ok, undefined} -> Default;
	{ok, Value}     -> Value
    end.
