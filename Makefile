## The MIT License
##
## Copyright (c) 2008-2010 Ulf Wiger <ulf@wiger.net>,
##
## Permission is hereby granted, free of charge, to any person obtaining a
## copy of this software and associated documentation files (the "Software"),
## to deal in the Software without restriction, including without limitation
## the rights to use, copy, modify, merge, publish, distribute, sublicense,
## and/or sell copies of the Software, and to permit persons to whom the
## Software is furnished to do so, subject to the following conditions:
##
## The above copyright notice and this permission notice shall be included in
## all copies or substantial portions of the Software.
##
## THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
## IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
## FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
## THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
## LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
## FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
## DEALINGS IN THE SOFTWARE.
REBAR3=$(shell which rebar3 || echo ./rebar3)

.PHONY: all compile clean eunit test doc check dialyzer

DIRS=src

all: check test

check: compile dialyzer

compile:
	$(REBAR3) compile

clean:
	$(REBAR3) clean

eunit:
	$(REBAR3) eunit

test: eunit

doc:
	$(REBAR3) as edown edoc

dialyzer:
	GPROC_DIST=true $(REBAR3) dialyzer
