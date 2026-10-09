---
name: deploy-medical-blocks-host
description: >-
  Deploy medical-blocks-studies programmer interface (environment / trajectory /
  competing / tst two-stage transformer) onto 5006 DockerHome or a new Linux
  host (e.g. 192.168.68.34:2202). Use when the user says 配到5006 / 迁移到34 /
  挂套路 / deploy medical-blocks / medical-blocks-studies / user02@2202 /
  两阶段transformer.
disable-model-invocation: false
---

# Deploy Medical Blocks Host

把「程序员隔离研究区」挂到目标机器：研究只改 `studies/<名>/config.R` + `Data/`，引擎在 `MEDICAL_BLOCKS_ROOT`。

## 何时用本技能

- 在 **5006** 追加新套路（环境 / 轨迹 / **竞争风险** …）
- 把整套 `medical-blocks-studies` **迁移**到新主机（如 `192.168.68.34:2202` user02）
- 用户说「像轨迹和环境一样挂到 5006」「迁到 34」

## 架构（固定）

```
目标机上的研究区（程序员可见）
  medical-blocks-studies/
    engine.env              → MEDICAL_BLOCKS_ROOT=引擎路径
    run_study.sh / .bat     → 按 config 自动识别 routine → 调引擎 run/*.R
    studies/_template*/     → 复制出具体研究
    templates/              → 自包含 config 模板
    docs/Decisiontree/      → 决策树副本

引擎（通常只读给程序员）
  MEDICAL_BLOCKS_ROOT = 01Block-new-Final
    Blocks/ R/ run/ configs/study_interface/
```

| 套路 | 识别关键字 | Runner |
|------|------------|--------|
| environment | `voc_col_pattern` / `environment_batch` | `run/environment/run_environment_dkd_batch.R` |
| trajectory | `trajectory_batch` / `trajectory_jlcm` | `run/trajectory_prognosis/run_trajectory_prognosis_apri_batch.R` |
| competing | `competing_risk` / `study_batch`+`competing_` | `run/competing_risk/run_competing_risk_chf_batch.R` |
| tst（两阶段 Transformer） | `tst_stroke` / `tst_cohort` / `two_stage_transformer` | `run/two_stage_transformer_stroke/run_two_stage_transformer_stroke_task_parallel.R` |
| ipw（用药Jin） | `ipw_diabetes` / `Diabetes_HbA1c` / `ipw_jin_composite_risk` | `run/ipw_diabetes_stroke/run_ipw_diabetes_stroke_batch.R`（**5003**；可迁 **2203/user03**） |

## Agent 可自动做 vs 必须人工

| 步骤 | Agent | 人工 |
|------|-------|------|
| 写/更新 skill、模板、run_study 分发、hook_slots | ✅ | |
| 在本机可写盘的 5006 目录挂 competing 模板 | ✅ | |
| SSH 登录 `192.168.68.34:220x` 建目录/装 R/拷文件 | ❌ 常无网 | ✅ |
| 在 34 上建 Linux 账户、开端口、挂 SMB | ❌ 需管理员 | ✅ |
| 改用户密码、写死密码进仓库 | ❌ **禁止** | 用户本地 `~/.ssh` |

---

## 流程 A — 在 5006 追加一套路（本机可实施）

参考现成：`/mnt/g/DockerHome/5006/medical-blocks-studies/`（即 `\\192.168.68.133\DockerHome\5006\medical-blocks-studies`）。

1. **引擎侧**（`01Block-new-Final`）
   - `configs/study_interface/baseline_pipelines.json` 增加 routine 的 pipeline 列表
   - `configs/study_interface/hook_slots.yaml` 增加 `routine.*` slots
   - `R/programmer_block_hooks.R` 的 `.hooks_mother_rel` 指向决策树
   - `Decisiontree/decision_tree_<routine>.md` 存在
2. **研究区侧**（`medical-blocks-studies`）
   - `templates/config_<routine>_batch.template.R`（隔离模式：产出=`dirname(--config)`）
   - `studies/_template_<routine>/`（`config.R` + `STUDY.md` + `Data/` 占位）
   - `docs/Decisiontree/` 复制决策树
   - `run_study.sh` / `run_study.bat`：自动识别 + `--routine` 映射到 runner
   - 更新根 `README.md`
