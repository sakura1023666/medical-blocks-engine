### Task 9: 回归与收尾

- [ ] **Step 1: Run**

```bash
Rscript tests/test_pub_figure_onplot_annotations.R
Rscript tests/test_pub_figure_export.R
Rscript tests/test_pub_figure_profile_gate.R
```

Expected: 全部 OK

- [ ] **Step 2: Spec coverage 自检**（§5–§8 逐项）

- [ ] **Step 3: 用户要求时统一 commit**（见下方命令）

```bash
git add \
  R/pub_figure_export.R \
  Blocks/15_rcs/01block_rcs_prognosis.R \
  Blocks/15_rcs/02block_rcs_incidence.R \
  Blocks/15_rcs/03block_rcs_nhanes.R \
  Blocks/15_rcs/04block_rcs_iptw_weighted.R \
  Blocks/27_KM/01block_km_binary.R \
  Blocks/27_KM/02block_km_strata.R \
  .cursor/rules/pub_figure_image_information.mdc \
  tests/test_pub_figure_export.R \
  tests/test_pub_figure_onplot_annotations.R \
  docs/superpowers/specs/2026-08-26-pub-figure-onplot-annotations-design.md \
  docs/superpowers/plans/2026-08-26-pub-figure-onplot-annotations.md
git commit -m "$(cat <<'EOF'
feat(pub-figure): require on-plot annotations in image_information

Persist RCS/KM panel stats, harvest into figure md, and document the global rule.
EOF
)"
```

---

