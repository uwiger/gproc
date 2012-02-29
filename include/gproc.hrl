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
%% @author Ulf Wiger <ulf.wiger@erlang-solutions.com>
%% 
%% gproc.hrl: Common definitions

-define(TAB, gproc).


-type type()     :: n | p | c | a.
-type scope()    :: l | g.
-type context()  :: {scope(),type()} | type().
-type sel_type() :: n | p | c | a |
                    names | props | counters | aggr_counters.

-type sel_var() :: '_' | atom().
-type keypat()  :: {sel_type() | sel_var(), l | g | sel_var(), any()}.
-type pidpat()  :: pid() | sel_var().
-type headpat() :: {keypat(),pidpat(),any()}.
-type key()     :: {type(), scope(), any()}.

-type sel_pattern() :: [{headpat(), list(), list()}].

%% update_counter increment
-type ctr_incr()   :: integer().
-type ctr_thr()    :: integer().
-type ctr_setval() :: integer().
-type ctr_update()  :: ctr_incr()
		     | {ctr_incr(), ctr_thr(), ctr_setval()}.
-type increment() :: ctr_incr() | ctr_update() | [ctr_update()].
