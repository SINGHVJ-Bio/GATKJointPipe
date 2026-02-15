import sys
from .steps import (
    step1_genotype,
    step2_merge,
    step3_remove_samples,
    step4_recalibrate,
    step5_annotate_rsids
)
from .utils import setup_logger
from .config import Config

class Orchestrator:
    """
    Loads configuration, determines which steps are enabled,
    and runs them in the correct order with dependency checks.
    """

    def __init__(self, config_path: str):
        self.config = Config(config_path)
        self.logger = setup_logger("GATKJointPipe")
        self.steps = [
            ("step1", step1_genotype.run, "run_step1"),
            ("step2", step2_merge.run, "run_step2"),
            ("step3", step3_remove_samples.run, "run_step3"),
            ("step4", step4_recalibrate.run, "run_step4"),
            ("step5", step5_annotate_rsids.run, "run_step5"),
        ]

    def run_selected_steps(self):
        """Run only the steps that are enabled in the config."""
        steps_enabled = [
            step for step in self.steps
            if self.config.get('steps', step[2], default=False)
        ]
        if not steps_enabled:
            self.logger.error("No steps are enabled in the configuration. Exiting.")
            sys.exit(1)

        for step_name, step_func, config_key in steps_enabled:
            self.logger.info(f"--- Starting step {step_name} ---")
            try:
                step_func(self.config, self.logger)
            except Exception as e:
                self.logger.error(f"Step {step_name} failed: {e}")
                sys.exit(1)
            self.logger.info(f"--- Completed step {step_name} ---")