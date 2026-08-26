# Task 4 Review — `ip_stage2_cohort_28d` + 单测

**Reviewer**: subagent (read-only)  
**Date**: 2026-08-26  
**Scope**: brief `task-4-brief.md` + constraints + spec §4.4（28d 截尾 / 规则 C）

## Verdict

| Gate | Result |
|------|--------|
| **Spec** | ✅ |
| **Quality** | **Approved** |

## Verification

| Check | Result | Evidence |
|-------|--------|----------|
| `ip_admin_censor_28` 公共函数 | ✅ | `00ip_common.R`：`futime=pmin(t,28)`；`fustatus=1 iff dead==1 & t≤28` |
| 28d 向量边界 | ✅ | 测试 (10,40,28,5)×(1,1,0,0)→(1,0,0,0)/(10,28,28,5)；t=28 死亡=事件；dead=NA→0 |
| 规则 C 时间零点 | ✅ | `any(aki_time)`→`coalesce(aki,icu)`+`aki_onset`；否则 `icu_intime`；假数据两分支均断言 |
| AKI 筛入 + 预后 merge | ✅ | `Disease==1`（fallback `Acute_Renal_Failure`）；`ID`↔`subject_id` |
| 随访终点 | ✅ | 死亡用 `dead_time`；存活用 `disch_time`/`icu_outtime` coalesce |
| ctx 产出 | ✅ | `stage2`+覆写 `imputed`；`study_type=prognosis`；`outcome_column`/`survival$*`→`fustatus`/`futime` |
| 注册 | ✅ | `register_block` + `pipeline_runner.R:417` 仅追加一行 |
| TDD / 真数据 | ✅ | Rscript PASS；270→110 AKI→110 stage2、24 events、t0=icu_intime |
| 无 git commit / 未改旧课题 | ✅ | 符合 global constraints |

## Critical

无。

## Important

1. **`ip_stage2_timezero_source` 仅队列级** — 列存在且部分行 `aki_time` 缺失时，元数据仍标 `aki_onset`（行内已回退 `icu_intime`）。spec 要求脚注标明混合回退；Task 7 config / image_information 需补。
2. **`hosp_survival_day` 回退锚点** — `t_days` 缺失时用院内生存天作兜底，相对 ICU 而非 AKI 起算；真数据暂无 `aki_time` 未触发，日后加列需回归或限用 `icu_intime` 模式。
3. **存活者 `futime<28`** — 符合 spec §4.4「末次随访/出院」；摘要表「未死时间=28」为简写，非实现偏差；Task 7 脚注需写清院内截尾偏倚（report §6.3 已记）。

## Strengths

- TDD 顺序正确；`00ip_common.R` 与 block/测试共用。
- 规则 C、locked 回退、`d/m/yyyy` 解析、注册、Task 3 回归均有覆盖。
- 非法 `futime` 剔除带 warning；真数据 110/110 无静默丢失。
