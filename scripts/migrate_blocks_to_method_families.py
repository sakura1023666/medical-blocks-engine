#!/usr/bin/env python3
"""
Build 01Block/Blocks method-family layout from 01Block-new-Final (read-only source).
Does not modify the source tree.
"""
from __future__ import annotations

import os
import re
import shutil
from pathlib import Path

SRC = Path("/mnt/e/01block/01Block-new-Final")
DST = Path("/mnt/e/01block/01Block")
SRC_BLOCKS = SRC / "Blocks"
DST_BLOCKS = DST / "Blocks"
DST_RUN = DST / "run"


def ensure_dir(p: Path) -> None:
    p.mkdir(parents=True, exist_ok=True)


def copy_file(src: Path, dst: Path) -> None:
    ensure_dir(dst.parent)
    shutil.copy2(src, dst)


def copy_tree_files(src_dir: Path, dst_dir: Path, names: list[str] | None = None) -> list[str]:
    """Copy R (and listed) files; return list of relative paths copied."""
    copied = []
    if not src_dir.is_dir():
        return copied
    ensure_dir(dst_dir)
    if names is None:
        for root, dirs, files in os.walk(src_dir):
            # skip phases/pilots/upstream heavy trees when copying whole method dirs selectively
            dirs[:] = [d for d in dirs if d not in ("__pycache__", ".Rproj.user")]
            for f in files:
                if f.endswith((".pyc", ".RData", ".rds")):
                    continue
                sp = Path(root) / f
                rel = sp.relative_to(src_dir)
                dp = dst_dir / rel
                copy_file(sp, dp)
                copied.append(str(rel))
    else:
        for name in names:
            sp = src_dir / name
            if sp.is_file():
                copy_file(sp, dst_dir / name)
                copied.append(name)
    return copied


def copy_method_dir(name: str, dst_name: str | None = None) -> None:
    src_dir = SRC_BLOCKS / name
    dst_dir = DST_BLOCKS / (dst_name or name)
    if not src_dir.is_dir():
        print(f"  SKIP missing {name}")
        return
    if dst_dir.exists():
        shutil.rmtree(dst_dir)
    shutil.copytree(
        src_dir,
        dst_dir,
        ignore=shutil.ignore_patterns("__pycache__", "*.pyc", "*.RData", "*.rds"),
    )
    print(f"  OK {name} -> {dst_dir.name}")


# ---------------------------------------------------------------------------
# 1) Already method-family dirs (section 一), with renames
# ---------------------------------------------------------------------------
KEEP_AS_IS = [
    "00_attrition",
    "00_dual_db",
    "00_index",
    "01_column_mappings",
    "02_data_clean",
    "03_imputation",
    "04_baseline",
    "05_boxplot",
    "06_univariate",
    "07_multivariate",
    "08_vif",
    "09_correlation",
    "10_cox",
    "11_logistic",
    "12_obj",
    "13_roc",
    "14_cutoff",
    "15_rcs",
    "17_shap",
    "18_subgroup",
    "19_feature_selection",
    "20_mediation",
    "21_train_validation",
    "22_ml_models",
    "23_ml_performance",
    "25_shiny",
    "27_KM",
    "28_plot",
    "29_chord_diagram",
    "30_lca",
    "31_subtype_viz",
    "32_stepp",
    "34_IPTW",
    "43_dynamic_causal",
    "44_multimorbidity",
    "45_multimodal",
    "50_complex_network",
    "51_bayesian_comorbidity",
    "Figures_Blocks",
    "Tables_Blocks",
]

RENAMES = {
    "16_weightcox": "16_segmented_cox",
    "33_composite_risk_score": "33_composite_risk",
    "36_capability": "36_sensitivity",
}


def build_keep_and_renames() -> None:
    print("== keep / rename method dirs ==")
    for name in KEEP_AS_IS:
        copy_method_dir(name)
    for src_name, dst_name in RENAMES.items():
        copy_method_dir(src_name, dst_name)


# ---------------------------------------------------------------------------
# 2) 24_ml_dual + supplementary merge
# ---------------------------------------------------------------------------
def build_ml_dual() -> None:
    print("== 24_ml_dual merge ==")
    dst = DST_BLOCKS / "24_ml_dual"
    if dst.exists():
        shutil.rmtree(dst)
    copy_method_dir("24_ml_dual")
    # merge supplementary into same folder
    src_sup = SRC_BLOCKS / "24_ml_supplementary" / "01block_supplementary_ml.R"
    if src_sup.is_file():
        copy_file(src_sup, dst / "10block_supplementary_ml.R")
        print("  merged supplementary_ml -> 10block_supplementary_ml.R")


