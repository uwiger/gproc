Module gproc_lib
================


<h1>Module gproc_lib</h1>

* [Description](#description)
* [Function Index](#index)
* [Function Details](#functions)


Extended process registry.



__Authors:__ Ulf Wiger ([`ulf.wiger@ericsson.com`](mailto:ulf.wiger@ericsson.com)).

<h2><a name="description">Description</a></h2>



This module implements an extended process registry


For a detailed description, see gproc/doc/erlang07-wiger.pdf.

<h2><a name="index">Function Index</a></h2>



<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#await-3">await/3</a></td><td></td></tr><tr><td valign="top"><a href="#do_set_counter_value-3">do_set_counter_value/3</a></td><td></td></tr><tr><td valign="top"><a href="#do_set_value-3">do_set_value/3</a></td><td></td></tr><tr><td valign="top"><a href="#ensure_monitor-2">ensure_monitor/2</a></td><td></td></tr><tr><td valign="top"><a href="#insert_many-4">insert_many/4</a></td><td></td></tr><tr><td valign="top"><a href="#insert_reg-4">insert_reg/4</a></td><td></td></tr><tr><td valign="top"><a href="#remove_many-4">remove_many/4</a></td><td></td></tr><tr><td valign="top"><a href="#remove_reg-2">remove_reg/2</a></td><td></td></tr><tr><td valign="top"><a href="#update_aggr_counter-3">update_aggr_counter/3</a></td><td></td></tr><tr><td valign="top"><a href="#update_counter-3">update_counter/3</a></td><td></td></tr><tr><td valign="top"><a href="#valid_opts-2">valid_opts/2</a></td><td></td></tr></table>




<h2><a name="functions">Function Details</a></h2>


<a name="await-3"></a>

<h3>await/3</h3>





`await(Key, WPid, From) -> any()`

<a name="do_set_counter_value-3"></a>

<h3>do_set_counter_value/3</h3>





`do_set_counter_value(Key, Value, Pid) -> any()`

<a name="do_set_value-3"></a>

<h3>do_set_value/3</h3>





`do_set_value(Key, Value, Pid) -> any()`

<a name="ensure_monitor-2"></a>

<h3>ensure_monitor/2</h3>





`ensure_monitor(Pid, Scope) -> any()`

<a name="insert_many-4"></a>

<h3>insert_many/4</h3>





<pre>insert_many(T::<a href="#type-type">type()</a>, Scope::<a href="#type-scope">scope()</a>, KVL::[{<a href="#type-key">key()</a>, any()}], Pid::pid()) -> {true, list()} | false</pre>
<br></br>


<a name="insert_reg-4"></a>

<h3>insert_reg/4</h3>





<pre>insert_reg(K::<a href="#type-key">key()</a>, Value::any(), Pid::pid(), Scope::<a href="#type-scope">scope()</a>) -> boolean()</pre>
<br></br>


<a name="remove_many-4"></a>

<h3>remove_many/4</h3>





`remove_many(T, Scope, L, Pid) -> any()`

<a name="remove_reg-2"></a>

<h3>remove_reg/2</h3>





`remove_reg(Key, Pid) -> any()`

<a name="update_aggr_counter-3"></a>

<h3>update_aggr_counter/3</h3>





`update_aggr_counter(C, N, Val) -> any()`

<a name="update_counter-3"></a>

<h3>update_counter/3</h3>





`update_counter(Key, Incr, Pid) -> any()`

<a name="valid_opts-2"></a>

<h3>valid_opts/2</h3>





`valid_opts(Type, Default) -> any()`

