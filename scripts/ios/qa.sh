#!/usr/bin/env bash
# Wrapper Unix — délègue à qa.mjs
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
exec node "$ROOT/scripts/ios/qa.mjs" "$@"
