# 程序员操作手册：从数据到决策树（隔离模式）

> 适用端口：`5001`（发病/预后）、`5003`（ML/环境）、`5006`（环境 VOC）
> 原则：**只改自己研究目录**；引擎 `Blocks/` **默认只读**（**唯一例外**：复合指标 `editable/01block_index.R`）；加功能必须用 `add_block`，禁止手改乱插 pipeline。

---

## 0. 你能改什么 / 不能改什么

| 能改                                                          | 不能改                                       |
| ------------------------------------------------------------- | -------------------------------------------- |
| `studies/<研究名>/config.R`                                 | `engine.env`、`R/`、**其它** `Blocks/**` |
| `studies/<研究名>/Data/`                                    | 研究区`templates/`（只复制，不直接改母版） |
| 经 CLI 生成的`extensions.json`、`Decisiontree/tree_v*.md` | 母版`docs/Decisiontree/*.md`               |
| 产出目录（自动生成，可删了重跑）                              | 手改`pipeline_*$blocks` 绕过 `add_block` |
| **`editable/01block_index.R`**（链接到引擎 index，全局共用） | 直接翻引擎目录改其它 `01block_xxx.R`       |

**非法手改 pipeline 的后果**：下次 `run_study` 启动即报错停跑（硬校验）。

**改 index 的后果**：一改影响 **5001/5003/5006 全部研究**（共用引擎同一份公式）。

---

## 1. 选端口与套路

| 你要做的分析              | 去哪个目录                                                                  | 默认套路                                                       |
| ------------------------- | --------------------------------------------------------------------------- | -------------------------------------------------------------- |
| 双库发病（eICU/MIMIC 等） | `\\192.168.68.133\DockerHome\5001\medical-blocks-studies`                 | incidence                                                      |
| 双库预后（生存）          | 同上 5001                                                                   | survival（`--routine survival` 或 config 含 survival build） |
| ML 双库（CHARLS/ELSA 等） | `...\5003\medical-blocks-studies`                                         | ml                                                             |
| 环境 VOC（NHANES）        | `...\5006\medical-blocks-studies`（或 5003 的 `_template_environment`） | environment                                                    |
| 轨迹预后 JLCM（eICU+MIMIC） | `...\5006\medical-blocks-studies`（复制 `_template_trajectory`）        | trajectory                                                     |

下文以 **5006 环境 VOC** 为主线写全流程；发病/ML 差异见文末附录。

---

## 2. 总流程图（心智模型）

```text
① 先读母版决策树（理解流水线）
    ↓
② 复制模板建研究
    ↓
③ 放入 Data/
    ↓
④ 改 config.R（病种、路径、结局、占位符）
    ↓
⑤ （可选）search_blocks → add_block 挂新功能
    ↓  同时自动生成新决策树 tree_v001.md
⑥ run_study --shared-only 冒烟
    ↓
⑦ run_study 全量 / 指定 VOC 或指标
    ↓
⑧ 看 Tables / Results_Summary / by_voc 或 by_index
```

---

## 3. 第一步：先读决策树（母版）

动手建研究前，先搞清该套路流水线长什么样：

| 端口      | 打开                                                         |
| --------- | ------------------------------------------------------------ |
| 5006      | `docs/Decisiontree/decision_tree_environment_voc_batch.md` |
| 5001 发病 | `docs/Decisiontree/decision_tree_incidence_dual_batch.md`  |
| 5001 预后 | `docs/Decisiontree/decision_tree_survival_dual_batch.md`   |
| 5003 ML   | `docs/Decisiontree/decision_tree_ml_dual_batch.md`         |

这些是 **母版，只读**。理解三段结构即可：

- **共享层**：清洗、Table1、协变量、主分析（如 LASSO/WQS/BKMR）
- **并行层**：按 VOC 或按指标
- **尾段**：qgcomp / 中介 / 亚组 等

---

## 4. 第二步：新建研究文件夹

在 **研究区根目录**（不要先钻进 studies 再找脚本）：

### Windows

```bat
cd \\192.168.68.133\DockerHome\5006\medical-blocks-studies

REM 环境研究：复制 _template
xcopy /E /I studies\_template studies\10_osteoporosis_environment_37419158
```

### WSL

```bash
cd /mnt/g/DockerHome/5006/medical-blocks-studies
cp -a studies/_template studies/10_osteoporosis_environment_37419158
```

**命名建议**：`疾病_套路_PMID`，例如 `10_osteoporosis_environment_37419158`。

建好后目录应类似：

