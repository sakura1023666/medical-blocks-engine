#!/usr/bin/env python3
"""对抗阅读 AI-B 调用助手 —— 纯标准库，带 provenance。

优先顺序：
  1) ZHIPU_API_KEY → 智谱 OpenAI 兼容 /chat/completions（默认 glm-5.1）
  2) ANTHROPIC_AUTH_TOKEN + ANTHROPIC_BASE_URL → Anthropic Messages API
     （如阿里云 token-plan /apps/anthropic）

环境变量：
  ZHIPU_API_KEY
  ANTHROPIC_AUTH_TOKEN / ANTHROPIC_BASE_URL / ANTHROPIC_MODEL
  READER_BASE_URL / READER_API_KEY / READER_MODEL  （batch 脚本 AI-A 用）

用法：
  python3 scripts/glm_call.py --system-file prompts/AI_B_tree_critic.md \\
      --user-file rounds/_for_glm/paper_001_Q1.md \\
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
    here = Path(__file__).resolve()
    candidates = [
        Path.cwd() / ".env",
        Path.cwd() / ".env.glm",
        here.parents[1] / ".env",       # adversarial_lit_reading/
        here.parents[2] / ".env",       # 项目根
    ]
    for envfile in candidates:
        if not envfile.exists():
            continue
        for line in envfile.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))


def _http_json(url, payload, headers, timeout=600, retries=2):
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers=headers,
        method="POST",
    )
    last_err = None
    for attempt in range(retries + 1):
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                return json.loads(resp.read().decode("utf-8"))
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
    raise last_err


def chat_openai(base_url, api_key, model, system, user,
                thinking=False, max_tokens=65536, temperature=1.0, timeout=600,
                retries=2):
    """OpenAI 兼容 /chat/completions，返回 (content, data)。"""
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
        payload["thinking"] = {"type": "enabled"}

    data = _http_json(
        f"{base_url.rstrip('/')}/chat/completions",
        payload,
        {"Content-Type": "application/json", "Authorization": f"Bearer {api_key}"},
        timeout=timeout, retries=retries,
    )
    if isinstance(data, dict) and "error" in data:
        raise GlmCallError("api", f"返回 error 结构: {str(data)[:500]}")
    choices = data.get("choices") if isinstance(data, dict) else None
    if not choices:
        raise GlmCallError("api", f"choices 为空: {str(data)[:500]}")
    choice = choices[0]
    content = (choice.get("message") or {}).get("content", "")
    finish = choice.get("finish_reason")
    if finish == "length":
        sys.stderr.write("[glm_call] 警告：finish_reason=length（被 max_tokens 截断）\n")
    if isinstance(content, list):
        # 部分网关返回 content blocks
        content = "".join(
            (b.get("text") or "") if isinstance(b, dict) else str(b) for b in content
        )
    if not str(content).strip():
        raise GlmCallError("api", "返回空 content")
    return str(content), data


def chat_anthropic(base_url, api_key, model, system, user,
                   max_tokens=65536, temperature=1.0, timeout=600, retries=2):
    """Anthropic Messages API（/v1/messages），返回 (content, data)。"""
    if not api_key:
        raise GlmCallError("auth", "缺少 ANTHROPIC_AUTH_TOKEN")
    payload = {
        "model": model,
        "max_tokens": max_tokens,
        "temperature": temperature,
        "messages": [{"role": "user", "content": user}],
        # 关闭深度思考，避免 thinking 吃光 max_tokens 导致 text 空/截断
        "thinking": {"type": "disabled"},
    }
    if system:
        payload["system"] = system
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {api_key}",
        "x-api-key": api_key,
        "anthropic-version": "2023-06-01",
    }
    data = _http_json(
        f"{base_url.rstrip('/')}/v1/messages",
        payload,
        headers,
        timeout=timeout, retries=retries,
    )
    if isinstance(data, dict) and data.get("type") == "error":
        raise GlmCallError("api", f"Anthropic error: {str(data)[:500]}")
    blocks = data.get("content") if isinstance(data, dict) else None
    if not blocks:
        raise GlmCallError("api", f"content 为空: {str(data)[:500]}")
    text_parts, think_parts = [], []
    for b in blocks:
        if not isinstance(b, dict):
            if isinstance(b, str):
                text_parts.append(b)
            continue
        btype = b.get("type")
        if btype == "thinking":
            think_parts.append(b.get("thinking") or "")
        elif btype in ("text", None) or "text" in b:
            text_parts.append(b.get("text") or "")
    content = "".join(text_parts).strip()
    stop = data.get("stop_reason")
    if stop == "max_tokens":
        sys.stderr.write("[glm_call] 警告：stop_reason=max_tokens（被截断）\n")
    # 部分网关（如 deepseek via anthropic）会先吐 thinking；若 text 空但 thinking 有字，
    # 仅在 text 完全空时回退，避免把草稿当终稿却静默失败。
    if not content:
        think = "\n".join(x for x in think_parts if x.strip()).strip()
        if think:
            sys.stderr.write(
                "[glm_call] 警告：仅有 thinking、无 text；将 thinking 回退为输出"
                "（建议增大 --max-tokens）\n"
            )
            content = think
        else:
            raise GlmCallError("api", "返回空 text content（thinking 亦空）")
    return content, data


def chat(base_url, api_key, model, system, user,
         thinking=False, max_tokens=65536, temperature=1.0, timeout=600,
         retries=2, protocol=None):
    """统一入口：protocol=openai|anthropic；返回文本（兼容旧调用方）。"""
    content, _ = chat_with_meta(
        base_url, api_key, model, system, user,
        thinking=thinking, max_tokens=max_tokens, temperature=temperature,
        timeout=timeout, retries=retries, protocol=protocol,
    )
    return content


def chat_with_meta(base_url, api_key, model, system, user,
                   thinking=False, max_tokens=65536, temperature=1.0, timeout=600,
                   retries=2, protocol=None):
    proto = (protocol or "openai").lower()
    if proto == "anthropic":
        return chat_anthropic(
            base_url, api_key, model, system, user,
            max_tokens=max_tokens, temperature=temperature,
            timeout=timeout, retries=retries,
        )
    return chat_openai(
        base_url, api_key, model, system, user,
        thinking=thinking, max_tokens=max_tokens, temperature=temperature,
        timeout=timeout, retries=retries,
    )


def resolve_critic_endpoint():
    """解析 AI-B 端点：优先智谱，其次 Anthropic 兼容网关。"""
    _load_dotenv()
    if os.environ.get("ZHIPU_API_KEY"):
        return {
            "protocol": "openai",
            "base_url": DEFAULT_BASE,
            "api_key": os.environ["ZHIPU_API_KEY"],
            "model": os.environ.get("ZHIPU_MODEL", DEFAULT_MODEL),
        }
    token = os.environ.get("ANTHROPIC_AUTH_TOKEN")
    base = os.environ.get("ANTHROPIC_BASE_URL")
    if token and base:
        return {
            "protocol": "anthropic",
            "base_url": base,
            "api_key": token,
            "model": os.environ.get("ANTHROPIC_MODEL", "deepseek-v4-flash-0731"),
        }
    raise GlmCallError(
        "auth",
        "缺少 ZHIPU_API_KEY，且未配置 ANTHROPIC_AUTH_TOKEN+ANTHROPIC_BASE_URL",
    )


def glm_chat(system, user, *, thinking=False, max_tokens=65536, temperature=1.0):
    """便捷函数：自动解析智谱或 Anthropic 网关。"""
    ep = resolve_critic_endpoint()
    return chat(
        ep["base_url"], ep["api_key"], ep["model"], system, user,
        thinking=thinking, max_tokens=max_tokens, temperature=temperature,
        protocol=ep["protocol"],
    )


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
    ap = argparse.ArgumentParser(description="调用智谱 GLM 或 Anthropic 兼容网关")
    ap.add_argument("--system-file", help="system 提示词文件（通常是角色 Prompt）")
    ap.add_argument("--user-file", required=True, help="user 正文文件")
    ap.add_argument("--out", required=True, help="输出文件路径")
    ap.add_argument("--model", default=None)
    ap.add_argument("--base-url", default=None)
    ap.add_argument("--api-key", default=None)
    ap.add_argument("--protocol", default=None, choices=["openai", "anthropic"])
    ap.add_argument("--thinking", action="store_true", help="启用 GLM 深度思考（攻击者推荐）")
    ap.add_argument("--max-tokens", type=int, default=65536)
    args = ap.parse_args()

    system = Path(args.system_file).read_text(encoding="utf-8") if args.system_file else ""
    user = Path(args.user_file).read_text(encoding="utf-8")

    try:
        if args.api_key or args.base_url or args.protocol:
            protocol = args.protocol or ("anthropic" if "anthropic" in (args.base_url or "") else "openai")
            base = args.base_url or (DEFAULT_BASE if protocol == "openai" else os.environ.get("ANTHROPIC_BASE_URL"))
            key = args.api_key or (
                os.environ.get("ZHIPU_API_KEY") if protocol == "openai"
                else os.environ.get("ANTHROPIC_AUTH_TOKEN")
            )
            model = args.model or (
                DEFAULT_MODEL if protocol == "openai"
                else os.environ.get("ANTHROPIC_MODEL", "deepseek-v4-flash-0731")
            )
        else:
            ep = resolve_critic_endpoint()
            protocol, base, key, model = ep["protocol"], ep["base_url"], ep["api_key"], ep["model"]
            if args.model:
                model = args.model

        content, data_obj = chat_with_meta(
            base, key, model, system, user,
            thinking=args.thinking, max_tokens=args.max_tokens, protocol=protocol,
        )
    except GlmCallError as e:
        sys.exit(f"{e}  ← glm_call 失败：整条对抗流程必须中止，禁止智能体自行生成该步产物。")
    prov = _provenance_line(model, data_obj, content)
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(prov + "\n" + content, encoding="utf-8")
    print(f"[glm_call] -> {args.out}  ({len(content)} chars, protocol={protocol}, model={model})")