# ---------------------------------------------------------------------------
# 3) Trajectory family 26
# ---------------------------------------------------------------------------
TRAJ_COPIES = [
    # (src_rel_under Blocks, dst_filename under 26_trajectory)
    ("26_trajectory/01block_trajectory_gbmt.R", "01block_trajectory_gbmt.R"),
    ("26_trajectory/02block_trajectory_jlcm.R", "02block_trajectory_jlcm.R"),
    ("26_trajectory/03block_trajectory_plot_gbmt.R", "03block_trajectory_plot_gbmt.R"),
    ("26_trajectory/04block_trajectory_plot_jlcm.R", "04block_trajectory_plot_jlcm.R"),
    ("26_trajectory/05block_trajectory_chisq.R", "05block_trajectory_chisq.R"),
    ("26_trajectory/06block_trajectory_dynpred.R", "06block_trajectory_dynpred.R"),
    ("52_trajectory_incidence/00block_trajectory_creatinine_pct.R", "07block_trajectory_creatinine_pct.R"),
    ("52_trajectory_incidence/01block_trajectory_wide_to_long.R", "08block_trajectory_wide_to_long.R"),
    ("52_trajectory_incidence/02block_trajectory_lcmm_fit.R", "09block_trajectory_lcmm_fit.R"),
    ("52_trajectory_incidence/03block_trajectory_outcome_models.R", "10block_trajectory_outcome_models.R"),
    ("52_trajectory_incidence/04block_trajectory_prepare_wide_rdata.R", "11block_trajectory_prepare_wide_rdata.R"),
    ("52_trajectory_incidence/05block_trajectory_lcmm_mpcmp_plot.R", "12block_trajectory_lcmm_mpcmp_plot.R"),
    ("52_trajectory_incidence/06block_trajectory_lcmm_external_validate.R", "13block_trajectory_lcmm_external_validate.R"),
    ("52_trajectory_incidence/07block_trajectory_outcome_adjusted.R", "14block_trajectory_outcome_adjusted.R"),
    ("53_trajectory_prognosis_full/01block_trajectory_piecewise_cox.R", "15block_trajectory_piecewise_cox.R"),
    ("53_trajectory_prognosis_full/02block_trajectory_weibull_compare.R", "16block_trajectory_weibull_compare.R"),
    ("53_trajectory_prognosis_full/03block_trajectory_jlcm_discovery_validate.R", "17block_trajectory_jlcm_discovery_validate.R"),
    ("53_trajectory_prognosis_full/04block_trajectory_km_class.R", "18block_trajectory_km_class.R"),
    ("53_trajectory_prognosis_full/05block_trajectory_dynpred_individual.R", "19block_trajectory_dynpred_individual.R"),
    ("53_trajectory_prognosis_full/06block_trajectory_subgroup_class.R", "20block_trajectory_subgroup_class.R"),
    ("53_trajectory_prognosis_full/07block_trajectory_baseline_by_class.R", "21block_trajectory_baseline_by_class.R"),
    ("53_trajectory_prognosis_full/08block_trajectory_calc_28d_index.R", "22block_trajectory_calc_28d_index.R"),
    ("76_cum_egdr_kmeans_ckm_full/03block_kmeans_elbow_bivar.R", "23block_kmeans_elbow_bivar.R"),
    ("76_cum_egdr_kmeans_ckm_full/04block_kmeans_trajectory_panels.R", "24block_kmeans_trajectory_panels.R"),
    ("64_causal_forest_trajectory_full/03block_cftraj_lcmm_fit.R", "25block_cftraj_lcmm_fit.R"),
    ("64_causal_forest_trajectory_full/08block_cftraj_lcmm_episodic.R", "26block_cftraj_lcmm_episodic.R"),
    ("48_multimorbidity_full/01block_multimorbidity_kml3d_trajectory.R", "27block_trajectory_kml3d.R"),
    ("55_competing_risk_full/02block_competing_lmm_trajectory.R", "28block_trajectory_lmm.R"),
    ("55_competing_risk_full/20block_competing_trajectory_cluster.R", "29block_trajectory_cluster.R"),
]


def build_trajectory() -> None:
    print("== 26_trajectory ==")
    dst = DST_BLOCKS / "26_trajectory"
    if dst.exists():
        shutil.rmtree(dst)
    ensure_dir(dst)
    for src_rel, dst_name in TRAJ_COPIES:
        sp = SRC_BLOCKS / src_rel
        if not sp.is_file():
            print(f"  MISS {src_rel}")
            continue
        copy_file(sp, dst / dst_name)
        print(f"  + {dst_name}")


# ---------------------------------------------------------------------------
# 4) Environment family merge -> 35_environment
# ---------------------------------------------------------------------------
ENV_SOURCES = [
    "35_environment_function",
    "36_environment_glm",
    "37_environment_wqs",
    "38_environment_bkmr",
    "39_environment_qgcomp",
    "40_environment_descriptive",
    "41_environment_target",
    "42_environment_single",
    "46_environment_omics",
]


def build_environment() -> None:
    print("== 35_environment (merged) ==")
    dst = DST_BLOCKS / "35_environment"
    if dst.exists():
        shutil.rmtree(dst)
    ensure_dir(dst)
    seq = 0
    for folder in ENV_SOURCES:
        src_dir = SRC_BLOCKS / folder
        if not src_dir.is_dir():
            print(f"  MISS {folder}")
            continue
        sub = dst / folder.split("_", 1)[-1] if folder.startswith("3") or folder.startswith("4") else dst / folder
        # flatter: put all R files with prefix from original folder short tag
        tag = folder  # keep readable subdirs by original short purpose
        subdir = dst / tag.replace("35_", "").replace("36_", "").replace("37_", "").replace("38_", "").replace("39_", "").replace("40_", "").replace("41_", "").replace("42_", "").replace("46_", "")
        # Actually use clear subdirs:
        mapping = {
            "35_environment_function": "prep",
            "36_environment_glm": "glm",
            "37_environment_wqs": "wqs",
            "38_environment_bkmr": "bkmr",
            "39_environment_qgcomp": "qgcomp",
            "40_environment_descriptive": "descriptive",
            "41_environment_target": "target",
            "42_environment_single": "single",
            "46_environment_omics": "omics",
        }
        subdir = dst / mapping[folder]
        copy_tree_files(src_dir, subdir)
        print(f"  + {folder} -> 35_environment/{mapping[folder]}/")


# ---------------------------------------------------------------------------
# 5) Expand method families from full packs (algorithms only)
# ---------------------------------------------------------------------------
def merge_into(dst_name: str, src_folder: str, files: list[str] | None = None, exclude_names: set[str] | None = None) -> None:
    dst = DST_BLOCKS / dst_name
    ensure_dir(dst)
    src_dir = SRC_BLOCKS / src_folder
    if not src_dir.is_dir():
        print(f"  MISS {src_folder}")
        return
    exclude_names = exclude_names or set()
    if files:
        for f in files:
            if f in exclude_names:
                continue
            sp = src_dir / f
            if sp.is_file():
                copy_file(sp, dst / f)
                print(f"  + {dst_name}/{f} <- {src_folder}")
    else:
        for sp in sorted(src_dir.glob("*.R")):
            if sp.name in exclude_names:
                continue
            # skip literature_validate / pub_finalize / flowchart shells at copy? plan says keep algorithms, shells to run
            copy_file(sp, dst / sp.name)
            print(f"  + {dst_name}/{sp.name} <- {src_folder}")


SHELL_NAME_RE = re.compile(
    r"(literature_validate|pub_finalize|pub_export|pub_deliverables|flowchart|data_ingest|study_phases|midterm)",
    re.I,
)


