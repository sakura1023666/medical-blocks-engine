---
name: feishu-result-sync
description: >-
  为 Medical Blocks 批量流水线配置飞书多维表格三表结果同步（凭证、.env.feishu、
  开放平台权限、文档应用授权、三表初始化、worker 路由推送、Sheet1 汇总更新、
  upsert 去重：同项目重跑更新旧行，新项目自动叠加新行）。
  当用户说飞书、Feishu、bitable、结果管理表、阳性阴性结果同步、筛选分配跟踪、
  三表架构、成功失败分表、去重、重跑时使用。与 run-batch-pipeline 配合：
  成功指标→Sheet2，失败指标→Sheet3，batch 结束后 Sheet1 自动汇总。
---

# 飞书结果管理表同步（三表架构 v2）

> 参考实现：`R/feishu_bitable.R`、`R/feishu_env.R`、`run_feishu_test.R`  
> 三表初始化脚本：`run_feishu_setup_tables.R`（运行一次）  
> 发病双库 batch 已完整接入：`configs/config_incidence_dual_batch.R`

---

## 三表架构总览

```
Sheet 1「项目汇总」   ← 1 行 / disease+protocol，batch 结束后自动更新
Sheet 2「成功指标」   ← worker 成功时自动 upsert（含 OR、分支、样本量）
Sheet 3「失败指标」   ← worker 失败时自动 upsert（含失败类型、错误信息）

Sheet1 有「成功指标关联」和「失败指标关联」字段（type=18）指向 Sheet2/3
```

| Sheet | 触发时机 | R 函数 | 写入策略 |
|-------|---------|--------|---------|
| Sheet 2 | worker status=success | `.push_success()` | **upsert**（项目编号+指标名） |
| Sheet 3 | worker status=error/failed | `.push_failure()` | **upsert**（项目编号+指标名） |
| Sheet 1 | batch 结束 / `run_feishu_sync_batch.R` | `incidence_batch_feishu_update_summary()` | **upsert**（疾病字段，同步成功指标列表） |

### 去重规则（upsert 行为）

| 场景 | Sheet 2/3 行为 | Sheet 1 行为 |
|------|----------------|-------------|
| 同项目重跑（`project_id` 相同）| 同名指标 → **UPDATE 旧行**，不新增 | 同疾病 → **UPDATE** |
| 新项目（`project_id` 不同）| 未命中 → **CREATE 新行**，正确叠加 | 新疾病 → **CREATE** |
| `run_feishu_sync_batch.R` 运行多次 | 同上，幂等 | 同上，幂等 |

去重键：Sheet 2/3 用 `项目编号 + 指标名`；Sheet 1 用 `疾病`。

---

## 核心文件

| 文件 | 职责 |
|------|------|
| `R/feishu_bitable.R` | token、CRUD、三表路由、Sheet1 汇总更新 |
| `R/feishu_env.R` | 读 `.env.feishu` → `Sys.setenv` |
| `.env.feishu` | 本地凭证（**勿提交 Git**） |
| `run_feishu_setup_tables.R` | **一次性**：建三表结构、关联字段、写初始汇总行 |
| `run_feishu_test.R` | 连通性自检 + 试写一条 |
| `run_feishu_sync_batch.R` | 补推已有结果 + 更新 Sheet1 |

入口脚本加载顺序（`source(config)` 之前）：

```r
source(file.path(root, "R/feishu_env.R"))
feishu_load_dotenv(root)
```

---

## Sheet 字段设计

### Sheet 1：项目汇总

| 字段 | 类型 | 说明 |
|------|------|------|
| 疾病（主字段）| 文本 | `feishu$disease_label`（如 `01_Urinary_Incontinence`） |
| 套路 | 文本 | `feishu$protocol_label` |
| 指标总数 | 数字 | 初始化时写入 |
| 成功数量 | 数字 | R 自动更新 |
| 失败数量 | 数字 | R 自动更新 |
| 未运行数量 | 数字 | R 自动更新 |
| **成功指标列表** | 文本 | R 自动更新，逗号分隔所有成功指标名 |
| 结果摘要 | 文本 | `"指标N个|成功N|失败N|进度N%"` |
| 成功项目号 | 文本 | 手动填写 |
| 整体状态 | 单选 | 待开始/运行中/部分完成/全部成功/已交付 |
| 负责人 | 文本 | 手动填写 |
| 最后同步时间 | 日期 | R 自动更新（毫秒时间戳） |
| 成功指标关联 | 关联→Sheet2 | 可展开查看所有成功记录 |
| 失败指标关联 | 关联→Sheet3 | 可展开查看所有失败记录 |

