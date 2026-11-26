# 复用地图：数据库池化交付收口 + Times/禁下划线 + 中期（2026-10-26；2026-11-16 收口）

沉淀自 ACG / ULN-all3 BlendedLoS 多库包对话。  
**新课题直接走引擎，勿抄 `/tmp`、结果目录或对话临时稿。**

规则（alwaysApply）：`.cursor/rules/dbpool_pub_reuse.mdc`

---

## 客户交付面（唯一）

路径：`<project_root>/summary_results/`（或 `summary_results_uln_triple` 等包名）

| 保留 | 说明 |
|------|------|
| `Figures/` | `pdf/` + `image_information/`（默认不强制 png/tiff） |
| `Tables/` | 仅发表 `.xlsx` |
| `Methods_statistical_analysis.md` | 方法（含 `## Software`） |
| `Methods_software_versions.txt` | 软件版本 |
| `*中期*.pdf` | 中期 PDF（Phase 7 后再 prune） |

中间稿（`content.json`、`_report_dump.md`、`项目信息-中期.md`、`reports/`）→ 同级 `*_delivery_workspace/`。

---

## 引擎正式入口（改这里）

| 能力 | 文件 | 何时跑 |
|------|------|--------|
| Methods（t0 / ICU mortality+RLoS / 表2≠表3 / Transfer） | `R/pub_dbpool_methods.R` | finalize |
| 禁下划线 + **Times xlsx** | `python/pub_xlsx_scrub_display.py` ← `pub_delivery_scrub_display` | finalize / prune-only |
| 发表小数位 | `Blocks/78_…/scripts/dbpool_pub_digits.py` + `.cursor/rules/dbpool_pub_digits.mdc`；EASL/ICUAKI finalize 共用 | 出表 |
| Times 薄 CLI（旧调用兼容） | `R/pub_xlsx_force_times.R` → 转调 scrub `--times-only`（路径一律 `shQuote`，兼容 `summary(new)`） | 可选 |
| 字体 QC（括号文件名 OK） | `R/pub_qc_fonts.R` | pub-qc |
| 软件版本（dbpool Python modules_only） | `R/pub_software_versions.R` | finalize |
| 一键收口 | `run/dbpool/finalize_summary_delivery.R` | Methods+软件+scrub+QC+prune |
| 通用 finalize | `run/pub/finalize_delivery_root.R --study-type dbpool` | 同上核心 |
| batch 挂点 | `Blocks/78_…/09block_dbpool_batch_finalize.R` | workers 末尾 |
| 定稿表图挂点 | `Blocks/78_…/scripts/finalize_easl_paper_pub.py` | 重导后 |
| ULN 三联 pack | `Blocks/78_…/scripts/pack_uln_triple_summary.py` | 主+敏感性后调 thin finalize |
| **Table S9 特征清单 + Fig↔表数字链** | `Blocks/78_…/scripts/dbpool_feature_inventory.py` | finalize / pack 自动挂 |
| 交叉评估 | `cross_eval_ams_mimic.py` + `refresh_uln_table3_after_cross.py` | Transfer/off-diagonal |
| 中期 PDF | `.cursor/skills/Aiya-NB004-midterm-report/engine/build_report.py` | Nature P0 清零后 |
| scripts 分层说明 | `Blocks/78_…/scripts/README.md`（A 复用 / B 运维 / C 已并引擎） | — |

### 2026-11-23 本轮并入（五条裁决 → 引擎）

| 裁决 | 引擎落点 |
|------|----------|
| 敏感性=三单指标非并集 | `R/pub_dbpool_methods.R` + pack Methods 块 |
| Fig 规模扫描 ↔ Gen 表锁链 | `dbpool_feature_inventory.append_training_size_metric_lock` |
| 特征清单 Table S9 | `dbpool_feature_inventory.write_table_s9`（finalize keep 白名单含 S9） |
| 软件踢 mice/jstable、无 TCF 注 | `finalize_delivery_root` exclude + `pub_software_versions` |
| Multi-centric N=care_site | Table1 脚注模板 / pack `LIVER_TABLE1_FOOTNOTE` |

**不要当源码**：G 盘 `summary(new)/`、`summary*_delivery_workspace/`、对话一次性 `python - <<` 写表——下一课题必须走上面入口。

### 手工补收口

```bash
Rscript run/dbpool/finalize_summary_delivery.R \
  --dir "/mnt/g/02block_result/.../summary_results" \
  --cohort "ULN-all3 laboratory gate (...)" \
  --feature-set "Model covariates followed prior multi-database ICU …"
```

---

## 本对话「有用 vs 没用」

### 已进引擎（下一课题直接复用）

- `R/pub_dbpool_methods.R`、`R/pub_qc_fonts.R`、`R/pub_software_versions.R`
- `python/pub_xlsx_scrub_display.py`（Times + 禁下划线）
- `run/dbpool/finalize_summary_delivery.R`、`run/pub/finalize_delivery_root.R`（dbpool 分支）
- `Blocks/78_…/scripts/finalize_easl_paper_pub.py`、`pack_uln_triple_summary.py`、`cross_eval_ams_mimic.py`…
- `.cursor/rules/dbpool_pub_reuse.mdc`、`pub_delivery_whitelist.mdc`、`pub_times_new_roman.mdc`

### 不要当源码

| 路径 | 说明 |
|------|------|
| `/tmp/finalize_*.py`、`/tmp/*uln*` | 过期/日志 |
| 结果盘私有 `hotfix_*.R` | 一次性 |
| `summary_results_delivery_workspace/` | 修剪归档，不是第二套引擎 |
| `scripts/_archive_oneoff/` | 运维热修归档 |

---

## 检查清单

- [ ] 收口走 `run/dbpool/finalize_summary_delivery.R`
- [ ] 交付仅五件套；QC 在 workspace/reports
- [ ] Methods：文献特征集；Transfer 破折号有说明
- [ ] 表 Times + 无 `_`；图 Times 系
- [ ] Nature P0 清零 → 中期 → 再 prune