def is_shell_filename(name: str) -> bool:
    return bool(SHELL_NAME_RE.search(name))


def build_expanded_families() -> None:
    print("== expand families from full packs ==")

    # 43 dynamic_causal + 47
    merge_into(
        "43_dynamic_causal",
        "47_dynamic_causal_full",
        files=[
            "01block_dynamic_causal_analysis_filter.R",
            "02block_dynamic_causal_cox_baseline.R",
            "03block_dynamic_causal_meta_merge.R",
            "04block_dynamic_causal_rcs_change.R",
        ],
    )

    # 44 multimorbidity + 48 (kml3d already in trajectory)
    merge_into(
        "44_multimorbidity",
        "48_multimorbidity_full",
        files=[
            "02block_multimorbidity_gee_stratified.R",
            "03block_multimorbidity_gee_interaction.R",
            "04block_multimorbidity_sensitivity_suite.R",
        ],
    )

    # 45 multimodal + 49
    merge_into(
        "45_multimodal",
        "49_multimodal_full",
        files=[
            "01block_multimodal_omics_preprocess.R",
            "02block_multimodal_dl_shap.R",
        ],
    )

    # 54 cross_lagged — algorithm R only, no phases/pilots
    print("  -- 54_cross_lagged --")
    dst = DST_BLOCKS / "54_cross_lagged"
    if dst.exists():
        shutil.rmtree(dst)
    ensure_dir(dst)
    src = SRC_BLOCKS / "54_cross_lagged_full"
    for sp in sorted(src.glob("*.R")):
        if is_shell_filename(sp.name) or sp.name.startswith("21block"):
            continue
        copy_file(sp, dst / sp.name)
        print(f"  + 54_cross_lagged/{sp.name}")

    # 55 competing_risk — algorithms; shells later to run
    print("  -- 55_competing_risk --")
    dst = DST_BLOCKS / "55_competing_risk"
    if dst.exists():
        shutil.rmtree(dst)
    ensure_dir(dst)
    src = SRC_BLOCKS / "55_competing_risk_full"
    for sp in sorted(src.glob("*.R")):
        # lmm/cluster already also copied into trajectory; keep in competing_risk too as method variants of Fine-Gray suite
        # exclude pure pub shells
        if sp.name in (
            "17block_competing_flowchart.R",
            "18block_competing_pub_export.R",
            "19block_competing_supp_tables.R",
        ):
            continue
        # skip trajectory ones that live in 26 (avoid dup register paths — pipeline will point to 26 for those)
        if sp.name in (
            "02block_competing_lmm_trajectory.R",
            "20block_competing_trajectory_cluster.R",
        ):
            continue
        copy_file(sp, dst / sp.name)
        print(f"  + 55_competing_risk/{sp.name}")

    # 56 ai_clinical_eval
    copy_method_dir("56_ai_clinical_full", "56_ai_clinical_eval")

    # 57 -> split conceptually into mr + crm folders
    print("  -- 57_mr / 57_crm --")
    for d in ("57_mr", "57_crm"):
        p = DST_BLOCKS / d
        if p.exists():
            shutil.rmtree(p)
        ensure_dir(p)
    src = SRC_BLOCKS / "57_dual_incidence_mr_full"
    for sp in sorted(src.glob("*.R")):
        if sp.name.startswith(("04", "05", "06", "07", "08")):
            copy_file(sp, DST_BLOCKS / "57_mr" / sp.name)
        else:
            copy_file(sp, DST_BLOCKS / "57_crm" / sp.name)
        print(f"  + split {sp.name}")

    # 58 medication — keep reusable; shells with literature_targets to run
    print("  -- 58_medication_regimen --")
    dst = DST_BLOCKS / "58_medication_regimen"
    if dst.exists():
        shutil.rmtree(dst)
    ensure_dir(dst)
    src = SRC_BLOCKS / "58_medication_regimen_full"
    for sp in sorted(src.glob("*.R")):
        if is_shell_filename(sp.name):
            continue
        copy_file(sp, dst / sp.name)

    # 59 markov
    print("  -- 59_markov --")
    dst = DST_BLOCKS / "59_markov"
    if dst.exists():
        shutil.rmtree(dst)
    ensure_dir(dst)
    src = SRC_BLOCKS / "59_markov_cognitive_full"
    for sp in sorted(src.glob("*.R")):
        if is_shell_filename(sp.name):
            continue
        copy_file(sp, dst / sp.name)

    # 60 cits
    print("  -- 60_cits --")
    dst = DST_BLOCKS / "60_cits"
    if dst.exists():
        shutil.rmtree(dst)
    ensure_dir(dst)
    src = SRC_BLOCKS / "60_cdc_wonder_cits_full"
    for sp in sorted(src.glob("*.R")):
        if "publication_tables" in sp.name:
            continue
        copy_file(sp, dst / sp.name)

    # 61 network_temperature
    print("  -- 61_network_temperature --")
    dst = DST_BLOCKS / "61_network_temperature"
    if dst.exists():
        shutil.rmtree(dst)
    ensure_dir(dst)
    src = SRC_BLOCKS / "61_network_temperature_full"
    for sp in sorted(src.glob("*.R")):
        if is_shell_filename(sp.name):
            continue
        copy_file(sp, dst / sp.name)

    # 62 sem
    print("  -- 62_sem --")
    dst = DST_BLOCKS / "62_sem"
    if dst.exists():
        shutil.rmtree(dst)
    ensure_dir(dst)
    src = SRC_BLOCKS / "62_sem_chain_mediation_full"
    for sp in sorted(src.glob("*.R")):
        if is_shell_filename(sp.name):
            continue
        copy_file(sp, dst / sp.name)

    # 63 ai_medical_qa
    copy_method_dir("63_ai_medical_qa_full", "63_ai_medical_qa")

    # 64 causal_forest (non-lcmm)
    print("  -- 64_causal_forest --")
    dst = DST_BLOCKS / "64_causal_forest"
    if dst.exists():
        shutil.rmtree(dst)
    ensure_dir(dst)
    src = SRC_BLOCKS / "64_causal_forest_trajectory_full"
    for sp in sorted(src.glob("*.R")):
        if "lcmm" in sp.name:
            continue
        if is_shell_filename(sp.name) or "validate" in sp.name:
            continue
        copy_file(sp, dst / sp.name)

    # 65 prepost_lmm
    print("  -- 65_prepost_lmm --")
    dst = DST_BLOCKS / "65_prepost_lmm"
    if dst.exists():
        shutil.rmtree(dst)
    ensure_dir(dst)
    src = SRC_BLOCKS / "65_incidence_prepost_full"
    for sp in sorted(src.glob("*.R")):
        if is_shell_filename(sp.name):
            continue
        copy_file(sp, dst / sp.name)

    # 66 target_trial
    print("  -- 66_target_trial --")
    dst = DST_BLOCKS / "66_target_trial"
    if dst.exists():
        shutil.rmtree(dst)
    ensure_dir(dst)
    src = SRC_BLOCKS / "66_target_trial_full"
    for sp in sorted(src.glob("*.R")):
        if is_shell_filename(sp.name):
            continue
        copy_file(sp, dst / sp.name)

    # 67 transformer_shortseq + reusable from 71
    print("  -- 67_transformer --")
    dst = DST_BLOCKS / "67_transformer"
    if dst.exists():
        shutil.rmtree(dst)
    ensure_dir(dst)
    src = SRC_BLOCKS / "67_transformer_shortseq_full"
    for sp in sorted(src.glob("*.R")):
        if is_shell_filename(sp.name):
            continue
        copy_file(sp, dst / sp.name)
    src71 = SRC_BLOCKS / "71_two_stage_transformer_stroke"
    for sp in sorted(src71.glob("0*.R")):
        # keep reusable train/calib/landmark/shap; skip pub/literature/cohort-specific later via shells
        if any(x in sp.name for x in ("literature", "pub_export", "summary_results", "cohort")):
            continue
        copy_file(sp, dst / f"tst_{sp.name}")

    # 68 dual_change_score
    print("  -- 68_dual_change_score --")
    dst = DST_BLOCKS / "68_dual_change_score"
    if dst.exists():
        shutil.rmtree(dst)
    ensure_dir(dst)
    src = SRC_BLOCKS / "68_dual_change_score_full"
    for sp in sorted(src.glob("*.R")):
        if is_shell_filename(sp.name):
            continue
        copy_file(sp, dst / sp.name)

    # 34 IPTW expand from 69
    print("  -- 34_IPTW expand from 69 --")
    src = SRC_BLOCKS / "69_ipw_diabetes_stroke_full"
    dst = DST_BLOCKS / "34_IPTW"
    for sp in sorted(src.glob("*.R")):
        if any(x in sp.name for x in ("flowchart", "literature", "pub_export", "jin_composite")):
            continue
        # exposure builders are study-ish but reusable IPW patterns — keep overlap/weights/km/calib
        if any(x in sp.name for x in ("overlap_weights", "weighted_km", "surv_calibration", "subgroup_km")):
            copy_file(sp, dst / sp.name)
            print(f"  + 34_IPTW/{sp.name}")

    # 57_crm expand from 70 (algorithmic)
    print("  -- 57_crm from 70 --")
    src = SRC_BLOCKS / "70_crm_nhanes_pub"
    dst = DST_BLOCKS / "57_crm"
    for sp in sorted(src.glob("*.R")):
        if any(x in sp.name for x in ("flowchart", "pub_deliverables", "pub_align", "literature", "table_builders")):
            continue
        copy_file(sp, dst / sp.name)
        print(f"  + 57_crm/{sp.name}")

    # 72 two_stage_cohort
    print("  -- 72_two_stage_cohort --")
    dst = DST_BLOCKS / "72_two_stage_cohort"
    if dst.exists():
        shutil.rmtree(dst)
    ensure_dir(dst)
    src = SRC_BLOCKS / "72_incidence_prognosis_two_stage"
    for sp in sorted(src.glob("*.R")):
        copy_file(sp, dst / sp.name)

    # 22/24 from 73 — copy nested cv etc as ml variants sidecar folder
    print("  -- 22_ml_models nafld variants --")
    dst = DST_BLOCKS / "22_ml_models"
    src = SRC_BLOCKS / "73_ml_nafld_cm"
    for sp in sorted(src.glob("*.R")):
        if any(x in sp.name for x in ("pub_finalize", "pub_polish", "external_bridge", "geo48452", "scheme_complements", "omics_display", "mr")):
            continue
        if sp.name.startswith("00"):
            copy_file(sp, dst / sp.name)
        elif "nested_cv" in sp.name or "feature_spaces" in sp.name or "score_compare" in sp.name:
            copy_file(sp, dst / sp.name)
            print(f"  + 22_ml_models/{sp.name}")

    # 75 dxa_qct
    copy_method_dir("75_osteo_dxa_qct", "75_dxa_qct")

    # 00_cumulative_exposure from 76
    print("  -- 00_cumulative_exposure --")
    dst = DST_BLOCKS / "00_cumulative_exposure"
    if dst.exists():
        shutil.rmtree(dst)
    ensure_dir(dst)
    sp = SRC_BLOCKS / "76_cum_egdr_kmeans_ckm_full" / "02block_cum_exposure_build.R"
    if sp.is_file():
        copy_file(sp, dst / "01block_cum_exposure_build.R")

    # 50 network + 81 symptom
    print("  -- 50_complex_network + symptom --")
    dst = DST_BLOCKS / "50_complex_network"
    src = SRC_BLOCKS / "81_clhls_symptom_network_full"
    for sp in sorted(src.glob("*.R")):
        if is_shell_filename(sp.name) or "ingest" in sp.name:
            continue
        copy_file(sp, dst / sp.name)
        print(f"  + 50_complex_network/{sp.name}")

    # 57_mr + easymr
    print("  -- 57_mr + easymr --")
    dst = DST_BLOCKS / "57_mr"
    src = SRC_BLOCKS / "80_easymr_full"
    for sp in sorted(src.glob("*.R")):
        copy_file(sp, dst / sp.name)
        print(f"  + 57_mr/{sp.name}")

    # 74: LMM pieces into a method folder pa_mobility (reusable LMM)
    print("  -- 74_pa_lmm --")
    dst = DST_BLOCKS / "74_pa_lmm"
    if dst.exists():
        shutil.rmtree(dst)
    ensure_dir(dst)
    src = SRC_BLOCKS / "74_pa_mobility_cognitive_full"
    for sp in sorted(src.glob("*.R")):
        if any(x in sp.name for x in ("assemble", "flowchart", "concept_fig", "pub_export", "contextual", "feasibility")):
            continue
        if sp.name.startswith("00"):
            copy_file(sp, dst / sp.name)
            continue
        copy_file(sp, dst / sp.name)


