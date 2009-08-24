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

ERLC = erlc -W -I ../include -o ../ebin
ERLC += +debug_info

EQC ?= /host/dev/eqc-1.16/ebin

EQC_ERLC = $(ERLC) -I $(EQC)/include
EQC_ERL = erl -pz ../ebin -pz $(EQC)/ebin -pz ./Unit-Quick-Files -kernel error_logger silent

beams = gproc.beam \
	gproc_app.beam \
	gproc_dist.beam \
	gproc_lib.beam \
	gproc_sup.beam

all : $(beams)
clean :
	rm -f  *~ ../ebin/*.beam ./Unit-Quick-Files/*.beam

## erlc targets
$(beams) : %.beam : %.erl
	$(ERLC) $<

./Unit-Quick-Files/gproc_eqc.beam : ./Unit-Quick-Files/gproc_eqc.erl
	$(EQC_ERLC) $<

## test targets
test : all ./Unit-Quick-Files/gproc_eqc.beam
	$(EQC_ERL) -s gproc_eqc run

itest : all ./Unit-Quick-Files/gproc_eqc.beam
	$(EQC_ERL) -s eqc start
