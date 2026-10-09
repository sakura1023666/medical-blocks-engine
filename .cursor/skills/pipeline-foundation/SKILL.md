---
name: pipeline-foundation
description: >-
  Medical Blocks「地基」架构：发病/预后两块地基；新套路只加法后缀。标准路径必须含
  PDF切块 → 对抗阅读(Q1–Q8) → 地基判定 → 门控 → 决策树确认 → batch → 发表收口
  → 发表质控(pub-qc-after-project)。Use when the user says 地基, 套路, 新流水线,
  文献复现, 接套路, 提示词出流水线, paper-to-routine, 对抗阅读接套路, Q1–Q8,
  IPW/轨迹/竞争风险/TST 挂哪块地基, or asks whether a prompt covers the full path.
---

# 流水线地基（Pipeline Foundation）

> 汇报口径：`docs/汇报_流水线地基与轨迹案例.md`  
> 对抗阅读：`.cursor/skills/adversarial-lit-reading/SKILL.md`（**接套路前必跑，不可跳**）  
> 发表质控：`.cursor/skills/pub-qc-after-project/SKILL.md`（**跑完立刻挂接，不可跳**）  
> 配套：`create-pipeline-config` · `run-batch-pipeline` · `review-raw-covariate-columns` ·  
> `split-medical-block` · `feishu-result-sync` · `deploy-medical-blocks-host`

---

## 标准路径（与汇报稿 mermaid 一致，不可跳步）

```text
PDF 入库切块
  → 对抗阅读（Q1–Q8：建树→GLM攻击→修正→Judge）
  → 方法能否落在某块地基？
       ├─ 能 → 3A 复制该地基模板（课题实例化）
       ├─ 地基有、后缀无 → 3B 只加方法层 Block
       └─ 连地基都对不上 → 改问题定义或确认不做
  → 写 config 前门控（列审阅 / 分层 / 查新）
  → 用户确认分析决策树
  → --shared-only → workers
  → 发表收口
  → 发表质控（结构 + 交叉数字 + Agent 逻辑 → reports/pub_qc_*.md）
```

**两棵树不要混：**

| 树 | 产出位置 | 用途 |
|----|----------|------|
| 对抗阅读证据树 | `adversarial_lit_reading/rounds/` + `labels/` | Q1–Q8 方法学理解，可训练 |
| 分析套路决策树 | `Decisiontree/decision_tree_<routine>.md` | 指导 config / pipeline / 跑批 |

对抗树 **喂给** 套路树；没有对抗阅读就写 config = 跳步，判不合格。

---

## 铁律（一句话）

系统只有 **两块地基**。新文献 = **对抗读透 → 选地基 + 加法后缀**。禁止为新病种再挖「清洗 → Table1 → VIF」。

| 地基 | 研究问题 | 主闸门 | 母版 routine |
|------|----------|--------|--------------|
| **发病** `incidence` | 指标/暴露 → 会不会发生 | Logistic Q→T→B | `config_incidence_dual_batch` |
| **预后** `survival` | 指标/暴露 → 发生后结局 | Cox Q→T→B | `config_survival_dual_batch` |

```text
地基前缀（复用）清洗 → 列对齐 → 指标 → 排除 → 插补 → Table1 → 单因素 → VIF → 多因素
方法后缀（文献多出来的）IPW / JLCM / Fine–Gray / ML / TST / STEPP …
```

---

## Agent 执行顺序（不可跳）

### Phase 0 — 文献入库
1. PDF 在 `adversarial_lit_reading/papers/`（或用户 @ 的路径）。  
2. 若无 chunk：`python3 adversarial_lit_reading/scripts/pdf_to_chunks.py`。  
3. 禁止把整篇 PDF 硬塞进上下文。

### Phase 1 — 对抗阅读（强制）
严格按 `.cursor/skills/adversarial-lit-reading/SKILL.md`：

