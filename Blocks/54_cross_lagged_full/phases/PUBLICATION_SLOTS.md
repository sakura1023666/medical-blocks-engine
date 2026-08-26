# 交叉滞后固定出版清单（所有课题必须）

`summary_result/{figure,table}` 只收这一套槽位：**不多、不少**。
中间件（Missing Overview、箱线、Fig3-Pooled、分库 S6/S7、VIF final、RCS S-XX、散落 csv/rds）一律不进 summary。

收集入口：`collect_summary_result.sh` → `collect_summary_result_generic.sh`。
敏感性：`phase_sensitivity.R`（S9–S17.1），每个交叉滞后课题都必须跑。

队列映射：横断面第三库有 NHANES 则用 NHANES（对应髋部 HRS）；纵向只收实际存在的 `phase3_long_*`（无则该槽位 N/A，不硬补）。

## Figure（核心）

| 槽位 | 内容 | 队列 |
|---|---|---|
| Fig1 | 纳排流程图 | 纵向库 + Pooled（纵向）；**无纵向的横断面库（NHANES）补横断面 Fig1** |
| Fig2 | RCS | 横断面库 + Pooled |
| Fig3 | 亚组森林 | 横断面库（**不要 Pooled**） |
| Fig4 | CLPN 网络 | 纵向库 |
| S1 | CLPN edge-weight bootstrap | 纵向库 |
| S2 | CLPN case-dropping 稳定性 | 纵向库 |
| S3 | 纵向中介路径图 | 纵向库 + Pooled |
| S4 | Mean ePWV（或 FI）by Year and Disease | 纵向库；昼夜课题另收 **NHANES**（横断面一年/周期） |
| S5 | Mean ePWV（或 FI）by Country and Disease | 一张合并图（昼夜含 NHANES=USA） |
| S11 | ROC | 横断面库 |
| README | FigS1/S2 说明 | 一份 |

## Table（核心 T1/T2/S1/S3–S8）

| 槽位 | 内容 | 队列 |
|---|---|---|
| T1 | 基线特征 | 横断面库 |
| T2 | Logistic（与主文同一分组：三分位或四分位） | 横断面库 + Pooled |
| S1 | 插补前后基线 | 横断面库 |
| S3 | 单因素回归 | 横断面库 |
| S4 | VIF screen（UV p 0.1） | 横断面库 |
| S5 / S5.1 | Change（auto / two-wave） | 合并表 |
| S6 | 相关回归（合并） | 一份 |
| S7 | 纵向中介（合并） | 一份 |
| S8 | CLPN adjacency | 纵向库 |
| CLPN bootstrap 旁表 | rds/csv | 非 CHARLS 的纵向库（与髋部 ELSA/HRS 对齐） |

## Table（敏感性 S9–S17.1，必跑）

| 槽位 | 场景 | 队列 |
|---|---|---|
| S9 / S10 | 剔除基线慢性共病 ≥2：基线 / logistic | 横断面库 |
| S11 / S11.1 | 同上：Change auto / two-wave | 合并（仅纵向库） |
| S12 / S13 | 未插补 listwise 完整病例：基线 / logistic | 横断面库 |
| S14 / S14.1 | 同上 Change | 合并（仅纵向库） |
| S15 / S16 | 剔除基线 2 年内发病：基线 / logistic | **仅纵向库**（无随访的横断面库跳过） |
| S17 / S17.1 | 同上 Change | 合并（仅纵向库） |
| README_sensitivity.txt | 口径说明 | 一份 |

竞争风险敏感性默认跳过（无死亡变量）。

## 一键

```bash
export CROSS_LAGGED_STUDY_ROOT="/path/to/study"
Rscript Blocks/54_cross_lagged_full/phases/phase_sensitivity.R --study-root "$CROSS_LAGGED_STUDY_ROOT" --no-sync
bash Blocks/54_cross_lagged_full/phases/collect_summary_result.sh "$CROSS_LAGGED_STUDY_ROOT"
```
