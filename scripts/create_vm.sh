#!/bin/bash
set -euo pipefail

# ------------------------------------
# Oracle VM Hunter - Create & Scale VM
# ------------------------------------
# Strategy: Run each CPU level in PARALLEL, each sweeping memory
# from MAX_MEMORY down to MIN_MEMORY. First success kills all others.

MIN_OCPUS="${MIN_OCPUS:-2}"
MAX_OCPUS="${MAX_OCPUS:-4}"
MIN_MEMORY="${MIN_MEMORY:-8}"
MAX_MEMORY="${MAX_MEMORY:-19}"

DISPLAY_NAME="${DISPLAY_NAME:-free-arm-instance}"
SHAPE="VM.Standard.A1.Flex"

# Shared temp dir for cross-process signaling
WORK_DIR=$(mktemp -d)
SUCCESS_FILE="$WORK_DIR/success"
trap 'rm -rf "$WORK_DIR"' EXIT

# Region override (optional — defaults to OCI config region)
REGION="${REGION:-}"
REGION_FLAG=""
if [ -n "$REGION" ]; then
  REGION_FLAG="--region $REGION"
  echo "Region override: $REGION"
fi

# --- Pre-flight: check if VM already exists ---
echo "Checking for existing instance '$DISPLAY_NAME'..."
EXISTING=$(oci compute instance list \
  --compartment-id "$COMPARTMENT_ID" \
  --display-name "$DISPLAY_NAME" \
  --lifecycle-state RUNNING \
  --query "data[0].id" \
  --raw-output $REGION_FLAG 2>/dev/null || true)

if [ -n "$EXISTING" ] && [ "$EXISTING" != "null" ]; then
  echo "VM already exists: $EXISTING — skipping creation."
  echo "vm_status=exists" >> "${GITHUB_OUTPUT:-/dev/null}"
  exit 0
fi

# --- Resolve latest Ubuntu image ---
echo "Resolving latest Ubuntu 22.04 ARM image..."
IMAGE_ID=$(oci compute image list \
  --compartment-id "$COMPARTMENT_ID" \
  --operating-system "Canonical Ubuntu" \
  --operating-system-version "22.04" \
  --shape "$SHAPE" \
  --sort-by TIMECREATED \
  --sort-order DESC \
  --query "data[0].id" \
  --raw-output $REGION_FLAG)

if [ -z "$IMAGE_ID" ] || [ "$IMAGE_ID" = "null" ]; then
  echo "ERROR: Could not find Ubuntu 22.04 image for $SHAPE"
  exit 1
fi
echo "Image: $IMAGE_ID"

# --- Auto-discover Availability Domains ---
if [ -n "${AVAILABILITY_DOMAINS:-}" ]; then
  IFS=',' read -ra ADS <<< "$AVAILABILITY_DOMAINS"
elif [ -n "${AVAILABILITY_DOMAIN:-}" ]; then
  ADS=("$AVAILABILITY_DOMAIN")
else
  echo "Auto-discovering availability domains..."
  AD_JSON=$(oci iam availability-domain list \
    --compartment-id "$COMPARTMENT_ID" \
    --query "data[].name" \
    --raw-output $REGION_FLAG)
  mapfile -t ADS < <(echo "$AD_JSON" | tr -d '[]"' | tr ',' '\n' | sed 's/^ *//;s/ *$//' | grep -v '^$')
  echo "Found ${#ADS[@]} ADs: ${ADS[*]}"
fi

# --- Worker: sweep memory for a single CPU level ---
hunt_cpu() {
  local OCPUS="$1"
  local LOG="$WORK_DIR/cpu_${OCPUS}.log"
  local MEMORY="$MAX_MEMORY"

  while [ "$MEMORY" -ge "$MIN_MEMORY" ]; do
    # Another worker already succeeded — stop
    [ -f "$SUCCESS_FILE" ] && return 0

    for AD in "${ADS[@]}"; do
      [ -f "$SUCCESS_FILE" ] && return 0

      AD=$(echo "$AD" | xargs)
      echo "[${OCPUS} OCPU] Trying ${MEMORY} GB @ $AD" >> "$LOG"

      RESULT=$(oci compute instance launch \
        --availability-domain "$AD" \
        --compartment-id "$COMPARTMENT_ID" \
        --shape "$SHAPE" \
        --shape-config "{\"ocpus\":${OCPUS},\"memoryInGBs\":${MEMORY}}" \
        --subnet-id "$SUBNET_ID" \
        --image-id "$IMAGE_ID" \
        --display-name "$DISPLAY_NAME" \
        --assign-public-ip true \
        --query "data.id" \
        --raw-output $REGION_FLAG 2>&1) && {
          echo "${OCPUS} ${MEMORY} ${RESULT}" > "$SUCCESS_FILE"
          echo "[${OCPUS} OCPU] SUCCESS: ${MEMORY} GB @ $AD -> $RESULT" >> "$LOG"
          return 0
        }

      echo "[${OCPUS} OCPU] Failed ${MEMORY} GB @ $AD" >> "$LOG"
    done

    MEMORY=$((MEMORY - 1))
  done

  echo "[${OCPUS} OCPU] All memory levels exhausted." >> "$LOG"
  return 0
}

# --- Launch parallel workers (one per CPU level) ---
echo ""
echo "Launching parallel hunters: ${MIN_OCPUS}-${MAX_OCPUS} OCPU × ${MAX_MEMORY}-${MIN_MEMORY} GB × ${#ADS[@]} ADs"
echo "---"

PIDS=()
for OCPUS in $(seq "$MIN_OCPUS" "$MAX_OCPUS"); do
  hunt_cpu "$OCPUS" &
  PIDS+=($!)
  echo "Started worker: ${OCPUS} OCPU (PID $!)"
done

# Wait for all workers to finish
for PID in "${PIDS[@]}"; do
  wait "$PID" 2>/dev/null || true
done

# --- Print logs from all workers ---
echo ""
echo "=== Worker Logs ==="
for OCPUS in $(seq "$MIN_OCPUS" "$MAX_OCPUS"); do
  LOG="$WORK_DIR/cpu_${OCPUS}.log"
  if [ -f "$LOG" ]; then
    cat "$LOG"
  fi
done

# --- Check result ---
if [ -f "$SUCCESS_FILE" ]; then
  read -r FINAL_OCPUS FINAL_MEMORY INSTANCE_ID < "$SUCCESS_FILE"
  echo ""
  echo "VM created: $INSTANCE_ID (${FINAL_OCPUS} OCPU / ${FINAL_MEMORY} GB)"
  echo "vm_status=created" >> "${GITHUB_OUTPUT:-/dev/null}"
  echo "Done."
  exit 0
fi

echo ""
echo "All combinations exhausted (${MIN_OCPUS}-${MAX_OCPUS} OCPU / ${MAX_MEMORY}-${MIN_MEMORY} GB) — no capacity."
exit 1
