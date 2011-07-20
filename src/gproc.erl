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
%% This module implements an extended process registry
%%
%% For a detailed description, see
%% <a href="erlang07-wiger.pdf">erlang07-wiger.pdf</a>.
%%
%% <h2>Tuning Gproc performance</h2>
%%
%% Gproc relies on a central server and an ordered-set ets table.
%% Effort is made to perform as much work as possible in the client without
%% sacrificing consistency. A few things can be tuned by setting the following
%% application environment variables in the top application of `gproc'
%% (usually `gproc'):
%%
%% * `{ets_options, list()}' - Currently, the options `{write_concurrency, F}'
%%   and `{read_concurrency, F}' are allowed. The default is
%%   `[{write_concurrency, true}, {read_concurrency, true}]'
%% * `{server_options, list()}' - These will be passed as spawn options when 
%%   starting the `gproc' and `gproc_dist' servers. Default is `[]'. It is 
%%   likely that `{priority, high | max}' and/or increasing `min_heap_size'
%%   will improve performance.
%%
%% @end

%% @type type()  = n | p | c | a. n = name; p = property; c = counter;
%%                                a = aggregate_counter
%% @type scope() = l | g. l = local registration; g = global registration
%%
%% @type reg_id() = {type(), scope(), any()}.
%% @type unique_id() = {n | a, scope(), any()}.
%%
%% @type sel_scope() = scope | all | global | local.
%% @type sel_type() = type() | names | props | counters | aggr_counters.
%% @type context() = {scope(), type()} | type(). {'all','all'} is the default
%%
%% @type headpat() = {keypat(),pidpat(),ValPat}.
%% @type keypat() = {sel_type() | sel_var(),
%%                   l | g | sel_var(),
%%                   any()}.
%% @type pidpat() = pid() | sel_var().
%% sel_var() = DollarVar | '_'.
%% @type sel_pattern() = [{headpat(), Guards, Prod}].
%% @type key()   = {type(), scope(), any()}.

-module(gproc).
-behaviour(gen_server).

-export([start_link/0,
         reg/1, reg/2, unreg/1,
         mreg/3,
         munreg/3,
         set_value/2,
         get_value/1,
         where/1,
         await/1, await/2,
         nb_wait/1,
         cancel_wait/2,
         lookup_pid/1,
         lookup_pids/1,
         lookup_value/1,
         lookup_values/1,
         update_counter/2,
         give_away/2,
         send/2,
         info/1, info/2,
         select/1, select/2, select/3,
         select_count/1, select_count/2,
         first/1,
         next/2,
         prev/2,
         last/1,
         table/1, table/2]).

%% Environment handling
-export([get_env/3, get_env/4,
         get_set_env/3, get_set_env/4,
         set_env/5]).

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

%% Callbacks for behaviour support
-export([whereis_name/1,
         unregister_name/1]).

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
    _ = create_tabs(),
    SpawnOpts = gproc_lib:valid_opts(server_options, []),
    gen_server:start_link({local, ?SERVER}, ?MODULE, [],
			  [{spawn_opt, SpawnOpts}]).

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

%% @spec get_env(Scope::scope(), App::atom(), Key::atom()) -> term()
%% @equiv get_env(Scope, App, Key, [app_env])
get_env(Scope, App, Key) ->
    get_env(Scope, App, Key, [app_env]).

