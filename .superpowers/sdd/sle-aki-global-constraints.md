# Global Constraints (SLE AKI two-stage)

- 引擎根：`/mnt/e/01block/01Block-new-Final`
- 结果根：`G:/02block_result/29_SLE/inincidence_prognosis_39003396_42304330/`（WSL `/mnt/g/...`）
- 数据：`.../data/mimic/` — baseline RData、SLE.csv、ARF.csv、mimic预后数据-all.csv；dabiao 仅核对
- R：`"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe"`
- 禁止改旧课题；禁止 Tables/Figures 写引擎仓库根
- `pub_figure$profile` 仅本套路 `"mimic_inc_prog_sle_aki"`；缺省=旧图
- Git：本仓库非 git / 仅用户要求时 commit — **跳过 commit**
- Spec：`docs/superpowers/specs/2026-08-26-sle-aki-incidence-prognosis-two-stage-design.md`
- 列审阅必须先有 `_column_review.md` 再定稿 disease_vars
- 遵循 skills/review-raw-covariate-columns/SKILL.md
