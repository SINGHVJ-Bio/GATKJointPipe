#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------------------
# remove_samples_and_write_cleaned.sh
#
# Removes specified samples from a VCF, then recalculates AC/AN/AF/MAF/HWE.
#
# Arguments:
#   1: INPUT_VCF    - input VCF (typically the merged sorted VCF from step2)
#   2: SAMPLE_LIST  - file containing one sample ID per line to remove
#   3: OUT_BASE     - base output directory
#   4: BASE_NAME    - base name for output files
#   5: BCFTOOLS     - bcftools executable path
#   6: TABIX        - tabix executable path
# -------------------------------------------------------------------

if [ $# -ne 6 ]; then
    echo "Usage: $0 INPUT_VCF SAMPLE_LIST OUT_BASE BASE_NAME BCFTOOLS TABIX"
    exit 1
fi

INPUT_VCF="$1"
SAMPLE_LIST="$2"
OUT_BASE="$3"
BASE_NAME="$4"
BCFTOOLS="$5"
TABIX="$6"

INTERMEDIATE_DIR="${OUT_BASE}/removed_samples"
CLEANED_DIR="${OUT_BASE}/cleaned_vcf"
mkdir -p "${INTERMEDIATE_DIR}" "${CLEANED_DIR}"

OUT_PREFIX="${BASE_NAME}.rm"
OUT_VCF_INTERMEDIATE="${INTERMEDIATE_DIR}/${OUT_PREFIX}.vcf.gz"
OUT_VCF_WITHTAGS="${INTERMEDIATE_DIR}/${OUT_PREFIX}.withtags.vcf.gz"
FINAL_CLEANED_VCF="${CLEANED_DIR}/${BASE_NAME}.cleaned.vcf.gz"

echo "==== remove_samples_and_write_cleaned.sh ===="
echo "INPUT_VCF: $INPUT_VCF"
echo "SAMPLE_LIST: $SAMPLE_LIST"
echo "OUT_BASE: $OUT_BASE"
echo "BASE_NAME: $BASE_NAME"
echo "BCFTOOLS: $BCFTOOLS"
echo "TABIX: $TABIX"
echo "============================================"

# Validate sample list and input VCF
if [ ! -s "${SAMPLE_LIST}" ]; then
    echo "ERROR: sample list file not found or empty: ${SAMPLE_LIST}"
    exit 1
fi
if [ ! -s "${INPUT_VCF}" ]; then
    echo "ERROR: input VCF missing or empty: ${INPUT_VCF}"
    exit 1
fi

# Ensure input VCF is indexed
if [ ! -f "${INPUT_VCF}.tbi" ] && [ ! -f "${INPUT_VCF}.csi" ]; then
    echo "Index file missing for input VCF; creating index..."
    ${TABIX} -p vcf -f "${INPUT_VCF}"
fi

# Read sample list and build unique comma‑separated list
SAMPLES_TO_REMOVE=""
COUNT=0
while IFS= read -r line || [ -n "${line}" ]; do
    s=$(echo "${line}" | tr -d '\r' | awk '{$1=$1;print}')
    [ -z "${s}" ] && continue
    # avoid duplicates
    if ! echo ",${SAMPLES_TO_REMOVE}," | grep -q ",${s},"; then
        if [ -z "${SAMPLES_TO_REMOVE}" ]; then
            SAMPLES_TO_REMOVE="${s}"
        else
            SAMPLES_TO_REMOVE="${SAMPLES_TO_REMOVE},${s}"
        fi
        COUNT=$((COUNT+1))
    fi
done < "${SAMPLE_LIST}"

if [ "${COUNT}" -eq 0 ]; then
    echo "ERROR: no valid sample IDs found in ${SAMPLE_LIST}"
    exit 1
fi
echo "Requested to remove ${COUNT} sample(s)."

# Verify samples exist in VCF header
MISSING=0
for S in $(echo "${SAMPLES_TO_REMOVE}" | tr ',' ' '); do
    if ! ${BCFTOOLS} query -l "${INPUT_VCF}" | grep -xq -- "${S}"; then
        echo "  MISSING: ${S}"
        MISSING=1
    else
        echo "  FOUND:   ${S}"
    fi
done
if [ "${MISSING}" -ne 0 ]; then
    echo "ERROR: one or more samples listed are not present in the VCF header. Aborting."
    exit 1
fi

# Remove samples
echo "Removing samples using bcftools view..."
${BCFTOOLS} view -s "^${SAMPLES_TO_REMOVE}" -Oz -o "${OUT_VCF_INTERMEDIATE}" "${INPUT_VCF}"
${TABIX} -p vcf -f "${OUT_VCF_INTERMEDIATE}"

# Recompute AC/AN/AF/MAF/HWE
echo "Recomputing AC, AN, AF, MAF, HWE using bcftools +fill-tags..."
${BCFTOOLS} +fill-tags "${OUT_VCF_INTERMEDIATE}" -Oz -o "${OUT_VCF_WITHTAGS}" -- -t AC,AN,AF,MAF,HWE
${TABIX} -p vcf -f "${OUT_VCF_WITHTAGS}"

# Move final file to cleaned directory
echo "Moving final file to ${FINAL_CLEANED_VCF}"
mv -n "${OUT_VCF_WITHTAGS}" "${FINAL_CLEANED_VCF}"
if [ -f "${OUT_VCF_WITHTAGS}.tbi" ]; then
    mv -n "${OUT_VCF_WITHTAGS}.tbi" "${FINAL_CLEANED_VCF}.tbi"
else
    ${TABIX} -p vcf -f "${FINAL_CLEANED_VCF}"
fi

echo "Cleaned VCF: ${FINAL_CLEANED_VCF}"