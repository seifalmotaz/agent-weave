#!/usr/bin/env python3
"""Record the official API operation index. Does not certify endpoint parity."""
import argparse
import hashlib
import json
from collections import Counter
from html.parser import HTMLParser
from pathlib import Path
from urllib.request import urlopen

SOURCE = "https://developers.openai.com/api/reference/overview"
TARGET = Path(__file__).resolve().parents[1] / "docs/openai-api-inventory.json"


class Operations(HTMLParser):
    def __init__(self):
        super().__init__()
        self.paths = set()

    def handle_starttag(self, tag, attrs):
        path = dict(attrs).get("href", "")
        if tag == "a" and path.startswith("/api/reference/resources/") and "/methods/" in path:
            self.paths.add(path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--refresh", action="store_true", help="Write a new reviewed-source candidate")
    args = parser.parse_args()
    html = urlopen(SOURCE, timeout=30).read()
    index = Operations()
    index.feed(html.decode())
    if len(index.paths) < 100:
        raise SystemExit("API index shape changed. Refusing to replace the inventory.")
    entries = []
    for path in sorted(index.paths):
        resource = path.split("/resources/", 1)[1].split("/", 1)[0]
        entries.append({"reference": "https://developers.openai.com" + path,
                        "resource": resource,
                        "review": "raw-json-fallback" if resource == "admin" else "provider-sdk-review",
                        "live_tested": False})
    document = {"source": SOURCE, "source_sha256": hashlib.sha256(html).hexdigest(),
                "meaning": "Discovery inventory, not a claim that every endpoint is typed or tested.",
                "provider_sdk": "openai_dart 11.0.1", "operations": entries}
    if args.refresh:
        TARGET.write_text(json.dumps(document, indent=2) + "\n")
    else:
        previous = json.loads(TARGET.read_text())
        before = {row["reference"] for row in previous["operations"]}
        after = {row["reference"] for row in entries}
        if before != after:
            print(json.dumps({"added": sorted(after - before), "removed": sorted(before - after)}, indent=2))
            raise SystemExit("Review upstream changes, then run with --refresh.")
    print(json.dumps({"operations": len(entries), "resources": dict(Counter(row["resource"] for row in entries))}))


if __name__ == "__main__":
    main()
