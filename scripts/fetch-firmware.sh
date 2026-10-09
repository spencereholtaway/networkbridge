#!/usr/bin/env bash
# Fetch the newest DD-WRT beta build for the Netgear R8000.
#
# Runs on your laptop (needs bash, curl, sha256sum or shasum). Walks the DD-WRT
# betas directory, finds the newest dated build folder that contains an R8000
# directory, downloads the two files you need and verifies they really are
# R8000 images before leaving them in ./firmware/:
#
#   factory-to-dd-wrt.chk   - flash this FIRST, from the stock Netgear GUI
#   netgear-r8000-webflash.bin - flash this SECOND, from inside DD-WRT
#
# Usage:  scripts/fetch-firmware.sh [output-dir]      (default: ./firmware)
#         scripts/fetch-firmware.sh --verify-only     re-check files already in ./firmware
set -euo pipefail
export LC_ALL=C   # byte-safe text tools: firmware images are binary

BASE="https://download1.dd-wrt.com/dd-wrtv2/downloads/betas/"
MODEL_RE='r8000'                 # matched case-insensitively against folder/file names
R8000_BOARD_ID='U12H315T00'      # Netgear board ID embedded in every R8000 .chk header
VERIFY_ONLY=0
if [[ "${1:-}" == "--verify-only" ]]; then VERIFY_ONLY=1; shift; fi
OUT="${1:-$(cd "$(dirname "$0")/.." && pwd)/firmware}"

say() { printf '%s\n' "$*" >&2; }
die() { say "ERROR: $*"; exit 1; }

# Print the href targets of a directory listing, one per line.
hrefs() {
  curl -fsSL --retry 3 "$1" | grep -oiE 'href="[^"?]+"' | sed -E 's/^href="//; s/"$//'
}

# Dated build folders look like MM-DD-YYYY-rNNNNN/. Sort them by date, newest first.
dated_dirs_newest_first() {
  grep -E '^[0-9]{2}-[0-9]{2}-[0-9]{4}-r[0-9]+/$' \
    | awk -F- '{ printf "%s%s%s %s\n", $3, $1, $2, $0 }' \
    | sort -r | awk '{ print $2 }'
}

# Look for an R8000 directory directly under a build folder, or one level deeper
# (some layouts group boards under e.g. broadcom_K3X/).
find_model_dir() {
  local build_url="$1" sub
  local listing; listing="$(hrefs "$build_url")" || return 1
  local hit; hit="$(printf '%s\n' "$listing" | grep -iE "${MODEL_RE}.*/$" | head -n1 || true)"
  if [[ -n "$hit" ]]; then printf '%s%s' "$build_url" "$hit"; return 0; fi
  while read -r sub; do
    [[ "$sub" == */ && "$sub" != ../ && "$sub" != /* ]] || continue
    hit="$(hrefs "$build_url$sub" 2>/dev/null | grep -iE "${MODEL_RE}.*/$" | head -n1 || true)"
    if [[ -n "$hit" ]]; then printf '%s%s%s' "$build_url" "$sub" "$hit"; return 0; fi
  done <<< "$listing"
  return 1
}

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else shasum -a 256 "$1" | awk '{print $1}'; fi
}

if [[ $VERIFY_ONLY -eq 1 ]]; then
  chk="$(ls "$OUT"/*.chk 2>/dev/null | head -n1 | xargs -n1 basename 2>/dev/null || true)"
  bin="$(ls "$OUT"/*.bin 2>/dev/null | head -n1 | xargs -n1 basename 2>/dev/null || true)"
  [[ -n "$chk" && -n "$bin" ]] || die "--verify-only: need one .chk and one .bin in $OUT"
  model_url="(already downloaded)"
  say "Verifying existing files in $OUT"
else
  say "Listing $BASE"
  years="$(hrefs "$BASE" | grep -E '^[0-9]{4}/$' | sort -r)"
  [[ -n "$years" ]] || die "no year folders found at $BASE (network blocked? layout changed?)"

  model_url=""
  for y in $years; do
    say "Scanning $BASE$y"
    builds="$(hrefs "$BASE$y" | dated_dirs_newest_first)"
    for b in $builds; do
      if model_url="$(find_model_dir "$BASE$y$b")"; then
        say "Newest build with an R8000 folder: $BASE$y$b"
        break 2
      fi
      say "  $b has no R8000 build, trying the previous one"
    done
  done
  [[ -n "$model_url" ]] || die "no R8000 folder found in any beta build"
  say "R8000 folder: $model_url"

  files="$(hrefs "$model_url" | grep -iE '\.(chk|bin)$' || true)"
  chk="$(printf '%s\n' "$files" | grep -iE '\.chk$' | head -n1 || true)"
  bin="$(printf '%s\n' "$files" | grep -iE '\.bin$' | head -n1 || true)"
  [[ -n "$chk" ]] || die "no .chk (factory-to-DD-WRT) file in $model_url"
  [[ -n "$bin" ]] || die "no .bin (webflash) file in $model_url"

  mkdir -p "$OUT"
  for f in "$chk" "$bin"; do
    say "Downloading $f"
    curl -fL --retry 3 --progress-bar -o "$OUT/$f" "$model_url$f"
  done
fi

# --- Verification: are these really R8000 images? ---
chk_path="$OUT/$chk"; bin_path="$OUT/$bin"
printf "%s" "$model_url $chk $bin" | tr "[:upper:]" "[:lower:]" | grep -q r8000 || die "neither folder nor filenames mention r8000: $model_url $chk $bin"

# Netgear .chk header: starts with magic *#$^ and carries the board ID string.
head -c 4 "$chk_path" | grep -aq '^\*#\$\^' || die "$chk does not start with the Netgear *#\$^ magic"
head -c 128 "$chk_path" | grep -aq "$R8000_BOARD_ID" \
  || die "$chk does not carry the R8000 board ID $R8000_BOARD_ID - this is NOT an R8000 image"

# DD-WRT webflash .bin for Broadcom ARM is a TRX image: magic HDR0 at offset 0.
head -c 4 "$bin_path" | grep -aq '^HDR0' || die "$bin does not start with the TRX HDR0 magic"
[[ $(stat -c %s "$bin_path" 2>/dev/null || stat -f %z "$bin_path") -gt 10000000 ]] || die "$bin is suspiciously small"

{
  echo "# DD-WRT R8000 beta build"
  echo "# source: $model_url"
  echo "# fetched: $(date -u +%Y-%m-%dT%H:%MZ)"
  echo "$(sha256 "$chk_path")  $chk"
  echo "$(sha256 "$bin_path")  $bin"
} > "$OUT/SHA256SUMS"

say ""
say "OK - verified R8000 images in $OUT:"
say "  1st flash (from stock Netgear GUI): $chk"
say "  2nd flash (from inside DD-WRT):     $bin"
say "Checksums written to $OUT/SHA256SUMS"