%% @spec (Scope::scope(), App::atom(), Key::atom(), Strategy) -> term()
%%   Strategy = [Alternative]
%%   Alternative = app_env
%%               | os_env
%%               | inherit | {inherit, pid()} | {inherit, unique_id()}
%%               | init_arg
%%               | {mnesia, ActivityType, Oid, Pos}
%%               | {default, term()}
%%               | error
%% @doc Read an environment value, potentially cached as a `gproc_env' property.
%%
%% This function first tries to read the value of a cached property,
%% `{p, Scope, {gproc_env, App, Key}}'. If this fails, it will try the provided
%% alternative strategy. `Strategy' is a list of alternatives, tried in order.
%% Each alternative can be one of:
%%
%% * `app_env' - try `application:get_env(App, Key)'
%% * `os_env' - try `os:getenv(ENV)', where `ENV' is `Key' converted into an
%%   uppercase string
%% * `{os_env, ENV}' - try `os:getenv(ENV)'
%% * `inherit' - inherit the cached value, if any, held by the parent process.
%% * `{inherit, Pid}' - inherit the cached value, if any, held by `Pid'.
%% * `{inherit, Id}' - inherit the cached value, if any, held by the process
%%    registered in `gproc' as `Id'.
%% * `init_arg' - try `init:get_argument(Key)'; expects a single value, if any.
%% * `{mnesia, ActivityType, Oid, Pos}' - try
%%   `mnesia:activity(ActivityType, fun() -> mnesia:read(Oid) end)'; retrieve
%%    the value in position `Pos' if object found.
%% * `{default, Value}' - set a default value to return once alternatives have
%%    been exhausted; if not set, `undefined' will be returned.
%% * `error' - raise an exception, `erlang:error(gproc_env, [App, Key, Scope])'.
%%
%% While any alternative can occur more than once, the only one that might make
%% sense to use multiple times is `{default, Value}'.
%%
%% The return value will be one of:
%%
%% * The value of the first matching alternative, or `error' eception,
%%   whichever comes first
%% * The last instance of `{default, Value}', or `undefined', if there is no
%%   matching alternative, default or `error' entry in the list.
%%
%% The `error' option can be used to assert that a value has been previously
%% cached. Alternatively, it can be used to assert that a value is either cached
%% or at least defined somewhere,
%% e.g. `get_env(l, mnesia, dir, [app_env, error])'.
%% @end
get_env(Scope, App, Key, Strategy)
  when Scope==l, is_atom(App), is_atom(Key);
       Scope==g, is_atom(App), is_atom(Key) ->
    do_get_env(Scope, App, Key, Strategy, false).

%% @spec get_set_env(Scope::scope(), App::atom(), Key::atom()) -> term()
%% @equiv get_set_env(Scope, App, Key, [app_env])
get_set_env(Scope, App, Key) ->
    get_set_env(Scope, App, Key, [app_env]).

%% @spec get_set_env(Scope::scope(), App::atom(), Key::atom(), Strategy) ->
%%           Value
%% @doc Fetch and cache an environment value, if not already cached.
%%
%% This function does the same thing as {@link get_env/4}, but also updates the
%% cache. Note that the cache will be updated even if the result of the lookup
%% is `undefined'.
%%
%% @see get_env/4.
%% @end
%%
get_set_env(Scope, App, Key, Strategy)
  when Scope==l, is_atom(App), is_atom(Key);
       Scope==g, is_atom(App), is_atom(Key) ->
    do_get_env(Scope, App, Key, Strategy, true).

do_get_env(Context, App, Key, Alternatives, Set) ->
    case lookup_env(Context, App, Key, self()) of
        undefined ->
            check_alternatives(Alternatives, Context, App, Key, undefined, Set);
        {ok, Value} ->
            Value
    end.

