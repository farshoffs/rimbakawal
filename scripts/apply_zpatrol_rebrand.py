#!/usr/bin/env python3
"""Apply the production-safe RimbaKawal -> ZPatrol rebrand.

Visible branding and the Cloudflare Worker name are changed. Legacy package IDs,
D1 database names/IDs and local persistence identifiers are intentionally kept so
existing installations and patrol data remain compatible.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OLD_BRAND = "RimbaKawal"
NEW_BRAND = "ZPatrol"
OLD_API = "https://rimbakawal.fscapitalmanagement.workers.dev"
NEW_API = "https://zpatrol.fscapitalmanagement.workers.dev"


def replace(path: Path, replacements: list[tuple[str, str]]) -> bool:
    if not path.exists() or not path.is_file():
        return False
    original = path.read_text(encoding="utf-8")
    updated = original
    for old, new in replacements:
        updated = updated.replace(old, new)
    if updated == original:
        return False
    path.write_text(updated, encoding="utf-8")
    return True


def main() -> None:
    touched: set[Path] = set()

    visible_text_files: list[Path] = [
        ROOT / "README.md",
        ROOT / "docs/IOS_PUSH_PREPARATION.md",
        ROOT / "lib/main.dart",
        ROOT / "lib/core/notifications/notification_service.dart",
        ROOT / "web/index.html",
        ROOT / "web/firebase-messaging-sw.js",
        ROOT / "mobile/android/AndroidManifest.xml",
        ROOT / "mobile/ios/Info.plist",
        ROOT / ".github/workflows/deploy-cloudflare.yml",
        ROOT / ".github/workflows/build-mobile-production.yml",
        ROOT / "scripts/cloudflare-build.sh",
        ROOT / "setup_windows.ps1",
    ]
    visible_text_files.extend((ROOT / "lib/features").rglob("*.dart"))
    visible_text_files.extend((ROOT / "worker").glob("*.js"))

    for path in visible_text_files:
        if replace(path, [(OLD_BRAND, NEW_BRAND), (OLD_API, NEW_API)]):
            touched.add(path)

    api_service = ROOT / "lib/core/api/api_service.dart"
    if replace(api_service, [(OLD_API, NEW_API)]):
        touched.add(api_service)

    # Purple-first visual identity and new launcher asset.
    for relative in ["lib/main.dart", "lib/features/auth/login_screen.dart"]:
        path = ROOT / relative
        if replace(
            path,
            [
                ("0xFFC0392B", "0xFF6D28D9"),
                ("0xFF4834D4", "0xFF8B5CF6"),
                ("assets/branding/rimbakawal_icon.png", "assets/branding/zpatrol_icon.png"),
                ("Logo RimbaKawal", "Logo ZPatrol"),
            ],
        ):
            touched.add(path)

    # Keep Dart package name + mobile bundle/application IDs stable for update compatibility.
    pubspec = ROOT / "pubspec.yaml"
    if replace(
        pubspec,
        [
            ("version: 0.5.18+36", "version: 0.6.0+37"),
            ("image_path: assets/branding/rimbakawal_icon.png", "image_path: assets/branding/zpatrol_icon.png"),
            ("- assets/branding/rimbakawal_icon.png", "- assets/branding/zpatrol_icon.png"),
        ],
    ):
        touched.add(pubspec)

    # New Worker URL, same D1 binding/database.
    wrangler = ROOT / "wrangler.jsonc"
    if replace(wrangler, [('"name": "rimbakawal"', '"name": "zpatrol"')]):
        touched.add(wrangler)

    # PWA identity.
    manifest_path = ROOT / "web/manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest.update(
        {
            "name": NEW_BRAND,
            "short_name": NEW_BRAND,
            "description": "ZPatrol — Sistem Rondaan Pintar.",
            "theme_color": "#7C3AED",
            "icons": [
                {
                    "src": "assets/assets/branding/zpatrol_icon.png",
                    "sizes": "1024x1024",
                    "type": "image/png",
                    "purpose": "any maskable",
                }
            ],
        }
    )
    manifest_path.write_text(
        json.dumps(manifest, indent=4, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    touched.add(manifest_path)

    index_path = ROOT / "web/index.html"
    if replace(
        index_path,
        [
            ('href="icons/Icon-192.png"', 'href="assets/assets/branding/zpatrol_icon.png"'),
            ('href="favicon.png"', 'href="assets/assets/branding/zpatrol_icon.png"'),
        ],
    ):
        touched.add(index_path)

    svg_path = ROOT / "assets/branding/zpatrol_icon.svg"
    svg_path.write_text(
        '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
  <rect width="1024" height="1024" rx="284" fill="#391969"/>
  <rect x="46" y="46" width="932" height="932" rx="244" fill="#100F18"/>
  <path d="M512 162 775 267v233c0 183-106 295-263 351-157-56-263-168-263-351V267L512 162Z" fill="none" stroke="#F8F7FF" stroke-width="58" stroke-linejoin="round"/>
  <path d="M354 351h319l-160 197h153L423 730l47-132H348l175-205H354Z" fill="#B8A6FF"/>
</svg>
''',
        encoding="utf-8",
    )
    touched.add(svg_path)

    png_path = ROOT / "assets/branding/zpatrol_icon.png"
    subprocess.run(
        [sys.executable, str(ROOT / "scripts/generate_zpatrol_icon.py"), str(png_path)],
        cwd=ROOT,
        check=True,
    )
    touched.add(png_path)

    release_note = ROOT / "release/zpatrol-rebrand-0.6.0+37-20260911.txt"
    release_note.write_text(
        '''ZPatrol rebrand release 0.6.0+37
Date: 2026-09-11
Previous product name: RimbaKawal
New product name: ZPatrol
Cloudflare Worker: zpatrol.fscapitalmanagement.workers.dev
Compatibility: existing dev.rimbakawal.rimbakawal package/bundle ID retained.
Data: existing rimbakawal-db D1 database retained; no patrol/attendance data migration required.
Branding: new purple shield + Z/lightning launcher/PWA identity.
''',
        encoding="utf-8",
    )
    touched.add(release_note)

    print("ZPatrol rebrand applied to:")
    for path in sorted(touched):
        print(" -", path.relative_to(ROOT))


if __name__ == "__main__":
    main()
