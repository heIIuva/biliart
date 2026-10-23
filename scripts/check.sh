#!/usr/bin/env bash
# All offline checks: format, lint, strict types, tests. Run from the repo root.
set -euo pipefail
cd "$(dirname "$0")/.."

stylua --check --glob "!**/Packages/**" src tests tools
selene src tests tools

[ -f globalTypes.d.luau ] || curl -sSfL https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau -o globalTypes.d.luau
rojo sourcemap -o sourcemap.json
luau-lsp analyze --definitions=globalTypes.d.luau --sourcemap=sourcemap.json --ignore="**/Packages/**" src

lune run tests/run
