#!/usr/bin/env bash
#
# mayhem/build.sh — build scnlib's libFuzzer harnesses (sanitized) plus its unit tests (normal flags).
# Runs inside the commit image as `mayhem` in /mayhem. Offline: fast_float and GoogleTest come from
# apt packages baked into the image (see mayhem/Dockerfile), never from CMake FetchContent.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${STANDALONE_FUZZ_MAIN:=/opt/mayhem/StandaloneFuzzTargetMain.c}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

# Options shared by both CMake builds: only the `scn` library and (for the test build) the unit tests.
COMMON_OPTS=(-G Ninja
  -DSCN_DOCS=OFF -DSCN_EXAMPLES=OFF -DSCN_INSTALL=OFF -DSCN_BENCHMARKS=OFF
  -DSCN_BENCHMARKS_BUILDTIME=OFF -DSCN_BENCHMARKS_BINARYSIZE=OFF
  -DSCN_USE_EXTERNAL_FAST_FLOAT=ON -DSCN_USE_EXTERNAL_GTEST=ON)

# 1) The library, instrumented: sanitizers + coverage (fuzzer-no-link) + DWARF 3.
FUZZ_BUILD="$SRC/build/mayhem-fuzz"
cmake -S . -B "$FUZZ_BUILD" "${COMMON_OPTS[@]}" -DSCN_TESTS=OFF -DCMAKE_BUILD_TYPE=None \
  -DCMAKE_CXX_FLAGS="-O1 $SANITIZER_FLAGS -fsanitize=fuzzer-no-link $DEBUG_FLAGS"
cmake --build "$FUZZ_BUILD" -j"$MAYHEM_JOBS" --target scn

# 2) Harnesses: libFuzzer binary + standalone (run-once) reproducer each. LSan is switched off at build time.
INC=(-I"$SRC/include" -I"$SRC/src" -I"$FUZZ_BUILD/include" -I"$SRC/tests/fuzz")
HFLAGS=(-std=c++17 -O1 $SANITIZER_FLAGS -fsanitize=fuzzer-no-link $DEBUG_FLAGS -Wno-missing-prototypes)
OBJ="$SRC/build/mayhem-obj"; mkdir -p "$OBJ"
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$OBJ/standalone_main.o"
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -o "$OBJ/lsan_off.o"

for name in int float string format chrono string_impl file; do
  src="$SRC/tests/fuzz/${name}_fuzz.cpp"
  # file: copy of upstream's harness minus its 5 s wall-clock check (Mayhem owns timeouts).
  [ "$name" != file ] || src="$SRC/mayhem/file_fuzz.cpp"
  $CXX "${HFLAGS[@]}" "${INC[@]}" -c "$src" -o "$OBJ/${name}_fuzz.o"
  $CXX $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE "$OBJ/${name}_fuzz.o" "$OBJ/lsan_off.o" \
    "$FUZZ_BUILD/libscn.a" -o "/mayhem/scn_fuzz_$name"
  $CXX $SANITIZER_FLAGS $DEBUG_FLAGS "$OBJ/${name}_fuzz.o" "$OBJ/standalone_main.o" "$OBJ/lsan_off.o" \
    "$FUZZ_BUILD/libscn.a" -o "/mayhem/scn_fuzz_$name-standalone"
done

# 3) Upstream's unit tests + the known-answer probe, with the project's normal flags (no sanitizers).
TEST_BUILD="$SRC/build/mayhem-tests"
cmake -S . -B "$TEST_BUILD" "${COMMON_OPTS[@]}" -DSCN_TESTS=ON -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_CXX_FLAGS="$COVERAGE_FLAGS"
cmake --build "$TEST_BUILD" -j"$MAYHEM_JOBS" --target scn_tests scn_impl_tests
cp "$TEST_BUILD/tests/unittests/scn_tests" "$TEST_BUILD/tests/unittests/scn_impl_tests" /mayhem/
$CXX -std=c++17 -O1 $COVERAGE_FLAGS -I"$SRC/include" -I"$TEST_BUILD/include" "$SRC/mayhem/kat.cpp" \
  "$TEST_BUILD/libscn.a" -o /mayhem/scn_kat
