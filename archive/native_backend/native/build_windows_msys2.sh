#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="${ROOT_DIR}/src"
OUT_DIR="${ROOT_DIR}/win"
OUT_FILE="${OUT_DIR}/scaleplusplus_native.so"

mkdir -p "${OUT_DIR}"

RUBY_INCLUDE_DIR="$(ruby -rrbconfig -e 'print RbConfig::CONFIG["rubyhdrdir"]')"
RUBY_ARCH_INCLUDE_DIR="$(ruby -rrbconfig -e 'print RbConfig::CONFIG["rubyarchhdrdir"]')"
RUBY_LIB_DIR="$(ruby -rrbconfig -e 'print RbConfig::CONFIG["libdir"]')"
RUBY_LIB_A="$(ruby -rrbconfig -e 'print File.join(RbConfig::CONFIG["libdir"], RbConfig::CONFIG["LIBRUBY_A"])')"

g++ \
  -std=c++17 \
  -O2 \
  -shared \
  -fPIC \
  -I"${RUBY_INCLUDE_DIR}" \
  -I"${RUBY_ARCH_INCLUDE_DIR}" \
  "${SRC_DIR}/scale_engine.cpp" \
  "${SRC_DIR}/ruby_bridge.cpp" \
  "${RUBY_LIB_A}" \
  -L"${RUBY_LIB_DIR}" \
  -o "${OUT_FILE}"

echo "Built ${OUT_FILE}"
