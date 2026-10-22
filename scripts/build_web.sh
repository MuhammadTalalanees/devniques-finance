#!/usr/bin/env bash
# Devniques Finance — web build + deploy prep (STANDING RECIPE, 2026-10-20)
# Teeno cheezein lazmi hain, warna site white screen degi:
#  1) --base-href /devniques-finance/  (site is path ke andar hai;
#     default "/" ho to saari files root se mangi ja kar 404 hoti hain)
#  2) --no-web-resources-cdn           (CanvasKit site ke andar se load
#     ho, Google CDN se nahi)
#  3) inline_bootstrap.py              (bootstrap index.html ke andar;
#     alag file Talal ke net par 404 hoti hai)
set -e
export PATH=~/flutter-sdk/f347/flutter/bin:$PATH
cd "$(dirname "$0")/.."
flutter build web --release --no-web-resources-cdn --base-href /devniques-finance/
python3 scripts/inline_bootstrap.py
grep -o '<base[^>]*>' build/web/index.html
echo "BUILD READY in build/web — ab gh-pages par rsync + push karo."
