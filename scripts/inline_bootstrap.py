#!/usr/bin/env python3
"""Inline flutter_bootstrap.js into build/web/index.html.

Why (2026-10-20): Talal's network/proxy returns 404 for the separate
flutter_bootstrap.js file while index.html itself loads fine, so the
app never starts (white screen). Inlining removes that request.
Run AFTER every `flutter build web` and BEFORE deploying build/web.
"""
import pathlib
import sys

web = pathlib.Path(__file__).resolve().parent.parent / "build" / "web"
index_path = web / "index.html"
boot_path = web / "flutter_bootstrap.js"

index = index_path.read_text(encoding="utf-8")
boot = boot_path.read_text(encoding="utf-8")

if "</script" in boot.lower():
    boot = boot.replace("</script", "<\\/script")

tag = '<script src="flutter_bootstrap.js" async></script>'
if tag not in index:
    print("ERROR: bootstrap script tag not found in index.html "
          "(already inlined?)")
    sys.exit(1)

index = index.replace(tag, "<script>\n" + boot + "\n</script>")
index_path.write_text(index, encoding="utf-8")
print(f"OK: inlined bootstrap ({len(boot)} chars) into index.html "
      f"({len(index)} chars total)")
