import subprocess
import sys
import logging
from pathlib import Path
from typing import List

def setup_logger(name: str, log_file: Path = None) -> logging.Logger:
    """
    Create a logger that writes to the console and optionally to a file.
    """
    logger = logging.getLogger(name)
    logger.setLevel(logging.INFO)
    formatter = logging.Formatter(
        '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )

    # Console handler
    ch = logging.StreamHandler(sys.stdout)
    ch.setFormatter(formatter)
    logger.addHandler(ch)

    # Optional file handler
    if log_file:
        fh = logging.FileHandler(log_file)
        fh.setFormatter(formatter)
        logger.addHandler(fh)

    return logger

def run_subprocess(cmd: List[str], logger: logging.Logger, step_name: str, check: bool = True):
    """
    Execute a command, log its output, and raise an exception on failure if requested.
    """
    logger.info(f"Running command: {' '.join(cmd)}")
    try:
        result = subprocess.run(
            cmd,
            check=check,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        if result.stdout:
            logger.info(f"{step_name} stdout:\n{result.stdout}")
        if result.stderr:
            logger.warning(f"{step_name} stderr:\n{result.stderr}")
        return result
    except subprocess.CalledProcessError as e:
        logger.error(f"Step {step_name} failed with exit code {e.returncode}")
        logger.error(f"stderr: {e.stderr}")
        raise

def check_files_exist(file_list: List[str], logger: logging.Logger, error_msg_prefix: str):
    """
    Verify that every file in the list exists. If any are missing, log an error and exit.
    """
    missing = [f for f in file_list if not Path(f).exists()]
    if missing:
        logger.error(f"{error_msg_prefix}: missing files: {missing}")
        sys.exit(1)
