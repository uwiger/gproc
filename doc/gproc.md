Module gproc
============


#Module gproc#
* [Description](#description)
* [Data Types](#types)
* [Function Index](#index)
* [Function Details](#functions)
Extended process registry.
__Behaviours:__ [`gen_server`](gen_server.html).
__Authors:__ Ulf Wiger ([`ulf.wiger@erlang-consulting.com`](mailto:ulf.wiger@erlang-consulting.com)).

##<a name="description">Description</a>##
Extended process registry
  
This module implements an extended process registry
  
For a detailed description, see
  [erlang07-wiger.pdf](erlang07-wiger.pdf).
 

##<a name="types">Data Types</a>##

<a name="type-context"></a>


###context()##

`context() = {[scope()](#type-scope), [type()](#type-type)} | [type()](#type-type)`
Local scope is the default
<a name="type-headpat"></a>


###headpat()##

`headpat() = {[keypat()](#type-keypat), [pidpat()](#type-pidpat), ValPat}`
<a name="type-key"></a>


###key()##

`key() = {[type()](#type-type), [scope()](#type-scope), any()}`
<a name="type-keypat"></a>


###keypat()##

`keypat() = {[sel_type()](#type-sel_type) | [sel_var()](#type-sel_var), l | g | [sel_var()](#type-sel_var), any()}`
<a name="type-pidpat"></a>


###pidpat()##

`pidpat() = pid() | [sel_var()](#type-sel_var)`
sel_var() = DollarVar | '_'.
<a name="type-scope"></a>


###scope()##

`scope() = l | g`
l = local registration; g = global registration
<a name="type-sel_pattern"></a>


###sel_pattern()##

`sel_pattern() = [{[headpat()](#type-headpat), Guards, Prod}]`
<a name="type-sel_type"></a>


###sel_type()##

`sel_type() = n | p | c | a | names | props | counters | aggr_counters`
<a name="type-type"></a>


###type()##

`type() = n | p | c | a`
n = name; p = property; c = counter;
                                 a = aggregate_counter

##<a name="index">Function Index</a>##

<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#add_global_aggr_counter-1">add_global_aggr_counter/1</a></td><td>Registers a global (unique) aggregated counter.</td></tr><tr><td valign="top"><a href="#add_global_counter-2">add_global_counter/2</a></td><td>Registers a global (non-unique) counter.</td></tr><tr><td valign="top"><a href="#add_global_name-1">add_global_name/1</a></td><td>Registers a global (unique) name.</td></tr><tr><td valign="top"><a href="#add_global_property-2">add_global_property/2</a></td><td>Registers a global (non-unique) property.</td></tr><tr><td valign="top"><a href="#add_local_aggr_counter-1">add_local_aggr_counter/1</a></td><td>Registers a local (unique) aggregated counter.</td></tr><tr><td valign="top"><a href="#add_local_counter-2">add_local_counter/2</a></td><td>Registers a local (non-unique) counter.</td></tr><tr><td valign="top"><a href="#add_local_name-1">add_local_name/1</a></td><td>Registers a local (unique) name.</td></tr><tr><td valign="top"><a href="#add_local_property-2">add_local_property/2</a></td><td>Registers a local (non-unique) property.</td></tr><tr><td valign="top"><a href="#audit_process-1">audit_process/1</a></td><td></td></tr><tr><td valign="top"><a href="#await-1">await/1</a></td><td>Equivalent to <a href="#await-2"><tt>await(Key, infinity)</tt></a>.</td></tr><tr><td valign="top"><a href="#await-2">await/2</a></td><td>Wait for a local name to be registered.</td></tr><tr><td valign="top"><a href="#cancel_wait-2">cancel_wait/2</a></td><td></td></tr><tr><td valign="top"><a href="#default-1">default/1</a></td><td></td></tr><tr><td valign="top"><a href="#first-1">first/1</a></td><td>Behaves as ets:first(Tab) for a given type of registration object.</td></tr><tr><td valign="top"><a href="#get_value-1">get_value/1</a></td><td>Read the value stored with a key registered to the current process.</td></tr><tr><td valign="top"><a href="#info-1">info/1</a></td><td>Similar to <code>process_info(Pid)</code> but with additional gproc info.</td></tr><tr><td valign="top"><a href="#info-2">info/2</a></td><td>Similar to process_info(Pid, Item), but with additional gproc info.</td></tr><tr><td valign="top"><a href="#last-1">last/1</a></td><td>Behaves as ets:last(Tab) for a given type of registration object.</td></tr><tr><td valign="top"><a href="#lookup_global_aggr_counter-1">lookup_global_aggr_counter/1</a></td><td>Lookup a global (unique) aggregated counter and returns its value.</td></tr><tr><td valign="top"><a href="#lookup_global_counters-1">lookup_global_counters/1</a></td><td>Look up all global (non-unique) instances of a given Counter.</td></tr><tr><td valign="top"><a href="#lookup_global_name-1">lookup_global_name/1</a></td><td>Lookup a global unique name.</td></tr><tr><td valign="top"><a href="#lookup_global_properties-1">lookup_global_properties/1</a></td><td>Look up all global (non-unique) instances of a given Property.</td></tr><tr><td valign="top"><a href="#lookup_local_aggr_counter-1">lookup_local_aggr_counter/1</a></td><td>Lookup a local (unique) aggregated counter and returns its value.</td></tr><tr><td valign="top"><a href="#lookup_local_counters-1">lookup_local_counters/1</a></td><td>Look up all local (non-unique) instances of a given Counter.</td></tr><tr><td valign="top"><a href="#lookup_local_name-1">lookup_local_name/1</a></td><td>Lookup a local unique name.</td></tr><tr><td valign="top"><a href="#lookup_local_properties-1">lookup_local_properties/1</a></td><td>Look up all local (non-unique) instances of a given Property.</td></tr><tr><td valign="top"><a href="#lookup_pid-1">lookup_pid/1</a></td><td>Lookup the Pid stored with a key.</td></tr><tr><td valign="top"><a href="#lookup_pids-1">lookup_pids/1</a></td><td>Returns a list of pids with the published key Key.</td></tr><tr><td valign="top"><a href="#lookup_values-1">lookup_values/1</a></td><td>Retrieve the <code>{Pid,Value}</code> pairs corresponding to Key.</td></tr><tr><td valign="top"><a href="#mreg-3">mreg/3</a></td><td>Register multiple {Key,Value} pairs of a given type and scope.</td></tr><tr><td valign="top"><a href="#nb_wait-1">nb_wait/1</a></td><td>Wait for a local name to be registered.</td></tr><tr><td valign="top"><a href="#next-2">next/2</a></td><td>Behaves as ets:next(Tab,Key) for a given type of registration object.</td></tr><tr><td valign="top"><a href="#prev-2">prev/2</a></td><td>Behaves as ets:prev(Tab,Key) for a given type of registration object.</td></tr><tr><td valign="top"><a href="#reg-1">reg/1</a></td><td>Equivalent to <a href="#reg-2"><tt>reg(Key, default(Key))</tt></a>.</td></tr><tr><td valign="top"><a href="#reg-2">reg/2</a></td><td>Register a name or property for the current process.</td></tr><tr><td valign="top"><a href="#select-1">select/1</a></td><td>Equivalent to <a href="#select-2"><tt>select(all, Pat)</tt></a>.</td></tr><tr><td valign="top"><a href="#select-2">select/2</a></td><td>Perform a select operation on the process registry.</td></tr><tr><td valign="top"><a href="#select-3">select/3</a></td><td>Like <a href="#select-2"><code>select/2</code></a> but returns Limit objects at a time.</td></tr><tr><td valign="top"><a href="#send-2">send/2</a></td><td>Sends a message to the process, or processes, corresponding to Key.</td></tr><tr><td valign="top"><a href="#set_value-2">set_value/2</a></td><td>Sets the value of the registeration entry given by Key.</td></tr><tr><td valign="top"><a href="#start_link-0">start_link/0</a></td><td>Starts the gproc server.</td></tr><tr><td valign="top"><a href="#table-1">table/1</a></td><td>Equivalent to <a href="#table-2"><tt>table(Context, [])</tt></a>.</td></tr><tr><td valign="top"><a href="#table-2">table/2</a></td><td>QLC table generator for the gproc registry.</td></tr><tr><td valign="top"><a href="#unreg-1">unreg/1</a></td><td>Unregister a name or property.</td></tr><tr><td valign="top"><a href="#update_counter-2">update_counter/2</a></td><td>Updates the counter registered as Key for the current process.</td></tr><tr><td valign="top"><a href="#where-1">where/1</a></td><td>Returns the pid registered as Key.</td></tr></table>

<a name="functions"></a>


##Function Details##

<a name="add_global_aggr_counter-1"></a>


###add_global_aggr_counter/1##


`add_global_aggr_counter(Name) -> any()`

Equivalent to [`reg({a, g, Name})`](#reg-1).
Registers a global (unique) aggregated counter.
<a name="add_global_counter-2"></a>


###add_global_counter/2##


`add_global_counter(Name, Initial) -> any()`

Registers a global (non-unique) counter. @equiv reg({c,g,Name},Value)
<a name="add_global_name-1"></a>


###add_global_name/1##


`add_global_name(Name) -> any()`

Registers a global (unique) name. @equiv reg({n,g,Name})
<a name="add_global_property-2"></a>


###add_global_property/2##


`add_global_property(Name, Value) -> any()`

Registers a global (non-unique) property. @equiv reg({p,g,Name},Value)
<a name="add_local_aggr_counter-1"></a>


###add_local_aggr_counter/1##


`add_local_aggr_counter(Name) -> any()`

Equivalent to [`reg({a, l, Name})`](#reg-1).
Registers a local (unique) aggregated counter.
<a name="add_local_counter-2"></a>


###add_local_counter/2##


`add_local_counter(Name, Initial) -> any()`

Registers a local (non-unique) counter. @equiv reg({c,l,Name},Value)
<a name="add_local_name-1"></a>


###add_local_name/1##


`add_local_name(Name) -> any()`

Registers a local (unique) name. @equiv reg({n,l,Name})
<a name="add_local_property-2"></a>


###add_local_property/2##


`add_local_property(Name, Value) -> any()`

Registers a local (non-unique) property. @equiv reg({p,l,Name},Value)
<a name="audit_process-1"></a>


###audit_process/1##


`audit_process(Pid) -> any()`

<a name="await-1"></a>


###await/1##


`await(Key::[key()](#type-key)) -> {pid(), Value}`

Equivalent to [`await(Key, infinity)`](#await-2).
<a name="await-2"></a>


###await/2##


`await(Key::[key()](#type-key), Timeout) -> {pid(), Value}`* `Timeout = integer() | infinity`


Wait for a local name to be registered.
  The function raises an exception if the timeout expires. Timeout must be
  either an interger > 0 or 'infinity'.
  A small optimization: we first perform a lookup, to see if the name
  is already registered. This way, the cost of the operation will be
  roughly the same as of where/1 in the case where the name is already
  registered (the difference: await/2 also returns the value).
<a name="cancel_wait-2"></a>


###cancel_wait/2##


`cancel_wait(Key, Ref) -> any()`

<a name="default-1"></a>


###default/1##


`default(X1) -> any()`

<a name="first-1"></a>


###first/1##


`first(Type::[type()](#type-type)) -> [key()](#type-key) | '$end_of_table'`


Behaves as ets:first(Tab) for a given type of registration object.
 
  See [`http://www.erlang.org/doc/man/ets.html#first-1`](http://www.erlang.org/doc/man/ets.html#first-1).
   The registry behaves as an ordered_set table.
<a name="get_value-1"></a>


###get_value/1##


`get_value(Key) -> Value`


Read the value stored with a key registered to the current process.
 
  If no such key is registered to the current process, this function exits.
<a name="info-1"></a>


###info/1##


`info(Pid::pid()) -> ProcessInfo`* `ProcessInfo = [{gproc, [{Key, Value}]} | ProcessInfo]`



Similar to `process_info(Pid)` but with additional gproc info.
 
  Returns the same information as process_info(Pid), but with the
  addition of a `gproc` information item, containing the `{Key,Value}`
  pairs registered to the process.
<a name="info-2"></a>


###info/2##


`info(Pid::pid(), Item::atom()) -> {Item, Info}`


Similar to process_info(Pid, Item), but with additional gproc info.
 
  For `Item = gproc`, this function returns a list of `{Key, Value}` pairs
  registered to the process Pid. For other values of Item, it returns the
  same as [`http://www.erlang.org/doc/man/erlang.html#process_info-2`](http://www.erlang.org/doc/man/erlang.html#process_info-2).
<a name="last-1"></a>


###last/1##


`last(Context::[context()](#type-context)) -> [key()](#type-key) | '$end_of_table'`


Behaves as ets:last(Tab) for a given type of registration object.
 
  See [`http://www.erlang.org/doc/man/ets.html#last-1`](http://www.erlang.org/doc/man/ets.html#last-1).
  The registry behaves as an ordered_set table.
<a name="lookup_global_aggr_counter-1"></a>


###lookup_global_aggr_counter/1##


`lookup_global_aggr_counter(Name::any()) -> integer()`

Equivalent to [`where({a, g, Name})`](#where-1).
Lookup a global (unique) aggregated counter and returns its value.
  Fails if there is no such object.
<a name="lookup_global_counters-1"></a>


###lookup_global_counters/1##


`lookup_global_counters(Counter::any()) -> [{pid(), Value::integer()}]`

Equivalent to [`lookup_values({c, g, Counter})`](#lookup_values-1).
Look up all global (non-unique) instances of a given Counter.
  Returns a list of {Pid, Value} tuples for all matching objects.
<a name="lookup_global_name-1"></a>


###lookup_global_name/1##


`lookup_global_name(Name::any()) -> pid()`

Equivalent to [`where({n, g, Name})`](#where-1).
Lookup a global unique name. Fails if there is no such name.
<a name="lookup_global_properties-1"></a>


###lookup_global_properties/1##


`lookup_global_properties(Property::any()) -> [{pid(), Value}]`

Equivalent to [`lookup_values({p, g, Property})`](#lookup_values-1).
Look up all global (non-unique) instances of a given Property.
  Returns a list of {Pid, Value} tuples for all matching objects.
<a name="lookup_local_aggr_counter-1"></a>


###lookup_local_aggr_counter/1##


`lookup_local_aggr_counter(Name::any()) -> integer()`

Equivalent to [`where({a, l, Name})`](#where-1).
Lookup a local (unique) aggregated counter and returns its value.
  Fails if there is no such object.
<a name="lookup_local_counters-1"></a>


###lookup_local_counters/1##


`lookup_local_counters(Counter::any()) -> [{pid(), Value::integer()}]`

Equivalent to [`lookup_values({c, l, Counter})`](#lookup_values-1).
Look up all local (non-unique) instances of a given Counter.
  Returns a list of {Pid, Value} tuples for all matching objects.
<a name="lookup_local_name-1"></a>


###lookup_local_name/1##


`lookup_local_name(Name::any()) -> pid()`

Equivalent to [`where({n, l, Name})`](#where-1).
Lookup a local unique name. Fails if there is no such name.
<a name="lookup_local_properties-1"></a>


###lookup_local_properties/1##


`lookup_local_properties(Property::any()) -> [{pid(), Value}]`

Equivalent to [`lookup_values({p, l, Property})`](#lookup_values-1).
Look up all local (non-unique) instances of a given Property.
  Returns a list of {Pid, Value} tuples for all matching objects.
<a name="lookup_pid-1"></a>


###lookup_pid/1##


`lookup_pid(Key) -> Pid`

Lookup the Pid stored with a key.
 
<a name="lookup_pids-1"></a>


###lookup_pids/1##


`lookup_pids(Key::[key()](#type-key)) -> [pid()]`


Returns a list of pids with the published key Key
 
  If the type of registration entry is either name or aggregated counter,
  this function will return either an empty list, or a list of one pid.
  For non-unique types, the return value can be a list of any length.
<a name="lookup_values-1"></a>


###lookup_values/1##


`lookup_values(Key::[key()](#type-key)) -> [{pid(), Value}]`


Retrieve the `{Pid,Value}` pairs corresponding to Key.
 
  Key refer to any type of registry object. If it refers to a unique
  object, the list will be of length 0 or 1. If it refers to a non-unique
  object, the return value can be a list of any length.
<a name="mreg-3"></a>


###mreg/3##


`mreg(T::[type()](#type-type), X2::[scope()](#type-scope), KVL::[{Key::any(), Value::any()}]) -> true`


Register multiple {Key,Value} pairs of a given type and scope.
 
  This function is more efficient than calling [`reg/2`](#reg-2) repeatedly.
<a name="nb_wait-1"></a>


###nb_wait/1##


`nb_wait(Key::[key()](#type-key)) -> Ref`

Wait for a local name to be registered.
  The caller can expect to receive a message,
  {gproc, Ref, registered, {Key, Pid, Value}}, once the name is registered.
<a name="next-2"></a>


###next/2##


`next(Context::[context()](#type-context), Key::[key()](#type-key)) -> [key()](#type-key) | '$end_of_table'`


Behaves as ets:next(Tab,Key) for a given type of registration object.
 
  See [`http://www.erlang.org/doc/man/ets.html#next-2`](http://www.erlang.org/doc/man/ets.html#next-2).
  The registry behaves as an ordered_set table.
<a name="prev-2"></a>


###prev/2##


`prev(Context::[context()](#type-context), Key::[key()](#type-key)) -> [key()](#type-key) | '$end_of_table'`


Behaves as ets:prev(Tab,Key) for a given type of registration object.
 
  See [`http://www.erlang.org/doc/man/ets.html#prev-2`](http://www.erlang.org/doc/man/ets.html#prev-2).
  The registry behaves as an ordered_set table.
<a name="reg-1"></a>


###reg/1##


`reg(Key::[key()](#type-key)) -> true`

Equivalent to [`reg(Key, default(Key))`](#reg-2).
<a name="reg-2"></a>


###reg/2##


`reg(Key::[key()](#type-key), Value) -> true`


Register a name or property for the current process
 
 
<a name="select-1"></a>


###select/1##


`select(Pat::[select_pattern()](#type-select_pattern)) -> list([sel_object()](#type-sel_object))`

Equivalent to [`select(all, Pat)`](#select-2).
<a name="select-2"></a>


###select/2##


`select(Type::[sel_type()](#type-sel_type), Pat::[sel_pattern()](#type-sel_pattern)) -> [{Key, Pid, Value}]`


Perform a select operation on the process registry.
 
  The physical representation in the registry may differ from the above,
  but the select patterns are transformed appropriately.
<a name="select-3"></a>


###select/3##


`select(Type::[sel_type()](#type-sel_type), Pat::[sel_patten()](#type-sel_patten), Limit::integer()) -> [{Key, Pid, Value}]`


Like [`select/2`](#select-2) but returns Limit objects at a time.
 
  See [`http://www.erlang.org/doc/man/ets.html#select-3`](http://www.erlang.org/doc/man/ets.html#select-3).
<a name="send-2"></a>


###send/2##


`send(Key::[key()](#type-key), Msg::any()) -> Msg`


Sends a message to the process, or processes, corresponding to Key.
 
  If Key belongs to a unique object (name or aggregated counter), this
  function will send a message to the corresponding process, or fail if there
  is no such process. If Key is for a non-unique object type (counter or
  property), Msg will be send to all processes that have such an object.
<a name="set_value-2"></a>


###set_value/2##


`set_value(Key::[key()](#type-key), Value) -> true`


Sets the value of the registeration entry given by Key
 
  
Key is assumed to exist and belong to the calling process.  
If it doesn't, this function will exit.
 
  Value can be any term, unless the object is a counter, in which case
  it must be an integer.
<a name="start_link-0"></a>


###start_link/0##


`start_link() -> {ok, pid()}`


Starts the gproc server.
 
  This function is intended to be called from gproc_sup, as part of
  starting the gproc application.
<a name="table-1"></a>


###table/1##


`table(Context::[context()](#type-context)) -> any()`

Equivalent to [`table(Context, [])`](#table-2).
<a name="table-2"></a>


###table/2##


`table(Context::[context()](#type-context), Opts) -> any()`

QLC table generator for the gproc registry.
  Context specifies which subset of the registry should be queried.
  See [`http://www.erlang.org/doc/man/qlc.html`](http://www.erlang.org/doc/man/qlc.html).
<a name="unreg-1"></a>


###unreg/1##


`unreg(Key::[key()](#type-key)) -> true`

Unregister a name or property.
<a name="update_counter-2"></a>


###update_counter/2##


`update_counter(Key::[key()](#type-key), Incr::integer()) -> integer()`


Updates the counter registered as Key for the current process.
 
  This function works like ets:update_counter/3
  (see [`http://www.erlang.org/doc/man/ets.html#update_counter-3`](http://www.erlang.org/doc/man/ets.html#update_counter-3)), but
  will fail if the type of object referred to by Key is not a counter.
<a name="where-1"></a>


###where/1##


`where(Key::[key()](#type-key)) -> pid()`


Returns the pid registered as Key
 
  The type of registration entry must be either name or aggregated counter.
  Otherwise this function will exit. Use [`lookup_pids/1`](#lookup_pids-1) in these
  cases.
_Generated by EDoc, Oct 22 2010, 19:32:29._