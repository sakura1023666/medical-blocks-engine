# 复用地图 — 联合轨迹发病套路进引擎（2026-11-18）

沉淀自 ELSA×CVD 文献复现（`56_CVD/incidence_trajectory_13393250`，
Liu et al. Cardiovasc Diabetol 2026）。**下一「双指标联合轨迹 → 新发结局」课题直接走引擎**，
禁止再在课题目录堆 bespoke phase 脚本。

## 引擎入口

| 能力 | 入口 |
|---|---|
| 七块流水线 | `Blocks/82_trajectory_incidence_joint/01–07block_tj_*.R` |
| register_block 名 | `tj_data_ingest` → `tj_gbmtm_fit` → `imputation` → `tj_cox_rubin` → [`tj_finegray_rubin`] → `tj_subgroup` → `tj_sensitivity` → `tj_pub_export` |
| GBMTM 内核 | `R/gbmtm_core.R`（`gbmtm_to_long/select/label`；AIC/BIC + AvePP/最小类软门控） |
| 公共 helper | `R/literature_trajectory_joint.R`（波次指标重算 / Rubin 向量 / KM / 森林 / 轨迹面板 / Table1 按类） |
| config 模板 | `configs/templates/config_trajectory_incidence_joint.template.R` |
| 单跑 | `run/trajectory_incidence/run_trajectory_incidence_joint.R --config …`（`--from/--to/--blocks/--list`） |
| 指标池预检 | `run/trajectory_incidence/screen_trajectory_joint_index_pool.R --config …` → `reports/tj_index_screen_<db>.md` |
| 筛选门控规则 | `.cursor/rules/trajectory_joint_index_screening.mdc`（Gate 0/1/2 + 用户确认） |
| 证据链模板 | `configs/templates/reports_tj_index_screen.template.md` |
| 决策树 | `Decisiontree/decision_tree_trajectory_incidence_joint.md` |
| Blocks 目录 | `docs/Blocks_catalog.md` §`82_trajectory_incidence_joint`（536 blocks） |
| 冒烟 | `tests/smoke_trajectory_joint.R`（SMOKE_OK） |

## 本次进引擎的修复（勿课题私改绕过）

1. **`tj_calc_index_waves` 公式求值 bug**：`eval(~expr)` 返回 formula 而非数值
   → 改 `eval(parse(text = expr), envir = env)`。影响所有 `recompute_indices=TRUE` 课题。
2. **`.tj_comp_env` parent**：`stats::globalenv()` 不存在 → `globalenv()`。
3. **模板插补接线**：pipeline 必须含 `imputation`（gbmtm_fit 之后、cox 之前），
   且 `config$imputation$exclude_from_mice_cols` 锁 `grp_* / event / time / .tj_row_id`
   —— 否则 `mi_rubin_enabled` 恒 FALSE，单套 Cox 冒充多重插补（违反 `mi_m5_rubin_pool`）。
4. **单跑入口 `--list`** 检查点早退，不空跑全链。

## 新课题标准顺序

```
1. 列审阅（review-raw-covariate-columns）→ disease_vars
2. screen_trajectory_joint_index_pool.R → Gate 0/1 落盘
3. PubMed Gate 2（疾病×A / ×B / ×A+B）→ 证据链 md → 用户确认 index_pairs
4. 拷 config 模板 → 改 waves/index_pairs/model_sets/outcome/age_filter
5. run_trajectory_incidence_joint.R 全链 → 发表收口
6. run_pub_qc_after_project.R + nature 两 skill → P0 清零 → 中期 → prune
```

## 2026-11-23 增补：Fine-Gray 竞争风险 + 5006/2203 部署

| 能力 | 入口 |
|---|---|
| Fine-Gray sHR（Rubin m 套合并） | `Blocks/82_trajectory_incidence_joint/07block_tj_finegray_rubin.R`（`tj_finegray_rubin`）|
| config 开关 | `joint_trajectory$competing_risk = list(enable, cause=1, death_cause=2, cencode=0, death_event_col, death_time_col)` |
| cmprsk 缺失回退 | cause-specific Cox，`method` 列写明（禁止冒充 Fine-Gray） |
| Table 4 | `tj_pub_export` 消费 `ctx$results$tj_fg` → `Table 4 - Fine-Gray competing risk by class.xlsx` |
| 隔离模板（程序员接口） | 5006: `templates/config_trajectory_incidence_joint_competing.template.R` + `studies/_template_trajinc/` |
| run_study 路由 | `trajinc`（先于 `competing` 判定；匹配 `joint_trajectory|tj_finegray_rubin|tj_gbmtm_fit`）|

## 本次进引擎的修复（2026-11-23）

1. **`pipeline_self_pub` 守卫**（`R/pipeline_runner.R`）：pipeline 含 `tj_pub_export`（或
   `pub$self_pub_finalize` / `joint_trajectory$pub$self_finalize`）时，跳过通用
   `incidence_single_finalize_after_pipeline` 与 `ml_finalize_index_summary_results`，
   否则通用收口按 main_mediation scheme 误删 tj 自产 PDF（Figures/pdf=0）。
2. **`01block_tj_data_ingest` 空 `prevalent_exclude=list()` 崩溃**：加 `length>=1 && 有名字` 检。
3. **`01block_imputation` 泛用 method token**：`"mice"/"default"/"auto"` → 按列类型展开
   （连续 pmm、二分类 logreg、多分类 polyreg）；不再报 `mice.impute.mice not found`。

