from pathlib import Path
from ..utils import run_subprocess, check_files_exist

def run(config, logger):
    """
    Step 4: VQSR (indels + SNPs) and snpEff annotation.
    Determines the appropriate input VCF based on whether step3 ran.
    """
    cfg = config.get('step4')
    if not cfg:
        logger.error("Missing 'step4' section in configuration")
        return

    # Decide input VCF: use step3 output if it exists and step3 was enabled,
    # otherwise fall back to step2 final VCF.
    if config.get('steps', 'run_step3', default=False):
        step3_cfg = config.get('step3')
        if step3_cfg:
            candidate = f"{step3_cfg['out_basedir']}/cleaned_vcf/{config.get('project','base_name')}.cleaned.vcf.gz"
            if Path(candidate).exists():
                input_vcf = candidate
                logger.info(f"Using step3 output as input: {input_vcf}")
            else:
                logger.warning(f"Step3 output not found at {candidate}, falling back to step2 final VCF")
                input_vcf = config.get('step2', 'final_vcf')
        else:
            input_vcf = config.get('step2', 'final_vcf')
    else:
        input_vcf = config.get('step2', 'final_vcf')

    out_base = cfg.get('out_base')
    ref = config.get('reference', 'fasta')
    dbsnp = config.get('reference', 'dbsnp')
    mills = config.get('reference', 'mills')
    axiom = config.get('reference', 'axiom')
    hapmap = config.get('reference', 'hapmap')
    omni = config.get('reference', 'omni')
    thousandg = config.get('reference', 'thousandg')
    snpeff_jar = cfg.get('snpeff_jar', '/home/ubuntu/snpEff/snpEff.jar')
    java_mem = cfg.get('java_mem', '-Xmx48g -Xms48g')
    excess_het_thresh = cfg.get('excess_het_threshold', 54.69)
    indel_tranches = ','.join(str(x) for x in cfg.get('indel_tranches', []))
    snp_tranches = ','.join(str(x) for x in cfg.get('snp_tranches', []))
    tabix = cfg.get('tabix', 'tabix')

    # Ensure all reference files exist
    check_files_exist(
        [input_vcf, ref, dbsnp, mills, axiom, hapmap, omni, thousandg],
        logger,
        "Step4 missing required files"
    )

    script_path = Path(__file__).parent.parent.parent / "scripts" / "recalibration.sh"
    if not script_path.exists():
        logger.error(f"Script not found: {script_path}")
        return

    cmd = [
        'bash', str(script_path),
        input_vcf,
        out_base,
        ref,
        dbsnp,
        mills,
        axiom,
        hapmap,
        omni,
        thousandg,
        snpeff_jar,
        java_mem,
        str(excess_het_thresh),
        indel_tranches,
        snp_tranches,
        tabix
    ]
    run_subprocess(cmd, logger, "step4")