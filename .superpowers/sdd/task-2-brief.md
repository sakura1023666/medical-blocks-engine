### Task 2: 指标库审计与补缺

**Files:**
- Modify: `Blocks/00_index/01block_index.R`（仅追加缺失 `list(name=...)`）
- Create: `G:/02block_result/29_SLE/.../data/_index_coverage.md`

**Interfaces:**
- Consumes: `01block_index.R` 内公式列表
- Produces: 本课题 `index$only` 推荐向量（覆盖文献+库内可算）

- [ ] **Step 1: 列出已有 vs 文献目标**

```bash
"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" -e '
f <- "/mnt/e/01block/01Block-new-Final/Blocks/00_index/01block_index.R"
tx <- readLines(f)
nms <- unique(sub(".*name\\s*=\\s*\"([^\"]+)\".*", "\\1", grep("name\\s*=\\s*\"", tx, value=TRUE)))
# crude; prefer parsing list(name=
want <- c("CONUT_score","PNI","GNRI","NLR","SII","SIRI","SIS","LMR","BMI","PLR","MLR","CAR","PIV","AGR","SIIR")
cat("have:\n"); print(intersect(want, nms))
cat("missing:\n"); print(setdiff(want, nms))
writeLines(c("## have", intersect(want, nms), "", "## missing", setdiff(want, nms), "", "## all_in_block", sort(nms)),
  "G:/02block_result/29_SLE/inincidence_prognosis_39003396_42304330/data/_index_coverage.md")
'
```

- [ ] **Step 2: 对 missing 追加公式**

在 `01block_index.R` 公式列表末尾按现有风格追加（示例 SIS / LMR，若 Step1 显示缺失）：

```r
list(name = "SIS",
     expr = quote( /* 按文献: 低白蛋白/淋巴细胞/肿瘤等计分；若成分不足则 skip */ ),
     digits = 4L),
list(name = "LMR",
     expr = quote(Lymphocytes / Monocyte),
     digits = 4L)
```

实现时：每个 missing 指标查文献定义；成分列不存在则依赖 index 块「自动跳过」行为，不改跳过逻辑。

- [ ] **Step 3: 冒烟——对 dabiao 子集跑 index 公式可用性**

用临时 R 加载 dabiao，source index 内部公式函数（或跑最小 pipeline `--only index`），确认 `computed_indices` 非空。

---
