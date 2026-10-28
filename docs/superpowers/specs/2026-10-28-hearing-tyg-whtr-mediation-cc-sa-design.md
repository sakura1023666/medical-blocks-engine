# 听力损失 TyG_WHtR（NHANES 单库 ML）— 中介 · 亚组补全 · 完整病例对照 · 表图整理

日期：2026-10-28  
课题：`/mnt/g/02block_result/15_hearing_loss/ml_tyg_whtr_nhanes_single`  
指标：`【success】TyG_WHtR`  
用户确认：主文仍 MI+Rubin（方案 1）；中介候选 = 引擎默认实验室池自动筛；图和表必须整理好交付。

## 1. 目标与非目标

### 做

1. **中介**：挂发病/NHANES 加权中介流程；默认实验室池自动筛；门控通过才导出中介主表、路径图、实验室关联表（`skip_export_if_ns` 同生共死）。
2. **亚组**：核对 Fig5 图面已有各层 OR/CI/P 与交互 P；补齐亚组结果表（若缺）、`image_information`、中期注释，使表图文一致。
3. **NRI/IDI**：已有 Table S12/S13；Methods + 中期点名；交付根编号与题名一致，不重复造表。
4. **完整病例对照**：在 **不改主文 MI** 前提下，增加完整病例（未插补）加权 logistic 对照表；敏感性 suite 开 `SA_complete_case`（及课题需要的轻量场景），产物进补充表并写清口径。
5. **收口**：统一 S 编号、四目录图、Methods、白名单修剪、中期 PDF。

### 不做

- 不把主分析改成完整病例（方案 2 已否）。
- 不做标准高频 PTA 结局（数据仅有 0.5/1/2/4 kHz，无 3/6 kHz）。
- 不重训全套 ML（除非对照/敏感性块强制依赖；默认只加关联侧完整病例 + 中介 + 文档整理）。
- 不放开中介全局门控；不在 `scripts/` 堆长期 hotfix。

## 2. 主文口径（锁定）

| 项 | 口径 |
|---|---|
| 队列 | NHANES，Age 45–69，分析集 N≈2736（权重合格） |
| 暴露 | TyG WHtR；分位与 Table 2 锁定 scheme 一致 |
| 结局 | 言语频率更好耳 PTA≥20 dB HL（现 DN） |
| 推断 | MICE m=5 + Rubin；操作层 complete#1 |
| 权重 | `new_Weight`（WTSAF2YR/WTSAF4YR） |

## 3. 中介设计

- Block：`mediation_nhanes_weighted`（挂入 NHANES ML pipeline，位置在亚组/RCS 关联链之后、或与发病 dual-batch 同序）。
- 候选中介：`.mi02_resolve_lab_indicator_pool`（Table1 Laboratory + `lab_indicator_vars` + `mediator_extra_vars`）；**不手写人口学进池**。
- 协变量：与 Table 2 Model 2 同集（脚注同源）。
- 门控：`skip_export_if_ns`；失败则 unlink 中介表、路径图、实验室关联表。
- 交付命名（建议，finalize 时按现有 S 最大号顺延）：
  - 实验室关联（若导出）→ Table S14（或课题双库角色 S8 对齐时用引擎角色号）
  - 中介主表 → Table S15
  - 路径图 → Figure S2（或 S\*；与 LASSO S1 不冲突）

单库 NHANES：文件名/表题不加 `-NHANES` 后缀（`pub_strip_db_tags`）。

## 4. 亚组补全

- 源：现 Fig5 PDF 已含各层 P；补：
  - 若无 Table 3/亚组 xlsx，从 subgroup step 导出或同步到 `summary_results/Tables`
  - 刷新 `Figures/image_information/Figure 5…md`（各层 OR/CI/**P** + 交互 P 全抄图面）
  - 中期 `content.json` 注释与图面一致
- 不改 `required_subgroup_vars` / `age_cutoff=65` / `forest_n_source=full_stratum`。

## 5. NRI/IDI

- 保留 Table S12（train）、S13（validation）。
- Methods「Machine learning」段加一句：以 NRI/IDI 评估相对基线的预测增益（见表 S12–S13）。
- 中期结果章点名 S12/S13，不另开主文图。

## 6. 完整病例对照 + 敏感性

| 角色 | 内容 | 落盘 |
|---|---|---|
| 主分析 | MI + Rubin（现 Table 2 等） | 不动编号 |
| 对照验证 | 完整病例、同 Model1/2、加权 logistic（连续 + 锁定分位） | 新补充表，题名含 Complete-case / unimputed |
| 敏感性 | `incidence_batch$sensitivity_suite$complete_case = TRUE`（及引擎默认场景）；成功产物进 `sensitivity/` 或汇总 S 表 | Methods 写：敏感性 = 完整病例；主分析仍为 MI |

禁止：敏感性表脚注写 Rubin's rules 却只拟合 complete-case；主表脚注写「first completed」冒充 MI 推断。

## 7. 表图整理规则

1. `summary_results/Tables`：主表 Table 1–4 → 补充 S1… 连续无空号；中介/完整病例接在 S13 后。  
2. `summary_results/Figures`：Fig1–5 + S1 Lasso + 中介路径图（若导出）；四目录齐全，dpi≥600。  
3. Methods：结局 PTA、中介门控、NRI/IDI、主分析 MI vs 完整病例对照/敏感性一句分写。  
4. 交付白名单 prune；再出/更新中期 PDF。  
5. 跑 `run_pub_qc_after_project.R` + Agent 核中介门控与分母。

## 8. 实现顺序

1. 改 `config.R`：mediation enable；sensitivity_suite complete_case；必要时 pipeline 插入 `mediation_nhanes_weighted`。  
2. 定向重跑：中介块 → 完整病例对照/敏感性轻量 → finalize/remirror。  
3. 外科整理 S 编号与 Fig image_information；写 Methods；prune；中期。  
4. pub QC；P0 清零。

## 9. 验收清单

- [ ] 中介：门控日志明确；通过则有表+路径图+（若适用）关联表；失败则三件皆无  
- [ ] 亚组：表/Fig5 md/中期 P 值与图面一致  
- [ ] S12/S13 仍在交付根；Methods 提及 NRI/IDI  
- [ ] 完整病例对照表存在；Methods 主分析≠完整病例  
- [ ] summary_results 白名单五项；无散落中间稿  
- [ ] 无高频结局假表  

## 10. 风险

- 中介不显著 → 无中介交付物（符合铁律，须在回复说明）。  
- 完整病例 N 小于 2736 → 表脚注写 n，不与 Table1 强行等同。  
- 敏感性闸门（Crude/Model2）可能导致 SA 标 failed → 仍保留对照表路径，不把 failed 敏感性混进主文。
