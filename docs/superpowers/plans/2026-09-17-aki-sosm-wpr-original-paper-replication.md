# AKI SOSM+WPR Original-Paper Replication Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 按 PMID 40537296 的主文及补充材料角色完整重建 AKI SOSM+WPR 双库 28 天预后结果，并保留 MIMIC-IV→eICU 冻结外验。

**Architecture:** 新增独立的 reference-paper profile 层，从既有无泄漏拆分/插补 checkpoint 克隆隔离 ctx，按 SOFA≤10/≥11 分层完成关联分析、分层 Boruta、五模型和冻结外验，再统一组装原文 Table 1–2、S1–S11、Figure 1–8、S1–S5。额外双库 ML 产物从 S12/S6 后顺延；旧结果只读。

**Tech Stack:** R、survival/rms/pROC/Boruta/tidymodels、现有五分类模型 Blocks、SHAP、openxlsx、PyMuPDF、公共发表图表导出模块。

## Global Constraints

- 疾病分层固定为数值 SOFA≤10 与 SOFA≥11，两库同切点。
- 仅 28 天结局；禁止生成 90 天数值。
- S9 为排除基线 Glucose<70 mg/dL，禁止写成 ICU 全程低血糖发作。
- 联合高低组：各指标最高 tertile=high，下两个 tertile=low。
- 先沿用原 overall train/internal split，再取 SOFA 子集；禁止层内重新随机拆分。
- eICU 禁止 Boruta、VIF 或模型重训；加载对应 MIMIC 分层资产。
- 结局显示必须为 Survivor/Non-survivor，不得为 AKI/No AKI。
- 当前目录不是 Git 仓库；每任务用测试和 manifest 代替 commit。

---

### Task 1: 修正 dev-ext 回归测试与结局显示

**Files:**
- Modify: `tests/test_ml_dual_dev_ext.R`
- Modify: `R/utils.R` 或实际 outcome display resolver 所在文件
- Create: `tests/test_prognosis_outcome_display.R`

**Interfaces:**
- Produces: `pipeline_resolve_outcome_display_labels(cfg)` 对 prognosis 返回 `Survivor/Non-survivor`。

- [ ] 写失败测试：`study_type="prognosis"`、`split_mode="dev_internal_ext"` 必须启用 dev-ext。
- [ ] 写失败测试：`survival$outcome_label="28-day all-cause mortality"` 时 0/1 显示为 Survivor/Non-survivor。
- [ ] 运行两测试确认分别因旧断言和错误 AKI 标签失败。
- [ ] 最小修复 resolver，incidence 保持疾病/非疾病标签。
- [ ] 运行测试，确认 prognosis dev-ext 与标签测试通过。

---

### Task 2: SOFA 分层证据、数据闸门与隔离 ctx

**Files:**
- Create: `R/ml_stratified_ctx.R`
- Create: `tests/test_ml_stratified_ctx.R`
- Create: `<study>/reports/disease_stratification_basis_AKI_SOFA_2026-09-17.md`

**Interfaces:**
- `ml_stratum_spec_sofa(cutoff=10)` → `sofa_le10/sofa_ge11`。
- `ml_clone_ctx_for_stratum(parent_ctx, stratum, output_root)` → 深拷贝 child ctx。
- `ml_stratum_audit(ctx, spec)` → n、events、missing、split counts。

- [ ] 测试父 ctx 序列化哈希在子集操作前后不变。
- [ ] 测试 train/test/imputed 通过患者 ID 同步过滤。
- [ ] 测试原 train/internal 分配不变。
- [ ] 测试清除 stale FS/models/queues，且输出重定向到 staging。
- [ ] 实现 helper 并运行测试。
- [ ] 落盘依据：SOFA cutoff 文献、两库原始缺失、插补后各层 n/事件数、KDIGO 不可算原因。

---

### Task 3: 原文联合分组与关联分析内核

**Files:**
- Create: `R/prognosis_reference_assoc.R`
- Create: `R/prognosis_landmark_ph.R`
- Create: `tests/test_prognosis_reference_assoc.R`
- Create: `tests/test_prognosis_landmark_ph.R`

**Interfaces:**
- `reference_joint_tertile_groups(a,b,cut_a,cut_b)`。
- `reference_fit_cox_suite(data,time,event,indices,stratum,covariates)`。
- `reference_grouped_rcs(...)`。
- `reference_ph_landmark_lock(mimic_fits)`。
- `reference_apply_landmark(data,locked_spec)`。

- [ ] 测试 high 仅为 `x > 66.67th percentile`，Group1–4 映射正确。
- [ ] 测试 Cox 输出 Unadjusted、Model1 Age+Gender、Model2 铁律协变量。
- [ ] 测试 RCS 返回每个 SOFA 层的 HR/CI、P-overall、P-nonlinear。
- [ ] 测试 PH 层/转折时间只由 MIMIC 选择，eICU 不可重选。
- [ ] 测试 landmark 前后风险集边界正确。
- [ ] 实现最小内核并通过测试。

---

### Task 4: 生成原文关联图表

**Files:**
- Create: `R/ml_reference_assoc_figures.R`
- Create: `tests/test_ml_reference_assoc_figures.R`

**Interfaces:**
- Produces: Figure 2–6、Table 2、Table S4–S10 的结构化结果和 PDF。

- [ ] Figure 2 测试：12 面板；4 行数据库/层，3 列 SOSM/WPR/joint；每面板 Log-rank P。
- [ ] Figure 3 测试：4 面板；每图含两条 SOFA 调整后 RCS 曲线及各自 CI/P。
- [ ] Figure 4 测试：4 面板；预测器固定为 SOSM、WPR、joint、APSIII、OASIS、GCS；AUC/CI/DeLong 写 S5。
- [ ] Figure 5 测试：MIMIC 锁定 stratum/day，eICU 读取相同锁。
- [ ] Figure 6 测试：2 数据库×2 指标森林图，N 为完整分层人数。
- [ ] Table 2/S4/S6–S10 测试：数据库、SOFA 层、模型、分母、敏感性口径齐全。
- [ ] 实现图表并输出到 staging，使用公共三线表与公共小数位。

