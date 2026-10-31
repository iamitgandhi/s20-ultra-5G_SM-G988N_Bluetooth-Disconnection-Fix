#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
OUTPUT_ZIP="$DIR/Samsung-S20-Ultra-Bluetooth-Fix-v3.3.zip"

echo "==> Packaging module into flashable zip..."
rm -f "$OUTPUT_ZIP"

cd "$DIR/module"
zip -r9 "$OUTPUT_ZIP" ./* -x "*.git*" "*.DS_Store*"

echo "==> Successfully built flashable module:"
echo "    $OUTPUT_ZIP"
ls -lh "$OUTPUT_ZIP"
