#!/usr/bin/env python3
"""全自动对抗训练编排（医学文献对抗式阅读用）。方案 B：纯脚本全自动。

来源：操作手册第 11.3 章「全自动对抗训练伪代码」；升级版接入 GLM 5.1 API + 自动归一化 + 校验分桶。

依赖：scripts/glm_call.py（纯标准库）+ 环境变量 ZHIPU_API_KEY。
AI-A 与 AI-B 默认都走 GLM-5.1；要异构对抗，设 READER_BASE_URL/READER_API_KEY/READER_MODEL。

用法：
  python3 scripts/batch_adversarial_run.py --reader glm-5.1 --critic glm-5.1 \
      --papers paper_001,paper_002 --questions Q1,Q2,Q4,Q5,Q8 --sleep 2
"""
from __future__ import annotations
import argparse, datetime, json, os, subprocess, sys, time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import glm_call  # noqa: E402

PROMPTS = {
    "reader":  ROOT / "prompts" / "AI_A_reader_decision_tree.md",
    "critic":  ROOT / "prompts" / "AI_B_tree_critic.md",
    "reviser": ROOT / "prompts" / "AI_A_revise_decision_tree.md",
    "judge":   ROOT / "prompts" / "Judge_labeler.md",
}
SCORE_KEYS = ["evidence_accuracy", "method_understanding", "tree_logic",
              "critique_absorption", "limitations_transfer", "expression_rigor"]
VALIDATE = ROOT / "scripts" / "validate_jsonl.py"


def call_model(model, prompt_path, context, *extras):
    """model 支持：'glm-5.1'（默认 GLM）、'reader:<model>'（走 READER_* 端点）、'glm:<model>'。"""
    sys_p = prompt_path.read_text(encoding="utf-8")
    user = "\n\n---\n\n".join([context, *extras])
    base, key = glm_call.DEFAULT_BASE, os.environ.get("ZHIPU_API_KEY")
    if model.startswith("reader:"):
        base = os.environ.get("READER_BASE_URL", glm_call.DEFAULT_BASE)
        key = os.environ.get("READER_API_KEY") or key
        model = model.split(":", 1)[1]
    elif model.startswith("glm:"):
        model = model.split(":", 1)[1]
    thinking = "critic" in prompt_path.name   # 仅攻击者开深度思考
    return glm_call.chat(base, key, model, sys_p, user,
                         thinking=thinking, max_tokens=65536)


def load_paper_text(paper_id: str) -> str:
    """读取 chunks/<paper_id>_*.md 全文。"""
    matches = list((ROOT / "chunks").glob(f"{paper_id}_*.md"))
    if not matches:
        sys.exit(f"[batch] 未找到 {paper_id} 的 chunk，请先运行 pdf_to_chunks.py")
    return matches[0].read_text(encoding="utf-8")


def _normalize_record(record: dict) -> dict:
    """归一化，防 validate FAIL：int 转换 + 键名白名单 + 缺失补 0 + 重算 score + 注入 metadata。"""
    raw_sd = record.get("score_detail") or {}
    sd = {k: int(raw_sd.get(k, 0) or 0) for k in SCORE_KEYS}
    record["score_detail"] = sd
    record["score"] = sum(sd.values())           # 无条件重算，覆盖 GLM 任何漂移
    md = record.setdefault("metadata", {})
    md.update({"reader_model": "Cursor model", "critic_model": "GLM 5.1",
               "judge": "Cursor model (Judge_labeler)",
               "created_at": datetime.date.today().isoformat()})
    return record


def _validate(path: Path) -> bool:
    r = subprocess.run([sys.executable, str(VALIDATE), "--input", str(path)],
                       capture_output=True, text=True)
    return r.returncode == 0