```text
studies/10_osteoporosis_environment_37419158/
├── config.R
├── STUDY.md
└── Data/
    └── nhanes/          ← 数据放这里
```

---

## 5. 第三步：准备并传入数据

### 4.1 环境 VOC（NHANES）— 5006

把 RData 放进：

```text
studies/<研究名>/Data/nhanes/
```

常见两种模式（二选一，以你 config 为准）：

| 模式        | 文件                                        | 对象名        | 说明                           |
| ----------- | ------------------------------------------- | ------------- | ------------------------------ |
| A. 已合并   | `D03_EnvResultData.RData`                 | `EnvResult` | 临床+环境+权重已合并           |
| B. 现场合并 | `D02_data.RData` + 环境表 + baseline 权重 | 见模板注释    | 需`environment_prepare` 打开 |

**最低要求字段（概念上）**：

- 结局：如 `Group`（病例/对照标签要与 config 里 `analysis_group` / `reference_group` 一致）
- ID：如 `SEQN`
- 调查设计：权重相关列（如 `WTMEC2YR` / `new_Weight` 由流水线计算）
- 暴露：VOC 列（或由 prepare 合并进来）

放完后可用 R 快速自检（在自己电脑或 WSL）：

```r
load("studies/你的研究/Data/nhanes/D03_EnvResultData.RData")  # 按实际文件改
ls()                          # 看对象名
head(EnvResult[, 1:10])       # 或 data
table(EnvResult$Group)        # 结局分布
```

### 4.2 发病/预后（5001）

```text
Data/eicu/   ← 主库（或 primary）
Data/mimic/  ← 次库（或 secondary）
```

各放一个清洗后的 `D04_*.RData`，对象名与 `.study` / config 中 `rawdata_obj` 一致。

### 4.3 ML（5003）

```text
Data/charls/
Data/elsa/
```

对象名、结局列与 `_template/config.R` 里 `.study` 一致。

---

## 6. 第四步：写 / 改 config.R

### 6.1 环境套路（完整模板，改占位符）

打开：

```text
studies/<研究名>/config.R
```

在编辑器中 **全局搜索** `<TO_CONFIRM`，逐项替换，至少包括：

1. **疾病与项目名**
   - `project$disease` / `disease_cn` / `name`
2. **结局**
   - `data$outcome_column`（常为 `Group`）
   - `project$analysis_group` / `reference_group`（必须与数据里因子水平字面一致）
3. **数据路径与对象**
   - `data$rawdata_path`（相对研究目录或绝对路径；隔离模式下常指向 `Data/nhanes/...`）
   - `data$rawdata_obj`（如 `EnvResult` / `data`）
4. **产出路径**
   - 模板顶部已用 `--config` 推断 `.batch_project_root` → **一般不要改成引擎路径**
5. **飞书**
   - 程序员侧建议 `feishu$enable = FALSE`
6. **亚组水平**（若跑尾段亚组）
   - `subgroup_strata` 的 `strata_levels` **必须与数据因子完全一致**
   - 例：吸烟是 `Never/Former/Current`，不能写 `nonSmoked/Smoked`
   - PIR 是 `< 1.3`，不能写 `≤ 1.3`
7. AI提示词（\192.168.68.133\DockerHome\5001\medical-blocks-studies\studies\02_AMI 这个路径下有我的数据，我现在的疾病是急性心肌梗死，我做的是预后，根据我的数据帮我写config，我想并行跑28路，给我在PS G:\DockerHome\5001\medical-blocks-studies>这个终端下我运行的命令）

**不要改**（除非管理员明确要求）：

- `pipeline_shared` / `pipeline_voc_batch` / `pipeline_tail` 里 **原有** blocks 顺序
- 需要加新步骤时，用第 7 节的 `add_block`，不要手插

### 6.2 发病 / ML（薄 config，只改 `.study`）

5001 / 5003 的 `_template/config.R` 通常是：

```r
.study <- list(
  disease_code = "...",
  disease = "...",
  literature_pmid = "...",
  analysis_group = "...",
  reference_group = "...",
  index_group = "dual_safe",
  # ... 库路径、RData 文件名、对象名 ...
  feishu_enable = FALSE
)
.batch_project_root <- ...  # 一般已自动推断
source(file.path(Sys.getenv("MEDICAL_BLOCKS_ROOT"),
  "configs/study_interface/xxx_dual_batch_build.R"))
```

**你只改 `.study` 块**；末尾 `source(..._build.R)` 不要删。

---

## 6.5 改复合指标公式（唯一可写的引擎文件）

需要增删/改 BMI、SII、CONUT 等公式时，**只**打开研究区根目录的入口（不要去翻整个 `Blocks/`）：

