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
%% @author Ulf Wiger <ulf.wiger@erlang-consulting.com>
%%
%% @doc Extended process registry
%% <p>This module implements an extended process registry</p>
%% <p>For a detailed description, see
%% <a href="erlang07-wiger.pdf">erlang07-wiger.pdf</a>.</p>
%%
%% @type type()  = n | p | c | a. n = name; p = property; c = counter; 
%%                                a = aggregate_counter
%% @type scope() = l | g. l = local registration; g = global registration
%% @type context() = {scope(), type()} | type(). Local scope is the default
%% @type sel_type() = n | p | c | a |
%%                    names | props | counters | aggr_counters.
%% @type headpat() = {keypat(),pidpat(),ValPat}.
%% @type keypat() = {sel_type() | sel_var(),
%%                   l | g | sel_var(),
%%                   any()}.
%% @type pidpat() = pid() | sel_var().
%% sel_var() = DollarVar | '_'.
%% @type sel_pattern() = [{headpat(), Guards, Prod}].
%% @type key()   = {type(), scope(), any()}
%% @end
-module(gproc).
-behaviour(gen_server).
 
-export([start_link/0,
         reg/1, reg/2, unreg/1,
         mreg/3,
         set_value/2,
         get_value/1,
         where/1,
         await/1, await/2,
         nb_wait/1,
         cancel_wait/2,
         lookup_pid/1,
         lookup_pids/1,
         lookup_values/1,
         update_counter/2,
         send/2,
         info/1, info/2,
         select/1, select/2, select/3,
         first/1,
         next/2,
         prev/2,
         last/1,
         table/1, table/2]).

%% Convenience functions
-export([add_local_name/1,
         add_global_name/1,
         add_local_property/2,
         add_global_property/2,
         add_local_counter/2,
         add_global_counter/2,
         add_local_aggr_counter/1,
         add_global_aggr_counter/1,
         lookup_local_name/1,
         lookup_global_name/1,
         lookup_local_properties/1,
         lookup_global_properties/1,
         lookup_local_counters/1,
         lookup_global_counters/1,
         lookup_local_aggr_counter/1,
         lookup_global_aggr_counter/1]).

-export([default/1]).

%%% internal exports
-export([init/1,
         handle_cast/2,
         handle_call/3,
         handle_info/2,
         code_change/3,
         terminate/2]).

%% this shouldn't be necessary
-export([audit_process/1]).


-include("gproc.hrl").
-include_lib("eunit/include/eunit.hrl").

-define(SERVER, ?MODULE).
%%-define(l, l(?LINE)). % when activated, calls a traceable empty function
-define(l, ignore).

-define(CHK_DIST,
        case whereis(gproc_dist) of
            undefined ->
                erlang:error(local_only);
            _ ->
                ok
        end).

-record(state, {}).

%% @spec () -> {ok, pid()}
%%
%% @doc Starts the gproc server.
%%
%% This function is intended to be called from gproc_sup, as part of 
%% starting the gproc application.
%% @end
start_link() ->
    create_tabs(),
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% spec(Name::any()) -> true
%%
%% @doc Registers a local (unique) name. @equiv reg({n,l,Name})
%% @end
%%
add_local_name(Name)  -> reg({n,l,Name}, undefined).


%% spec(Name::any()) -> true
%%
%% @doc Registers a global (unique) name. @equiv reg({n,g,Name})
%% @end
%%
add_global_name(Name) -> reg({n,g,Name}, undefined).


%% spec(Name::any(), Value::any()) -> true
%%
%% @doc Registers a local (non-unique) property. @equiv reg({p,l,Name},Value)
%% @end
%%
add_local_property(Name , Value) -> reg({p,l,Name}, Value).

%% spec(Name::any(), Value::any()) -> true
%%
%% @doc Registers a global (non-unique) property. @equiv reg({p,g,Name},Value)
%% @end
%%
add_global_property(Name, Value) -> reg({p,g,Name}, Value).

%% spec(Name::any(), Initial::integer()) -> true
%%
%% @doc Registers a local (non-unique) counter. @equiv reg({c,l,Name},Value)
%% @end
%%
add_local_counter(Name, Initial) when is_integer(Initial) ->
    reg({c,l,Name}, Initial).


%% spec(Name::any(), Initial::integer()) -> true
%%
%% @doc Registers a global (non-unique) counter. @equiv reg({c,g,Name},Value)
%% @end
%%
add_global_counter(Name, Initial) when is_integer(Initial) ->
    reg({c,g,Name}, Initial).

%% spec(Name::any()) -> true
%%
%% @doc Registers a local (unique) aggregated counter.
%% @equiv reg({a,l,Name})
%% @end
%%
add_local_aggr_counter(Name)  -> reg({a,l,Name}).