def _bucket_and_save(paper_id: str, qid: str, record: dict) -> str:
    """PASS 且 score>=8 进 training.jsonl；6-7 进 review_needed；<=5 或 FAIL 进 reject。"""
    line = json.dumps(record, ensure_ascii=False)
    per = ROOT / "labels" / f"{paper_id}_{qid}_training.jsonl"
    per.write_text(line + "\n", encoding="utf-8")
    ok = _validate(per)
    score = record.get("score", 0)
    if ok and score >= 8:
        with (ROOT / "labels" / "training.jsonl").open("a", encoding="utf-8") as fh:
            fh.write(line + "\n")
        return "train"
    dest = "review_needed" if (ok and 6 <= score < 8) else "reject"
    d = ROOT / "labels" / dest
    d.mkdir(parents=True, exist_ok=True)
    (d / f"{paper_id}_{qid}_training.jsonl").write_text(line + "\n", encoding="utf-8")
    return dest


def run_pipeline(paper_id: str, question_id: str, question: str,
                 reader_model: str, critic_model: str) -> str:
    """对单篇论文 × 单个问题跑完整 A1→B1→A2→Judge 流程，返回分桶名。"""
    context = load_paper_text(paper_id)

    a1 = call_model(reader_model, PROMPTS["reader"], context, question)
    (ROOT / "rounds" / f"A_tree_round1_{paper_id}_{question_id}.md").write_text(a1, encoding="utf-8")

    b1 = call_model(critic_model, PROMPTS["critic"], context, a1)
    (ROOT / "rounds" / f"B_attack_tree_{paper_id}_{question_id}.md").write_text(b1, encoding="utf-8")

    a2 = call_model(reader_model, PROMPTS["reviser"], context, a1, b1)
    (ROOT / "rounds" / f"A_tree_round2_revised_{paper_id}_{question_id}.md").write_text(a2, encoding="utf-8")

    judged_raw = call_model(reader_model, PROMPTS["judge"], context, a1, b1, a2)
    record = glm_call.extract_json(judged_raw)
    record = _normalize_record(record)
    return _bucket_and_save(paper_id, question_id, record)


def main() -> int:
    glm_call._load_dotenv()
    ap = argparse.ArgumentParser(description="全自动对抗训练编排（需 ZHIPU_API_KEY）")
    ap.add_argument("--reader", default="glm-5.1", help="AI-A 模型 id（可 reader:<m> 走另一端点）")
    ap.add_argument("--critic", default="glm-5.1", help="AI-B 模型 id")
    ap.add_argument("--papers", default="all",
                    help="逗号分隔的 paper_id 列表，或 all（处理 chunks/ 全部）")
    ap.add_argument("--questions", default="Q1,Q2,Q4,Q5,Q8",
                    help="逗号分隔的 question_id 列表")
    ap.add_argument("--sleep", type=float, default=0.0, help="样本间退避秒数（缓解 429）")
    args = ap.parse_args()

    papers = (sorted({p.name.split("_")[0] for p in (ROOT / "chunks").glob("paper_*_*.md")})
              if args.papers == "all"
              else [p.strip() for p in args.papers.split(",") if p.strip()])
    questions = [q.strip() for q in args.questions.split(",") if q.strip()]
    if not papers:
        sys.exit("[batch] 没有可处理的论文，请先运行 pdf_to_chunks.py")

    print(f"[batch] papers={papers} questions={questions} "
          f"reader={args.reader} critic={args.critic}")
    counters = {"train": 0, "review_needed": 0, "reject": 0}
    for paper_id in papers:
        for qid in questions:
            question = f"{qid}（见 prompts/question_templates_medical.md 第 8.1 节）"
            print(f"[batch] >> {paper_id} / {qid}")
            try:
                bucket = run_pipeline(paper_id, qid, question, args.reader, args.critic)
                counters[bucket] = counters.get(bucket, 0) + 1
                print(f"[batch]    -> {bucket}")
            except Exception as e:  # noqa: BLE001
                print(f"[batch] {paper_id}/{qid} 失败：{e}")
            if args.sleep:
                time.sleep(args.sleep)

    print(f"[batch] 完成。分桶：{counters}")
    print("提示：python3 scripts/validate_jsonl.py --input labels/training.jsonl")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
