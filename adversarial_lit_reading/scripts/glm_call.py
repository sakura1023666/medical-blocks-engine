#!/usr/bin/env python3
"""GLM 5.1（智谱 BigModel）调用助手 —— 纯标准库，OpenAI 兼容接口，带 provenance。

供「一键对抗阅读」的 AI-B（攻击者）使用，也供 batch_adversarial_run.py
在纯脚本全自动模式下调用任意 OpenAI 兼容端点（GLM / DeepSeek / OpenAI 兼容网关）。

环境变量：
  ZHIPU_API_KEY   智谱 API key（必填，AI-B 用）
  READER_BASE_URL / READER_API_KEY / READER_MODEL  可选，AI-A 在纯脚本模式的端点

用法：
  python3 scripts/glm_call.py --system-file prompts/AI_B_tree_critic.md \
      --user-file rounds/_for_glm/paper_001_Q1.md \
      --out rounds/B_attack_tree_paper_001_Q1.md --thinking
"""
from __future__ import annotations
import argparse, datetime, json, os, sys, time, urllib.request, urllib.error
from pathlib import Path

DEFAULT_BASE = "https://open.bigmodel.cn/api/paas/v4"
DEFAULT_MODEL = "glm-5.1"
GLM_HOSTS = ("bigmodel.cn", "z.ai")  # 仅这些端点发送 thinking 字段


class GlmCallError(RuntimeError):
    """结构化错误：调用方可据 stage/http_code 决定中止还是重试。"""
    def __init__(self, stage, msg, http_code=None):
        super().__init__(f"[{stage}] {msg}")
        self.stage, self.http_code, self.msg = stage, http_code, msg


def _load_dotenv() -> None:
    """极简 .env 读取：把 KEY=VALUE 装进 os.environ（不覆盖已有值）。"""
    candidates = [Path.cwd() / ".env", Path.cwd() / ".env.glm",
                  Path(__file__).resolve().parents[1] / ".env"]
    for envfile in candidates:
        if not envfile.exists():
            continue
        for line in envfile.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))


def chat(base_url, api_key, model, system, user,
         thinking=False, max_tokens=65536, temperature=1.0, timeout=600,
         retries=2):
    """调用 OpenAI 兼容 /chat/completions，返回纯文本。429/5xx 有限重试。"""
    if not api_key:
        raise GlmCallError("auth", "缺少 API key（设 ZHIPU_API_KEY 或 --api-key）")
    messages = []
    if system:
        messages.append({"role": "system", "content": system})
    messages.append({"role": "user", "content": user})
    send_thinking = thinking and any(h in base_url for h in GLM_HOSTS)
    payload = {"model": model, "messages": messages, "max_tokens": max_tokens,
               "temperature": temperature, "stream": False}
    if send_thinking:
        payload["thinking"] = {"type": "enabled"}   # 非 GLM 端点剥离，避免 400

    req = urllib.request.Request(
        f"{base_url.rstrip('/')}/chat/completions",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {api_key}"},
        method="POST")
    last_err = None
    for attempt in range(retries + 1):
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                data = json.loads(resp.read().decode("utf-8"))
            break
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", "ignore")[:800]
            last_err = GlmCallError("http", f"HTTP {e.code}: {body}", e.code)
            if e.code in (429, 500, 502, 503, 504) and attempt < retries:
                time.sleep(2 ** attempt)
                continue
            raise last_err
        except urllib.error.URLError as e:
            last_err = GlmCallError("network", str(e))
            if attempt < retries:
                time.sleep(2 ** attempt)
                continue
            raise last_err
    else:
        raise last_err

    # 返回前自检：杜绝空/截断内容被静默当攻击意见
    if isinstance(data, dict) and "error" in data:
        raise GlmCallError("api", f"返回 error 结构: {str(data)[:500]}")
    choices = data.get("choices") if isinstance(data, dict) else None
    if not choices:
        raise GlmCallError("api", f"choices 为空: {str(data)[:500]}")
    choice = choices[0]
    content = (choice.get("message") or {}).get("content", "")
    finish = choice.get("finish_reason")
    if finish == "length":
        sys.stderr.write(f"[glm_call] 警告：finish_reason=length（被 max_tokens 截断，"
                         f"建议增大 --max-tokens）\n")
    if not content.strip():
        raise GlmCallError("api", "返回空 content（疑似被 thinking 耗尽预算，"
                           "增大 max_tokens 或关闭 thinking）")
    return content