# ---------------------------------------------------------------------------
# 6) Study shells -> run/<study>/blocks_shell/
# ---------------------------------------------------------------------------
SHELL_MAP = {
    "47_dynamic_causal_full": "dynamic_causal",
    "48_multimorbidity_full": "multimorbidity",
    "49_multimodal_full": "multimodal",
    "52_trajectory_incidence": "trajectory_incidence",
    "53_trajectory_prognosis_full": "trajectory_prognosis",
    "54_cross_lagged_full": "cross_lagged",
    "55_competing_risk_full": "competing_risk",
    "56_ai_clinical_full": "ai_clinical",
    "57_dual_incidence_mr_full": "dual_incidence_mr",
    "58_medication_regimen_full": "medication_regimen",
    "59_markov_cognitive_full": "markov_cognitive",
    "60_cdc_wonder_cits_full": "cdc_wonder",
    "61_network_temperature_full": "network_temperature",
    "62_sem_chain_mediation_full": "sem_chain_mediation",
    "63_ai_medical_qa_full": "ai_medical_qa",
    "64_causal_forest_trajectory_full": "causal_forest_trajectory",
    "65_incidence_prepost_full": "incidence_prepost",
    "66_target_trial_full": "target_trial",
    "67_transformer_shortseq_full": "transformer_shortseq",
    "68_dual_change_score_full": "dual_change_score",
    "69_ipw_diabetes_stroke_full": "ipw_diabetes_stroke",
    "70_crm_nhanes_pub": "crm_nhanes_mr",
    "71_two_stage_transformer_stroke": "two_stage_transformer_stroke",
    "72_incidence_prognosis_two_stage": "sle_aki_inc_prog",
    "73_ml_nafld_cm": "ml",
    "74_pa_mobility_cognitive_full": "pa_mobility_cognitive",
    "76_cum_egdr_kmeans_ckm_full": "cum_egdr_kmeans_ckm",
    "77_gallstone_nomogram_full": "gallstone_nomogram",
    "78_database_pooling_full": "database_pooling",
    "79_sleep_dyslipid_prognosis_full": "prognosis_v2",
    "80_easymr_full": "dual_incidence_mr",
    "81_clhls_symptom_network_full": "clhls_symptom_network",
}


