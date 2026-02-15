from pathlib import Path
from ..utils import run_subprocess, check_files_exist

def run(config, logger):
    """
    Step 3: Remove specified samples from the VCF and recalculate tags.
    Only runs if enabled in config.
    """
    if not config.get('steps', 'run_step3', default=False):
        logger.info("Step3 is disabled, skipping.")
        return

    cfg = config.get('step3')
    if not cfg:
        logger.error("Missing 'step3' section in configuration")
        return

    input_vcf = cfg.get('input_vcf')
    sample_list = cfg.get('sample_remove_list')
    out_basedir = cfg.get('out_basedir')
    base_name = config.get('project', 'base_name')
    bcftools = cfg.get('bcftools', 'bcftools')
    tabix = cfg.get('tabix', 'tabix')

    # Check required input files
    check_files_exist([input_vcf, sample_list], logger, "Step3 missing input files")

    script_path = Path(__file__).parent.parent.parent / "scripts" / "remove_samples_and_write_cleaned.sh"
    if not script_path.exists():
        logger.error(f"Script not found: {script_path}")
        return

    cmd = [
        'bash', str(script_path),
        input_vcf,
        sample_list,
        out_basedir,
        base_name,
        bcftools,
        tabix
    ]
    run_subprocess(cmd, logger, "step3")