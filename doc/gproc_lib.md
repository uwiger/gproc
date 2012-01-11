

#Module gproc_lib#
* [Description](#description)
* [Function Index](#index)
* [Function Details](#functions)


Extended process registry.



__Authors:__ Ulf Wiger ([`ulf.wiger@ericsson.com`](mailto:ulf.wiger@ericsson.com)).<a name="description"></a>

##Description##


This module implements an extended process registry


For a detailed description, see gproc/doc/erlang07-wiger.pdf.<a name="index"></a>

##Function Index##


<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#add_monitor-3">add_monitor/3</a></td><td></td></tr><tr><td valign="top"><a href="#await-3">await/3</a></td><td></td></tr><tr><td valign="top"><a href="#do_set_counter_value-3">do_set_counter_value/3</a></td><td></td></tr><tr><td valign="top"><a href="#do_set_value-3">do_set_value/3</a></td><td></td></tr><tr><td valign="top"><a href="#ensure_monitor-2">ensure_monitor/2</a></td><td></td></tr><tr><td valign="top"><a href="#insert_many-4">insert_many/4</a></td><td></td></tr><tr><td valign="top"><a href="#insert_reg-4">insert_reg/4</a></td><td></td></tr><tr><td valign="top"><a href="#notify-2">notify/2</a></td><td></td></tr><tr><td valign="top"><a href="#notify-3">notify/3</a></td><td></td></tr><tr><td valign="top"><a href="#remove_many-4">remove_many/4</a></td><td></td></tr><tr><td valign="top"><a href="#remove_monitor-3">remove_monitor/3</a></td><td></td></tr><tr><td valign="top"><a href="#remove_monitors-3">remove_monitors/3</a></td><td></td></tr><tr><td valign="top"><a href="#remove_reg-3">remove_reg/3</a></td><td></td></tr><tr><td valign="top"><a href="#remove_reg-4">remove_reg/4</a></td><td></td></tr><tr><td valign="top"><a href="#remove_reverse_mapping-3">remove_reverse_mapping/3</a></td><td></td></tr><tr><td valign="top"><a href="#remove_wait-4">remove_wait/4</a></td><td></td></tr><tr><td valign="top"><a href="#update_aggr_counter-3">update_aggr_counter/3</a></td><td></td></tr><tr><td valign="top"><a href="#update_counter-3">update_counter/3</a></td><td></td></tr><tr><td valign="top"><a href="#valid_opts-2">valid_opts/2</a></td><td></td></tr></table>


<a name="functions"></a>

##Function Details##

<a name="add_monitor-3"></a>

###add_monitor/3##




`add_monitor(T, Pid, Ref) -> any()`

<a name="await-3"></a>

###await/3##




`await(Key, WPid, From) -> any()`

<a name="do_set_counter_value-3"></a>

###do_set_counter_value/3##




`do_set_counter_value(Key, Value, Pid) -> any()`

<a name="do_set_value-3"></a>

###do_set_value/3##




`do_set_value(Key, Value, Pid) -> any()`

<a name="ensure_monitor-2"></a>

###ensure_monitor/2##




`ensure_monitor(Pid, Scope) -> any()`

<a name="insert_many-4"></a>

###insert_many/4##




<pre>insert_many(T::<a href="#type-type">type()</a>, Scope::<a href="#type-scope">scope()</a>, KVL::[{<a href="#type-key">key()</a>, any()}], Pid::pid()) -> {true, list()} | false</pre>
<br></br>


<a name="insert_reg-4"></a>

###insert_reg/4##




<pre>insert_reg(K::<a href="#type-key">key()</a>, Value::any(), Pid::pid() | shared, Scope::<a href="#type-scope">scope()</a>) -> boolean()</pre>
<br></br>


<a name="notify-2"></a>

###notify/2##




`notify(Key, Opts) -> any()`

<a name="notify-3"></a>

###notify/3##




`notify(Event, Key, Opts) -> any()`

<a name="remove_many-4"></a>

###remove_many/4##




`remove_many(T, Scope, L, Pid) -> any()`

<a name="remove_monitor-3"></a>

###remove_monitor/3##




`remove_monitor(T, Pid, Ref) -> any()`

<a name="remove_monitors-3"></a>

###remove_monitors/3##




`remove_monitors(Key, Pid, MPid) -> any()`

<a name="remove_reg-3"></a>

###remove_reg/3##




`remove_reg(Key, Pid, Event) -> any()`

<a name="remove_reg-4"></a>

###remove_reg/4##




`remove_reg(Key, Pid, Event, Opts) -> any()`

<a name="remove_reverse_mapping-3"></a>

###remove_reverse_mapping/3##




`remove_reverse_mapping(Event, Pid, Key) -> any()`

<a name="remove_wait-4"></a>

###remove_wait/4##




`remove_wait(Key, Pid, Ref, Waiters) -> any()`

<a name="update_aggr_counter-3"></a>

###update_aggr_counter/3##




`update_aggr_counter(C, N, Val) -> any()`

<a name="update_counter-3"></a>

###update_counter/3##




`update_counter(Key, Incr, Pid) -> any()`

<a name="valid_opts-2"></a>

###valid_opts/2##




`valid_opts(Type, Default) -> any()`

