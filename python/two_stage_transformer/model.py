"""model.py — 两阶段(B 轨)+ 单阶段(A2 轨)Transformer(通用纵向时序二分类)。

迁移自 `code/model_5day.py`，`TwoStageTransformer` 算法逐字保留：
  Stage1 hour-level(天内采样点 self-attention + avg-pool -> daily rep)
  + Stage2 day-level(跨天 self-attention + day_mask + 取截止日 -> 预测)。
F/D/H 全参数化(不限于 5 天/24 小时/226 特征)。

新增 `SingleStageTransformer`(A2 轨，统一规范管线下的单阶段公平基线):
  把 (D,H,F) 展平成一条长度 D*H 的序列，一次 self-attention 编码，
  用同样的 day_mask/cutoff 语义截断到指定天，取最后一个有效位置预测。
  与 B 轨共享 encoder 组件、优化器、损失、训练循环，只有"两阶段 vs 单阶段"
  这一个结构变量不同，用于对比小时+天两阶段注意力的增量价值(A2 vs B)。
"""
from __future__ import annotations

import copy
import math

import torch
import torch.nn as nn
import torch.nn.functional as F

device = torch.device("cuda" if torch.cuda.is_available() else "cpu")


def day_k_keep_count(cutoff, D: int):
    """Day-k 预测可用天数：只用前 k-1 天（后续 mask），对齐原文 Methods。

    Day1 无日级数据时「前 0 天」不可用，退回保留 day1（【场景迁移】标注）。
    返回与 cutoff 同型的 keep 天数（至少 1）。
    """
    if isinstance(cutoff, torch.Tensor):
        return torch.clamp(cutoff.long() - 1, min=1)
    c = D if cutoff is None else int(cutoff)
    return max(c - 1, 1)


class Norm(nn.Module):
    def __init__(self, d_model, eps=1e-6):
        super().__init__()
        self.alpha = nn.Parameter(torch.ones(d_model))
        self.bias = nn.Parameter(torch.zeros(d_model))
        self.eps = eps

    def forward(self, x):
        return self.alpha * (x - x.mean(dim=-1, keepdim=True)) / (x.std(dim=-1, keepdim=True) + self.eps) + self.bias


def attention(q, k, v, d_k, mask=None, dropout=None):
    scores = torch.matmul(q, k.transpose(-2, -1)) / math.sqrt(d_k)
    scores = F.softmax(scores, dim=-1)
    if dropout is not None:
        scores = dropout(scores)
    return torch.matmul(scores, v)


class MultiHeadAttention(nn.Module):
    def __init__(self, heads, d_model, dropout=0.5):
        super().__init__()
        self.d_model, self.d_k, self.h = d_model, d_model // heads, heads
        self.q_linear = nn.Linear(d_model, d_model)
        self.k_linear = nn.Linear(d_model, d_model)
        self.v_linear = nn.Linear(d_model, d_model)
        self.dropout = nn.Dropout(dropout)
        self.out = nn.Linear(d_model, d_model)

    def forward(self, q, k, v, mask=None):
        bs = q.size(0)
        k = self.k_linear(k).view(bs, -1, self.h, self.d_k).transpose(1, 2)
        q = self.q_linear(q).view(bs, -1, self.h, self.d_k).transpose(1, 2)
        v = self.v_linear(v).view(bs, -1, self.h, self.d_k).transpose(1, 2)
        scores = attention(q, k, v, self.d_k, mask, self.dropout)
        return self.out(scores.transpose(1, 2).contiguous().view(bs, -1, self.d_model))


class FeedForward(nn.Module):
    def __init__(self, d_model, d_ff=512, dropout=0.5):
        super().__init__()
        self.linear_1 = nn.Linear(d_model, d_ff)
        self.dropout = nn.Dropout(dropout)
        self.linear_2 = nn.Linear(d_ff, d_model)

    def forward(self, x):
        return self.linear_2(self.dropout(F.relu(self.linear_1(x))))


class EncoderLayer(nn.Module):
    def __init__(self, d_model, heads, dropout=0.5):
        super().__init__()
        self.norm_1 = Norm(d_model)
        self.norm_2 = Norm(d_model)
        self.attn = MultiHeadAttention(heads, d_model, dropout)
        self.ff = FeedForward(d_model)
        self.dropout_1 = nn.Dropout(dropout)
        self.dropout_2 = nn.Dropout(dropout)

    def forward(self, x, mask=None):
        x2 = self.norm_1(x)
        x = x + self.dropout_1(self.attn(x2, x2, x2, mask))
        x2 = self.norm_2(x)
        x = x + self.dropout_2(self.ff(x2))
        return x


