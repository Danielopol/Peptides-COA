#!/usr/bin/env bash
# Vercel build for the Flutter web app. Kept in a script because Vercel caps the
# inline buildCommand at 256 chars. Invoked via "bash build.sh" from vercel.json.
set -euo pipefail

git clone https://github.com/flutter/flutter.git -b stable --depth 1

flutter/bin/flutter build web --release \
  --dart2js-optimization=O2 \
  --no-source-maps \
  --no-tree-shake-icons \
  --dart-define=API_BASE_URL=https://peptides-coa-production.up.railway.app \
  --dart-define=USE_MOCK=false
