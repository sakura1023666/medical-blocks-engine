#!/usr/bin/env python3
"""JSONL 训练数据校验脚本（医学文献对抗式阅读用）。

来源：操作手册第 7.3 章 JSONL 标准格式 + 第 7.1 章 Rubric。
校验 ``labels/*.jsonl`` 是否符合 schema，并按 score 分桶统计（train/review/reject）。

依赖：仅 Python 标准库（无第三方依赖）。

用法
----
    python3 scripts/validate_jsonl.py --input labels/training.jsonl
    python3 scripts/validate_jsonl.py --input labels/training.jsonl --strict
    python3 scripts/validate_jsonl.py --input labels/training.jsonl --fix-hints
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter
from pathlib import Path

# ── schema 常量（与 decision_tree_schema.md / rubrics/scoring_rubric_10pt.md 同源）──

TASK_TYPE = "literature_decision_tree_reasoning"
TOTAL_SCORE_MAX = 10

SCORE_DETAIL_KEYS = {
    "evidence_accuracy": (0, 3),
    "method_understanding": (0, 2),
    "tree_logic": (0, 2),
    "critique_absorption": (0, 1),
    "limitations_transfer": (0, 1),
    "expression_rigor": (0, 1),
}
SCORE_DETAIL_MAX_SUM = sum(hi for _, hi in SCORE_DETAIL_KEYS.values())  # 10

TOP_LEVEL_REQUIRED = [
    "paper_id", "question_id", "task_type", "question", "context",
    "rejected_answer", "rejected_decision_tree", "critique",
    "chosen_answer", "chosen_decision_tree", "evidence", "score",
    "score_detail", "metadata",
]

DECISION_TREE_REQUIRED = ["mermaid", "nodes", "edges"]
EVIDENCE_ITEM_REQUIRED = ["evidence_id", "location", "summary"]
METADATA_REQUIRED = ["reader_model", "critic_model", "judge", "created_at"]

QUESTION_ID_RE = re.compile(r"^Q[1-8]$")
ISO_DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}")

# mermaid 轻量健全性：含分支/箭头/方括号任一即可（仅警告，不致命）
MERMAID_TOKENS = ("-->", "---", "if", "{{", "}", "]")


def _is_nonempty_str(v) -> bool:
    return isinstance(v, str) and v.strip() != ""


def validate_record(rec: dict, errors: list[str], lineno: int) -> str | None:
    """校验单条记录，把错误追加到 errors。返回 QC 分桶名或 None。"""
    prefix = f"line {lineno}"

    def add(msg: str):
        errors.append(f"[{prefix}] {msg}")

    # 1) 顶层必填键
    for k in TOP_LEVEL_REQUIRED:
        if k not in rec:
            add(f"缺少顶层字段: {k}")

    # 2) task_type
    if rec.get("task_type") != TASK_TYPE:
        add(f"task_type 必须为 '{TASK_TYPE}'，实际为 {rec.get('task_type')!r}")

    # 3) paper_id / question_id
    if not _is_nonempty_str(rec.get("paper_id")):
        add("paper_id 必须为非空字符串")
    qid = rec.get("question_id")
    if not (isinstance(qid, str) and QUESTION_ID_RE.match(qid)):
        add(f"question_id 必须形如 Q1~Q8，实际为 {qid!r}")

    # 4) 文本字段
    for k in ("question", "context", "rejected_answer", "critique", "chosen_answer"):
        if not _is_nonempty_str(rec.get(k)):
            add(f"{k} 必须为非空字符串")

    # 5) 决策树（rejected / chosen）
    for key in ("rejected_decision_tree", "chosen_decision_tree"):
        tree = rec.get(key)
        if not isinstance(tree, dict):
            add(f"{key} 必须为对象")
            continue
        for rk in DECISION_TREE_REQUIRED:
            if rk not in tree:
                add(f"{key} 缺少字段: {rk}")
        if not _is_nonempty_str(tree.get("mermaid")):
            add(f"{key}.mermaid 必须为非空字符串")
        elif not any(tok in tree["mermaid"] for tok in MERMAID_TOKENS):
            add(f"{key}.mermaid 似乎不像决策树（未检测到分支/箭头标记）", )  # 警告级
        # nodes
        nodes = tree.get("nodes")
        if not isinstance(nodes, list):
            add(f"{key}.nodes 必须为列表")
        else:
            node_ids: set[str] = set()
            for n in nodes:
                if not isinstance(n, dict) or not _is_nonempty_str(n.get("node_id")):
                    add(f"{key}.nodes 中存在无 node_id 的节点: {n!r}")
                    continue
                nid = n["node_id"]
                if nid in node_ids:
                    add(f"{key} 中 node_id 重复: {nid}")
                node_ids.add(nid)
            # edges
            edges = tree.get("edges")
            if isinstance(edges, list):
                for e in edges:
                    if not isinstance(e, dict):
                        add(f"{key}.edges 中存在非对象边: {e!r}")
                        continue
                    src, dst = e.get("from"), e.get("to")
                    if src not in node_ids:
                        add(f"{key}.edges 悬空起点: {src!r}（不在 nodes 中）")
                    if dst not in node_ids:
                        add(f"{key}.edges 悬空终点: {dst!r}（不在 nodes 中）")

    # 6) evidence
    ev = rec.get("evidence")
    if not isinstance(ev, list) or len(ev) == 0:
        add("evidence 必须为非空列表")
    else:
        ev_ids: set[str] = set()
        for item in ev:
            if not isinstance(item, dict):
                add(f"evidence 项非对象: {item!r}")
                continue
            for k in EVIDENCE_ITEM_REQUIRED:
                if not _is_nonempty_str(item.get(k)):
                    add(f"evidence 项缺少/为空: {k} ({item!r})")
            eid = item.get("evidence_id")
            if isinstance(eid, str) and eid in ev_ids:
                add(f"evidence_id 重复: {eid}")
            if isinstance(eid, str):
                ev_ids.add(eid)

    # 7) 分数一致性（核心规则）
    score = rec.get("score")
    sd = rec.get("score_detail")
    if not isinstance(score, int) or isinstance(score, bool) or not (0 <= score <= TOTAL_SCORE_MAX):
        add(f"score 必须为 0-10 的整数，实际为 {score!r}")
    if not isinstance(sd, dict):
        add("score_detail 必须为对象")
    else:
        extra = set(sd.keys()) - set(SCORE_DETAIL_KEYS.keys())
        if extra:
            add(f"score_detail 含未定义维度: {sorted(extra)}")
        detail_sum = 0
        for k, (lo, hi) in SCORE_DETAIL_KEYS.items():
            v = sd.get(k)
            if not isinstance(v, int) or isinstance(v, bool) or not (lo <= v <= hi):
                add(f"score_detail.{k} 必须为 {lo}-{hi} 的整数，实际为 {v!r}")
            else:
                detail_sum += v
        if detail_sum > SCORE_DETAIL_MAX_SUM:
            add(f"score_detail 六维度之和 {detail_sum} 超过总分上限 {SCORE_DETAIL_MAX_SUM}")
        if (isinstance(score, int) and not isinstance(score, bool)
                and detail_sum != score):
            add(f"分数不一致: sum(score_detail)={detail_sum} 但 score={score}（必须相等）")

    # 8) metadata
    md = rec.get("metadata")
    if not isinstance(md, dict):
        add("metadata 必须为对象")
    else:
        for k in METADATA_REQUIRED:
            if k == "created_at":
                if not (isinstance(md.get(k), str) and ISO_DATE_RE.match(md.get(k, ""))):
                    add(f"metadata.{k} 必须为 ISO 日期 YYYY-MM-DD，实际为 {md.get(k)!r}")
            elif not _is_nonempty_str(md.get(k)):
                add(f"metadata.{k} 必须为非空字符串")

    # QC 分桶
    if isinstance(score, int) and not isinstance(score, bool):
        if score >= 8:
            return "train"
        if score >= 6:
            return "review"
        return "reject"
    return None


def main() -> int:
    ap = argparse.ArgumentParser(description="校验 JSONL 训练数据")
    ap.add_argument("--input", required=True, help="待校验的 .jsonl 文件路径")
    ap.add_argument("--strict", action="store_true",
                    help="严格模式：score<=5（reject）视为失败")
    ap.add_argument("--fix-hints", action="store_true",
                    help="为常见错误打印修正建议（只读，不改文件）")
    args = ap.parse_args()

    path = Path(args.input)
    if not path.exists():
        sys.exit(f"[validate_jsonl] 文件不存在: {path}")

    all_errors: list[str] = []
    buckets: Counter[str] = Counter()
    n_records = 0
    n_bad = 0

    try:
        with path.open("r", encoding="utf-8") as fh:
            for lineno, raw in enumerate(fh, start=1):
                raw = raw.strip()
                if not raw:
                    continue  # 空行跳过
                try:
                    rec = json.loads(raw)
                except json.JSONDecodeError as e:
                    all_errors.append(f"[line {lineno}] JSON 解析失败: {e}")
                    n_bad += 1
                    continue
                if not isinstance(rec, dict):
                    all_errors.append(f"[line {lineno}] 顶层不是 JSON 对象")
                    n_bad += 1
                    continue
                rec_errors: list[str] = []
                bucket = validate_record(rec, rec_errors, lineno)
                all_errors.extend(rec_errors)
                n_records += 1
                if rec_errors:
                    n_bad += 1
                if bucket:
                    buckets[bucket] += 1
    except UnicodeDecodeError as e:
        sys.exit(f"[validate_jsonl] 文件非 UTF-8 编码: {e}")

    # ── 报告 ──
    print(f"输入: {path}")
    print(f"记录总数: {n_records}  |  含错误记录: {n_bad}")
    print(f"QC 分桶: train(>=8)={buckets.get('train', 0)}  "
          f"review(6-7)={buckets.get('review', 0)}  "
          f"reject(<=5)={buckets.get('reject', 0)}")

    if all_errors:
        print("\n── 错误明细 ──")
        for e in all_errors:
            print(e)
        if args.fix_hints:
            print("\n── 常见修正建议 ──")
            if any("分数不一致" in e for e in all_errors):
                print("· score 必须 == sum(score_detail 六维度)，请调整使二者相等。")
            if any("悬空" in e for e in all_errors):
                print("· edges 的 from/to 必须是 nodes 中已存在的 node_id。")
            if any("node_id 重复" in e for e in all_errors):
                print("· 同一棵决策树内 node_id 必须唯一。")
            if any("question_id 必须形如" in e for e in all_errors):
                print("· question_id 取值范围 Q1~Q8。")

    strict_fail = args.strict and buckets.get("reject", 0) > 0
    ok = (n_bad == 0) and not strict_fail
    print(f"\n结果: {'PASS ✓' if ok else 'FAIL ✗'}"
          + ("（--strict：存在 reject 样本）" if strict_fail else ""))
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
