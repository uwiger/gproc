Module gproc_monitor
====================


<h1>Module gproc_monitor</h1>

* [Description](#description)
* [Function Index](#index)
* [Function Details](#functions)



This module implements a notification system for gproc names
When a process subscribes to notifications for a given name, a message
will be sent each time that name is registered.



__Behaviours:__ [`gen_server`](gen_server.md).

__Authors:__ Ulf Wiger ([`ulf.wiger@feuerlabs.com`](mailto:ulf.wiger@feuerlabs.com)).

<h2><a name="index">Function Index</a></h2>



<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#start_link-0">start_link/0</a></td><td>
Starts the server.</td></tr><tr><td valign="top"><a href="#subscribe-1">subscribe/1</a></td><td>  
Subscribe to registration events for a certain name.</td></tr><tr><td valign="top"><a href="#unsubscribe-1">unsubscribe/1</a></td><td>  
Unsubscribe from registration events for a certain name.</td></tr></table>




<h2><a name="functions">Function Details</a></h2>


<a name="start_link-0"></a>

<h3>start_link/0</h3>





<pre>start_link() -> {ok, Pid} | ignore | {error, Error}</pre>
<br></br>





Starts the server
<a name="subscribe-1"></a>

<h3>subscribe/1</h3>





<pre>subscribe(Key::<a href="#type-key">key()</a>) -> ok</pre>
<br></br>






  
Subscribe to registration events for a certain name



The subscribing process will receive a `{gproc_monitor, Name, Pid}` message
whenever a process registers under the given name, and a
`{gproc_monitor, Name, undefined}` message when the name is unregistered,  
either explicitly, or because the registered process dies.

When the subscription is first ordered, one of the above messages will be
sent immediately, indicating the current status of the name.<a name="unsubscribe-1"></a>

<h3>unsubscribe/1</h3>





<pre>unsubscribe(Key::<a href="#type-key">key()</a>) -> ok</pre>
<br></br>






  
Unsubscribe from registration events for a certain name

This function is the reverse of subscribe/1. It removes the subscription.