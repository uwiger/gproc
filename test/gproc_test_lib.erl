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
-module(gproc_test_lib).

-export([t_spawn/1, t_spawn/2,
         t_spawn_reg/2, t_spawn_reg/3, t_spawn_reg/4,
         t_spawn_reg_shared/3,
         t_spawn_mreg/2,
         t_spawn_mreg/3,
         t_call/2,
         t_loop/0, t_loop/1,
         t_pool_contains_atleast/2,
         got_msg/1, got_msg/2,
         no_msg/2]).

-export([ensure_dist/0,
         start_nodes/1, start_nodes/2,
         start_node/1, start_node/2,
         stop_nodes/1,
         stop_node/1,
         node_name/1,
         mesh_connect/1,
         start_gproc/1,
         wait_gproc_leader/1,
         subscribe_dist_events/1,
         wait_dist_ready/1,
         setup_peer_logger/2]).

-include_lib("eunit/include/eunit.hrl").


%% ============================================================
%% Node lifecycle (peer)
%% ============================================================

start_nodes(Ns) ->
    start_nodes(Ns, #{}).

%% Opts:
%%   log_dir => dirname() | undefined  — enable disk logger on each peer
start_nodes(Ns, Opts) when is_map(Opts) ->
    Nodes = [start_node(N, Opts) || N <- Ns],
    mesh_connect(Nodes),
    case maps:get(log_dir, Opts, undefined) of
        undefined -> ok;
        LogDir    -> [setup_peer_logger(N, LogDir) || N <- Nodes]
    end,
    Nodes.

start_node(Name0) ->
    start_node(Name0, #{}).

start_node(Name0, Opts) when is_map(Opts) ->
    {Name, _} = eunit_lib:split_node(Name0),
    ensure_dist(),
    {Pa, Pz} = paths(),
    Paths = lists:append([["-pa", "./", "-pz", "../ebin"]]
                         ++ [["-pa", Path] || Path <- Pa]
                         ++ [["-pz", Path] || Path <- Pz]),
    Args = ["-kernel", "prevent_overlapping_partitions", "false",
            "-kernel", "logger_level", "debug"
            | Paths],
    %% standard_io control so intentional dist drops do not kill the peer.
    {ok, Pid, Node} = peer:start(#{ name => Name
                                  , host => host_string()
                                  , args => Args
                                  , connection => standard_io }),
    save_controlling_pid(Node, Pid),
    case maps:get(log_dir, Opts, undefined) of
        undefined -> ok;
        LogDir    -> setup_peer_logger(Node, LogDir)
    end,
    Node.

%% Full mesh among peers.
mesh_connect(Nodes) ->
    [begin
         true = rpc:call(A, net_kernel, connect_node, [B])
     end || A <- Nodes, B <- Nodes, A =/= B],
    ok.

%% Start gproc (and thus locks + gproc_dist) on every peer; wait until
%% gproc_dist role properties agree on a leader (see wait_dist_ready/1).
start_gproc(Ns) ->
    {Results, Bad} = rpc:multicall(Ns, application, ensure_all_started, [gproc]),
    [] = Bad,
    [case R of
         {ok, _} -> ok;
         {error, {already_started, _}} -> ok;
         Other -> error({gproc_start_failed, Other})
     end || R <- Results],
    %% Remote subscribe needs gproc already running on the peer.
    %% Role properties are authoritative if we miss early events.
    ok = subscribe_dist_events(Ns),
    wait_gproc_leader(Ns),
    ok.

wait_gproc_leader(Ns) ->
    wait_dist_ready(Ns).

%% Controller: remote-subscribe to local lifecycle events on each peer.
%% Messages: {gproc_ps_event, gproc_dist, RoleMsg}.
subscribe_dist_events(Ns) ->
    Ev = gproc_dist:lifecycle_event(),
    lists:foreach(fun(N) -> true = gproc_ps:subscribe_remote(N, Ev) end, Ns),
    ok.

%% Wait until every node has a gproc_dist_role property of
%% {elected, L} or {following, L} for the same L. Drain pub/sub events while
%% waiting (useful diagnostics; property is authoritative if we subscribed late).
wait_dist_ready(Ns) ->
    wait_dist_ready(Ns, 100).

wait_dist_ready(Ns, 0) ->
    error({dist_not_ready, Ns, [{N, role_on(N)} || N <- Ns]});
wait_dist_ready(Ns, I) ->
    _ = drain_lifecycle_events(),
    case roles_agree(Ns) of
        {ok, Leader} ->
            Leader;
        _ ->
            timer:sleep(50),
            wait_dist_ready(Ns, I - 1)
    end.

drain_lifecycle_events() ->
    Ev = gproc_dist:lifecycle_event(),
    receive
        {gproc_ps_event, Ev, _Msg} ->
            drain_lifecycle_events()
    after 0 ->
            ok
    end.

roles_agree(Ns) ->
    Roles = [{N, role_on(N)} || N <- Ns],
    %% undefined can appear if leader_node/1 was read before the election
    %% opaque had leader set; never treat it as agreement.
    Leaders =
        [L || {_, {elected, L}} <- Roles, is_atom(L), L =/= undefined] ++
        [L || {_, {following, L}} <- Roles, is_atom(L), L =/= undefined],
    case {lists:usort(Leaders), length(Roles) =:= length(Ns)} of
        {[Leader], true} ->
            case lists:all(
                   fun({_, {elected, L}}) -> L =:= Leader;
                      ({_, {following, L}}) -> L =:= Leader;
                      (_) -> false
                   end, Roles) of
                true  -> {ok, Leader};
                false -> error
            end;
        _ ->
            error
    end.

role_on(N) ->
    case rpc:call(N, gproc, lookup_values, [{p, l, gproc_dist_role}]) of
        [{_Pid, {elected, _} = R}]   -> R;
        [{_Pid, {following, _} = R}] -> R;
        []                           -> undefined;
        {badrpc, _} = E              -> E;
        Other                        -> Other
    end.

%% Disk log per peer under LogDir/<node>.log (logger_std_h).
setup_peer_logger(Node, LogDir) ->
    ok = filelib:ensure_dir(filename:join(LogDir, "dummy")),
    File = filename:join(LogDir, atom_to_list(Node) ++ ".log"),
    ok = rpc:call(Node, logger, set_primary_config, [level, debug]),
    %% Replace default handler so everything hits the file (and keep stderr
    %% free of CT noise). Fail soft if already configured.
    _ = rpc:call(Node, logger, remove_handler, [default]),
    case rpc:call(Node, logger, add_handler,
                  [default, logger_std_h,
                   #{level => debug,
                     config => #{file => File},
                     formatter =>
                         {logger_formatter,
                          #{template => [time, " ", level, " ",
                                         {pid, ["[", pid, "] "], []},
                                         msg, "\n"]}}}]) of
        ok -> ok;
        {error, {already_exist, _}} -> ok;
        Other -> error({peer_logger_failed, Node, Other})
    end,
    ok.