### Sheet 2：成功指标

指标名（主字段）、疾病、套路、文献、数据库模式、NHANES_分支、MIMIC_分支、NHANES_OR、MIMIC_OR、NHANES_N、MIMIC_N、耗时_秒、完成时间、项目编号、负责人、是否已交付、是否查重（手动填）

### Sheet 3：失败指标

指标名（主字段）、疾病、套路、失败类型、数据库模式、错误信息、NHANES_N、MIMIC_N、耗时_秒、失败时间、项目编号、备注、是否查重（手动填）

---

## 新项目配置清单

```
- [ ] 1. 复制 R/feishu_bitable.R、R/feishu_env.R
         run_feishu_test.R、run_feishu_sync_batch.R、run_feishu_setup_tables.R
- [ ] 2. config_*_batch.R 加 feishu 段（见下方模板）
- [ ] 3. 入口脚本 + worker 加 feishu_env.R 加载 + .write_status 调 push_result
         worker fields 要含 disease、protocol（三表路由必需）
- [ ] 4. batch_runner 汇总后调 incidence_batch_feishu_update_summary
- [ ] 5. 飞书开放平台：自建应用 → 开通 bitable:app → 发布版本
- [ ] 6. 飞书建 Wiki 页面或独立多维表格
- [ ] 7. 表格内 ··· → 更多 → 添加文档应用 → 搜应用名 → 可管理
         （创建新数据表需要「可管理」，仅写记录需要「可编辑」）
- [ ] 8. 填 .env.feishu（5 个变量），跑 run_feishu_test.R --write-test
- [ ] 9. 跑 run_feishu_setup_tables.R（建三表结构），记录输出的 table IDs
- [ ] 10. 把 TABLE_SUCCESS_ID / TABLE_FAILURE_ID 写回 .env.feishu
- [ ] 11. 跑 batch 验证三表路由正常
```

### config 模板

```r
feishu = list(
  enable               = TRUE,
  app_id               = Sys.getenv("FEISHU_APP_ID", ""),
  app_secret           = Sys.getenv("FEISHU_APP_SECRET", ""),
  app_token            = Sys.getenv("FEISHU_BITABLE_APP_TOKEN", ""),
  table_id             = Sys.getenv("FEISHU_BITABLE_TABLE_ID", ""),         # Sheet 1
  table_success_id     = Sys.getenv("FEISHU_BITABLE_TABLE_SUCCESS_ID", ""), # Sheet 2
  table_failure_id     = Sys.getenv("FEISHU_BITABLE_TABLE_FAILURE_ID", ""), # Sheet 3
  disease_label        = "01_Urinary_Incontinence",  # Sheet1/2/3「疾病」列显示值
  literature_default   = "NHANES + MIMIC 发病双库（项目描述）",
  protocol_label       = "incidence_XXXXXXXX",   # Sheet1/2/3「套路」列显示值
  project_id           = "YOUR_PROJECT_ID",      # 去重键之一，新项目改这里
  owner_default        = Sys.getenv("FEISHU_OWNER", ""),
  push_on_worker_finish  = TRUE,   # 每指标完成即推 Sheet2/3
  push_on_batch_summary  = TRUE    # batch 结束时更新 Sheet1（不重复推 Sheet2/3）
)
```

### Worker .write_status 里 fields 必含字段

```r
# disease_label 优先保证飞书「疾病」列与 Sheet1 一致（upsert 去重依赖此值）
fields$disease  <- (config_ix$feishu %||% list())$disease_label %||%
                   config_ix$project$disease %||% config_ix$project$analysis_group %||% ""
fields$protocol <- (config_ix$feishu %||% list())$protocol_label %||% ""
```

