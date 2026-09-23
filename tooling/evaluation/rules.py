"""The evaluation rules, versioned. Pure arithmetic over `turn_history`.

Everything the number depends on lives here, so a grade is recomputable
from the same stored data a student can ask for (PUNTENFORMULE §3.3). The
diagnostics in `diagnostics.py` inform the teacher; they never touch the
number.

Why replay from `turn_history` instead of reading `lo_beliefs`: clients on
an older build wrote docs without the difficulty ratchet and without the
mastery stamp, and applied (or dropped) incidental signals differently.
The turn log is the one record every build wrote the same way. Replaying
it with the symmetric factor and incidentals on reproduces the stored
beliefs exactly (validated 2026-09-23 on 6EWI) — `evaluate.py validate`
checks that on demand.

Rule set `1.0.16-eval1` = PUNTENFORMULE v1.0.16, replayed from the turn
log. It computes exactly what `1.0.10-eval1` computed; what changed is the
formula around it. That set was v1.0.10 with three deliberate departures,
each decided with the teacher on 2026-09-23, which the formula has since
taken over (v1.0.12–v1.0.14):

  * asymmetric difficulty factor (#169): a wrong answer on `hard` weighs
    ×0.6, on `easy` ×1.4 — so μ becomes level-aware and promotion on the
    calibration ladder no longer pushes a student out of mastery;
  * the grade reads the one-way mastery stamp (#168): once an LO met the
    three conditions it stays demonstrated for grading;
  * incidental *negative* signals (grader remarks about an earlier subgoal's
    LO while grading another) are not evidence (#167).

and P = M. In `1.0.10-eval1` that was a framing choice (M_start = 0 for a
first report, so G = M/100 and the 60/40 mix collapsed to M); since
PUNTENFORMULE v1.0.16 (#191) it is the rule itself: the growth term G, and
with it M_start, is gone from the formula, in the app as here.
"""

from __future__ import annotations

import datetime as dt
from dataclasses import dataclass, field

RULES_VERSION = "1.0.16-eval1"

PRIOR = 1.0
EVIDENCE_CAP = 20.0
DECAY_HALF_LIFE_DAYS = 60.0  # the conductor decays on every write; replay must too

WEIGHT = {"strong": 2.0, "moderate": 1.0, "weak": 0.5}
POS_FACTOR = {"easy": 0.6, "medium": 1.0, "hard": 1.4}
NEG_FACTOR = {"easy": 1.4, "medium": 1.0, "hard": 0.6}  # #169; symmetric would equal POS_FACTOR

MASTERY_MEAN = 0.80
MASTERY_EVIDENCE = 4.0

WEIGHT_EXTENSION = 0.6
WEIGHT_DIFFICULTY = 0.4
PASS_MARK = 50

DIFF_ORDER = {None: -1, "easy": 0, "medium": 1, "hard": 2}


def parse_at(s: str) -> dt.datetime:
    return dt.datetime.fromisoformat(s.replace("Z", "+00:00"))


@dataclass
class LoState:
    alpha: float = PRIOR
    beta: float = PRIOR
    last_at: dt.datetime | None = None
    positive_at_calibrated_at: dt.datetime | None = None
    first_mastered_at: dt.datetime | None = None
    ratchet: str | None = None
    n_direct: int = 0
    last_direct_at: dt.datetime | None = None
    direct_signals: list[tuple[dt.datetime, str, str, str]] = field(default_factory=list)  # (at, signal, strength, difficulty)

    @property
    def mean(self) -> float:
        return self.alpha / (self.alpha + self.beta)

    @property
    def evidence(self) -> float:
        return self.alpha + self.beta

    @property
    def mastered_now(self) -> bool:
        return (
            self.mean >= MASTERY_MEAN
            and self.evidence >= MASTERY_EVIDENCE
            and self.positive_at_calibrated_at is not None
        )

    @property
    def demonstrated(self) -> bool:
        """What the grade reads (#168): the one-way stamp."""
        return self.first_mastered_at is not None


def _decay(a: float, b: float, last: dt.datetime | None, now: dt.datetime) -> tuple[float, float]:
    if last is None or now <= last:
        return a, b
    d = 0.5 ** (((now - last).total_seconds() / 86400.0) / DECAY_HALF_LIFE_DAYS)
    return PRIOR + (a - PRIOR) * d, PRIOR + (b - PRIOR) * d


def _apply(a: float, b: float, da: float, db: float) -> tuple[float, float]:
    """Cap-then-add, as `belief_math.applyEvidence`."""
    nd = da + db
    if a + b + nd > EVIDENCE_CAP:
        excess_capacity = EVIDENCE_CAP - 2 * PRIOR - nd
        existing_excess = a + b - 2 * PRIOR
        if existing_excess > 0 and excess_capacity > 0:
            s = excess_capacity / existing_excess
            a = PRIOR + (a - PRIOR) * s
            b = PRIOR + (b - PRIOR) * s
        elif excess_capacity <= 0:
            a = b = PRIOR
    return a + da, b + db


def same_root_backward(goals: dict, signal_sg: str, active_sg: str) -> bool:
    """The conductor's filter for an incidental signal: same root goal, and
    the signal's subgoal is not later in the curriculum than the active one."""
    a, s = goals.get(active_sg), goals.get(signal_sg)
    return bool(
        a and s and a.get("parentId") == s.get("parentId") and s.get("order", 0) <= a.get("order", 0)
    )


