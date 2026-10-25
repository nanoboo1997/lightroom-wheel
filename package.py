#!/usr/bin/env python3
"""Package the build without runtime data, private images or AppleDouble files."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
root = Path(__file__).resolve().parent
package = root / "dist" / "LightroomWheel"
assert (package / "Lightroom Wheel.app/Contents/MacOS/LightroomWheel").is_file(), "Run ./build.sh first"
archive = root / "dist" / "Lightroom-Wheel-v0.2.0-AppleSilicon.zip"
with ZipFile(archive, "w", ZIP_DEFLATED) as z:
    for path in sorted(package.rglob("*")):
        relative = path.relative_to(package)
        if "bridge" in relative.parts or any(p.startswith("._") or p == ".DS_Store" for p in relative.parts):
            continue
        if path.is_file():
            z.write(path, Path("LightroomWheel") / relative)
with ZipFile(archive) as z:
    assert z.testzip() is None
print(archive)
