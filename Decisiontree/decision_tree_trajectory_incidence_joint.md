# 分析决策树 — 双指标联合轨迹发病（GBMTM Joint Trajectories → Incidence）

> 对标文献：Liu et al. *Joint longitudinal trajectories of … and incident CVD*. Cardiovasc Diabetol 2026;25:207（PMID 索引课题 `56_CVD/incidence_trajectory_13393250`）
> 地基判定：**发病 incidence** + 方法后缀 **trajectory_incidence_joint**（GBMTM 定类 → 序贯 Cox → 亚组/敏感性 → 发表收口）
> 引擎入口：`Blocks/82_trajectory_incidence_joint/`（6 块）+ `R/literature_trajectory_joint.R` + `R/gbmtm_core.R`
> 单跑：`run/trajectory_incidence/run_trajectory_incidence_joint.R --config <cfg>`
> 指标池门控：`.cursor/rules/trajectory_joint_index_screening.mdc`（Gate 0/1/2 → 用户确认 → 写 config）
> 冒烟：`tests/smoke_trajectory_joint.R`（合成波次数据，Rubin m=2，全链 OK）

---

## 0. 对抗阅读 → 套路约束（摘要）

| Q | 硬约束 |
|---|---|
| Q1 | 暴露 = **一对复合指标的联合轨迹类别**（GBMTM group-based multi-trajectory），非单指标分位；类别数 K 由 AIC/BIC 主选 + AvePP≥0.70 / 最小类≥5% 软门控 |
| Q2 | 参照类 = 基线风险最低类 T1；所有 HR 相对 T1；多重比较压力来自 结局×体系×Model |
| Q3 | 主分析 = Cox（发病时间/中点随访）；logistic 不冒充；轨迹定类**不做插补**（操作层锁 master），推断 Cox 走 **MICE m≥5 + Rubin** |
| Q4 | Model1–4 序贯递进（文献四段式）；协变量成分/疾病泄漏硬排除 |
| Q5 | 亚组 = 分层 HR + **LRT 交互 P**（跨插补平均 χ²）；年龄二分类切点病种依据 |
| Q6 | 敏感性 ≥9 项：前 2 年剔除、排除 DM/HBP、完整病例、药物排除、后验概率加权、时间尺度 |
| Q7 | PH  Schoenfeld；违则 Limitations；判别（ΔC/NRI/IDI）另表 |
| Q8 | 发表键：Fig1 纳排诚实分项（年龄+成分缺失 n）、Fig2 KM、Fig3 AIC/BIC+轨迹面板、Fig4/5 森林、Table1-3+S*；数字单一出处 |

---

## 1. 总览（数据流）

```
原始多波宽表 master（成分列 <comp>_w<k>；结局 event/time 预生成）
  │  tj_data_ingest   年龄门控 → 逐波重算复合指标(00_index 公式)
  │                    → 基线成分缺失诚实剔除 → 基线现患剔除 → 结局挂接
  ▼
分析队列（attrition 诚实分项落 Fig1）
  │  tj_gbmtm_fit     每体系 (A,B) 联合 GBMTM：长表→k_range 拟合→AIC/BIC+软门控选 K
  │                    → 命名 T1..TK（基线风险升序）→ grp_<system> 锁列 + 后验矩阵落盘
  ▼
master + grp_* 固定类别列
  │  imputation       MICE m≥5（协变量）；grp_*/event/time 不插补（exclude_from_mice_cols）
  ▼
  │  tj_cox_rubin     体系×结局×Model1–4：mi_coxph 每套 complete 拟合 → Rubin 合并
  │                    HR/CI/P；PH=complete#1 代表集（Methods 注明）
  ▼
  │  tj_subgroup      分层 Cox（剔分层变量自身）+ LRT 交互 χ² 跨套平均 → HR, P-int
  │  tj_sensitivity   S0/S1/S3/S4/S5/S6/S7(PP加权)/S9a/S9b；Rubin 或完整病例
  ▼
  │  tj_pub_export    Table1(按类基线) / Table2(Cox) / Table3(亚组) / S*
  │                    Fig1 flowchart / Fig2 KM / Fig3 AIC-BIC+轨迹 / Fig4 森林
  │                    Methods md + 软件版本 txt + 交付根白名单 prune
  ▼
<Output>/summary_results/
```

---

## 2. 复用 vs 新建

| 能力 | 来源 | 动作 |
|------|------|------|
| GBMTM 统计内核 | `R/gbmtm_core.R`（Nagin 口径） | 复用；勿用 lcmm GMM 冒充 joint |
| MICE + Rubin | `Blocks/03_imputation` + `R/mi_rubin_pool.R` | 复用；`mi_complete_aligned` extra 带类别列 |
| 复合指标公式 | `Blocks/00_index/01block_index.R` | 复用 `tj_calc_index_waves` 逐波重算 |
| 疾病/成分硬排除 | `analysis_exclusion` 规则 | 复用 config；Gate 0 预检 |
| Fig1 CONSORT | `R/attrition_log.R` | 复用；年龄+成分缺失诚实出框 |
| 三线表/字体/位数 | `export_sci_table` + `pub_digits` + Times | 复用引擎收口 |
| 交付白名单 | `R/pub_delivery_prune.R` | finalize 尾挂 |

---

## 3. 关键决策节点

1. **换疾病/换库**：只改 config（disease、waves、index_pairs、model_sets、outcome 列名）；
   指标必须先过 Gate 0/1/2（规则 mdc），**用户确认后**才写 `index_pairs`。
2. **K 的选择**：默认数据驱动 `gbmtm_select`（AIC/BIC 主 + 软门控）；复现实验文可 `force_K` 锁定，
   但表/图/Methods 须同口径。
3. **体系数 >1**：每体系独立出 Table IC、Fig 轨迹面板、KM、森林；正文写明体系命名 `A_B`。
4. **结局时间尺度**：event/time 列须由独立结局步预生成（波次 interview 中点随访月）；
   ingest 只挂接不臆造。
5. **敏感性 S7**：后验概率加权 = 类别不确定入模（PP 矩阵 rds 已在 gbmtm_fit 落盘）。
6. **禁**：把 grp_* 插补/重估；用 complete#1 Cox 点估计冒充 MI；穷举指标对不经查新。

---

## 4. 出厂门控（发表前）

```
[ ] smoke_trajectory_joint.R SMOKE_OK（Rubin>=2套、LRT、敏感性、交付五件套）
[ ] index_pairs 有 reports/tj_index_screen_<db>.md + 用户确认
[ ] Fig1 年龄/成分缺失 n 诚实分项；无图底长脚注
[ ] Table2 脚注协变量 = 实际拟合（Model1–4 序贯）；类别=grp_* 锁定
[ ] Methods：GBMTM 参数、选 K 规则、MICE(m/seed/不入模列)、Rubin、PH、敏感性清单
[ ] 无裸 "best"；S 表 A1 = 文件名；交付根白名单 prune
```
