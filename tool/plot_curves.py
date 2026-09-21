"""학습 산출물(curve.csv, eval.json) → PPT용 그래프 PNG.

사용: python tool/plot_curves.py [--out dungeon_core/out] [--dest docs/ppt]
생성: learning_curve.png (승률·평균 리턴 vs 에피소드, 단계 마커 3개)
      stage_stats.png    (단계별 승률/평균 턴/함정/물약/처치 막대)
      eval_curve.png     (체크포인트별 고정 평가셋 승률, 단계 마커)
"""
from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

# ── 팔레트 (디자인 시안과 동일) ──────────────────────────
VOID, STONE, LINE = "#120F1A", "#1E1A2A", "#3A3350"
PARCHMENT, MUTED = "#EFE6D3", "#9A8FB0"
VIOLET, EMBER, GOLD, POTION = "#A879FF", "#FF7A45", "#F2C14E", "#5AD07A"
STAGE_COLORS = {1: MUTED, 2: VIOLET, 3: GOLD}
STAGE_NAMES = {1: "1단계 풋내기", 2: "2단계 노련한", 3: "3단계 각성한"}

plt.rcParams.update({
    "font.family": "Malgun Gothic",
    "axes.unicode_minus": False,
    "figure.facecolor": VOID,
    "axes.facecolor": STONE,
    "axes.edgecolor": LINE,
    "axes.labelcolor": PARCHMENT,
    "xtick.color": MUTED,
    "ytick.color": MUTED,
    "text.color": PARCHMENT,
    "grid.color": LINE,
    "grid.alpha": 0.6,
    "legend.facecolor": STONE,
    "legend.edgecolor": LINE,
    "savefig.dpi": 200,
})


def moving_avg(xs: list[float], k: int) -> list[float]:
    out: list[float] = []
    acc = 0.0
    for i, x in enumerate(xs):
        acc += x
        if i >= k:
            acc -= xs[i - k]
        out.append(acc / min(i + 1, k))
    return out