- 默认至少跑 **Q4（变量/建模）+ Q5（假设/加权/缺失）+ Q8（可迁移到本研究）**；用户要求「完整」则 **Q1–Q8 全跑**。  
- 每问：AI-A 建树 → **真实** GLM 攻击 → AI-A 修正 → Judge JSONL → `validate_jsonl.py`。  
- 禁止伪造 `B_*.md`；glm_call 非零即停。  
- 可选：Block Extractor → `rounds/block_gap_*`（只登记缺失，不改旧 Blocks）。

### Phase 2 — 地基判定
根据对抗结论 + 用户研究问题 → 发病 or 预后；对照 `Decisiontree/` / templates / `baseline_pipelines.json`：

- **3A** 方法已有 → 复制地基模板做课题实例  
- **3B** 地基有、后缀无 → 只加方法层 Block（序号接着最大号）  
- **停** 连地基都对不上 → 先和用户改问题，禁止硬开第三块地基  

### Phase 3 — 写 config 前门控
列名对齐 → 列审阅（`review-raw-covariate-columns`）→ 可算指标池 → 分层数值 → 年龄切点 →（双复合）PubMed 查新 → **输出分析决策树，等用户确认**。

### Phase 4 — 交付件
- `Decisiontree/decision_tree_<routine>.md`（须引用对抗 reading 的 chosen 结论）  
- template + 项目 `config_*.R`（新目录，不覆盖旧 【success】）  
- `run/<routine>/run_*_batch.R` + worker  
- Blocks 复用优先；缺则新建  
- 飞书 `run/feishu/` + `feishu-result-sync`  
- 发表图/表键对照清单（文献一个不漏）

### Phase 5 — 跑批与收口
`--shared-only` → `--workers`；约定 Rscript；R 不能则 Python。成功单元四目录图 + code 包（若该套路适用）。

### Phase 6 — 发表质控（强制）
严格按 `.cursor/skills/pub-qc-after-project/SKILL.md` + 规则 `nature_pub_qc_after_project`：

- 仅对**刚交付 / 用户点名**的 `project_root` 执行；用户举例路径或说「不要审项目」则不打开审阅。  
- **只审 `【success】` 指标/单元**；跳过全部 `【failed】` 与裸名目录。  
- Layer A 结构 → Layer B 交叉数字 → Layer C Agent 逻辑 → **Layer D `nature-statistics` + `nature-figure`（P0 必须修完）**。  
- 落盘 `reports/pub_qc_YYYY-MM-DD.md` 与 `reports/nature_*_qc_*.md`，口头给出 **PASS / WARN / FAIL**。  
- **未出质控报告、或 Nature P0 未清零前不得宣称项目完成。**

---

## 复用优先（反例）

| ✅ | ❌ |
|----|----|
| 先对抗阅读再写 config | 跳过 Q1–Q8 直接抄 Methods 写 pipeline |
| IPW → 预后地基 + `69_ipw_*` | 再写一套 Table1/VIF |
| 轨迹 → 预后地基 + `53_*` | 把轨迹叫成第三块地基 |
| 伪造 GLM 攻击 | 一律 FAIL |

---

## 怎么判断挂哪块地基

| 用户说法 | 地基 |
|----------|------|
| 发病风险、OR、病例对照 | **发病** |
| 28 天死亡、HR、KM | **预后** |
| IPW + 死亡结局 | **预后** + IPW 后缀 |
| 轨迹再预测死亡 | **预后** + 轨迹后缀 |
| 竞争风险 | **预后** + competing 后缀 |

---

## 提示词

完整可复制版：[prompt-template.md](prompt-template.md)（**已含对抗阅读硬段**）。

短自检：若提示词里没有「PDF 切块 / 对抗阅读 Q1–Q8 / GLM 真实攻击 / 发表质控」，**不能**声称覆盖完整标准路径。

---

## 案例速查

| 案例 | 地基 | 后缀 | 入口 |
|------|------|------|------|
| 心衰轨迹 JLCM | 预后 | `trajectory_*` | `run/trajectory_prognosis/` |
| 糖尿病×卒中 IPW | 预后 | `69_ipw_*` | `run/ipw_diabetes_stroke/` |
| 双库发病批量 | 发病本身 | Logistic/RCS/亚组/中介 | `run/incidence/` |
