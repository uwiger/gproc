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
%%
%% @author Ulf Wiger <ulf@wiger.net>
%%
-module(gproc_remote_tests).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

-define(t(E), ?_test(?debugVal(E))).

remote_test_() ->
    %% dbg:tracer(),
    %% dbg:tpl(?MODULE,x),
    %% dbg:tpl(gproc_test_lib,x),
    %% dbg:tp(slave,x),
    %% dbg:p(all,[c]),
    StartedNet = gproc_test_lib:ensure_dist(),
    N = gproc_test_lib:node_name(remote_n1),
    {setup,
     fun() ->
             gproc_test_lib:start_node(N),
             rpc:call(N, application, start, [gproc]),
             N
     end,
     fun(Node) ->
             gproc_test_lib:stop_node(Node),
             case StartedNet of
                 true ->
                     net_kernel:stop();
                 false ->
                     ok
             end
     end,
     [
      ?t(t_remote_reg_name(N)),
      ?t(t_remote_reg_prop(N)),
      ?t(t_pub_sub(N)),
      ?t(t_single(N))
     ]}.

%% remote_setup() ->
%%     gproc_test_lib:start_node(remote_n1).

%% remote_cleanup(N) ->
%%     gproc_test_lib:stop_node(N).

t_remote_reg_name(N) ->
    Key = {n,l,the_remote_name},
    true = gproc:reg_remote(N, Key),
    Me = self(),
    Me = rpc:call(N, gproc, where, [Key]),
    true = gproc:unreg_remote(N, Key),
    undefined = rpc:call(N, gproc, where, [Key]),
    ok.

t_remote_reg_prop(N) ->
    Key = {p, l, the_remote_prop},
    true = gproc:reg_remote(N, Key),
    Me = self(),
    [Me] = rpc:call(N, gproc, lookup_pids, [Key]),
    true = gproc:unreg_remote(N, Key),
    [] = rpc:call(N, gproc, lookup_pids, [Key]),
    ok.

t_pub_sub(N) ->
    true = gproc_ps:subscribe_remote(N, my_event),
    Msg = rpc:call(N, gproc_ps, publish, [l, my_event, foo]),
    receive
        Msg ->
            ok
    after 1000 ->
            error(timeout)
    end,
    true = gproc_ps:unsubscribe_remote(N, my_event),
    Msg2 = rpc:call(N, gproc_ps, publish, [my_event, foo2]),
    receive
        Msg2 ->
            error(unsub_failed)
    after 100 ->
            ok
    end.

t_single(N) ->
    Me = self(),
    true = gproc_ps:create_single_remote(N, my_single),
    [Me] = rpc:call(N, gproc_ps, tell_singles, [l, my_single, foo1]),
    receive
        {gproc_ps_event, my_single, foo1} -> ok
    after 1000 -> error(timeout)
    end,
    [] = rpc:call(N, gproc_ps, tell_singles, [l, my_single, foo2]),
    0 = gproc_ps:enable_single_remote(N, my_single),
    [Me] = rpc:call(N, gproc_ps, tell_singles, [l, my_single, foo3]),
    receive
        {gproc_ps_event, my_single, foo3} -> ok
    after 1000 -> error(enable_single_failed)
    end,
    0 = gproc_ps:enable_single_remote(N, my_single),
    1 = gproc_ps:disable_single_remote(N, my_single),
    [] = rpc:call(N, gproc_ps, tell_singles, [l, my_single, foo4]),
    true = gproc_ps:delete_single_remote(N, my_single),
    true = gproc_ps:create_single_remote(N, my_single),
    true = gproc_ps:delete_single_remote(N, my_single),
    ok.

-endif.