def load_curve(path: Path) -> list[dict]:
    with path.open(encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    for r in rows:
        r["episode"] = int(r["episode"])
        for k in ("winRate", "avgReturn", "avgSteps"):
            r[k] = float(r[k])
    return rows


def stage_episodes(ev: dict | None) -> dict[int, int]:
    if not ev or "stages" not in ev:
        return {}
    out = {}
    for s in (1, 2, 3):
        v = ev["stages"].get(f"stage{s}")
        if isinstance(v, int):
            out[s] = v
    return out


def draw_stage_markers(ax, stages: dict[int, int], ymax: float | None = None):
    for s, ep in stages.items():
        ax.axvline(ep, color=STAGE_COLORS[s], linestyle="--", linewidth=1.4, alpha=0.9)
        y = ymax if ymax is not None else ax.get_ylim()[1]
        ax.annotate(
            STAGE_NAMES[s], xy=(ep, y), xytext=(6, -14), textcoords="offset points",
            color=STAGE_COLORS[s], fontsize=9, fontweight="bold",
        )


def plot_learning_curve(rows: list[dict], stages: dict[int, int], dest: Path):
    eps = [r["episode"] for r in rows]
    win = [r["winRate"] * 100 for r in rows]
    ret = [r["avgReturn"] for r in rows]
    k = max(1, len(rows) // 25)

    fig, ax1 = plt.subplots(figsize=(11, 5.2))
    ax1.plot(eps, win, color=VIOLET, alpha=0.28, linewidth=1)
    ax1.plot(eps, moving_avg(win, k), color=VIOLET, linewidth=2.4, label="승률 (이동평균)")
    ax1.set_xlabel("학습 에피소드")
    ax1.set_ylabel("학습 중 승률 (%)", color=VIOLET)
    ax1.set_ylim(0, 100)
    ax1.grid(True, linewidth=0.5)

    ax2 = ax1.twinx()
    ax2.plot(eps, ret, color=EMBER, alpha=0.22, linewidth=1)
    ax2.plot(eps, moving_avg(ret, k), color=EMBER, linewidth=2.0, label="평균 리턴 (이동평균)")
    ax2.set_ylabel("에피소드 평균 리턴", color=EMBER)
    ax2.tick_params(axis="y", colors=EMBER)

    # 커리큘럼 구간 배경 (Balance.curriculumEasyEnd 0.2, curriculumMediumEnd 0.6)
    total = eps[-1]
    for lo, hi, alpha, label in ((0.0, 0.2, 0.0, "easy"), (0.2, 0.6, 0.04, "medium"), (0.6, 1.0, 0.08, "hard · 적대적 · 고정")):
        if alpha > 0:
            ax1.axvspan(lo * total, hi * total, color=PARCHMENT, alpha=alpha, linewidth=0)
        ax1.text((lo + hi) / 2 * total, 3, label, ha="center", va="bottom", fontsize=9, color=MUTED)

    draw_stage_markers(ax1, stages, ymax=97)
    h1, l1 = ax1.get_legend_handles_labels()
    h2, l2 = ax2.get_legend_handles_labels()
    ax1.legend(h1 + h2, l1 + l2, loc="lower right", fontsize=9)
    ax1.set_title("용사 Q-learning 학습 곡선 (커리큘럼: easy → medium → hard/적대적/고정)", fontsize=13, pad=12)
    fig.tight_layout()
    fig.savefig(dest / "learning_curve.png")
    plt.close(fig)


def plot_eval_curve(ev: dict, stages: dict[int, int], dest: Path):
    ck = ev.get("checkpoints", [])
    if not ck:
        return
    eps = [c["episode"] for c in ck]
    win = [c["stats"]["winRate"] * 100 for c in ck]
    trap = [c["stats"]["trapHits"] for c in ck]

    fig, ax1 = plt.subplots(figsize=(11, 5.0))
    ax1.plot(eps, win, color=VIOLET, linewidth=2.2, marker="o", markersize=3, label="고정 평가셋 승률 (300 배치)")
    ax1.set_ylim(0, 100)
    ax1.set_xlabel("체크포인트 (에피소드)")
    ax1.set_ylabel("승률 (%)", color=VIOLET)
    ax1.grid(True, linewidth=0.5)
    ax2 = ax1.twinx()
    ax2.plot(eps, trap, color=EMBER, linewidth=1.8, label="에피소드당 함정 밟은 횟수")
    ax2.set_ylabel("함정 밟은 횟수", color=EMBER)
    ax2.tick_params(axis="y", colors=EMBER)
    for s, ep in stages.items():
        ax1.scatter([ep], [win[eps.index(ep)]] if ep in eps else [0], s=120, color=STAGE_COLORS[s], zorder=5, edgecolor=PARCHMENT)
    draw_stage_markers(ax1, stages, ymax=97)
    h1, l1 = ax1.get_legend_handles_labels()
    h2, l2 = ax2.get_legend_handles_labels()
    ax1.legend(h1 + h2, l1 + l2, loc="center right", fontsize=9)
    rule = ev.get("selectionRule", "")
    ax1.set_title(f"체크포인트 평가와 단계 선정 (선정 규칙: {rule})", fontsize=13, pad=12)
    fig.tight_layout()
    fig.savefig(dest / "eval_curve.png")
    plt.close(fig)


def plot_stage_stats(ev: dict, out: Path, dest: Path):
    metas = []
    for s in (1, 2, 3):
        p = out / f"policy_stage{s}.json"
        if not p.exists():
            continue
        with p.open(encoding="utf-8") as f:
            metas.append(json.load(f)["meta"])
    if not metas:
        return
    keys = [("winRate", "승률", 100, "%"), ("avgSteps", "평균 턴", 1, ""), ("trapHits", "함정 밟음", 1, "회"),
            ("potionsUsed", "물약 사용", 1, "개"), ("kills", "처치", 1, "마리")]
    fig, axes = plt.subplots(1, len(keys), figsize=(13, 3.8))
    for ax, (k, label, scale, unit) in zip(axes, keys):
        xs = [m["stage"] for m in metas]
        ys = [m[k] * scale for m in metas]
        bars = ax.bar([STAGE_NAMES[x].split()[0] for x in xs], ys, color=[STAGE_COLORS[x] for x in xs], width=0.62)
        for b, y in zip(bars, ys):
            ax.text(b.get_x() + b.get_width() / 2, b.get_height(), f"{y:.1f}{unit}", ha="center", va="bottom", fontsize=9)
        ax.set_title(label, fontsize=11)
        ax.set_ylim(0, max(ys) * 1.28 if max(ys) > 0 else 1)
        ax.grid(True, axis="y", linewidth=0.5)
        for sp in ("top", "right"):
            ax.spines[sp].set_visible(False)
    demo = ev.get("demo", {})
    sub = "  ".join(f"{STAGE_NAMES[s].split()[0]} 데모: {'용사 승' if demo.get(f'stage{s}') else '방어 성공'}" for s in (1, 2, 3) if f"stage{s}" in demo)
    fig.suptitle("단계별 행동 통계 (고정 평가셋 300배치, ε=0.03 동일)" + (f"\n{sub}" if sub else ""), fontsize=12)
    fig.tight_layout()
    fig.savefig(dest / "stage_stats.png")
    plt.close(fig)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="dungeon_core/out")
    ap.add_argument("--dest", default="docs/ppt")
    a = ap.parse_args()
    out, dest = Path(a.out), Path(a.dest)
    dest.mkdir(parents=True, exist_ok=True)

    ev = None
    if (out / "eval.json").exists():
        ev = json.loads((out / "eval.json").read_text(encoding="utf-8"))
    stages = stage_episodes(ev)

    if (out / "curve.csv").exists():
        plot_learning_curve(load_curve(out / "curve.csv"), stages, dest)
        print("learning_curve.png")
    if ev:
        plot_eval_curve(ev, stages, dest)
        print("eval_curve.png")
        plot_stage_stats(ev, out, dest)
        print("stage_stats.png")


if __name__ == "__main__":
    main()
