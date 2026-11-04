#!/usr/bin/env bash
# Regenerate parity fixtures from the Python rules engine and copy shared seed files into the Flutter app.
set -euo pipefail
cd "$(dirname "$0")/.."
(cd backend && python scripts/make_parity_fixtures.py)
cp seed/demo_seed.json seed/assistant_copy.json flutter_app/assets/seed/
mkdir -p flutter_app/test/fixtures && cp seed/parity_fixtures.json flutter_app/test/fixtures/
echo "Seed synced. Run: (cd flutter_app && flutter test test/parity_test.dart)"