---

### Task 5: 分层模型资产包与冻结外验

**Files:**
- Create: `R/ml_frozen_model_bundle.R`
- Create: `tests/test_ml_frozen_model_bundle.R`
- Create: `tests/test_ml_external_stratum_inheritance.R`
- Create: `tests/test_ml_factor_schema_external.R`

**Interfaces:**
- `ml_fit_stratum_bundle(ctx,stratum,methods)`。
- `ml_save_frozen_bundle(bundle,path)`。
- `ml_load_frozen_bundle(path)`。
- `ml_predict_external_bundle(bundle,newdata)`。

- [ ] 测试每层五模型、特征顺序、recipe、因子水平、阈值和版本均落盘。
- [ ] 测试序列化往返预测完全一致。
- [ ] 测试 eICU `sofa_le10` 只能载入同名主库资产。
- [ ] 测试外验缺特征硬失败，未知因子水平进入显式审计。
- [ ] 在 MIMIC 每层运行 Boruta+五模型，保留原 split。
- [ ] 在 eICU 对应层冻结评估，验证日志无 Boruta/fit。
- [ ] 输出 Table S11 所需 train/internal/external 性能长表。

---

### Task 6: 分层与 overall SHAP/个体解释

**Files:**
- Create: `R/ml_external_frozen_shap.R`
- Create: `tests/test_ml_external_frozen_shap.R`
- Create: `tests/test_ml_reference_shap_panels.R`

**Interfaces:**
- `ml_shap_from_frozen_bundle(bundle,newdata)`。
- `ml_pick_paired_cases(predictions,outcome,stratum)`。
- Produces: Figure 7、8、S2–S5。

- [ ] 测试 eICU SHAP 的模型哈希等于 MIMIC 冻结模型哈希。
- [ ] 测试每层 survivor/non-survivor 个体均来自本库本层。
- [ ] Figure 7：MIMIC 两层 Boruta。
- [ ] Figure 8：数据库×SOFA 层的 ROC、beeswarm、importance bar。
- [ ] S2 overall Boruta；S3 overall internal/external ROC；S4 overall 双库冻结 SHAP；S5 双库两层个体解释。
- [ ] 验证 SHAP 特征名回映和预测值一致。

---

### Task 7: 原文 profile、Flowchart、基线及编号

**Files:**
- Create: `R/ml_reference_paper_profile.R`
- Create: `tests/test_aki_sosm_wpr_reference_profile.R`
- Create: `Blocks/24_ml_dual/09block_ml_stratified_reference_profile.R`

**Interfaces:**
- `ml_reference_profile_40537296()`。
- `ml_reference_build_tables(...)`。
- `ml_reference_build_figures(...)`。

- [ ] 固定主表 Table 1–2、补表 S1–S16、主图 Figure 1–8、补图 S1–S8。
- [ ] Figure 1 从 raw→analysis→split/外验逐步人数生成真实双库 flowchart。
- [ ] Table 1 双库 Panel A/B，结局为 Survivor/Non-survivor。
- [ ] S1 写已证实 AKI 队列定义；上游代码未提供时明确标记证据不足。
- [ ] S2 UV、S3 VIF/继承审计、S11 分层 ML、S12–S16 本课题额外表。
- [ ] 所有角色写 manifest 的 `reference_role/adaptation/source/denominator`。
- [ ] 测试编号连续、角色唯一、面板数正确。

---

### Task 8: CLI、staging、四格式与完整运行

**Files:**
- Create: `run/ml/build_aki_sosm_wpr_replication.R`
- Modify: `Decisiontree/decision_tree_ml_dual_prognosis_aki_dev_ext.md`
- Create: `<success>/publication_final/OBSOLETE.md`

**Interfaces:**

```bash
Rscript run/ml/build_aki_sosm_wpr_replication.R \
  --config "<study>/config.R" \
  --index "SOSM+WPR" \
  --out "<success>/publication_literature_final"
```

- [ ] CLI `--dry-run` 输出全部原文角色、适配差异和来源 checkpoint。
- [ ] 实际构建只写 `publication_literature_final.__staging__`。
- [ ] 调用 `pub_figure_ensure_formats()`，确保 PDF/PNG/TIFF/MD 数量一致。
- [ ] 逐表执行 `pub_xlsx_verify()`，要求 readable、corrupt=0、styles>0。
- [ ] 全部通过后原子替换 `publication_literature_final/`。
- [ ] 旧 `publication_final/OBSOLETE.md` 指向新终稿，不删除旧审计结果。
- [ ] 更新决策树：SOFA 数值分层、原文全套角色、28 天适配及终稿路径。

---

### Task 9: 最终验证

- [ ] 运行新增和受影响的全部 R 测试。
- [ ] 运行 Python 拼图脚本语法检查。
- [ ] 验证 Figure 1–8、S1–S8，无重号、无平铺 PDF。
- [ ] 验证 Table 1–2、S1–S16，无重号、无损坏。
- [ ] 验证 eICU 资产 manifest 中 `trained_in=MIMIC-IV`。
- [ ] 验证 90-day 数值出现次数为 0；S9 标题含 baseline glucose。
- [ ] 验证所有结局标签无 `AKI/No AKI` 误写。
- [ ] 视觉抽查 Figure 1、2、3、4、8 和 S5。
- [ ] 输出 `FINAL_ACCEPTANCE.txt` 与 `MANIFEST.csv`。

