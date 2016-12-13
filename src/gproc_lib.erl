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
%% @author Ulf Wiger <ulf@wiger.net>
%%
%% @doc Extended process registry
%% <p>This module implements an extended process registry</p>
%% <p>For a detailed description, see gproc/doc/erlang07-wiger.pdf.</p>
%% @end
-module(gproc_lib).

-export([reg_type/2,
         await/3,
         do_set_counter_value/3,
         do_set_value/3,
         ensure_monitor/2,
         insert_many/4,
         insert_reg/4, insert_reg/5, insert_reg/7,
	 insert_attr/4,
         remove_many/4,
         remove_reg/3, remove_reg/4,
         monitors/1,
         standbys/1,
         followers/1,
         remove_monitor_pid/2,
	 add_monitor/4,
	 remove_monitor/3,
	 remove_monitors/3,
	 remove_reverse_mapping/3, remove_reverse_mapping/4,
	 notify/2, notify/3,
	 remove_wait/4,
         update_aggr_counter/3, update_aggr_counter/4,
         update_counter/4,
         decrement_resource_count/2, decrement_resource_count/3,
	 valid_opts/2]).

-include("gproc_int.hrl").
-include("gproc.hrl").


reg_type(n, _N) ->
    #{tag => n, type => n, unique => true, scan => [],
      aggr => [], rc => []};
reg_type(p, _N) ->
    #{tag => p, type => p, unique => false, scan => [],
      aggr => [], rc => []};
reg_type(c, _N) ->
    #{tag => c, type => c, unique => false, scan => [],
      aggr => [#{tag => a}], rc => []};
reg_type(a, _N) ->
    #{tag => a, type => a, unique => true, scan => [#{tag => c,
                                                      mode => sum}],
      aggr => [], rc => []};
reg_type(r, _N) ->
    #{tag => r, type => r, unique => false, scan => [],
      aggr => [], rc => [#{tag => rc}]};
reg_type(rc, _N) ->
    #{tag => rc, type => rc, unique => true, scan => [#{tag => r,
                                                        mode => count}],
      aggr => [], rc => []};
reg_type(T, N) ->
    case ?GPROC_EXT_CB:reg_type(T, N) of
        #{} = Type ->
            Type;
        undefined ->
            ?THROW_GPROC_ERROR(badarg)
    end.

%% We want to store names and aggregated counters with the same
%% structure as properties, but at the same time, we must ensure
%% that the key is unique. We replace the Pid in the key part
%% with an atom. To know which Pid owns the object, we lug the
%% Pid around as payload as well. This is a bit redundant, but
%% symmetric.
%%
-spec insert_reg(gproc:key(), any(), pid() | shared, gproc:scope()) -> boolean().
insert_reg(K, Value, Pid, Scope) ->
    insert_reg(K, Value, Pid, Scope, registered).

insert_reg({T,_,Name} = K, Value, Pid, Scope, Event) when T==a; T==n; T==rc ->
    Res = case ets_insert_new({{K,T}, Pid, Value}) of
              true ->
                  %% Use insert_new to avoid overwriting existing entry
                  _ = ets_insert_new({{Pid,K}, []}),
                  true;
              false ->
                  maybe_waiters(K, Pid, Value, T, Event)
          end,
    maybe_scan(T, Pid, Scope, Name, K),
    Res;
insert_reg({p,Scope,_} = K, Value, shared, Scope, _E)
  when Scope == g; Scope == l ->
    %% shared properties are unique
    Info = [{{K, shared}, shared, Value}, {{shared,K}, []}],
    ets_insert_new(Info);
insert_reg({c,Scope,Ctr} = Key, Value, Pid, Scope, _E) when Scope==l; Scope==g ->
    %% Non-unique keys; store Pid in the key part
    K = {Key, Pid},
    Kr = {Pid, Key},
    Res = ets_insert_new([{K, Pid, Value}, {Kr, [{initial, Value}]}]),
    case Res of
        true ->
            update_aggr_counter(Scope, Ctr, Value);
        false ->
            ignore
    end,
    Res;
insert_reg({r,Scope,R} = Key, Value, Pid, Scope, _E) when Scope==l; Scope==g ->
    K = {Key, Pid},
    Kr = {Pid, Key},
    Res = ets_insert_new([{K, Pid, Value}, {Kr, [{initial, Value}]}]),
    case Res of
        true ->
            update_resource_count(Scope, R, 1);
        false ->
            ignore
    end,
    Res;
