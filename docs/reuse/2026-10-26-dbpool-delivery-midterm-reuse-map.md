# 复用地图：数据库池化交付收口 + 中期 intro 守卫（2026-10-26）

沉淀自 ACG 酶升高 BlendedLoS 多库包（`database_pooled_42151996`）对话。  
**新课题直接走引擎，勿再抄 `/tmp`、课题结果目录或对话临时稿。**

## 客户交付面（唯一）

路径：`<project_root>/summary_results/`（或指标级同名）

| 保留 | 说明 |
|------|------|
| `Figures/` | pdf / png / tiff / image_information |
| `Tables/` | 仅发表 `.xlsx` |
| `Methods_statistical_analysis.md` | 方法（含 `## Software`） |
| `Methods_software_versions.txt` | 软件版本 |
| `*中期*.pdf` | 中期 PDF（Phase 7 写出后再 prune） |

中间稿（`content.json`、`_report_dump.md`、`项目信息-中期.md`、`reports/`）进同级  
`summary_results_delivery_workspace/`，**不进客户目录**。

## 引擎正式入口（改这里）

| 能力 | 文件 | 何时跑 |
|------|------|--------|
| Methods 正文（dbpool） | `R/pub_dbpool_methods.R` → `pub_dbpool_methods_statistical_lines` | finalize |
| 发表收口 CLI | `run/pub/finalize_delivery_root.R --study-type dbpool` | Methods + 软件版本 + 四目录 + 白名单 |
| 薄封装（课题一键） | `run/dbpool/finalize_summary_delivery.R --dir …/summary_results` | 同上 + 结构 QC |
| batch 自动挂点 | `Blocks/78_database_pooling_full/09block_dbpool_batch_finalize.R` | workers/tail 末尾 |
| 定稿表图后自动挂 | `Blocks/78_database_pooling_full/scripts/finalize_easl_paper_pub.py` → `_finalize_delivery_root` | 重导 Table/Fig 后 |
| 白名单 | `R/pub_delivery_prune.R` | finalize / prune-only |
| 结构 QC + Phase7 队列 | `run/pub/run_pub_qc_after_project.R` + `R/pub_qc_after_finalize.R`（含 `summary_results`） | finalize 后 |
| 中期 PDF | `.cursor/skills/Aiya-NB004-midterm-report/engine/build_report.py`（`intro_paras`） | Nature P0 清零后 |
| 规则 | `.cursor/rules/pub_delivery_whitelist.mdc`、`nature_pub_qc_after_project.mdc`、`midterm_after_pub_qc.mdc` |

### 手工补收口（任意 dbpool 结果根）

```bash
Rscript run/dbpool/finalize_summary_delivery.R \
  --dir "/mnt/g/02block_result/.../summary_results" \
  --cohort "ACG-style enzyme elevation (ALT/AST ≥2×ULN)"
```

或：

```bash
Rscript run/pub/finalize_delivery_root.R \
  --dir ".../summary_results" --study-type dbpool
```

## 本对话「有用 vs 没用」

### 已进引擎（下一课题直接复用）

- `R/pub_dbpool_methods.R`
- `run/dbpool/finalize_summary_delivery.R`
- `run/pub/finalize_delivery_root.R`（`--study-type dbpool` 分支）
- `Blocks/78_database_pooling_full/09block_dbpool_batch_finalize.R`
- `Blocks/78_database_pooling_full/scripts/finalize_easl_paper_pub.py`（末尾 delivery hook）
- `R/pub_qc_after_finalize.R`（Phase7 队列含 `summary_results`）
- `.cursor/skills/Aiya-NB004-midterm-report/engine/build_report.py`（`intro_paras` + build 自检）

### 课题/文献重建工具（留在 Block scripts，换病可改参调用，勿复制到 /tmp）

- `rebuild_table_s1_allyn.py` / `rebuild_table_s2_moesm2.py` / `rebuild_table2_only.py` / `rebuild_table3_only.py`
- `freeze_liver_acg.py` / `prepare_liver_acg_blendedlos.py`（ACG 门控定义）
- `eval_liver_paper_ci.py`

### 不要当源码（一次性 / 过期）

| 路径 | 说明 |
|------|------|
| `/tmp/finalize_easl_paper_pub.py`（~542 行） | **旧副本**；正式版在 Blocks（~1666 行） |
| `/tmp/acg_midterm_pub/` | 中期合成工作区；交付 PDF 已在 G 盘 `summary_results` |
| `/tmp/dbpool_*.log`、`/tmp/run_dbpool_experiment.py` 等 | 调试日志/草稿 |
| `summary_results_delivery_workspace/` | 交付修剪归档，不是第二套引擎 |
| 课题根以外手改的 skill 副本 | 以仓库 `.cursor/skills/Aiya-NB004-midterm-report/` 为准 |

## 中期 intro 一字竖排（已修，禁止再犯）

根因：`content.json` 的 `intro` 是字符串时，`for p in intro` 会按**字符**迭代。  
铁律：渲染必须 `intro_paras()`；build 启动自检；≥8 个单字段直接 `sys.exit`。

## 新课题检查

- [ ] 收口走 `finalize_delivery_root --study-type dbpool` 或 `run/dbpool/finalize_summary_delivery.R`
- [ ] `summary_results` 根目录仅白名单五项
- [ ] 未从 `/tmp` 抄 finalize / prune / Methods
- [ ] 中期用仓库内 Aiya-NB004 引擎；`intro` 可为字符串或段落数组
- [ ] Nature P0 清零后再出中期，出完再 `--prune-only`

## 反例

- 把 `/tmp/finalize_easl_paper_pub.py` 当定稿脚本
- 交付目录留 `content.json` / `reports/`
- 中期引擎绕过 `intro_paras` 再写 `for p in ch["intro"]`
