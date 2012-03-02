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
%% @author Ulf Wiger <ulf.wiger@feuerlabs.com>
%%
%% @doc Gproc Publish/Subscribe patterns
%% This module implements a few convenient functions for publish/subscribe.
%%
%% Publish/subscribe with Gproc relies entirely on gproc properties and counters.
%% This makes for a very concise implementation, as the monitoring of subscribers and
%% removal of subscriptions comes for free with Gproc.
%%
%% Using this module instead of rolling your own (which is easy enough) brings the
%% benefit of consistency, in tracing and debugging.
%% The implementation can also serve to illustrate how to use gproc properties and
%% counters to good effect.
%%
%% @type scope()  = l | g.
%% @type event()  = any().
%% @type msg()    = any().
%% @type status() = 1 | 0.
%% @end
-module(gproc_ps).

-export([subscribe/2,
	 unsubscribe/2,
	 publish/3,
	 list_subs/2
	]).

-export([create_single/2,
	 delete_single/2,
	 disable_single/2,
	 enable_single/2,
	 tell_singles/3,
	 notify_single_if_true/4,
	 list_singles/2]).

-define(ETag, gproc_ps_event).

%% These types are duplicated above in EDoc syntax, since EDoc annoyingly doesn't pick up
%% the type definitions, even if they are referred to in the -spec:s that EDoc does parse.
-type scope()  :: l | g.
-type event()  :: any().
-type msg()    :: any().
-type status() :: 1 | 0.


-spec subscribe(scope(), event()) -> true.
%% @doc Subscribe to events of type `Event'
%%
%% Any messages published with `gproc_ps:publish(Scope, Event, Msg)' will be delivered to
%% the current process, along with all other subscribers.
%%
%% This function creates a property, `{p,Scope,{gproc_ps_event,Event}}', which can be
%% searched and displayed for debugging purposes.
%% @end
subscribe(Scope, Event) when Scope==l; Scope==g ->
    gproc:reg({p,Scope,{?ETag, Event}}).

-spec unsubscribe(scope(), event()) -> true.
%% @doc Remove subscribtion created using `subscribe(Scope, Event)'
%%
%% This removes the property created through `subscribe/2'.
%% @end
unsubscribe(Scope, Event) when Scope==l; Scope==g ->
    gproc:unreg({p,Scope,{?ETag, Event}}).

-spec publish(scope(), event(), msg()) -> ok.
%% @doc Publish the message `Msg' to all subscribers of `Event'
%%
%% The message delivered to each subscriber will be of the form:
%%
%% `{gproc_ps_event, Event, Msg}'
%%
%% The function uses `gproc:send/2' to send a message to all processes which have a
%% property `{p,Scope,{gproc_ps_event,Event}}'.
%% @end
publish(Scope, Event, Msg) when Scope==l; Scope==g ->
     gproc:send({p, Scope, {?ETag, Event}}, {?ETag, Event, Msg}).


-spec list_subs(scope(), event()) -> [pid()].
%% @doc List the pids of all processes subscribing to `Event'
%%
%% This function uses `gproc:select/2' to find all properties indicating a subscription.
%% @end
list_subs(Scope, Event) when Scope==l; Scope==g ->
    gproc:select({Scope,p}, [{ {{p,Scope,{?ETag,Event}}, '$1', '_'}, [], ['$1'] }]).

-spec create_single(scope(), event()) -> true.
%% @doc Creates a single-shot subscription entry for Event
%%
%% Single-shot subscriptions behave similarly to the `{active,once}' property of sockets.
%% Once a message has been published, the subscription is disabled, and no more messages
%% will be delivered to the subscriber unless the subscription is re-enabled using
%% `enable_single/2'.
%%
%% The function creates a gproc counter entry, `{c,Scope,{gproc_ps_event,Event}}', which
%% will have either of the values `0' (disabled) or `1' (enabled). Initially, the value
%% is `1', meaning the subscription is enabled.
%%
%% Counters are used in this case, since they can be atomically updated by both the
%% subscriber (owner) and publisher. The publisher sets the counter value to `0' as soon
%% as it has delivered a message.
%% @end
create_single(Scope, Event) when Scope==l; Scope==g ->
    gproc:reg({c,Scope,{?ETag, Event}}, 1).

