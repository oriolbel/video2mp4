#!/bin/bash

# ==============================
# CONFIGURATION
# ==============================

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    echo "Usage: $0 <extension> [limit]"
    echo "Example: $0 avi 5"
    exit 1
fi

EXTENSION="$1"
LIMIT="${2:-0}"  # optional limit, default = 0 (no limit)
INPUT_DIR="."
OUTPUT_DIR="<your_output_path>"
LOG_FILE="$OUTPUT_DIR/conversion.log"

mkdir -p "$OUTPUT_DIR"

{
  echo "=========================="
  echo "Process started: $(date)"
  echo "Input dir: $INPUT_DIR"
  echo "Output dir: $OUTPUT_DIR"
  echo "Extension: .$EXTENSION"
  echo "File limit: $LIMIT"
  echo "=========================="
} >> "$LOG_FILE"

# ==============================
# FUNCTION: check if genpts is required
# ==============================
needs_genpts() {
    FILE="$1"
    ERRORS=$(ffmpeg -v error -t 10 -i "$FILE" -f null - 2>&1 | grep -E "non monotonically increasing dts|Invalid timestamps")
    if [ -n "$ERRORS" ]; then
        echo "true"
    else
        echo "false"
    fi
}

# ==============================
# PROCESS FILES
# ==============================

COUNT=0

find "$INPUT_DIR" -type f -iname "*.${EXTENSION}" -print0 | \
while IFS= read -r -d '' FILE; do
    BASENAME=$(basename "$FILE")
    NAME_NO_EXT=${BASENAME%.*}
    OUTPUT_FILE="$OUTPUT_DIR/${NAME_NO_EXT}-fixed.mp4"
    TEMP_FILE="$OUTPUT_DIR/tmp_${NAME_NO_EXT}.mp4"

    if [ -f "$OUTPUT_FILE" ]; then
        echo "Already exists: $OUTPUT_FILE → skipping..."
        echo "[SKIP] $FILE → already exists" >> "$LOG_FILE"
        continue
    fi

    echo "Processing: $FILE → $OUTPUT_FILE"
    echo "[START] $FILE" >> "$LOG_FILE"

    # Check if genpts is needed
    APPLY_GENPTS=$(needs_genpts "$FILE")
    EXTRA_FLAGS=""
    if [ "$APPLY_GENPTS" = "true" ]; then
        EXTRA_FLAGS="-fflags +genpts"
        echo "[INFO] Needs genpts" >> "$LOG_FILE"
    fi

    # Conversion
    ffmpeg $EXTRA_FLAGS -err_detect ignore_err -i "$FILE" \
        -c:v libx264 -profile:v high -level:v 4.1 -pix_fmt yuv420p \
        -vf "scale='min(1920,iw)':'min(1080,ih)':force_original_aspect_ratio=decrease" \
        -preset medium -crf 20 \
        -c:a aac -b:a 192k -ac 2 \
        -movflags +faststart \
        "$TEMP_FILE" >> "$LOG_FILE" 2>&1

    if [ $? -eq 0 ] && [ -s "$TEMP_FILE" ]; then
        mv "$TEMP_FILE" "$OUTPUT_FILE"
        echo "[OK] $FILE → $OUTPUT_FILE" >> "$LOG_FILE"
        echo "✅ Conversion completed: $FILE"
    else
        echo "[ERROR] $FILE" >> "$LOG_FILE"
        echo "❌ Error converting: $FILE"
        rm -f "$TEMP_FILE"
        continue
    fi

    COUNT=$((COUNT+1))
    if [ "$LIMIT" -gt 0 ] && [ "$COUNT" -ge "$LIMIT" ]; then
        echo "Reached file limit ($LIMIT), stopping."
        break
    fi
done

{
  echo "=========================="
  echo "Process finished: $(date)"
  echo "Files processed: $COUNT"
  echo "=========================="
} >> "$LOG_FILE"

echo "✅ Process completed! Converted videos are in: $OUTPUT_DIR"
echo "📄 Log available at: $LOG_FILE"

