#!/bin/sh
set -e

APP=$(basename "$PWD")

SRC="_build/default/lib/$APP"
DST="$PWD/_build/zomp/lib/$APP"
IGNORE_FILE="zomp.ignore"

mkdir -p "$DST"

# Remove broken symlinks
find "$SRC" -type l ! -exec test -e {} \; -delete || true

# Build ignore matcher
IGNORE_TEMP=$(mktemp)
trap "rm -f $IGNORE_TEMP" EXIT

# Expand globs in zomp.ignore to patterns suitable for grep
if [ -e "$IGNORE_FILE" ]; then
   grep -v '^\s*#' "$IGNORE_FILE" | sed 's#/#\\/#g' | sed 's/\./\\./g' | sed 's/\*/.*/g' > "$IGNORE_TEMP"
fi

# Copy Git-tracked and Zomp-allowed files
git ls-files -z | while IFS= read -r -d '' file; do
    # Skip if ignored
    echo "$file" | grep -Eq -f "$IGNORE_TEMP" && continue
    # Only copy if file exists in the build dir
    if [ -e "$SRC/$file" ]; then
        mkdir -p "$DST/$(dirname "$file")"
        cp -a "$SRC/$file" "$DST/$file"
    fi
done

rm "$IGNORE_TEMP"

# Copy metadata
cp "$PWD/zomp.meta" "$DST/"
cp "$PWD/Emakefile" "$DST/"

# Clean up beam files just in case
[ -d "$DST/ebin" ] && find "$DST/ebin" -name '*.beam' -exec rm -f {} + || true
