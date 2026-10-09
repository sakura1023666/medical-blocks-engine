# 本轮（2026-10 Nature 质控 + SA-AKI TST）复用地图

目的：分清 **引擎可复用** vs **课题私有产物**，避免「文件散落、不知有没有用」。

## 一句话

| 位置 | 之后所有项目？ |
|------|----------------|
| `01Block-new-Final/.cursor/`、`Blocks/`、`run/pub/`、`configs/templates/` | **是** — 新课题自动或拷模板用 |
| `02block_result/.../summary_results/`、`reports/` | **否** — 仅本课题投稿/审计痕迹 |
| `/tmp/nature-skills*`、`/tmp/ns.zip` | **否** — 安装残留，可删 |

---

## A. 引擎内（全项目复用）— 已就位

### A1 Nature 检查（跑完任意项目）

| 路径 | 作用 |
|------|------|
| `.cursor/skills/nature-statistics/` | 统计报告审查（P0/P1/P2） |
| `.cursor/skills/nature-figure/` | 配图审查（FAIL = P0） |
| `.cursor/skills/nature-shared/` | 两 skill 依赖 |
| `.cursor/rules/nature_pub_qc_after_project.mdc` | `alwaysApply`：跑完强制 Layer D，修 P0 |
| `.cursor/skills/pub-qc-after-project/` | 结构/数字/逻辑 + **Layer D** 挂接 |
| `.cursor/skills/pipeline-foundation/` | Phase 6 含 Nature P0 |

个人机副本（跨仓库 Cursor 会话）：`~/.cursor/skills/nature-{figure,statistics,shared}/`  
与项目内目录应保持同步；以 **项目仓库** 为准做版本管理。

### A2 发表手术刀 / 版本采集

| 路径 | 作用 |
|------|------|
| `run/pub/surgical_xlsx_repair.R` | 改表脚注不毁三线样式（本轮 Table2/3 用过） |
| `run/pub/collect_software_versions.py` | 采集 Python/R 版本 → 课题 `Software_versions_for_submission.txt` |
| `configs/templates/Software_versions_for_submission.template.txt` | 版本清单模板 |
| `configs/templates/H1_Methods_P0_author_adjudication.template.md` | Methods/H1 作者裁决模板（与 Nature 表图 P0 双轨） |

### A3 TST 补充表图脚本

| 路径 | 作用 |
|------|------|
| `Blocks/71_two_stage_transformer_stroke/scripts/add_pub_supplements_midterm.py` | 只增不改：校准/DCA/NRI/外验分层等 S3–S7 + Fig S8–S11 |
| `Blocks/71_two_stage_transformer_stroke/scripts/README.md` | 已登记用法 |

新 TST 课题：改 `--project-root` 复用；勿在 `02block_result` 下另存一份引擎脚本。

### A4 计划文档（查阅，非运行时）

| 路径 | 作用 |
|------|------|
| `docs/superpowers/plans/2026-09-29-saaki-tst-pub-supplements-a.md` | Plan A 设计备忘 |

---

## B. 课题私有（勿拷进引擎当「通用代码」）

课题根：  
`\\192.168.68.133\02block_result\42_AKI_spesis\two_stage_transformer_40041421_mimic_main\`

| 路径 | 性质 |
|------|------|
| `summary_results/Tables|Figures/` | 定稿投稿产物 |
| `summary_results/Software_versions_for_submission.txt` | 本课题版本快照（由 A2 脚本/模板生成） |
| `summary_results/H1_Methods_P0_author_adjudication.md` | 本课题 Methods 裁决（由模板填实） |
| `summary_results/00_Supplement_S3_S7_map.txt` | 本课题补充编号地图 |
| `reports/pub_qc_*.md`、`nature_*_qc_*.md` | 本课题质控报告 |
| 已外科改过的 Table 2/3 脚注、S8–S11 image_information | 本课题定稿内容 |

新课题：**不要**复制这些 md/xlsx；用模板 + 质控 skill 重新生成。

---

## C. 双轨 P0（写稿时勿混）

| 轨道 | 工具 | 是否改代码 |
|------|------|------------|
| Nature 表图 P0 | nature-statistics / nature-figure | 常要改表图/重导 |
| H1 Methods P0 | `H1_Methods_P0_*.template.md` | 通常只写描述 |

---

## D. 新课题最小清单

1. 跑完 → 自动遵守 `nature_pub_qc_after_project` + `pub-qc-after-project`  
2. `python run/pub/collect_software_versions.py --out <project>/summary_results/Software_versions_for_submission.txt`  
3. 需要写 Methods 时：拷贝 `configs/templates/H1_Methods_P0_author_adjudication.template.md` → 课题 `summary_results/` 填实  
4. TST 要补校准/DCA/外验层：跑 `add_pub_supplements_midterm.py`  

---

## E. 可删垃圾

```bash
rm -rf /tmp/nature-skills-staging /tmp/nature-skills-deferred.txt /tmp/ns.zip
```

不影响引擎与课题结果。
