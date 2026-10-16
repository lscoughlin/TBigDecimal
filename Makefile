# TBigDecimal build file
FPC      ?= fpc
COMMON   = -MObjFPC -Sh- -dMATH -Fusrc -Futests -FUlib -FEbin
DEBUG    = $(COMMON) -g -gl -Cr -Co -Ct -O1
RELEASE  = $(COMMON) -O3

.PHONY: test bench benchsmall benchcompare clean refs vectors heaptest

refs:
	sh tools/fetchrefs.sh

vectors:
	@test -f tests/vectors/add.txt || (sh tools/setup-venv.sh && tools/.venv/bin/python tools/genvectors.py 3000)

test: refs vectors
	@mkdir -p lib bin
	$(FPC) $(DEBUG) tests/RunTests.lpr
	./bin/RunTests --all --format=plain

bench:
	@mkdir -p lib bin
	$(FPC) $(RELEASE) bench/BenchAll.lpr
	./bin/BenchAll

benchsmall:
	@mkdir -p lib bin
	$(FPC) $(RELEASE) bench/BenchSmall.lpr
	./bin/BenchSmall

# Prints timings for the operations that tools/benchpython.py times in Python.
benchcompare:
	@mkdir -p lib bin
	$(FPC) $(RELEASE) bench/BenchCompare.lpr
	./bin/BenchCompare
	python3 -W ignore tools/benchpython.py

clean:
	rm -rf lib bin

# Debug build with heap tracing. The run reports unfreed blocks at exit.
heaptest: refs vectors
	@mkdir -p lib/heap bin
	$(FPC) $(COMMON) -g -gh -gl -Cr -Co -Ct -O1 -FUlib/heap -oRunTestsHeap tests/RunTests.lpr
	./bin/RunTestsHeap --all --format=plain
