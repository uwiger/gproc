## The MIT License
##
## Copyright (c) 2008 Ulf Wiger <ulf@wiger.net>,
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


.SUFFIXES: .erl .beam

vpath %.beam ../ebin
vpath %.pdf ../doc

ERLC = erlc -W -o ../ebin +debug_info
EQC = /host/dev/eqc-1.16/ebin
ERL_EQC = erl -pz ../ebin -pz $(EQC) -kernel error_logger silent

beams = gproc.beam \
	gproc_app.beam \
	gproc_dist.beam \
	gproc_lib.beam \
	gproc_sup.beam

all : $(beams)
test : all gproc_eqc.beam
	$(ERL_EQC) -s gproc_eqc run

itest : all gproc_eqc.beam
	$(ERL_EQC) -s eqc start

clean :
	rm -f *~ #*# 

$(beams) : %.beam : %.erl
	$(ERLC) $<

gproc_eqc.beam : gproc_eqc.erl
	$(ERLC) -pz $(EQC) gproc_eqc.erl
