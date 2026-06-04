#!/usr/bin/env bash
# Download the ECDICT English-Chinese dictionary (https://github.com/skywind3000/ECDICT)
# and produce a slimmed sqlite database at Resources/ecdict.db for bundling.
# Run once; build_app.sh picks the file up automatically if present.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DB="$ROOT_DIR/Resources/ecdict.db"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

RELEASE_URL="https://github.com/skywind3000/ECDICT/releases/download/1.0.28/ecdict-sqlite-28.zip"

if [[ -s "$OUT_DB" ]]; then
  echo "Resources/ecdict.db already exists ($(du -h "$OUT_DB" | cut -f1)). Delete it first to re-fetch."
  exit 0
fi

echo "Downloading ECDICT sqlite release..."
curl -fL --retry 3 -o "$WORK_DIR/ecdict.zip" "$RELEASE_URL"

echo "Unzipping..."
unzip -q "$WORK_DIR/ecdict.zip" -d "$WORK_DIR"

FULL_DB="$(find "$WORK_DIR" -name '*.db' | head -1)"
if [[ -z "$FULL_DB" ]]; then
  echo "error: no .db file found in the downloaded archive" >&2
  exit 1
fi

echo "Slimming database (keeping word/phonetic/translation/definition/tag)..."
sqlite3 "$FULL_DB" <<SQL
ATTACH DATABASE '$OUT_DB' AS slim;
CREATE TABLE slim.stardict AS
  SELECT word, phonetic, definition, translation, tag
  FROM stardict
  WHERE translation IS NOT NULL AND translation != '';
CREATE INDEX slim.idx_stardict_word ON stardict(word COLLATE NOCASE);
DETACH DATABASE slim;
SQL

echo "Done: $OUT_DB ($(du -h "$OUT_DB" | cut -f1))"
