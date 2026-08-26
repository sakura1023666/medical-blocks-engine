# 发表图三格式目录 + 多库拼图 + image_information

日期：2026-08-20  
状态：已批准；实现计划见 `docs/superpowers/plans/2026-08-20-pub-figures-formats-and-image-information.md`  
范围：所有会把发表图汇总到 `Figures/`（或交叉滞后 `summary_result/figure`）的套路：发病、预后、机器学习 dual-batch、交叉滞后、竞争风险、CRM/IPW/中介等。

## 1. 目标

以后跑任何现有套路：

1. **多库必须拼图**：同一图号、不同库的发表图拼成一张（无库标签文件名），再进入汇总交付。
2. **单库不拼图**：该库终稿直接进入汇总交付。
3. **无论单库/多库**，汇总图目录顶层只保留四个子目录：
   - `pdf/`
   - `png/`
   - `tiff/`
   - `image_information/`
4. 三种栅格/矢量格式**同名不同扩展名**；TIFF 使用 **LZW 压缩**。
5. 每张定稿图一份 Markdown，描述该图在讲什么，并附可拿到的 N / 结局 / 暴露。

## 2. 已确认决策

| 项 | 决定 |
|----|------|
| 四目录 | 单库、多库一律创建 |
| 多库拼图 | 强制；复用并扩展现有 `dual_db_combine_paired_figures` |
| 单库拼图 | 不拼 |
| 汇总顶层 | 只有上述四目录，不再直接放图文件 |
| 分库底稿 | 不进汇总（`remove_singles`）；可留在 `<DB>/Figures` 与 `step*/Figures` |
| TIFF | 默认 300 dpi，压缩 LZW，RGB |
| PNG | 与 TIFF 同 DPI |
| PDF | 仍为矢量主交付（拼图优先矢量路径） |
| 图信息 | 每图一份 md + 总目录 `README.md` |
| 图信息内容 | 图号/图题、这张图描述的信息、N/结局/暴露（有则写） |
| 不写入 md | 完整 HR/OR 结果表（避免与主表重复） |

## 3. 非目标

- 不改各分析 block 内部多面板（SHAP cowplot、RCS patchwork 等）；那些仍是单库底稿。
- 不把 step 级中间图强制三联导出。
- 不在缺配对时让整条流水线失败（告警；汇总仍不留带库标签单图）。
- 不把 `Figure Missing Value Overview*` 纳入拼图或四目录。
- 不二次拼已经无库标签的合成图（例如总 flowchart）。

## 4. 目录布局

### 4.1 Dual-batch（发病 / 预后 / ML）

```
<output>/by_index/【success】<ix>/
  Figures/
    pdf/
    png/
    tiff/
    image_information/
      README.md
      Figure 1. ….md
  <DB>/Figures/          ← 分库底稿（带库标签 PDF），不搬进汇总四目录
  <DB>/stepNN_*/Figures/
```

交叉滞后汇总目录名为 `summary_result/figure`（单数），规则相同：该目录顶层改为四个子目录，不再散落 PDF/PNG。

竞争风险等根 `Output/Figures/` 同样改造。

### 4.2 文件名

- 定稿 stem 与现有发表命名一致：`Figure N. <caption>` / `Figure SN. <caption>`。
- `pdf/xxx.pdf`、`png/xxx.png`、`tiff/xxx.tiff`、`image_information/xxx.md` 共用同一 `xxx`（含空格与图题，与现网 PDF 文件名去掉扩展名后一致）。
- 多库拼图文件名**不带**库标签、不带 `Combined`。

## 5. 架构

发表层统一收口（方案 A）：block 仍按现状写 PDF；在**汇总目录定稿之后**调用一次导出。

```
各库出图（PDF 底稿）
    → 镜像到汇总 Figures/（可含库标签成对文件）
    → 若库数 ≥ 2：拼图（remove_singles）
    → export_pub_figures(figures_dir, meta)
         扫描顶层定稿 PDF（无库标签）
         写入 pdf/ png/ tiff/
         写 image_information/*.md 与 README.md
         删除 Figures/ 顶层散落图文件
```

分库与 step 目录不跑 `export_pub_figures`。

## 6. 组件

### 6.1 `export_pub_figures(figures_dir, meta = list())`

新共享函数（建议放在 `R/pub_figure_export.R`，由 `utils.R` 或 finalize 源入）。

输入：已定稿的汇总图目录（此时顶层应是无库标签 PDF，或单库终稿 PDF）。

行为：

1. 确保四个子目录存在。
2. 收集顶层 `Figure*.pdf` / `Figure*.png`（忽略已在子目录内的文件；忽略 Missing Value Overview）。
3. 每个 stem：复制/规范化 PDF → `pdf/`；栅格化 → `png/` 与 `tiff/`（300 dpi；TIFF `compression = "lzw"`；优先 Python/Pillow 或 magick，与现有拼图栅格回退一致）。
4. 写 `image_information/<stem>.md`。
5. 写/覆盖 `image_information/README.md`。
6. 删除顶层散落的图文件（不删除四子目录）。

