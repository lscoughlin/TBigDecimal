# TBigDecimal build file
FPC      ?= fpc
COMMON   = -MObjFPC -Sh- -dMATH -Fusrc -Futests -FEbin
# each profile has its own unit directory: FPC does not rebuild a unit when only the options change
DEBUG    = $(COMMON) -FUlib/debug -g -gl -Cr -Co -Ct -O1
RELEASE  = $(COMMON) -FUlib/release -O3

.PHONY: test bench benchsmall benchcompare benchbcd profile clean refs vectors heaptest

refs:
	sh tools/fetchrefs.sh

vectors:
	@test -f tests/vectors/add.txt || (sh tools/setup-venv.sh && tools/.venv/bin/python tools/genvectors.py 3000)

test: refs vectors
	@mkdir -p lib/debug bin
	$(FPC) $(DEBUG) tests/RunTests.lpr
	./bin/RunTests --all --format=plain

bench:
	@mkdir -p lib/release bin
	$(FPC) $(RELEASE) bench/BenchAll.lpr
	./bin/BenchAll

benchsmall:
	@mkdir -p lib/release bin
	$(FPC) $(RELEASE) bench/BenchSmall.lpr
	./bin/BenchSmall

# Prints timings for the operations that tools/benchpython.py times in Python.
benchcompare:
	@mkdir -p lib/release bin
	$(FPC) $(RELEASE) bench/BenchCompare.lpr
	./bin/BenchCompare
	python3 -W ignore tools/benchpython.py

# Compares add, multiply and divide with TBcd of the RTL unit FmtBCD.
benchbcd:
	@mkdir -p lib/release bin
	$(FPC) $(RELEASE) bench/BenchBcd.lpr
	./bin/BenchBcd

# Samples each 34-digit operation for 3 seconds and prints the top frames.
# Needs the macOS `sample` tool.
profile:
	@mkdir -p lib/profile bin
	$(FPC) $(COMMON) -FUlib/profile -O3 -g bench/ProfileSmall.lpr
	@for op in m d a s e l; do \
	  ./bin/ProfileSmall $$op > /dev/null & \
	  sleep 1; sample ProfileSmall 3 -file bin/profile-$$op.txt > /dev/null 2>&1; \
	  echo "== operation $$op"; \
	  grep -A12 'Sort by top of stack' bin/profile-$$op.txt | tail -12 | cut -c1-110; \
	  kill $$! 2>/dev/null; wait 2>/dev/null; \
	done

clean:
	rm -rf lib bin

# Debug build with heap tracing. The run reports unfreed blocks at exit.
heaptest: refs vectors
	@mkdir -p lib/heap bin
	$(FPC) $(COMMON) -g -gh -gl -Cr -Co -Ct -O1 -FUlib/heap -oRunTestsHeap tests/RunTests.lpr
	./bin/RunTestsHeap --all --format=plain