-spec delete_single(scope(), event()) -> true.
%% @doc Deletes the single-shot subscription for Event
%%
%% This function deletes the counter entry representing the single-shot description.
%% An exception will be raised if there is no such subscription.
%% @end
delete_single(Scope, Event) when Scope==l; Scope==g ->
    gproc:unreg({c,Scope,{?ETag, Event}}).

-spec disable_single(scope(), event()) -> integer().
%% @doc Disables the single-shot subscription for Event
%%
%% This function changes the value of the corresponding gproc counter to `0' (disabled).
%%
%% The subscription remains (e.g. for debugging purposes), but with a 'disabled' status.
%% This function is insensitive to concurrency, using 'wrapping' ets counter update ops.
%% This guarantees that the counter will have either the value 1 or 0, depending on which
%% update happened last.
%%
%% The return value indicates the previous status.
%% @end
disable_single(Scope, Event) when Scope==l; Scope==g ->
    gproc:update_counter({c,Scope,{?ETag,Event}}, {-1, 0, 0}).

-spec enable_single(scope(), event()) -> integer().
%% @doc Enables the single-shot subscription for Event
%%
%% This function changes the value of the corresponding gproc counter to `1' (enabled).
%%
%% After enabling, the subscriber will receive the next message published for `Event',
%% after which the subscription is automatically disabled.
%%
%% This function is insensitive to concurrency, using 'wrapping' ets counter update ops.
%% This guarantees that the counter will have either the value 1 or 0, depending on which
%% update happened last.
%%
%% The return value indicates the previous status.
%% @end
enable_single(Scope, Event) when Scope==l; Scope==g ->
    gproc:update_counter({c,Scope,{?ETag,Event}}, {1, 1, 1}).

-spec tell_singles(scope(), event(), msg()) -> [pid()].
%% @doc Publish `Msg' to all single-shot subscribers of `Event'
%%
%% The subscriber status of each active subscriber is changed to `0' (disabled) before
%% delivering the message. This reduces the risk that two different processes will be able
%% to both deliver a message before disabling the subscribers. This could happen if the
%% context switch happens just after the select operation (finding the active subscribers)
%% and before the process is able to update the counters. In this case, it is possible
%% that more than one can be delivered.
%%
%% The way to prevent this from happening is to ensure that only one process publishes
%% for `Event'.
%% @end
tell_singles(Scope, Event, Msg) when Scope==l; Scope==g ->
    Subs = gproc:select(
	     {Scope,c},
	     [{ {{c,Scope,{?ETag,Event}}, '$1', 1}, [],
		[{{ {{c,Scope, {{?ETag,wrap(Event)}} }}, '$1', {{-1,0,0}} }}] }]),
    _ = gproc:update_counters(Scope, Subs),
    [begin P ! {?ETag, Event, Msg}, P end || {_,P,_} <- Subs].

wrap(E) when is_tuple(E) ->
    {list_to_tuple([wrap(X) || X <- tuple_to_list(E)])};
wrap(E) when is_list(E) ->
    [wrap(X) || X <- E];
wrap(X) ->
    X.


-spec list_singles(scope(), event()) -> [{pid(), status()}].
%% @doc Lists all single-shot subscribers of Event, together with their status
%% @end
list_singles(Scope, Event) ->
    gproc:select({Scope,c}, [{ {{c,Scope,{?ETag,Event}}, '$1', '$2'},
			       [], [{{'$1','$2'}}] }]).

-spec notify_single_if_true(scope(), event(), fun(() -> boolean()), msg()) -> ok.
%% @doc Create/enable a single subscription for event; notify at once if F() -> true
%%
%% This function is a convenience function, wrapping a single-shot pub/sub around a
%% user-provided boolean test. `Msg' should be what the publisher will send later, if the
%% immediate test returns `false'.
%% @end
notify_single_if_true(Scope, Event, F, Msg) ->
    try enable_single(Scope, Event)
    catch
	error:_ ->
	    create_single(Scope, Event)
    end,
    case F() of
	true ->
	    disable_single(Scope, Event),
	    self() ! {?ETag, Event, Msg},
	    ok;
	false ->
	    ok
    end.
