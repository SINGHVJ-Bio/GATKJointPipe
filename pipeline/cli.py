#!/usr/bin/env python3
"""
Command-line interface for GATKJointPipe.
"""
import argparse
from .orchestrator import Orchestrator

def main():
    parser = argparse.ArgumentParser(
        description="GATKJointPipe: run selected steps of the joint calling pipeline"
    )
    parser.add_argument(
        '--config', '-c',
        required=True,
        help='Path to YAML configuration file'
    )
    args = parser.parse_args()

    orch = Orchestrator(args.config)
    orch.run_selected_steps()

if __name__ == '__main__':
    main()