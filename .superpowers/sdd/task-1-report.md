# Task 1 Report: 文献切块 + 对抗阅读（门控）

**Status:** DONE  
**Date:** 2026-10-09  
**Paper:** Jin et al. 2026 *Breast Cancer Research and Treatment* — PMRT × IPW/STEPP（`用药模型三分.pdf`）  
**paper_id:** `yaoyong_moxing_sanfen`  
**Commits:** none（工作区非 git 仓库）

---

## 地基判定（门控一句话）

**地基 = 预后 + IPW；暴露映射：放疗 → 阿替普酶；结局映射：OS → 28 天死亡。**

目标迁移：PE 队列；暴露=alteplase yes/no；结局=28-day mortality；双库 MIMIC+eICU。  
**等用户点头后再开 Task 3 写 config。**

---

## Step 1: PDF chunks

| 项 | 值 |
|---|---|
| 输入 | `adversarial_lit_reading/papers/用药模型三分.pdf` |
| 输出 | `adversarial_lit_reading/chunks/yaoyong_moxing_sanfen.md` |
| 页数 / 字符 | 10 页 / ~35,493 字符 |
| 说明 | 任务简报中的 `--pdf/--out-dir` 与脚本实际 CLI 不一致（`pdf_to_chunks.py` 仅支持扫描 `papers/*.pdf` + 可选 `paper_NNN`）。为避免重编号全库 PDF，对本文件用同脚本 `extract_pages` 逻辑单独落盘稳定 id `yaoyong_moxing_sanfen`（排序号本为 paper_033）。 |

---

## Step 2: 对抗流水线（Q4 / Q5 / Q8）

每问：AI-A 建树 → `glm_call.py` 真实攻击 → 修正 → Judge JSONL → `validate_jsonl.py`。

| QID | A round1 | B attack（provenance） | A revised | labels JSONL | validate | score / 桶 |
|---|---|---|---|---|---|---|
| Q4 | `rounds/A_tree_round1_yaoyong_moxing_sanfen_Q4.md` | `B_attack_tree_…_Q4.md`（`glm_call provenance` 首行 OK；model=`deepseek-v4-flash-0731` via Anthropic） | `A_tree_round2_revised_…_Q4.md` | `labels/yaoyong_moxing_sanfen_Q4_training.jsonl` | **PASS** | 10 → train |
| Q5 | `…_Q5.md` | `…_Q5.md` provenance OK | `…_Q5.md` | `…_Q5_training.jsonl` | **PASS** | 10 → train |
| Q8 | `…_Q8.md` | `…_Q8.md` provenance OK | `…_Q8.md` | `…_Q8_training.jsonl` | **PASS** | 10 → train |

- 三条亦已追加至 `adversarial_lit_reading/labels/training.jsonl`。
- **未伪造** `B_*.md`；首次沙箱网络 403 后以 `full_network` 重试成功。
- Q1–Q3 / Q6–Q7 **未跑**（任务最低要求为 Q4/Q5/Q8）。

### 对抗摘要（要点）

- **Q4（变量/建模）：** 原文叙述为「Table 全部潜在混杂 → PS logistic → IPW」；未见 DAG/VIF/RCS/LASSO 报告（absence≠proof）。高优先修正：勿把「未见」当「未做」；Methods eleven vs Results nine selected；Fig.3 imputed vs 主分析排除缺失。
- **Q5（假设/缺失/加权）：** IPW=处理权重非 survey；加权 SMD&lt;0.1 支持平衡；未报告 PH/极端权重诊断。高优先修正：Fig.3 插补是亚组 fallback，非与完整病例「矛盾」。
- **Q8（迁移）：** IPW/SMD/敏感性双轨仅**条件性复用**；须先过暴露时间窗/immortal time、28d logistic vs Cox、双库 PS 策略。STEPP 五年绝对 OS 与肿瘤变量不适用原样；溶栓剂量/时机缺失升格高危。

---

## Step 3: 门控自检命令结果

```text
Q4 PASS ✓  train(>=8)=1
Q5 PASS ✓  train(>=8)=1
Q8 PASS ✓  train(>=8)=1
B_*.md provenance headers: all present
```

---

## Concerns

1. `pdf_to_chunks.py` CLI 与任务简报不一致；本任务用稳定自定义 `paper_id`，未重跑全库切块以免打乱既有 `paper_*` 映射。
2. `glm_call` 经 Anthropic 兼容端点，provenance 中 model 为 `deepseek-v4-flash-0731`（非字面 glm-5.1）；metadata 仍按 skill 记 `critic_model="GLM 5.1"` 通道调用。
3. 全文 chunk 未含 Supplementary；Q4/Q5 对补料中可能存在的诊断/插补细节标为未知。
4. 未跑完整 Q1–Q8；若用户要全覆盖可续跑。

---

## 产出路径清单

- Chunk: `adversarial_lit_reading/chunks/yaoyong_moxing_sanfen.md`
- Rounds A/B: `adversarial_lit_reading/rounds/A_tree_*_yaoyong_moxing_sanfen_Q{4,5,8}.md`, `B_attack_tree_yaoyong_moxing_sanfen_Q{4,5,8}.md`
- Labels: `adversarial_lit_reading/labels/yaoyong_moxing_sanfen_Q{4,5,8}_training.jsonl`
- 本报告: `.superpowers/sdd/task-1-report.md`
