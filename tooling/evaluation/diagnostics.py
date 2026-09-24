"""What the data knows that the app does not show. Informs the teacher;
never enters the number.

Each function takes the student's turn log and/or the replayed states and
returns plain dicts/lists that `evaluate.py` renders into the draft.
"""

from __future__ import annotations

import datetime as dt
import statistics
from collections import Counter, defaultdict

from rules import DIFF_ORDER, NEG_FACTOR, POS_FACTOR, LoState, MilestoneLo, parse_at, turn_scope

# Plain-Dutch labels for the report text; the raw names are app vocabulary.
DIFF_NL = {"easy": "makkelijk", "medium": "gewoon", "hard": "moeilijk"}
TYPE_NL = {
    "mc": "meerkeuze",
    "completeCode": "code aanvullen",
    "explainCode": "code uitleggen",
    "writeCode": "code schrijven",
    "socratic": "gesprek over je antwoord",
}
KIND_NL = {
    "recall": "iets benoemen of herinneren",
    "predict": "voorspellen wat code doet",
    "write": "zelf code schrijven",
    "fix": "een fout in code verbeteren",
    "explain": "uitleggen waarom",
    "reason": "redeneren over code",
}

FOSSIL_MIN_AGE_DAYS = 7
FOSSIL_RECENT_TURNS = 30
FOSSIL_RECENT_ACCURACY = 0.75  # level-weighted, see fossils()
NEAR_MISS_MEAN = 0.70
# With prior (1,1) and μ ≥ 0.80 a LO needs n·w ≥ 3 of positive weight: three
# moderate answers, or two strong ones. Below this many direct questions the
# stamp is out of reach whatever the answers were — "not assessed".
THIN_QUESTIONS = 3


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


def trend(rows: list[dict]) -> dict | None:
    """Accuracy over the first two lesson days vs. the last two: the growth
    a student and their parents can see."""
    if len(rows) < 3:
        return None

    def avg(part):
        t = sum(r["turns"] for r in part)
        return round(sum(r["correct_pct"] * r["turns"] for r in part) / t) if t else 0

    return {
        "first": avg(rows[:2]),
        "last": avg(rows[-2:]),
        "first_days": [r["day"] for r in rows[:2]],
        "last_days": [r["day"] for r in rows[-2:]],
    }


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
            out.append({"lo": lo, "mean": 0.0, "n": 0, "status": "nooit bevraagd", "ratchet": None, "last": None, "thin": True})
            continue
        if s.demonstrated:
            status = "aangetoond, maar hoogste niveau onder het verwachte"
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
                "thin": s.n_direct < THIN_QUESTIONS,
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
        "by_difficulty": {
            DIFF_NL.get(k, k): pct(v)
            for k, v in sorted(by_diff.items(), key=lambda x: ["easy", "medium", "hard"].index(x[0]) if x[0] in DIFF_NL else 9)
        },
        "by_type": {
            TYPE_NL.get(k.replace("Question", ""), k.replace("Question", "")): pct(v)
            for k, v in sorted(by_type.items(), key=lambda x: -sum(x[1].values()))[:5]
        },
        "by_kind": {
            KIND_NL.get(k, k): f"{round(100 * v['positive'] / (v['positive'] + v['negative']))}%"
            for k, v in sorted(by_kind.items())
            if v["positive"] + v["negative"] >= 4
        },
    }


def fossils(los: list[MilestoneLo], st: dict, turns: list[dict], now: dt.datetime) -> list[dict]:
    """Milestone LOs not demonstrated whose last direct probe is old, while
    the student's recent work says they have since moved up. The 30-day
    warm-up review would catch these eventually; this catches them now.

    "Recent work is good" is level-weighted like μ under #169: a correct
    answer on hard counts ×1.4 and a wrong one ×0.6 (the reverse on easy),
    so ~63% raw on hard reads as 0.80, the rule's own mastery bar. Raw
    accuracy never reaches 75% on hard, which hid every fossil in the
    first 6EWI round."""
    recent = turns[-FOSSIL_RECENT_TURNS:]
    if len(recent) < 10:
        return []
    pos = neg = 0.0
    for t in recent:
        d = t.get("difficulty") or "medium"
        if t.get("overallQuality") == "correct":
            pos += POS_FACTOR.get(d, 1.0)
        else:
            neg += NEG_FACTOR.get(d, 1.0)
    if pos / (pos + neg) < FOSSIL_RECENT_ACCURACY:
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
    negatives are the least reliable judgment the system has. On a warm-up
    or recheck the active subgoal is the one the student was on, not the
    one the question was about (`rules.turn_scope`, #195)."""
    pos = neg = 0
    per: dict[tuple[str, str], list[int]] = defaultdict(lambda: [0, 0])
    days: dict[tuple[str, str], set[str]] = defaultdict(set)
    for t in turns:
        scope = turn_scope(t, goals)
        for s in t.get("loSignals") or []:
            sg = s.get("subgoalId")
            if sg not in milestone_subgoals:
                continue
            if scope.reading(goals, sg, s["loId"]) is not None:
                continue  # the conductor applies these
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
