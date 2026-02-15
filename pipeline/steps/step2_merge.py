from pathlib import Path
from ..utils import run_subprocess

def run(config, logger):
    """
    Step 2: Merge per‑chromosome VCFs into a whole‑genome sorted VCF.
    Calls merge_parallel_by_chr.sh.
    """
    cfg = config.get('step2')
    if not cfg:
        logger.error("Missing 'step2' section in configuration")
        return

    input_dir = cfg.get('input_dir')
    out_dir = cfg.get('out_dir')
    final_vcf = cfg.get('final_vcf')
    jobs = cfg.get('jobs', 12)
    base_name = config.get('project', 'base_name')
    chromosomes = config.get('step1', 'chromosomes', default=[])
    bcftools = cfg.get('bcftools', 'bcftools')
    tabix = cfg.get('tabix', 'tabix')
    parallel = cfg.get('parallel', 'parallel')

    # Convert chromosome list to space-separated string
    chroms_str = ' '.join(chromosomes)

    # Create output directory
    Path(out_dir).mkdir(parents=True, exist_ok=True)

    script_path = Path(__file__).parent.parent.parent / "scripts" / "merge_parallel_by_chr.sh"
    if not script_path.exists():
        logger.error(f"Script not found: {script_path}")
        return

    cmd = [
        'bash', str(script_path),
        input_dir,
        out_dir,
        final_vcf,
        str(jobs),
        base_name,
        chroms_str,
        bcftools,
        tabix,
        parallel
    ]
    run_subprocess(cmd, logger, "step2")