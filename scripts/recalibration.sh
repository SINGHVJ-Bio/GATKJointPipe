#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------------------
# recalibration.sh
#
# Runs GATK VQSR (indels + SNPs) and snpEff annotation.
#
# Arguments:
#   1: INPUT_VCF          - input VCF (should be filtered/cleaned)
#   2: OUT_BASE           - output directory base
#   3: REF_FASTA          - reference FASTA
#   4: DBSNP              - dbSNP VCF
#   5: MILLS              - Mills and 1000G gold standard indels VCF
#   6: AXIOM              - Axiom Exome Plus VCF
#   7: HAPMAP             - HapMap VCF
#   8: OMNI               - 1000G Omni VCF
#   9: THOUSANDG          - 1000G phase1 SNPs VCF
#  10: SNPEFF_JAR         - path to snpEff.jar
#  11: JAVA_MEM           - Java memory options (e.g., "-Xmx48g -Xms48g")
#  12: EXCESS_HET_THRESH  - ExcessHet filter threshold
#  13: INDEL_TRANCHES     - comma‑separated list of indel tranche levels
#  14: SNP_TRANCHES       - comma‑separated list of SNP tranche levels
#  15: TABIX              - tabix executable path
# -------------------------------------------------------------------

if [ $# -ne 15 ]; then
    echo "Usage: $0 INPUT_VCF OUT_BASE REF_FASTA DBSNP MILLS AXIOM HAPMAP OMNI THOUSANDG SNPEFF_JAR JAVA_MEM EXCESS_HET_THRESH INDEL_TRANCHES SNP_TRANCHES TABIX"
    exit 1
fi

INPUT_VCF="$1"
OUT_BASE="$2"
REF_FASTA="$3"
DBSNP="$4"
MILLS="$5"
AXIOM="$6"
HAPMAP="$7"
OMNI="$8"
THOUSANDG="$9"
SNPEFF_JAR="${10}"
JAVA_MEM="${11}"
EXCESS_HET_THRESH="${12}"
INDEL_TRANCHES="${13}"
SNP_TRANCHES="${14}"
TABIX="${15}"

# Derive prefix from input filename (remove .vcf.gz)
PREFIX="$(basename "${INPUT_VCF%.vcf.gz}")"
COHORT_PREFIX="${PREFIX}_cohort"

mkdir -p "${OUT_BASE}"
cd "${OUT_BASE}"

# Step 1: VariantFiltration to tag ExcessHet
echo "Running VariantFiltration..."
gatk --java-options "${JAVA_MEM}" VariantFiltration \
    -V "${INPUT_VCF}" \
    --filter-expression "ExcessHet > ${EXCESS_HET_THRESH}" \
    --filter-name ExcessHet \
    -O "${COHORT_PREFIX}.excesshet.vcf.gz"

# Step 2: Make sites-only VCF
echo "Creating sites-only VCF..."
gatk MakeSitesOnlyVcf \
    -I "${COHORT_PREFIX}.excesshet.vcf.gz" \
    -O "${COHORT_PREFIX}.sitesonly.vcf.gz"

# Step 3: Indel recalibration (VariantRecalibrator)
echo "Running VariantRecalibrator for INDELs..."
gatk --java-options "${JAVA_MEM}" VariantRecalibrator \
    -V "${COHORT_PREFIX}.sitesonly.vcf.gz" \
    --trust-all-polymorphic \
    -tranche $(echo "${INDEL_TRANCHES}" | tr ',' ' ') \
    -an FS -an ReadPosRankSum -an MQRankSum -an QD -an SOR -an DP \
    -mode INDEL \
    --max-gaussians 4 \
    -resource:mills,known=false,training=true,truth=true,prior=12 "${MILLS}" \
    -resource:axiomPoly,known=false,training=true,truth=false,prior=10 "${AXIOM}" \
    -resource:dbsnp,known=true,training=false,truth=false,prior=2 "${DBSNP}" \
    -O "${COHORT_PREFIX}.indels.recal" \
    --tranches-file "${COHORT_PREFIX}.indels.tranches"

# Step 4: ApplyVQSR for INDELs
echo "Applying VQSR for INDELs..."
gatk --java-options "${JAVA_MEM}" ApplyVQSR \
    -V "${COHORT_PREFIX}.excesshet.vcf.gz" \
    --recal-file "${COHORT_PREFIX}.indels.recal" \
    --tranches-file "${COHORT_PREFIX}.indels.tranches" \
    --truth-sensitivity-filter-level 99.7 \
    --create-output-variant-index true \
    -mode INDEL \
    -O "${COHORT_PREFIX}.indel.recalibrated.vcf.gz"

# Step 5: SNP recalibration (VariantRecalibrator)
echo "Running VariantRecalibrator for SNPs..."
gatk --java-options "${JAVA_MEM}" VariantRecalibrator \
    -V "${COHORT_PREFIX}.sitesonly.vcf.gz" \
    --trust-all-polymorphic \
    -tranche $(echo "${SNP_TRANCHES}" | tr ',' ' ') \
    -an QD -an MQRankSum -an ReadPosRankSum -an FS -an MQ -an SOR -an DP \
    -mode SNP \
    --max-gaussians 6 \
    -resource:hapmap,known=false,training=true,truth=true,prior=15 "${HAPMAP}" \
    -resource:omni,known=false,training=true,truth=true,prior=12 "${OMNI}" \
    -resource:1000G,known=false,training=true,truth=false,prior=10 "${THOUSANDG}" \
    -resource:dbsnp,known=true,training=false,truth=false,prior=7 "${DBSNP}" \
    -O "${COHORT_PREFIX}.snps.recal" \
    --tranches-file "${COHORT_PREFIX}.snps.tranches"

# Step 6: ApplyVQSR for SNPs
echo "Applying VQSR for SNPs..."
gatk --java-options "${JAVA_MEM}" ApplyVQSR \
    -V "${COHORT_PREFIX}.indel.recalibrated.vcf.gz" \
    --recal-file "${COHORT_PREFIX}.snps.recal" \
    --tranches-file "${COHORT_PREFIX}.snps.tranches" \
    --truth-sensitivity-filter-level 99.7 \
    --create-output-variant-index true \
    -mode SNP \
    -O "${COHORT_PREFIX}.snp.recalibrated.vcf.gz"

# Step 7: Annotate with snpEff
echo "Annotating SNP-recalibrated VCF with snpEff..."
if [ ! -f "${SNPEFF_JAR}" ]; then
    echo "ERROR: snpEff jar not found at ${SNPEFF_JAR}"
    exit 1
fi

java ${JAVA_MEM} -jar "${SNPEFF_JAR}" -v GRCh38.99 "${COHORT_PREFIX}.snp.recalibrated.vcf.gz" \
    | bgzip -c > "${COHORT_PREFIX}.snp.recalibrated.snpEff_ann.vcf.gz"
${TABIX} -p vcf -f "${COHORT_PREFIX}.snp.recalibrated.snpEff_ann.vcf.gz"

echo "Recalibration completed. Outputs in ${OUT_BASE}:"
ls -lh "${OUT_BASE}" | head -20