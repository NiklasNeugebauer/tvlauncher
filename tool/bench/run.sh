#!/bin/bash
# Builds the desktop home-screen bench (profile mode) and runs it; prints one `BENCH {json}` line and keeps the
# report in build/bench/latest.json. BENCH_PASSES (default 3) sets the measured passes after one warmup.
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p build/bench
mise exec -- flutter build linux --profile -t lib/desktop/main_bench.dart >build/bench/build.log 2>&1 \
  || { tail -30 build/bench/build.log; exit 1; }
# One instance at a time: a second launcher window would compete for the GPU.
pkill -x tvlauncher || true
BENCH_OUT=build/bench/latest.json build/linux/x64/profile/bundle/tvlauncher >build/bench/run.log 2>&1
grep "^BENCH" build/bench/run.log || [ -n "${BENCH_SHOTS:-}" ]
