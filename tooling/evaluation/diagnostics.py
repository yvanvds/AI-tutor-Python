"""What the data knows that the app does not show. Informs the teacher;
never enters the number.

Each function takes the student's turn log and/or the replayed states and
returns plain dicts/lists that `evaluate.py` renders into the draft.
"""

from __future__ import annotations

import datetime as dt
import statistics
from collections import Counter, defaultdict

from rules import DIFF_ORDER, NEG_FACTOR, POS_FACTOR, LoState, MilestoneLo, belgian_time, is_audit, parse_at, turn_scope

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
# How many of an LO's last direct answers the concept shows (#189).
LAST_ANSWERS = 5


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


def evidence(s: LoState | None) -> dict:
    """Where an LO's belief came from (#189), read off the replay: the
    questions and how many were answered right, the follow-ups, the
    incidental signals that passed the conductor's filter, the transfer
    credits; and the last direct answers, with the run of right ones at the
    end. A μ of 0.93 on "2 questions" may be two wrong answers and 27
    incidental right ones (#188); this says which."""
    if s is None:
        return {"n": 0, "n_pos": 0, "follow_up": (0, 0), "incidental": (0, 0), "transfer": 0, "recent": [], "streak": 0}
    streak = 0
    for d in reversed(s.direct_signals):
        if d.signal != "positive":
            break
        streak += 1
    return {
        "n": s.n_direct,
        "n_pos": s.n_direct_pos,
        "follow_up": (s.n_follow_up_pos, s.n_follow_up_neg),
        "incidental": (s.n_incidental_pos, s.n_incidental_neg),
        "transfer": s.n_transfer,
        "recent": s.direct_signals[-LAST_ANSWERS:],
        "streak": streak,
    }


def near_misses(los: list[MilestoneLo], st: dict, expected: str) -> list[dict]:
    """Milestone LOs not demonstrated, nearest first."""
    exp = DIFF_ORDER[expected]
    out = []
    for lo in los:
        s = st.get(lo.key)
        if s and s.demonstrated and DIFF_ORDER[s.ratchet] >= exp:
            continue
        if s is None:
            out.append({"lo": lo, "mean": 0.0, "status": "nooit bevraagd", "ratchet": None, "last": None, "thin": True, **evidence(None)})
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
                "status": status,
                "ratchet": s.ratchet,
                "last": s.last_direct_at.date().isoformat() if s.last_direct_at else None,
                "thin": s.n_direct < THIN_QUESTIONS,
                **evidence(s),
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


def lost_oefeningen(turns: list[dict], goals: dict, milestone_subgoals: set[str]) -> dict:
    """Direct questions whose grade left no signal on the LO they asked
    about (#225): the oefening counted for nothing on its own LO. A direct
    question here is a first answer (no follow-up) on the active subgoal (no
    warm-up or recheck), and no audit record. Its own LO is the turn's
    target (`targetLOIds`) under its `subgoalId`.

    What is gone does not come back: the record keeps `overallQuality` and
    the signals that survived, nothing of the one that was dropped. The
    cause is the app's (a stale grading scope dropped the signal, #225) or
    the grader's (it judged other LOs and not the asked one). Grouped per
    LO, most first."""
    total = correct = in_ms = 0
    per: dict[tuple[str, str], dict] = {}
    for t in turns:
        if is_audit(t) or t.get("isFollowUp") or t.get("isWarmUp") or t.get("isRecheck"):
            continue
        sg = t["subgoalId"]
        targets = set(t.get("targetLOIds") or [])
        if not targets:
            continue
        if any(s.get("subgoalId") == sg and s.get("loId") in targets for s in t.get("loSignals") or []):
            continue
        lo = (t.get("targetLOIds") or [])[0]
        right = t.get("overallQuality") == "correct"
        total += 1
        correct += right
        in_ms += sg in milestone_subgoals
        row = per.setdefault(
            (sg, lo),
            {"subgoal": sg, "lo": lo, "n": 0, "correct": 0, "days": [], "in_milestone": sg in milestone_subgoals},
        )
        row["n"] += 1
        row["correct"] += right
        day = t["turnAt"][5:10]
        if day not in row["days"]:
            row["days"].append(day)
    for row in per.values():
        g = goals.get(row["subgoal"]) or {}
        row["subgoal_title"] = g.get("title") or row["subgoal"]
        row["statement"] = next(
            (o.get("statement") for o in g.get("objectives") or [] if o.get("id") == row["lo"]), None
        ) or row["lo"]
    return {
        "total": total,
        "correct": correct,
        "in_milestone": in_ms,
        "per": sorted(per.values(), key=lambda r: (-r["n"], r["days"][0])),
    }