insert_reg({_,_,_} = Key, Value, Pid, _Scope, _E) when is_pid(Pid) ->
    %% Non-unique keys; store Pid in the key part
    K = {Key, Pid},
    Kr = {Pid, Key},
    ets_insert_new([{K, Pid, Value}, {Kr, []}]).

insert_reg({T,Scope,N} = Key,
           #{tag    := T,
             type   := Ty,
             unique := U,
             scan   := Scan,
             aggr   := Aggr,
             rc     := Rc}, V, Pid, As, Scope, Event) ->
    K = case U of
            true  -> {Key, T};
            false -> {Key, Pid}
        end,
    V1 = if Ty =:= a; Ty =:= rc -> 0;
            true -> V
         end,
    Kr = {Pid, Key},
    As1 = reg_attrs(Ty, Aggr, Rc),
    Res = case ets_insert_new([{K, Pid, V1}, {Kr, [{initial, V1},
                                                   {attrs, As}|As1]}]) of
              true ->
                  update_aggr(Ty, Aggr, N, V1, Scope),
                  update_rc(Ty, Rc, N, 1, Scope),
                  true;
              false ->
                  maybe_waiters(U, Key, Pid, V1, T, Event)
          end,
    maybe_scan_(Res, Scan, Scope, N, K),
    Res.

reg_attrs(c, Aggr, _) ->
    [{type,c},{aggr, Aggr}];
reg_attrs(r, _, Rc) ->
    [{type,r},{rc, Rc}];
reg_attrs(T, _, _) ->
    [{type,T}].

