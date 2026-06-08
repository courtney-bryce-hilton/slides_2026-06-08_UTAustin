#!/usr/bin/env bash
set -euo pipefail

# ----------------------------
# Human diversity image grabber
# ----------------------------
# Requirements:
#   - bash
#   - curl
#   - jq
#   - python3
#
# On macOS, if needed:
#   brew install jq
#
# What it does:
#   - Pulls file pages from selected Wikimedia Commons categories
#   - Downloads up to 50 images total
#   - Skips obvious art/illustration-heavy items where possible
#   - Saves a metadata TSV for attribution / later filtering

API="https://commons.wikimedia.org/w/api.php"
OUTDIR="human_diversity_images"
IMGDIR="$OUTDIR/images"
METADATA="$OUTDIR/metadata.tsv"

MAX_TOTAL=50
PER_CATEGORY=8

mkdir -p "$IMGDIR"

# You can tweak these if you want a different balance.
CATEGORIES=(
  "Category:Hadza people"
  "Category:San people"
  "Category:Inuit people"
  "Category:Sami people with reindeer"
  "Category:Bedouins in Palestine"
  "Category:Quechua people"
  "Category:Children of Micronesia"
  "Category:Female farmers in India"
  "Category:Farmers from India"
  "Category:Mongolian horse"
)

# ----------------------------
# Helper functions
# ----------------------------

urlencode() {
  python3 - "$1" <<'PY'
import sys, urllib.parse
print(urllib.parse.quote(sys.argv[1], safe=""))
PY
}

safe_name() {
  python3 - "$1" <<'PY'
import re, sys
s = sys.argv[1]
s = s.replace("File:", "")
s = re.sub(r'[^A-Za-z0-9._-]+', '_', s)
print(s)
PY
}

# crude filter to reduce art / scans / diagrams
is_probably_ok() {
  local title="$1"
  local categories_json="$2"

  local lower
  lower="$(printf '%s\n%s' "$title" "$categories_json" | tr '[:upper:]' '[:lower:]')"

  if echo "$lower" | grep -Eq '(^|[^a-z])(painting|drawings?|illustrations?|artwork|engraving|etching|lithograph|poster|stamp|statue|sculpture|coat of arms|flag|map|logo|icon|book cover|postcard|album cover)($|[^a-z])'; then
    return 1
  fi

  return 0
}

# ----------------------------
# Metadata header
# ----------------------------

printf "file_name\tcommons_title\tcategory\timage_url\tdescription_url\tartist\tlicense\tcredit\n" > "$METADATA"

downloaded=0
declare -A SEEN_TITLES=()

for category in "${CATEGORIES[@]}"; do
  echo "=== Category: $category ==="
  cat_count=0
  gcmcontinue=""

  while [[ $cat_count -lt $PER_CATEGORY && $downloaded -lt $MAX_TOTAL ]]; do
    query="$API?action=query&format=json&generator=categorymembers&gcmtitle=$(urlencode "$category")&gcmtype=file&gcmlimit=50&prop=imageinfo|categories&iiprop=url|extmetadata&cllimit=max"
    if [[ -n "$gcmcontinue" ]]; then
      query="$query&gcmcontinue=$(urlencode "$gcmcontinue")"
    fi

    json="$(curl -sL "$query")"

    # pull continue token if present
    gcmcontinue="$(printf '%s' "$json" | jq -r '.continue.gcmcontinue // empty')"

    # no results
    if [[ "$(printf '%s' "$json" | jq 'has("query")')" != "true" ]]; then
      break
    fi

    # iterate pages in a stable order
    while IFS=$'\t' read -r title image_url description_url artist license credit page_categories; do
      [[ -z "$title" || -z "$image_url" ]] && continue

      # avoid duplicate files across categories
      if [[ -n "${SEEN_TITLES[$title]+x}" ]]; then
        continue
      fi

      # keep mostly jpg/jpeg/png
      lower_url="$(echo "$image_url" | tr '[:upper:]' '[:lower:]')"
      if ! echo "$lower_url" | grep -Eq '\.(jpg|jpeg|png)$'; then
        continue
      fi

      if ! is_probably_ok "$title" "$page_categories"; then
        continue
      fi

      fname="$(safe_name "$title")"

      echo "Downloading: $title"
      curl -L --fail --silent --show-error "$image_url" -o "$IMGDIR/$fname"

      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
        "$fname" \
        "$title" \
        "$category" \
        "$image_url" \
        "$description_url" \
        "$artist" \
        "$license" \
        "$credit" >> "$METADATA"

      SEEN_TITLES["$title"]=1
      downloaded=$((downloaded + 1))
      cat_count=$((cat_count + 1))

      if [[ $downloaded -ge $MAX_TOTAL || $cat_count -ge $PER_CATEGORY ]]; then
        break
      fi
    done < <(
      printf '%s' "$json" | jq -r '
        .query.pages
        | to_entries
        | sort_by(.value.title)
        | .[]
        | .value as $p
        | [
            $p.title,
            ($p.imageinfo[0].url // ""),
            ($p.imageinfo[0].descriptionurl // ""),
            ($p.imageinfo[0].extmetadata.Artist.value // "" | gsub("<[^>]*>"; "")),
            ($p.imageinfo[0].extmetadata.LicenseShortName.value // ""),
            ($p.imageinfo[0].extmetadata.Credit.value // "" | gsub("<[^>]*>"; "")),
            (($p.categories // []) | map(.title) | join(" | "))
          ]
        | @tsv
      '
    )

    # stop if no continuation
    if [[ -z "$gcmcontinue" ]]; then
      break
    fi
  done

  echo "Downloaded so far: $downloaded"
  echo
  if [[ $downloaded -ge $MAX_TOTAL ]]; then
    break
  fi
done

echo "Done."
echo "Images saved in: $IMGDIR"
echo "Metadata saved in: $METADATA"