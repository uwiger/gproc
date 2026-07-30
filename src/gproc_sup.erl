%% -*- erlang-indent-level: 4;indent-tabs-mode: nil -*-
%% --------------------------------------------------
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%% --------------------------------------------------
%%----------------------------------------------------------------------
%% File    : gproc_sup.erl
%% Purpose : GPROC top-level supervisor
%%----------------------------------------------------------------------

-module(gproc_sup).
-vsn("1.3.0").

-behaviour(supervisor).

%% External exports
-export([start_link/1]).

%% supervisor callbacks
-export([init/1]).

%%%----------------------------------------------------------------------
%%% API
%%%----------------------------------------------------------------------
start_link(Args) ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, Args).

%%%----------------------------------------------------------------------
%%% Callback functions from supervisor
%%%----------------------------------------------------------------------

%%----------------------------------------------------------------------
%% Func: init/1
%% Returns: {ok,  {SupFlags,  [ChildSpec]}} |
%%          ignore                          |
%%          {error, Reason}
%%----------------------------------------------------------------------
%% @spec(_Args::term()) -> {ok, {supervisor_flags(), child_spec_list()}}
%% @doc The main GPROC supervisor.

init(_Args) ->
    %% Hint:
    %% Child_spec = [Name, {M, F, A},
    %%               Restart, Shutdown_time, Type, Modules_used]

    Gproc = {gproc, {gproc, start_link, []},
             permanent, 2000, worker, [gproc]},
    Mon = {gproc_monitor, {gproc_monitor, start_link, []},
	   permanent, 2000, worker, [gproc_monitor]},
    BCast = {gproc_bcast, {gproc_bcast, start_link, []},
	     permanent, 2000, worker, [gproc_bcast]},
    Pool = {gproc_pool, {gproc_pool, start_link, []},
	    permanent, 2000, worker, [gproc_pool]},
    Children = [Gproc] ++ maybe_dist() ++ [Mon, BCast, Pool],
    {ok, {{one_for_one, 15, 60}, Children}}.


%%%----------------------------------------------------------------------
%%% Internal functions
%%%----------------------------------------------------------------------

%% gproc_dist needs locks. With locks as an optional_application, the app
%% controller starts it when present; if it is missing (or failed to start),
%% we stay local-only.
%%
%% `{gproc, gproc_dist}' env is passed through to start_link/1 so configured
%% peer node names are connected (gen_leader used to do that implicitly).
maybe_dist() ->
    case whereis(locks_server) of
        Pid when is_pid(Pid) ->
            Env = application:get_env(gproc, gproc_dist),
            [{gproc_dist, {gproc_dist, start_link, [Env]},
              permanent, 2000, worker, [gproc_dist]}];
        undefined ->
            []
    end.
