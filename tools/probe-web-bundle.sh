#!/usr/bin/env bash
# Verifies the REQUEST BODY shapes the iOS app sends for mutating endpoints, by reading
# the panel's own React bundle. Downloads static assets only — issues no API writes.
#
# Written for bash 3.2 (the version macOS ships): no mapfile, no associative arrays.
#
# Usage: bash tools/probe-web-bundle.sh
# Output: tools/web-bundle-calls.txt

set -uo pipefail

BASE="${ORCH_BASE_URL:-https://orchestrator.abesadze.digital}"
DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="$DIR/web-bundle-calls.txt"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Fetching $BASE ..."
curl -sSL -m 30 -o "$TMP/index.html" "$BASE/" || { echo "Could not fetch the panel root."; exit 1; }
echo "  index.html: $(wc -c < "$TMP/index.html") bytes"

# Vite emits <script type="module" src="/assets/index-XXXX.js"> plus lazy chunks.
grep -oE '(src|href)="[^"]*\.(js|mjs)"' "$TMP/index.html" \
  | sed -E 's/^(src|href)="//; s/"$//' \
  | sort -u > "$TMP/assets.txt"

if [ ! -s "$TMP/assets.txt" ]; then
  echo
  echo "No .js references found in the HTML. First 40 lines of what came back:"
  head -40 "$TMP/index.html"
  echo
  echo "The panel shell may need auth. Open it in a browser, View Source, and send me"
  echo "the <script src=...> URL — I will adjust the script."
  exit 1
fi

: > "$TMP/bundle.js"
COUNT=0
while IFS= read -r asset; do
  case "$asset" in
    http*) url="$asset" ;;
    /*)    url="$BASE$asset" ;;
    *)     url="$BASE/$asset" ;;
  esac
  echo "  fetching $url"
  if curl -sSL -m 60 "$url" >> "$TMP/bundle.js"; then
    printf '\n' >> "$TMP/bundle.js"
    COUNT=$((COUNT + 1))
  fi
done < "$TMP/assets.txt"

# The page components are lazy-loaded chunks whose names only appear inside the entry
# bundle. Do a second pass so the whole app — not just the API client — is captured.
grep -oE '[A-Za-z0-9_.-]+-[A-Za-z0-9_-]{6,}\.js' "$TMP/bundle.js" | sort -u > "$TMP/chunks.txt"
echo "Discovered $(wc -l < "$TMP/chunks.txt" | tr -d ' ') lazy chunk(s)"
while IFS= read -r chunk; do
  case " $(cat "$TMP/assets.txt" | tr '\n' ' ') " in
    *"$chunk"*) continue ;;
  esac
  echo "  fetching /assets/$chunk"
  if curl -sSLf -m 60 "$BASE/assets/$chunk" >> "$TMP/bundle.js"; then
    printf '\n' >> "$TMP/bundle.js"
    COUNT=$((COUNT + 1))
  fi
done < "$TMP/chunks.txt"

echo "Fetched $COUNT file(s), $(wc -c < "$TMP/bundle.js") bytes total"

# Keep the concatenated bundle so the whole API client object can be read, not just
# fixed-width windows around each route. It is public frontend JS — no secrets.
cp "$TMP/bundle.js" "$DIR/bundle.js"
echo "Saved $DIR/bundle.js"

# Pull a window of characters around each interesting route so the JSON body that
# accompanies the call is visible.
python3 - "$TMP/bundle.js" "$OUT" <<'PYEOF'
import re, sys

src = open(sys.argv[1], encoding="utf-8", errors="replace").read()
out = open(sys.argv[2], "w", encoding="utf-8")

ROUTES = [
    "/deploy", "/deploy/cancel", "/rollback", "/redeploy",
    "/maintenance", "/supervisor/control", "/artisan/run",
    "/failed-jobs", "/billing/enforcement", "/invoices/",
    "/config/env", "/config/nginx", "/phpfpm", "/php-version",
    "/ssl", "/database/backup", "/files/", "/security",
    "/scheduler", "/cron", "/status-page", "/servers", "/server/actions",
]

total = 0
for route in ROUTES:
    hits = [m.start() for m in re.finditer(re.escape(route), src)]
    if not hits:
        out.write("=" * 70 + "\n### %s  -- NOT FOUND\n\n" % route)
        continue
    total += len(hits)
    out.write("=" * 70 + "\n### %s  (%d occurrences)\n\n" % (route, len(hits)))
    for start in hits[:4]:
        snippet = src[max(0, start - 280): start + 360]
        snippet = re.sub(r"\s+", " ", snippet)
        out.write("  ..." + snippet + "...\n\n")

out.close()
print("Matched %d route occurrences. Wrote %s" % (total, sys.argv[2]))
PYEOF

echo
echo "Done. Send me tools/web-bundle-calls.txt"
