# Task 6 Report: pub_figure profile gating

**Status**: DONE · **Commits**: none

`R/pub_figure_profile.R`：`pub_figure_profile()` 缺省/空白→NULL；`is_pub_profile()` 仅 `identical(..., "mimic_inc_prog_sle_aki")` 为 TRUE。`pub_figure_profile_apply_ggplot()` 在 NULL profile 时返回同一对象。`utils.R` 尾部 source 挂载。

门控（仅 if 分支改 theme/标注；else 原路径）：attrition 浅蓝框、simple_ROC Youden 点+方形画布、ROC/RCS/KM/plot_cutoff ggplot classic overlay、RCS 结点 rug、森林图显著交互 P 高亮。`threshold_logistic` 已走公共 getter。

TDD：RED `file.exists(src) is not TRUE` → GREEN `OK profile gate`；`test_attrition_log` / `test_threshold_logistic` / parse 均 OK。未 git commit。
