from pathlib import Path
from ..utils import run_subprocess, check_files_exist

def run(config, logger):
    """
    Step 5: Annotate VCF with rsIDs from dbSNP, producing intact and split versions.
    """
    cfg = config.get('step5')
    if not cfg:
        logger.error("Missing 'step5' section in configuration")
        return

    # Derive input VCF from step4 output by default
    step4_out_base = config.get('step4', 'out_base')
    base_name = config.get('project', 'base_name')
    default_input = f"{step4_out_base}/{base_name}_cohort.snp.recalibrated.snpEff_ann.vcf.gz"
    input_vcf = cfg.get('input_vcf', default_input)
    out_intact = cfg.get('out_intact', f"{cfg['workdir']}/{base_name}_cohort.snp.recalibrated.snpEff_ann.rsids.vcf.gz")
    out_split = cfg.get('out_split', f"{cfg['workdir']}/{base_name}_cohort.snp.recalibrated.snpEff_ann.rsids.split.vcf.gz")
    dbsnp = cfg.get('dbsnp', config.get('reference', 'dbsnp'))
    ref_fasta = cfg.get('ref_fasta', config.get('reference', 'fasta', default=''))
    bcftools = cfg.get('bcftools', 'bcftools')
    tabix = cfg.get('tabix', 'tabix')

    check_files_exist([input_vcf, dbsnp], logger, "Step5 missing input files")

    script_path = Path(__file__).parent.parent.parent / "scripts" / "annotate_rsids_bcftools.sh"
    if not script_path.exists():
        logger.error(f"Script not found: {script_path}")
        return

    cmd = [
        'bash', str(script_path),
        input_vcf,
        out_intact,
        out_split,
        dbsnp,
        ref_fasta,
        bcftools,
        tabix
    ]
    run_subprocess(cmd, logger, "step5")