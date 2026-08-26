### Task 4: 启动 10 路批量并确认调度

**Files:**
- Touch: `…/by_index/`, `…/checkpoints/`, `…/logs/`（由引擎创建）

**Interfaces:**
- Consumes: Task 1–3 产物
- Produces: 后台批处理进程；日志出现 worker / index 调度

- [ ] **Step 1: 启动批处理（后台，长跑）**

```bash
export MEDICAL_BLOCKS_ROOT=/mnt/e/01block/01Block-new-Final
cd "$MEDICAL_BLOCKS_ROOT"
nohup Rscript run/ml/run_ml_dual_batch.R \
  --config "/mnt/g/02block_result/27_eclampsia/small sample prediction_39780007/config.R" \
  --workers 10 --db nhanes \
  > "/mnt/g/02block_result/27_eclampsia/small sample prediction_39780007/logs/batch_$(date +%Y%m%d_%H%M%S).log" 2>&1 &
echo $!
```

若入口自动转 Windows Rscript，保持同一参数即可。

- [ ] **Step 2: 确认启动**

```bash
# 日志出现 config 加载 / workers=10 / 指标列表或首批 index 开始
tail -n 40 "/mnt/g/02block_result/27_eclampsia/small sample prediction_39780007/logs/"*.log | tail -40
ls "/mnt/g/02block_result/27_eclampsia/small sample prediction_39780007/by_index" 2>/dev/null | head
```

Expected: 进程存活；日志无立刻 FATAL；`by_index` 或 checkpoints 开始出现产物。

- [ ] **Step 3: 向用户报告**

回报：日志路径、PID、已排队/已出现的指标数；说明整批为长跑，可断点续跑（`skip_existing=TRUE`）。

---

## Spec coverage check

| Spec 项 | Task |
|---------|------|
| D04 合并 n=4756 / events=482 | Task 1 |
| `_column_review` + disease_vars | Task 2 |
| 六模型 / age 35 / index_group=all / logistic | Task 3 |
| workers 10 启动 | Task 4 |
| 不做 all_vars / cox / 额外模型 | Global Constraints |

## Placeholder scan

无 TBD；config 中 `disease_vars` 由 Task 2 实填，不可留注释占位上线。