def copy_shells_to_run() -> None:
    print("== study shells -> run/*/blocks_shell ==")
    for src_folder, study in SHELL_MAP.items():
        src_dir = SRC_BLOCKS / src_folder
        if not src_dir.is_dir():
            continue
        dst_dir = DST_RUN / study / "blocks_shell"
        ensure_dir(dst_dir)
        # copy phases/pilots for cross_lagged
        if src_folder == "54_cross_lagged_full":
            for sub in ("phases", "pilots"):
                sp = src_dir / sub
                if sp.is_dir():
                    target = dst_dir / sub
                    if target.exists():
                        shutil.rmtree(target)
                    shutil.copytree(
                        sp,
                        target,
                        ignore=shutil.ignore_patterns("__pycache__", "*.pyc", "*.RData"),
                    )
                    print(f"  + run/{study}/blocks_shell/{sub}/")
            # also copy study_phases R and any shell-named
            for sp in src_dir.glob("*.R"):
                if is_shell_filename(sp.name) or sp.name.startswith("21block"):
                    copy_file(sp, dst_dir / sp.name)
                    print(f"  + run/{study}/blocks_shell/{sp.name}")
            continue

        # generic: copy files matching shell patterns OR entire leftover study-only scripts
        # For trajectory incidence/prognosis: no leftover algorithm in Blocks — copy README only if any; shells empty?
        # Plan: ingest/flowchart/pub_finalize/literature_validate go to run
        for sp in sorted(src_dir.glob("*.R")):
            if is_shell_filename(sp.name) or "ingest" in sp.name or "attrition" in sp.name:
                copy_file(sp, dst_dir / sp.name)
                print(f"  + run/{study}/blocks_shell/{sp.name}")
        # 76 extras
        if src_folder == "76_cum_egdr_kmeans_ckm_full":
            for name in (
                "00block_ckm_attrition_flowchart.R",
                "01block_ckm_stroke_data_ingest.R",
                "04b_block_table1_by_class_ckm.R",
                "05block_logistic_cum_index_bundle.R",
                "06block_rcs_ckm_strata_panels.R",
                "07block_sensitivity_cox_mice_bundle.R",
                "08block_table3_class_subgroup_forests.R",
                "09block_ckm_pub_finalize.R",
                "README.md",
            ):
                sp = src_dir / name
                if sp.is_file():
                    copy_file(sp, dst_dir / name)
        # 77 all as shells (algorithms already covered by generic families)
        if src_folder == "77_gallstone_nomogram_full":
            for sp in sorted(src_dir.glob("*")):
                if sp.is_file():
                    copy_file(sp, dst_dir / sp.name)
        # 78: copy R blocks as shells; upstream stays out or copy pointer
        if src_folder == "78_database_pooling_full":
            for sp in sorted(src_dir.glob("*.R")):
                copy_file(sp, dst_dir / sp.name)
            readme = src_dir / "README.md"
            if readme.is_file():
                copy_file(readme, dst_dir / "README.md")


