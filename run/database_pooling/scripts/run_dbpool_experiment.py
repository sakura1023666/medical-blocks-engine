#!/usr/bin/env python3
"""Run one BlendedLoS experiment unit (wraps upstream CIC-1410/BlendedLoS).

Each unit gets an isolated work_dir (config.json / results / paths.json) so
parallel workers never clobber a shared upstream/config.json.
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

BLOCK78 = Path(__file__).resolve().parents[1]
ROOT = BLOCK78.parents[1]
UPSTREAM = BLOCK78 / "upstream" / "BlendedLoS"
if not UPSTREAM.exists():
    legacy = ROOT / "python" / "blended_los_upstream"
    if legacy.exists():
        UPSTREAM = legacy
    else:
        raise SystemExit(f"BlendedLoS upstream not found at {UPSTREAM}")

UNIT_CONFIG = {
    "expA_amumc_solo": {
        "experiments": {
            "main_experiment": {
                "models": ["tpc"],
                "runs": [{"train_on": ["amsterdam"], "percentage_trainval": 25}],
            }
        }
    },
    "expB_mimic_solo": {
        "experiments": {
            "main_experiment": {
                "models": ["tpc"],
                "runs": [{"train_on": ["mimic4"], "percentage_trainval": 75, "use_as_pretrained": True}],
            }
        }
    },
    "expC_mimic2amumc_transfer": {
        "experiments": {
            "main_experiment": {
                "models": ["tpc"],
                "runs": [
                    {"train_on": ["mimic4"], "percentage_trainval": 75, "use_as_pretrained": True},
                    {
                        "train_on": ["amsterdam"],
                        "percentage_trainval": 25,
                        "from_pretrained": True,
                        "retrain_last_layer_only": False,
                    },
                ],
            }
        }
    },
    "expD_pooled_mimic_amumc": {
        "experiments": {
            "main_experiment": {
                "models": ["tpc"],
                "runs": [
                    {
                        "percentage_trainval_dic": {"amsterdam": 25, "mimic4": 75},
                    }
                ],
            }
        }
    },
    "model_benchmark": {
        "experiments": {
            "model_benchmark": {
                "models": ["lstm", "transformer", "tpc"],
                "runs": [
                    {
                        # Allyn Table S2: one model, equal n per database, about 3,000 each.
                        # 56% of the train split. On a ~5,314-stay folder that is ~2,975.
                        # With stays_per_db set, the same 56% applies to the cap.
                        "train_on": ["amsterdam", "hirid", "mimic4", "eicu"],
                        "percentage_trainval": 56,
                    }
                ],
            }
        }
    },
    "dataset_benchmark": {
        "experiments": {
            "dataset_benchmark": {
                "models": ["tpc"],
                "runs": [
                    {"train_on": ["amsterdam"], "percentage_trainval": 100},
                    {"train_on": ["mimic4"], "percentage_trainval": 100},
                    {"train_on": ["eicu"], "percentage_trainval": 100},
                    {"train_on": ["hirid"], "percentage_trainval": 100},
                ],
            }
        }
    },
    "training_size_study": {
        "experiments": {
            "training_size_study": {
                "models": ["tpc"],
                "runs": [
                    {"train_on": ["mimic4"], "percentage_trainval": p}
                    for p in (10, 25, 50, 75, 100)
                ],
            }
        }
    },
    # Cirrhosis cohort: MIMIC-IV + NWICU train, eICU held out. Full train/val, not a 25/75 resample.
    "cirr_expA_nwicu_solo": {
        "config_overrides": {"datasets": ["mimic4", "eicu", "nwicu"]},
        "experiments": {
            "main_experiment": {
                "models": ["tpc"],
                "runs": [{"train_on": ["nwicu"], "percentage_trainval": 100}],
            }
        },
    },
    "cirr_expB_mimic_solo": {
        "config_overrides": {"datasets": ["mimic4", "eicu", "nwicu"]},
        "experiments": {
            "main_experiment": {
                "models": ["tpc"],
                "runs": [{"train_on": ["mimic4"], "percentage_trainval": 100, "use_as_pretrained": True}],
            }
        },
    },
    "cirr_expC_mimic2nwicu_transfer": {
        "config_overrides": {"datasets": ["mimic4", "eicu", "nwicu"]},
        "experiments": {
            "main_experiment": {
                "models": ["tpc"],
                "runs": [
                    {"train_on": ["mimic4"], "percentage_trainval": 100, "use_as_pretrained": True},
                    {
                        "train_on": ["nwicu"],
                        "percentage_trainval": 100,
                        "from_pretrained": True,
                        "retrain_last_layer_only": False,
                    },
                ],
            }
        },
    },
    "cirr_expD_pooled_mimic_nwicu": {
        "config_overrides": {"datasets": ["mimic4", "eicu", "nwicu"]},
        "experiments": {
            "main_experiment": {
                "models": ["tpc"],
                "runs": [
                    {"percentage_trainval_dic": {"mimic4": 100, "nwicu": 100}},
                ],
            }
        },
    },
    # Liver dysfunction (SOFA liver >=2 on first bilirubin). Amsterdam + MIMIC train;
    # eICU and HiRID are external test only. Full train/val, not a 25/75 resample.
    "liver_expA_amsterdam_solo": {
        "config_overrides": {"datasets": ["amsterdam", "mimic4", "eicu", "hirid"]},
        "experiments": {
            "main_experiment": {
                "models": ["tpc"],
                "runs": [{"train_on": ["amsterdam"], "percentage_trainval": 100}],
            }
        },
    },
    "liver_expB_mimic_solo": {
        "config_overrides": {"datasets": ["amsterdam", "mimic4", "eicu", "hirid"]},
        "experiments": {
            "main_experiment": {
                "models": ["tpc"],
                "runs": [{"train_on": ["mimic4"], "percentage_trainval": 100, "use_as_pretrained": True}],
            }
        },
    },
    "liver_expC_mimic2amsterdam_transfer": {
        "config_overrides": {"datasets": ["amsterdam", "mimic4", "eicu", "hirid"]},
        "experiments": {
            "main_experiment": {
                "models": ["tpc"],
                "runs": [
                    {"train_on": ["mimic4"], "percentage_trainval": 100, "use_as_pretrained": True},
                    {
                        "train_on": ["amsterdam"],
                        "percentage_trainval": 100,
                        "from_pretrained": True,
                        "retrain_last_layer_only": False,
                    },
                ],
            }
        },
    },
    "liver_expD_pooled_mimic_amsterdam": {
        "config_overrides": {"datasets": ["amsterdam", "mimic4", "eicu", "hirid"]},
        "experiments": {
            "main_experiment": {
                "models": ["tpc"],
                "runs": [
                    {"percentage_trainval_dic": {"mimic4": 100, "amsterdam": 100}},
                ],
            }
        },
    },
    # Architecture comparison on the same pooled Amsterdam+MIMIC train set as
    # the main pooling arm. eICU and HiRID stay external-only.
    "liver_model_benchmark": {
        "config_overrides": {"datasets": ["amsterdam", "mimic4", "eicu", "hirid"]},
        "experiments": {
            "model_benchmark": {
                "models": ["lstm", "transformer", "tpc"],
                "runs": [
                    {"percentage_trainval_dic": {"mimic4": 100, "amsterdam": 100}},
                ],
            }
        },
    },
    # Allyn Table S2 style: train on all four DBs with equal per-DB cap
    # (set DBPOOL_TRAIN_STAYS_PER_DB, default handled in finalize watcher).
    "liver_model_benchmark_equaln": {
        "config_overrides": {"datasets": ["amsterdam", "mimic4", "eicu", "hirid"]},
        "experiments": {
            "model_benchmark": {
                "models": ["lstm", "transformer", "tpc"],
                "runs": [
                    {
                        "train_on": ["amsterdam", "eicu", "hirid", "mimic4"],
                        "percentage_trainval": 100,
                    }
                ],
            }
        },
    },
    # Allyn Table 2 style: TPC trained on each database alone.
    "liver_dataset_benchmark": {
        "config_overrides": {"datasets": ["amsterdam", "mimic4", "eicu", "hirid"]},
        "experiments": {
            "dataset_benchmark": {
                "models": ["tpc"],
                "runs": [
                    {"train_on": ["amsterdam"], "percentage_trainval": 100},
                    {"train_on": ["mimic4"], "percentage_trainval": 100},
                    {"train_on": ["eicu"], "percentage_trainval": 100},
                    {"train_on": ["hirid"], "percentage_trainval": 100},
                ],
            }
        },
    },
    # Training-size sweep on MIMIC-IV (patient-level percentages of the train
    # folder). Matches Allyn Figure 2 / training_size_study, inside this cohort.
    # Denser grid than 10/25/50/75/100 so Fig.2 has discrete points across the
    # available MIMIC train N (paper used ~1k–55k; here max is cohort train size).
    "liver_training_size_study": {
        "config_overrides": {"datasets": ["amsterdam", "mimic4", "eicu", "hirid"]},
        "experiments": {
            "training_size_study": {
                "models": ["tpc"],
                "runs": [
                    {"train_on": ["mimic4"], "percentage_trainval": p}
                    for p in (5, 10, 15, 20, 25, 35, 50, 65, 75, 90, 100)
                ],
            }
        },
    },
}


def _base_config():
    """Literature defaults = BlendedLoS config.py (n_epochs=200, batch=32, alpha=20).

    Fast path only when DBPOOL_FAST_TRAIN=1 (or DBPOOL_FULL_EPOCHS=0).
    R wiring: config$dbpool$fast_train=FALSE → DBPOOL_FULL_EPOCHS=1.
    Early-stop patience in public Template is hardcoded to 5 (config key unused).
    """
    fast_env = os.environ.get("DBPOOL_FAST_TRAIN", "").strip().lower()
    full_env = os.environ.get("DBPOOL_FULL_EPOCHS", "").strip().lower()
    if fast_env in ("1", "true", "yes"):
        full = False
    elif full_env in ("0", "false", "no"):
        full = False
    elif full_env in ("1", "true", "yes"):
        full = True
    else:
        # default: literature-grade
        full = True
    n_epochs = 200 if full else 40
    ep_env = os.environ.get("DBPOOL_N_EPOCHS", "").strip()
    if ep_env:
        n_epochs = int(ep_env)
    # Paper / public Template default is 100. Config$dbpool$percentage_test overrides it.
    pct_test = 100
    pct_env = os.environ.get("DBPOOL_PERCENTAGE_TEST", "").strip()
    if pct_env:
        pct_test = int(pct_env)
    cfg = {
        "config": {
            "task": "multitask",
            "dataset": "blended",
            "use_flat": True,
            "use_med": True,
            "use_lab": True,
            "use_vitals": True,
            "use_resp": False,
            "percentage_test": pct_test,
            "alpha": 20,
            "n_epochs": n_epochs,
            "batch_size_train": 32 if full else 64,
            "batch_size_val": 32 if full else 64,
            "batch_size_test": 32 if full else 64,
            # mirrored for logs; Template still uses patience=5 (public code)
            "patience": 5,
        }
    }
    cap_b = os.environ.get("DBPOOL_MAX_N_BATCH", "").strip()
    if cap_b:
        cfg["config"]["max_n_batch"] = int(cap_b)
    return cfg


def _unit_train_on(unit: str) -> list:
    if unit not in UNIT_CONFIG:
        return ["amsterdam"]
    spec = UNIT_CONFIG[unit]["experiments"]
    run0 = next(iter(spec.values()))["runs"][0]
    train_on = run0.get("train_on")
    if not train_on:
        train_on = list(run0.get("percentage_trainval_dic") or {})
    return list(train_on)


def _split_marker(unit: str, blended_out: Path) -> Path:
    name = "train_on_" + "_".join(sorted(_unit_train_on(unit)))
    return Path(blended_out) / "extraction" / name / "train" / "labels.parquet"


def write_unit_config(unit: str, out_json: Path):
    cfg = _base_config()
    if unit == "generate_tables":
        out_json.write_text(json.dumps(cfg, indent=2), encoding="utf-8")
        return cfg
    if unit not in UNIT_CONFIG:
        raise SystemExit(f"Unknown unit: {unit}. Known: {sorted(UNIT_CONFIG)}")
    spec = UNIT_CONFIG[unit]
    overrides = spec.get("config_overrides") or {}
    cfg["config"].update(overrides)
    cfg["experiments"] = spec["experiments"]
    out_json.write_text(json.dumps(cfg, indent=2), encoding="utf-8")
    return cfg


def _prepare_isolated_cwd(work_dir: Path, blended_out: Path) -> Path:
    """Create an isolated BlendedLoS cwd for one unit (no shared config race)."""
    work_dir.mkdir(parents=True, exist_ok=True)
    paths = {"blendedICU": str(Path(blended_out).resolve()) + "/"}
    (work_dir / "paths.json").write_text(json.dumps(paths, indent=2), encoding="utf-8")
    # symlink read-only assets from upstream
    for name in ("ts_variables.csv", "models", "utils", "database"):
        src = UPSTREAM / name
        dst = work_dir / name
        if dst.exists() or dst.is_symlink():
            continue
        try:
            dst.symlink_to(src, target_is_directory=src.is_dir())
        except OSError:
            if src.is_dir():
                shutil.copytree(src, dst, dirs_exist_ok=True)
            else:
                shutil.copy2(src, dst)
    return work_dir


def run_unit(unit: str, blended_out: Path, work_dir: Path, dry_run: bool = False):
    cwd = _prepare_isolated_cwd(work_dir, blended_out)
    cfg_path = cwd / "config.json"
    write_unit_config(unit, cfg_path)

    meta = {"unit": unit, "blended_out": str(blended_out), "config": str(cfg_path), "cwd": str(cwd)}
    (cwd / "unit_meta.json").write_text(json.dumps(meta, indent=2), encoding="utf-8")

    # also keep upstream paths.json for any leftover absolute tools
    (UPSTREAM / "paths.json").write_text(
        json.dumps({"blendedICU": str(Path(blended_out).resolve()) + "/"}, indent=2),
        encoding="utf-8",
    )

    if dry_run:
        print(json.dumps({"dry_run": True, **meta}, indent=2))
        return 0

    # Guard: this unit's train_on split must exist (cirrhosis units are not Amsterdam).
    need = _split_marker(unit, Path(blended_out))
    if unit != "generate_tables" and not need.exists():
        raise SystemExit(
            f"Missing DataSplitter output: {need}. "
            "Re-run dbpool_split / 1_split_train_test.py before training."
        )

    env = os.environ.copy()
    env["PYTHONPATH"] = str(cwd) + os.pathsep + str(UPSTREAM) + os.pathsep + env.get("PYTHONPATH", "")

    runner = cwd / "_run_one.py"
    if unit == "generate_tables":
        script = UPSTREAM / "3_generate_table.py"
        runner.write_text(
            "import runpy\nrunpy.run_path(%r, run_name='__main__')\n" % script.as_posix(),
            encoding="utf-8",
        )
        exp_names = []
    else:
        exp_names = list((_base_config() | UNIT_CONFIG.get(unit, {})).get("experiments", {}).keys())
        tpl = (BLOCK78 / "scripts" / "_run_one_template.py").read_text(encoding="utf-8")
        runner.write_text(
            tpl.replace("__CWD__", str(cwd))
            .replace("__UPSTREAM__", str(UPSTREAM))
            .replace("__CONFIG__", str(cfg_path))
            .replace("__EXPERIMENTS__", repr(exp_names)),
            encoding="utf-8",
        )

    log = cwd / "train.log"
    with log.open("w", encoding="utf-8") as fh:
        proc = subprocess.run(
            [sys.executable, str(runner)],
            cwd=str(cwd),
            env=env,
            stdout=fh,
            stderr=subprocess.STDOUT,
        )
    print(f"unit={unit} exit={proc.returncode} log={log}")
    return proc.returncode


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--unit", default="")
    ap.add_argument("--blended-out", default="")
    ap.add_argument("--work-dir", default="")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--list-units", action="store_true")
    args = ap.parse_args()
    if args.list_units:
        print("\n".join(sorted(list(UNIT_CONFIG) + ["generate_tables"])))
        return
    if not args.unit or not args.blended_out or not args.work_dir:
        raise SystemExit("--unit / --blended-out / --work-dir are required (unless --list-units)")
    code = run_unit(args.unit, Path(args.blended_out), Path(args.work_dir), dry_run=args.dry_run)
    raise SystemExit(code)


if __name__ == "__main__":
    main()