3. **冒烟**
   ```bash
   cd /mnt/g/DockerHome/5006/medical-blocks-studies
   ./run_study.sh <研究名> --routine competing --shared-only
   ```

### competing 默认约定（AKI 版）

- 主事件：`derive_competing_aki_28d`（KDIGO 简化）
- 硬排除：`Creatinine` / `BUN` / `UreaNitrogen` 及含其组分的复合指标
- 数据：`Data/mimic/`（基线 RData + dabiao + 预后 CSV + 实验室 1–30 天 CSV）
- CLI：`--shared-only` / `--workers N` / `--only-unit NLR` / `--no-skip`

### tst 默认约定（两阶段 Transformer）

- 入口：`run/two_stage_transformer_stroke/run_two_stage_transformer_stroke_task_parallel.R`
- 隔离模板：`templates/config_two_stage_transformer_stroke_batch.template.R`
- 骨架：`studies/_template_tst/`
- 数据：`Data/mimic/`（基线 RData + dabiao + 预后 CSV + 实验室长表）
- 产出：研究文件夹内（非 `02block_result`）
- 依赖：R 共享层 + **Python/PyTorch** Worker
- CLI：`--shared-only` / `--workers N` / `--only-unit L72_B_twostage` / `--list-units`

---

## 流程 B — 迁移到 192.168.68.34（user02 / 端口 2202）

> 本环境曾探测：`ssh -p 2202 user02@192.168.68.34` → **Network unreachable**。  
> 下列在 **能 SSH 到 34 的机器**（办公室 Windows / 同网段 WSL）上执行。

### B0. 账户与端口（管理员）

| 用户 | 密码（首次登录后立刻改） | SSH 端口 |
|------|--------------------------|----------|
| user01 | user01@2026 | 2201 |
| user02 | user02@2026 | **2202** ← 本项目默认 |
| user03 | user03@2026 | 2203 |
| user04 | user04@2026 | 2204 |
| user05 | user05@2026 | 2205 |

确认：`ssh -p 2202 user02@192.168.68.34`

### B1. 在 34 上准备目录

```bash
ssh -p 2202 user02@192.168.68.34
mkdir -p ~/medical-blocks/{engine,studies-iface,data,results}
# 建议布局：
#   ~/medical-blocks/engine          ← 引擎只读克隆或 rsync
#   ~/medical-blocks/studies-iface   ← medical-blocks-studies 副本
#   ~/medical-blocks/data            ← 大数据（可挂 NAS）
#   ~/medical-blocks/results         ← 可选；默认产出在 studies/<名>/ 下
```

### B2. 同步引擎（从 133 / 本机 E 盘）

在 **能同时访问源与 34** 的机器上：

```bash
# 示例：从本机引擎推到 34（排除巨大结果与 .git 对象可按需）
rsync -avz --progress \
  --exclude '.git' --exclude 'adversarial_lit_reading' \
  -e 'ssh -p 2202' \
  /mnt/e/01block/01Block-new-Final/ \
  user02@192.168.68.34:~/medical-blocks/engine/
```

或挂 SMB：`\\192.168.68.133\...` → 34 上 `mount.cifs`，再软链到 `~/medical-blocks/engine`。

### B3. 同步研究区接口

```bash
rsync -avz -e 'ssh -p 2202' \
  /mnt/g/DockerHome/5006/medical-blocks-studies/ \
  user02@192.168.68.34:~/medical-blocks/studies-iface/
```

### B4. 写 `engine.env`（34 上）

```bash
# ~/medical-blocks/studies-iface/engine.env
MEDICAL_BLOCKS_ROOT=/home/user02/medical-blocks/engine
```

### B5. 依赖

- R ≥ 4.3（建议 4.5.x）+ `Rscript` 在 PATH
- 常用包：`data.table` `survival` `cmprsk` `lcmm` `mice` `gtsummary` `cli` `dplyr` …
- （可选）与 5006 相同的 `renv.lock` / 站点库
- **容器/overlayfs 主机坑（2202 实测）**：`R CMD INSTALL` 在 `/tmp` 解包后找不到源文件
 （`cc1: fatal error: *.c: No such file or directory`，纯 make 亦然）→
 把 `TMPDIR` 指到家目录：`echo "TMPDIR=$HOME/tmp" >> ~/.Renviron; mkdir -p ~/tmp`，
 否则**所有**源码包（含 magrittr 级别）全军覆没。