def get_clones(module, n):
    return nn.ModuleList([copy.deepcopy(module) for _ in range(n)])


class PositionalEncoder(nn.Module):
    def __init__(self, d_model, max_len=512):
        super().__init__()
        self.d_model = d_model
        pe = torch.zeros(max_len, d_model)
        pos = torch.arange(0, max_len).unsqueeze(1).float()
        div = torch.exp(torch.arange(0, d_model, 2).float() * (-math.log(10000.0) / d_model))
        pe[:, 0::2] = torch.sin(pos * div)
        pe[:, 1::2] = torch.cos(pos * div)
        self.register_buffer("pe", pe.unsqueeze(0))

    def forward(self, x):  # x: (B, S, d_model)
        s = x.size(1)
        if s > self.pe.size(1):
            raise RuntimeError(
                f"sequence length {s} exceeds PositionalEncoder max_len={self.pe.size(1)}"
            )
        return x * math.sqrt(self.d_model) + self.pe[:, :s]


class Encoder(nn.Module):
    def __init__(self, d_model, N, heads, dropout, max_len=512):
        super().__init__()
        self.N = N
        self.pe = PositionalEncoder(d_model, max_len=max_len)
        self.layers = get_clones(EncoderLayer(d_model, heads, dropout), N)
        self.norm = Norm(d_model)

    def forward(self, x):
        x = self.pe(x)
        for i in range(self.N):
            x = self.layers[i](x, None)
        return self.norm(x)


class TwoStageTransformer(nn.Module):
    """两阶段(B 轨 / A1 轨复用同一结构):hour-level encoder(天内)+ day-level encoder(跨天)。"""

    def __init__(self, n_days=5, n_hours=24, n_features=226,
                 d_model=128, heads=4, N=2, dropout=0.5, n_classes=2):
        super().__init__()
        assert d_model % heads == 0, f"d_model={d_model} 必须能被 heads={heads} 整除"
        self.n_days, self.n_hours, self.n_features = n_days, n_hours, n_features
        self.in_proj = nn.Linear(n_features, d_model)  # F -> d_model(任意 F)
        self.hour_enc = Encoder(d_model, N, heads, dropout, max_len=max(n_hours, 64))  # seq=H
        self.day_enc = Encoder(d_model, N, heads, dropout, max_len=max(n_days, 64))  # seq=D
        self.fc = nn.Sequential(
            nn.Linear(d_model, 128), nn.ReLU(), nn.Dropout(dropout),
            nn.Linear(128, n_classes),
        )

    def forward(self, x, day_mask=None, cutoff=None):
        # x:(B,D,H,F)  day_mask:(B,D){1=在院,0=缺失}  cutoff:int(统一)或 tensor(B,)(per-sample)
        # Day-k 语义：只用前 k-1 天（mask 第 k 天及之后）；Day1 保留 day1（日级迁移）。
        B, D, H, nf = x.shape
        assert nf == self.n_features, f"特征维应为 {self.n_features},实际 {nf}"
        h = x.reshape(B * D, H, nf)  # (B*D, H, F)
        h = self.in_proj(h)  # (B*D, H, d_model)
        h = self.hour_enc(h)  # (B*D, H, d_model)
        h = h.mean(dim=1)  # avg-pool over H -> (B*D, d_model)
        h = h.reshape(B, D, -1)  # (B, D, d_model)
        if day_mask is None:
            return F.log_softmax(self.fc(self.day_enc(h)[:, -1, :]), dim=1)
        ar = torch.arange(D, device=x.device)
        if isinstance(cutoff, torch.Tensor):  # per-sample cutoff(训练)
            n_keep = day_k_keep_count(cutoff, D)
            cmask = (ar[None, :] < n_keep[:, None]).float()
            h = h * (day_mask * cmask).unsqueeze(-1)
            rep = self.day_enc(h)[torch.arange(B, device=x.device), n_keep - 1]
        else:  # 统一 cutoff(评估)
            n_keep = day_k_keep_count(cutoff, D)
            cmask = (ar < n_keep).float()
            h = h * (day_mask * cmask).unsqueeze(-1)
            rep = self.day_enc(h)[:, n_keep - 1, :]
        return F.log_softmax(self.fc(rep), dim=1)