%% spec(Name::any()) -> true
%%
%% @doc Registers a global (unique) aggregated counter.
%% @equiv reg({a,g,Name})
%% @end
%%
add_global_aggr_counter(Name) -> reg({a,g,Name}).
    

%% @spec (Name::any()) -> pid()
%%
%% @doc Lookup a local unique name. Fails if there is no such name.
%% @equiv where({n,l,Name})
%% @end
%%
lookup_local_name(Name)   -> where({n,l,Name}).

%% @spec (Name::any()) -> pid()
%%
%% @doc Lookup a global unique name. Fails if there is no such name.
%% @equiv where({n,g,Name})
%% @end
%%
lookup_global_name(Name)  -> where({n,g,Name}).

%% @spec (Name::any()) -> integer()
%%
%% @doc Lookup a local (unique) aggregated counter and returns its value.
%% Fails if there is no such object.
%% @equiv where({a,l,Name})
%% @end
%%
lookup_local_aggr_counter(Name)  -> lookup_value({a,l,Name}).

%% @spec (Name::any()) -> integer()
%%
%% @doc Lookup a global (unique) aggregated counter and returns its value.
%% Fails if there is no such object.
%% @equiv where({a,g,Name})
%% @end
%%
lookup_global_aggr_counter(Name) -> lookup_value({a,g,Name}).
    

%% @spec (Property::any()) -> [{pid(), Value}]
%%
%% @doc Look up all local (non-unique) instances of a given Property.
%% Returns a list of {Pid, Value} tuples for all matching objects.
%% @equiv lookup_values({p, l, Property})
%% @end
%%
lookup_local_properties(P)  -> lookup_values({p,l,P}).

%% @spec (Property::any()) -> [{pid(), Value}]
%%
%% @doc Look up all global (non-unique) instances of a given Property.
%% Returns a list of {Pid, Value} tuples for all matching objects.
%% @equiv lookup_values({p, g, Property})
%% @end
%%
lookup_global_properties(P) -> lookup_values({p,g,P}).


%% @spec (Counter::any()) -> [{pid(), Value::integer()}]
%%
%% @doc Look up all local (non-unique) instances of a given Counter.
%% Returns a list of {Pid, Value} tuples for all matching objects.
%% @equiv lookup_values({c, l, Counter})
%% @end
%%
lookup_local_counters(P)    -> lookup_values({c,l,P}).


%% @spec (Counter::any()) -> [{pid(), Value::integer()}]
%%
%% @doc Look up all global (non-unique) instances of a given Counter.
%% Returns a list of {Pid, Value} tuples for all matching objects.
%% @equiv lookup_values({c, g, Counter})
%% @end
%%
lookup_global_counters(P)   -> lookup_values({c,g,P}).



%% @spec reg(Key::key()) -> true
%%
%% @doc
%% @equiv reg(Key, default(Key))
%% @end
reg(Key) ->
    reg(Key, default(Key)).

default({T,_,_}) when T==c -> 0;
default(_) -> undefined.

%% @spec await(Key::key()) -> {pid(),Value}
%% @equiv await(Key,infinity)
%%
await(Key) ->
    await(Key, infinity).

%% @spec await(Key::key(), Timeout) -> {pid(),Value}
%%   Timeout = integer() | infinity
%%
%% @doc Wait for a local name to be registered.
%% The function raises an exception if the timeout expires. Timeout must be 
%% either an interger &gt; 0 or 'infinity'.
%% A small optimization: we first perform a lookup, to see if the name
%% is already registered. This way, the cost of the operation will be 
%% roughly the same as of where/1 in the case where the name is already 
%% registered (the difference: await/2 also returns the value).
%% @end
%%
await({n,g,_} = Key, Timeout) ->
    ?CHK_DIST,
    request_wait(Key, Timeout);
await({n,l,_} = Key, Timeout) ->
    case ets:lookup(?TAB, {Key, n}) of
        [{_, Pid, Value}] ->
            {Pid, Value};
        _ ->
            request_wait(Key, Timeout)
    end;
await(K, T) ->
    erlang:error(badarg, [K, T]).

request_wait({n,C,_} = Key, Timeout) when C==l; C==g ->
    TRef = case Timeout of
               infinity -> no_timer;
               T when is_integer(T), T > 0 ->
                   erlang:start_timer(T, self(), gproc_timeout);
               _ ->
                   erlang:error(badarg, [Key, Timeout])
           end,
    WRef = call({await,Key,self()}, C),
    receive
        {gproc, WRef, registered, {_K, Pid, V}} ->
	    case TRef of
		no_timer -> ignore;
		_ -> erlang:cancel_timer(TRef)
	    end,
            {Pid, V};
        {timeout, TRef, gproc_timeout} ->
            cancel_wait(Key, WRef),
            erlang:error(timeout, [Key, Timeout])
    end.


