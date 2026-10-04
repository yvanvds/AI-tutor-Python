"""Brings the questions already in the question bank in line with #215.

Since #215 a generated question enters the bank only when the first graded
answer to it is correct, a socratic question never does, a question hides
itself once at least 10 answers are graded and less than half of them were
correct, and nothing is "reviewed" or carries a note any more. The questions
stored before were stored when they were asked, by builds that did none of
this. Run this once after the merge, and once more after `MinimumVersion`
keeps the old builds out (they keep storing questions when asked until then).

Per question:

1. Its first graded answer: the earliest turn record with its `questionId`
   and an `overallQuality`, from the moment the doc was created on (a
   question deleted and stored again later starts afresh). Without one, the
   counters: `answeredCount == 0` is never answered, `correctCount ==
   answeredCount` a correct first answer, `correctCount == 0` a wrong one; a
   mixed count without a turn record says nothing, and the question stays.
2. Deleted: a socratic question, a first answer that is not `correct`
   (`partial` is not), a question never answered.
3. Hidden (`hiddenBy: auto`, `hiddenAt`): what stays with at least 10
   answers and less than half correct — the rule the app now applies itself.
   A question the teacher already hid stays hidden as it is; one the teacher
   showed again after it hid itself (`keptByTeacher`) stays shown.
4. `reviewedAt` and `teacherNote` are removed from what stays.

    python tooling/question_bank/cleanup.py           # dry run: counts per reason
    python tooling/question_bank/cleanup.py --apply   # backup, then write

The dry run only reads. `--apply` writes nothing before it saved a backup
of the whole `questions` container to `~/ai-tutor-backups` (outside the
public repo); then it deletes and writes with `If-Match`, so a doc a
student's app changed in between is skipped and named — run it again.
Whether to apply is the teacher's call, after the dry run.

It prints counts and question ids, never a student: turn records are read
for `questionId`, `overallQuality` and `turnAt` only.

Standard library only; the Cosmos client is `tooling/evaluation/cosmos.py`
(`COSMOS_ENDPOINT` / `COSMOS_KEY` from `.env`). Tests:

    python -m unittest discover -s tooling/question_bank/tests
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import sys
from collections import Counter
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BACKUP_DIR = Path.home() / "ai-tutor-backups"
CONTAINER = "questions"

# `PolicyConstants.bankAutoHideMinAnswers` / `bankAutoHideMaxShare` in
# lib/services/tutor/policy_constants.dart; a test keeps them equal.
AUTO_HIDE_MIN_ANSWERS = 10
AUTO_HIDE_MAX_SHARE = 0.5

SOCRATIC = "socraticQuestion"
OLD_FIELDS = ("reviewedAt", "teacherNote")

DELETE, HIDE, KEEP = "delete", "hide", "keep"

# Why, per decision. The dry run prints a count per reason.
SOCRATIC_Q = "socratisch"
FIRST_NOT_CORRECT = "eerste antwoord niet juist (turn_history)"
NEVER_ANSWERED = "nooit beantwoord"
FIRST_WRONG_BY_COUNTS = "eerste antwoord fout (tellers, geen turn record)"
FIRST_CORRECT = "eerste antwoord juist (turn_history)"
FIRST_CORRECT_BY_COUNTS = "eerste antwoord juist (tellers, geen turn record)"
MIXED_COUNTS = "gemengde telling zonder turn record (blijft staan)"
AUTO_HIDDEN = "minder dan de helft juist op 10 of meer antwoorden"

ACTION_LABELS = {
    KEEP: "behouden",
    DELETE: "verwijderd",
    HIDE: "automatisch verborgen",
}


def _cosmos():
    """The REST client. Imported late: it reads `.env` on import."""
    sys.path.insert(0, str(ROOT / "tooling" / "evaluation"))
    import cosmos

    return cosmos


# ---- the rules ---------------------------------------------------------------


@dataclass(frozen=True)
class Decision:
    action: str
    reason: str
    # The old fields this question still carries, removed when it stays.
    strip: tuple[str, ...] = ()

    @property
    def writes(self) -> bool:
        return self.action != KEEP or bool(self.strip)


def _count(raw) -> int:
    return int(raw) if isinstance(raw, (int, float)) and not isinstance(raw, bool) else 0


def _time(raw) -> dt.datetime | None:
    if not isinstance(raw, str):
        return None
    try:
        t = dt.datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError:
        return None
    return t if t.tzinfo else t.replace(tzinfo=dt.timezone.utc)


def hides_itself(answered: int, correct: int) -> bool:
    """`QuestionBankService.hidesItself`: at least 10 answers and less than
    half correct. Exactly half stays."""
    return answered >= AUTO_HIDE_MIN_ANSWERS and correct / answered < AUTO_HIDE_MAX_SHARE


def first_answers(turns: list[dict]) -> dict[str, list[tuple[dt.datetime, str]]]:
    """Per `questionId`, its graded answers as (turnAt, overallQuality),
    oldest first. Records without a quality or a time are left out."""
    out: dict[str, list[tuple[dt.datetime, str]]] = {}
    for t in turns:
        qid, quality, at = t.get("questionId"), t.get("overallQuality"), _time(t.get("turnAt"))
        if isinstance(qid, str) and isinstance(quality, str) and at is not None:
            out.setdefault(qid, []).append((at, quality))
    for answers in out.values():
        answers.sort()
    return out


def first_quality(doc: dict, answers: dict[str, list[tuple[dt.datetime, str]]]) -> str | None:
    """The quality of the first graded answer to [doc] since it was created,
    or None when no turn record has one."""
    created = _time(doc.get("createdAt"))
    for at, quality in answers.get(doc.get("id"), []):
        if created is None or at >= created:
            return quality
    return None


def decide(doc: dict, first: str | None) -> Decision:
    """What happens to [doc], whose first graded answer was [first] (None:
    no turn record has one)."""
    if doc.get("questionType") == SOCRATIC:
        return Decision(DELETE, SOCRATIC_Q)
    answered = _count(doc.get("answeredCount"))
    correct = _count(doc.get("correctCount"))
    if first is not None:
        if first != "correct":
            return Decision(DELETE, FIRST_NOT_CORRECT)
        kept = FIRST_CORRECT
    elif answered == 0:
        return Decision(DELETE, NEVER_ANSWERED)
    elif correct >= answered:
        kept = FIRST_CORRECT_BY_COUNTS
    elif correct == 0:
        return Decision(DELETE, FIRST_WRONG_BY_COUNTS)
    else:
        kept = MIXED_COUNTS
    strip = tuple(f for f in OLD_FIELDS if f in doc)
    if (
        doc.get("status") != "hidden"
        and doc.get("keptByTeacher") is not True
        and hides_itself(answered, correct)
    ):
        return Decision(HIDE, AUTO_HIDDEN, strip)
    return Decision(KEEP, kept, strip)


def rewritten(doc: dict, decision: Decision, now: str) -> dict:
    """[doc] as [decision] leaves it (for HIDE and a KEEP that strips)."""
    out = {k: v for k, v in doc.items() if not k.startswith("_") and k not in decision.strip}
    if decision.action == HIDE:
        out["status"] = "hidden"
        out["hiddenBy"] = "auto"
        out["hiddenAt"] = now
    return out


def plan(docs: list[dict], turns: list[dict]) -> list[tuple[dict, Decision]]:
    answers = first_answers(turns)
    return [(d, decide(d, first_quality(d, answers))) for d in docs]


# ---- the report --------------------------------------------------------------


def summary(planned: list[tuple[dict, Decision]]) -> str:
    by_action = Counter(d.action for _, d in planned)
    by_reason = Counter((d.action, d.reason) for _, d in planned)
    lines = [f"vragen in de bank: {len(planned)}", ""]
    for action in (KEEP, DELETE, HIDE):
        lines.append(f"{ACTION_LABELS[action]:<56}{by_action[action]:>6}")
        for (a, reason), n in sorted(by_reason.items()):
            if a == action:
                lines.append(f"  {reason:<54}{n:>6}")
    by_hand = sum(1 for doc, d in planned if d.action == KEEP and doc.get("status") == "hidden")
    stripped = sum(1 for _, d in planned if d.action != DELETE and d.strip)
    lines += [
        "",
        f"{'behouden en al met de hand verborgen (blijft zo)':<56}{by_hand:>6}",
        f"{'reviewedAt/teacherNote weg uit wat blijft':<56}{stripped:>6}",
        f"{'te schrijven (verwijderen of bijwerken)':<56}{sum(1 for _, d in planned if d.writes):>6}",
    ]
    return "\n".join(lines)


# ---- the run -----------------------------------------------------------------


def _now() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


def _iso(t: dt.datetime) -> str:
    return t.isoformat(timespec="milliseconds").replace("+00:00", "Z")


def backup(docs: list[dict], out_dir: Path, at: dt.datetime) -> Path:
    out_dir.mkdir(parents=True, exist_ok=True)
    path = out_dir / f"backup_questions_{at.strftime('%Y%m%dT%H%M%S')}.json"
    path.write_text(
        json.dumps({"takenAt": _iso(at), "questions": docs}, ensure_ascii=False),
        encoding="utf-8",
    )
    return path


def apply(planned: list[tuple[dict, Decision]], cosmos, now: str) -> Counter:
    done: Counter = Counter()
    for doc, d in planned:
        if not d.writes:
            continue
        try:
            if d.action == DELETE:
                cosmos.delete(CONTAINER, doc["id"], doc["subgoalId"], etag=doc.get("_etag"))
            else:
                cosmos.upsert(CONTAINER, rewritten(doc, d, now), doc["subgoalId"], etag=doc.get("_etag"))
            done[d.action] += 1
        except cosmos.Conflict:
            done["overgeslagen"] += 1
            print(f"  overgeslagen (intussen gewijzigd): {doc['id']}")
    return done


def run(args) -> None:
    cosmos = _cosmos()
    docs = cosmos.query(CONTAINER, "SELECT * FROM c")
    turns = cosmos.query(
        "turn_history",
        "SELECT c.questionId, c.overallQuality, c.turnAt FROM c WHERE IS_DEFINED(c.questionId)",
    )
    planned = plan(docs, turns)
    print(f"turn records met een questionId: {len(turns)}")
    print(summary(planned))
    if not args.apply:
        print("\nDroge run: er is niets geschreven. Schrijven met --apply.")
        return
    out_dir = Path(args.backup_dir).resolve()
    if out_dir == ROOT or ROOT in out_dir.parents:
        sys.exit(f"de back-up hoort buiten de publieke repo, niet in {out_dir}")
    at = _now()
    path = backup(docs, out_dir, at)
    print(f"\nback-up: {path}")
    done = apply(planned, cosmos, _iso(at))
    print(
        "geschreven: "
        + ", ".join(f"{ACTION_LABELS.get(k, k)} {n}" for k, n in sorted(done.items()))
    )


def main(argv: list[str] | None = None) -> None:
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--apply", action="store_true", help="na een back-up echt schrijven")
    p.add_argument("--backup-dir", default=str(BACKUP_DIR), help="waar de back-up komt")
    run(p.parse_args(argv))


if __name__ == "__main__":
    main()