```text
medical-blocks-studies/editable/01block_index.R
  → 引擎 Blocks/00_index/01block_index.R（符号链接）
```

Windows 示例：

```bat
cd \\192.168.68.133\DockerHome\5006\medical-blocks-studies
notepad editable\01block_index.R
```

WSL：

```bash
cd /mnt/g/DockerHome/5006/medical-blocks-studies
# 用你的编辑器打开 editable/01block_index.R
```

流程建议：

1. 读 `editable/README.md`（全局影响警告）
2. 改前备份或确认可回滚
3. 编辑公式后保存
4. 某研究冒烟：`run_study.bat <研究名> --shared-only` 或 `--only-index BMI`

其它 block 源码仍禁止改；挂新功能用下一节的 `add_block`。

---

## 7. 第五步：搜索 Block 并挂到流水线（可选）

当你需要「多跑一个已有功能」（例如某个图、富集、额外表），**不要改其它 Blocks 源码**，按下面做。

### 7.1 搜索可用 block（只读）

在研究区 **根目录**：

```bat
cd \\192.168.68.133\DockerHome\5006\medical-blocks-studies

search_blocks.bat mediation
search_blocks.bat histogram
search_blocks.bat --list-slots --routine environment
```

WSL：

```bash
./search_blocks.sh mediation
./search_blocks.sh --list-slots --routine environment
```

- 搜到的名字必须是引擎 **已注册** 的 block（目录来自 catalog，不是随便一个 `.R` 文件名）
- `--list-slots` 看允许挂接的 **槽位**（只能插在这些位置）

环境常用槽位示例：

| 槽位 id                                    | 含义          |
| ------------------------------------------ | ------------- |
| `environment.tail_after_qgcomp`          | qgcomp 之后   |
| `environment.tail_after_mediation`       | 中介之后      |
| `environment.tail_end`                   | 尾段最末      |
| `environment.shared_after_bkmr_analysis` | BKMR 分析之后 |

### 7.2 挂接（会改 config + 生成新决策树）

```bat
add_block.bat 10_osteoporosis_environment_37419158 --slot environment.tail_end --block plot_histogram
```

成功后研究目录会出现/更新：

```text
studies/<研究名>/
├── config.R                 ← pipeline 对应位置多了该 block 名
├── extensions.json          ← 合法挂接清单（运行时校验用）
└── Decisiontree/
    ├── baseline_environment.md   ← 首次从母版复制，之后锁死不改
    ├── tree_v001.md              ← 【新】本版决策树（含挂接说明）
    ├── tree_v002.md              ← 再挂一次会再生成新版本
    └── CURRENT.md                ← 指向当前 tree_v00N.md
```

**重要**：

- **母版** `docs/Decisiontree/*.md` **不会被改**
- **baseline_*.md** 复制一次后 **永不改**
- 每次 `add_block` / `remove_block` 都生成 **新的** `tree_vNNN.md`，请打开最新版看图

撤销：

```bat
remove_block.bat 10_osteoporosis_environment_37419158 --slot environment.tail_end --block plot_histogram
```

### 7.3 禁止的做法

```text
❌ 直接打开 config.R，在 blocks = c(...) 中间手插一个名字
❌ 去引擎 Blocks/ 里改「非 index」的 01block_xxx.R（index 只走 editable/ 入口）
❌ 改 docs/Decisiontree/ 母版来“同步”你的流程
```

手改乱插 → `run_study` **直接报错停跑**。

---

## 8. 第六步：运行流水线

始终在 **medical-blocks-studies 根目录** 执行：

### 8.1 建议顺序

```bat
REM 1) 只跑共享层，确认数据/config 无误
run_study.bat 10_osteoporosis_environment_37419158 --shared-only

REM 2) 全量（RCS 并行等）
run_study.bat 10_osteoporosis_environment_37419158 --workers auto

REM 3) 只要某几个 VOC
run_study.bat 10_osteoporosis_environment_37419158 --workers auto --only-voc BMA,DHBMA

REM 4) 共享层+BKMR 已有检查点时，只补尾段
run_study.bat 10_osteoporosis_environment_37419158 --tail-only

REM 5) 强制重跑（忽略已有 by_voc）
run_study.bat 10_osteoporosis_environment_37419158 --no-skip
```

显式指定套路（一般可省略，会自动识别）：

```bat
run_study.bat 10_osteoporosis_environment_37419158 --routine environment --workers auto
```

### 8.2 发病（5001）常用

