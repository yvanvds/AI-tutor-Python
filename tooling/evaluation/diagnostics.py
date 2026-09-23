"""What the data knows that the app does not show. Informs the teacher;
never enters the number.

Each function takes the student's turn log and/or the replayed states and
returns plain dicts/lists that `evaluate.py` renders into the draft.
"""

from __future__ import annotations

import datetime as dt
import statistics
from collections import Counter, defaultdict

from rules import DIFF_ORDER, LoState, MilestoneLo, parse_at, same_root_backward

FOSSIL_MIN_AGE_DAYS = 7
FOSSIL_RECENT_TURNS = 30
FOSSIL_RECENT_ACCURACY = 0.75
NEAR_MISS_MEAN = 0.70


def timeline(turns: list[dict]) -> list[dict]:
    """One row per lesson day: volume, accuracy, calibration, subgoals."""
    by_day: dict[str, list[dict]] = defaultdict(list)
    for t in turns:
        by_day[t["turnAt"][:10]].append(t)
    rows = []
    for day in sorted(by_day):
        L = by_day[day]
        q = Counter(t.get("overallQuality") for t in L)
        sg = Counter(t["subgoalId"] for t in L)
        rows.append(
            {
                "day": day,
                "turns": len(L),
                "correct_pct": round(100 * q["correct"] / len(L)),
                "calibration_end": L[-1].get("calibrationAfter"),
                "advanced": sum(1 for t in L if t.get("subgoalAdvanced")),
                "subgoals": ", ".join(f"{k}:{v}" for k, v in sg.most_common(3)),
            }
        )
    return rows


def absences(turns: list[dict], class_days: set[str]) -> list[str]:
    """Days the class worked and this student did not."""
    mine = {t["turnAt"][:10] for t in turns}
    return sorted(class_days - mine)


def near_misses(los: list[MilestoneLo], st: dict, expected: str) -> list[dict]:
    """Milestone LOs not demonstrated, nearest first."""
    exp = DIFF_ORDER[expected]
    out = []
    for lo in los:
        s = st.get(lo.key)
        if s and s.demonstrated and DIFF_ORDER[s.ratchet] >= exp:
            continue
        if s is None:
            out.append({"lo": lo, "mean": 0.0, "n": 0, "status": "nooit gemeten", "ratchet": None, "last": None})
            continue
        if s.demonstrated:
            status = "gestempeld, maar ratel onder verwacht niveau"
        elif s.mean >= NEAR_MISS_MEAN:
            status = "bijna"
        else:
            status = "ver"
        out.append(
            {
                "lo": lo,
                "mean": s.mean,
                "n": s.n_direct,
                "status": status,
                "ratchet": s.ratchet,
                "last": s.last_direct_at.date().isoformat() if s.last_direct_at else None,
            }
        )
    out.sort(key=lambda r: -r["mean"])
    return out


def profile(turns: list[dict]) -> dict:
    """Answer behaviour: think time, quality split, where the student fails."""
    gaps = []
    for i in range(1, len(turns)):
        g = (parse_at(turns[i]["turnAt"]) - parse_at(turns[i - 1]["turnAt"])).total_seconds()
        if 5 < g < 900:
            gaps.append(g)
    n = max(1, len(turns))
    q = Counter(t.get("overallQuality") for t in turns)
    by_diff: dict[str, Counter] = defaultdict(Counter)
    by_type: dict[str, Counter] = defaultdict(Counter)
    by_kind: dict[str, Counter] = defaultdict(Counter)
    strong_neg = all_neg = 0
    for t in turns:
        by_diff[t.get("difficulty") or "?"][t.get("overallQuality")] += 1
        by_type[t.get("questionType") or "?"][t.get("overallQuality")] += 1
        for s in t.get("loSignals") or []:
            if s.get("signal") in ("positive", "negative"):
                by_kind[s["loId"].split("_")[0]][s["signal"]] += 1
                if s["signal"] == "negative":
                    all_neg += 1
                    strong_neg += s.get("strength") == "strong"

    def pct(c: Counter) -> str:
        tot = sum(c.values())
        return f"{round(100 * c['correct'] / tot)}% ({tot})" if tot else "-"

    return {
        "turns": len(turns),
        "think_time_s": round(statistics.median(gaps)) if gaps else None,
        "correct_pct": round(100 * q["correct"] / n),
        "partial_pct": round(100 * q["partial"] / n),
        "wrong_pct": round(100 * q["wrong"] / n),
        "follow_up_pct": round(100 * sum(1 for t in turns if t.get("isFollowUp")) / n),
        "strong_neg_share": round(100 * strong_neg / all_neg) if all_neg else None,
        "by_difficulty": {k: pct(v) for k, v in sorted(by_diff.items())},
        "by_type": {k.replace("Question", ""): pct(v) for k, v in sorted(by_type.items(), key=lambda x: -sum(x[1].values()))[:5]},
        "by_kind": {
            k: f"{round(100 * v['positive'] / (v['positive'] + v['negative']))}%"
            for k, v in sorted(by_kind.items())
            if v["positive"] + v["negative"] >= 4
        },
    }


def fossils(los: list[MilestoneLo], st: dict, turns: list[dict], now: dt.datetime) -> list[dict]:
    """Milestone LOs not demonstrated whose last direct probe is old, while
    the student's recent work says they have since moved up. The 30-day
    warm-up review would catch these eventually; this catches them now."""
    recent = turns[-FOSSIL_RECENT_TURNS:]
    if len(recent) < 10:
        return []
    acc = sum(1 for t in recent if t.get("overallQuality") == "correct") / len(recent)
    if acc < FOSSIL_RECENT_ACCURACY:
        return []
    out = []
    for lo in los:
        s = st.get(lo.key)
        if not s or s.demonstrated or not s.last_direct_at:
            continue
        age = (now - s.last_direct_at).days
        if age >= FOSSIL_MIN_AGE_DAYS:
            out.append({"lo": lo, "mean": s.mean, "age_days": age})
    return out


def discarded_cross_root(turns: list[dict], goals: dict, milestone_subgoals: set[str]) -> dict:
    """Grader signals on the milestone's LOs produced while the student
    worked in another root goal. The conductor drops these ("outside the
    active root"). Positives are direct evidence of "she can do it now";
    negatives are the least reliable judgment the system has."""
    pos = neg = 0
    per: dict[tuple[str, str], list[int]] = defaultdict(lambda: [0, 0])
    days: dict[tuple[str, str], set[str]] = defaultdict(set)
    for t in turns:
        active = t["subgoalId"]
        for s in t.get("loSignals") or []:
            sg = s.get("subgoalId")
            if sg not in milestone_subgoals or sg == active:
                continue
            if same_root_backward(goals, sg, active):
                continue  # same root: the conductor applies these
            key = (sg, s["loId"])
            if s.get("signal") == "positive":
                pos += 1
                per[key][0] += 1
                days[key].add(t["turnAt"][5:10])
            elif s.get("signal") == "negative":
                neg += 1
                per[key][1] += 1
    top = sorted(per.items(), key=lambda x: -x[1][0])[:5]
    return {
        "positive": pos,
        "negative": neg,
        "top": [
            {"lo": k[1], "subgoal": k[0], "pos": v[0], "neg": v[1], "days": sorted(days[k])}
            for k, v in top
        ],
    }
