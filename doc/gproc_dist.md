Module gproc_dist
=================


<h1>Module gproc_dist</h1>

* [Description](#description)
* [Function Index](#index)
* [Function Details](#functions)


Extended process registry.



__Behaviours:__ [`gen_leader`](/Users/uwiger/ETC/git/gproc/deps/gen_leader/doc/gen_leader.md).

__Authors:__ Ulf Wiger ([`ulf.wiger@erlang-solutions.com`](mailto:ulf.wiger@erlang-solutions.com)).

<h2><a name="description">Description</a></h2>



This module implements an extended process registry


For a detailed description, see gproc/doc/erlang07-wiger.pdf.

<h2><a name="index">Function Index</a></h2>



<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#code_change-4">code_change/4</a></td><td></td></tr><tr><td valign="top"><a href="#elected-2">elected/2</a></td><td></td></tr><tr><td valign="top"><a href="#elected-3">elected/3</a></td><td></td></tr><tr><td valign="top"><a href="#from_leader-3">from_leader/3</a></td><td></td></tr><tr><td valign="top"><a href="#get_leader-0">get_leader/0</a></td><td>Returns the node of the current gproc leader.</td></tr><tr><td valign="top"><a href="#give_away-2">give_away/2</a></td><td></td></tr><tr><td valign="top"><a href="#handle_DOWN-3">handle_DOWN/3</a></td><td></td></tr><tr><td valign="top"><a href="#handle_call-4">handle_call/4</a></td><td></td></tr><tr><td valign="top"><a href="#handle_cast-3">handle_cast/3</a></td><td></td></tr><tr><td valign="top"><a href="#handle_info-2">handle_info/2</a></td><td></td></tr><tr><td valign="top"><a href="#handle_leader_call-4">handle_leader_call/4</a></td><td></td></tr><tr><td valign="top"><a href="#handle_leader_cast-3">handle_leader_cast/3</a></td><td></td></tr><tr><td valign="top"><a href="#init-1">init/1</a></td><td></td></tr><tr><td valign="top"><a href="#leader_call-1">leader_call/1</a></td><td></td></tr><tr><td valign="top"><a href="#leader_cast-1">leader_cast/1</a></td><td></td></tr><tr><td valign="top"><a href="#mreg-2">mreg/2</a></td><td></td></tr><tr><td valign="top"><a href="#munreg-2">munreg/2</a></td><td></td></tr><tr><td valign="top"><a href="#reg-1">reg/1</a></td><td></td></tr><tr><td valign="top"><a href="#reg-2">reg/2</a></td><td>
Class = n  - unique name
| p  - non-unique property
| c  - counter
| a  - aggregated counter
Scope = l | g (global or local).</td></tr><tr><td valign="top"><a href="#set_value-2">set_value/2</a></td><td></td></tr><tr><td valign="top"><a href="#start_link-0">start_link/0</a></td><td></td></tr><tr><td valign="top"><a href="#start_link-1">start_link/1</a></td><td></td></tr><tr><td valign="top"><a href="#surrendered-3">surrendered/3</a></td><td></td></tr><tr><td valign="top"><a href="#sync-0">sync/0</a></td><td>Synchronize with the gproc leader.</td></tr><tr><td valign="top"><a href="#terminate-2">terminate/2</a></td><td></td></tr><tr><td valign="top"><a href="#unreg-1">unreg/1</a></td><td></td></tr><tr><td valign="top"><a href="#update_counter-2">update_counter/2</a></td><td></td></tr></table>




<h2><a name="functions">Function Details</a></h2>


<a name="code_change-4"></a>

<h3>code_change/4</h3>





`code_change(FromVsn, S, Extra, E) -> any()`

<a name="elected-2"></a>

<h3>elected/2</h3>





`elected(S, E) -> any()`

<a name="elected-3"></a>

<h3>elected/3</h3>





`elected(S, E, Node) -> any()`

<a name="from_leader-3"></a>

<h3>from_leader/3</h3>





`from_leader(Ops, S, E) -> any()`

<a name="get_leader-0"></a>

<h3>get_leader/0</h3>





<pre>get_leader() -> node()</pre>
<br></br>




Returns the node of the current gproc leader.<a name="give_away-2"></a>

<h3>give_away/2</h3>





`give_away(Key, To) -> any()`

<a name="handle_DOWN-3"></a>

<h3>handle_DOWN/3</h3>





`handle_DOWN(Node, S, E) -> any()`

<a name="handle_call-4"></a>

<h3>handle_call/4</h3>





`handle_call(X1, X2, S, E) -> any()`

<a name="handle_cast-3"></a>

<h3>handle_cast/3</h3>





`handle_cast(Msg, S, X3) -> any()`

<a name="handle_info-2"></a>

<h3>handle_info/2</h3>





`handle_info(X1, S) -> any()`

<a name="handle_leader_call-4"></a>

<h3>handle_leader_call/4</h3>





`handle_leader_call(X1, From, State, E) -> any()`

<a name="handle_leader_cast-3"></a>

<h3>handle_leader_cast/3</h3>





`handle_leader_cast(X1, S, E) -> any()`

<a name="init-1"></a>

<h3>init/1</h3>





`init(Opts) -> any()`

<a name="leader_call-1"></a>

<h3>leader_call/1</h3>





`leader_call(Req) -> any()`

<a name="leader_cast-1"></a>

<h3>leader_cast/1</h3>





`leader_cast(Msg) -> any()`

<a name="mreg-2"></a>

<h3>mreg/2</h3>





`mreg(T, KVL) -> any()`

<a name="munreg-2"></a>

<h3>munreg/2</h3>





`munreg(T, Keys) -> any()`

<a name="reg-1"></a>

<h3>reg/1</h3>





`reg(Key) -> any()`

<a name="reg-2"></a>

<h3>reg/2</h3>





`reg(Key, Value) -> any()`




Class = n  - unique name
| p  - non-unique property
| c  - counter
| a  - aggregated counter
Scope = l | g (global or local)<a name="set_value-2"></a>

<h3>set_value/2</h3>





`set_value(Key, Value) -> any()`

<a name="start_link-0"></a>

<h3>start_link/0</h3>





`start_link() -> any()`

<a name="start_link-1"></a>

<h3>start_link/1</h3>





`start_link(Nodes) -> any()`

<a name="surrendered-3"></a>

<h3>surrendered/3</h3>





`surrendered(S, X2, E) -> any()`

<a name="sync-0"></a>

<h3>sync/0</h3>





<pre>sync() -> true</pre>
<br></br>






Synchronize with the gproc leader

This function can be used to ensure that data has been replicated from the
leader to the current node. It does so by asking the leader to ping all
live participating nodes. The call will return `true` when all these nodes
have either responded or died. In the special case where the leader dies
during an ongoing sync, the call will fail with a timeout exception.
(Actually, it should be a `leader_died` exception; more study needed to find
out why gen_leader times out in this situation, rather than reporting that
the leader died.)<a name="terminate-2"></a>

<h3>terminate/2</h3>





`terminate(Reason, S) -> any()`

<a name="unreg-1"></a>

<h3>unreg/1</h3>





`unreg(Key) -> any()`

<a name="update_counter-2"></a>

<h3>update_counter/2</h3>





`update_counter(Key, Incr) -> any()`

