# 部署示例

## 示例 1：已有 incidence dual batch → 新建 ARDS 研究

```bat
cd \\192.168.68.133\DockerHome\5001\medical-blocks-studies
xcopy /E /I studies\_template studies\01_SEPSIS_incidence_12345678
```

改 `studies/01_SEPSIS_incidence_12345678/config.R`：

```r
.study <- list(
  disease_code = "02", disease = "Sepsis",
  literature_pmid = "12345678",
  analysis_group = "Sepsis", reference_group = "Non_Sepsis",
  index_group = "dual_safe",
  sensitivity_enable = TRUE, feishu_enable = FALSE
)
.batch_project_root <- normalizePath(getwd(), winslash = "/")
source(file.path(Sys.getenv("MEDICAL_BLOCKS_ROOT"),
  "configs/study_interface/incidence_dual_batch_build.R"))
```

放数据 → 运行：

```bat
run_study.bat 01_SEPSIS_incidence_12345678 --shared-only
run_study.bat 01_SEPSIS_incidence_12345678 --workers 4
```

---

## 示例 2：完整模板方式（改 block 参数）

```bat
copy templates\config_incidence_dual_batch.template.R studies\我的研究\config.R
```

在 config.R 顶部改：

```r
.batch_project_root <- normalizePath(getwd(), winslash = "/")
.batch_ck_root      <- file.path(.batch_project_root, "checkpoints")
```

搜索【必改】逐项修改；**勿改** pipeline blocks 顺序。

---

## 示例 3：管理员首次 scaffold 研究区

```bash
ENGINE=/mnt/e/01block/01Block-new-Final
STUDIES=/mnt/g/DockerHome/5001/medical-blocks-studies

mkdir -p "$STUDIES"/{templates,docs/create-pipeline-config,studies/_template/Data/{eicu,mimic}}

cp "$ENGINE"/configs/templates/*.template.R "$STUDIES/templates/"
cp "$ENGINE"/skills/create-pipeline-config/{SKILL.md,examples.md} "$STUDIES/docs/create-pipeline-config/"
cp -r "$ENGINE"/skills/deploy-programmer-interface/reference.md "$STUDIES/docs/" 2>/dev/null || true

# 从本 skill 的 medical-blocks-studies README 复制 run_study.bat/sh、engine.env
```

---

## 示例 4：新套路（预后 batch）扩展清单

假设已完成 `run_survival_sae_batch.R`：

1. 写 `configs/study_interface/survival_sae_batch_build.R`（`.study` 含 `time_var`, `event_var`, `index_group`）
2. `run_study.bat` 内把 `run_incidence_dual_batch.R` 改为可配置或增加第二脚本 `run_survival_study.bat`
3. 复制 `config_survival_sae.template.R` → `templates/`
4. `_template/config.R` 指向新 build 脚本
5. 程序员指南增加「预后」章节

---

## 示例 5：engine.env

```ini
# Windows
MEDICAL_BLOCKS_ROOT=E:/01block/01Block-new-Final

# WSL run_study.sh 会自动尝试 /mnt/e/01block/01Block-new-Final
```

---

## 验证命令

```bash
# config 能否 source
cd studies/01_ARDS_incidence_38341157
MEDICAL_BLOCKS_ROOT=/mnt/e/01block/01Block-new-Final Rscript -e 'source("config.R"); cat(config$project$output_dir)'

# 完整冒烟
cd /mnt/g/DockerHome/5001/medical-blocks-studies
./run_study.sh 01_ARDS_incidence_38341157 --workers 2 --only-index NLR
```
