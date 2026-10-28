#!/usr/bin/env python3
"""Shim → Blocks/78_database_pooling_full/scripts/run_dbpool_experiment.py"""
from pathlib import Path
import runpy
import sys
target = Path(__file__).resolve().parents[2] / "Blocks/78_database_pooling_full/scripts/run_dbpool_experiment.py"
sys.argv[0] = str(target)
runpy.run_path(str(target), run_name="__main__")