def glm_chat(system, user, *, thinking=False, max_tokens=65536, temperature=1.0):
    """便捷函数：直接用 ZHIPU_API_KEY 调 GLM-5.1。"""
    key = os.environ.get("ZHIPU_API_KEY")
    if not key:
        raise GlmCallError("auth", "缺少 ZHIPU_API_KEY（设环境变量或在 .env 里配置）")
    return chat(DEFAULT_BASE, key, DEFAULT_MODEL, system, user,
                thinking=thinking, max_tokens=max_tokens, temperature=temperature)


def extract_json(text):
    """从模型输出抠单个 JSON（去 ```json 围栏 + 状态机找首个平衡 {...}）。
    对 JSON 字符串值内的 { } 安全（mermaid 含花括号也不误截）。"""
    s = text.strip()
    if s.startswith("```"):
        s = s.split("\n", 1)[1] if "\n" in s else s
        if s.endswith("```"):
            s = s[:-3]
        s = s.strip()
    start = s.find("{")
    if start < 0:
        raise ValueError("未找到 JSON 起始 '{'")
    depth, end, in_str, esc = 0, -1, False, False
    for i, ch in enumerate(s[start:], start):
        if in_str:
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == '"':
                in_str = False
        else:
            if ch == '"':
                in_str = True
            elif ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    end = i
                    break
    if end < 0:
        raise ValueError("JSON 大括号未闭合")
    return json.loads(s[start:end + 1])


def _provenance_line(model, data, content):
    rid = ""
    usage = {}
    if isinstance(data, dict):
        rid = data.get("id", "") or ""
        usage = data.get("usage", {}) or {}
    return ("<!-- glm_call provenance: "
            f"model={model} | ts={datetime.datetime.now().isoformat(timespec='seconds')} "
            f"| request_id={rid} | usage={json.dumps(usage, ensure_ascii=False)} "
            f"| char_len={len(content)} -->")


if __name__ == "__main__":
    _load_dotenv()
    ap = argparse.ArgumentParser(description="调用 GLM 5.1（或任意 OpenAI 兼容端点）")
    ap.add_argument("--system-file", help="system 提示词文件（通常是角色 Prompt）")
    ap.add_argument("--user-file", required=True, help="user 正文文件")
    ap.add_argument("--out", required=True, help="输出文件路径")
    ap.add_argument("--model", default=DEFAULT_MODEL)
    ap.add_argument("--base-url", default=DEFAULT_BASE)
    ap.add_argument("--api-key", default=None, help="默认读 ZHIPU_API_KEY")
    ap.add_argument("--thinking", action="store_true", help="启用 GLM 深度思考（攻击者推荐）")
    ap.add_argument("--max-tokens", type=int, default=65536)
    args = ap.parse_args()

    system = Path(args.system_file).read_text(encoding="utf-8") if args.system_file else ""
    user = Path(args.user_file).read_text(encoding="utf-8")
    key = args.api_key or os.environ.get("ZHIPU_API_KEY")
    try:
        content = chat(args.base_url, key, args.model, system, user,
                       thinking=args.thinking, max_tokens=args.max_tokens)
        data_obj = {}  # CLI 模式仅写来源标记；如需 request_id/usage 可让 chat() 返回 (content, data)
    except GlmCallError as e:
        sys.exit(f"{e}  ← glm_call 失败：整条对抗流程必须中止，禁止智能体自行生成该步产物。")
    prov = _provenance_line(args.model, data_obj, content)
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(prov + "\n" + content, encoding="utf-8")
    print(f"[glm_call] -> {args.out}  ({len(content)} chars, provenance written)")
