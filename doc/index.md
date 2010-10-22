

#The gproc application#
The gproc application
=====================
Extended process dictionary


##Introduction##
.
__Authors:__ Ulf Wiger ([`ulf.wiger@erlang-consulting.com`](mailto:ulf.wiger@erlang-consulting.com)), Joseph Wayne Norton ([`norton@geminimobile.com`](mailto:norton@geminimobile.com)).Extended process dictionary


##Introduction##



Gproc was first introduced at the ACM SIGPLAN Erlang Workshop in
Freiburg 2007 ([Paper available here](erlang07-wiger.pdf)).


This application was designed to meet the following requirements:



<li>
  A process can register itself using any term.
  A process can register more than one name
  A process can publish non-unique {Key,Value} 'properties' 
  The registry must be efficiently searchable
</li>



As additional features, the registry was designed to allow global
registration, and a special {Key,Value} property called a counter.
It is also possible to create an 'aggregate counter', which will
continuously reflect the sum of all counters with the same name.

_In its current state, the global registration facility is brokenand should not be used. It will be migrated over to a new version of gen_leader. This work will be done with low priority unless peopleexpress a strong urge to use this functionality._


##Modules##

<table width="100%" border="0" summary="list of modules">
<tr><td><a href="gproc.md" class="module">gproc</a></td></tr>
<tr><td><a href="gproc_app.md" class="module">gproc_app</a></td></tr>
<tr><td><a href="gproc_dist.md" class="module">gproc_dist</a></td></tr>
<tr><td><a href="gproc_init.md" class="module">gproc_init</a></td></tr>
<tr><td><a href="gproc_lib.md" class="module">gproc_lib</a></td></tr>
<tr><td><a href="gproc_sup.md" class="module">gproc_sup</a></td></tr></table>