# ---- trace (#228) ------------------------------------------------------------

# Why a grader signal did not count, as `SignalDropReason` names it.
DROP_NL = {
    "outOfScope": "buiten de scope",
    "targetOutOfScope": "gevraagd leerdoel buiten de scope",
    "unknownLo": "onbekend leerdoel",
    "laterSubgoal": "later subdoel",
    "outsideActiveRoot": "buiten het actieve hoofddoel",
    "incidentalNegative": "negatief van opzij",
    "incidentalNeutral": "neutraal van opzij",
}
SESSION_START_NL = {
    "startup": "opstart",
    "continueLearningPath": "Verder in Leerpad",
    "workOnGoal": "Werk hieraan",
    "restart": "herstart in de chat",
}


def _signal_key(s: dict) -> tuple:
    return (s.get("subgoalId"), s.get("loId"), s.get("signal"), s.get("strength"))


def trace_signals(turn: dict | None, content: dict | None) -> list[dict]:
    """The grader's signals on one oefening (#228), each with what became of
    it: `telt` (it passed every check), `weggegooid` with the reason, `sleutel`
    (a grader's signal the answer key replaced, #186) or `terugval` (the weak
    signal the app put on the asked LO when every signal dropped). Without a
    content doc only the turn record's signals are known: `aanvaard` — they
    passed the scope check, and the conductor may still have declined one."""
    if content is None:
        return [{**s, "status": "aanvaard"} for s in (turn or {}).get("loSignals") or []]
    out: list[dict] = []
    dropped = list(content.get("droppedSignals") or [])
    raw = content.get("rawSignals") or []
    checked = raw
    if turn is not None and turn.get("gradedByKey"):
        out.extend({**s, "status": "sleutel"} for s in raw)
        checked = turn.get("loSignals") or []
    for s in checked:
        hit = next((d for d in dropped if _signal_key(d) == _signal_key(s)), None)
        if hit is None:
            out.append({**s, "status": "telt"})
        else:
            dropped.remove(hit)
            out.append({**s, "status": "weggegooid", "reason": hit.get("reason")})
    # A drop with no raw signal to go with it: shown all the same.
    out.extend({**d, "status": "weggegooid"} for d in dropped)
    if turn is not None and turn.get("hadFallback"):
        out.extend({**s, "status": "terugval"} for s in turn.get("loSignals") or [])
    return out


def trace(turns: list[dict], contents: dict[str, dict], goals: dict) -> list[dict]:
    """One row per oefening (#228), oldest first: the turn record and the
    content doc with the same id. A turn without content (from before #228,
    or a write that failed) and content without a turn (a turn record
    deleted by a progress reset) both get a row with what there is. Audit
    records are not oefeningen and are left out."""
    by_id: dict[str, tuple[dict | None, dict | None]] = {}
    for t in turns:
        if not is_audit(t):
            by_id[t["id"]] = (t, contents.get(t["id"]))
    for cid, c in contents.items():
        by_id.setdefault(cid, (None, c))
    rows = []
    for tid, (t, c) in by_id.items():
        src = t or c
        sg = src.get("subgoalId")
        g = goals.get(sg) or {}
        lo = ((t or {}).get("targetLOIds") or [None])[0]
        statement = next((o.get("statement") for o in g.get("objectives") or [] if o.get("id") == lo), None)
        qtype = (src.get("questionType") or "").replace("Question", "")
        context = dict((c or {}).get("context") or {})
        rows.append(
            {
                "id": tid,
                "at": belgian_time(parse_at(src["turnAt"])),
                "subgoal": sg,
                "subgoal_title": g.get("title") or sg,
                "lo": lo,
                "statement": statement,
                "type": TYPE_NL.get(qtype, qtype),
                "difficulty": (t or {}).get("difficulty"),
                "quality": (t or {}).get("overallQuality"),
                "follow_up": bool(src.get("isFollowUp")),
                "warm_up": bool((t or {}).get("isWarmUp")),
                "recheck": bool((t or {}).get("isRecheck")),
                "graded_by_key": bool((t or {}).get("gradedByKey")),
                "has_turn": t is not None,
                "has_content": c is not None,
                "question": (c or {}).get("question"),
                "answer": (c or {}).get("answer"),
                "feedback": (c or {}).get("feedback"),
                "hints": (c or {}).get("hintCount"),
                "signals": trace_signals(t, c),
                "context": context,
                "session_start": SESSION_START_NL.get(context.get("sessionStart"), context.get("sessionStart")),
            }
        )
    rows.sort(key=lambda r: r["at"])
    return rows