```bat
run_study.bat 01_ARDS_incidence_38341157 --shared-only
run_study.bat 01_ARDS_incidence_38341157 --workers 4
run_study.bat 01_ARDS_incidence_38341157 --workers 4 --only-index NLR,SII
run_study.bat 01_ARDS_incidence_38341157 --sensitivity-only
```

### 8.3 预后（5001）

```bat
run_study.bat 06_GIB_prognosis_38902748 --routine survival --shared-only
run_study.bat 06_GIB_prognosis_38902748 --routine survival --workers 2
```

### 8.4 ML（5003）

```bat
run_study.bat 06_Psoriasis_ml_40395549 --shared-only
run_study.bat 06_Psoriasis_ml_40395549 --workers 2 --only-index Leisure_activities
```

---

## 9. 第七步：看结果在哪里

### 环境 VOC

```text
studies/<研究名>/
├── _shared/              共享层逐步产出
├── by_voc/<VOC>/         每个 VOC 的 RCS 等
├── _tail/                尾段 qgcomp/中介/亚组
├── Tables/  Figures/     镜像发表表图
└── Results_Summary/      汇总打包
```

### 发病 / 预后 / ML

```text
studies/<研究名>/
├── by_index/<指标>/<库>/
├── Tables/Batch_summary_all_indices.csv
└── checkpoints/
```

挂接后的决策树：打开

`studies/<研究名>/Decisiontree/CURRENT.md` → 再打开其中的 `tree_v00N.md`。

---

## 10. 推荐工作清单（打印用）

- [ ] 阅读母版决策树，确认三段流程
- [ ] 复制 `_template`（或 `_template_environment`）为新研究名
- [ ] 数据放入正确 `Data/...` 子目录，对象名已知
- [ ] 改 config：结局标签、路径、对象名、飞书关闭
- [ ] （如需改公式）只编辑 `editable/01block_index.R`，确认全局影响
- [ ] 亚组 `strata_levels` 与数据因子一致
- [ ] （可选）`search_blocks` → `add_block`，打开新的 `tree_v001.md`
- [ ] `--shared-only` 冒烟通过
- [ ] 全量或 `--only-voc` / `--only-index`
- [ ] 检查 Tables / Results_Summary / by_voc|by_index
- [ ] 需要撤销挂接用 `remove_block`，不要手删一半

---

## 11. 常见报错

| 现象                                         | 处理                                                               |
| -------------------------------------------- | ------------------------------------------------------------------ |
| 找不到引擎 / MEDICAL_BLOCKS_ROOT             | 找管理员查`engine.env`，程序员勿改                               |
| 找不到 RData 对象                            | 核对`rawdata_obj` 与 `load()` 后的名字                         |
| 结局水平对不上                               | `analysis_group` / `reference_group` 必须与 `Group` 水平一致 |
| 亚组整层被跳过                               | `strata_levels` 写错（吸烟/PIR 最常见）                          |
| `非法 pipeline 扩展` / `extensions.json` | 你手改了 blocks；用`add_block` 重做或还原 config                 |
| `unknown block`                            | 该名字未在引擎注册；换 catalog 里有的名字                          |
| 挂接 slot 不存在                             | `search_blocks --list-slots --routine <套路>` 看合法槽位         |
| BKMR / 共享层很慢                            | 正常；环境 BKMR iter=1000 可能要 1–2 小时                         |

---

## 12. 附录：三端口模板对照

| 端口      | 复制谁                    | config 改法                      | 数据目录                        |
| --------- | ------------------------- | -------------------------------- | ------------------------------- |
| 5001      | `_template`             | 薄`.study` 或完整发病/预后模板 | `Data/eicu` + `Data/mimic`  |
| 5003 ML   | `_template`             | 薄`.study`                     | `Data/charls` + `Data/elsa` |
| 5003 环境 | `_template_environment` | 占位符`<TO_CONFIRM*>`          | `Data/nhanes`                 |
| 5006      | `_template`             | 占位符`<TO_CONFIRM*>`          | `Data/nhanes`                 |

---

## 13. 相关文档（研究区内）

- 本手册：`docs/程序员操作手册.md`（与 `docs/block操作手册.md` 同源）
- 决策树母版：`docs/Decisiontree/`
- Block 目录：`docs/block_catalog/catalog.md`
- 复合指标唯一入口：`editable/01block_index.R`（见 `editable/README.md`）
- 配置规范：`docs/create-pipeline-config/`
- 各端口简版命令：根目录 `README.md`

有问题先查决策树与 catalog；需要**非 index** 的新算法/新 block 源码时找 **徐彤**（其它 `Blocks/` 不可改；指标公式只走 `editable/`）。
