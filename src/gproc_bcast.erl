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
%% @author Ulf Wiger <ulf@wiger.net>
%%
%% @doc Gproc message broadcast server
%% This module is used to support gproc:bcast(Key, Msg).
%%
%% gproc:bcast/2 allows for e.g. distributed publish/subscribe, without
%% having to resort to global property registration.
%% To ensure that erlang's message ordering guarantees are kept, all sends
%% are channeled through a broadcast server on each node.
%% @end

-module(gproc_bcast).
-behaviour(gen_server).

-export([start_link/0,
	 init/1,
	 handle_cast/2,
	 handle_call/3,
	 handle_info/2,
	 terminate/2,
	 code_change/3]).

-include("gproc_int.hrl").

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    {ok, []}.

handle_call(_, _, S) ->
    {reply, {error, unknown_call}, S}.

handle_cast({send, Key, Msg}, S) ->
    ?MAY_FAIL(gproc:send(Key, Msg)),
    {noreply, S};
handle_cast(_, S) ->
    {noreply, S}.

handle_info(_, S) ->
    {noreply, S}.

terminate(_, _) ->
    ok.

code_change(_, S, _) ->
    {ok, S}.

