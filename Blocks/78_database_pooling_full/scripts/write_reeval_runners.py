#!/usr/bin/env python3
from pathlib import Path

tpl = Path("/mnt/sda/cirrhosis_train/Blocks/78_database_pooling_full/scripts/_run_one_template.py").read_text()
up = "/mnt/sda/cirrhosis_train/Blocks/78_database_pooling_full/upstream/BlendedLoS"
root = Path("/mnt/sda/BlendedICU/data/cirrhosis_dzx_42151996/Output_database_pooling")
units = [
    "cirr_expA_nwicu_solo",
    "cirr_expB_mimic_solo",
    "cirr_expC_mimic2nwicu_transfer",
    "cirr_expD_pooled_mimic_nwicu",
]
for unit in units:
    cwd = root / unit
    text = (
        tpl.replace("__CWD__", str(cwd))
        .replace("__UPSTREAM__", up)
        .replace("__CONFIG__", str(cwd / "config.json"))
        .replace("__EXPERIMENTS__", repr(["main_experiment"]))
    )
    (cwd / "_run_reeval.py").write_text(text)
    print(unit, "experiments line ok", "['main_experiment']" in text)