stop_nodes(Ns) ->
    [stop_node(N) || N <- Ns],
    ok.

stop_node(N) ->
    Pid = get_controlling_pid(N),
    try peer:stop(Pid)
    after
        delete_controlling_pid(N)
    end.

save_controlling_pid(Node, Pid) ->
    persistent_term:put({?MODULE, peer_ref, Node}, Pid).

get_controlling_pid(Node) ->
    persistent_term:get({?MODULE, peer_ref, Node}).

delete_controlling_pid(Node) ->
    persistent_term:erase({?MODULE, peer_ref, Node}).

paths() ->
    Path = code:get_path(),
    {ok, [[Root]]} = init:get_argument(root),
    {Pas, Rest} = lists:splitwith(fun(P) ->
                                          not lists:prefix(Root, P)
                                  end, Path),
    {_, Pzs} = lists:splitwith(fun(P) ->
                                       lists:prefix(Root, P)
                               end, Rest),
    {Pas, Pzs}.


host_string() ->
    [_Name, Host] = re:split(atom_to_list(node()), "@", [{return, list}]),
    Host.

node_name(NamePart) ->
    ensure_dist(),
    list_to_atom(atom_to_list(NamePart) ++ "@" ++ host_string()).

ensure_dist() ->
    case node() of
        nonode@nohost ->
            os:cmd("epmd -daemon"),
            {ok, _} = net_kernel:start([gproc_master, shortnames]),
            true;
        _ ->
            false
    end.

%% ============================================================
%% Spawned helpers on peer nodes
%% ============================================================

t_spawn(Node) ->
    t_spawn(Node, false).

