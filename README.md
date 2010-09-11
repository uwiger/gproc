Gproc - Extended Process Dictionary for Erlang
==============================================

Gproc is a process dictionary for Erlang, which provides a number of useful features beyond what the built-in dictionary has:

* Use any term as a process alias
* Register a process under several aliases
* Non-unique properties can be registered simultaneously by many processes
* QLC and match specification interface for efficient queries on the 
  dictionary
* Await registration, let's you wait until a process registers itself
* Counters, and aggregated counters, which automatically maintain the 
  total of all counters with a given name.
* Global registry, with all the above functions applied to a network of nodes.

Gproc has a QuickCheck test suite, covering a fairly large part of the local gproc functionality, although none of the global registry. It requires a commercial EQC license, but rebar is smart enough to detect whether EQC is available, and if it isn't, the code in gproc_eqc.erl will be "defined away".

There is also an eunit suite in gproc.erl, but it covers only some of the most basic functions (local only). Lots more tests need to be written... some day. Contributions are most welcome.
