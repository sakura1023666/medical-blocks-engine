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
日期：YYYY-MM-DD
回复：全按推荐
备注：默认确认（用户授权「以后都默认确定 H1」）；Agent 填实推荐结论后勾满 [x]，勿再停等作者逐条确认。
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
| 7a | Figure vs Table：主图是否单次快照、表是否 bootstrap 权威 | Fig2 md / Table2 脚注 | 表权威；图注写 snapshot n | [ ] |
| 7b | 外验筛选只写首末数+可评定义，中间不造数 | 外验纳排 txt | | [ ] |
| 7c | 外验无严重度对照时：只报 TF 衰减/校准，不写「未做对照」 | Methods Limitations | | [ ] |
| 7d | 未记录的优化器/最大轮数正文省略；Software 不列未用包 | Methods Software | | [ ] |
| 7e | Day1–5 同一 landmark 测试队列；短住院不外推 | Methods Limitations | | [ ] |
| 8 | 软件版本与未使用包 | Software_versions_*.txt | | [ ] |
| 9 | α / 单双侧 / 切点来源 | config / Methods | | [ ] |
| 10 | TRIPOD / STROBE / 其它清单 | 作者定 | | [ ] |
| 11 | **NHANES** 复合指标公式全文 + 系数出处（成人外推一句） | Methods / index block | | [ ] |
| 12 | **NHANES** MICE：method、m、seed、结局是否入模、complete#1 vs Rubin | config$imputation / Methods | | [ ] |
| 13 | **NHANES** new_Weight 构造 + SDMVSTRA/PSU；主切点=加权、敏感性不加权须标明 | Fig1 / Methods / S1·S10 脚注 | | [ ] |
| 14 | **NHANES** Table2 Model2 调整集与中介/RCS 脚注同集；总效应≠主表 OR 须脚注不硬拗 | Table2 / S12 | | [ ] |
| 15 | **NHANES** 终模路径 S3–S7；S5 暴露效应消失如实写 | Methods / S5 | | [ ] |
| 16 | **NHANES** ROC 只报图面 AUC；禁自曝内部算法试验；Fig NE 与 md 一致 | Fig S* md / Fig3 | | [ ] |

> 11–16：无 NHANES 加权发病可整行 N/A。细则见 `.cursor/rules/pub_nhanes_incidence_p0_gate.mdc`。

## Methods 可粘贴段（填实后）

```text
（英文）
（中文）
```

## 检查清单

- [ ] 轨道 A 已跑并落盘
- [ ] 本表 H1 全部有定稿结论，且已按默认政策勾满 `[x]`（全按推荐）
- [ ] 未把「只写描述」的项误开成全库重跑
