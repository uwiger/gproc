

<h1>The gproc application</h1>

The gproc application
=====================
Extended process dictionary.

__Authors:__ Ulf Wiger ([`ulf.wiger@erlang-solutions.com`](mailto:ulf.wiger@erlang-solutions.com)), Joseph Wayne Norton ([`norton@geminimobile.com`](mailto:norton@geminimobile.com)).

Extended process dictionary



<h3><a name="Introduction">Introduction</a></h3>





Gproc is a process dictionary for Erlang, which provides a number of useful features beyond what the built-in dictionary has:


* Use any term as a process alias

* Register a process under several aliases

* Non-unique properties can be registered simultaneously by many processes

* QLC and match specification interface for efficient queries on the 
  dictionary

* Await registration, let's you wait until a process registers itself

* Atomically give away registered names and properties to another process

* Counters, and aggregated counters, which automatically maintain the 
  total of all counters with a given name

* Global registry, with all the above functions applied to a network of nodes





An interesting application of gproc is building publish/subscribe patterns.
Example:

<pre>
subscribe(EventType) ->
    %% Gproc notation: {p, l, Name} means {(p)roperty, (l)ocal, Name}
    gproc:reg({p, l, {?MODULE, EventType}}).

notify(EventType, Msg) ->
    Key = {?MODULE, EventType},
    gproc:send({p, l, Key}, {self(), Key, Msg}).
</pre>



Gproc has a QuickCheck test suite, covering a fairly large part of the local 
gproc functionality, although none of the global registry. It requires a 
commercial EQC license, but rebar is smart enough to detect whether EQC is 
available, and if it isn't, the code in gproc_eqc.erl will be "defined away".



There is also an eunit suite, covering the basic operations for local and 
global gproc.



<h3><a name="Building_Edoc">Building Edoc</a></h3>




By default, `./rebar doc` generates Github-flavored Markdown files.If you want to change this, remove the `edoc_opts` line from `rebar.config`.

Gproc was first introduced at the ACM SIGPLAN Erlang Workshop in
Freiburg 2007 ([Paper available here](erlang07-wiger.pdf)).


<h2 class="indextitle">Modules</h2>



<table width="100%" border="0" summary="list of modules">
<tr><td><a href="gproc.md" class="module">gproc</a></td></tr>
<tr><td><a href="gproc_app.md" class="module">gproc_app</a></td></tr>
<tr><td><a href="gproc_dist.md" class="module">gproc_dist</a></td></tr>
<tr><td><a href="gproc_init.md" class="module">gproc_init</a></td></tr>
<tr><td><a href="gproc_lib.md" class="module">gproc_lib</a></td></tr>
<tr><td><a href="gproc_sup.md" class="module">gproc_sup</a></td></tr></table>

