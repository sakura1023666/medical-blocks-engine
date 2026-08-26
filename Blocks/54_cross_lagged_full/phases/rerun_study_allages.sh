#!/usr/bin/env bash
# 全年龄 + HRS 不剔人（恢复 _backup_pre_age65 基线）+ 抑郁中介（无血检试点）
# 清空旧结果/检查点后按全流程重跑；结果在引擎 Output，结束后同步课题盘。
#
# 用法（仓库根目录）:
#   bash Blocks/54_cross_lagged_full/phases/rerun_study_allages.sh
#
# 各阶段通过唯一入口:
#   Rscript run/cross_lagged/run_cross_lagged_frailty.R --phase <名>
set -euo pipefail
ENGINE="${MEDICAL_BLOCKS_ROOT:-/mnt/e/01block/01Block-new-Final}"
STUDY="${CROSS_LAGGED_STUDY_ROOT:-$ENGINE/Output/16_Hip_fracture_cross-laged_40595747_allages}"
G_STUDY="/mnt/g/02block_result/16_Hip fracture/cross-laged_40595747"
BACKUP="$G_STUDY/data/harmonized/_backup_pre_age65"
export MEDICAL_BLOCKS_ROOT="$ENGINE"
export SMOKE_NO_FEISHU=1
export CROSS_LAGGED_STUDY_ROOT="$STUDY"
export CROSS_LAGGED_SYNC_ROOT="$G_STUDY"
cd "$ENGINE"
CL_RUN="Rscript run/cross_lagged/run_cross_lagged_frailty.R"

LOG="$ENGINE/Output/rerun_allages_no_hdl_filter.log"
mkdir -p "$(dirname "$LOG")"
exec > >(tee -a "$LOG") 2>&1
ts() { date '+%F %T'; }
step() { echo; echo "======== [$(ts)] $* ========"; }

step "1) Restore full-age baselines (HRS N≈3906, no HDL-drop filter)"
if [[ ! -f "$BACKUP/D04_HRS_hip_baseline.allages.RData" ]]; then
  echo "ERROR: missing backup: $BACKUP/D04_HRS_hip_baseline.allages.RData" >&2
  exit 1
fi
# 引擎 study 必须恢复；课题盘可能只读/权限不稳，失败不中断
mkdir -p "$STUDY/data/harmonized"
for db in CHARLS ELSA HRS; do
  src="$BACKUP/D04_${db}_hip_baseline.allages.RData"
  cp -a "$src" "$STUDY/data/harmonized/D04_${db}_hip_baseline.RData"
  echo "  restored $STUDY/data/harmonized/D04_${db}_hip_baseline.RData"
done
if mkdir -p "$G_STUDY/data/harmonized" 2>/dev/null; then
  for db in CHARLS ELSA HRS; do
    src="$BACKUP/D04_${db}_hip_baseline.allages.RData"
    if cp -a "$src" "$G_STUDY/data/harmonized/D04_${db}_hip_baseline.RData" 2>/dev/null; then
      echo "  restored $G_STUDY/.../D04_${db}_hip_baseline.RData"
    else
      echo "  WARN: cannot write G disk baseline for $db (continue on engine)"
    fi
  done
fi

Rscript -e '
s <- Sys.getenv("CROSS_LAGGED_STUDY_ROOT")
for (db in c("CHARLS","ELSA","HRS")) {
  e <- new.env(); load(file.path(s,"data/harmonized",sprintf("D04_%s_hip_baseline.RData",db)), e)
  a <- as.numeric(e$dabiao$Age)
  cat(sprintf("%s N=%d Age[%.0f,%.0f] cases=%d\n", db, nrow(e$dabiao),
              min(a,na.rm=TRUE), max(a,na.rm=TRUE),
              sum(grepl("Hip", as.character(e$dabiao$Disease_Group)))))
}
stopifnot({
  e <- new.env(); load(file.path(s,"data/harmonized/D04_HRS_hip_baseline.RData"), e)
  nrow(e$dabiao) >= 3900
})
cat("OK: HRS full sample restored\n")
'

# cohort policy note
cat > "$STUDY/README_COHORT.txt" <<'EOF'
Cohort policy:
- Full age range (no Age>=65 filter)
- HRS: NO drop for missing HDL / controls (full HRS baseline N≈3906)
- ELSA longitudinal years: 2004 / 2008 / 2012 / 2016 (wave2/4/6/8)
- Mediation primary: Depression (no blood-lab pilot as primary)
- Covariates Model2 = 三库 Table S4 / VIF_screen_pass 交集 (NOT forced Age+Gender;
  Model2Factors may inject Gender via force_sex — ignore for intersect)