# ---------------------------------------------------------------------------
# 7) Rewrite pipeline_runner.R paths in DST
# ---------------------------------------------------------------------------
PATH_REPLACEMENTS = [
    # renames
    ("16_weightcox/", "16_segmented_cox/"),
    ("33_composite_risk_score/", "33_composite_risk/"),
    ("36_capability/", "36_sensitivity/"),
    ("75_osteo_dxa_qct/", "75_dxa_qct/"),
    # trajectory consolidation
    ("52_trajectory_incidence/00block_trajectory_creatinine_pct.R", "26_trajectory/07block_trajectory_creatinine_pct.R"),
    ("52_trajectory_incidence/01block_trajectory_wide_to_long.R", "26_trajectory/08block_trajectory_wide_to_long.R"),
    ("52_trajectory_incidence/02block_trajectory_lcmm_fit.R", "26_trajectory/09block_trajectory_lcmm_fit.R"),
    ("52_trajectory_incidence/03block_trajectory_outcome_models.R", "26_trajectory/10block_trajectory_outcome_models.R"),
    ("52_trajectory_incidence/04block_trajectory_prepare_wide_rdata.R", "26_trajectory/11block_trajectory_prepare_wide_rdata.R"),
    ("52_trajectory_incidence/05block_trajectory_lcmm_mpcmp_plot.R", "26_trajectory/12block_trajectory_lcmm_mpcmp_plot.R"),
    ("52_trajectory_incidence/06block_trajectory_lcmm_external_validate.R", "26_trajectory/13block_trajectory_lcmm_external_validate.R"),
    ("52_trajectory_incidence/07block_trajectory_outcome_adjusted.R", "26_trajectory/14block_trajectory_outcome_adjusted.R"),
    ("53_trajectory_prognosis_full/01block_trajectory_piecewise_cox.R", "26_trajectory/15block_trajectory_piecewise_cox.R"),
    ("53_trajectory_prognosis_full/02block_trajectory_weibull_compare.R", "26_trajectory/16block_trajectory_weibull_compare.R"),
    ("53_trajectory_prognosis_full/03block_trajectory_jlcm_discovery_validate.R", "26_trajectory/17block_trajectory_jlcm_discovery_validate.R"),
    ("53_trajectory_prognosis_full/04block_trajectory_km_class.R", "26_trajectory/18block_trajectory_km_class.R"),
    ("53_trajectory_prognosis_full/05block_trajectory_dynpred_individual.R", "26_trajectory/19block_trajectory_dynpred_individual.R"),
    ("53_trajectory_prognosis_full/06block_trajectory_subgroup_class.R", "26_trajectory/20block_trajectory_subgroup_class.R"),
    ("53_trajectory_prognosis_full/07block_trajectory_baseline_by_class.R", "26_trajectory/21block_trajectory_baseline_by_class.R"),
    ("53_trajectory_prognosis_full/08block_trajectory_calc_28d_index.R", "26_trajectory/22block_trajectory_calc_28d_index.R"),
    ("76_cum_egdr_kmeans_ckm_full/03block_kmeans_elbow_bivar.R", "26_trajectory/23block_kmeans_elbow_bivar.R"),
    ("76_cum_egdr_kmeans_ckm_full/04block_kmeans_trajectory_panels.R", "26_trajectory/24block_kmeans_trajectory_panels.R"),
    ("64_causal_forest_trajectory_full/03block_cftraj_lcmm_fit.R", "26_trajectory/25block_cftraj_lcmm_fit.R"),
    ("64_causal_forest_trajectory_full/08block_cftraj_lcmm_episodic.R", "26_trajectory/26block_cftraj_lcmm_episodic.R"),
    ("48_multimorbidity_full/01block_multimorbidity_kml3d_trajectory.R", "26_trajectory/27block_trajectory_kml3d.R"),
    ("55_competing_risk_full/02block_competing_lmm_trajectory.R", "26_trajectory/28block_trajectory_lmm.R"),
    ("55_competing_risk_full/20block_competing_trajectory_cluster.R", "26_trajectory/29block_trajectory_cluster.R"),
    # ck m shells stay referenced via run — but pipeline still needs paths; point remaining 76 to run shells
    ("76_cum_egdr_kmeans_ckm_full/00block_ckm_attrition_flowchart.R", "RUN_SHELL:cum_egdr_kmeans_ckm/00block_ckm_attrition_flowchart.R"),
    ("76_cum_egdr_kmeans_ckm_full/01block_ckm_stroke_data_ingest.R", "RUN_SHELL:cum_egdr_kmeans_ckm/01block_ckm_stroke_data_ingest.R"),
    ("76_cum_egdr_kmeans_ckm_full/02block_cum_exposure_build.R", "00_cumulative_exposure/01block_cum_exposure_build.R"),
    ("76_cum_egdr_kmeans_ckm_full/04b_block_table1_by_class_ckm.R", "RUN_SHELL:cum_egdr_kmeans_ckm/04b_block_table1_by_class_ckm.R"),
    ("76_cum_egdr_kmeans_ckm_full/05block_logistic_cum_index_bundle.R", "RUN_SHELL:cum_egdr_kmeans_ckm/05block_logistic_cum_index_bundle.R"),
    ("76_cum_egdr_kmeans_ckm_full/06block_rcs_ckm_strata_panels.R", "RUN_SHELL:cum_egdr_kmeans_ckm/06block_rcs_ckm_strata_panels.R"),
    ("76_cum_egdr_kmeans_ckm_full/07block_sensitivity_cox_mice_bundle.R", "RUN_SHELL:cum_egdr_kmeans_ckm/07block_sensitivity_cox_mice_bundle.R"),
    ("76_cum_egdr_kmeans_ckm_full/08block_table3_class_subgroup_forests.R", "RUN_SHELL:cum_egdr_kmeans_ckm/08block_table3_class_subgroup_forests.R"),
    ("76_cum_egdr_kmeans_ckm_full/09block_ckm_pub_finalize.R", "RUN_SHELL:cum_egdr_kmeans_ckm/09block_ckm_pub_finalize.R"),
    # environment merge — map old folders to 35_environment/sub
    ("35_environment_function/", "35_environment/prep/"),
    ("36_environment_glm/", "35_environment/glm/"),
    ("37_environment_wqs/", "35_environment/wqs/"),
    ("38_environment_bkmr/", "35_environment/bkmr/"),
    ("39_environment_qgcomp/", "35_environment/qgcomp/"),
    ("40_environment_descriptive/", "35_environment/descriptive/"),
    ("41_environment_target/", "35_environment/target/"),
    ("42_environment_single/", "35_environment/single/"),
    ("46_environment_omics/", "35_environment/omics/"),
    # full -> method family renames
    ("47_dynamic_causal_full/", "43_dynamic_causal/"),
    ("48_multimorbidity_full/", "44_multimorbidity/"),
    ("49_multimodal_full/", "45_multimodal/"),
    ("54_cross_lagged_full/", "54_cross_lagged/"),
    ("55_competing_risk_full/", "55_competing_risk/"),
    ("56_ai_clinical_full/", "56_ai_clinical_eval/"),
    ("59_markov_cognitive_full/", "59_markov/"),
    ("60_cdc_wonder_cits_full/", "60_cits/"),
    ("61_network_temperature_full/", "61_network_temperature/"),
    ("62_sem_chain_mediation_full/", "62_sem/"),
    ("63_ai_medical_qa_full/", "63_ai_medical_qa/"),
    ("64_causal_forest_trajectory_full/", "64_causal_forest/"),
    ("65_incidence_prepost_full/", "65_prepost_lmm/"),
    ("66_target_trial_full/", "66_target_trial/"),
    ("67_transformer_shortseq_full/", "67_transformer/"),
    ("68_dual_change_score_full/", "68_dual_change_score/"),
    ("72_incidence_prognosis_two_stage/", "72_two_stage_cohort/"),
    ("74_pa_mobility_cognitive_full/", "74_pa_lmm/"),
    ("80_easymr_full/", "57_mr/"),
    ("81_clhls_symptom_network_full/", "50_complex_network/"),
    ("24_ml_supplementary/", "24_ml_dual/"),
]


