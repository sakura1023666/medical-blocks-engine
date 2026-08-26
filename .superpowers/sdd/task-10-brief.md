### Task 10: 全量并行 + 验收清单

**Files:** 无新代码；产出在结果根

- [ ] **Step 1: 全指标 batch**

```bash
"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" \
  run/sle_aki_inc_prog/run_sle_aki_inc_prog_batch.R \
  --config "G:/02block_result/29_SLE/inincidence_prognosis_39003396_42304330/config_sle_aki_inc_prog_batch.R" \
  --workers auto
```

- [ ] **Step 2: 勾选验收**

| 检查项 | 通过标准 |
|--------|----------|
| 15 步 | 决策树与产出一一对应 |
| Fig1 | 逐步 n + 排除人数 |
| Table1 ×2 | 发病/预后各一 |
| ROC ×2 | 有 AUC 表 |
| RCS + threshold + segmented | 文件存在 |
| KM + Cox | 28 天截尾脚注 |
| 旧课题 | 抽一旧 incidence config，`profile` 空，图逻辑无回归 |
| 落盘 | 引擎根无本课题 Tables/Figures |

- [ ] **Step 3: `update-blocks-catalog` skill** 更新 `docs/Blocks_catalog.md`（新 72 块）

---
