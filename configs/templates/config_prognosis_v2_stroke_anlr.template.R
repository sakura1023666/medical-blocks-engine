###############################################################################
#  config_prognosis_v2_stroke_anlr.template.R
#  缺血性卒中 · ANLR · prognosis_v2（MIMIC + eICU 平权）
#  （程序员隔离：产出写在本研究文件夹；run_study 设 STROKE_ANLR_PROJ=本目录）
#
#  入口: run/prognosis_v2/run_prognosis_v2_stroke_anlr.R
#  收口: run/prognosis_v2/remirror_stroke_anlr_pub.R
#  决策树: docs/Decisiontree/decision_tree_stroke_anlr_prognosis_v2.md
#
#  CLI:
#    run_study.sh <研究名> --routine prognosis_v2 --days 28 --out summary_results
#    run_study.sh <研究名> --routine prognosis_v2 --days 14 --out summary_results_14d
###############################################################################

# 识别关键字（run_study 自动路由）: prognosis_v2_stroke_anlr / STROKE_ANLR / ANLR
.study <- list(
  routine = "prognosis_v2_stroke_anlr",
  disease_code = "11",
  disease = "ischemic_stroke",
  literature_pmid = "41904528",
  index = "ANLR",
  default_days = 28L,
  default_out = "summary_results"
)

# 数据布局（相对本研究根）:
#   data/mimic/D02_rt_Stroke_surv28.RData + 预后 CSV + 实验室…
#   data/eicu/D02_rt_Stroke_surv28.RData + …
#   data/shared_feature_pool.json

message("[prognosis_v2 stroke ANLR] study markers loaded; runner uses STROKE_ANLR_PROJ")
