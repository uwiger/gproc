

#Module gproc_dist#
* [Description](#description)
* [Function Index](#index)
* [Function Details](#functions)


Extended process registry.



__Behaviours:__ [`gen_leader`](/Users/uwiger/FL/git/gen_leader/doc/gen_leader.md).

__Authors:__ Ulf Wiger ([`ulf.wiger@erlang-solutions.com`](mailto:ulf.wiger@erlang-solutions.com)).<a name="description"></a>

##Description##


This module implements an extended process registry


For a detailed description, see gproc/doc/erlang07-wiger.pdf.<a name="index"></a>

##Function Index##


<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#code_change-4">code_change/4</a></td><td></td></tr><tr><td valign="top"><a href="#elected-2">elected/2</a></td><td></td></tr><tr><td valign="top"><a href="#elected-3">elected/3</a></td><td></td></tr><tr><td valign="top"><a href="#from_leader-3">from_leader/3</a></td><td></td></tr><tr><td valign="top"><a href="#get_leader-0">get_leader/0</a></td><td>Returns the node of the current gproc leader.</td></tr><tr><td valign="top"><a href="#give_away-2">give_away/2</a></td><td></td></tr><tr><td valign="top"><a href="#handle_DOWN-3">handle_DOWN/3</a></td><td></td></tr><tr><td valign="top"><a href="#handle_call-4">handle_call/4</a></td><td></td></tr><tr><td valign="top"><a href="#handle_cast-3">handle_cast/3</a></td><td></td></tr><tr><td valign="top"><a href="#handle_info-2">handle_info/2</a></td><td></td></tr><tr><td valign="top"><a href="#handle_leader_call-4">handle_leader_call/4</a></td><td></td></tr><tr><td valign="top"><a href="#handle_leader_cast-3">handle_leader_cast/3</a></td><td></td></tr><tr><td valign="top"><a href="#init-1">init/1</a></td><td></td></tr><tr><td valign="top"><a href="#leader_call-1">leader_call/1</a></td><td></td></tr><tr><td valign="top"><a href="#leader_cast-1">leader_cast/1</a></td><td></td></tr><tr><td valign="top"><a href="#mreg-2">mreg/2</a></td><td></td></tr><tr><td valign="top"><a href="#munreg-2">munreg/2</a></td><td></td></tr><tr><td valign="top"><a href="#reg-1">reg/1</a></td><td></td></tr><tr><td valign="top"><a href="#reg-2">reg/2</a></td><td>
Class = n  - unique name
| p  - non-unique property
| c  - counter
| a  - aggregated counter
Scope = l | g (global or local).</td></tr><tr><td valign="top"><a href="#reg_shared-2">reg_shared/2</a></td><td></td></tr><tr><td valign="top"><a href="#reset_counter-1">reset_counter/1</a></td><td></td></tr><tr><td valign="top"><a href="#set_value-2">set_value/2</a></td><td></td></tr><tr><td valign="top"><a href="#start_link-0">start_link/0</a></td><td></td></tr><tr><td valign="top"><a href="#start_link-1">start_link/1</a></td><td></td></tr><tr><td valign="top"><a href="#surrendered-3">surrendered/3</a></td><td></td></tr><tr><td valign="top"><a href="#sync-0">sync/0</a></td><td>Synchronize with the gproc leader.</td></tr><tr><td valign="top"><a href="#terminate-2">terminate/2</a></td><td></td></tr><tr><td valign="top"><a href="#unreg-1">unreg/1</a></td><td></td></tr><tr><td valign="top"><a href="#unreg_shared-1">unreg_shared/1</a></td><td></td></tr><tr><td valign="top"><a href="#update_counter-2">update_counter/2</a></td><td></td></tr><tr><td valign="top"><a href="#update_counters-1">update_counters/1</a></td><td></td></tr><tr><td valign="top"><a href="#update_shared_counter-2">update_shared_counter/2</a></td><td></td></tr></table>


<a name="functions"></a>

##Function Details##

<a name="code_change-4"></a>

###code_change/4##




`code_change(FromVsn, S, Extra, E) -> any()`

<a name="elected-2"></a>

###elected/2##




`elected(S, E) -> any()`

<a name="elected-3"></a>

###elected/3##




`elected(S, E, Node) -> any()`

<a name="from_leader-3"></a>

###from_leader/3##




`from_leader(Ops, S, E) -> any()`

<a name="get_leader-0"></a>

###get_leader/0##




<pre>get_leader() -&gt; node()</pre>
<br></br>




Returns the node of the current gproc leader.<a name="give_away-2"></a>

###give_away/2##




`give_away(Key, To) -> any()`

<a name="handle_DOWN-3"></a>

###handle_DOWN/3##




`handle_DOWN(Node, S, E) -> any()`

<a name="handle_call-4"></a>

###handle_call/4##




`handle_call(X1, X2, S, E) -> any()`

<a name="handle_cast-3"></a>

###handle_cast/3##




`handle_cast(Msg, S, X3) -> any()`

<a name="handle_info-2"></a>

###handle_info/2##




`handle_info(X1, S) -> any()`

<a name="handle_leader_call-4"></a>

###handle_leader_call/4##




`handle_leader_call(X1, From, State, E) -> any()`

<a name="handle_leader_cast-3"></a>

###handle_leader_cast/3##




`handle_leader_cast(X1, S, E) -> any()`

<a name="init-1"></a>

###init/1##




`init(Opts) -> any()`

<a name="leader_call-1"></a>

###leader_call/1##




`leader_call(Req) -> any()`

<a name="leader_cast-1"></a>

###leader_cast/1##




`leader_cast(Msg) -> any()`

<a name="mreg-2"></a>

###mreg/2##




`mreg(T, KVL) -> any()`

<a name="munreg-2"></a>

###munreg/2##




`munreg(T, Keys) -> any()`

<a name="reg-1"></a>

###reg/1##




`reg(Key) -> any()`

<a name="reg-2"></a>

###reg/2##




`reg(Key, Value) -> any()`




Class = n  - unique name
| p  - non-unique property
| c  - counter
| a  - aggregated counter
Scope = l | g (global or local)<a name="reg_shared-2"></a>

###reg_shared/2##




`reg_shared(Key, Value) -> any()`

<a name="reset_counter-1"></a>

###reset_counter/1##




`reset_counter(Key) -> any()`

<a name="set_value-2"></a>

###set_value/2##




`set_value(Key, Value) -> any()`

<a name="start_link-0"></a>

###start_link/0##




`start_link() -> any()`

<a name="start_link-1"></a>

###start_link/1##




`start_link(Nodes) -> any()`

<a name="surrendered-3"></a>

###surrendered/3##




`surrendered(S, X2, E) -> any()`

<a name="sync-0"></a>

###sync/0##




<pre>sync() -&gt; true</pre>
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

###terminate/2##




`terminate(Reason, S) -> any()`

<a name="unreg-1"></a>

###unreg/1##




`unreg(Key) -> any()`

<a name="unreg_shared-1"></a>

###unreg_shared/1##




`unreg_shared(Key) -> any()`

<a name="update_counter-2"></a>

###update_counter/2##




`update_counter(Key, Incr) -> any()`

<a name="update_counters-1"></a>

###update_counters/1##




`update_counters(List) -> any()`

<a name="update_shared_counter-2"></a>

###update_shared_counter/2##




`update_shared_counter(Key, Incr) -> any()`

