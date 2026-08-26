# Review package Task 6
- Figure 1 流程图必须走 `pipeline_pdf_device`（cairo_pdf 嵌 Times New Roman）；禁止对 `pdf()` 传 `"Times New Roman"`（Linux 报 unknown family）。
- 双库附表编号与正表相同：同一角色两库共用 S 号（`Table S1-eICU` + `Table S1-MIMIC` 都是插补）。禁止 `compact` 把根目录压成 S1…S22（一库一号）。森林图禁止整表 `clip=on`，轴端须留白，否则 0.2 的「0」会被裁掉。
- `simple_ROC` 默认 `mode=multivariable` + `covariate_source=locked`（与 Table2/Gate B 锁定协变量一致）；锁定为空须硬停。双库 `dual_db_cox_unified_locked` 后 locked 名单优先 `Model2Factors`，禁止用单库整份 `vif_final_pass`。ML 管线若把 ROC 放在 VIF 前，模板须显式 `mode=univariate`。预后结局用 `survival$event_var`。
- 实验室关联 Table S8：`BAR ~ scale(lab)`，列名须为 `β per 1-SD`；禁止未标准化的原始量纲（PH 等会出现 |β|≈十几）。分位基线 Table S10 须剔除暴露公式组分（BAR→BUN/Albumin）。分段 Cox 表脚注须说明：段内 HR=段内 median high vs low，LLR 可与各段 P 值不一致。
- 双库汇总 `by_index/<ix>/Figures`（含 `【success】*`）**只保留拼图**（`Figure N. …` / `Figure SN. …`）；分库底稿只留在 `<db>/Figures`。`dual_db$combine_figures$remove_singles` 默认 TRUE，拼图后会硬清扫 `-eICU`/`-MIMIC` 单图。禁止把课题一次性 `tmp_*`/`rerun_*.R` 留在引擎根目录当“正式脚本”。
- 汇总 `Figures/`（及交叉滞后 `summary_result/figure`）顶层只保留 `pdf/` `png/` `tiff/` `image_information/`；多库先拼图再导出；TIFF=LZW。
- 强制协变量默认**只 Age**（`covariate_policy$force_age=TRUE`，`force_sex=FALSE`）。Gender 须 UV/MV/VIF 自然入选，或课题显式 `force_sex=TRUE`。
- `exclude_from_models` 默认**不**含 BMI/Weight/Height；人体测量去留交给 VIF / anthropometric 共线性协调。若课题仍要硬踢，再在 `logistic_covariates$exclude_from_models` 显式写出。
- 敏感性勿手写固定场景名单。Yes/No 从两库 Table 1 动态生成（Yes n>50）+ 可配 `age_cutoff`；忽略旧 `scenarios`。轻量只重跑 Table 1/2，目录 `【success】`/`【failed】`，表 S12/S13。
<!-- /MANUAL:PITFALLS -->

<!-- BEGIN AUTO:dir_index -->
## 4. 目录速览（AUTO）

| 目录 | 块数 | register_block（节选） |
|---|---:|---|
