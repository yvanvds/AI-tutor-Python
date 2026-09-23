"""Evaluate a class on a milestone, outside the app.

    python tooling/evaluation/evaluate.py draft    --klas 6WEWI [--mijlpaal <id|titel>] [--out DIR]
    python tooling/evaluation/evaluate.py validate --klas 6WEWI
    python tooling/evaluation/evaluate.py backup   --klas 6WEWI [--out DIR]
    python tooling/evaluation/evaluate.py apply    <draft>.json [--force]

`draft` writes two files outside the repo (default `C:\\Users\\yvan\\ai-tutor-evaluaties`):
a Markdown draft to discuss, and a JSON sidecar that `apply` reads. The
JSON is the source of truth for what gets written; the Markdown is for
people. Nothing is written to Cosmos by `draft` or `validate`.

`apply` backs up the target `grade_proposals` docs first, then upserts one
signed-off proposal per student that is not marked `skip`, guarded by
`If-Match`. Publishing to students stays in the app: press "Vrijgeven" on
the Reports page, which copies signed-off proposals only.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import cosmos  # noqa: E402
import diagnostics as dx  # noqa: E402
import rules  # noqa: E402

DEFAULT_OUT = Path.home() / "ai-tutor-evaluaties"
BACKUP_DIR = Path.home() / "ai-tutor-backups"
LESSON_QUIET_MINUTES = 10


def _now() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


def _stamp() -> str:
    return _now().strftime("%Y%m%dT%H%M%S")


def _slug(s: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")[:40]


def _pick_milestone(arg: str | None) -> dict:
    ms = cosmos.milestones()
    if not ms:
        sys.exit("geen mijlpalen in de database")
    if arg is None:
        if len(ms) == 1:
            return ms[0]
        sys.exit("meerdere mijlpalen; geef --mijlpaal <id|titel>:\n  " + "\n  ".join(f"{m['id']}  {m['title']}" for m in ms))
    hits = [m for m in ms if m["id"] == arg or arg.lower() in m["title"].lower()]
    if len(hits) != 1:
        sys.exit(f"--mijlpaal {arg!r} matcht {len(hits)} mijlpalen")
    return hits[0]


def _lesson_in_progress(students: list[dict]) -> list[str]:
    cutoff = _now() - dt.timedelta(minutes=LESSON_QUIET_MINUTES)
    return [
        f"{a.get('firstName')} {a.get('lastName')}"
        for a in students
        if a.get("updatedAt") and rules.parse_at(a["updatedAt"]) > cutoff
    ]


# ---- draft -------------------------------------------------------------------


def cmd_draft(args) -> None:
    out_dir = Path(args.out or DEFAULT_OUT)
    out_dir.mkdir(parents=True, exist_ok=True)
    milestone = _pick_milestone(args.mijlpaal)
    goals = cosmos.goals()
    los = rules.milestone_los(milestone, goals)
    ms_subgoals = set(milestone.get("subgoalIds") or [])
    students = cosmos.accounts(args.klas)
    if not students:
        sys.exit(f"geen leerlingen met className={args.klas!r}")
    now = _now()

    per_student = []
    all_turns = {}
    for a in students:
        all_turns[a["uid"]] = cosmos.turns(a["uid"])
    # Een klasdag is een dag waarop minstens de helft van de klas (en
    # minstens twee leerlingen) werkte; wie alleen thuis of in het weekend
    # werkt, maakt geen klasdag en dus geen afwezigen.
    active_per_day: dict[str, set[str]] = {}
    for uid_, ts in all_turns.items():
        for t in ts:
            active_per_day.setdefault(t["turnAt"][:10], set()).add(uid_)
    quorum = max(2, len(students) // 2)
    class_days = {d for d, who in active_per_day.items() if len(who) >= quorum}

    for a in students:
        uid = a["uid"]
        turns = all_turns[uid]
        st = rules.replay(turns, goals)
        sc = rules.score(los, st, milestone["expectedDifficulty"])
        tl = dx.timeline(turns)
        # Accuracy is not a growth measure here: later subgoals are harder and
        # the calibration ladder raises the questions as the student improves,
        # so a percentage falls while skill rises. Growth a report can state
        # honestly is what was demonstrated when, and the level climbed.
        ms_turns = [t for t in turns if t["subgoalId"] in ms_subgoals]
        level_start = ms_turns[0].get("calibrationBefore") if ms_turns else None
        level_end = ms_turns[-1].get("calibrationAfter") if ms_turns else None
        level_hard_from = next((t["turnAt"][:10] for t in ms_turns if t.get("calibrationAfter") == "hard"), None)
        # When each part of the milestone was finished, and between which
        # dates the goals were demonstrated: the "wanneer" a report needs.
        order = {sid: i for i, sid in enumerate(milestone.get("subgoalIds") or [])}
        seen: set[str] = set()
        reached = []
        for t in turns:
            sid = t["subgoalId"]
            if t.get("subgoalAdvanced") and sid in ms_subgoals and sid not in seen:
                seen.add(sid)
                reached.append((order.get(sid, 99), (goals.get(sid) or {}).get("title") or sid, t["turnAt"][:10]))
        reached.sort()
        stamps = [st[lo.key].first_mastered_at for lo in los if lo.key in st and st[lo.key].first_mastered_at]
        per_student.append(
            {
                "uid": uid,
                "name": f"{a.get('firstName', '')} {a.get('lastName', '')}".strip(),
                "calibration": (a.get("calibration") or {}).get("difficulty"),
                "score": sc,
                "needed": rules.stamps_needed_to_pass(sc),
                "timeline": tl,
                "level_start": level_start,
                "level_end": level_end,
                "level_hard_from": level_hard_from,
                "reached": [(title, day) for _, title, day in reached],
                "stamp_first": min(stamps).date().isoformat() if stamps else None,
                "stamp_last": max(stamps).date().isoformat() if stamps else None,
                "absent": dx.absences(turns, class_days),
                "near": dx.near_misses(los, st, milestone["expectedDifficulty"]),
                "profile": dx.profile(turns),
                "fossils": dx.fossils(los, st, turns, now),
                "cross_root": dx.discarded_cross_root(turns, goals, ms_subgoals),
                "has_data": any(lo.key in st for lo in los),
            }
        )

    base = f"{now.strftime('%Y%m%d')}-{_slug(args.klas)}-{_slug(milestone['title'])}"
    md_path = out_dir / f"{base}.md"
    json_path = out_dir / f"{base}.json"
    md_path.write_text(_render_md(milestone, args.klas, per_student, now, json_path), encoding="utf-8")
    json_path.write_text(json.dumps(_render_json(milestone, args.klas, per_student, now), ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"concept : {md_path}")
    print(f"sidecar : {json_path}")
    print(f"regels  : {rules.RULES_VERSION}")
    print("\nOverzicht:")
    for p in sorted(per_student, key=lambda p: -p["score"].proposal):
        sc = p["score"]
        flag = "  (geen data)" if not p["has_data"] else ("  afwezig: " + ", ".join(p["absent"]) if p["absent"] else "")
        print(f"  {p['name']:26} kern {sc.core_counted:2}/{sc.core_total}  uitbr {sc.extension_mastered}/{sc.extension_total}  moeilijk {sc.hard_count:2}/{sc.mastered_total:<2}  punt {sc.proposal:3}{flag}")


def _lo_label(lo: rules.MilestoneLo) -> str:
    # The statement is what the report text must use; the id is for the teacher.
    return f"{lo.statement} `{lo.lo_id}`" + ("" if lo.is_core else " (uitbreiding)")


def _render_md(milestone, klas, per_student, now, json_path) -> str:
    L = []
    L.append(f"# Evaluatie — {milestone['title']} — {klas}")
    L.append("")
    L.append(f"Opgesteld {now.strftime('%Y-%m-%d %H:%M')} UTC · regels `{rules.RULES_VERSION}` · sidecar `{json_path.name}`")
    L.append("")
    L.append("**Zo is het getal gemaakt.** Elke oefening uit `turn_history` is herspeeld met de regels van v1.0.10, met drie afwijkingen die op 23-09 met de leerkracht beslist zijn: een fout op `hard` weegt ×0,6 en op `easy` ×1,4 (#169); een leerdoel dat ooit aan de drie beheersingsvoorwaarden voldeed blijft aangetoond (#168); een opmerking van de grader over een eerder subdoel telt niet als negatief bewijs (#167). Kern = aangetoond én hoogste niveau (waarop het doel juist beantwoord werd) ≥ verwacht niveau van de mijlpaal. `M = 50·k + 50·k·(0,6·u + 0,4·d)`, en `P = M` omdat M_start = 0 voor een eerste rapport dat alles sinds de start van het jaar beslaat.")
    L.append("")
    L.append("**Wat hieronder géén invloed heeft op het getal:** alles onder *diagnostiek*. Dat is er om de leerkracht te informeren. Een aanpassing van het punt is een beslissing van de leerkracht en krijgt een reden in het vak *Aanpassing*; die reden gaat mee naar het rapport.")
    L.append("")
    L.append("**Drie teksten per leerling.** *Diagnostiek* en *Voor de leerkracht* blijven hier. *Tekst voor het rapport* gaat letterlijk naar de leerling en de ouders: je-vorm, gewone taal, twee koppen als gewone regels (de app toont platte tekst). Benoem een leerdoel met zijn eigen zin ('Je kan …'), nooit met de code erachter. De woordregels staan in de skill.")
    L.append("")
    L.append("## Overzicht")
    L.append("")
    L.append("| leerling | kern | uitbr | moeilijk | **punt** | nodig om te slagen | signalen |")
    L.append("|---|---|---|---|---|---|---|")
    for p in sorted(per_student, key=lambda p: -p["score"].proposal):
        sc = p["score"]
        need = p["needed"]
        need_s = "—" if not p["has_data"] else ("geslaagd" if sc.proposal >= rules.PASS_MARK else (f"+{need[0]} kern → {need[1]}" if need else "?"))
        sig = []
        if not p["has_data"]:
            sig.append("geen data")
        if p["absent"]:
            sig.append("afwezig " + ", ".join(d[5:] for d in p["absent"]))
        if p["fossils"]:
            sig.append(f"{len(p['fossils'])} fossiel")
        thin = sum(1 for r in p["near"] if r["thin"])
        if thin >= 2:
            sig.append(f"{thin} doelen te weinig bevraagd")
        if p["cross_root"]["positive"] >= 10:
            sig.append(f"{p['cross_root']['positive']} weggegooide positieven")
        L.append(f"| {p['name']} | {sc.core_counted}/{sc.core_total} | {sc.extension_mastered}/{sc.extension_total} | {sc.hard_count}/{sc.mastered_total} | **{sc.proposal}** | {need_s} | {', '.join(sig)} |")
    L.append("")
    for p in sorted(per_student, key=lambda p: p["name"]):
        sc = p["score"]
        L.append(f"## {p['name']}")
        L.append("")
        if not p["has_data"]:
            L.append("_Geen enkele vraag over de leerdoelen van deze mijlpaal. Niet beoordelen._")
            L.append("")
            L.append("**Observatie leerkracht:** ")
            L.append("")
            L.append("**Beslissing:** overslaan")
            L.append("")
            continue
        L.append(f"**Punt {sc.proposal}** — kern {sc.core_counted}/{sc.core_total} (k = {sc.k:.2f}), uitbreiding {sc.extension_mastered}/{sc.extension_total} (u = {sc.u:.2f}), op moeilijk {sc.hard_count}/{sc.mastered_total} (d = {sc.d:.2f}), M = {sc.m:.1f}. Kalibratie nu: {p['calibration']}.")
        if sc.proposal < rules.PASS_MARK and p["needed"]:
            L.append(f"Nog **+{p['needed'][0]} kernleerdoel(en)** nodig om te slagen (→ {p['needed'][1]}).")
        L.append("")
        L.append("### Diagnostiek")
        L.append("")
        L.append("**Per lesdag** (oefeningen · % juist · kalibratie · afgeronde subdoelen · waar):")
        L.append("")
        for r in p["timeline"]:
            L.append(f"- {r['day']}: {r['turns']} · {r['correct_pct']}% · {r['calibration_end']} · {r['advanced']} · {r['subgoals']}")
        if p["absent"]:
            L.append(f"- **Afwezig** terwijl de klas werkte: {', '.join(p['absent'])}")
        if p["level_start"]:
            nl = {"easy": "makkelijke", "medium": "gewone", "hard": "moeilijke"}
            path = f"begon met {nl.get(p['level_start'], p['level_start'])} oefeningen, eindigde met {nl.get(p['level_end'], p['level_end'])}"
            if p["level_hard_from"] and p["level_start"] != "hard":
                path += f" (moeilijk vanaf {p['level_hard_from'][5:]})"
            L.append(f"- **Niveau binnen dit onderdeel:** {path}")
        L.append("")
        if p["reached"]:
            n_ms = len(milestone.get("subgoalIds") or [])
            L.append("**Onderdelen afgerond:** " + "; ".join(f"{t} op {d[5:]}" for t, d in p["reached"]) + f" ({len(p['reached'])} van {n_ms})")
            L.append("")
        if p["stamp_first"]:
            L.append(f"**Doelen aangetoond tussen** {p['stamp_first']} en {p['stamp_last']}.")
            L.append("")
        near = [r for r in p["near"] if r["status"] != "ver"]
        far = [r for r in p["near"] if r["status"] == "ver"]
        if near:
            L.append("**Bijna / aandacht:**")
            L.append("")
            for r in near:
                L.append(f"- {_lo_label(r['lo'])} — μ {r['mean']:.2f}, {r['n']} vragen, hoogste niveau {r['ratchet']}, laatst {r['last']} — {r['status']}{' — te weinig vragen om aan te tonen' if r['thin'] else ''}")
            L.append("")
        if far:
            L.append("**Ver:**")
            L.append("")
            for r in far:
                L.append(f"- {_lo_label(r['lo'])} — μ {r['mean']:.2f}, {r['n']} vragen{' — te weinig vragen om aan te tonen' if r['thin'] else ''}")
            L.append("")
        pr = p["profile"]
        L.append(f"**Profiel:** {pr['turns']} oefeningen · denktijd {pr['think_time_s']} s · juist {pr['correct_pct']}% / deels {pr['partial_pct']}% / fout {pr['wrong_pct']}% · vervolgvragen {pr['follow_up_pct']}%")
        L.append(f"- per moeilijkheid: {', '.join(f'{k} {v}' for k, v in pr['by_difficulty'].items())}")
        L.append(f"- per vraagtype: {', '.join(f'{k} {v}' for k, v in pr['by_type'].items())}")
        if pr["by_kind"]:
            L.append(f"- per soort leerdoel: {', '.join(f'{k} {v}' for k, v in pr['by_kind'].items())}")
        L.append("")
        if p["fossils"]:
            L.append("**Fossielen** — niet aangetoond, al minstens een week niet meer bevraagd, terwijl recent werk op zijn niveau goed is:")
            L.append("")
            for f in p["fossils"]:
                L.append(f"- {_lo_label(f['lo'])} — μ {f['mean']:.2f}, {f['age_days']} dagen oud")
            L.append("")
        cr = p["cross_root"]
        if cr["positive"] or cr["negative"]:
            L.append(f"**Signalen vanuit ander doel, door de app weggegooid:** {cr['positive']} positief, {cr['negative']} negatief.")
            for r in cr["top"][:4]:
                L.append(f"- {r['lo']} +{r['pos']}/−{r['neg']} ({', '.join(r['days'])})")
            L.append("")
        L.append("### Voor de leerkracht (concept)")
        L.append("")
        L.append("_[2 à 4 zinnen, vaktaal mag, blijft hier: wat moet de leerkracht weten om te beslissen — bijna-doelen, fossielen, afwezigheid, een profiel dat op iets wijst]_")
        L.append("")
        L.append("**Observatie leerkracht:** ")
        L.append("")
        L.append("**Beslissing:** aftekenen / uitstellen / overslaan")
        L.append("")
        L.append("**Aanpassing:** — **Reden** (gaat mee naar het rapport, in je-vorm): ")
        L.append("")
        L.append("### Tekst voor het rapport (concept)")
        L.append("")
        L.append("_[gaat letterlijk naar de leerling en de ouders — pas schrijven ná de observaties van de leerkracht; twee koppen als gewone regels; je-vorm; geen vaktaal; zie de skill]_")
        L.append("")
        L.append("Verantwoording van je score")
        L.append("")
        L.append("_[3 à 5 zinnen]_")
        L.append("")
        L.append("Feedback")
        L.append("")
        L.append("_[4 à 8 zinnen]_")
        L.append("")
    return "\n".join(L)


def _render_json(milestone, klas, per_student, now) -> dict:
    return {
        "rulesVersion": rules.RULES_VERSION,
        "computedAt": now.isoformat().replace("+00:00", "Z"),
        "klas": klas,
        "milestoneId": milestone["id"],
        "milestoneTitle": milestone["title"],
        "students": [
            {
                "uid": p["uid"],
                "name": p["name"],
                "skip": not p["has_data"],
                "skipReason": "geen data" if not p["has_data"] else "",
                "computed": {
                    "k": p["score"].k,
                    "u": p["score"].u,
                    "d": p["score"].d,
                    "mEnd": p["score"].m,
                    "proposal": p["score"].proposal,
                    "coreTotal": p["score"].core_total,
                    "coreCounted": p["score"].core_counted,
                    "extensionTotal": p["score"].extension_total,
                    "extensionMastered": p["score"].extension_mastered,
                    "masteredTotal": p["score"].mastered_total,
                    "hardCount": p["score"].hard_count,
                    "neverProbedCount": p["score"].never_probed,
                },
                "justification": None,
                "justificationSource": "ai",
                "adjustedGrade": None,
                "adjustmentNote": "",
            }
            for p in per_student
        ],
    }


# ---- validate ----------------------------------------------------------------


def cmd_validate(args) -> None:
    """Replays with the app's own arithmetic and compares to `lo_beliefs`.
    A student on the current build should match to the rounding."""
    goals = cosmos.goals()
    students = cosmos.accounts(args.klas)
    print(f"{'leerling':26}{'docs':>6}{'vergeleken':>12}{'|d mean|>0.01':>14}{'hoogste niveau anders':>24}")
    for a in students:
        turns = cosmos.turns(a["uid"])
        stored = cosmos.beliefs(a["uid"])
        st = rules.replay(turns, goals, asymmetric=False, drop_incidental_negatives=False)
        n = off = rat = 0
        for key, b in stored.items():
            s = st.get(key)
            if not s:
                continue
            n += 1
            if abs(s.mean - b["alpha"] / (b["alpha"] + b["beta"])) > 0.01:
                off += 1
            if b.get("highestPositiveDifficulty") and b["highestPositiveDifficulty"] != s.ratchet:
                rat += 1
        print(f"{a.get('firstName','')+' '+a.get('lastName',''):26}{len(stored):>6}{n:>12}{off:>14}{rat:>24}")
    print("\nAfwijkingen wijzen op een client die anders rekende (oude build) of op transfer-krediet buiten loSignals; ze raken het concept niet, dat leest alleen turn_history.")


# ---- backup ------------------------------------------------------------------


def _backup(students: list[dict], milestone_id: str | None, out_dir: Path, label: str) -> Path:
    out_dir.mkdir(parents=True, exist_ok=True)
    dump = {"takenAt": _stamp(), "accounts": students, "grade_proposals": [], "lo_beliefs": []}
    for a in students:
        uid = a["uid"]
        if milestone_id:
            doc = cosmos.read("grade_proposals", f"{uid}_{milestone_id}", uid)
            if doc:
                dump["grade_proposals"].append(doc)
        else:
            dump["grade_proposals"] += cosmos.query("grade_proposals", "SELECT * FROM c WHERE c.uid=@u", {"@u": uid}, pk=uid, cross=False)
            dump["lo_beliefs"] += list(cosmos.beliefs(uid).values())
    path = out_dir / f"backup_{label}_{dump['takenAt']}.json"
    path.write_text(json.dumps(dump, ensure_ascii=False), encoding="utf-8")
    return path


def cmd_backup(args) -> None:
    students = cosmos.accounts(args.klas)
    path = _backup(students, None, Path(args.out or BACKUP_DIR), _slug(args.klas))
    print(f"back-up: {path}")


# ---- apply -------------------------------------------------------------------


def cmd_apply(args) -> None:
    data = json.loads(Path(args.draft).read_text(encoding="utf-8"))
    mid = data["milestoneId"]
    students = cosmos.accounts(data["klas"])
    by_uid = {a["uid"]: a for a in students}

    busy = _lesson_in_progress(students)
    if busy and not args.force:
        sys.exit("Deze leerlingen waren de laatste minuten actief — de klas werkt. Wacht, of --force:\n  " + ", ".join(busy))

    todo = [s for s in data["students"] if not s.get("skip")]
    missing = [s["name"] for s in todo if not s.get("justification")]
    if missing and not args.force:
        sys.exit("Zonder verantwoording niet aftekenen (of --force):\n  " + ", ".join(missing))

    for s in todo:
        j = s.get("justification") or ""
        if "Verantwoording van je score" not in j or "\nFeedback" not in j:
            print(f"  let op: {s['name']}: de rapporttekst mist een van de twee koppen")
    path = _backup([by_uid[s["uid"]] for s in todo if s["uid"] in by_uid], mid, BACKUP_DIR, f"{_slug(data['klas'])}_apply")
    print(f"back-up: {path}")

    now = _now().isoformat().replace("+00:00", "Z")
    written = conflicts = 0
    for s in todo:
        c = s["computed"]
        doc = {
            "id": f"{s['uid']}_{mid}",
            "type": "grade_proposal",
            "uid": s["uid"],
            "milestoneId": mid,
            "formulaVersion": data["rulesVersion"],
            "computedAt": data["computedAt"],
            "k": c["k"], "u": c["u"], "d": c["d"],
            "mEnd": c["mEnd"], "mStart": 0.0, "g": c["mEnd"] / 100.0,
            "proposal": c["proposal"],
            "coreTotal": c["coreTotal"], "coreCounted": c["coreCounted"],
            "extensionTotal": c["extensionTotal"], "extensionMastered": c["extensionMastered"],
            "masteredTotal": c["masteredTotal"], "hardCount": c["hardCount"],
            "staleLoCount": 0, "neverProbedCount": c["neverProbedCount"],
            "supervisedTurns": 0, "homeTurns": 0,
            "mStartSource": "snapshot", "mStartInexactCount": 0,
            "justification": s["justification"],
            "justificationAt": now,
            "justificationSource": s.get("justificationSource") or "ai",
            "adjustmentNote": s.get("adjustmentNote") or "",
            "signedOffAt": now,
        }
        if s.get("adjustedGrade") is not None:
            doc["adjustedGrade"] = int(s["adjustedGrade"])
        existing = cosmos.read("grade_proposals", doc["id"], s["uid"])
        if existing and existing.get("signedOffAt") and not args.force:
            print(f"  {s['name']}: al afgetekend op {existing['signedOffAt'][:10]} — overgeslagen (--force om te overschrijven)")
            continue
        try:
            cosmos.upsert("grade_proposals", doc, s["uid"], etag=existing["_etag"] if existing else None)
            written += 1
            final = doc.get("adjustedGrade", doc["proposal"])
            print(f"  {s['name']}: {doc['proposal']}" + (f" → {final} (aangepast)" if "adjustedGrade" in doc else "") + "  afgetekend")
        except cosmos.Conflict:
            conflicts += 1
            print(f"  {s['name']}: CONFLICT — doc veranderde intussen, niet geschreven")
    skipped = [s["name"] for s in data["students"] if s.get("skip")]
    print(f"\ngeschreven {written}, conflicten {conflicts}, overgeslagen {len(skipped)}" + (f" ({', '.join(skipped)})" if skipped else ""))
    print("Vrijgeven naar de leerlingen gebeurt in de app: Rapporten → Vrijgeven.")


# ---- main --------------------------------------------------------------------


def main() -> None:
    # Windows-consoles staan vaak op cp1252; namen met ë en tekens als μ
    # mogen de run niet breken.
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    d = sub.add_parser("draft"); d.add_argument("--klas", required=True); d.add_argument("--mijlpaal"); d.add_argument("--out")
    v = sub.add_parser("validate"); v.add_argument("--klas", required=True)
    b = sub.add_parser("backup"); b.add_argument("--klas", required=True); b.add_argument("--out")
    a = sub.add_parser("apply"); a.add_argument("draft"); a.add_argument("--force", action="store_true")
    args = ap.parse_args()
    {"draft": cmd_draft, "validate": cmd_validate, "backup": cmd_backup, "apply": cmd_apply}[args.cmd](args)


if __name__ == "__main__":
    main()