def replay(
    turns: list[dict],
    goals: dict,
    *,
    asymmetric: bool = True,
    drop_incidental_negatives: bool = True,
) -> dict[tuple[str, str], LoState]:
    """Replays the student's whole turn log into per-LO states.

    With `asymmetric=False, drop_incidental_negatives=False` this is the
    app's own arithmetic and should match `lo_beliefs` for a client on the
    current build.
    """
    st: dict[tuple[str, str], LoState] = {}
    for t in turns:
        now = parse_at(t["turnAt"])
        follow_up = t.get("isFollowUp") is True
        diff = t.get("difficulty") or "medium"
        cal = t.get("calibrationBefore") or "medium"
        active = t["subgoalId"]
        for s in t.get("loSignals") or []:
            if s.get("signal") not in ("positive", "negative"):
                continue
            sig_sg = s.get("subgoalId") or active
            incidental = sig_sg != active
            if incidental and not same_root_backward(goals, sig_sg, active):
                continue  # cross-root or forward: the conductor drops it
            if incidental and s["signal"] == "negative" and drop_incidental_negatives:
                continue  # #167
            key = (sig_sg, s["loId"])
            lo = st.setdefault(key, LoState())
            a, b = _decay(lo.alpha, lo.beta, lo.last_at, now)
            strength = s.get("strength") or "moderate"
            if follow_up and WEIGHT.get(strength, 1.0) > WEIGHT["weak"]:
                strength = "weak"  # §6.2
            eff_diff = "medium" if (follow_up or incidental) else diff
            base = WEIGHT.get(strength, 1.0)
            if s["signal"] == "positive":
                a, b = _apply(a, b, base * POS_FACTOR[eff_diff], 0.0)
            else:
                factor = NEG_FACTOR if asymmetric else POS_FACTOR
                a, b = _apply(a, b, 0.0, base * factor[eff_diff])
            lo.alpha, lo.beta, lo.last_at = a, b, now
            direct = not follow_up and not incidental
            if direct:
                lo.n_direct += 1
                lo.last_direct_at = now
                lo.direct_signals.append((now, s["signal"], strength, diff))
                if s["signal"] == "positive":
                    if DIFF_ORDER[diff] >= DIFF_ORDER[cal]:
                        lo.positive_at_calibrated_at = now
                    if DIFF_ORDER[diff] > DIFF_ORDER[lo.ratchet]:
                        lo.ratchet = diff
            if lo.first_mastered_at is None and lo.mastered_now:
                lo.first_mastered_at = now
    return st


@dataclass
class MilestoneLo:
    subgoal_id: str
    lo_id: str
    is_core: bool
    statement: str = ""  # the LO's own Dutch "Je kan ..." sentence; student-facing text uses this, never the id
    subgoal_title: str = ""

    @property
    def key(self) -> tuple[str, str]:
        return (self.subgoal_id, self.lo_id)


def milestone_los(milestone: dict, goals: dict) -> list[MilestoneLo]:
    """The milestone's LOs in curriculum order, from the live goal tree —
    `GradeProposalService.milestoneLos`."""
    core = set(milestone.get("coreLoKeys") or [])
    out = []
    for sid in milestone.get("subgoalIds") or []:
        for o in (goals.get(sid) or {}).get("objectives") or []:
            out.append(
                MilestoneLo(
                    sid,
                    o["id"],
                    f"{sid}/{o['id']}" in core,
                    o.get("statement") or o["id"],
                    (goals.get(sid) or {}).get("title") or sid,
                )
            )
    return out


@dataclass
class Score:
    k: float
    u: float
    d: float
    m: float
    proposal: int
    core_total: int
    core_counted: int
    extension_total: int
    extension_mastered: int
    mastered_total: int
    hard_count: int
    never_probed: int


def mastery_from_fractions(k: float, u: float, d: float) -> float:
    return 50 * k + 50 * k * (WEIGHT_EXTENSION * u + WEIGHT_DIFFICULTY * d)


def score(los: list[MilestoneLo], st: dict, expected_difficulty: str) -> Score:
    """`M = 50·k + 50·k·(w_u·u + w_d·d)` (§2.3) over the stamps, and P = M."""
    exp = DIFF_ORDER[expected_difficulty]
    ct = cc = et = em = mt = hc = never = 0
    for lo in los:
        s = st.get(lo.key)
        if s is None:
            never += 1
        demonstrated = bool(s and s.demonstrated)
        ratchet = s.ratchet if s else None
        if demonstrated:
            mt += 1
            if ratchet == "hard":
                hc += 1
        if lo.is_core:
            ct += 1
            if demonstrated and DIFF_ORDER[ratchet] >= exp:
                cc += 1
        else:
            et += 1
            if demonstrated:
                em += 1
    k = (1.0 if los else 0.0) if ct == 0 else cc / ct
    u = 0.0 if et == 0 else em / et
    d = 0.0 if mt == 0 else hc / mt
    m = mastery_from_fractions(k, u, d)
    return Score(k, u, d, m, max(0, min(100, round(m))), ct, cc, et, em, mt, hc, never)


def stamps_needed_to_pass(sc: Score) -> tuple[int, int] | None:
    """(extra core stamps, resulting grade) with u and d held as they are."""
    if sc.core_total == 0:
        return None
    for extra in range(0, sc.core_total - sc.core_counted + 1):
        k = (sc.core_counted + extra) / sc.core_total
        p = round(mastery_from_fractions(k, sc.u, sc.d))
        if p >= PASS_MARK:
            return extra, p
    return None
