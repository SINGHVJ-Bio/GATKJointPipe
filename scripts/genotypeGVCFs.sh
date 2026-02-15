#!/bin/bash
set -euo pipefail

# -------------------------------------------------------------------
# genotypeGVCFs.sh
#
# Runs GATK GenotypeGVCFs for a single chromosome, splitting it into
# intervals, then merges and sorts the resulting VCFs.
#
# Arguments:
#   1: jcResdir   - output directory for per‑interval VCFs
#   2: ref        - reference FASTA
#   3: combinedcohort - base name for output files
#   4: genomicsdb - name of the GenomicsDB workspace
#   5: gvcfdir    - directory containing the GenomicsDB
#   6: chr        - chromosome name (e.g., chr1)
#   7: workdir    - working directory for temporary files
# -------------------------------------------------------------------

if [ $# -ne 7 ]; then
    echo "Usage: $0 jcResdir ref combinedcohort genomicsdb gvcfdir chr workdir"
    exit 1
fi

jcResdir=$1
ref=$2
combinedcohort=$3
genomicsdb=$4
gvcfdir=$5
chr=$6
workdir=$7

mkdir -p $workdir/temp_dir
mkdir -p $jcResdir
cd $jcResdir

echo "Script started"
echo "Parameters: jcResdir=$jcResdir ref=$ref combinedcohort=$combinedcohort genomicsdb=$genomicsdb gvcfdir=$gvcfdir chr=$chr workdir=$workdir"

# Function to create intervals for a chromosome
create_intervals() {
  chr=$1
  chr_length=$2
  interval_size=50000000
  start=1
  echo "Creating intervals for $chr (length: $chr_length, interval size: $interval_size)"
  # remove any existing intervals file to avoid appending duplicates
  rm -f intervals_${chr}.bed
  while [ $start -le $chr_length ]; do
    end=$((start + interval_size - 1))
    if [ $end -gt $chr_length ]; then
      end=$chr_length
    fi
    echo "$chr $start $end" >> intervals_${chr}.bed
    start=$((end + 1))
  done
  echo "Created intervals file intervals_${chr}.bed"
}

# Function to process intervals and merge VCFs
process_intervals() {
  chr=$1
  chr_length=$2
  output_prefix=$3

  create_intervals $chr $chr_length

  # Process each interval
  while read -r chr start end; do
    echo "Genotyping interval ${chr}:${start}-${end}"
    gatk --java-options "-Xmx32g -XX:ParallelGCThreads=32 -XX:ConcGCThreads=16 -XX:+UseG1GC -XX:InitiatingHeapOccupancyPercent=75" \
      GenotypeGVCFs \
      -R $ref \
      -V gendb://$gvcfdir/$genomicsdb \
      -O $jcResdir/${output_prefix}_${chr}_${start}_${end}.vcf.gz \
      -L ${chr}:${start}-${end} \
      --tmp-dir $workdir/temp_dir
    echo "Finished genotyping interval ${chr}:${start}-${end}"
  done < intervals_${chr}.bed
  echo "Completed all intervals for $chr"
}

# Function to merge and sort per‑chromosome VCFs
process_merge() {
  chr=$1
  output_prefix=$2

  echo "Merging VCFs for $chr into ${output_prefix}_${chr}_merged.vcf.gz"
  # Note: TMPDIR is set for bcftools to use a fast temporary directory.
  # You may change this path if needed.
  TMPDIR=/home/ubuntu/DATA_DRIVE/WGS_JC_run/temp_dir bcftools concat -O z -o $jcResdir/${output_prefix}_${chr}_merged.vcf.gz $jcResdir/${output_prefix}_${chr}_*.vcf.gz
  echo "Concat completed for $chr"

  echo "Sorting merged VCF for $chr"
  TMPDIR=/home/ubuntu/DATA_DRIVE/WGS_JC_run/temp_dir bcftools sort $jcResdir/${output_prefix}_${chr}_merged.vcf.gz -o $jcResdir/${output_prefix}_${chr}_merged_sorted.vcf.gz
  echo "Sort completed for $chr"

  echo "Indexing merged VCF for $chr"
  tabix -p vcf $jcResdir/${output_prefix}_${chr}_merged_sorted.vcf.gz
  echo "Indexing completed for $chr"

  # Clean up interval file and intermediate VCFs (optional)
  rm -f intervals_${chr}.bed

  # Uncomment the following lines if you want to delete intermediate interval VCFs
  # for file in $jcResdir/${output_prefix}_${chr}_*.vcf.gz; do
  #   if [[ $file != *"${output_prefix}_${chr}_merged_sorted.vcf.gz"* ]]; then
  #     rm -f $file
  #   fi
  # done

  echo "Merge and cleanup steps completed for $chr"
}

# Chromosome lengths based on GRCh38
declare -A chr_lengths
chr_lengths["chr1"]=248956422
chr_lengths["chr2"]=242193529
chr_lengths["chr3"]=198295559
chr_lengths["chr4"]=190214555
chr_lengths["chr5"]=181538259
chr_lengths["chr6"]=170805979
chr_lengths["chr7"]=159345973
chr_lengths["chr8"]=145138636
chr_lengths["chr9"]=138394717
chr_lengths["chr10"]=133797422
chr_lengths["chr11"]=135086622
chr_lengths["chr12"]=133275309
chr_lengths["chr13"]=114364328
chr_lengths["chr14"]=107043718
chr_lengths["chr15"]=101991189
chr_lengths["chr16"]=90338345
chr_lengths["chr17"]=83257441
chr_lengths["chr18"]=80373285
chr_lengths["chr19"]=58617616
chr_lengths["chr20"]=64444167
chr_lengths["chr21"]=46709983
chr_lengths["chr22"]=50818468
chr_lengths["chrX"]=156040895
chr_lengths["chrY"]=57227415

# Check if chromosome parameter is provided
if [ "$chr" = "None" ]; then
  echo "Not using chromosome parameter. Running GenotypeGVCFs for whole cohort"
  gatk --java-options "-Xmx32g -XX:ParallelGCThreads=32 -XX:ConcGCThreads=16 -XX:+UseG1GC -XX:InitiatingHeapOccupancyPercent=50" \
      GenotypeGVCFs \
      -R $ref \
      -V gendb://$gvcfdir/$genomicsdb \
      -O $jcResdir/${combinedcohort}.vcf.gz \
      --tmp-dir $workdir/temp_dir
  echo "Completed GenotypeGVCFs for whole cohort"
else
  echo "Using chromosome parameter: $chr"
  echo "Calling process_intervals for $chr"
  process_intervals $chr ${chr_lengths[$chr]} $combinedcohort
  echo "Calling process_merge for $chr"
  process_merge $chr $combinedcohort
  echo "Chromosome processing completed for $chr"
fi

echo "Script finished"