# Task brief

### Task 6: 文档与 Blocks 目录（若改了 register_block）

**Files:**
- Modify: `docs/Blocks_catalog.md` MANUAL 段（仅当新增全局约定时）— 用 `python3 scripts/update_blocks_catalog.py` 若 block 头有变
- 可选：在 `docs/Blocks_catalog.md` 手写「发表图四目录」坑位一句（MANUAL 坑点区）

- [ ] **Step 1:** 在 catalog MANUAL「发表图」相关处加一条：

> 汇总 `Figures/`（及交叉滞后 `summary_result/figure`）顶层只保留 `pdf/` `png/` `tiff/` `image_information/`；多库先拼图再导出；TIFF=LZW。

- [ ] **Step 2:** Commit docs

```bash
git add docs/Blocks_catalog.md
git commit -m "$(cat <<'EOF'
docs: note pub Figures four-directory delivery convention
EOF
)"
```

---

