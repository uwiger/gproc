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
%%%----------------------------------------------------------------------
%%% File     : gproc_app.erl
%%% Purpose  : GPROC application callback module
%%%----------------------------------------------------------------------

-module(gproc_app).
-vsn("1.3.0").

-behaviour(application).

%% application callbacks
-export([start/0, start/2, stop/1]).

%%%----------------------------------------------------------------------
%%% Callback functions from application
%%%----------------------------------------------------------------------

%%----------------------------------------------------------------------
%% Func: start/2
%% Returns: {ok, Pid}        |
%%          {ok, Pid, State} |
%%          {error, Reason}
%%----------------------------------------------------------------------
start() ->
    start(normal, []).

start(_Type, StartArgs) ->
    %% locks is optional_applications: ensure_all_started(gproc) will start it
    %% as a dep, but ensure_started/start(gproc) will not. Pull locks in here
    %% when it is loadable so gproc_sup can start gproc_dist; ignore failure
    %% when locks is not present (local-only install).
    _ = application:ensure_all_started(locks),
    case gproc_sup:start_link(StartArgs) of
        {ok, Pid} ->
            {ok, Pid};
        Error ->
            Error
    end.

%%----------------------------------------------------------------------
%% Func: stop/1
%% Returns: any
%%----------------------------------------------------------------------
stop(_State) ->
    ok.

%%%----------------------------------------------------------------------
%%% Internal functions
%%%----------------------------------------------------------------------
