# 跑完项目后的发表质控（C 档）设计

> 日期：2026-09-29  
> 状态：已落地 skill（不对具体历史项目自动审阅）  
> Skill：`.cursor/skills/pub-qc-after-project/`  
> 挂点：`pipeline-foundation` Phase 6

## 目标

每个课题在 batch + 发表收口之后，**立刻**做一次图表质控：结构、交叉数字、逻辑通顺；落盘报告并口头给出 PASS/WARN/FAIL。未出报告不得宣称交付完成。  
**范围：只审 `【success】` 指标/单元，不审 `【failed】` 与裸名目录。**

## 方案

**混合 C 档**：Layer A 可用 `scripts/pub_qc_inventory.py`；Layer B/C 由 Agent 按 checklist 读表读图写 `reports/pub_qc_*.md`。

## 非目标

- 不在用户未点名时扫描 `02block_result` 全盘  
- 不替代外科 xlsx 修复 / 不自动重跑主分析冒充质控  

## 验收（系统级）

- [x] skill + checklist + report-template 存在  
- [x] inventory 脚本可 `--help`  
- [x] `pipeline-foundation` / 提示词 / 汇报稿标准路径含 Phase 6  
- [ ] 用户下次指定项目根时，Agent 按 skill 产出报告（实跑验收）
