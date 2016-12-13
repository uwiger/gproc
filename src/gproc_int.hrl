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
%% @author Ulf Wiger <ulf.wiger@feuerlabs.com
%%
%% gproc_int.hrl: Shared internal definitions

-define(CATCH_GPROC_ERROR(Expr, Args),
	try Expr
	catch
	    throw:{gproc_error, GprocError} ->
		erlang:error(GprocError, Args)
	end).

-define(THROW_GPROC_ERROR(E), throw({gproc_error, E})).

%% Used to wrap operations that may fail, but we ignore the exception.
%% Use instead of catch, to avoid building a stacktrace unnecessarily.
-define(MAY_FAIL(Expr), try (Expr) catch _:_ -> '$caught_exception' end).

-ifdef(GPROC_EXT).
-define(GPROC_EXT_CB, ?GPROC_EXT).
-else.
-define(GPROC_EXT_CB, gproc_ext).
-endif.