## 部署（2203）

- 同步清单：`02block_result` 外仅代码；rsync 排除 `Output/logs/checkpoints/02block_result`。
- 2203 布局：`~/medical-blocks/engine`（=MEDICAL_BLOCKS_ROOT）+ `~/medical-blocks/studies-iface`。
- R 4.6.1 空库：装包脚本 `~/install_trajinc_v2.R`（清华镜像，
  `dependencies=c("Depends","Imports","LinkingTo")` —— **勿用 TRUE**，Suggests 会拉
  bayesm/ks/robustbase 全家桶）；TMPDIR 指 `~/tmp`（容器 overlay 坑）。
- 冒烟：`studies/_route_test`（合成 N=400）`./run_study.sh _route_test --routine trajinc`
  → 8 blocks、Tables=8（含 Table 4）、Figures/pdf=6、summary_results 白名单干净。

## 反例（禁止）

- 在课题 scripts/ 重写 phase0–9 脚本而不调 tj_* blocks
- 穷举 combn 指标对不经 Gate 2 / 用户确认
- pipeline 漏 `imputation` 块后用 complete#1 Cox 交差
- 换病种照抄 ELSA `model_sets`（bpmed/fvc 等列不存在须裁剪）

## 2026-11-24/25 增补：文献九项敏感性全复现 + FDR + 竞争语义三档

对标 Liu et al. Cardiovasc Diabetol 2026;25:207 补全（`都补全！！！！！一切按照正确的来`）。
**下一课题直接走引擎**，禁止再在课题目录补敏感性。

| 能力 | 入口 |
|---|---|
| S8 区间删失 cloglog | `05block_tj_sensitivity.R` → `S8_cloglog_interval`；`tj_interval_windows`（优先 `outcome$primary$visit_time_cols` 真实访视窗，缺则 `interval_half_months` 对称近似）+ `tj_cloglog_fit`（`survreg(dist="weibull")`，`HR=exp(-coef/scale)`，delta 法方差）；`image_information` 标注 `interval censored (L, R]` |
| S10 基线中位数交叉分类 | `05block_tj_sensitivity.R` → `S10_cross_class`；A/B 各按 master 中位数四分 → T1 双低（参照）…T4 双高；表注 `median cross-classification; reference = double-low` |
| BH-FDR（轨迹组间） | `05block_tj_sensitivity.R` 尾部 `p.adjust(method="BH")`，按 `system×analysis` 分组；Table S1 输出 `P (FDR-adjusted)` + 脚注 |
| 竞争事件语义三档 | `07block_tj_finegray_rubin.R`：a) `death_cause_icd_col`+`main_cause_regex`（严格 non-CVD）；b) 无 ICD → 未报告主事件的死亡近似（自证计数）；c) `competing_is_all_cause=TRUE` 明示全因。文案落 `ctx$results$tj_fg_note` → Table 4 脚注 + Methods |
| 语义告警 | `07block_tj_finegray_rubin.R` 开头：死亡者>0 且全部已报告主结局事件 → warning「竞争组近空，Fine-Gray≈Cox」 |
| 缺列诚实 | S3/S4/S6 排除列缺失 → `colv()` 全 NA = 不排除任何人（表注/日志如实），禁止静默空集假跳过 |

**`.pub_col_kind` 修复（`R/utils.R`，全项目受益）**：`"Sensitivity analysis"` 等标签列曾被
`^(…|sensitivity|…)\b` 误判成概率列，Table S1 分析名单元格整列打 `NE`。修复=正则判定前先过
标签列例外（`sensitivity analysis|analysis|variable|indicator|term|feature|characteristic`）。

**模板/接口接线**（新课题默认开 S8/S10）：
`outcome$primary$visit_time_cols`、`competing_risk$death_cause_icd_col/main_cause_regex/competing_is_all_cause`、
sensitivity `items` 含 `S8_cloglog_interval`/`S10_cross_class` + `interval_half_months`；
`exclude_from_mice_cols` 补死因组与访视月列。
5006 `templates/config_trajectory_incidence_joint_competing.template.R`（**非** plain——
run_study 对 plain 模板强制覆盖 competing 三件套）与 `studies/_template_trajinc/config.R` 已同步；
2203 接口 md5 与 5006 一致。`recompute_indices`：master 已含 `<IX>_w<k>` 时置 FALSE。

**2203 全链冒烟通过**（2026-11-25，N=400 富化数据，m=5）：
- 8 blocks、18.6s、`【success】`；S1 = **11 项 / 42 行 / NA p=0**；FDR 列 42/47 非空（余为注脚行）
- Table 4：`Fine-Gray (crr), Rubin m-pooled (5/5)`；Events=76、Competing=29（ICD 口径）；
  脚注含 `NOT matching /^I/ (23 cvd-cause deaths … censored conservatively)`
- Methods：`Competing-risk semantics (Table 4, Fine-Gray): non-CVD death by underlying cause …`
- QC：Layer A **STRUCT_OK**、A3 下划线 PASS、A4 字体 PASS；交付 8 表白名单干净

**验证坑**：`sshpass ssh host 'grep …'` 类复合命令里本地 shell 会把带空格的变量串当多参数——
比对 MD5 用「一次 ssh 收全部远端和 → 本地逐行比对」；`| md5sum` 接 `cat` 在 Rscript 后会触发
SIGPIPE 停止执行，校验语句拆开跑。
