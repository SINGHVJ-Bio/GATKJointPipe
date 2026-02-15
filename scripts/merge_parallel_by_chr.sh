#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------------------
# merge_parallel_by_chr.sh
#
# Concatenates per‑chromosome VCF fragments (from step1) into whole‑chromosome VCFs,
# then merges all chromosomes into a final sorted whole‑genome VCF.
#
# Arguments:
#   1: INPUT_DIR   - directory containing per‑chromosome fragment VCFs
#   2: OUT_DIR     - directory where per‑chromosome and final VCFs will be written
#   3: FINAL_VCF   - path to the final merged (unsorted) VCF
#   4: JOBS        - number of parallel jobs for GNU parallel
#   5: BASE_NAME   - base name used in fragment filenames (e.g., ENABL_merged_323_2rep)
#   6: CHROMS_LIST - space‑separated list of chromosomes (e.g., "chr1 chr2 chrX")
#   7: BCFTOOLS    - bcftools executable path
#   8: TABIX       - tabix executable path
#   9: PARALLEL    - GNU parallel executable path
# -------------------------------------------------------------------

if [ $# -lt 9 ]; then
    echo "Usage: $0 INPUT_DIR OUT_DIR FINAL_VCF JOBS BASE_NAME CHROMS_LIST BCFTOOLS TABIX PARALLEL"
    echo "Example: $0 /input /output /output/final.vcf.gz 12 ENABL_merged 'chr1 chr2' bcftools tabix parallel"
    exit 1
fi

INPUT_DIR="$1"
OUT_DIR="$2"
FINAL_VCF="$3"
JOBS="$4"
BASE_NAME="$5"
CHROMS_LIST="$6"
BCFTOOLS="$7"
TABIX="$8"
PARALLEL="$9"

# Create output directories
mkdir -p "${OUT_DIR}"
PER_CHR_DIR="${OUT_DIR}/per_chr"
mkdir -p "${PER_CHR_DIR}"

echo "==== merge_parallel_by_chr.sh ===="
echo "INPUT_DIR: $INPUT_DIR"
echo "OUT_DIR: $OUT_DIR"
echo "FINAL_VCF: $FINAL_VCF"
echo "JOBS: $JOBS"
echo "BASE_NAME: $BASE_NAME"
echo "CHROMS_LIST: $CHROMS_LIST"
echo "BCFTOOLS: $BCFTOOLS"
echo "TABIX: $TABIX"
echo "PARALLEL: $PARALLEL"
echo "================================="

# Build master list of input VCFs (fragments from step1)
ALL_LIST="${OUT_DIR}/all_vcfs.list"
find "${INPUT_DIR}" -maxdepth 1 -type f -name "${BASE_NAME}_chr*.vcf.gz" -print | sort > "${ALL_LIST}"
NUM_IN=$(wc -l < "${ALL_LIST}" || echo 0)
echo "Found ${NUM_IN} input VCF.gz files"
if [ "${NUM_IN}" -eq 0 ]; then
    echo "ERROR: no input VCF.gz files found in ${INPUT_DIR}"
    exit 1
fi

# Convert CHROMS_LIST string into an array
IFS=' ' read -r -a CHROMS <<< "$CHROMS_LIST"

# Create per‑chromosome file lists
echo "Creating per‑chromosome file lists..."
for CHR in "${CHROMS[@]}"; do
    LIST="${PER_CHR_DIR}/per_chr_${CHR}.list"
    # match token chr<CHR> followed by ., _, or end
    grep -E "chr${CHR}([_.]|$)" "${ALL_LIST}" > "${LIST}" || true
    COUNT=$(wc -l < "${LIST}" || echo 0)
    echo "  chr${CHR}: ${COUNT} fragment(s)"
done

# Parallel concat per chromosome
echo "Starting per‑chromosome concatenation..."
export BCFTOOLS TABIX PER_CHR_DIR
${PARALLEL} --jobs "${JOBS}" --no-notice --lb --tagstring "chr{1}:" '
    CHR={1}
    LIST="${PER_CHR_DIR}/per_chr_${CHR}.list"
    OUT="${PER_CHR_DIR}/${BASE_NAME}_chr${CHR}.vcf.gz"
    if [ -s "$LIST" ]; then
        echo "START $(date)"
        ${BCFTOOLS} concat -a -Oz -o "$OUT" -f "$LIST"
        ${TABIX} -p vcf -f "$OUT"
        echo "DONE  $(date)"
    else
        echo "SKIP (no fragments)"
    fi
' ::: "${CHROMS[@]}"

# Build final ordered list
FINAL_LIST="${OUT_DIR}/final_per_chr_order.list"
: > "${FINAL_LIST}"
for CHR in "${CHROMS[@]}"; do
    PC="${PER_CHR_DIR}/${BASE_NAME}_chr${CHR}.vcf.gz"
    if [ -s "${PC}" ]; then
        echo "${PC}" >> "${FINAL_LIST}"
    fi
done
FINAL_COUNT=$(wc -l < "${FINAL_LIST}" || echo 0)
echo "Final per‑chromosome list entries: ${FINAL_COUNT}"
if [ "${FINAL_COUNT}" -eq 0 ]; then
    echo "ERROR: no per‑chromosome outputs to merge; aborting"
    exit 1
fi

# Final concat, sort and index
echo "Concatenating per‑chromosome files into ${FINAL_VCF}"
${BCFTOOLS} concat -a -Oz -o "${FINAL_VCF}" -f "${FINAL_LIST}"
${TABIX} -p vcf -f "${FINAL_VCF}"

FINAL_SORTED="${FINAL_VCF%.vcf.gz}.sorted.vcf.gz"
echo "Sorting ${FINAL_VCF} -> ${FINAL_SORTED}"
${BCFTOOLS} sort -Oz -o "${FINAL_SORTED}" "${FINAL_VCF}"
${TABIX} -p vcf -f "${FINAL_SORTED}"

echo "All done. Final outputs:"
ls -lh "${FINAL_VCF}" "${FINAL_SORTED}"