%% @spec nb_wait(Key::key()) -> Ref
%%
%% @doc Wait for a local name to be registered.
%% The caller can expect to receive a message,
%% {gproc, Ref, registered, {Key, Pid, Value}}, once the name is registered.
%% @end
%%
nb_wait({n,g,_} = Key) ->
    ?CHK_DIST,
    call({await, Key, self()}, g);
nb_wait({n,l,_} = Key) ->
    call({await, Key, self()}, l);
nb_wait(Key) ->
    erlang:error(badarg, [Key]).

cancel_wait({_,g,_} = Key, Ref) ->
    ?CHK_DIST,
    cast({cancel_wait, self(), Key, Ref}, g),
    ok;
cancel_wait({_,l,_} = Key, Ref) ->
    cast({cancel_wait, self(), Key, Ref}, l),
    ok.
            

%% @spec reg(Key::key(), Value) -> true
%%
%% @doc Register a name or property for the current process
%%
%%
reg({_,g,_} = Key, Value) ->
    %% anything global
    ?CHK_DIST,
    gproc_dist:reg(Key, Value);
reg({p,l,_} = Key, Value) ->
    local_reg(Key, Value);
reg({a,l,_} = Key, undefined) ->
    call({reg, Key, undefined});
reg({c,l,_} = Key, Value) when is_integer(Value) ->
    call({reg, Key, Value});
reg({n,l,_} = Key, Value) ->
    call({reg, Key, Value});
reg(_, _) ->
    erlang:error(badarg).

%% @spec mreg(type(), scope(), [{Key::any(), Value::any()}]) -> true
%%
%% @doc Register multiple {Key,Value} pairs of a given type and scope.
%% 
%% This function is more efficient than calling {@link reg/2} repeatedly.
%% @end
mreg(T, g, KVL) ->
    ?CHK_DIST,
    gproc_dist:mreg(T, KVL);
mreg(T, l, KVL) when T==a; T==n ->
    if is_list(KVL) ->
            call({mreg, T, l, KVL});
       true ->
            erlang:error(badarg)
    end;
mreg(p, l, KVL) ->
    local_mreg(p, KVL);
mreg(_, _, _) ->
    erlang:error(badarg).

%% @spec (Key:: key()) -> true
%%
%% @doc Unregister a name or property.
%% @end
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

%% @spec (select_pattern()) -> list(sel_object())
%% @doc
%% @equiv select(all, Pat)
%% @end
select(Pat) ->
    select(all, Pat).

%% @spec (Type::sel_type(), Pat::sel_pattern()) -> [{Key, Pid, Value}]
%%
%% @doc Perform a select operation on the process registry.
%%
%% The physical representation in the registry may differ from the above,
%% but the select patterns are transformed appropriately.
%% @end
select(Type, Pat) ->
    ets:select(?TAB, pattern(Pat, Type)).

