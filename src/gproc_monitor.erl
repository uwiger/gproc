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
%% @doc
%% This module implements a notification system for gproc names
%% When a process subscribes to notifications for a given name, a message
%% will be sent each time that name is registered
-module(gproc_monitor).

-behaviour(gen_server).

%% API
-export([subscribe/1,
	 unsubscribe/1]).

%% Process start function
-export([start_link/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).

-define(SERVER, ?MODULE).
-define(TAB, ?MODULE).

-record(state, {}).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @spec subscribe(key()) -> ok
%%
%% @doc
%% Subscribe to registration events for a certain name
%%
%% The subscribing process will receive a `{gproc_monitor, Name, Pid}' message
%% whenever a process registers under the given name, and a
%% `{gproc_monitor, Name, undefined}' message when the name is unregistered,
%% either explicitly, or because the registered process dies.
%%
%% When the subscription is first ordered, one of the above messages will be
%% sent immediately, indicating the current status of the name.
%% @end
%%--------------------------------------------------------------------
subscribe({T,S,_} = Key) when (T==n orelse T==a)
			      andalso (S==g orelse S==l) ->
    try gproc:reg({p,l,{?MODULE,Key}})
    catch
	error:badarg -> ok
    end,
    gen_server:cast(?SERVER, {subscribe, self(), Key}).


%%--------------------------------------------------------------------
%% @spec unsubscribe(key()) -> ok
%%
%% @doc
%% Unsubscribe from registration events for a certain name
%%
%% This function is the reverse of subscribe/1. It removes the subscription.
%% @end
%%--------------------------------------------------------------------
unsubscribe({T,S,_} = Key) when (T==n orelse T==a)
				andalso (S==g orelse S==l) ->
    try gproc:unreg({p, l, {?MODULE,Key}})
    catch
	error:badarg -> ok
    end,
    ok.

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link() ->
    Me = self(),
    case ets:info(?TAB, owner) of
	undefined ->
	    ets:new(?TAB, [ordered_set, protected, named_table,
			      {heir, self(), []}]);
	Me ->
	    ok
    end,
    {ok, Pid} = proc_lib:start_link(?MODULE, init, [Me]),
    ets:give_away(?TAB, Pid, []),
    {ok, Pid}.

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
init(Parent) ->
    register(?SERVER, self()),
    proc_lib:init_ack(Parent, {ok, self()}),
    receive {'ETS-TRANSFER',?TAB,_,_} -> ok end,
    gen_server:enter_loop(?MODULE, [], #state{}).

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @spec handle_call(Request, From, State) ->
%%                                   {reply, Reply, State} |
%%                                   {reply, Reply, State, Timeout} |
%%                                   {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, Reply, State} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                  {noreply, State, Timeout} |
%%                                  {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_cast({subscribe, Pid, Key}, State) ->
    Status = gproc:where(Key),
    do_monitor(Key, Status),
    Pid ! {?MODULE, Key, Status},
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_info({gproc, unreg, _Ref, Name}, State) ->
    ets:delete(?TAB, Name),
    notify(Name, undefined),
    do_monitor(Name, undefined),
    {noreply, State};
handle_info({gproc, _, registered, {{T,_,_} = Name, Pid, _}}, State)
  when T==n; T==a ->
    notify(Name, Pid),
    do_monitor(Name, Pid),
    {noreply, State};
handle_info(_, State) ->
    {noreply, State}.


%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

do_monitor(Name, undefined) ->
    gproc:nb_wait(Name);
do_monitor(Name, Pid) when is_pid(Pid) ->
    case ets:member(?TAB, Name) of
	false ->
	    Ref = gproc:monitor(Name),
	    ets:insert(?TAB, {Name, Ref});
	true ->
	    ok
    end.

notify(Name, Where) ->
    gproc:send({p, l, {?MODULE, Name}}, {?MODULE, Name, Where}).
