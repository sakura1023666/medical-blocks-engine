---
name: pub-qc-after-project
description: >-
  Post-project publication QC (C档): after batch/pub finalize, review ONLY
  【success】 indices/units (skip 【failed】 and bare by_index names); check
  Tables/Figures for structure, cross-number consistency, Agent logic, then
  Layer D nature-statistics + nature-figure (fix all P0); write reports/pub_qc_*.md
  and reports/nature_*_qc_*.md with PASS/WARN/FAIL. Use when the user says 质控,
  审图表, 数字是否一致, 逻辑是否通顺, 跑完了审一下, pub QC, after-project QC,
  nature-statistics, nature-figure, or when pipeline-foundation Phase 6 fires.
  Do NOT invent numbers; cite paths.
---

# 项目发表质控（跑完立刻挂接）

> 深度：**C**（结构 + 交叉数字 + Agent 读图读表）  
> 挂点：`pipeline-foundation` **Phase 6**（发表收口之后）  
> 铁律：未写出 `reports/pub_qc_*.md` 并给出总评前，**不得宣称项目交付完成**  
> **只审成功指标**：仅 `by_index/【success】*` / `by_unit/【success】*`（及其 Tables/Figures）  
> **默认不对历史目录主动审阅**；仅当用户给出项目根路径（或刚跑完的产出目录）时执行。

配套清单：[checklist.md](checklist.md) · 报告模板：[report-template.md](report-template.md)  
引擎入口总表：[`run/pub/README.md`](../../../run/pub/README.md)

### 引擎自动骨架（勿课题复制）

1. CLI：`Rscript run/pub/run_pub_qc_after_project.R --project <根>`  
2. 函数：`R/pub_qc_after_finalize.R` → `pub_qc_run_after_project()`（已挂 `run_pipeline` / dual-batch finalize / TST summary）  
3. 结构层会 WARN：四目录缺口、image_information 缺段、**xlsx/图注含下划线**  
4. Agent 必须再跑 nature-statistics + nature-figure 并修清全部 P0

---

## 范围铁律（成功指标 only）

| 审 | 不审 |
|----|------|
| `by_index/【success】INDEX/` | `by_index/【failed】*` |
| `by_unit/【success】UNIT/` | `by_unit/【failed】*` |
| 上述目录下的 `Tables/` `Figures/` `code/` | 裸名 `by_index/INDEX/`（未改名为 success） |
| 项目根仅作入口；根 `Tables/` 汇总表可附带对照，**不以失败单元为主审对象** | checkpoints / logs / `_shared` 中间产物（除非核对 Fig1 attrition 必需） |

- 默认 `scope = all_success`：扫齐所有 `【success】` 目录。  
- 用户指定 `--index NLR` 时：只审 `【success】NLR`（或等价 success 目录）；若该指标只有 `【failed】` 或裸名 → **跳过并 WARN「无成功产物可审」**，不审失败目录。  
- **零个 success**：报告总评 **FAIL**（或 WARN：无可发表成功单元），说明失败数，**禁止**改去审 failed 充数。

---

## 何时调用

- 用户说：质控 / 审图表 / 数字一致 / 逻辑通顺 / 跑完审一下  
- 标准路径跑完 Phase 5（`--shared-only` → workers → 四目录收口）之后  
- 用户 `@` 某个 `02block_result/...` 项目根并要求质控  

**不要**：用户只是举例路径、或明确说「先完善系统不要审项目」时，去打开该目录做审阅。

---

## 输入

| 参数 | 说明 |
|------|------|
| `project_root` | 课题产出根 |
| `scope` | 默认 `all_success`；或单个成功指标名（须能解析到 `【success】*`） |
| `routine`（可选） | incidence / survival / trajectory / ipw / ml / tst … 启用专项清单 |

路径兼容：`\\192.168.68.133\02block_result\...` ↔ `/mnt/g/02block_result/...`

---

## 执行步骤（不可跳）

### 1. 定审阅对象（先过滤成功）
1. 枚举 `by_index/【success】*` 与 `by_unit/【success】*`（两者都有时优先 `by_index` 发表根，unit 作核对）。  
2. **忽略**一切 `【failed】*`、裸名指标目录。  
3. 多指标默认审全部 success；指标很多时可问「全部 success / TopN / 单指标」，但候选池仍只能是 success。  
4. 聊天里先报：  
   - success 列表（将审）  
   - failed 个数（只报数，不审）  
   再开始查。

### 2. Layer A — 结构（可脚本辅助）
对**每个 success 目录**按 [checklist.md](checklist.md) §A。至少检查：
- `Figures/` 是否 `pdf|png|tiff|image_information` 四目录；根目录无平铺 `Figure*.pdf`  
- 每张 pdf 有对应 png/tiff；tiff 非 0 字节  
- 每张定稿图有 `image_information/*.md`，且含 `## 图面说明` / `## 分析上下文`（无「标识」「技术」）  
- Tables 文件名与表内标题角色一致；双库同角色同号（若双库）  
- 适用时：该 success 下 `code/` 包存在  

可选：`python3 scripts/pub_qc_inventory.py --root <project_root> --success-only`（把 stdout 贴进报告附录）。

