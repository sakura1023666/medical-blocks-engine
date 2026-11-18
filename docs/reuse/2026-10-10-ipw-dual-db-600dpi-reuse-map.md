# 本轮（PE×alteplase IPW + 600 dpi）复用地图

目的：分清 **引擎可复用** vs **课题私有 / 一次性**，避免「文件散落、不知有没有用」。

## 一句话

| 位置 | 之后所有项目？ |
|------|----------------|
| `01Block-new-Final` 的 `Blocks/` `R/` `run/pub/` `configs/templates/` `.cursor/rules|skills` | **是** |
| `run/ipw_pe_alteplase/` 批跑 + 薄封装 + 本课题 Methods | **本课题入口**；逻辑已回写引擎 |
| `run/ipw_pe_alteplase/_archive_oneoff/` | **否** — 归档，勿拷 |
| `02block_result/47_PE/.../summary_result` `reports/` `tmp_qa/` | **否** — 投稿/审计产物 |
| `/tmp/ipw_*` `/tmp/LCI_*` | **否** — 可删 |

---

## A. 引擎内（全项目复用）— 已就位

### A1 图 DPI ≥ 600（铁律）

| 路径 | 作用 |
|------|------|
| `R/pub_figure_export.R` | 默认 dpi=600；`formats_status$bad_dpi`；路径含括号时可靠读 DPI |
| `python/pub_figure_rasterize.py` | 栅格默认 600 |
| `run/pub/rasterize_index_figures.R` | CLI 默认 600 |
| `.cursor/rules/pub_figure_three_formats.mdc` | 四目录 + 600 dpi |
| `.cursor/rules/nature_pub_qc_after_project.mdc` | Nature 审图必检 DPI；不足=P0 |
| `.cursor/skills/nature-figure/SKILL.md` | Medical Blocks 600 dpi 专节 |
| `.cursor/skills/pub-qc-after-project/SKILL.md` | Layer A 检 DPI |

### A2 发表结构 QC（本轮补齐缺失入口）

| 路径 | 作用 |
|------|------|
| `R/pub_qc_after_finalize.R` | `pub_qc_run_after_project()` — pipeline 收尾已挂 |
| `run/pub/run_pub_qc_after_project.R` | CLI（规则/README 原先指向但文件缺失，已补） |

### A3 IPW 双库拼图 / summary_result

| 路径 | 作用 |
|------|------|
| `R/ipw_dual_db_pub.R` | `ipw_jin_role_spec` / `ipw_dual_panel_remirror` / `ipw_finalize_summary_result` |
| `Blocks/69_ipw_diabetes_stroke_full/03block_ipw_weighted_km_pub.R` | IPW log-rank：取 svylogrank **p** 非 Chisq |
| `Blocks/69_…/02block_ipw_flowchart.R` | 流程图标签跟暴露走（勿残留 Diabetes） |
| `Blocks/69_…/10block_ipw_alteplase_exposure.R` | 阿替普酶暴露派生 |
| `Blocks/18_subgroup/08block_subgroup_iptw_weighted.R` | 预后默认 HR；退化层 NE；caption 可配 |
| `configs/templates/config_ipw_pe_alteplase_dual_batch.template.R` | 双库 IPW 模板 |

### A4 新 IPW 双库课题怎么用

1. 拷模板改暴露/结局/路径 → `--shared-only` → workers  
2. `ipw_dual_panel_remirror(project, role_spec = ipw_jin_role_spec(exposure_lab=…))`  
3. `ipw_finalize_summary_result(project, methods_lines=…)`  
4. `Rscript run/pub/run_pub_qc_after_project.R --project …` + Nature Layer D  

禁止：在结果目录再写 `hotfix_remirror_*.R`；禁止依赖 `/tmp` 脚本。

---

## B. 课题私有（勿当通用代码）

课题根：`/mnt/g/02block_result/47_PE/Medication_regimen_model_alteplase_ipw/`

| 路径 | 说明 |
|------|------|
| `summary_result/` | 定稿表图 + Methods |
| `reports/pub_qc_*.md` `nature_*_qc_*.md` | 本课题质控痕迹 |
| `scripts/assemble_pe_alteplase_analysis.R` | 数据组装（课题） |
| `tmp_qa/` | 目视 QA 截图，可删或留档，不进引擎 |
| `config_ipw_pe_alteplase_*.R` | 本课题 config |

---

## C. 本轮已清理

| 原位置 | 处理 |
|--------|------|
| `run/ipw_pe_alteplase/repair_*.R` `rerun_*.R` `restore_*.R` | → `_archive_oneoff/` |
| `remirror_*.R` `finalize_*.R` 大段逻辑 | → `R/ipw_dual_db_pub.R`；脚本变薄封装 |
| 规则写的 QC CLI 缺失 | → 已补 `run/pub/run_pub_qc_after_project.R` |

---

## D. 个人机 skill 副本

`~/.cursor/skills/nature-figure/` 已同步 600 dpi 专节与 `validate_figure.py` FAIL&lt;600。  
版本以 **项目仓库** `.cursor/skills/` 为准。
