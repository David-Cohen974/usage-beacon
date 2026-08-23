#!/usr/bin/env python3
"""Generate static release metadata from the GitHub Releases API response."""

from __future__ import annotations

import json
import sys
from pathlib import Path


def fail(message: str) -> None:
    raise SystemExit(message)


if len(sys.argv) != 3:
    fail("Usage: generate-site-data.py <github-releases.json> <site-output-dir>")

releases_path = Path(sys.argv[1])
output_dir = Path(sys.argv[2])
releases = json.loads(releases_path.read_text(encoding="utf-8"))

if not isinstance(releases, list):
    fail("GitHub Releases response must be an array")

published = [release for release in releases if not release.get("draft", False)]
published.sort(key=lambda release: release.get("published_at") or "", reverse=True)
stable = next((release for release in published if not release.get("prerelease", False)), None)

minimum_macos = "14.0"
latest = {
    "version": None,
    "downloadUrl": None,
    "releaseDate": None,
    "minimumMacOS": minimum_macos,
}

if stable is not None:
    assets = stable.get("assets") or []
    dmg = next(
        (
            asset
            for asset in assets
            if asset.get("name", "").startswith("UsageBeacon-")
            and asset.get("name", "").endswith(".dmg")
        ),
        None,
    )
    if dmg is None:
        fail(f"Stable release {stable.get('tag_name')} has no versioned DMG asset")

    latest = {
        "version": str(stable.get("tag_name", "")).removeprefix("v"),
        "downloadUrl": dmg.get("browser_download_url"),
        "releaseDate": stable.get("published_at"),
        "minimumMacOS": minimum_macos,
    }

changelog = []
for release in published:
    tag = str(release.get("tag_name", ""))
    changelog.append(
        {
            "version": tag.removeprefix("v"),
            "tag": tag,
            "name": release.get("name") or tag,
            "releaseDate": release.get("published_at"),
            "prerelease": bool(release.get("prerelease", False)),
            "notes": release.get("body") or "No release notes were provided.",
            "url": release.get("html_url"),
        }
    )

output_dir.mkdir(parents=True, exist_ok=True)
(output_dir / "latest.json").write_text(
    json.dumps(latest, indent=2) + "\n",
    encoding="utf-8",
)
(output_dir / "releases.json").write_text(
    json.dumps(changelog, indent=2) + "\n",
    encoding="utf-8",
)