### 3. Layer B — 交叉数字
仅在 success 单元内对照。按 checklist §B。**只引用可收获来源**。禁止编造。

核心对照（有则查，无则记「未收获」）：
- Fig1 逐步 n ↔ `Flowchart_attrition*.csv`  
- Table1 分析集 N ↔ Fig1 最终保留 n / `_batch_status`  
- 主表效应量（OR/HR）↔ 森林 Overall / KM 注释（同口径）  
- RCS/KM：P-overall、P-nonlinear、Log-rank、cutoff ↔ `image_information` 与源产物  
- 双库拼图：两侧 N、切点、暴露对比口径一致  

不一致 → **FAIL**（数字）或 **WARN**（口径需人工确认）。

### 4. Layer C — Agent 逻辑审阅
打开**该 success** 的代表性表与图：
- 参照组 / 病例组是否反了  
- 文件名 vs A1 标题 vs 图题是否同号同义  
- 中介未显著却残留实验室关联表（门控铁律）  
- 脚注是否解释 Firth‡ / 权重 / 分母  
- 亚组：年龄二分类、全分析集最高 vs 最低（双库一致）  
- 「读起来不通」的跳跃结论 → 记 P0/P1/P2，不擅自改表  

### 5. Layer D — Nature 统计与配图（强制，修 P0）

严格按项目规则 `nature_pub_qc_after_project` 与下列 skill：

| Skill | 路径 |
|-------|------|
| nature-statistics | `.cursor/skills/nature-statistics/SKILL.md` |
| nature-figure | `.cursor/skills/nature-figure/SKILL.md` |
| nature-shared | `.cursor/skills/nature-shared/`（依赖） |

1. 对同一批 success / `summary_results` 跑 **statistics audit** + **figure audit**。  
2. 落盘 `reports/nature_statistics_qc_YYYY-MM-DD.md` 与 `reports/nature_figure_qc_YYYY-MM-DD.md`（或并入 `pub_qc_*.md` 专节，P0 清单须可检索）。  
3. **凡 statistics 标为 P0，或 figure 侧 `FIX BEFORE DELIVERY` / FAIL** → **当场修改并复检**，清零后方可 PASS。  
4. P1/P2 记入报告；默认不阻塞，但须口头报条数。  
5. 改图后必须再跑四目录导出（`pub_figure_ensure_formats`）。  

未完成 Layer D 或仍有未处理 P0 → **总评不得 PASS**，且不得宣称项目交付完成。

### 6. 落盘与口头结论
写到项目内（创建 `reports/` 如无）：

```text
reports/pub_qc_YYYY-MM-DD.md
reports/pub_qc_YYYY-MM-DD_issues.csv   # 可选；有多条问题时必写
reports/nature_statistics_qc_YYYY-MM-DD.md
reports/nature_figure_qc_YYYY-MM-DD.md
```

报告首部必须含：

```markdown
# 发表质控报告
- 项目根：...
- 审阅结论：**PASS** | **WARN** | **FAIL**
- 是否建议交稿：是 / 否（附条件）
- 审阅范围：仅 【success】（n=…）；已跳过 【failed】（n=…）
- Nature P0：已清零 / 仍有 n 条（不得 PASS）/ 用户接受残留（注明）
```

聊天里用 **3～5 行**告诉用户总评 + 审了几个 success + FAIL/WARN/Nature-P0 条数 + 报告路径。  
**PASS**：可交稿口径（含 Nature P0 清零）；**WARN**：可交但须改列问题；**FAIL**：数字或硬结构未过，或 Nature P0 未清，禁止宣称完成。

### 7. 不做的事
- **不审 【failed】 / 裸名指标目录**（即使用户说「顺便看看失败的」→ 先确认；默认仍拒绝）  
- 不 `write.xlsx` 整表覆盖返工（须外科修复另说）  
- 不偷偷重跑全流水线「顶替质控」  
- 不修改用户未授权的历史成功项目  
- 不把质控报告写进引擎 `Blocks/`  
- **不跳过 Layer D**（除非用户明确说「不要 Nature 质控」并在回复中声明）

---

## 判定规则（总评）

| 总评 | 条件 |
|------|------|
| **FAIL** | 无任何 success 可审；或任一条 Layer A 硬伤；或 Layer B 明确数字冲突；或 Layer D 仍有未处理 P0 |
| **WARN** | 无 FAIL，但有口径不清、缺 image 数字、双库标签用词差异待确，或仅剩 Nature P1/P2 |
| **PASS** | 至少一个 success 审完；A+B 无冲突；C 无 P0；**Layer D Nature P0 已清零** |

多指标时：任一 success 的 FAIL 可拉低总评；报告中按指标分列，避免「一个挂全盘说不清」。

---

## 与地基路径的关系

```text
… → --shared-only → workers → 发表收口（Phase 5）
                              → 【Phase 6】本 skill 质控（仅 【success】）
                                   Layer A/B/C → Layer D nature-statistics + nature-figure（修 P0）
                              → 用户看到 PASS/WARN/FAIL 后才算闭环
```
