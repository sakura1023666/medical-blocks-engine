# Task 4 Report: `ip_stage2_cohort_28d` + 单测

**Status**: DONE  
**Date**: 2026-08-26  
**Worker**: Task 4 subagent  
**Commits**: none（global constraints / 用户明确禁止）

---

## 1. 执行摘要

已按 TDD 实现 Stage2 胶水块 `ip_stage2_cohort_28d`：28 天行政截尾纯函数、AKI 阳性筛入、预后 CSV 合并、规则 C 时间零点、`study_type` 切到 prognosis。假数据与真数据冒烟均通过。`pipeline_block_sources` 已注册；`docs/Blocks_catalog.md` AUTO 已同步。未 git commit。

TDD：先写 `tests/test_ip_stage2_28d.R`，Windows Rscript 首次失败为 `exists("ip_admin_censor_28", mode = "function") is not TRUE`；实现 `00ip_common.R` + block + 注册后 PASS。

---

## 2. 交付物

| 项 | 路径 | 说明 |
|----|------|------|
| 公共函数 | `Blocks/72_incidence_prognosis_two_stage/00ip_common.R` | `ip_admin_censor_28`：futime=min(t,28)；fustatus=1 iff dead & t≤28 |
| Block | `Blocks/72_incidence_prognosis_two_stage/02block_ip_stage2_cohort_28d.R` | 新建；加载时 source 同目录 `00ip_common.R` |
| 注册 | `R/pipeline_runner.R` → `pipeline_block_sources` | `ip_stage2_cohort_28d = b("72_.../02block_ip_stage2_cohort_28d.R")`（仅追加一行，未改旧映射） |
| 测试 | `tests/test_ip_stage2_28d.R` | 截尾向量 + 假队列 + 规则 C + locked 回退 + d/m/yyyy + 注册 + 真数据冒烟 |
| Catalog | `docs/Blocks_catalog.md` | `python3 scripts/update_blocks_catalog.py` exit 0；MANUAL §1–§3 未改 |

---

## 3. Block 行为

消费：`ctx$data$imputed`（空则 `locked` / `cleaned`）；`config$ip_two_stage$prognosis_path`；并键默认 `ID` ↔ `subject_id`。

产出：

- 筛 `Disease==1`（否则 `Acute_Renal_Failure`）后并预后 CSV
- 规则 C：`aki_time` 有非缺失 → t0=aki_time（行内缺失回退 icu_intime），`ctx$results$ip_stage2_timezero_source = "aki_onset"`；否则 `"icu_intime"`
- `t` = `dead_time`（存活则 `disch_time`/`icu_outtime`）− t0（天）；`ip_admin_censor_28`
- `ctx$data$stage2` 并覆写 `imputed`（供后续 Cox/KM 读同一分析集）
- `project$study_type = "prognosis"`；`data$outcome_column` / `survival$time_var`/`event_var` → `fustatus` / `futime`

---

## 4. 测试摘要

命令：

```bash
cd /mnt/e/01block/01Block-new-Final
"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" tests/test_ip_stage2_28d.R
```

| 阶段 | 结果 |
|------|------|
| RED | `Error: exists("ip_admin_censor_28", mode = "function") is not TRUE` |
| GREEN | `OK censor logic` + `OK test_ip_stage2_28d` + `real-data smoke: n_AKI=110 stage2=110 events=24 timezero=icu_intime` |

回归：`tests/test_ip_cohort_sle_aki.R` 仍 `OK`（analytic=270, n_AKI=110）。

假数据：截尾向量 (10,40,28,5)×(1,1,0,0)→fustatus (1,0,0,0) / futime (10,28,28,5)；5 人 Stage1 → 3 AKI；无 `aki_time` → `icu_intime`；有 `aki_time` → `aki_onset` 且随访相对 AKI 起算；`locked` 回退；MIMIC `d/m/yyyy` 解析。

---

## 5. Catalog

- 脚本 exit OK；新 `register_block` id：`ip_stage2_cohort_28d`（415 blocks）
- AUTO 卡片用途行已是 purpose
- MANUAL §1/§2/§3 未改（套路 template 属 Task 7）
- `00ip_common.R` 无 `register_block`；`index_code_bundle` 会按同目录 `00*common` 一并拷贝

---

## 6. Concerns / 待后续确认

1. **真数据无 `aki_time`**：冒烟 t0=`icu_intime`（Task 1 已预期）；规则 C 的 `aki_onset` 分支仅假数据覆盖。
2. **`is_dead` 为 1 或 NA**（不是 0）：`ip_admin_censor_28` 把 NA dead 视为 0。
3. **存活者截在出院**：无死亡时用 `disch_time`/`icu_outtime`，属院内随访；spec §4.4 要求脚注偏倚（Task 7 config / image_information）。
4. **28d 事件偏少**：110 AKI 中 24 例 28 天死亡，后续 Cox/亚组可能不稳。
5. **覆写 `imputed`**：Stage2 之后分析集变为 AKI 子集；worker 须先完成 Stage1 导出再切阶段。
6. **未改旧课题 config**；未 git commit。

---

## 7. 自检清单

- [x] 失败测试先跑（`ip_admin_censor_28` 未定义）
- [x] `ip_admin_censor_28` 在 `00ip_common.R`；block 与测试共用
- [x] `register_block("ip_stage2_cohort_28d", ...)` + `pipeline_block_sources` 一行
- [x] 测试 PASS（假数据 + 真数据冒烟）；Task 3 回归 PASS
- [x] catalog 脚本 OK
- [x] 无 git commit
- [x] 本 report 已写入 `.superpowers/sdd/task-4-report.md`