`fields` 完整清单：`index`, `status`, `db_mode`, `nhanes_branch`, `mimic_branch`,
`nhanes_or`, `mimic_or`, `n_nhanes_before`, `n_nhanes_after`, `n_mimic_before`,
`n_mimic_after`, `error_message`, `elapsed_sec`, `disease`, `protocol`

---

## .env.feishu 模板

```bash
FEISHU_APP_ID=cli_xxxxxxxx
FEISHU_APP_SECRET=xxxxxxxx
FEISHU_BITABLE_APP_TOKEN=J63xxxxxxxx       # wiki/后面 或 base/后面
FEISHU_BITABLE_TABLE_ID=tblxxxxxxxx        # Sheet 1（setup 前已有或 URL 里 table=）
FEISHU_BITABLE_TABLE_SUCCESS_ID=tblxxxxxx  # Sheet 2（run_feishu_setup_tables.R 输出）
FEISHU_BITABLE_TABLE_FAILURE_ID=tblxxxxxx  # Sheet 3（run_feishu_setup_tables.R 输出）
FEISHU_OWNER=张三
```

URL 解析规则：
- 独立多维表格：`base/bascnXXXX` → APP_TOKEN，`table=tblXXXX` → TABLE_ID
- Wiki 内嵌：`wiki/J63XXXX` → APP_TOKEN，`table=tblXXXX` → TABLE_ID

---

## 飞书开放平台（第一层权限）