def patch_pipeline_runner() -> None:
    print("== patch pipeline_runner.R ==")
    path = DST / "R" / "pipeline_runner.R"
    text = path.read_text(encoding="utf-8")
    # supplementary filename rename
    text = text.replace(
        "24_ml_dual/01block_supplementary_ml.R",
        "24_ml_dual/10block_supplementary_ml.R",
    )
    text = text.replace(
        'b("24_ml_supplementary/01block_supplementary_ml.R")',
        'b("24_ml_dual/10block_supplementary_ml.R")',
    )

    # RUN_SHELL: study/file -> file.path(root, "run", study, "blocks_shell", file)
    # First apply RUN_SHELL markers after replacements
    for old, new in PATH_REPLACEMENTS:
        if new.startswith("RUN_SHELL:"):
            continue
        if old in text:
            text = text.replace(old, new)
            print(f"  replace {old} -> {new}")

    # Handle RUN_SHELL entries specially in the list(...) body
    # Pattern: = b("RUN_SHELL:study/file.R")
    # We'll replace original paths that map to RUN_SHELL
    for old, new in PATH_REPLACEMENTS:
        if not new.startswith("RUN_SHELL:"):
            continue
        rel = new.split(":", 1)[1]  # study/file
        study, fname = rel.split("/", 1)
        # old still in file if not replaced
        if old not in text:
            # maybe already partially replaced
            continue
        replacement = (
            f'file.path(root, "run", "{study}", "blocks_shell", "{fname}")'
        )
        # replace b("76_.../file.R") with file.path(...)
        old_b = f'b("{old}")'
        if old_b in text:
            text = text.replace(old_b, replacement)
            print(f"  shell {old} -> run/{study}/blocks_shell/{fname}")
        else:
            text = text.replace(old, f"__SHELL__{study}/{fname}")
            print(f"  mark shell {old}")

    # fix any __SHELL__ leftovers inside b("...")
    def shell_sub(m: re.Match) -> str:
        inner = m.group(1)
        study, fname = inner.split("/", 1)
        return f'file.path(root, "run", "{study}", "blocks_shell", "{fname}")'

    text2 = re.sub(r'b\("__SHELL__([^"]+)"\)', shell_sub, text)
    text = text2

    # MR/CRM split: dual_incidence paths for mr_* files
    # After 57_dual -> need careful: we replaced folder with 43 etc already for other packs.
    # Fix 57_dual_incidence_mr_full references:
    text = text.replace("57_dual_incidence_mr_full/04", "57_mr/04")
    text = text.replace("57_dual_incidence_mr_full/05", "57_mr/05")
    text = text.replace("57_dual_incidence_mr_full/06", "57_mr/06")
    text = text.replace("57_dual_incidence_mr_full/07", "57_mr/07")
    text = text.replace("57_dual_incidence_mr_full/08", "57_mr/08")
    text = text.replace("57_dual_incidence_mr_full/", "57_crm/")

    # 70 crm nhanes: algorithms in 57_crm; shells in run
    for shell_pat, study_file in [
        ("70_crm_nhanes_pub/02block_crm_nhanes_flowchart.R", ("crm_nhanes_mr", "02block_crm_nhanes_flowchart.R")),
        ("70_crm_nhanes_pub/08block_crm_nhanes_pub_align.R", ("crm_nhanes_mr", "08block_crm_nhanes_pub_align.R")),
        ("70_crm_nhanes_pub/11block_crm_mr_literature.R", ("crm_nhanes_mr", "11block_crm_mr_literature.R")),
        ("70_crm_nhanes_pub/12block_crm_nhanes_pub_deliverables.R", ("crm_nhanes_mr", "12block_crm_nhanes_pub_deliverables.R")),
        ("70_crm_nhanes_pub/14block_crm_nhanes_table_builders.R", ("crm_nhanes_mr", "14block_crm_nhanes_table_builders.R")),
    ]:
        old_b = f'b("{shell_pat}")'
        if old_b in text:
            st, fn = study_file
            text = text.replace(
                old_b,
                f'file.path(root, "run", "{st}", "blocks_shell", "{fn}")',
            )
    text = text.replace("70_crm_nhanes_pub/", "57_crm/")

    # 69 IPW: method files in 34_IPTW; shells in run
    for fname in (
        "01block_ipw_diabetes_exposure.R",
        "02block_ipw_flowchart.R",
        "06block_ipw_literature_targets.R",
        "07block_ipw_pub_export.R",
        "09block_ipw_jin_composite_risk.R",
        "10block_ipw_alteplase_exposure.R",
    ):
        old_b = f'b("69_ipw_diabetes_stroke_full/{fname}")'
        if old_b in text:
            text = text.replace(
                old_b,
                f'file.path(root, "run", "ipw_diabetes_stroke", "blocks_shell", "{fname}")',
            )
    text = text.replace("69_ipw_diabetes_stroke_full/", "34_IPTW/")

    # 71 transformer stroke leftovers
    text = text.replace("71_two_stage_transformer_stroke/", "67_transformer/")
    # fix tst_ prefix for files we renamed when copying from 71
    # Actually pipeline still has original filenames under 71 — we copied as tst_0N...
    # Better: also copy 71 files with original names into 67 for path stability
    # (handled below in ensure_transformer_aliases)

    # 73 nafld
    text = text.replace("73_ml_nafld_cm/", "22_ml_models/")

    # 77 gallstone -> run shells
    text = re.sub(
        r'b\("77_gallstone_nomogram_full/([^"]+)"\)',
        r'file.path(root, "run", "gallstone_nomogram", "blocks_shell", "\1")',
        text,
    )

    # 78 database pooling -> run shells
    text = re.sub(
        r'b\("78_database_pooling_full/([^"]+)"\)',
        r'file.path(root, "run", "database_pooling", "blocks_shell", "\1")',
        text,
    )

    # 79 sleep -> keep algorithms if any in Blocks; shells to run — most are method-ish; map folder
    text = text.replace("79_sleep_dyslipid_prognosis_full/", "RUN79/")
    # For simplicity put sleep method files into a family folder
    # (created below)

    path.write_text(text, encoding="utf-8")
    print("  wrote", path)