- **升级 R 后的坏 site-library（2202 实测）**：R 升到 4.6.1 后，旧 site-library 里的
 `fansi` 等 C 包报 `undefined symbol: R_nchar`，连锁拖垮 tidyverse 栈全部安装 →
 用 `R CMD INSTALL -l ~/R/library` 把核心 C 包**重装到用户库**（user-lib 排在 site 前自动影子覆盖）。
- **批量装包策略（2202 已验证）**：不要信任该容器上的 `install.packages()` 并行解包；
 用「闭包 download → `~/pkgs/*.tar.gz` → 多轮按依赖序 `R CMD INSTALL`」脚本
 （`34:~/install_pkgs_2202.sh`）。
- trajectory 套路核心包：`lcmm mclust mice flexsurv survminer timeROC gbmt pROC emmeans rms openxlsx patchwork gtsummary data.table`
- competing 套路核心包：`cmprsk coxme lme4 riskRegression prodlim mice mclust openxlsx tableone dcurves Hmisc survey`

### B6. 冒烟

```bash
ssh -p 2202 user02@192.168.68.34
cd ~/medical-blocks/studies-iface
# 复制模板
cp -a studies/_template_competing studies/stroke_aki_smoke
# 放入 Data/mimic/ 后：
./run_study.sh stroke_aki_smoke --routine competing --shared-only
```

### B7. Cursor / 远程开发（可选）

- Cursor Remote-SSH：`Host 34-user02` / `HostName 192.168.68.34` / `Port 2202` / `User user02`
- 打开文件夹：`/home/user02/medical-blocks/studies-iface`
- 引擎路径保持 `engine.env`，勿把引擎拷进每个研究

---

## 流程 C — 下次「直接调用」检查清单

复制后逐项打勾：

- [ ] 目标是 **5006 加套路** 还是 **迁 34**？
- [ ] 套路名：environment / trajectory / **competing** / 其他
- [ ] 引擎 `MEDICAL_BLOCKS_ROOT` 在目标机可读
- [ ] `run_study` 能识别 routine 并找到 runner
- [ ] `_template_*` + `STUDY.md` + Data 占位齐全
- [ ] `--shared-only` 冒烟通过
- [ ] 34：SSH 端口、用户、R、engine.env 已验证
- [ ] **未**把密码提交进 git / skill 明文长期保存（本 skill 表格仅部署备忘，部署后改密）

## 已完成部署记录

### 2202 / user02（2026-09-14，双库轨迹预后 + 竞争风险）

- 研究区实际路径：`~/medical-blocks/P_BLOCK`（原 `studies-iface`，当天被改名，内容完好；engine.env 指向 `~/medical-blocks/engine`）
- 引擎：最新源码已 rsync（排除 `.git logs tmp _archive adversarial_lit_reading checkpoints Output Data studies_run`）
- 套路模板：`templates/` + `studies/_template_trajectory|_template_competing` 均为 9/14 刷新版
- R 包：版本感知闭包（`34:~/closure_dl_2202.R` + `install_v2_2202.sh`，tarball 留 `~/pkgs`）70 包全绿；
  `~/.Renviron` 已固化 `TMPDIR=~/tmp`、`R_LIBS_USER=~/R/library`
- 冒烟：两套 config `SOURCE_OK`、全部 pipeline block 注册匹配、`run_study` 路由正确（trajectory/competing/tst/environment）
- 正式跑：把数据放入 `P_BLOCK/studies/<研究>/Data/{eicu,mimic}`，然后
  `./run_study.sh <研究> --shared-only` → `--workers N --only-index …`

## 参考路径

- 5006 研究区：`/mnt/g/DockerHome/5006/medical-blocks-studies`
- 引擎：`/mnt/e/01block/01Block-new-Final`
- 轨迹设计：`docs/superpowers/specs/2026-07-17-5006-trajectory-prognosis-interface-design.md`
- 竞争风险决策树：`Decisiontree/decision_tree_competing_risk_stroke.md`
