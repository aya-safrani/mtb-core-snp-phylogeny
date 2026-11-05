#!/usr/bin/env bash
# Core-SNP phylogeny of 10 public Mycobacterium tuberculosis isolates (reference H37Rv)
# Run from the project root. Isolate accessions are listed in isolate_list.txt.
# Required tools: sra-tools, fastp, snippy (includes snippy-core), snp-sites, IQ-TREE
set -euo pipefail

THREADS=4
REF_GBK=ref/H37Rv.gbk   # H37Rv reference (NC_000962), GenBank format

mkdir -p data/raw data/trimmed results/qc results/mapping results/core_snp results/tree

# 1. Download the public sequencing runs and extract paired FASTQ files
for id in $(cat isolate_list.txt); do
  echo "=== Download $id ==="
  prefetch "$id" -O data/raw/
  fasterq-dump data/raw/$id/$id.sra -O data/raw/$id/ --split-files
  gzip data/raw/$id/${id}_1.fastq
  gzip data/raw/$id/${id}_2.fastq
done

# 2. Read trimming and quality report (fastp)
for id in $(cat isolate_list.txt); do
  echo "=== Trimming $id ==="
  fastp \
    -i data/raw/$id/${id}_1.fastq.gz \
    -I data/raw/$id/${id}_2.fastq.gz \
    -o data/trimmed/${id}_1.trim.fastq.gz \
    -O data/trimmed/${id}_2.trim.fastq.gz \
    --detect_adapter_for_pe \
    -q 20 -l 50 \
    -j results/qc/fastp_${id}.json \
    -h results/qc/fastp_${id}.html
done

# 3. Mapping and variant calling against H37Rv, one isolate at a time (snippy)
#    Note: Snippy's samclip step can conflict with recent samtools versions (markdup error "no ms score tag");
#    check that samclip and samtools versions are compatible before running.
for id in $(cat isolate_list.txt); do
  echo "=== Snippy $id ==="
  snippy --cpus "$THREADS" --force \
    --outdir results/mapping/$id \
    --ref "$REF_GBK" \
    --R1 data/trimmed/${id}_1.trim.fastq.gz \
    --R2 data/trimmed/${id}_2.trim.fastq.gz
done

# 4. Core genome alignment of the 10 isolates (snippy-core), then keep variable sites only (snp-sites)
snippy-core --ref results/mapping/ERR234101/reference/ref.fa \
  $(for id in $(cat isolate_list.txt); do echo results/mapping/$id; done) \
  --prefix results/core_snp/core
snp-sites -c results/core_snp/core.full.aln > results/core_snp/core_filtered.aln

# 5. Maximum-likelihood phylogeny: GTR + ascertainment bias correction, 1,000 ultrafast bootstraps
iqtree -s results/core_snp/core_filtered.aln \
  -m GTR+ASC -B 1000 -T AUTO \
  --prefix results/tree/mtb10

# 6. Visualisation: open results/tree/mtb10.treefile (or .contree) in iTOL
#    with the colour annotation file results/tree/itol_colors.txt