def ensure_transformer_aliases() -> None:
    """Keep original 71 filenames inside 67_transformer for pipeline path stability."""
    dst = DST_BLOCKS / "67_transformer"
    src = SRC_BLOCKS / "71_two_stage_transformer_stroke"
    if not src.is_dir():
        return
    for sp in src.glob("*.R"):
        if any(x in sp.name for x in ("literature", "pub_export", "summary_results")):
            # shells
            shell = DST_RUN / "two_stage_transformer_stroke" / "blocks_shell"
            ensure_dir(shell)
            copy_file(sp, shell / sp.name)
            continue
        copy_file(sp, dst / sp.name)


def ensure_sleep_family_and_fix_runner() -> None:
    dst = DST_BLOCKS / "79_sleep_dyslipid"
    if dst.exists():
        shutil.rmtree(dst)
    ensure_dir(dst)
    src = SRC_BLOCKS / "79_sleep_dyslipid_prognosis_full"
    for sp in sorted(src.glob("*.R")):
        if is_shell_filename(sp.name):
            shell = DST_RUN / "prognosis_v2" / "blocks_shell"
            ensure_dir(shell)
            copy_file(sp, shell / sp.name)
        else:
            copy_file(sp, dst / sp.name)
    path = DST / "R" / "pipeline_runner.R"
    text = path.read_text(encoding="utf-8")
    text = text.replace("RUN79/", "79_sleep_dyslipid/")
    path.write_text(text, encoding="utf-8")


def ensure_58_medication_shells() -> None:
    src = SRC_BLOCKS / "58_medication_regimen_full"
    shell = DST_RUN / "medication_regimen" / "blocks_shell"
    ensure_dir(shell)
    for sp in src.glob("*.R"):
        if is_shell_filename(sp.name):
            copy_file(sp, shell / sp.name)


def write_blocks_readme() -> None:
    readme = DST_BLOCKS / "README.md"
    readme.write_text(
        """# Blocks/（方法族布局）

本树由 `01Block-new-Final` **只读拷贝并重组** 生成，目标目录为仓库根 `01Block/`。

- **只放可复用方法族**；族目录下并列变体（对齐 `04_baseline`）。
- **文献/课题壳**（ingest / flowchart / pub_finalize / literature_validate / phases）在 `run/<study>/blocks_shell/`。
- `register_block` 名称尽量与 Final 保持一致；路径映射见 `R/pipeline_runner.R`。

重新生成：`python3 scripts/migrate_blocks_to_method_families.py`
""",
        encoding="utf-8",
    )


def main() -> None:
    ensure_dir(DST_BLOCKS)
    ensure_dir(DST_RUN)
    build_keep_and_renames()
    build_ml_dual()
    build_trajectory()
    build_environment()
    build_expanded_families()
    copy_shells_to_run()
    ensure_transformer_aliases()
    ensure_sleep_family_and_fix_runner()
    ensure_58_medication_shells()
    # copy 70 shells explicitly
    src70 = SRC_BLOCKS / "70_crm_nhanes_pub"
    shell70 = DST_RUN / "crm_nhanes_mr" / "blocks_shell"
    ensure_dir(shell70)
    for sp in src70.glob("*.R"):
        if is_shell_filename(sp.name) or "table_builders" in sp.name or "pub_align" in sp.name:
            copy_file(sp, shell70 / sp.name)
    # 69 shells
    src69 = SRC_BLOCKS / "69_ipw_diabetes_stroke_full"
    shell69 = DST_RUN / "ipw_diabetes_stroke" / "blocks_shell"
    ensure_dir(shell69)
    for sp in src69.glob("*.R"):
        if sp.name not in {p.name for p in (DST_BLOCKS / "34_IPTW").glob("*.R")}:
            # copy study-specific not already in 34
            if any(x in sp.name for x in ("flowchart", "literature", "pub_export", "exposure", "jin_composite")):
                copy_file(sp, shell69 / sp.name)

    patch_pipeline_runner()
    # re-apply sleep fix after patch (patch may have run before sleep folder)
    ensure_sleep_family_and_fix_runner()
    write_blocks_readme()

    # summary
    dirs = sorted([p.name for p in DST_BLOCKS.iterdir() if p.is_dir()])
    print("\n== DST Blocks dirs (%d) ==" % len(dirs))
    for d in dirs:
        n = len(list((DST_BLOCKS / d).rglob("*.R")))
        print(f"  {d}: {n} R")


if __name__ == "__main__":
    main()
