# 预后 2.0 决策树（睡眠时长 × 血脂异常 × 死亡）

文献方法骨架来自 Jin 等 2026（PMID 41904528，DOI 10.1186/s12933-026-03149-5）正文 Methods 与补充表 S1–S5。该文没有公开代码，Data availability 只指向 NHANES 官网。

本套路是**预后 2.0**。原来的双库预后（`config_survival_dual_batch`、`run/survival/`）保留，不改 pipeline。

## 和文献的对应

| 文献 | 本课题 |
|---|---|
| 暴露 TyG 及衍生指标，主分析连续 + 四分位 | 暴露睡眠小时。主分析短 / 7–8 / 长；连续和四分位作辅；RCS 只核对谷底是否落在 7–8 |
| 主结局心衰相关死亡 | 主结局全因死亡 |
| Fine–Gray：非心衰死亡为竞争事件 | 全因死亡不做竞争。能分出心血管死亡时，Fine–Gray 只做敏感性 |
| ROC / Youden、中介把随访死亡当分类 | 统一先截到主窗口 2 年；NHANES 与 SHHS 另做 5 年 |
| 单库 NHANES | NHANES + CHARLS + SHHS 并行 |

## 前段（与旧预后相同，协变量规则不同）

列审阅 → 列名对齐 → MICE（cart，**m=5**，seed=1234）。  
- **推断层（Table 3 Cox 等）**：m 套各自拟合，按 **Rubin 规则**合并（`pv2_mi_cox.R` / `R/mi_rubin_pool.R`）。  
- **操作层（Boruta/SHAP/KM/RCS/Table1）**：用 complete#1，方法学写明。  
- **禁止** m=5 只取第 1 套 HR 还写成多重插补。  
- 索引文献 Jin 2026：关键变量缺失为**删除**（complete-case），未做 MICE。  
暴露、随访、死亡、权重不插补。单库表/图文件名不加库名前缀。

## 协变量（与 Jin 2026 相同，不用旧预后单因素规则）

1. 候选池只保留三库都有的列。血脂异常的定义列（TG、TC、HDL、LDL、降脂药、高脂血症诊断）不进协变量。种族只有 NHANES 有，不进共同模型。
2. Boruta（随机森林，对照影子变量）+ fastshap（梯度提升）排序。
3. VIF < 5。暴露睡眠小时不参与 VIF。
4. Model 1 不调整。Model 2 固定为年龄 + 性别。Model 3 = Model 2 + 三库都被 Boruta 确认且 VIF 通过的变量。
5. 只有 NHANES 的 Cox / Fine–Gray 使用 `WTMEC2YR`。CHARLS、SHHS 不加权。

## 流程

```text
三库各自纳排（血脂异常标准与 NHANES handle_data.R 相同）
  → Boruta + SHAP + VIF，锁定三库相同的 Model 3
  → 睡眠分组 + RCS 谷底核对 + 全随访 Cox / KM / 人年发病率
  → 行政删失到 2 年（备选 5 年仅 NHANES、SHHS）
  → 窗口内 ROC / Youden
  → 窗口内二分类准贝叶斯中介
  → 心血管死亡 Fine–Gray 敏感性
  → 三库拼成一张图
```

血脂异常（满足任一，单位 mg/dL）：TG ≥ 150，或 TC ≥ 200，或 LDL ≥ 130（缺测且 TG < 400 时用 Friedewald），或 HDL ≤ 40。NHANES 最终表已经是 DN=1。CHARLS 用 Hyperlipidemia=Yes。SHHS 用同一数值标准现算。

## 数据（2026-10-14 更新后）

- NHANES：血脂异常表（DN=1）并基线，死亡用 `nhanes-死亡.Rdata`（`mortstat`、`permth_exm`、`ucod_leading`）。加权。
- CHARLS：`ID_h_charls` 连接 `da049_sleep_hrs`，高脂血症 Yes，`death_status`。不加权。随访到 2013，按 2 年。
- SHHS：`hrswd02`、`vital==0` 为死亡、`systbp`。`weight` 是千克体重，不加权。

## Block

新块只在 `Blocks/79_sleep_dyslipid_prognosis_full/`。引擎 `pipeline_block_sources()` 只追加这 5 个名字，不改旧 block 行为。

1. `sleep_dyslipid_cohort`
2. `sleep_duration_range`
3. `survival_fixed_horizon`
4. `horizon_roc_youden`
5. `bayesian_mediation_horizon`

Boruta、SHAP、既有 `rcs_prognosis` / `subgroup_prognosis` 仍用原 block。死亡链和睡眠列齐了之后，用 `--blocks` 追加，不写进旧预后默认 pipeline。
