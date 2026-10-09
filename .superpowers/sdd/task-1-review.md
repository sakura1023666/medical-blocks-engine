# Task 1 审查报告

**审查日期：** 2026-09-20  
**范围：** Spec 符合性 + 实现质量（只读）  
**依据：** `task-1-brief.md`、`task-1-report.md`、`task-1-review-package.md`；独立核对 UNC `C01_MI_baseline.R`、`C01_MI_baseline.fixed.R`、`task-1-column-map.md`、`task-1-probe.rds`

---

## 1) Spec 符合性

**Verdict: ✅**

| Brief 项 | 状态 | 证据 |
|----------|------|------|
| Step 1：1st 三处 `load_one` 改为 `*2` RData | ✅ | UNC `03*\C01_MI_baseline.R` L115–123 已为 `D10_C_SSRS2` / `D07_HAMA2` / `D08_HAMD2`；与 `C01_MI_baseline.fixed.R` 一致 |
| Index 侧仍用 `*1` 文件 | ✅ | `C_SSRS1`/`HAMA1`/`HAMD1` 未改 |
| Step 2：grep 探测 Index/1st 列名并文档化 | ✅ | `task-1-column-map.md` + `task-1-probe.rds` 与 brief 正则一致 |
| Step 3：`digest` Index≠1st | ✅ | `probe_rdata_columns.R` 含三对检查；RDS 六列名与 map 一致（未重跑全探测） |
| Task 2 列名 verbatim | ✅ | 六节点表含 `HAMA_intex_all` 拼写保留、CSSRS item1 两列、severity 排除说明 |
| 全局：不跑全分析 | ✅ | 报告明确；审查未触发流水线 |
| 全局：无 git commit | ✅ | 符合 |
| 引擎侧备份 | ✅（等价交付） | Brief 允许 prep 头注释；实际交付 `C01_MI_baseline.fixed.R` + `fix_c01_baseline.ps1`，可接受 |

**Missing（相对 brief 字面）：**

- 无：`stopifnot(digest(...))` **写入** UNC `C01_MI_baseline.R`（brief Step 3 为验证步骤，已在探测脚本完成，非必须落盘 C01）。

**Extra（未要求但合理）：**

- `probe_rdata_columns.R`、`task-1-probe.rds`、`rdata_probe/` 六文件副本、`fix_c01_baseline.ps1` — 可复现、利于 Task 2，不违背约束。

**与设计 spec §3.1–3.2 对齐：** 1st 文件指向与六节点列名与设计文档一致（C-SSRS 仅 Ideation item1；HAMA `intex` 保留）。

---

## 2) Task 质量

**Verdict: Approved**

实现目标清晰、UNC 修改已现场复读确认、列名有机器可读 + 人类可读双产物，Task 2 可直接引用 `task-1-column-map.md`。

---

## 3) 发现项

### Critical

- 无。

### Important

- **无。**（UNC 修复与列名探测结论经独立核对成立。）

### Minor

1. **`probe_rdata_columns.R` 缺包时 `install.packages("digest")`** — 在离线/锁定环境可能失败或产生非预期副作用；Task 2+ 宜改为 `requireNamespace` + 明确报错，或文档声明依赖。
2. **`task-1-column-map.md` 未记 C-SSRS item1 取值编码** — 设计 spec 为 Yes=1 / No=0；Task 1 只要求列名，但 Task 2 prep 仍需在 dabiao 阶段核对实际水平（是否已是 0/1、是否有字符 Yes/No）。
3. **C01 无回归防护** — `digest` 断言仅在探测脚本；未来若再误改 `*1`/`*2`，QC 脚本本身不会自失败；可选在 C01 加载后加轻量 `stopifnot`（非 Task 1 硬性要求）。
4. **`fix_c01_baseline.ps1` 全文件 `Set-Content`** — 报告已记录编码迭代；中文注释在 PowerShell 输出中显示乱码可能是控制台编码，建议在下次动 UNC 时用 diff/备份比对，确认 R 源文件 UTF-8 可读。
5. **`id_col_candidates`  grep 过宽** — 会把 `C_SSRS_Ideation_*` 误列为 ID 候选；不影响 map 中已锁定的 `新编号`。

---

## 4) 审查者执行的核对

- PowerShell 读取 UNC `C01_MI_baseline.R` Skip 113 / 12 行：三处 `*2` 文件名正确。
- `readRDS("task-1-probe.rds")`：`ideation_or_all` 与 `task-1-column-map.md` grep 列表一致。

---

## 5) 总结

Task 1 满足 brief 三步与全局约束；产物足以支撑 Task 2 prep。**Spec ✅；质量 Approved。**
