# Design: TST 病种特征白名单「先查再跑」

> 日期: 2026-08-31  
> 状态: 已批准（方案 4 混合）  
> 相关: `Blocks/71_two_stage_transformer_stroke/`、`configs/tst_feature_priority/`、`R/tst_feature_density_gate.R`

## 问题

两阶段 Transformer 复用他病白名单（如骨质疏松挂 `aki_mimic.R`）会导致特征集与病种声明不一致；裸 `coverage` 又会留下报警/护理等高频噪声且无同义合并。

## 目标

每次开 TST 课题：**先查并落盘本病种白名单 → 用户确认 → 再跑 shared/workers**。  
Cursor 规则强制流程；流水线硬闸防止漏查仍开跑。

## 非目标

- 无人值守自动 PubMed/LLM 生成最终名单并开跑
- 默认改回裸 coverage
- 把疾病诊断泄漏变量硬塞进动态预测特征

## 设计

### A. Cursor 规则（Agent）

触发：用户说跑 TST / 两阶段 transformer / 新病种 TST。

顺序：

1. 识别 `disease` + `database` + 课题索引/对标文献（若有）
2. **先检索**该病 ICU/院内死亡常用动态特征（生命体征、常规实验室、通气等；排除报警/敷料/护理文书）；落盘 `reports/tst_feature_lit_<disease>_<db>.md`
3. 仅当对标文献**就是本课题索引文**且含特征附录时，才可用其 Supp 表作主名单；禁止把 Yang pbaf003 Supp Table 1 等无检索套到下一病
4. 落盘 `configs/tst_feature_priority/<disease>_<db>.R`，函数名 `tst_feature_priority_<disease>_<db>`，头注释写依据
5. config：`feature_select_mode="whitelist"` + `feature_priority_file`；`whitelist_apply_coverage_drop` 按本稿 Methods（不砍维则 FALSE + 患者缺失剔人）
6. 向用户展示名单摘要，确认后再跑
7. 禁止 config 指向他病/他文文件且无本病依据

ICU 通用核心可作底稿复制，但必须改名/改函数名/写本病注释。

### B. 流水线闸门

当 `feature_select_mode ∈ {whitelist, density_gate}`：

1. `feature_priority_file` 必须存在且可加载
2. 若文件名含他病关键字（如 `aki_` / `stroke_`），而 `project$disease` 不含对应病种 → **PAUSE**，提示换本病名单
3. 日志打印：disease、priority_file、n_canon

挂点：`tst_timeseries` 在加载 priority 之前（`02block_tst_timeseries.R` / 公共校验函数）。

### C. 覆盖率砍列（不变）

白名单之后仍：先删高缺失患者（可选）→ day1 缺失 >30% 砍列 → 前向填充。同义合并由 priority alias 完成。

### D. 骨质疏松本次落地

1. 停当前 workers
2. 新建 `osteoporosis_mimic.R`（ICU 核心 + 骨代谢相关候选：25-OH VitD / PTH / Albumin / Ionized Calcium 等）
3. config 改指向该文件
4. 清 `tst_timeseries` 及之后 shared checkpoint + `by_unit`
5. 重跑 shared → full workers

## 验收

- [ ] `.cursor/rules` 存在 TST 白名单铁律
- [ ] 他病文件 + 本病 disease → shared pause/报错
- [ ] 骨质疏松 config 指向 `osteoporosis_mimic.R`
- [ ] shared 日志含 whitelist 本病文件与保留/砍列数
- [ ] workers 在新 shared 上启动
