#!/usr/bin/env python3
"""Reads or sets the app version in Dict-app.xcodeproj.

  version.py get             prints "<marketing> <build>", e.g. "1.0 1"
  version.py set 1.1 5       writes both into every configuration
"""
import pathlib
import re
import sys

PBXPROJ = pathlib.Path(__file__).resolve().parent.parent / "Dict-app.xcodeproj/project.pbxproj"


def main():
    text = PBXPROJ.read_text()
    if sys.argv[1:2] == ["get"]:
        versions = set(re.findall(r"MARKETING_VERSION = ([^;]+);", text))
        builds = set(re.findall(r"CURRENT_PROJECT_VERSION = ([^;]+);", text))
        if len(versions) != 1 or len(builds) != 1:
            sys.exit(f"project.pbxproj has inconsistent versions: {versions} builds: {builds}")
        print(f"{versions.pop()} {builds.pop()}")
    elif sys.argv[1:2] == ["set"] and len(sys.argv) == 4:
        version, build = sys.argv[2], sys.argv[3]
        if not re.fullmatch(r"\d+(\.\d+)*", version) or not build.isdigit():
            sys.exit("usage: version.py set <marketing like 1.1> <build integer>")
        text = re.sub(r"MARKETING_VERSION = [^;]+;", f"MARKETING_VERSION = {version};", text)
        text = re.sub(r"CURRENT_PROJECT_VERSION = [^;]+;", f"CURRENT_PROJECT_VERSION = {build};", text)
        PBXPROJ.write_text(text)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
