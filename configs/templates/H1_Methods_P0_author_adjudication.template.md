# H1 作者裁决 / Methods P0（与 Nature 表图 P0 双轨）

> 模板：`configs/templates/H1_Methods_P0_author_adjudication.template.md`  
> 用法：拷到课题 `summary_results/` 或 `reports/`，按本课题 config/产物填实。  
> **通常只改 Methods 描述，不改代码。**

## 文件应落在

```text
<project_root>/summary_results/H1_Methods_P0_author_adjudication.md
# 或
<project_root>/reports/H1_Methods_P0_author_adjudication.md
```

## 0. 双轨（都要审）

| 轨道 | 工具 | 本课题状态 |
|------|------|------------|
| A Nature 表图 P0 | nature-statistics + nature-figure | PASS/WARN/FAIL → `reports/pub_qc_*.md` |
| B H1 Methods P0 | 本文件 | 填下表 |

## 裁决记录

```text
日期：
回复：全按推荐 / 逐条：
```

## H1 清单（按课题增删）

| # | 问题 | 证据路径 | 定稿结论 | 状态 |
|---|------|----------|----------|------|
| 1 | 模型超参 / 架构定义 | config / meta.json | | [ ] |
| 2 | 时间窗 / landmark / 风险集（含是否排除早期事件） | config landmark / Fig1 | | [ ] |
| 3 | 划分比例与 seed | config split | | [ ] |
| 4 | 插补方法与防泄漏 | config imputation | | [ ] |
| 5 | 主表 SD / CI / bootstrap 口径 | Table 脚注 / S 表 | | [ ] |
| 6 | 外验库版本与纳排链 | 外验说明 txt | | [ ] |
| 7 | 阴性/劣势指标如何写（NRI、外验衰减等） | S 表 | | [ ] |
| 8 | 软件版本与未使用包 | Software_versions_*.txt | | [ ] |
| 9 | α / 单双侧 / 切点来源 | config / Methods | | [ ] |
| 10 | TRIPOD / STROBE / 其它清单 | 作者定 | | [ ] |

## Methods 可粘贴段（填实后）

```text
（英文）
（中文）
```

## 检查清单

- [ ] 轨道 A 已跑并落盘
- [ ] 本表 H1 全部有定稿结论
- [ ] 未把「只写描述」的项误开成全库重跑
