-define(event(E), event(?LINE, E, [])).
-define(event(E, S), event(?LINE, E, S)).

event(_L, _E, _S) ->
    ok.
