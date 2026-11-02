#!/usr/bin/env python3
"""Adds a version to the top of Sparkle's appcast.xml.

  appcast.py appcast.xml VERSION BUILD ZIP_URL 'sparkle:edSignature="…" length="…"' notes.md
"""
import html
import re
import sys
from email.utils import formatdate

path, version, build, url, signature, notes_path = sys.argv[1:7]


def inline(text):
    text = html.escape(text)
    text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"`(.+?)`", r"<code>\1</code>", text)
    return text


def markdown(source):
    """Just enough Markdown for release notes: headings, bullets, paragraphs."""
    out, items, para = [], [], []

    def flush():
        if para:
            out.append("<p>" + inline(" ".join(para)) + "</p>")
            para.clear()
        if items:
            out.append("<ul>" + "".join(f"<li>{inline(i)}</li>" for i in items) + "</ul>")
            items.clear()

    for line in source.splitlines():
        stripped = line.strip()
        if not stripped:
            flush()
        elif stripped.startswith("#"):
            flush()
            out.append("<h3>" + inline(stripped.lstrip("#").strip()) + "</h3>")
        elif stripped[:2] in ("- ", "* "):
            if para:
                flush()
            items.append(stripped[2:])
        elif items and line.startswith(" "):
            items[-1] += " " + stripped
        else:
            if items:
                flush()
            para.append(stripped)
    flush()
    return "\n".join(out)


notes = markdown(open(notes_path).read())
item = f"""        <item>
            <title>Dict {version}</title>
            <pubDate>{formatdate(usegmt=True)}</pubDate>
            <sparkle:version>{build}</sparkle:version>
            <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
            <sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>
            <description><![CDATA[
{notes}
            ]]></description>
            <enclosure url="{url}" type="application/octet-stream" {signature.strip()}/>
        </item>
"""
feed = open(path).read()
marker = "</language>\n"
assert marker in feed, "appcast.xml has no <language> line to add after"
feed = feed.replace(marker, marker + item, 1)
open(path, "w").write(feed)
