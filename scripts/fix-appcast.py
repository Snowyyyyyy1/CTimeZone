#!/usr/bin/env python3
"""Point every appcast enclosure at its own GitHub release.

generate_appcast applies one URL prefix to every item, but each DMG lives under
its own tag. The tag is derived from the file name (CTimeZone-1.2.3.dmg ->
v1.2.3), so the build must name the DMG with its version.

Usage: fix-appcast.py <appcast.xml> <owner/repo>
"""
import re
import sys
from xml.etree import ElementTree as ET

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE_NS)
ET.register_namespace("dc", "http://purl.org/dc/elements/1.1/")

path, repo = sys.argv[1], sys.argv[2]
tree = ET.parse(path)
pattern = re.compile(r"^CTimeZone-(\d+\.\d+\.\d+)\.dmg$")

for enclosure in tree.iter("enclosure"):
    filename = enclosure.get("url", "").rsplit("/", 1)[-1]
    match = pattern.match(filename)
    if not match:
        sys.exit(f"Unexpected asset name in appcast: {filename}")
    tag = f"v{match.group(1)}"
    enclosure.set("url", f"https://github.com/{repo}/releases/download/{tag}/{filename}")

tree.write(path, xml_declaration=True, encoding="utf-8")
print(f"Rewrote enclosure URLs in {path}")
