%%% File        : gproc_eqc_node_tests.erl
%%% Author      : Hans Svensson
%%% Description :
%%% Created     : 14 Sep 2017 by Hans Svensson
-module(gproc_eqc_node_tests).

-compile([export_all, nowarn_export_all]).

-ifdef(EQC).
-include_lib("eqc/include/eqc.hrl").
-include_lib("eqc/include/eqc_statem.hrl").
-endif.

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-define(TIMEOUT, 100).

%% -- EUnit stuff ------------------------------------------------------------
gproc_node_test_() ->
  {timeout, 60, [fun() -> ?assert(run(100)) end]}.

run(N) ->
  erlang:group_leader(whereis(user), self()),
  error_logger:delete_report_handler(error_logger_tty_h),
  eqc:quickcheck(eqc:numtests(N, prop_nodes())).

%% -- State ------------------------------------------------------------------

-record(state, { nodes = [] }).

-record(node, { id, worker, monitors = [] }).

initial_state() -> #state{}.

-define(NODES, [a, b, c, d]).

%% -- Generators -------------------------------------------------------------

gen_monitor() ->
  elements([x, y, z]).

%% -- Operations -------------------------------------------------------------

%% --- start_node ---

start_node_args(S) ->
  [elements(?NODES), [Id || #node{ id = Id } <-S#state.nodes ]].

start_node_pre(S, [Node, Ns]) ->
  not lists:keymember(Node, #node.id, S#state.nodes)
    andalso lists:all(fun(N) -> lists:keymember(N, #node.id, S#state.nodes) end, Ns).

start_node_adapt(S, [Node, _Ns]) ->
  [Node, [Id || #node{ id = Id } <- S#state.nodes]].

start_node(NodeName, Ns) ->
  case slave:start(element(2, inet:gethostname()), NodeName,
                   "-gproc gproc_dist all -pa ../../gproc/ebin -pa ../../gproc/deps/*/ebin") of
    {ok, Node} ->
      [ pong = rpc:call(Node, net_adm, ping, [mk_node(N)]) || N <- Ns ],
      Worker = rpc:call(Node, ?MODULE, start_worker, [self()]),
      {ok, Worker} = worker_rpc(Worker, init),
      Worker;
    Err ->
      Err
  end.

start_node_next(S, V, [Node, _]) ->
  S#state{ nodes = S#state.nodes ++ [#node{ id = Node, worker = V }] }.

start_node_post(_S, [_Node, _], V) ->
  case V of
    Pid when is_pid(Pid) -> true;
    Err                  -> eq(Err, '<pid>')
  end.


%% --- stop_node ---

stop_node_pre(S) ->
  S#state.nodes /= [].

stop_node_args(S) ->
  [?LET(Node, elements(S#state.nodes), Node#node.id)].

stop_node(Id) ->
  slave:stop(mk_node(Id)), timer:sleep(20).

stop_node_next(S, _, [Id]) ->
  S#state{ nodes = lists:keydelete(Id, #node.id, S#state.nodes) }.


%% --- monitor ---

monitor_pre(S) ->
  S#state.nodes /= [].

monitor_args(S) ->
  [elements(S#state.nodes), gen_monitor()].

monitor_pre(S, [Node, _]) ->
  lists:member(Node, S#state.nodes).

monitor_adapt(S, [#node{ id = Id }, Mon]) ->
  case lists:keyfind(Id, #node.id, S#state.nodes) of
    false -> false;
    Node  -> [Node, Mon]
  end.

monitor(#node{ worker = Worker }, Monitor) ->
  worker_rpc(Worker, monitor, {n, g, Monitor}).

monitor_next(S, Ref, [#node{ id = NId }, Monitor]) ->
  Node = get_node(NId, S),
  set_node(Node#node{ monitors = Node#node.monitors ++ [{Monitor, Ref}] }, S).

monitor_post(_S, [_Node, _Monitor], Ref) ->
  is_reference(Ref).


%% --- check_node ---
check_node_pre(S) ->
  S#state.nodes /= [].

check_node_args(S) ->
  [elements(S#state.nodes)].

check_node_pre(S, [Node]) ->
  lists:member(Node, S#state.nodes).

check_node_adapt(S, [#node{ id = Id }]) ->
  case lists:keyfind(Id, #node.id, S#state.nodes) of
    false -> false;
    Node  -> [Node]
  end.

check_node(#node{ worker = Worker }) ->
  worker_rpc(Worker, check).

check_node_post(S, [#node{ id = NId }], Res) ->
  case Res of
    {ok, Table} ->
      check_table(S, NId, Table);
    Err -> eq(Err, ok)
  end.

check_table(_, _, Table) ->
  Pids = [ {io_lib:format("~p", [Pid]), Pid} || {{Pid, {n, g, _}}, _} <- Table ],
  case [ {P, lists:usort(Ps)} || {P, Ps} <- eqc_cover:group(1, lists:keysort(1, Pids)),
                                 length(lists:usort(Ps)) > 1 ] of
    [] -> true;
    Gs -> eq(Gs, [])
  end.

%% -- Common -----------------------------------------------------------------
get_node(Id, #state{ nodes = Nodes }) ->
  lists:keyfind(Id, #node.id, Nodes).

set_node(Node = #node{ id = NId }, S = #state{ nodes = Nodes }) ->
  S#state{ nodes = lists:keystore(NId, #node.id, Nodes, Node) }.

cleanup() ->
  [ slave:stop(mk_node(N)) || N <- ?NODES ].

mk_node(N) ->
  list_to_atom(lists:concat([N, '@', element(2, inet:gethostname())])).

start_worker(Mama) ->
  spawn(fun() ->
    {ok, [gproc]} = application:ensure_all_started(gproc),
    worker(Mama, []) end).

worker_rpc(Worker, Cmd) ->
  worker_rpc(Worker, Cmd, unused).

worker_rpc(Worker, Cmd, Args) ->
  Ref = make_ref(),
  Worker ! {self(), Ref, Cmd, Args},
  receive {Ref, Res} -> Res
  after ?TIMEOUT     -> {worker_error, timeout} end.

worker(Mama, Data) ->
  receive
    {Mama, Ref, Cmd, Args} ->
      Res = case Cmd of
              init    -> {ok, self()};
              monitor -> (catch gproc:monitor(Args, follow));
              check   -> {ok, ets:tab2list(gproc)}
            end,
      Mama ! {Ref, Res},
      worker(Mama, Data);
    Msg ->
      %% All gproc messages are just tagged with node and sent to Mama
      Mama ! {node(), Msg},
      worker(Mama, Data)
  end.

%% -- Property ---------------------------------------------------------------

weight(_, check_node) -> 5;
weight(_, start_node) -> 3;
weight(_, monitor)    -> 3;
weight(_, _)          -> 1.


%% The property.
prop_nodes() -> prop_nodes(?MODULE).
prop_nodes(Mod) ->
  ?SETUP(fun() -> setup(), fun() -> ok end end,
  ?FORALL(Cmds, commands(Mod),
  begin
    cleanup(),
    HSR={_, _, Res} = run_commands(Mod, Cmds),
    cleanup(),
    ?WHENFAIL(flush(), %% For debugging, get all messages from workers
    pretty_commands(Mod, Cmds, HSR,
    check_command_names(Mod, Cmds,
      Res == ok)))
  end)).

setup() ->
  case is_alive() of
    false -> {ok, _} = net_kernel:start([eqc, shortnames]);
    true  -> ok
  end.

flush() ->
  receive Msg -> io:format("Msg: ~p\n", [Msg]), flush()
  after 1 -> ok end.

