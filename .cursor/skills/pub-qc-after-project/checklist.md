# 发表质控检查清单（C 档）

Agent 按层打勾；不适用项写 `N/A` + 一句理由。

## §0 范围（先做）

- [ ] 只枚举 `【success】*`；已统计并跳过全部 `【failed】*` 与裸名 `by_index/<INDEX>/`
- [ ] 聊天已列出「将审 success」与「failed 仅计数」
- [ ] 用户点名的指标若无 success 产物 → 跳过并记 WARN，未打开 failed 目录

## §A 结构（硬）

- [ ] 审阅根路径已确认（Windows/WSL 等价）
- [ ] 成功单元列表已列出（且仅为 success）
- [ ] `Figures/pdf|png|tiff|image_information` 存在
- [ ] Figures 根无残留平铺 `Figure*.pdf`
- [ ] 每张定稿 pdf 有同 stem 的 png + tiff
- [ ] tiff 体积 > 0（过小视为缺失）
- [ ] 每张图有对应 `image_information/*.md`
- [ ] md 含 `## 图面说明` + `## 分析上下文`；无 `## 标识` / `## 技术`
- [ ] Fig1（若有）md 含逐步 n 与排除人数
- [ ] Tables 主文/补充命名与角色一致
- [ ] 双库：同角色同 S 号（或课题约定）；无次库独有列泄漏（Gate A）
- [ ] 中介门控：未导出时无 Associations / Path diagram 残留
- [ ] 成功指标 `code/README.md` + `run.R`（发病/预后/ML dual-batch 主分析）

## §B 交叉数字

来源优先级：attrition CSV → Table xlsx/csv → `_batch_status.json` → rds 旁路元数据 → `image_information` → 图面可读标注。

- [ ] Fig1 逐步 n = attrition CSV（分库）
- [ ] Table1 总 N（或分析集）与 Fig1 终步 / status.json 一致（允许脚注说明的加权/子集）
- [ ] 主效应表 OR/HR(CI) 与森林 Overall 同对比、同模型
- [ ] KM Log-rank / cutoff 与 md、源 cutoff 表一致
- [ ] RCS P-overall / P-nonlinear / cutoff 与 md 一致
- [ ] 分段 Cox / Firth‡ 脚注与表内符号一致
- [ ] 双库拼图：暴露对比（最高 vs 最低）、年龄切点、N 口径一致
- [ ] ML：Table 主指标与 Fig 校准/ROC 同源（同 n、同 cutoff 规则）

冲突记录格式：`左侧来源 | 数值 | 右侧来源 | 数值 | 差分说明`

## §C 逻辑通顺（Agent）

- [ ] 暴露/结局命名在表题、图题、md 上下文一致（疾病显示名，非裸列名泄漏）
- [ ] 参照组方向正确（Q1/T1/非暴露为 Ref）
- [ ] 亚组：二分类年龄；非旧 Q1+Q4 子集冒充全人群（除非 config 显式）
- [ ] 补充表编号连续、无错位角色
- [ ] 脚注解释了权重、分母、‡、NE
- [ ] 无明显「阴性当阳性」表述残留
- [ ] P0/P1/P2 已分级（P0=阻断交稿）

## 套路专项（按需）

### 轨迹
- [ ] 类别数 ng、最小类占比与 Table2/健康 guard 脚注一致
- [ ] 潜类别 KM / dynpred 类别标签与轨迹图一致（双库若独立拟合，勿误写迁移验证）

### IPW
- [ ] 加权前后 SMD / Table1 角色齐全
- [ ] 暴露定义（如 HbA1c 阈值）与硬排除不进 PS 一致

### TST
- [ ] Table2 Day5 与 Table3 / S6 字符串级对齐；脚注含 test n 与对照分数可得 n