class SingleStageTransformer(nn.Module):
    """单阶段(A2 轨公平基线):(D,H,F) 展平为一条 D*H 长序列,单层 self-attention 编码。

    与 TwoStageTransformer 共享同一训练循环/优化器/损失/day_mask 语义，
    唯一结构差异是不做"小时内 -> 跨天"两级注意力，用于对比两阶段的增量价值。
    """

    def __init__(self, n_days=5, n_hours=24, n_features=226,
                 d_model=128, heads=4, N=2, dropout=0.5, n_classes=2):
        super().__init__()
        assert d_model % heads == 0, f"d_model={d_model} 必须能被 heads={heads} 整除"
        self.n_days, self.n_hours, self.n_features = n_days, n_hours, n_features
        self.in_proj = nn.Linear(n_features, d_model)
        # expand_hours 后 seq=D*H（如 5×24=120），PE 必须覆盖该长度
        self.enc = Encoder(d_model, N, heads, dropout, max_len=max(n_days * n_hours, 64))
        self.fc = nn.Sequential(
            nn.Linear(d_model, 128), nn.ReLU(), nn.Dropout(dropout),
            nn.Linear(128, n_classes),
        )

    def forward(self, x, day_mask=None, cutoff=None):
        B, D, H, nf = x.shape
        assert nf == self.n_features, f"特征维应为 {self.n_features},实际 {nf}"
        h = self.in_proj(x.reshape(B, D * H, nf))  # (B, D*H, d_model)
        ar_day = torch.arange(D, device=x.device)
        if day_mask is None:
            h = self.enc(h)
            rep = h[:, -1, :]
            return F.log_softmax(self.fc(rep), dim=1)
        if isinstance(cutoff, torch.Tensor):  # per-sample cutoff(训练)
            n_keep = day_k_keep_count(cutoff, D)
            cmask_day = (ar_day[None, :] < n_keep[:, None]).float()  # (B,D)
            full_mask = (day_mask * cmask_day).unsqueeze(-1).repeat(1, 1, H).reshape(B, D * H, 1)
            h = h * full_mask
            h = self.enc(h)
            last_idx = n_keep * H - 1
            rep = h[torch.arange(B, device=x.device), last_idx]
        else:  # 统一 cutoff(评估)
            n_keep = day_k_keep_count(cutoff, D)
            cmask_day = (ar_day < n_keep).float()
            full_mask = (day_mask * cmask_day).unsqueeze(-1).repeat(1, 1, H).reshape(B, D * H, 1)
            h = h * full_mask
            h = self.enc(h)
            rep = h[:, n_keep * H - 1, :]
        return F.log_softmax(self.fc(rep), dim=1)


ARCH_REGISTRY = {
    "b": TwoStageTransformer,
    "a1": TwoStageTransformer,  # 公开实现原结构(单独命名,训练循环不同,见 train.py)
    "a2": SingleStageTransformer,
}


def build_model(arch: str, n_days: int, n_hours: int, n_features: int, **kwargs) -> nn.Module:
    arch = (arch or "b").lower()
    if arch not in ARCH_REGISTRY:
        raise ValueError(f"未知 arch={arch!r},可选 {sorted(ARCH_REGISTRY)}")
    cls = ARCH_REGISTRY[arch]
    return cls(n_days=n_days, n_hours=n_hours, n_features=n_features, **kwargs)


if __name__ == "__main__":
    torch.manual_seed(0)
    B, D, H, NF = 4, 5, 24, 226
    x = torch.randn(B, D, H, NF)
    dm = torch.ones(B, D)
    dm[0, 3:] = 0
    dm[1, 4:] = 0
    for arch in ("b", "a2"):
        m = build_model(arch, D, H, NF).to(device)
        xx, dmm = x.to(device), dm.to(device)
        print(f"参数量[{arch}]: {sum(p.numel() for p in m.parameters()):,}")
        for c in range(1, D + 1):
            out = m(xx, dmm, c)
            assert out.shape == (B, 2)
        print(f"[{arch}] Day1..{D} forward OK")