%% @spec (Type::sel_type(), Pat::sel_patten(), Limit::integer()) ->
%%          [{Key, Pid, Value}]
%% @doc Like {@link select/2} but returns Limit objects at a time.
%%
%% See [http://www.erlang.org/doc/man/ets.html#select-3].
%% @end
select(Type, Pat, Limit) ->
    ets:select(?TAB, pattern(Pat, Type), Limit).


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




%% @spec (Key :: key(), Value) -> true
%% @doc Sets the value of the registeration entry given by Key
%% 
%% Key is assumed to exist and belong to the calling process.
%% If it doesn't, this function will exit.
%%
%% Value can be any term, unless the object is a counter, in which case
%% it must be an integer.
%% @end
%%
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




%% @spec (Key) -> Value
%% @doc Read the value stored with a key registered to the current process.
%%
%% If no such key is registered to the current process, this function exits.
%% @end
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


%% @spec (Key) -> Pid
%% @doc Lookup the Pid stored with a key.
%%
lookup_pid({_T,_,_} = Key) ->
    case where(Key) of
        undefined -> erlang:error(badarg);
        P -> P
    end.

lookup_value({T,_,_} = Key) ->
    if T==n orelse T==a ->
            ets:lookup_element(?TAB, {Key,T}, 3);
       true ->
            erlang:error(badarg)
    end.

%% @spec (Key::key()) -> pid()
%%
%% @doc Returns the pid registered as Key
%% 
%% The type of registration entry must be either name or aggregated counter.
%% Otherwise this function will exit. Use {@link lookup_pids/1} in these
%% cases.
%% @end
%%
where({T,_,_}=Key) ->
    if T==n orelse T==a ->
            case ets:lookup(?TAB, {Key,T}) of
                [{_, P, _Value}] ->
                    case my_is_process_alive(P) of
			true -> P;
			false ->
			    undefined
		    end;
                _ ->  % may be [] or [{Key,Waiters}]
                    undefined
            end;
       true ->
            erlang:error(badarg)
    end.

%% @spec (Key::key()) -> [pid()]
%%
%% @doc Returns a list of pids with the published key Key
%%
%% If the type of registration entry is either name or aggregated counter,
%% this function will return either an empty list, or a list of one pid.
%% For non-unique types, the return value can be a list of any length.
%% @end
%%
lookup_pids({T,_,_} = Key) ->
    L = if T==n orelse T==a ->
		ets:select(?TAB, [{{{Key,T}, '$1', '_'},[],['$1']}]);
	   true ->
		ets:select(?TAB, [{{{Key,'_'}, '$1', '_'},[],['$1']}])
	end,
    [P || P <- L, my_is_process_alive(P)].


%% @spec (pid()) -> boolean()
%%
my_is_process_alive(P) when node(P) =:= node() ->
    is_process_alive(P);
my_is_process_alive(_) ->
    %% remote pid - assume true (too costly to find out)
    true.




%% @spec (Key::key()) -> [{pid(), Value}]
%%
%% @doc Retrieve the `{Pid,Value}' pairs corresponding to Key.
%%
%% Key refer to any type of registry object. If it refers to a unique
%% object, the list will be of length 0 or 1. If it refers to a non-unique
%% object, the return value can be a list of any length.
%% @end
%%
lookup_values({T,_,_} = Key) ->
    L = if T==n orelse T==a ->
		ets:select(?TAB, [{{{Key,T}, '$1', '$2'},[],[{{'$1','$2'}}]}]);
	   true ->
		ets:select(?TAB, [{{{Key,'_'}, '$1', '$2'},[],[{{'$1','$2'}}]}])
	end,
    [Pair || {P,_} = Pair <- L, my_is_process_alive(P)].



%% @spec (Key::key(), Incr::integer()) -> integer()
%%
%% @doc Updates the counter registered as Key for the current process.
%%
%% This function works like ets:update_counter/3
%% (see [http://www.erlang.org/doc/man/ets.html#update_counter-3]), but 
%% will fail if the type of object referred to by Key is not a counter.
%% @end
%%
update_counter({c,l,_} = Key, Incr) when is_integer(Incr) ->
    gproc_lib:update_counter(Key, Incr, self());
update_counter({c,g,_} = Key, Incr) when is_integer(Incr) ->
    ?CHK_DIST,
    gproc_dist:update_counter(Key, Incr);
update_counter(_, _) ->
    erlang:error(badarg).



%% @spec (Key::key(), Msg::any()) -> Msg
%%
%% @doc Sends a message to the process, or processes, corresponding to Key.
%%
%% If Key belongs to a unique object (name or aggregated counter), this 
%% function will send a message to the corresponding process, or fail if there
%% is no such process. If Key is for a non-unique object type (counter or 
%% property), Msg will be send to all processes that have such an object.
%% @end
%%
send({T,C,_} = Key, Msg) when C==l; C==g ->
    if T == n orelse T == a ->
            case ets:lookup(?TAB, {Key, T}) of
                [{_, Pid, _}] ->
                    Pid ! Msg;
                _ ->
                    erlang:error(badarg)
            end;
       T==p orelse T==c ->
            %% BUG - if the key part contains select wildcards, we may end up
            %% sending multiple messages to the same pid
            lists:foreach(fun(Pid) ->
                                  Pid ! Msg
                          end, lookup_pids(Key)),
            Msg;
       true ->
            erlang:error(badarg)
    end;
send(_, _) ->
    erlang:error(badarg).


%% @spec (Type :: type()) -> key() | '$end_of_table'
%%
%% @doc Behaves as ets:first(Tab) for a given type of registration object.
%%
%% See [http://www.erlang.org/doc/man/ets.html#first-1].
%%  The registry behaves as an ordered_set table.
%% @end
%%
first(Type) ->
    {HeadPat,_} = headpat(Type, '_', '_', '_'),
    case ets:select(?TAB, [{HeadPat,[],[{element,1,'$_'}]}], 1) of
        {[First], _} ->
            First;
        _ ->
            '$end_of_table'
    end.

%% @spec (Context :: context()) -> key() | '$end_of_table'
%%
%% @doc Behaves as ets:last(Tab) for a given type of registration object.
%%
%% See [http://www.erlang.org/doc/man/ets.html#last-1].
%% The registry behaves as an ordered_set table.
%% @end
%%
last(Context) ->
    {S, T} = get_s_t(Context),
    S1 = if S == '_'; S == l -> m;
            S == g -> h
         end,
    Beyond = {{T,S1,[]},[]},
    step(ets:prev(?TAB, Beyond), S, T).


%% @spec (Context::context(), Key::key()) -> key() | '$end_of_table'
%%
%% @doc Behaves as ets:next(Tab,Key) for a given type of registration object.
%%
%% See [http://www.erlang.org/doc/man/ets.html#next-2].
%% The registry behaves as an ordered_set table.
%% @end
%%
next(Context, K) ->
    {S,T} = get_s_t(Context),
    step(ets:next(?TAB,K), S, T).

%% @spec (Context::context(), Key::key()) -> key() | '$end_of_table'
%%
%% @doc Behaves as ets:prev(Tab,Key) for a given type of registration object.
%%
%% See [http://www.erlang.org/doc/man/ets.html#prev-2].
%% The registry behaves as an ordered_set table.
%% @end
%%
prev(Context, K) ->
    {S, T} = get_s_t(Context),
    step(ets:prev(?TAB, K), S, T).

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
step(Key, S, '_') ->
    case Key of
        {{_, S, _}, _} -> Key;
        _ -> '$end_of_table'
    end;
step(Key, S, T) ->
    case Key of
        {{T, S, _}, _} -> Key;
        _ -> '$end_of_table'
    end.


%% @spec (Pid::pid()) -> ProcessInfo
%% ProcessInfo = [{gproc, [{Key,Value}]} | ProcessInfo]
%%
%% @doc Similar to `process_info(Pid)' but with additional gproc info.
%% 
%% Returns the same information as process_info(Pid), but with the 
%% addition of a `gproc' information item, containing the `{Key,Value}'
%% pairs registered to the process.
%% @end
info(Pid) when is_pid(Pid) ->
    Items = [?MODULE | [ I || {I,_} <- process_info(self())]],
    [info(Pid,I) || I <- Items].

%% @spec (Pid::pid(), Item::atom()) -> {Item, Info}
%%
%% @doc Similar to process_info(Pid, Item), but with additional gproc info.
%%
%% For `Item = gproc', this function returns a list of `{Key, Value}' pairs
%% registered to the process Pid. For other values of Item, it returns the 
%% same as [http://www.erlang.org/doc/man/erlang.html#process_info-2].
%% @end
info(Pid, ?MODULE) ->
    Keys = ets:select(?TAB, [{ {{Pid,'$1'}, r}, [], ['$1'] }]),
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

%% @hidden
handle_cast({monitor_me, Pid}, S) ->
    erlang:monitor(process, Pid),
    {noreply, S};
handle_cast({cancel_wait, Pid, {T,_,_} = Key, Ref}, S) ->
    case ets:lookup(?TAB, {Key,T}) of
        [{K, Waiters}] ->
            NewWaiters = Waiters -- [{Pid,Ref}],
            %% for now, we don't remove the reverse entry. If we should do
            %% that, we have to make sure that Pid doesn't have another
            %% waiter (which it shouldn't have, given that the wait is 
            %% synchronous). Keeping it is not problematic - worst case, we
            %% will get an unnecessary cleanup.
            ets:insert(?TAB, {K, NewWaiters});
        _ ->
            ignore
    end,
    {noreply, S}.

%% @hidden
handle_call({reg, {_T,l,_} = Key, Val}, {Pid,_}, S) ->
    case try_insert_reg(Key, Val, Pid) of
        true ->
            gproc_lib:ensure_monitor(Pid,l),
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
handle_call({await, {_,l,_} = Key, Pid}, {_, Ref}, S) ->
    %% Passing the pid explicitly is needed when leader_call is used,
    %% since the Pid given as From in the leader is the local gen_leader
    %% instance on the calling node.
    case gproc_lib:await(Key, {Pid, Ref}) of
        noreply ->
            {noreply, S};
        {reply, Reply, _} ->
            {reply, Reply, S}
    end;
%%     Rev = {{Pid,Key}, r},
%%     case ets:lookup(?TAB, {Key,T}) of
%%         [{_, P, Value}] ->
%%             %% for symmetry, we always reply with Ref and then send a message
%%             gen_server:reply(From, Ref),
%%             Pid ! {gproc, Ref, registered, {Key, P, Value}},
%%             {noreply, S};
%%         [{K, Waiters}] ->
%%             NewWaiters = [{Pid,Ref} | Waiters],
%%             ets:insert(?TAB, [{K, NewWaiters}, Rev]),
%%             gproc_lib:ensure_monitor(Pid,l),
%%             {reply, Ref, S};
%%         [] ->
%%             ets:insert(?TAB, [{{Key,T}, [{Pid,Ref}]}, Rev]),
%%             gproc_lib:ensure_monitor(Pid,l),
%%             {reply, Ref, S}
%%     end;
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
handle_call({audit_process, Pid}, _, S) ->
    case is_process_alive(Pid) of
	false ->
	    process_is_down(Pid);
	true ->
	    ignore
    end,
    {reply, ok, S};
handle_call(_, _, S) ->
    {reply, badarg, S}.

%% @hidden
handle_info({'DOWN', _MRef, process, Pid, _}, S) ->
    process_is_down(Pid),
    {noreply, S};
handle_info(_, S) ->
    {noreply, S}.


%% @hidden
code_change(_FromVsn, S, _Extra) ->
    %% We have changed local monitor markers from {Pid} to {Pid,l}.
    case ets:select(?TAB, [{{'$1'},[],['$1']}]) of
        [] ->
            ok;
        Pids ->
            ets:insert(?TAB, [{P,l} || P <- Pids]),
            ets:select_delete(?TAB, [{{'_'},[],[true]}])
    end,
    {ok, S}.

%% @hidden
terminate(_Reason, _S) ->
    ok.


call(Req) ->
    call(Req, l).

call(Req, l) ->
    chk_reply(gen_server:call(?MODULE, Req), Req);
call(Req, g) ->
    chk_reply(gproc_dist:leader_call(Req), Req).

chk_reply(Reply, Req) ->
    case Reply of
        badarg -> erlang:error(badarg, Req);
        Reply  -> Reply
    end.


cast(Msg) ->
    cast(Msg, l).

cast(Msg, l) ->
    gen_server:cast(?MODULE, Msg);
cast(Msg, g) ->
    gproc_dist:leader_cast(Msg).




try_insert_reg({T,l,_} = Key, Val, Pid) ->
    case gproc_lib:insert_reg(Key, Val, Pid, l) of
        false ->
            case ets:lookup(?TAB, {Key,T}) of
                %% In this particular case, the lookup cannot result in
                %% [{_, Waiters}], since the insert_reg/4 function would
                %% have succeeded then.
                [{_, OtherPid, _}] ->
                    case is_process_alive(OtherPid) of
                        true ->
                            false;
                        false ->
                            process_is_down(OtherPid),
                            true = gproc_lib:insert_reg(Key, Val, Pid, l)
                    end;
                [] ->
                    false
            end;
        true ->
            true
    end.


-spec audit_process(pid()) -> ok.

audit_process(Pid) when is_pid(Pid) ->
    gen_server:call(gproc, {audit_process, Pid}, infinity).
    

-spec process_is_down(pid()) -> ok.

process_is_down(Pid) ->
    %% delete the monitor marker
    %% io:fwrite(user, "process_is_down(~p) - ~p~n", [Pid,ets:tab2list(?TAB)]),
    ets:delete(?TAB, {Pid,l}),
    Revs = ets:select(?TAB, [{{{Pid,'$1'},r}, 
                              [{'==',{element,2,'$1'},l}], ['$1']}]),
    lists:foreach(
      fun({n,l,_}=K) ->
              Key = {K,n},
              case ets:lookup(?TAB, Key) of
                  [{_, Pid, _}] ->
                      ets:delete(?TAB, Key);
                  [{_, Waiters}] ->
                      case [W || {P,_} = W <- Waiters,
                                 P =/= Pid] of
                          [] ->
                              ets:delete(?TAB, Key);
                          Waiters1 ->
                              ets:insert(?TAB, {Key, Waiters1})
                      end;
                  [] ->
                      true
              end;
         ({c,l,C} = K) ->
              Key = {K, Pid},
              [{_, _, Value}] = ets:lookup(?TAB, Key),
              ets:delete(?TAB, Key),
              gproc_lib:update_aggr_counter(l, C, -Value);
         ({a,l,_} = K) -> 
              ets:delete(?TAB, {K,a});
         ({p,_,_} = K) ->
              ets:delete(?TAB, {K, Pid})
      end, Revs),
    ets:select_delete(?TAB, [{{{Pid,{'_',l,'_'}},'_'}, [], [true]}]),
    ok.

create_tabs() ->
    case ets:info(?TAB, name) of
	undefined ->
	    ets:new(?TAB, [ordered_set, public, named_table]);
	_ ->
	    ok
    end.


%% @hidden
init([]) ->
    set_monitors(),
    {ok, #state{}}.


set_monitors() ->
    set_monitors(ets:select(?TAB, [{{{'$1',l}},[],['$1']}], 100)).


set_monitors('$end_of_table') ->
    ok;
set_monitors({Pids, Cont}) ->
    [erlang:monitor(process,Pid) || Pid <- Pids],
    set_monitors(ets:select(Cont)).



monitor_me() ->
    case ets:insert_new(?TAB, {{self(),l}}) of
        false -> true;
        true  ->
            cast({monitor_me,self()}),
            true
    end.




pattern([{'_', Gs, As}], T) ->
    ?l,
    {HeadPat, Vs} = headpat(T, '$1', '$2', '$3'),
    [{HeadPat, rewrite(Gs,Vs), rewrite(As,Vs)}];
pattern([{{A,B,C},Gs,As}], Scope) ->
    ?l,
    {HeadPat, Vars} = headpat(Scope, A,B,C),
    [{HeadPat, rewrite(Gs,Vars), rewrite(As,Vars)}];
pattern([{Head, Gs, As}], Scope) ->
    ?l,
    case is_var(Head) of
        {true,_N} ->
            HeadPat = {{{type(Scope),'_','_'},'_'},'_','_'},
            Vs = [{Head, obj_prod()}],
%%            {HeadPat, Vs} = headpat(Scope, A,B,C),
            %% the headpat function should somehow verify that Head is
            %% consistent with Scope (or should we add a guard?)
            [{HeadPat, rewrite(Gs, Vs), rewrite(As, Vs)}];
        false ->
            erlang:error(badarg)
    end.

%% This is the expression to use in guards and the RHS to address the whole
%% object, in its logical representation.
obj_prod() ->
    {{ {element,1,{element,1,'$_'}},
       {element,2,'$_'},
       {element,3,'$_'} }}.

obj_prod_l() ->
    [ {element,1,{element,1,'$_'}},
      {element,2,'$_'},
      {element,3,'$_'} ].


headpat({S, T}, V1,V2,V3) when S==global; S==local; S==all ->
    headpat(type(T), scope(S), V1,V2,V3);
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
                        ?l,
                        {T1,Vs1} = subst(T,Vt,fun() -> Rf(1) end,[]),
                        {C1,Vs2} = subst(C,Vc,fun() -> Rf(2) end,Vs1),
                        {{T1,C1,Vn}, Vs2};
                    '_' ->
                        ?l,
                        {{T,C,'_'}, []};
                    _ ->
                        ?l,
                        case is_var(V1) of
                            {true,_} ->
                                {{T,C,V1}, [{V1, {element,1,
                                                  {element,1,'$_'}}}]};
                            false ->
                                erlang:error(badarg)
                        end
                end,
    {{{Kp,K2},V2,V3}, Vars}.

%% l(L) -> L.
    


subst(X, '_', _F, Vs) ->
    {X, Vs};
subst(X, V, F, Vs) ->
    case is_var(V) of
        {true,_} ->
            {X, [{V,F()}|Vs]};
        false ->
            {V, Vs}
    end.

scope(all)    -> '_';
scope(global) -> g;
scope(local)  -> l.

type(all)   -> '_';
type(T) when T==n; T==p; T==c; T==a -> T;
type(names) -> n;
type(props) -> p;
type(counters) -> c;
type(aggr_counters) -> a.

keypat(Context) ->
    {S,T} = get_s_t(Context),
    {{T,S,'_'},'_'}.



get_s_t({S,T}) -> {scope(S), type(T)};
get_s_t(T) when is_atom(T) ->
    {l, type(T)}.

is_var('$1') -> {true,1};
is_var('$2') -> {true,2};
is_var('$3') -> {true,3};
is_var('$4') -> {true,4};
is_var('$5') -> {true,5};
is_var('$6') -> {true,6};
is_var('$7') -> {true,7};
is_var('$8') -> {true,8};
is_var('$9') -> {true,9};
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


rewrite(Gs, R) ->
    [rewrite1(G, R) || G <- Gs].

rewrite1('$_', _) ->
    obj_prod();
rewrite1('$$', _) ->
    obj_prod_l();
rewrite1(Guard, R) when is_tuple(Guard) ->
    list_to_tuple([rewrite1(G, R) || G <- tuple_to_list(Guard)]);
rewrite1(Exprs, R) when is_list(Exprs) ->
    [rewrite1(E, R) || E <- Exprs];
rewrite1(V, R) when is_atom(V) ->
    case is_var(V) of
        {true,_N} ->
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


%% @spec (Context::context()) -> any()
%%
%% @doc
%% @equiv table(Context, [])
%% @end
%%
table(Context) ->
    table(Context, []).

%% @spec (Context::context(), Opts) -> any()
%%
%% @doc QLC table generator for the gproc registry.
%% Context specifies which subset of the registry should be queried.
%% See [http://www.erlang.org/doc/man/qlc.html].
%% @end
table(Ctxt, Opts) ->
    [Traverse, NObjs] = [proplists:get_value(K,Opts,Def) ||
                            {K,Def} <- [{traverse,select}, {n_objects,100}]],
    TF = case Traverse of
             first_next ->
                 fun() -> qlc_next(Ctxt, first(Ctxt)) end;
             last_prev -> fun() -> qlc_prev(Ctxt, last(Ctxt)) end;
             select ->
                 fun(MS) -> qlc_select(select(Ctxt, MS, NObjs)) end;
             {select,MS} ->
                 fun() -> qlc_select(select(Ctxt, MS, NObjs)) end;
             _ ->
                 erlang:error(badarg, [Ctxt,Opts])
         end,
    InfoFun = fun(indices) -> [2];
                 (is_unique_objects) -> is_unique(Ctxt);
                 (keypos) -> 1;
                 (is_sorted_key) -> true;
                 (num_of_objects) ->
                      %% this is just a guesstimate.
                      trunc(ets:info(?TAB,size) / 2.5)
              end,
    LookupFun =
        case Traverse of
            {select, _MS} -> undefined;
            _ -> fun(Pos, Ks) -> qlc_lookup(Ctxt, Pos, Ks) end
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
            [{Key,Pid,V}] ++ fun() -> qlc_next(Scope, next(Scope, K)) end;
        [] ->
            qlc_next(Scope, next(Scope, K))
    end.

qlc_prev(_, '$end_of_table') -> [];
qlc_prev(Scope, K) ->
    case ets:lookup(?TAB, K) of
        [{{Key,_},Pid,V}] ->
            [{Key,Pid,V}] ++ fun() -> qlc_prev(Scope, prev(Scope, K)) end;
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


%% =============== EUNIT tests

reg_test_() ->
    {setup,
     fun() ->
             application:start(gproc)
     end,
     fun(_) ->
             application:stop(gproc)
     end,
     [
      {spawn, ?_test(t_simple_reg())}
      , ?_test(t_is_clean())
      , {spawn, ?_test(t_simple_prop())}
      , ?_test(t_is_clean())
      , {spawn, ?_test(t_await())}
      , ?_test(t_is_clean())
      , {spawn, ?_test(t_simple_mreg())}
      , ?_test(t_is_clean())
      , {spawn, ?_test(t_gproc_crash())}
      , ?_test(t_is_clean())
     ]}.

t_simple_reg() ->
    ?assert(gproc:reg({n,l,name}) =:= true),
    ?assert(gproc:where({n,l,name}) =:= self()),
    ?assert(gproc:unreg({n,l,name}) =:= true),
    ?assert(gproc:where({n,l,name}) =:= undefined).


                       
t_simple_prop() ->
    ?assert(gproc:reg({p,l,prop}) =:= true),
    ?assert(t_other_proc(fun() ->
                                 ?assert(gproc:reg({p,l,prop}) =:= true)
                         end) =:= ok),
    ?assert(gproc:unreg({p,l,prop}) =:= true).

t_other_proc(F) ->
    {_Pid,Ref} = spawn_monitor(fun() -> exit(F()) end),
    receive
        {'DOWN',Ref,_,_,R} ->
            R
    after 10000 ->
            erlang:error(timeout)
    end.

t_await() ->
    Me = self(),
    {_Pid,Ref} = spawn_monitor(
                   fun() -> exit(?assert(gproc:await({n,l,t_await}) =:= {Me,val})) end),
    ?assert(gproc:reg({n,l,t_await},val) =:= true),
    receive
        {'DOWN', Ref, _, _, R} ->
            ?assertEqual(R, ok)
    after 10000 ->
            erlang:error(timeout)
    end.

t_is_clean() ->
    sys:get_status(gproc), % in order to synch
    T = ets:tab2list(gproc),
    ?assert(T =:= []).
                                        

t_simple_mreg() ->
    ok.


t_gproc_crash() ->
    P = spawn_helper(),
    ?assert(gproc:where({n,l,P}) =:= P),
    exit(whereis(gproc), kill),
    give_gproc_some_time(100),
    ?assert(whereis(gproc) =/= undefined),
    %%
    %% Check that the registration is still there using an ets:lookup(),
    %% Once we've killed the process, gproc will always return undefined
    %% if the process is not alive, regardless of whether the registration
    %% is still there. So, here, the lookup should find something...
    %%
    ?assert(ets:lookup(gproc,{{n,l,P},n}) =/= []),
    ?assert(gproc:where({n,l,P}) =:= P),
    exit(P, kill),
    %% ...and here, it shouldn't.
    %% (sleep for a while first to let gproc handle the EXIT
    give_gproc_some_time(10),
    ?assert(ets:lookup(gproc,{{n,l,P},n}) =:= []).

    
spawn_helper() ->
    Parent = self(),
    P = spawn(fun() ->
		      ?assert(gproc:reg({n,l,self()}) =:= true),
		      Ref = erlang:monitor(process, Parent),
		      Parent ! {ok,self()},
		      receive 
			  {'DOWN', Ref, _, _, _} ->
			      ok
		      end
	      end),
    receive
	{ok,P} ->
	     P
    end.

give_gproc_some_time(T) ->
    timer:sleep(T),
    sys:get_status(gproc).