%% @spec set_env(Scope::scope(), App::atom(),
%%               Key::atom(), Value::term(), Strategy) -> Value
%%   Strategy = [Alternative]
%%   Alternative = app_env | os_env | {os_env, VAR}
%%                | {mnesia, ActivityType, Oid, Pos}
%%
%% @doc Updates the cached value as well as underlying environment.
%%
%% This function should be exercised with caution, as it affects the larger
%% environment outside gproc. This function modifies the cached value, and then
%% proceeds to update the underlying environment (OS environment variable or
%% application environment variable).
%%
%% When the `mnesia' alternative is used, gproc will try to update any existing
%% object, changing only the `Pos' position. If no such object exists, it will
%% create a new object, setting any other attributes (except `Pos' and the key)
%% to `undefined'.
%% @end
%%
set_env(Scope, App, Key, Value, Strategy)
  when Scope==l, is_atom(App), is_atom(Key);
       Scope==g, is_atom(App), is_atom(Key) ->
    case is_valid_set_strategy(Strategy, Value) of
        true ->
            update_cached_env(Scope, App, Key, Value),
            set_strategy(Strategy, App, Key, Value);
        false ->
            erlang:error(badarg)
    end.

check_alternatives([{default, Val}|Alts], Scope, App, Key, _, Set) ->
    check_alternatives(Alts, Scope, App, Key, Val, Set);
check_alternatives([H|T], Scope, App, Key, Def, Set) ->
    case try_alternative(H, App, Key, Scope) of
        undefined ->
            check_alternatives(T, Scope, App, Key, Def, Set);
        {ok, Value} ->
            if Set ->
                    cache_env(Scope, App, Key, Value),
                    Value;
               true ->
                    Value
            end
    end;
check_alternatives([], Scope, App, Key, Def, Set) ->
    if Set ->
            cache_env(Scope, App, Key, Def);
       true ->
            ok
    end,
    Def.

try_alternative(error, App, Key, Scope) ->
    erlang:error(gproc_env, [App, Key, Scope]);
try_alternative(inherit, App, Key, Scope) ->
    case get('$ancestors') of
        [P|_] ->
            lookup_env(Scope, App, Key, P);
        _ ->
            undefined
    end;
try_alternative({inherit, P}, App, Key, Scope) when is_pid(P) ->
    lookup_env(Scope, App, Key, P);
try_alternative({inherit, P}, App, Key, Scope) ->
    case where(P) of
        undefined -> undefined;
        Pid when is_pid(Pid) ->
            lookup_env(Scope, App, Key, Pid)
    end;
try_alternative(app_env, App, Key, _Scope) ->
    case application:get_env(App, Key) of
        undefined       -> undefined;
        {ok, undefined} -> undefined;
        {ok, Value}     -> {ok, Value}
    end;
try_alternative(os_env, _App, Key, _) ->
    case os:getenv(os_env_key(Key)) of
        ""  -> undefined;
        Val -> {ok, Val}
    end;
try_alternative({os_env, Key}, _, _, _) ->
    case os:getenv(Key) of
        ""  -> undefined;
        Val -> {ok, Val}
    end;
try_alternative(init_arg, _, Key, _) ->
    case init:get_argument(Key) of
        {ok, [[Value]]} ->
            {ok, Value};
        error ->
            undefined
    end;
try_alternative({mnesia,Type,Key,Pos}, _, _, _) ->
    case mnesia:activity(Type, fun() -> mnesia:read(Key) end) of
        [] -> undefined;
        [Found] ->
            {ok, element(Pos, Found)}
    end.

os_env_key(Key) ->
    string:to_upper(atom_to_list(Key)).

lookup_env(Scope, App, Key, P) ->
    case ets:lookup(?TAB, {{p, Scope, {gproc_env, App, Key}}, P}) of
        [] ->
            undefined;
        [{_, _, Value}] ->
            {ok, Value}
    end.

cache_env(Scope, App, Key, Value) ->
    reg({p, Scope, {gproc_env, App, Key}}, Value).

update_cached_env(Scope, App, Key, Value) ->
    case lookup_env(Scope, App, Key, self()) of
        undefined ->
            cache_env(Scope, App, Key, Value);
        {ok, _} ->
            set_value({p, Scope, {gproc_env, App, Key}}, Value)
    end.

is_valid_set_strategy([os_env|T], Value) ->
    is_string(Value) andalso is_valid_set_strategy(T, Value);
is_valid_set_strategy([{os_env, _}|T], Value) ->
    is_string(Value) andalso is_valid_set_strategy(T, Value);
is_valid_set_strategy([app_env|T], Value) ->
    is_valid_set_strategy(T, Value);
is_valid_set_strategy([{mnesia,_Type,_Oid,_Pos}|T], Value) ->
    is_valid_set_strategy(T, Value);
is_valid_set_strategy([], _) ->
    true;
is_valid_set_strategy(_, _) ->
    false.

set_strategy([H|T], App, Key, Value) ->
    case H of
        app_env ->
            application:set_env(App, Key, Value);
        os_env ->
            os:putenv(os_env_key(Key), Value);
        {os_env, ENV} ->
            os:putenv(ENV, Value);
        {mnesia,Type,Oid,Pos} ->
            mnesia:activity(
              Type,
              fun() ->
                      Rec = case mnesia:read(Oid) of
                                [] ->
                                    {Tab,K} = Oid,
                                    Tag = mnesia:table_info(Tab, record_name),
                                    Attrs = mnesia:table_info(Tab, attributes),
                                    list_to_tuple(
                                      [Tag,K |
                                       [undefined || _ <- tl(Attrs)]]);
                                [Old] ->
                                    Old
                            end,
                      mnesia:write(setelement(Pos, Rec, Value))
              end)
    end,
    set_strategy(T, App, Key, Value);
set_strategy([], _, _, Value) ->
    Value.

is_string(S) ->
    try begin _ = iolist_to_binary(S),
              true
        end
    catch
        error:_ ->
            false
    end.

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
    WRef = case {call({await,Key,self()}, C), C} of
               {{R, {Kg,Pg,Vg}}, g} ->
                   self() ! {gproc, R, registered, {Kg,Pg,Vg}},
                   R;
               {R,_} ->
                   R
           end,
    receive
        {gproc, WRef, registered, {_K, Pid, V}} ->
            _ = case TRef of
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
%% It is also atomic in regard to unique names; either all names are registered
%% or none are.
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

%% @spec munreg(type(), scope(), [Key::any()]) -> true
%%
%% @doc Unregister multiple Key items of a given type and scope.
%%
%% This function is usually more efficient than calling {@link unreg/1}
%% repeatedly.
%% @end
munreg(T, g, L) ->
    ?CHK_DIST,
    gproc_dist:munreg(T, existing(T,g,L));
munreg(T, l, L) when T==a; T==n ->
    if is_list(L) ->
            call({munreg, T, l, existing(T,l,L)});
       true ->
            erlang:error(badarg)
    end;
munreg(p, l, L) ->
    local_munreg(p, existing(p,l,L));
munreg(_, _, _) ->
    erlang:error(badarg).

existing(T,Scope,L) ->
    Keys = if T==p; T==c ->
                   [{{T,Scope,K}, self()} || K <- L];
              T==a; T==n ->
                   [{{T,Scope,K}, T} || K <- L]
           end,
    _ = [case ets:member(?TAB, K) of
             false -> erlang:error(badarg);
             true  -> true
         end || K <- Keys],
    L.


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
                    _ = gproc_lib:remove_reg(Key, self()),
                    true;
                false ->
                    erlang:error(badarg)
            end
    end.

%% @equiv unreg/1
unregister_name(Key) ->
    unreg(Key).

%% @spec (select_pattern()) -> list(sel_object())
%% @doc
%% @equiv select(all, Pat)
%% @end
select(Pat) ->
    select(all, Pat).

%% @spec (Context::context(), Pat::sel_pattern()) -> [{Key, Pid, Value}]
%%
%% @doc Perform a select operation on the process registry.
%%
%% The physical representation in the registry may differ from the above,
%% but the select patterns are transformed appropriately.
%% @end
select(Context, Pat) ->
    ets:select(?TAB, pattern(Pat, Context)).

%% @spec (Context::context(), Pat::sel_patten(), Limit::integer()) ->
%%          [{Key, Pid, Value}]
%% @doc Like {@link select/2} but returns Limit objects at a time.
%%
%% See [http://www.erlang.org/doc/man/ets.html#select-3].
%% @end
select(Context, Pat, Limit) ->
    ets:select(?TAB, pattern(Pat, Context), Limit).


%% @spec (select_pattern()) -> list(sel_object())
%% @doc
%% @equiv select_count(all, Pat)
%% @end
select_count(Pat) ->
    select_count(all, Pat).

%% @spec (Context::context(), Pat::sel_pattern()) -> [{Key, Pid, Value}]
%%
%% @doc Perform a select_count operation on the process registry.
%%
%% The physical representation in the registry may differ from the above,
%% but the select patterns are transformed appropriately.
%% @end
select_count(Context, Pat) ->
    ets: select_count(?TAB, pattern(Pat, Context)).


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

local_munreg(T, L) when T==p; T==c ->
    _ = [gproc_lib:remove_reg({T,l,K}, self()) || K <- L],
    true.

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

%% @spec (Key) -> Value
%% @doc Lookup the value stored with a key.
%%
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

%% @equiv where/1
whereis_name(Key) ->
    where(Key).

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

%% @spec (From::key(), To::pid() | key()) -> undefined | pid()
%%
%% @doc Atomically transfers the key `From' to the process identified by `To'.
%%
%% This function transfers any gproc key (name, property, counter, aggr counter)
%% from one process to another, and returns the pid of the new owner.
%%
%% `To' must be either a pid or a unique name (name or aggregated counter), but
%% does not necessarily have to resolve to an existing process. If there is
%% no process registered with the `To' key, `give_away/2' returns `undefined',
%% and the `From' key is effectively unregistered.
%%
%% It is allowed to give away a key to oneself, but of course, this operation
%% will have no effect.
%%
%% Fails with `badarg' if the calling process does not have a `From' key
%% registered.
%% @end
give_away({_,l,_} = Key, ToPid) when is_pid(ToPid), node(ToPid) == node() ->
    call({give_away, Key, ToPid});
give_away({_,l,_} = Key, {n,l,_} = ToKey) ->
    call({give_away, Key, ToKey});
give_away({_,g,_} = Key, To) ->
    ?CHK_DIST,
    gproc_dist:give_away(Key, To).

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


%% @spec (Context :: context()) -> key() | '$end_of_table'
%%
%% @doc Behaves as ets:first(Tab) for a given type of registration object.
%%
%% See [http://www.erlang.org/doc/man/ets.html#first-1].
%%  The registry behaves as an ordered_set table.
%% @end
%%
first(Context) ->
    {S, T} = get_s_t(Context),
    {HeadPat,_} = headpat({S, T}, '_', '_', '_'),
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
    S1 = if S == '_'; S == l -> m;              % 'm' comes after 'l'
            S == g -> h                         % 'h' comes between 'g' & 'l'
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
    Rev = {Pid,Key},
    case ets:lookup(?TAB, {Key,T}) of
        [{K, Waiters}] ->
            case Waiters -- [{Pid,Ref}] of
                [] ->
                    ets:delete(?TAB, K),
                    ets:delete(?TAB, Rev);
                NewWaiters ->
                    ets:insert(?TAB, {K, NewWaiters}),
                    case lists:keymember(Pid, 1, NewWaiters) of
                        true ->
                            %% should be extremely unlikely
                            ok;
                        false ->
                            %% delete the reverse entry
                            ets:delete(?TAB, Rev)
                    end
            end;
        _ ->
            ignore
    end,
    {noreply, S}.

%% @hidden
handle_call({reg, {_T,l,_} = Key, Val}, {Pid,_}, S) ->
    case try_insert_reg(Key, Val, Pid) of
        true ->
            _ = gproc_lib:ensure_monitor(Pid,l),
            {reply, true, S};
        false ->
            {reply, badarg, S}
    end;
handle_call({unreg, {_,l,_} = Key}, {Pid,_}, S) ->
    case ets:member(?TAB, {Pid,Key}) of
        true ->
            _ = gproc_lib:remove_reg(Key, Pid),
            {reply, true, S};
        false ->
            {reply, badarg, S}
    end;
handle_call({await, {_,l,_} = Key, Pid}, From, S) ->
    %% Passing the pid explicitly is needed when leader_call is used,
    %% since the Pid given as From in the leader is the local gen_leader
    %% instance on the calling node.
    case gproc_lib:await(Key, Pid, From) of
        noreply ->
            {noreply, S};
        {reply, Reply, _} ->
            {reply, Reply, S}
    end;
handle_call({mreg, T, l, L}, {Pid,_}, S) ->
    try gproc_lib:insert_many(T, l, L, Pid) of
        {true,_} -> {reply, true, S};
        false    -> {reply, badarg, S}
    catch
        error:_  -> {reply, badarg, S}
    end;
handle_call({munreg, T, l, L}, {Pid,_}, S) ->
    _ = gproc_lib:remove_many(T, l, L, Pid),
    {reply, true, S};
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
handle_call({give_away, Key, To}, {Pid,_}, S) ->
    Reply = do_give_away(Key, To, Pid),
    {reply, Reply, S};
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
    _ = case ets:select(?TAB, [{{'$1'},[],['$1']}]) of
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
        _  -> Reply
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
    ok = gen_server:call(gproc, {audit_process, Pid}, infinity).


-spec process_is_down(pid()) -> ok.

process_is_down(Pid) when is_pid(Pid) ->
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

do_give_away({T,l,_} = K, To, Pid) when T==n; T==a ->
    Key = {K, T},
    case ets:lookup(?TAB, Key) of
        [{_, Pid, Value}] ->
            %% Pid owns the reg; allowed to give_away
            case pid_to_give_away_to(To) of
                Pid ->
                    %% Give away to ourselves? Why not? We'll allow it,
                    %% but nothing needs to be done.
                    Pid;
                ToPid when is_pid(ToPid) ->
                    ets:insert(?TAB, [{Key, ToPid, Value},
                                      {{ToPid, K}, r}]),
                    ets:delete(?TAB, {Pid, K}),
                    _ = gproc_lib:ensure_monitor(ToPid, l),
                    ToPid;
                undefined ->
                    _ = gproc_lib:remove_reg(K, Pid),
                    undefined
            end;
        _ ->
            badarg
    end;
do_give_away({T,l,_} = K, To, Pid) when T==c; T==p ->
    Key = {K, Pid},
    case ets:lookup(?TAB, Key) of
        [{_, Pid, Value}] ->
            case pid_to_give_away_to(To) of
                ToPid when is_pid(ToPid) ->
                    ToKey = {K, ToPid},
                    case ets:member(?TAB, ToKey) of
                        true ->
                            badarg;
                        false ->
                            ets:insert(?TAB, [{ToKey, ToPid, Value},
                                              {{ToPid, K}, r}]),
                            ets:delete(?TAB, {Pid, K}),
                            ets:delete(?TAB, Key),
                            _ = gproc_lib:ensure_monitor(ToPid, l),
                            ToPid
                    end;
                undefined ->
                    _ = gproc_lib:remove_reg(K, Pid),
                    undefined
            end;
        _ ->
            badarg
    end.


pid_to_give_away_to(P) when is_pid(P), node(P) == node() ->
    P;
pid_to_give_away_to({T,l,_} = Key) when T==n; T==a ->
    case ets:lookup(?TAB, {Key, T}) of
        [{_, Pid, _}] ->
            Pid;
        _ ->
            undefined
    end.

create_tabs() ->
    Opts = gproc_lib:valid_opts(ets_options, [{write_concurrency,true},
					      {read_concurrency, true}]),
    case ets:info(?TAB, name) of
        undefined ->
            ets:new(?TAB, [ordered_set, public, named_table | Opts]);
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
    _ = [erlang:monitor(process,Pid) || Pid <- Pids],
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
    {S, T} = get_s_t(Scope),
    case is_var(Head) of
        {true,_N} ->
            HeadPat = {{{T,S,'_'},'_'},'_','_'},
            Vs = [{Head, obj_prod()}],
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


headpat({S, T}, V1,V2,V3) ->
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

scope('_')    -> '_';
scope(all)    -> '_';
scope(global) -> g;
scope(local)  -> l;
scope(S) when S==l; S==g -> S.

type('_')   -> '_';
type(all)   -> '_';
type(T) when T==n; T==p; T==c; T==a -> T;
type(names) -> n;
type(props) -> p;
type(counters) -> c;
type(aggr_counters) -> a.

rev_keypat(Context) ->
    {S,T} = get_s_t(Context),
    {T,S,'_'}.

get_s_t({S,T}) -> {scope(S), type(T)};
get_s_t(T) when is_atom(T) ->
    {scope(all), type(T)}.

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
table(Context, Opts) ->
    Ctxt = {_, Type} = get_s_t(Context),
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
                 (is_unique_objects) -> is_unique(Type);
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
                              ets:select(?TAB, [{ {{Pid, rev_keypat(Scope)}, r},
                                                  [], ['$_']}]),
                          lists:flatmap(
                            fun({{_,{T,_,_}=K}, r}) ->
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


is_unique(n) -> true;
is_unique(a) -> true;
is_unique(_) -> false.
