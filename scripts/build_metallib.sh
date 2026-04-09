#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CMLX="$REPO_ROOT/.build/checkouts/mlx-swift/Source/Cmlx"
INCLUDES="-I $CMLX/mlx/mlx/backend/metal/kernels -I $CMLX/mlx/mlx/backend/metal/kernels/steel -I $CMLX/mlx-generated/metal"
OUT=/tmp/metallib_build

rm -rf "$OUT" && mkdir -p "$OUT"

# Compile generated .metal -> .air
for f in "$CMLX"/mlx-generated/metal/*.metal "$CMLX"/mlx-generated/metal/steel/*.metal "$CMLX"/mlx-generated/metal/steel/attn/kernels/*.metal; do
    [ -f "$f" ] || continue
    NAME=$(basename "$f" .metal)
    xcrun metal -c "$f" -o "$OUT/${NAME}.air" $INCLUDES -std=metal3.1 2>/dev/null
done

echo "AIR files: $(ls "$OUT"/*.air | wc -l)"

# Link into metallib
xcrun metallib "$OUT"/*.air -o "$OUT/mlx.metallib"
echo "Built: $OUT/mlx.metallib ($(du -h "$OUT/mlx.metallib" | cut -f1))"
