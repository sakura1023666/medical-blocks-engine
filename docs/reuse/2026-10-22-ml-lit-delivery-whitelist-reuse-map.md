# 复用地图：ML 文献终稿 + 交付根白名单（2026-10-22）

沉淀自 AKI SAR+CrCV（MIMIC+eICU）对话。**新课题直接走引擎，勿再抄结果目录 hotfix / `/tmp` 脚本。**

## 铁律（交付面）

客户打开的 `summary_result` / `summary_results` 根目录**只留**：

| 保留 | 说明 |
|------|------|
| `Figures/` | pdf/png/tiff/image_information |
| `Tables/` | 仅发表 `.xlsx` |
| `Methods_statistical_analysis.md` | 方法（含 `## Software`） |
| `Methods_software_versions.txt` | 软件版本 |
| `*中期*.pdf` | 中期 PDF |

其余进交付根**同级** `summary_result_delivery_workspace/`（不进客户面）。

## 引擎入口（改这里）

| 能力 | 文件 |
|------|------|
| 白名单 + Tables 清非 xlsx + figure/table 改名 | `R/pub_delivery_prune.R` |
| 交付收口 CLI（主入口） | `run/pub/finalize_delivery_root.R` |
| 仅修剪（兼容别名） | `run/pub/prune_delivery_root.R` → 转调上一行 `--prune-only` |
| 发病/预后 summary 写完自动 prune | `R/incidence_summary_result.R` |
| ML 文献终稿：重编号 + Methods + sync summary + prune | `R/ml_literature_pub_finalize.R` |
| ML 指标 summary_results finalize：Methods+软件版本+白名单 | `R/ml_index_summary_results.R` → `ml_finalize_index_summary_results` |
| ML 单库交付复用地图（防课题根双份） | `docs/reuse/2026-10-23-ml-single-summary-results-delivery-reuse-map.md` |
| ML 终稿 CLI | `run/ml/finalize_ml_literature_publication.R` |
| SOSM/WPR 类 build 原子替换后自动 finalize | `run/ml/build_aki_sosm_wpr_replication.R`（末尾 `ml_lit_finalize_delivery`） |
| Cursor 规则 | `.cursor/rules/pub_delivery_whitelist.mdc` |
| 中期出完再 prune | `.cursor/skills/Aiya-NB004-midterm-report/SKILL.md` Phase 7 |

## 常用命令

```bash
# 完整交付收口（方法 + 软件版本 + 四目录 + 白名单）
Rscript run/pub/finalize_delivery_root.R --dir ".../summary_result" --study-type ml

# 只修剪
Rscript run/pub/finalize_delivery_root.R --dir ".../summary_result" --prune-only
# 或扫课题下全部 summary_result*
Rscript run/pub/finalize_delivery_root.R --project /mnt/g/02block_result/<课题> --prune-only

# ML 文献终稿（重编号填空号 → Methods → summary_result → prune）
Rscript run/ml/finalize_ml_literature_publication.R \
  --pub ".../by_index/【success】INDEX/publication_literature_final"
```

## 本对话「结果目录」改动 ≠ 引擎代码

下列只作用于 SAR+CrCV 交付产物，**不要**当成下一课题脚本复用：

- `summary_result` / `publication_literature_final` 里改过的 xlsx 脚注、image_information 措辞、中期 `content.json`
- `/tmp/sar_*`、`tmp/*sar*` 一次性重画/拆表脚本（已归档 `_archive_oneoff/sar_crcv_2026-10/`）

文献 Model1–3 统一 / 关联图返工另见：`docs/reuse/2026-10-26-ml-literature-m123-assoc-reuse-map.md`（正式入口 `run/ml/rebuild_assoc_unified_model3.R`、`run/ml/redraw_assoc_figs.R`）。

下一课题若 overall-only、去分层脚注：在**出表脚本/引擎**里改默认文案，或用 `run/pub/surgical_xlsx_repair.R` 外科改，禁止复制 `/tmp`。

## 检查清单（新课题）

- [ ] summary finalize / ML lit finalize / 中期 build 后根目录只有白名单 5 类
- [ ] 未在课题 `scripts/` 或 `/tmp` 再写 prune/hotfix
- [ ] Methods 的 Software 并进 `Methods_statistical_analysis.md`，无单独交付 `Methods_software_section.md`
- [ ] Tables 内无 `Methods_*.txt` / csv / rds（`pub_delivery_clean_tables_xlsx_only`）
