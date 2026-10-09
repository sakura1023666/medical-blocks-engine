### Task 6: 新建 Block `modality_discordance_profile`

**Files:**
- Create: `Blocks/75_osteo_dxa_qct/03block_modality_discordance_profile.R`
- Modify: `tests/test_osteo_dxa_qct_blocks.R`

**Interfaces:**
- Consumes: `discordance_group` + 协变量列（复用 baseline 统计：连续 mean±SD / 分类 n(%)）
- Config: `config$modality_discordance_profile = list(enable=TRUE, group_var="discordance_group", exclude_vars=c("SampleID"))`
- Produces: Table S5 xlsx；`ctx$results$modality_discordance_profile`
- register_block: `"modality_discordance_profile"`

- [ ] **Step 1: 单测 — 四组水平齐全时 n 之和=208（用真实 dabiao 若存在）**

```r
load("/mnt/g/02block_result/10_osteoporosis/personalized/data/harmonized/D01_osteo_personalized.RData")
stopifnot(all(c("Both_OP","QCT_only_OP","DXA_only_OP","Neither_OP") %in% dabiao$discordance_group))
stopifnot(sum(dabiao$discordance_group == "QCT_only_OP") == 40L)
```

- [ ] **Step 2: 实现 block**

优先调用引擎已有 table1 工具函数（若可 `gtsummary` by=`discordance_group`）；否则手写汇总表。表注写：QCT_only 骨折例数。

- [ ] **Step 3: Run 单测 Expected PASS**

---