update_aggr(c, [#{tag := Tag, wild := W}|T], N, Val, Scope)
  when is_number(Val) ->
    N1 = insert_wild(N, W, '\\_'),
    ?MAY_FAIL(ets_update_counter({{Tag, Scope, N1}, Tag}, {3, Val})),
    update_aggr(c, T, N, Val, Scope);
update_aggr(c, [#{tag := Tag}|T], N, Val, Scope)
  when is_number(Val) ->
    ?MAY_FAIL(ets_update_counter({{Tag, Scope, N}, Tag}, {3, Val})),
    update_aggr(c, T, N, Val, Scope);
update_aggr(_, _, _, _, _) ->
    ok.

update_rc(r, [_|_] = Rc, N, Val, Scope) ->
    update_rc(Rc, N, Val, Scope);
update_rc(_, _, _, _, _) ->
    ok.

update_rc([#{tag := Tag, wild := W}|T], N, Val, Scope) ->
    update_one_rc(Tag, Scope, insert_wild(N, W, '\\_'), Val),
    update_rc(T, N, Val, Scope);
update_rc([#{tag := Tag}|T], N, Val, Scope) ->
    update_one_rc(Tag, Scope, N, Val),
    update_rc(T, N, Val, Scope);
update_rc(_, _, _, _) ->
    ok.

update_one_rc(Tag, Scope, N, Val) ->
    try ets_update_counter({{Tag, Scope, N}, Tag}, {3, Val}) of
        0 -> resource_count_zero(Scope, Tag, N);
        _ -> ok
    catch
        _:_ -> ok
    end.

maybe_scan_(true, [_|_] = Tags, Scope, Name, K) ->
    Mode = scan_mode(Tags),
    Pat = scan_pattern(Tags, Mode, Scope, Name),
    Sum = case Mode of
              count -> ets_select_count(Pat);
              _ ->
                  Vs = ets_select(Pat),
                  lists:sum(Vs)
          end,
    ets_update_counter(K, {3, Sum});
maybe_scan_(_, _, _, _, _) ->
    ok.

scan_mode([#{mode := M}|T]) ->
    scan_mode(T, M).

scan_mode([#{mode := M}|T], M) ->
    scan_mode(T, M);
scan_mode([#{mode := _}|_], _) ->
    mixed;
scan_mode([], M) ->
    M.

scan_pattern([#{tag := Tag, wild := W, mode := M}|T], Mode, Scope, Name) ->
    [{ {{{Tag,Scope,insert_wild(Name, W, '_')},'_'},'_', '_'},
       guard_pattern(M),
       prod_pattern(M, Mode) }
     | scan_pattern(T, Mode, Scope, Name)];
scan_pattern([#{tag := Tag, mode := M}|T], Mode, Scope, Name) ->
    [{ {{{Tag,Scope,Name},'_'},'_', '_'},
       guard_pattern(M),
       prod_pattern(M, Mode) }
     | scan_pattern(T, Mode, Scope, Name)];
scan_pattern(_, _, _, _) ->
    [].

guard_pattern(sum  ) -> [{is_number, {element, 3, '$_'}}];
guard_pattern(count) -> [].

prod_pattern(sum  , _    ) -> [{element, 3, '$_'}];
prod_pattern(count, count) -> [true];
prod_pattern(count, _    ) -> [1].

insert_wild(Name, W, X) when is_tuple(Name) ->
    Sz = size(Name),
    insert_wild(W, Sz, Name, X).

insert_wild([last|T], Sz, Nm, X) ->
    insert_wild(T, Sz, setelement(Sz, Nm, X), X);
insert_wild([H|T], Sz, Nm, X) when is_integer(H) ->
    P = if H > 0 -> H;
           true  -> Sz + H
        end,
    insert_wild(T, Sz, setelement(P, Nm, X), X);
insert_wild([], _, Nm, _) ->
    Nm.

maybe_scan(a, Pid, Scope, Name, K) ->
    Initial = scan_existing_counters(Scope, Name),
    ets_insert({{K,a}, Pid, Initial});
maybe_scan(rc, Pid, Scope, Name, K) ->
    Initial = scan_existing_resources(Scope, Name),
    ets_insert({{K,rc}, Pid, Initial});
maybe_scan(_, _, _, _, _) ->
    true.

insert_attr({_,Scope,_} = Key, Attrs, Pid, Scope) when Scope==l;
						       Scope==g ->
    case ets_lookup(K = {Pid, Key}) of
	[{_, Attrs0}] when is_list(Attrs) ->
	    As = proplists:get_value(attrs, Attrs0, []),
	    As1 = lists:foldl(fun({K1,_} = Attr, Acc) ->
				     lists:keystore(K1, 1, Acc, Attr)
			     end, As, Attrs),
	    Attrs1 = lists:keystore(attrs, 1, Attrs0, {attrs, As1}),
	    ets_insert({K, Attrs1}),
	    Attrs1;
	_ ->
	    false
    end.

get_attr(Attr, Pid, {_,_,_} = Key, Default) ->
    case ets_lookup({Pid, Key}) of
        [{_, Opts}] when is_list(Opts) ->
            case lists:keyfind(attrs, 1, Opts) of
                {_, Attrs} ->
                    case lists:keyfind(Attr, 1, Attrs) of
                        {_, Val} ->
                            Val;
                        _ ->
                            Default
                    end;
                _ ->
                    Default
            end;
        _ ->
            Default
    end.

-spec insert_many(gproc:type(), gproc:scope(), [{gproc:key(),any()}], pid()) ->
          {true,list()} | false.

insert_many(T, Scope, KVL, Pid) ->
    Objs = mk_reg_objs(T, Scope, Pid, KVL),
    case ets_insert_new(Objs) of
        true ->
            RevObjs = mk_reg_rev_objs(T, Scope, Pid, KVL),
            ets_insert(RevObjs),
            _ = gproc_lib:ensure_monitor(Pid, Scope),
            {true, Objs};
        false ->
            Existing = [{Obj, ets_lookup(K)} || {K,_,_} = Obj <- Objs],
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

-spec insert_objects([{gproc:key(), pid(), any()}]) -> ok.

insert_objects(Objs) ->
    lists:foreach(
      fun({{{Id,_} = _K, Pid, V} = Obj, Existing}) ->
              ets_insert([Obj, {{Pid, Id}, []}]),
              case Existing of
                  [] -> ok;
                  [{_, Waiters}] ->
                      notify_waiters(Waiters, Id, Pid, V, registered)
              end
      end, Objs).


await({T,C,_} = Key, WPid, {_Pid, Ref} = From) ->
    Rev = {{WPid,Key}, []},
    case ets_lookup({Key,T}) of
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
            ets_insert([W, Rev]),
            _ = gproc_lib:ensure_monitor(WPid,C),
            {reply, Ref, [W,Rev]};
        [] ->
            W = {{Key,T}, [{WPid,Ref}]},
            ets_insert([W, Rev]),
            _ = gproc_lib:ensure_monitor(WPid,C),
            {reply, Ref, [W,Rev]}
    end.

maybe_waiters(_Unique = false, _, _, _, _, _) ->
    false;
maybe_waiters(_Unique = true, K, Pid, Value, T, Event) ->
    maybe_waiters(K, Pid, Value, T, Event).

maybe_waiters(_, _, _, _, []) ->
    false;
maybe_waiters(K, Pid, Value, T, Event) ->
    case ets_lookup({K,T}) of
        [{_, Waiters}] when is_list(Waiters) ->
            Followers = [F || {_,_,follow} = F <- Waiters],
            ets_insert([{{K,T}, Pid, Value},
                        {{Pid,K}, [{monitor, Followers}
                                   || Followers =/= []]}]),
            notify_waiters(Waiters, K, Pid, Value, Event),
            true;
        _ ->
            false
    end.

-spec notify_waiters([{pid(), reference()}], gproc:key(), pid(), any(), any()) -> ok.
notify_waiters([{P, Ref}|T], K, Pid, V, E) ->
    P ! {gproc, Ref, registered, {K, Pid, V}},
    notify_waiters(T, K, Pid, V, E);
notify_waiters([{P, Ref, follow}|T], K, Pid, V, E) ->
    %% This is really a monitor, lurking in the Waiters list
    P ! {gproc, E, Ref, K},
    notify_waiters(T, K, Pid, V, E);
notify_waiters([], _, _, _, _) ->
    ok.

remove_wait({T,_,_} = Key, Pid, Ref, Waiters) ->
    Rev = {Pid,Key},
    case remove_from_waiters(Waiters, Pid, Ref) of
	[] ->
	    ets_delete({Key,T}),
	    ets_delete(Rev),
	    [{delete, [{Key,T}, Rev], []}];
	NewWaiters ->
	    ets_insert({Key, NewWaiters}),
	    case lists:keymember(Pid, 1, NewWaiters) of
		true ->
		    %% should be extremely unlikely
		    [{insert, [{Key, NewWaiters}]}];
		false ->
		    %% delete the reverse entry
		    ets_delete(Rev),
		    [{insert, [{Key, NewWaiters}]},
		     {delete, [Rev], []}]
	    end
    end.

remove_from_waiters(Waiters, Pid, all) ->
    [W || W <- Waiters,
	      element(1,W) =/= Pid];
remove_from_waiters(Waiters, Pid, Ref) ->
    [W || W <- Waiters, not is_waiter(W, Pid, Ref)].

is_waiter({Pid, Ref}   , Pid, Ref) -> true;
is_waiter({Pid, Ref, _}, Pid, Ref) -> true;
is_waiter(_, _, _) ->
    false.

remove_monitors(Key, Pid, MPid) ->
    case ets_lookup({Pid, Key}) of
	[{_, r}] ->
	    [];
	[{K, Opts}] when is_list(Opts) ->
	    case lists:keyfind(monitors, 1, Opts) of
		false ->
		    [];
		{_, Ms} ->
		    Ms1 = [{P,R} || {P,R} <- Ms,
				    P =/= MPid],
		    NewMs = lists:keyreplace(monitors, 1, Opts, {monitors,Ms1}),
		    ets_insert({K, NewMs}),
		    [{insert, [{{Pid,Key}, NewMs}]}]
	    end;
	_ ->
	    []
    end.


mk_reg_objs(T, Scope, Pid, L) when T==n; T==a; T==rc ->
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
    [{{Pid,{T,Scope,K}}, []} || {K,_} <- L].


ensure_monitor(shared, _) ->
    ok;
ensure_monitor(Pid, _) when Pid == self() ->
    %% monitoring is ensured through a 'monitor_me' message
    ok;
ensure_monitor(Pid, Scope) when Scope==g; Scope==l ->
    case ets_insert_new({{Pid, Scope}}) of
        false -> ok;
        true  -> erlang:monitor(process, Pid)
    end.

remove_reg(Key, Pid, Event) ->
    Reg = remove_reg_1(Key, Pid),
    Rev = remove_reverse_mapping(Event, Pid, Key),
    [Reg, Rev].

remove_reg(Key, Pid, Event, Opts) ->
    Reg = remove_reg_1(Key, Pid),
    Rev = remove_reverse_mapping(Event, Pid, Key, Opts),
    [Reg, Rev].

remove_reverse_mapping(Event, Pid, Key) ->
    Opts = case ets_lookup({Pid, Key}) of
	       [] ->       [];
	       [{_, r}] -> [];
	       [{_, L}] when is_list(L) ->
		   L
	   end,
    remove_reverse_mapping(Event, Pid, Key, Opts).

remove_reverse_mapping(Event, Pid, Key, Opts) when Event==unreg;
						   element(1,Event)==migrated;
                                                   element(1,Event)==failover ->
    Rev = {Pid, Key},
    _ = notify(Event, Key, Opts),
    ets_delete(Rev),
    Rev.

notify(Key, Opts) ->
    notify(unreg, Key, Opts).

monitors(Opts) ->
    case lists:keyfind(monitor, 1, Opts) of
	false ->
	    [];
	{_, Mons} ->
            Mons
    end.

standbys(Opts) ->
    select_monitors(monitors(Opts), standby, []).

followers(Opts) ->
    select_monitors(monitors(Opts), follow, []).

select_monitors([{_,_,Type}=H|T], Type, Acc) ->
    select_monitors(T, Type, [H|Acc]);
select_monitors([_|T], Type, Acc) ->
    select_monitors(T, Type, Acc);
select_monitors([], _, Acc) ->
    Acc.

remove_monitor_pid([{monitor, Mons}|T], Pid) ->
    [{monitors, [M || M <- Mons,
                      element(1, M) =/= Pid]}|T];
remove_monitor_pid([H|T], Pid) ->
    [H | remove_monitor_pid(T, Pid)];
remove_monitor_pid([], _) ->
    [].


notify([], _, _) ->
    ok;
notify(Event, Key, Opts) ->
    notify_(monitors(Opts), Event, Key).

%% Also handle old-style monitors
notify_([{Pid,Ref}|T], Event, Key) ->
    Pid ! {gproc, Event, Ref, Key},
    notify_(T, Event, Key);
notify_([{Pid,Ref,_}|T], Event, {_,l,_} = Key) ->
    Pid ! {gproc, Event, Ref, Key},
    notify_(T, Event, Key);
notify_([{Pid,Ref,_}|T], Event, {_,g,_} = Key) when node(Pid) == node() ->
    Pid ! {gproc, Event, Ref, Key},
    notify_(T, Event, Key);
notify_([_|T], Event, Key) ->
    notify_(T, Event, Key);
notify_([], _, _) ->
    ok.



add_monitor([{monitor, Mons}|T], Pid, Ref, Type) ->
    [{monitor, [{Pid,Ref,Type}|Mons]}|T];
add_monitor([H|T], Pid, Ref, Type) ->
    [H|add_monitor(T, Pid, Ref, Type)];
add_monitor([], Pid, Ref, Type) ->
    [{monitor, [{Pid, Ref, Type}]}].

remove_monitor([{monitor, Mons}|T], Pid, Ref) ->
    [{monitor, [Mon || Mon <- Mons, not is_mon(Mon,Pid,Ref)]} | T];
remove_monitor([H|T], Pid, Ref) ->
    [H|remove_monitor(T, Pid, Ref)];
remove_monitor([], _Pid, _Ref) ->
    [].

is_mon({Pid,Ref,_}, Pid, Ref) -> true;
is_mon({Pid,Ref},   Pid, Ref) -> true;
is_mon(_, _, _) ->
    false.

remove_many(T, Scope, L, Pid) ->
    lists:flatmap(fun(K) ->
                          Key = {T, Scope, K},
                          remove_reg(Key, Pid, unreg, unreg_opts(Key, Pid))
                  end, L).

unreg_opts(Key, Pid) ->
    case ets_lookup({Pid, Key}) of
	[] ->
	    [];
	[{_,r}] ->
	    [];
	[{_,Opts}] ->
	    Opts
    end.

remove_reg_1({c,_,_} = Key, Pid) ->
    remove_counter_1(Key, ets_lookup_element(Reg = {Key,Pid}, 3), Pid),
    Reg;
remove_reg_1({r,_,_} = Key, Pid) ->
    remove_resource_1(Key, ets_lookup_element(Reg = {Key,Pid}, 3), Pid),
    Reg;
remove_reg_1({T,_,_} = Key, _Pid) when T==a; T==n; T==rc ->
    ets_delete(Reg = {Key,T}),
    Reg;
remove_reg_1({_,_,_} = Key, Pid) ->
    ets_delete(Reg = {Key, Pid}),
    Reg.

remove_counter_1({c,C,N} = Key, Val, Pid) ->
    Res = ets_delete({Key, Pid}),
    update_aggr_counter(C, N, -Val),
    Res.

remove_resource_1({r,C,N} = Key, _, Pid) ->
    Res = ets_delete({Key, Pid}),
    update_resource_count(C, N, -1),
    Res.

do_set_value({T,_,_} = Key, Value, Pid) ->
    K2 = if Pid == shared -> shared;
	    T==n orelse T==a orelse T==rc -> T;
	    true -> Pid
         end,
    try ets_lookup_element({Key,K2}, 2) of
        Pid ->
            ets_insert({{Key, K2}, Pid, Value});
        _ ->
            false
    catch
        error:_ -> false
    end.

do_set_counter_value({_,C,N} = Key, Value, Pid) ->
    OldVal = ets_lookup_element({Key, Pid}, 3), % may fail with badarg
    Res = ets_insert({{Key, Pid}, Pid, Value}),
    update_aggr_counter(C, N, Value - OldVal),
    Res.

update_counter({_,l,Ctr} = Key, #{type := T, aggr := Aggr}, Incr, Pid)
  when is_integer(Incr), T =:= c;
       is_integer(Incr), T =:= p;
       is_integer(Incr), T =:= r;
       is_integer(Incr), T =:= n ->
    if is_pid(Pid); Pid =:= n; Pid =:= shared -> ok;
       true -> ?THROW_GPROC_ERROR(badarg)
    end,
    Res = ets_update_counter({Key, Pid}, {3,Incr}),
    if T =:= c ->
	    update_aggr(T, Aggr, Ctr, Incr, l);
       true ->
	    ok
    end,
    Res;
update_counter({_,l,Ctr} = Key, #{type := T, aggr := Aggr},
               {Incr, Threshold, SetValue}, Pid)
  when is_integer(Incr), is_integer(Threshold), is_integer(SetValue), T =:= c;
       is_integer(Incr), is_integer(Threshold), is_integer(SetValue), T =:= r;
       is_integer(Incr), is_integer(Threshold), is_integer(SetValue), T =:= p;
       is_integer(Incr), is_integer(Threshold), is_integer(SetValue), T =:= n ->
    if is_pid(Pid); Pid =:= n; Pid =:= shared -> ok;
       true -> ?THROW_GPROC_ERROR(badarg)
    end,
    [Prev, New] = ets_update_counter(
                    {Key, Pid}, [{3, 0}, {3, Incr, Threshold, SetValue}]),
    if T==c ->
            update_aggr(T, Aggr, Ctr, New - Prev, l);
       true ->
	    ok
    end,
    New;
update_counter({_,l,Ctr} = Key, #{type := T, aggr := Aggr}, Ops, Pid)
  when is_list(Ops), T==c;
       is_list(Ops), T==r;
       is_list(Ops), T==p;
       is_list(Ops), T==n ->
    case ets_update_counter({Key, Pid}, [{3, 0} | expand_ops(Ops)]) of
	[_] ->
	    [];
	[Prev | Rest] ->
	    [New | _] = lists:reverse(Rest),
	    if T==c ->
		    update_aggr(T, Aggr, Ctr, New - Prev, l);
	       true ->
		    ok
	    end,
	    Rest
    end;
update_counter(_, _, _, _) ->
    ?THROW_GPROC_ERROR(badarg).

expand_ops([{Incr,Thr,SetV}|T])
  when is_integer(Incr), is_integer(Thr), is_integer(SetV) ->
    [{3, Incr, Thr, SetV}|expand_ops(T)];
expand_ops([Incr|T]) when is_integer(Incr) ->
    [{3, Incr}|expand_ops(T)];
expand_ops([]) ->
    [];
expand_ops(_) ->
    ?THROW_GPROC_ERROR(badarg).

update_aggr_counter(C, N, Val) ->
    update_aggr_counter(C, a, N, Val).

update_aggr_counter(C, T, N, Val) ->
    ?MAY_FAIL(ets_update_counter({{T,C,N},T}, {3, Val})).

decrement_resource_count(C, N) ->
    update_resource_count(C, rc, N, -1).

decrement_resource_count(C, T, N) ->
    update_resource_count(C, T, N, -1).

update_resource_count(C, N, Val) ->
    update_resource_count(C, rc, N, Val).

update_resource_count(C, T, N, Val) ->
    try ets_update_counter({{T,C,N},T}, {3, Val}) of
        0 ->
            resource_count_zero(T, C, N);
        _ ->
            ok
    catch
        _:_ -> ok
    end.

%% resource_count_zero(C, N) ->
%%     case ets:lookup(?TAB, {K = {rc,C,N},rc}) of
%%         [{_, Pid, _}] ->
%%             case get_attr(on_zero, Pid, K, undefined) of
%%                 undefined -> ok;
%%                 Actions ->
%%                     perform_on_zero(Actions, rc, C, N, Pid)
%%             end;
%%         _ -> ok
%%     end.

resource_count_zero(Tag, C, N) ->
    case ets_lookup({K = {Tag,C,N},Tag}) of
        [{_, Pid, _}] ->
            case get_attr(on_zero, Pid, K, undefined) of
                undefined -> ok;
                Actions ->
                    perform_on_zero(Actions, Tag, C, N, Pid)
            end;
        _ -> ok
    end.

perform_on_zero(Actions, Tag, C, N, Pid) ->
    lists:foreach(
      fun(A) ->
              try perform_on_zero_(A, Tag, C, N, Pid)
              catch error:_ -> ignore
              end
      end, Actions).

perform_on_zero_({send, ToProc}, Tag, C, N, Pid) ->
    gproc:send(ToProc, on_zero_msg(Tag, C, N, Pid)),
    ok;
perform_on_zero_({bcast, ToProc}, Tag, C, N, Pid) ->
    gproc:bcast(ToProc, on_zero_msg(Tag, C, N, Pid)),
    ok;
perform_on_zero_(publish, rc, C, N, Pid) ->
    gproc_ps:publish(C, gproc_resource_on_zero, {C, N, Pid}),
    ok;
perform_on_zero_(publish, Tag, C, N, Pid) ->
    gproc_ps:publish(C, gproc_resource_on_zero, {Tag, C, N, Pid}),
    ok;
perform_on_zero_({unreg_shared, T, N}, _, C, _, _) ->
    K = {T, C, N},
    case ets_member({K, shared}) of
        true ->
            Objs = remove_reg(K, shared, unreg),
            _ = if C == g -> self() ! {gproc_unreg, Objs};
                   true   -> ok
                end,
            ok;
        false ->
            ok
    end;
perform_on_zero_(_, _, _, _, _) ->
    ok.

on_zero_msg(rc, C, N, Pid) ->
    {gproc, resource_on_zero, C, N, Pid};
on_zero_msg(Tag, C, N, Pid) ->
    {gproc, resource_on_zero, Tag, C, N, Pid}.


scan_existing_counters(Ctxt, Name) ->
    Head = {{{c,Ctxt,Name},'_'},'_','$1'},
    Cs = ets_select([{Head, [], ['$1']}]),
    lists:sum(Cs).

scan_existing_resources(Ctxt, Name) ->
    Head = {{{r,Ctxt,Name},'_'},'_','_'},
    ets_select_count([{Head, [], [true]}]).

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

%% function wrappers for easier tracing
ets_insert(V)            -> ets:insert(?TAB, V).
ets_insert_new(V)        -> ets:insert_new(?TAB, V).
%%ets_update_element(K, X) -> ets:update_element(?TAB, K, X).
ets_update_counter(K, I) -> ets:update_counter(?TAB, K, I).
ets_lookup(K)            -> ets:lookup(?TAB, K).
ets_member(K)            -> ets:member(?TAB, K).
ets_lookup_element(K, P) -> ets:lookup_element(?TAB, K, P).
ets_select(Pat)          -> ets:select(?TAB, Pat).
ets_select_count(Pat)    -> ets:select_count(?TAB, Pat).
ets_delete(K)            -> ets:delete(?TAB, K).
