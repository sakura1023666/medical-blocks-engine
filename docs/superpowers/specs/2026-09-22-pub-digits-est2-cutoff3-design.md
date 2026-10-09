# 发表数字口径引擎默认调整（est=2 / cutoff=3 / 千分位）

## 目标

全套路（发病 / 预后 / ML / 中介 / 亚组等）SCI 表与森林图共用同一套发表数字默认：

| 字段 | 新默认 | 用途 |
|------|--------|------|
| `est` | **2** | OR / HR / RR 及其 95%CI 上下限 |
| `p` | **3** | P 值（`<0.001`） |
| `desc` | **2** | 均值 / SD / % 等描述统计 |
| `cutoff` | **3** | Youden / RCS 等切点展示 |
| `int_big_mark` | **TRUE** | 人数 / 事件数 / 计数 → `4,399` |

课题可用 `config$pub_digits` 覆盖；期刊要求 3 位效应量时写 `est = 3L` 即可。

## 已确认决策

1. **效应量范围（方案 A）**：仅 OR / HR / RR + CI 走 `est=2`；AUC / C-index / Youden 切点不借此改成「一律两位」——切点走 `cutoff=3`；AUC/C-index 若当前走 `pub_format_est` 会跟 `est=2`（本期不新增独立字段）。
2. **回滚策略（方案 A）**：只改引擎默认与模板；**已落盘表不强制回刷**；新跑 / 重导出自动生效。
3. **实现深度（方案 1）**：改默认入口 + 铁律 + 模板 + 少数写死 `d_est=3` 的中介路径图入口；**不全仓清剿**散落 `sprintf("%.3f")` / `round(..., 3)`（留作可选第二期）。
4. **千分位**：维持现有 `pub_format_int` + `.prepare_df_for_tex` 渲染守卫；数据层 CSV 仍存裸整数。

## 相对旧默认的变更

| 项 | 旧 | 新 |
|----|----|----|
| `est` | 3 | **2** |
| `cutoff` | 4 | **3** |
| `p` / `desc` / `int_big_mark` | 3 / 2 / TRUE | 不变 |

铁律文案同步：删除「禁止用 2 位格式化效应量 / Table2 OR 必须 3 位」等与新默认冲突的表述。

## 实现挂载点

1. **单一事实来源**：`R/utils.R`
   - `.pipeline_pub_digits()` 默认 `est=2L`、`cutoff=3L`
   - `pub_format_est` / `pub_format_ci` 兜底位数与注释对齐新默认
   - `pipeline_apply_pub_digits` 行为不变（仍从 config 注入 options）
2. **铁律**：`.cursor/rules/pub_digits_consistency.mdc` 默认表与检查清单改为 `2/3/2/3 + int_big_mark`
3. **模板**（至少）：
   - `configs/templates/config_incidence_dual_batch.template.R`
   - `configs/templates/config_survival_dual_batch.template.R`
   - `configs/templates/config_pa_mobility_cognitive.template.R`
   - 其它模板若含 `pub_digits = list(est = 3L, … cutoff = 4L)` 一并改
4. **写死位数入口**（读 `.pipeline_pub_digits()$est`，禁止再默认 `d_est = 3L`）：
   - `Blocks/20_mediation/00mediation_common.R`
   - `Blocks/20_mediation/01block_mediation_prognosis.R`
   - 其它同模式路径图标签函数（实现时 grep `d_est\s*=\s*3`）
5. **测试**：更新期望 `est=3`/`cutoff=4` 的单元测试（如 `tests/test_ml_reference_assoc_figures.R`）

## 明确不做（本期）

- 不外科回刷已导出 xlsx / 不重跑课题
- 不全仓替换专题 `run/` 脚本中的 `%.3f`
- 不新增 `auc_digits` 等字段
- 不把千分位逗号写回 attrition CSV 等数据层

## 验收

- 无 `config$pub_digits` 覆盖时：新跑 Table2 / 单因素 OR(CI) 为两位；P 三位；切点三位；`n (%)` 中 ≥4 位 n 为 `1,234` 形式
- 显式 `config$pub_digits$est = 3L` 的课题仍输出三位效应量
- `int_big_mark = FALSE` 时人数无逗号且全表一致
- 旧课题已落盘文件内容不变（未重导则不自动变）

## 风险与缓解

| 风险 | 缓解 |
|------|------|
| 个别 Block 硬编码 3 位 OR，新跑仍偶发三位 | 本期只改公共入口；第二期按主路径 grep 清剿 |
| 已写死 `pub_digits$est=3` 的旧 config 不跟新默认 | 预期行为；尊重课题覆盖 |
| AUC 走 `pub_format_est` 变成两位 | 接受；若期刊要更多位，课题临时抬 `est` 或后续加独立字段 |
