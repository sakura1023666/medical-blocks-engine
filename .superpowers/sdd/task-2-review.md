# Task 2 Review — Prep（门诊/病房 dabiao + 纳排）

**Reviewer**：read-only spec + quality pass  
**Date**：2026-09-20  
**Inputs**：`task-2-brief.md`, `task-2-report.md`, `task-2-review-package.md`, `docs/superpowers/specs/2026-09-20-suicide-cssrs-hama-hamd-clpm-design.md`, `scripts/prep_cross_lagged_suicide_cssrs.R`, mirror harmonized 产物

---

## Verdict

| Gate | Result |
|------|--------|
| **Spec (Task 2 scope)** | ✅ |
| **Quality** | **Approved**（无阻塞项；见 Important 下游衔接） |

---

## Spec checklist (Task 2 brief + design §3–4.1 prep 边界)

| Requirement | Status | Evidence |
|-------------|--------|----------|
| 脚本 `scripts/prep_cross_lagged_suicide_cssrs.R` | ✅ | 289 行，路径/`load_one`/合并/纳排/QC 完整 |
| 消费 D01–D06 + D07/08/10 Index/1st RData | ✅ | D01–D06（+ CGI1/12）；D07/08/10 的 `*1`/`*2` 分列 join |
| **1st 必须 `*2` 文件** | ✅ | `D07_HAMA2`, `D08_HAMD2`, `D10_C_SSRS2`（L181–193） |
| 列映射：`HAMA_intex_all` 拼写保留 | ✅ | L174, L206；头注释写明勿改 |
| C-SSRS **item1** Yes/No → 1/0 | ✅ | `cssrs_item1_01` + `C_SSRS_Ideation_index_1` / `_1st_1` |
| `ID`←`新编号`，`patient_group`←`患者类别` | ✅ | L201–202 |
| 六节点 numeric/integer + **complete.cases 删例** | ✅ | `filter_cohort` L123–131；镜像 `D04_outpatient` n=649 且 649/649 节点完整 |
| 门诊主 / 病房 Exploratory 分轨落盘 | ✅ | `D04_outpatient_clpm.RData` / `D04_ward_clpm.RData` + 双 attrition |
| `attrition_*.csv`：`step,n_remain,n_excluded,rule` | ✅ | 与 review-package 一致 |
| `prep_qc.csv`：门诊 `n_nodes_complete>0`，HAMD Index≠1st 粗检 | ✅ | 649；`hamd_index_eq_1st=FALSE` |
| 节点阶段 **不做 MICE** | ✅ | prep 无插补；listwise 即 spec 节点策略 |
| 未 git commit / 未开全分析 | ✅ | report 声明；符合 global constraints |

**Spec 未纳入 Task 2 的项（不扣分）**：design §4.1 可选「关键人口学缺失删例」、§4.2 协变量 MICE 与 `exclude_from_mice_cols`（下游 config/插补任务）。

---

## Quality notes

### Critical

无。

### Important

1. **`exclude_from_mice` 未在 prep 落盘**（review-package 自动检缺失）：design §4.2 要求插补前锁定节点禁 MICE。建议在 prep 产物中显式写出（任选其一即可）：RData 内 `exclude_from_mice_cols <- node_cols`、或 `harmonized/prep_node_manifest.csv`、或在 `prep_qc.csv` 增列/伴生 README。避免下游 config 漏挂六列。
2. **Listwise 删例率大**（门诊 1101→649，~41%）：report 已 Concern；主文 Methods / Fig1 必须写清分母与规则（与 attrition CSV 一致）。
3. **验证环境为 study_mirror + prep_raw**，非 brief 默认 UNC 根：可接受于「dry-run / 路径验证」；正式交付前应用同一脚本指向 `cross-laged_40595747` 再跑一遍并核对 `prep_qc` 数值一致或可解释差异。

### Minor

1. Brief「Creates」仅列 `attrition_outpatient.csv`；脚本另写 `attrition_ward.csv`（与 spec 病房 Exploratory 一致，建议 brief 下一版补列）。
2. Report「产物同步 UNC」：脚本只写 `CROSS_LAGGED_STudy_ROOT` 下 `data/harmonized/`；若 STUDY=挂载 UNC 则等价，否则需人工拷贝（文档一句即可）。
3. `fix_id` 静默去重 `新编号`（1423→1422）：report 已记；可在 attrition 增加可选 step 或 QC 计数（非必须）。
4. 病房 HAMD Index 均值 < 1st（与门诊相反）：Exploratory 解读注意，非 prep 缺陷。

---

## Script hygiene (spot)

- **Left join 锚 D01**（`safe_merge`）：避免量表独有 ID 膨胀 — 正确。
- **`NA == group_label` 显式排除**（L112）：避免 phantom 行 — 正确，report 已说明修复动机。
- 保存对象为 **纳排后** `dabiao`（含协变量宽表 + 六节点）— 符合 brief「协变量候选原样合并」。

---

## Recommendation

**Task 2 可关闭。** 开 Task 3（config / 列审阅 / 协变量 MICE）前：落实 Important #1（节点禁 MICE 名单落盘），并在 UNC 课题根复跑 prep 留档。
