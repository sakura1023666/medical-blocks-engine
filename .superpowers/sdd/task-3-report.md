# Task 3 Report: `ip_cohort_sle_aki` glue block + register

**Status**: DONE  
**Date**: 2026-08-26  
**Worker**: Task 3 subagent  
**Commits**: none（global constraints / 用户明确禁止）

---

## 1. 执行摘要

已按 TDD 实现 SLE∩baseline 纳排胶水块 `ip_cohort_sle_aki`：假数据 10∩5→5 与真数据冒烟均通过。`pipeline_block_sources` 已注册；`docs/Blocks_catalog.md` AUTO 已同步。未 git commit。

TDD：先写 `tests/test_ip_cohort_sle_aki.R`，Windows Rscript 首次失败为 `exists("block_ip_cohort_sle_aki") is not TRUE`（函数未定义）；实现后 PASS。

---

## 2. 交付物

| 项 | 路径 | 说明 |
|----|------|------|
| Block | `Blocks/72_incidence_prognosis_two_stage/01block_ip_cohort_sle_aki.R` | 新建 |
| 注册 | `R/pipeline_runner.R` → `pipeline_block_sources` | `ip_cohort_sle_aki = b("72_.../01block_ip_cohort_sle_aki.R")` |
| 测试 | `tests/test_ip_cohort_sle_aki.R` | 假数据 + 注册 + 真数据冒烟 |
| data_clean 闸门 | `Blocks/02_data_clean/01block_data_clean.R` | `ip_cohort_prepared` 时用已筛 `ctx$data$raw`，不改旧课题默认 |
| Catalog | `docs/Blocks_catalog.md` | `python3 scripts/update_blocks_catalog.py` exit 0；MANUAL §1–§3 未改 |

---

## 3. Block 行为

消费 `config$ip_two_stage`：`baseline_path` / `baseline_obj`（默认 `baseline`）/ `sle_path` / `arf_path`；并键 `baseline_id_col` 默认 `ID` ↔ SLE/ARF `subject_id`。

产出：

- `ctx$data$raw`（并抄 `ctx$data$cleaned`）
- `ctx$results$ip_attrition_steps`：`step, n_in, n_out, n_excluded, reason`
- 结局列 `Acute_Renal_Failure`（已有则保留；否则按 ARF.csv 成员派生 Yes/No）、`Disease`（0/1）
- `ctx$results$ip_aki_window_note`（读 `config$ip_two_stage$aki_window_note`；空则写入默认 ICU 期 ARF/AKI 脚注）
- `ctx$results$ip_cohort_prepared = TRUE`（供 data_clean 吃现场筛入集，避免再 load 全库 65366）

纳排步：`baseline_icu` → `intersect_SLE` →（若有 Age 列）`age_ge_18`。ID 一律转字符再交集，避免 numeric/character 漏并。

---

## 4. 测试摘要

命令：

```bash
cd /mnt/e/01block/01Block-new-Final
"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" tests/test_ip_cohort_sle_aki.R
```

| 阶段 | 结果 |
|------|------|
| RED | `Error: exists("block_ip_cohort_sle_aki") is not TRUE` |
| GREEN | `OK test_ip_cohort_sle_aki` + `real-data smoke: intersect_SLE=271 analytic=270 n_AKI=110` |

假数据：10∩5→5；Age&lt;18 剔除；已有 `Acute_Renal_Failure` 不覆盖；character `subject_id` 仍能并；`pipeline_block_sources` 含本块且文件存在。

真数据（`G:/02block_result/29_SLE/.../data/mimic/`）：baseline 65366 → SLE 271 → analytic **270**（1 例 `Age=NA`，ID `12370999`）→ AKI **110**。

---

## 5. Catalog

- 脚本 exit OK；新 `register_block` id：`ip_cohort_sle_aki`
- AUTO 卡片用途行已是 purpose（非哈希横幅）
- MANUAL §1/§2/§3 未改（套路 template 属 Task 7）

---

## 6. Concerns / 待后续确认

1. **Age=NA 剔除 1 人**：brief 伪代码为 `!is.na(Age) & Age>=18`，故 271→270。若临床要保留 Age 缺失的 SLE 例，需改过滤规则（仅踢明确 &lt;18）。
2. **data_clean 闸门**：spec 顺序是本块在 `data_clean` 之前；无 `ip_cohort_prepared` 时 data_clean 会重新 load 全库。已加 gated 分支，旧课题不走该旗。
3. **AKI 时间窗**：baseline 仅 ICU 期二分类，无精确 `aki_time`；脚注走 `aki_window_note`。Stage2 规则 C 回退 `icu_intime` 仍待 Task 4。
4. **dabiao 交叉核对**：`dabiao_path` 可选；未配则只日志现场筛入。Task 1 显示 dabiao=271（含 Age=NA 那例），与 analytic 270 会差 1——Task 7 若配 dabiao_path 会打 warning。
5. **未改旧课题 config**；未 git commit。

---

## 7. 自检清单

- [x] 失败测试先跑（函数未定义）
- [x] `register_block("ip_cohort_sle_aki", ...)` + `pipeline_block_sources` 一行
- [x] 测试 PASS（假数据 + 真数据冒烟）
- [x] catalog 脚本 OK
- [x] 无 git commit
- [x] 本 report 已写入 `.superpowers/sdd/task-3-report.md`
