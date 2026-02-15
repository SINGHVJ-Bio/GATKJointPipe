#!/bin/bash
# Simple GenomicsDB Update Script
# For adding 39 samples to existing 2.5TB database on 48-core system

# Set paths (EDIT THESE)
EXISTING_DB="gvcf_genomicsdb"
NEW_GVCF_DIR="/home/ubuntu/DATA_DRIVE/gvcfs"
TMP="/home/ubuntu/DATA_DRIVE/TMP"

mkdir -p "$TMP"

# Create sample map
cd "$NEW_GVCF_DIR"
echo "Creating sample map..."
for gvcf in *.g.vcf.gz; do
    sample="${gvcf%.g.vcf.gz}"
    echo -e "$sample\t$(realpath "$gvcf")"
done > new_samples.map

# Update GenomicsDB (optimized for 48 cores)
echo "Starting GenomicsDB update..."
gatk --java-options "-Xmx180g -Xms180g" \
  GenomicsDBImport \
  --genomicsdb-update-workspace-path "$EXISTING_DB" \
  --sample-name-map new_samples.map \
  --reader-threads 40 \
  --batch-size 20 \
  --tmp-dir "$TMP"

echo "Update complete."