1. [飞书开放平台](https://open.feishu.cn/app) → 自建应用
2. 权限管理 → 开通 **`bitable:app`**
3. 版本管理与发布 → 创建版本 → 发布（需管理员审批）
4. 记录 App ID（`cli_...`）和 App Secret

---

## 文档级授权（第二层，最常见卡点）

| 操作 | 所需权限 |
|------|---------|
| 读字段/记录 | 可阅读 |
| 写/更新记录 | 可编辑 |
| 创建新数据表（Sheet） | **可管理** |

**正确入口**：表格右上角 **`···`** → 更多 → **「添加文档应用」** → 搜应用名（不是表格标题）→ 选权限

- 首次建三表：给**可管理**
- 之后只写记录：**可编辑**即可

---

## 关键函数速查

| 函数 | 文件 | 调用时机 |
|------|------|---------|
| `feishu_tenant_access_token()` | feishu_bitable.R | 所有 API 调用前 |
| `feishu_bitable_create_record(cfg, fields, table_id)` | feishu_bitable.R | 强制新建记录（不去重） |
| `feishu_bitable_update_record(cfg, table_id, record_id, fields)` | feishu_bitable.R | 更新已有记录 |
| `feishu_bitable_search_records(cfg, table_id, conditions)` | feishu_bitable.R | 按字段值查找记录 |
| `feishu_bitable_upsert_record(cfg, fields, table_id, key_fields, dedup_field)` | feishu_bitable.R | **去重写入**：命中→update，未命中→create；`dedup_field=NULL`（默认不自动填，手动维护） |
| `incidence_batch_feishu_push_result(config, fields)` | feishu_bitable.R | worker 完成时，自动路由+upsert Sheet2/3 |
| `incidence_batch_feishu_update_summary(config, statuses_df)` | feishu_bitable.R | batch 结束后更新 Sheet1 |
| `incidence_batch_feishu_sync_all(config, statuses_df)` | feishu_bitable.R | 补推历史（详情+汇总） |
| `feishu_load_dotenv(root)` | feishu_env.R | 脚本启动时 |

---

## 推送时机与开关

| 开关 | 目标 | 建议值 |
|------|------|--------|
| `push_on_worker_finish = TRUE` | Sheet 2 或 Sheet 3（upsert） | TRUE（实时） |
| `push_on_batch_summary = TRUE` | Sheet 1 汇总行（upsert） | TRUE |
| `run_feishu_sync_batch.R` | 三表全量补推（upsert，幂等） | 手动按需 |

所有写入路径均已改为 **upsert**，重复运行不产生重复行。

---

## 验证命令

```bash
# token + 凭证齐全检查
Rscript run_feishu_test.R

# 试写一条测试记录（写 Sheet1 legacy 字段）
Rscript run_feishu_test.R --write-test

# 三表初始化（新项目运行一次）
Rscript run_feishu_setup_tables.R

# 补推历史 + 更新 Sheet1
Rscript run_feishu_sync_batch.R

# 正式 batch（自动并行路数，无需 --workers）
Rscript run_incidence_dual_batch.R
```

**成功标志**：
- `飞书 Sheet2 成功 [NLR]` / `飞书 Sheet3 失败 [BMI]`
- `Sheet1 汇总行已更新: 成功=N, 失败=N`

---

## 排障

| 现象 | 原因 | 处理 |
|------|------|------|
| `91403 Forbidden` 写记录 | 未「添加文档应用」或权限不足 | 添加应用→可编辑 |
| `1254302 RolePermNotAllow` 建表 | 只有可编辑权限 | 改为可管理后运行 `run_feishu_setup_tables.R` |
| 邀请协作者搜不到应用 | 入口错了 | 用「添加文档应用」不是「邀请协作者」 |
| Sheet2/3 路由到了 Sheet1 | `table_success_id`/`table_failure_id` 为空 | 补写 `.env.feishu` 两个 TABLE_*_ID |
| `disease`/`protocol` 为空 | worker `fields` 未赋值 | worker `.write_status` 里加两行赋值 |
| Sheet1 搜不到汇总行、反复新建 | `feishu$disease_label` 与表里「疾病」列不一致 | config 加 `disease_label` 使两者一致 |
| 日期字段 `DatetimeFieldConvFail` | 字符串格式写日期 | 改用毫秒时间戳 `as.numeric(Sys.time())*1000` |
| `Syntax error: "&" unexpected` | Linux dispatch 旧写法 | `incidence_dual_batch_runner.R` 用 `system2(..., wait=FALSE)` |
| 改代码后旧进程仍出错 | R 进程未重启 | `Ctrl+C` 后重跑 |

---

## 与 batch 架构关系

```
run_*_batch.R（主入口）
  └─ incidence_batch_dispatch_workers
       └─ run_*_batch_worker.R（每指标子进程）
            └─ .write_status(fields) → incidence_batch_feishu_push_result
                 ├─ status=success → Sheet 2（.push_success）
                 └─ status=error   → Sheet 3（.push_failure）
  └─ incidence_batch_feishu_update_summary → Sheet 1 汇总行（若 push_on_batch_summary）
```

`run_*_batch_worker.R` 不能删，主入口并行派发时依赖它。

Worker 派发（Linux/WSL）必须用 `system2(..., wait=FALSE)`，不能用 `system("... &")`。

---

## 扩展（按需开发）

1. **阳性/阴性分类**：在 Sheet2 加「筛选结论」列（`extend_*`→阳性，`degrade_*`→阴性），在 `.push_success` 里写入
2. **负责人映射**：`configs/feishu_owner_map.csv`（指标→负责人），push 时查表填入
3. **飞书回读**：`run_feishu_pull_status.R`，将飞书表中「是否已交付」回写本地

---

## Agent 执行顺序（用户说「配飞书」时）

1. 确认 batch config 路径、`output_base`、`project$disease`
2. 检查/复制核心文件（见清单第 1 步）
3. config 加 feishu 段（含三个 table_id 变量）
4. worker `.write_status` 赋 `disease`/`protocol`
5. 创建 `.env.feishu`，引导用户填 App ID/Secret（勿硬编码）
6. 指导开放平台开通 `bitable:app` + 发布
7. 指导「添加文档应用」→**可管理**
8. `Rscript run_feishu_test.R --write-test` 验证 token
9. `Rscript run_feishu_setup_tables.R` 建三表，记录输出的 table IDs
10. 把两个新 TABLE_ID 写入 `.env.feishu`
11. `Rscript run_feishu_test.R --write-test` 再次验证写入正常
12. 告知用户正式跑 batch 即可

**勿将 App Secret 写入任何 .R 文件或提交 Git。**
