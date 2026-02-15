#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------------------
# annotate_rsids_bcftools.sh
#
# Annotates a VCF with rsIDs from dbSNP, producing two versions:
#   - intact (original multiallelic representation preserved)
#   - split (multiallelic sites split and normalized)
#
# All parameters are passed as command-line arguments.
#
# Usage: $0 INPUT_VCF OUT_INTACT OUT_SPLIT DBSNP_VCF REF_FASTA BCFTOOLS TABIX
#   REF_FASTA may be empty to skip left-alignment.
# -------------------------------------------------------------------

if [ $# -ne 7 ]; then
    echo "Usage: $0 INPUT_VCF OUT_INTACT OUT_SPLIT DBSNP_VCF REF_FASTA BCFTOOLS TABIX"
    echo "Example: $0 input.vcf.gz intact.vcf.gz split.vcf.gz dbsnp.vcf.gz ref.fa bcftools tabix"
    exit 1
fi

INPUT_VCF="$1"
OUT_INTACT="$2"
OUT_SPLIT="$3"
DBSNP_VCF="$4"
REF_FASTA="$5"
BCFTOOLS="$6"
TABIX="$7"

WORKDIR=$(dirname "${INPUT_VCF}")
TMPDIR="${WORKDIR}/tmp_annot_rsids_$$"
mkdir -p "${TMPDIR}"
trap 'rm -rf "${TMPDIR}"' EXIT

echo "==== annotate_rsids_bcftools.sh ===="
echo "INPUT_VCF: $INPUT_VCF"
echo "OUT_INTACT: $OUT_INTACT"
echo "OUT_SPLIT: $OUT_SPLIT"
echo "DBSNP_VCF: $DBSNP_VCF"
echo "REF_FASTA: $REF_FASTA"
echo "BCFTOOLS: $BCFTOOLS"
echo "TABIX: $TABIX"
echo "====================================="

# Index dbSNP if needed
if [ ! -f "${DBSNP_VCF}.tbi" ] && [ ! -f "${DBSNP_VCF}.csi" ]; then
    echo "Indexing dbSNP VCF..."
    ${TABIX} -p vcf "${DBSNP_VCF}"
fi

# Copy input and dbSNP to temporary directory
echo "Creating temporary copies..."
${BCFTOOLS} view -Oz -o "${TMPDIR}/input.copy.vcf.gz" "${INPUT_VCF}"
${TABIX} -p vcf "${TMPDIR}/input.copy.vcf.gz"
${BCFTOOLS} view -Oz -o "${TMPDIR}/dbsnp.copy.vcf.gz" "${DBSNP_VCF}"
${TABIX} -p vcf "${TMPDIR}/dbsnp.copy.vcf.gz"

# Extract header from original VCF
${BCFTOOLS} view -h "${INPUT_VCF}" > "${TMPDIR}/orig.header.hdr"

# -------------------------------------------------------------------
# Split version (normalize + split multiallelics)
# -------------------------------------------------------------------
echo "Creating split version..."
if [ -n "${REF_FASTA}" ]; then
    ${BCFTOOLS} norm -f "${REF_FASTA}" -m -both -Oz -o "${TMPDIR}/input.norm.split.vcf.gz" "${TMPDIR}/input.copy.vcf.gz"
else
    ${BCFTOOLS} norm -m -both -Oz -o "${TMPDIR}/input.norm.split.vcf.gz" "${TMPDIR}/input.copy.vcf.gz"
fi
${TABIX} -p vcf "${TMPDIR}/input.norm.split.vcf.gz"

# Annotate with dbSNP IDs
${BCFTOOLS} annotate -a "${TMPDIR}/dbsnp.copy.vcf.gz" -c ID -Oz -o "${TMPDIR}/annotated.split.vcf.gz" "${TMPDIR}/input.norm.split.vcf.gz"
${TABIX} -p vcf "${TMPDIR}/annotated.split.vcf.gz"

# Extract records as TSV for merging
${BCFTOOLS} query -f '%CHROM\t%POS\t%REF\t%ALT\t%ID\t%QUAL\t%FILTER\t%INFO\n' "${TMPDIR}/input.norm.split.vcf.gz" \
    | sort -k1,1 -k2,2n -k3,3 -k4,4 > "${TMPDIR}/orig.split.tsv"
${BCFTOOLS} query -f '%CHROM\t%POS\t%REF\t%ALT\t%ID\t%QUAL\t%FILTER\t%INFO\n' "${TMPDIR}/annotated.split.vcf.gz" \
    | sort -k1,1 -k2,2n -k3,3 -k4,4 > "${TMPDIR}/annot.split.tsv"

# Merge IDs: prefer original ID if present and not '.', else use dbSNP ID
awk -F'\t' 'BEGIN{OFS="\t"}
NR==FNR{
    key=$1"\t"$2"\t"$3"\t"$4
    origID[key]=$5
    rest_orig[key]= (NF>=6 ? substr($0, index($0,$6)) : "")
    next
}
{
    key=$1"\t"$2"\t"$3"\t"$4
    annotID=$5
    rest = (key in rest_orig ? rest_orig[key] : (NF>=6 ? substr($0, index($0,$6)) : ""))
    if ((key in origID) && origID[key] != ".") id = origID[key]
    else id = annotID
    printf "%s\t%s\t%s\t%s\t%s%s\n", $1,$2,id,$3,$4,rest
}' "${TMPDIR}/orig.split.tsv" "${TMPDIR}/annot.split.tsv" > "${TMPDIR}/records.split.vcf"

# Assemble final split VCF
cat "${TMPDIR}/orig.header.hdr" > "${TMPDIR}/final.split.vcf"
cat "${TMPDIR}/records.split.vcf" >> "${TMPDIR}/final.split.vcf"
bgzip -c "${TMPDIR}/final.split.vcf" > "${OUT_SPLIT}"
${TABIX} -p vcf "${OUT_SPLIT}"
echo "Split VCF written: ${OUT_SPLIT}"

# -------------------------------------------------------------------
# Intact version (preserve multiallelic representation)
# -------------------------------------------------------------------
echo "Creating intact version..."
${BCFTOOLS} annotate -a "${TMPDIR}/dbsnp.copy.vcf.gz" -c ID -Oz -o "${TMPDIR}/annotated.intact.vcf.gz" "${TMPDIR}/input.copy.vcf.gz"
${TABIX} -p vcf "${TMPDIR}/annotated.intact.vcf.gz"

# Extract TSVs
${BCFTOOLS} query -f '%CHROM\t%POS\t%REF\t%ALT\t%ID\t%QUAL\t%FILTER\t%INFO\n' "${TMPDIR}/input.copy.vcf.gz" \
    | sort -k1,1 -k2,2n -k3,3 -k4,4 > "${TMPDIR}/orig.intact.tsv"
${BCFTOOLS} query -f '%CHROM\t%POS\t%REF\t%ALT\t%ID\t%QUAL\t%FILTER\t%INFO\n' "${TMPDIR}/annotated.intact.vcf.gz" \
    | sort -k1,1 -k2,2n -k3,3 -k4,4 > "${TMPDIR}/annot.intact.tsv"

# Merge IDs
awk -F'\t' 'BEGIN{OFS="\t"}
NR==FNR{
    key=$1"\t"$2"\t"$3"\t"$4
    origID[key]=$5
    rest_orig[key]= (NF>=6 ? substr($0, index($0,$6)) : "")
    next
}
{
    key=$1"\t"$2"\t"$3"\t"$4
    annotID=$5
    rest = (key in rest_orig ? rest_orig[key] : (NF>=6 ? substr($0, index($0,$6)) : ""))
    if ((key in origID) && origID[key] != ".") id = origID[key]
    else id = annotID
    printf "%s\t%s\t%s\t%s\t%s%s\n", $1,$2,id,$3,$4,rest
}' "${TMPDIR}/orig.intact.tsv" "${TMPDIR}/annot.intact.tsv" > "${TMPDIR}/records.intact.vcf"

# Assemble final intact VCF
cat "${TMPDIR}/orig.header.hdr" > "${TMPDIR}/final.intact.vcf"
cat "${TMPDIR}/records.intact.vcf" >> "${TMPDIR}/final.intact.vcf"
bgzip -c "${TMPDIR}/final.intact.vcf" > "${OUT_INTACT}"
${TABIX} -p vcf "${OUT_INTACT}"
echo "Intact VCF written: ${OUT_INTACT}"

echo "All done."