-module(gproc_ext).

-export([reg_type/2]).


reg_type(rw, _N) ->
    #{tag => rw,
      type => r,
      unique => false,
      scan   => [],
      aggr   => [],
      rc     => [#{tag => rwc}, #{tag => rwc, wild => [0]}]};
reg_type(rcw, _N) ->
    #{tag    => rcw,
      type   => rc,
      unique => true,
      scan   => [#{tag => rc}],
      aggr   => [],
      rc     => []};
reg_type(_, _) ->
    undefined.
