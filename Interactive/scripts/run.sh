#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
"$ROOT/scripts/make_app.sh"
killall MacPet 2>/dev/null || true
sleep 0.2
open "$ROOT/MacPet.app"