- Group-FI descriptive figure: ONLY Figure S4 (no S2 FI boxplot)
- Workspace: engine Output/16_Hip_fracture_cross-laged_40595747_allages
- Sync target: /mnt/g/02block_result/16_Hip fracture/cross-laged_40595747
EOF
cp -a "$STUDY/README_COHORT.txt" "$G_STUDY/README_COHORT.txt" 2>/dev/null || true
cat > "$STUDY/cohort_restore_allages_full_hrs.txt" <<EOF
time=$(ts)
policy=full_age_range + full_HRS (no HDL missing control drop)
restore_from=$BACKUP/*.allages.RData
mediation_primary=Depression
EOF

step "2) Wipe previous results / checkpoints (keep data/ raw+harmonized+medition)"
# engine study
cd "$STUDY"
rm -rf \
  phase1_CHARLS_allages phase1_ELSA_allages phase1_HRS_allages \
  phase2_Pooled phase3_post_Pooled \
  phase3_long_CHARLS phase3_long_ELSA phase3_long_HRS phase3_long_Pooled \
  summary_result
rm -f \
  mediation_depression_covar_lock.rds \
  mediation_depression_covar_lock.txt \
  phase2_acceptance.txt \
  phase3_relock_acceptance.txt \
  data/harmonized/D04_Pooled_hip_postvif.RData \
  data/harmonized/D05_long_mediation_Pooled.RData \
  cohort_restore_allages_hrs_hdl_filter.txt 2>/dev/null || true

# G disk phases/summary (keep data/, _backup, _logs_pre_age65, configs)
cd "$G_STUDY"
rm -rf \
  phase1_CHARLS_allages phase1_ELSA_allages phase1_HRS_allages \
  phase1_CHARLS phase1_ELSA phase1_HRS \
  phase1_CHARLS_v2 phase1_ELSA_v2 phase1_HRS_v2 \
  phase2_Pooled phase3_post_Pooled \
  phase3_long_CHARLS phase3_long_ELSA phase3_long_HRS phase3_long_Pooled \
  summary_result 2>/dev/null || true
rm -f \
  mediation_depression_covar_lock.rds \
  mediation_depression_covar_lock.txt \
  phase2_acceptance.txt \
  phase3_relock_acceptance.txt 2>/dev/null || true

# residual pilot blood tables if reappear under any summary
find "$STUDY" "$G_STUDY" -maxdepth 4 -type f \( -name 'Pilot_blood4*' -o -name '*blood4*' \) -delete 2>/dev/null || true

cd "$ENGINE"
echo "Wipe done."
ls -la "$STUDY" | head -40

step "3) PHASE1 CHARLS / ELSA / HRS"
for db in CHARLS ELSA HRS; do
  step "PHASE1 $db"
  Rscript run/incidence/run_incidence_single.R --config "$STUDY/config_phase1_${db}.R"
done

step "4) PHASE2 vif_pooled"
$CL_RUN --phase vif_pooled --study-root "$STUDY"

step "5) PHASE3 post_vif"
$CL_RUN --phase post_vif --study-root "$STUDY"

step "6) PHASE3 relock"
$CL_RUN --phase relock --study-root "$STUDY"

step "7) PHASE3 long_figs (Depression mediation; 三库共用锁定协变量; + pooled)"
$CL_RUN --phase long_figs --study-root "$STUDY" --sims 200 --with-pooled

step "8) PHASE3 subgroup"
$CL_RUN --phase subgroup --study-root "$STUDY"

step "9) SUMMARY + SYNC"
$CL_RUN --phase summary --study-root "$STUDY"

step "10) Pub figs S4/S5/Fig4 (+ S8; group legends)"
$CL_RUN --phase pub_figs --study-root "$STUDY"

step "11) Copy Figure2 RCS into summary_result if missing"
for db in CHARLS ELSA HRS; do
  src=$(ls -1t "$STUDY/phase1_${db}_allages/Figures/Figure 2-${db}. RCS"*.pdf 2>/dev/null | head -1 || true)
  if [[ -n "${src:-}" && -f "$src" ]]; then
    mkdir -p "$STUDY/summary_result/figure" "$G_STUDY/summary_result/figure"
    dest="Figure 2-${db}. RCS plot between Frailty Index and Hip Fracture.pdf"
    cp -f "$src" "$STUDY/summary_result/figure/$dest"
    cp -f "$src" "$G_STUDY/summary_result/figure/$dest" 2>/dev/null || true
  fi
done
srcp="$STUDY/phase3_post_Pooled/Figures/Figure 4-Pooled. RCS plot between Frailty Index and Hip Fracture.pdf"
if [[ -f "$srcp" ]]; then
  dest="Figure 2-Pooled. RCS plot between Frailty Index and Hip Fracture.pdf"
  cp -f "$srcp" "$STUDY/summary_result/figure/$dest"
  cp -f "$srcp" "$G_STUDY/summary_result/figure/$dest" 2>/dev/null || true
fi

step "12) Mid-term PDF report"
$CL_RUN --phase midterm --study-root "$STUDY"

step "13) VERIFY common Model2 + HRS N + ELSA years + key tables"
Rscript -e '
s <- Sys.getenv("CROSS_LAGGED_STUDY_ROOT")
acc <- file.path(s, "phase3_relock_acceptance.txt")
if (file.exists(acc)) {
  cat(readLines(acc), sep="\n"); cat("\n")
} else cat("WARN: no phase3_relock_acceptance.txt\n")
for (db in c("CHARLS","ELSA","HRS")) {
  cands <- Sys.glob(file.path(s, paste0("*", db, "*"), "Tables", "Summary",
                   paste0("FinalCovariates_Locked_", tolower(db), ".txt")))
  hit <- cands[file.exists(cands)][1]
  if (!is.na(hit) && length(hit)) {
    L <- readLines(hit); cat("==", db, "==\n")
    cat(grep("^Model2|^# Model2|lock_source", L, value=TRUE), sep="\n"); cat("\n")
  }
}
e <- new.env(); load(file.path(s,"data/harmonized/D04_HRS_hip_baseline.RData"), e)
cat("HRS baseline N=", nrow(e$dabiao), "\n")
# ELSA long years: 2004/2008/2012/2016
if (file.exists(file.path(s,"phase3_long_ELSA/D05_long_ELSA.RData"))) {
  ee <- new.env(); load(file.path(s,"phase3_long_ELSA/D05_long_ELSA.RData"), ee)
  ys <- sort(unique(as.integer(ee$long_all$year)))
  cat("ELSA long years:", paste(ys, collapse=","), "\n")
  stopifnot(all(c(2004L,2008L,2012L,2016L) %in% ys))
  stopifnot(all(ys %in% c(2004L,2008L,2012L,2016L)))
  cat("OK: ELSA includes 2016\n")
}
csv <- file.path(s,"summary_result/table/FigureS4-ELSA_mean_FI_by_year.csv")
if (file.exists(csv)) {
  x <- utils::read.csv(csv)
  cat("S4 ELSA years in fig:", paste(unique(x$x), collapse=","), "\n")
  stopifnot("2016" %in% as.character(x$x) || 2016L %in% as.integer(x$x))
}
# Model2 = three-DB VIF_screen intersect (not forced Age+Gender)
acc2 <- file.path(s, "phase3_relock_acceptance.txt")
if (file.exists(acc2)) {
  L <- readLines(acc2)
  m2l <- sub("^Model2_single=", "", L[grepl("^Model2_single=", L)][1])
  src <- sub("^lock_source=", "", L[grepl("^lock_source=", L)][1])
  cat("VERIFY Model2_single=", m2l, " source=", src, "\n")
  stopifnot(!grepl("forced_M1_Age_M2_AgeGender", as.character(src)))
  stopifnot(grepl("Alcohol", m2l) || grepl("vif_screen", src))
  cat("OK: Model2 from VIF_screen triple intersect\n")
}
print(list.files(file.path(s,"summary_result/table"), pattern="Table (S5|2-|S6|S7)"))
print(list.files(file.path(s,"summary_result/figure"), pattern="Figure (2|S4-ELSA)"))
mid <- list.files(file.path(s,"summary_result"), pattern="中期报告", full.names=TRUE)
print(mid)
'
ls -la "$STUDY/summary_result" 2>/dev/null | head -20
ls -la "$G_STUDY/summary_result" 2>/dev/null | head -20

step "DONE all-ages full-HRS re-run + midterm"
echo "Log: $LOG"
echo "Engine: $STUDY/summary_result"
echo "Sync:   $G_STUDY/summary_result"
