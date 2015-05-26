-module(envtest).
-compile(export_all).


init() ->
    ets:new(?MODULE, [public,named_table,ordered_set]),
    gproc:reg_shared({p,l,getenv}, {?MODULE, get_env}),
    gproc:reg_shared({p,l,getenvc}, {?MODULE, get_env, cache}),
    gproc:reg_shared({p,l,setenv}, {?MODULE, set_env}).

write(App, Key, Value) ->
    ets:insert(?MODULE, {{App,Key}, Value}).

get_env(App, Key, Prop) ->
    io:fwrite("~p:get_env(~p, ~p, ~p)~n", [?MODULE, App, Key, Prop]),
    case ets:lookup(?MODULE, {App,Key}) of
	[{_, Value}] ->
	    {ok, Value};
	_ ->
	    undefined
    end.

get_env(App, Key, Value, Prop) ->
    io:fwrite("~p:get_env(~p, ~p, ~p, ~p) (CACHE!)~n",
	      [?MODULE, App, Key, Value, Prop]),
    write(App, Key, Value).

set_env(App, Key, Value, Prop) ->
    io:fwrite("~p:set_env(~p, ~p, ~p, ~p)~n", [?MODULE, App, Key, Value, Prop]),
    write(App, Key, Value).