`meta` 由调用方注入：暴露名、结局、各库 N、grouping、库名单、是否拼图、布局。缺字段在 md 写「未记录」。

配置入口（可选，有默认即可跑）：

```r
config$pub_figures <- list(
  formats_dir = TRUE,          # 总开关，默认 TRUE
  dpi = 300L,
  tiff_compression = "lzw",    # 固定 LZW，不允许课题改成无压缩除非显式测试
  write_image_information = TRUE
)
```

### 6.2 多库拼图：扩展现有 `dual_db_combine_paired_figures`

- **2 库**：行为与 `docs/superpowers/specs/2026-08-12-dual-db-combine-paired-figures-design.md` 相同。
- **3 库及以上**：按 config 库顺序生成 `A. {db}`、`B. {db}`、…；默认一行 N 列，N=4 时可用 2×2。
- 库名单来源优先级：`dual_db` primary/secondary（及已有第三库字段若存在）→ 课题 meta 队列顺序（交叉滞后）→ 文件名中实际出现的库标签（稳定排序兜底）。
- 交叉滞后 `summary_result/figure`、竞争风险发表导出：在收集/编号完成之后调用同一拼图函数（目录参数泛化为「汇总 Figures 目录」+ 库名向量），再调用 `export_pub_figures`。
- Dual-batch 挂点保持：`incidence_batch_finalize_index_outputs` 中 combine 之后、`incidence_batch_curate_index_pub_outputs` 之后（或 curate 末尾）调用导出，避免 curate 再把文件挪回顶层。

若 curate 会重排/改名，**必须先 curate 再 export**。顺序定为：

1. 各库 sync / mirror  
2. combine（多库）  
3. curate / 交叉滞后 reorder 白名单  
4. `export_pub_figures`

### 6.3 图信息 Markdown（全项目铁律）

每图一份。**不要**写「标识」「技术」；**不要**一句话空话。结构固定为：

```markdown
# Figure N. <caption>

## 图面说明
（多段：图类型、面板 A/B 对应库、视觉编码、可收获的结果要点。
 纳排图必须逐步列出保留 n 与本步排除人数，来源 Tables/Flowchart_attrition*.csv）

## 分析上下文
- 暴露 / 结局（可读名；可附原字段）/ N（多库：分库 N + 合计）
- Grouping（须与主文闸门一致）
- 库名单、是否拼图
```

生成规则（可测试、禁止空话）：

- 统一由 `pub_figure_write_image_md` / `export_pub_figures` 写出；旧结果用 `run/pub/refresh_image_information.R` 补刷。
- 拼图：显式写「A 面板=…；B 面板=…」。
- 禁止编造未提供的统计数字；N / AUC / 切点 / 纳排步只来自可收获文件或 meta。
- 禁止写入 DPI、TIFF 压缩、尺寸、文件相对路径列表。

`README.md`：表格列 = 图号、图题、是否拼图、pdf 相对路径。

## 7. 数据流与错误处理

| 情况 | 处理 |
|------|------|
| 单库 | 跳过 combine；export 四目录 |
| 多库配对完整 | 拼图 → remove_singles → export |
| 多库缺一侧 | 与现网拼图一致：cli 告警，保留可得到的一侧为**无库标签**终稿并进入 export；带库标签底稿不留在汇总顶层 |
| 栅格化失败 | PDF 仍写入 `pdf/`；png/tiff 告警；md 注明缺失格式 |
| 无任何发表图 | 仍创建四空目录 + 空 README，避免下游脚本找不到路径 |
| TIFF 设备不可用 | 失败应可见（warning + 日志），不静默改成未压缩 TIFF |

## 8. 测试

- 单库假 PDF 两张：export 后顶层无散落文件；三格式同 stem；md 含图题；README 两行。
- 双库成对 PDF：combine 后无 `-DB` 文件；四目录只有无标签拼图；md 写明 A/B 库名。
- 三库成对：一行三列或约定网格；三个面板标签。
- TIFF 文件头/ magick 信息含 LZW（或 Pillow `compression == "tiff_lzw"`）。
- 交叉滞后路径名 `figure/`（单数）同样适用。
- 回归：现有 `tests/test_result_review_guards.R` 中 dual combine 用例在 export 之后仍「汇总无分库单图」。

## 9. 实现入口（计划阶段再拆任务）

- 新：`R/pub_figure_export.R`（`export_pub_figures` + md 渲染）
- 改：`R/dual_db_combine_figures.R`（≥3 库布局）
- 改：`R/incidence_dual_batch_runner.R` finalize 顺序
- 改：交叉滞后 `collect_summary_result*.sh` 或对应 R collect：收集后 combine（若多队列）+ export
- 改：竞争风险 `18block_competing_pub_export.R`（及同类发表收口）
- 模板：`pub_figures` 默认块写入 dual / 单流水线模板
- 测试：`tests/test_pub_figure_export.R`

## 10. 与分位铁律的关系

change / 敏感性图若进入汇总四目录，md 中 Grouping 必须来自课题 `cross_lagged_study_meta()$grouping` 或调用方注入的主文闸门，禁止在导出层写死 tertile。