t_spawn(Node, Selective) when is_boolean(Selective) ->
    Me = self(),
    P = spawn(Node, fun() ->
                            Me ! {self(), ok},
                            t_loop(Selective)
                    end),
    receive
        {P, ok} -> P
    after 1000 ->
            erlang:error({timeout, t_spawn, [Node, Selective]})
    end.

t_spawn_reg(Node, Name) ->
    t_spawn_reg(Node, Name, default_value(Name)).

t_spawn_reg(Node, Name, Value) ->
    Me = self(),
    P = spawn(Node, fun() ->
                            ?assertMatch(true, gproc:reg(Name, Value)),
                            Me ! {self(), ok},
                            t_loop()
                    end),
    receive
        {P, ok} ->
            P
    after 1000 ->
            erlang:error({timeout, t_spawn_reg, [Node, Name, Value]})
    end.

t_spawn_reg(Node, Name, Value, Attrs) ->
    Me = self(),
    P = spawn(Node, fun() ->
                            ?assertMatch(true, gproc:reg(Name, Value, Attrs)),
                            Me ! {self(), ok},
                            t_loop()
                    end),
    receive
        {P, ok} ->
            P
    after 1000 ->
            erlang:error({timeout, t_spawn_reg, [Node, Name, Value]})
    end.

t_spawn_mreg(Node, KVL) ->
    t_spawn_mreg(Node, n, KVL).

t_spawn_mreg(Node, T, KVL) ->
    Me = self(),
    P = spawn(Node, fun() ->
                            ?assertMatch(true, gproc:mreg(T, g, KVL)),
                            Me ! {self(), ok},
                            t_loop()
                    end),
    receive
        {P, ok} ->
            P
    after 1000 ->
            error({timeout, t_spawn_mreg, [Node, T, KVL]})
    end.


t_spawn_reg_shared(Node, Name, Value) ->
    Me = self(),
    P = spawn(Node, fun() ->
                            ?assertMatch(true, gproc:reg_shared(Name, Value)),
                            Me ! {self(), ok},
                            t_loop()
                    end),
    receive
        {P, ok} -> P
    after 1000 ->
              erlang:error({timeout, t_spawn_reg_shared, [Node,Name,Value]})
    end.

default_value({c,_,_}) -> 0;
default_value(_) -> undefined.

t_call(P, Req) ->
    Ref = erlang:monitor(process, P),
    P ! {self(), Ref, Req},
    receive
        {P, Ref, Res} ->
            erlang:demonitor(Ref, [flush]),
            Res;
        {'DOWN', Ref, _, _, Error} ->
            erlang:error({'DOWN', P, Error})
    after 1000 ->
            erlang:error({timeout,t_call,[P,Req]})
    end.

t_loop() ->
    t_loop(false).

t_loop(Selective) when is_boolean(Selective) ->
    receive
        {From, Ref, die} ->
            From ! {self(), Ref, ok};
        {From, Ref, {selective, Bool}} when is_boolean(Bool) ->
            From ! {self(), Ref, ok},
            t_loop(Bool);
        {From, Ref, {apply, M, F, A}} ->
            From ! {self(), Ref, apply(M, F, A)},
            t_loop(Selective);
        {From, Ref, {apply_fun, F}} ->
            From ! {self(), Ref, F()},
            t_loop(Selective);
        Other when not Selective ->
            ?debugFmt("got unknown msg: ~p~n", [Other]),
            exit({unknown_msg, Other})
    end.

got_msg(Pb) ->
    t_call(Pb,
           {apply_fun,
            fun() ->
                    receive M -> M
                    after 1000 ->
                            erlang:error({timeout, got_msg, [Pb]})
                    end
            end}).

got_msg(Pb, Tag) ->
    t_call(Pb,
           {apply_fun,
            fun() ->
                    receive
                        M when element(1, M) == Tag ->
                            M
                    after 1000 ->
                            erlang:error({timeout, got_msg, [Pb, Tag]})
                    end
            end}).

no_msg(Pb, Timeout) ->
    t_call(Pb,
           {apply_fun,
            fun() ->
                    receive
                        M ->
                            erlang:error({unexpected_msg, M})
                    after Timeout ->
                            ok
                    end
            end}).

t_pool_contains_atleast(Pool,N)->
    Existing = lists:foldl(fun({_X,_Y},Acc)->
                                   Acc+1;
                              (_,Acc) ->
                                   Acc
                           end, 0, gproc_pool:worker_pool(Pool) ),
    Existing >= N.
