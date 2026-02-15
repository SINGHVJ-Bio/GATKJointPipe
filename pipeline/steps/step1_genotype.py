import subprocess
import concurrent.futures
from pathlib import Path
from ..utils import check_files_exist

def run(config, logger):
    """
    Step 1: GenotypeGVCFs in parallel per chromosome.
    Calls genotypeGVCFs.sh for each chromosome, running in batches.
    """
    cfg = config.get('step1')
    if not cfg:
        logger.error("Missing 'step1' section in configuration")
        return

    # Required inputs
    ref = config.get('reference', 'fasta')
    if not ref:
        logger.error("Reference FASTA not defined in configuration")
        return
    genomicsdb = cfg.get('genomicsdb')
    gvcfdir = cfg.get('gvcfdir')
    chromosomes = cfg.get('chromosomes')
    workdir = cfg.get('workdir', config.get('project', 'work_dir'))
    out_dir = cfg.get('out_dir', f"{workdir}/ENABL_merged")
    batch_size = cfg.get('batch_size', 12)
    interval_size = cfg.get('interval_size', 50000000)  # not used directly, but passed to script

    # Validate existence of reference and GVCF directory
    check_files_exist([ref], logger, "Step1 missing reference file")
    if not Path(gvcfdir).is_dir():
        logger.error(f"GVCF directory does not exist: {gvcfdir}")
        return

    # Create output directory
    Path(out_dir).mkdir(parents=True, exist_ok=True)

    # Path to the shell script
    script_path = Path(__file__).parent.parent.parent / "scripts" / "genotypeGVCFs.sh"
    if not script_path.exists():
        logger.error(f"Script not found: {script_path}")
        return

    base_name = config.get('project', 'base_name')

    def run_chr(chr_name):
        """Run genotypeGVCFs.sh for a single chromosome."""
        cmd = [
            'bash', str(script_path),
            out_dir,
            ref,
            base_name,
            genomicsdb,
            gvcfdir,
            chr_name,
            workdir
        ]
        logger.debug(f"Starting chromosome {chr_name}")
        # Run and capture output; we'll log at the batch level
        return subprocess.run(cmd, capture_output=True, text=True)

    # Process chromosomes in batches
    total_chrs = len(chromosomes)
    for i in range(0, total_chrs, batch_size):
        batch = chromosomes[i:i+batch_size]
        logger.info(f"Processing batch {i//batch_size + 1}/{(total_chrs-1)//batch_size + 1}: {batch}")
        with concurrent.futures.ThreadPoolExecutor(max_workers=cfg.get('max_workers', batch_size)) as executor:
            futures = {executor.submit(run_chr, c): c for c in batch}
            for future in concurrent.futures.as_completed(futures):
                chr_name = futures[future]
                try:
                    result = future.result()
                    if result.returncode != 0:
                        logger.error(f"Chromosome {chr_name} failed with return code {result.returncode}")
                        logger.error(f"stderr: {result.stderr}")
                        raise RuntimeError(f"Step1 failed for chromosome {chr_name}")
                    else:
                        logger.info(f"Chromosome {chr_name} completed successfully")
                except Exception as e:
                    logger.error(f"Exception for chromosome {chr_name}: {e}")
                    raise

    logger.info("Step1 completed successfully")