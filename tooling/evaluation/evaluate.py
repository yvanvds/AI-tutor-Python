"""Evaluate a class on a milestone, outside the app.

    python tooling/evaluation/evaluate.py draft    --klas 6WEWI [--mijlpaal <id|titel>] [--out DIR]
    python tooling/evaluation/evaluate.py validate --klas 6WEWI [--regels 1.1]
    python tooling/evaluation/evaluate.py backup   --klas 6WEWI [--out DIR]
    python tooling/evaluation/evaluate.py apply    <draft>.json [--force]
    python tooling/evaluation/evaluate.py what-if  --klas 6WEWI --leerling <naam> --tel lo_a,lo_b [--mijlpaal ...]
    python tooling/evaluation/evaluate.py trace    --leerling <naam> --dag 2026-10-02 [--subdoel <id>] [--klas 6WEWI]
    python tooling/evaluation/evaluate.py replay-beliefs --klas 6EWI [--leerling <naam> ...] [--regels 1.1] [--apply [--force]]

`draft` writes two files outside the repo (default `C:\\Users\\yvan\\ai-tutor-evaluaties`):
a Markdown draft to discuss, and a JSON sidecar that `apply` reads. The
JSON is the source of truth for what gets written; the Markdown is for
people. `what-if` prints the number `rules.score` gives with the named LOs
counted as demonstrated: what a teacher's adjustment comes to by the rule.
Nothing is written to Cosmos by `draft`, `validate`, `what-if` or `trace`,
nor by `replay-beliefs` without `--apply`.

`replay-beliefs` (#242) replays `lo_beliefs` from `turn_history` with the
replay `validate` compares them to, and restores the fields of
`BELIEF_FIELDS` on the docs there: α and β, the stamp `firstMasteredAt`
(the earliest of stored and replayed by oefening, never cleared),
`highestPositiveDifficulty` (the highest of the two, never lowered),
`lastProbedAt` where the doc has none (#275), and the own-question counts
of formula 1.1 (the larger of the two, #281). A dry run by default;
`--apply` backs up first, refuses in the class's lesson time, and writes
with `If-Match`. `--regels 1.1`, on it and on `validate`, replays every
oefening with formula 1.1, also those of a build from before it (#281).

`trace` prints one student's oefeningen of one day (Belgian time) as they
happened (#228): per oefening the time, LO, type, level and grade from
`turn_history`, and from `turn_content` the question, the answer, the
feedback and the grader's signals — the ones that counted and the ones that
were dropped, with why. To the terminal only; it writes no file.

`apply` backs up the target `grade_proposals` docs first, then upserts one
signed-off proposal per student that is not marked `skip`, guarded by
`If-Match`. It may run during a lesson: the student app never opens
`grade_proposals`. Publishing to students stays in the app: press
"Vrijgeven" on the Reports page, which copies signed-off proposals only.
"""

from __future__ import annotations

import argparse
import bisect
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


def _period_start(milestone: dict) -> dt.datetime | None:
    """Where the milestone's grading window opens (`Milestone.periodStart`).
    Missing or unreadable reads as "from the first turn", as the app's 1970
    fallback does."""
    raw = milestone.get("periodStart")
    if not isinstance(raw, str):
        return None
    try:
        at = rules.parse_at(raw)
    except ValueError:
        return None
    return at if at.tzinfo else at.replace(tzinfo=dt.timezone.utc)


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
    period_start = _period_start(milestone)
    # Supervised = in the lesson time of the class (#219), also for the
    # oefeningen from before the app read it so: one rule over the year.
    supervised = rules.by_timetable(rules.lessons_of(cosmos.classes(), args.klas))

    per_student = []
    all_turns = {}
    for a in students:
        # An audit record is no oefening (#201): left out here, once, it
        # counts nowhere — not as a wrong answer in the timeline, profile or
        # fossils, not as a day at work, not as a level. The replay does not
        # change: the record carries no signals.
        all_turns[a["uid"]] = [t for t in cosmos.turns(a["uid"]) if not rules.is_audit(t)]
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
        st = rules.replay(turns, goals, supervised=supervised)
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
            # What advances is the subgoal the student was on, also on a
            # warm-up or recheck about another one (#195).
            sid = rules.turn_scope(t, goals).active
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
                "reliability": rules.reliability(los, st, turns, period_start, now, supervised=supervised),
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
                "lost": dx.lost_oefeningen(turns, goals, ms_subgoals),
                "has_data": any(lo.key in st for lo in los),
            }
        )

    base = f"{now.strftime('%Y%m%d')}-{_slug(args.klas)}-{_slug(milestone['title'])}"
    md_path = out_dir / f"{base}.md"
    json_path = out_dir / f"{base}.json"
    md_path.write_text(_render_md(milestone, args.klas, per_student, now, json_path, period_start), encoding="utf-8")
    json_path.write_text(json.dumps(_render_json(milestone, args.klas, per_student, now), ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"concept : {md_path}")
    print(f"sidecar : {json_path}")
    print(f"regels  : {rules.RULES_VERSION}")
    exp = milestone["expectedDifficulty"]
    print(f"verwacht: {exp} (kern telt vanaf hoogste niveau {exp})")
    print("\nOverzicht:")
    for p in sorted(per_student, key=lambda p: -p["score"].proposal):
        sc = p["score"]
        flag = "  (geen data)" if not p["has_data"] else ("  afwezig: " + ", ".join(p["absent"]) if p["absent"] else "")
        print(f"  {p['name']:26} kern {sc.core_counted:2}/{sc.core_total}  uitbr {sc.extension_mastered}/{sc.extension_total}  moeilijk {sc.hard_count:2}/{sc.mastered_total:<2}  punt {sc.proposal:3}{flag}")


def _lo_label(lo: rules.MilestoneLo) -> str:
    # The statement is what the report text must use; the id is for the teacher.
    return f"{lo.statement} `{lo.lo_id}`" + ("" if lo.is_core else " (uitbreiding)")


LEVELS = ("easy", "medium", "hard")
SIGNAL_MARK = {"positive": "✓", "negative": "✗", "neutral": "○"}
LEVEL_LETTER = {"easy": "e", "medium": "m", "hard": "h"}
ASKED_MARK = {"recheck": "c", "warmup": "o"}


def _or(items: list[str]) -> str:
    return items[0] if len(items) == 1 else ", ".join(items[:-1]) + " of " + items[-1]


def _expected_level(exp: str) -> str:
    """The concept's header line on the milestone's expected level (#189)."""
    ok = [f"`{d}`" for d in LEVELS if rules.DIFF_ORDER[d] >= rules.DIFF_ORDER[exp]]
    low = [f"`{d}`" for d in LEVELS if rules.DIFF_ORDER[d] < rules.DIFF_ORDER[exp]]
    return (
        f"**Verwacht niveau van de mijlpaal: `{exp}`** ({dx.DIFF_NL.get(exp, exp)}). Kern telt vanaf hoogste niveau `{exp}`:"
        f" een aangetoond kerndoel met hoogste niveau {_or(ok)} telt mee" + (f", met {_or(low)} niet." if low else ".")
    )


def _herkomst(ev: dict) -> str:
    """Where μ came from: `dx.evidence`, in the concept's words (#189)."""
    n = ev["n"]
    parts = [f"{n} {'vraag' if n == 1 else 'vragen'}" + (f" ({ev['n_pos']} juist)" if n else "")]
    for label, (pos, neg) in (("vervolgvragen", ev["follow_up"]), ("incidenteel", ev["incidental"])):
        if pos or neg:
            parts.append(f"{label} {pos} juist / {neg} fout")
    if ev["transfer"]:
        parts.append(f"transfer-krediet {ev['transfer']}")
    return " · ".join(parts)


def _highest(ratchet: str | None) -> str:
    return ratchet or "nog geen rechtstreeks juist antwoord"


def _last_answers(ev: dict) -> str:
    """The last direct answers per day, e.g. `09-04 ✗h ✗h · 09-11 ✓mc ✓h`."""
    days: list[tuple[str, list[str]]] = []
    for d in ev["recent"]:
        day = d.at.strftime("%m-%d")
        mark = SIGNAL_MARK.get(d.signal, "?") + LEVEL_LETTER.get(d.difficulty, "?") + ASKED_MARK.get(d.asked_as, "") + ("s" if d.by_key else "")
        if days and days[-1][0] == day:
            days[-1][1].append(mark)
        else:
            days.append((day, [mark]))
    if not days:
        return "geen"
    text = " · ".join(f"{day} {' '.join(marks)}" for day, marks in days)
    if ev["streak"] > len(ev["recent"]):
        text += f" (de laatste {ev['streak']} juist)"
    return text


def _render_md(milestone, klas, per_student, now, json_path, period_start) -> str:
    since = f"sinds {period_start.date().isoformat()}" if period_start else "sinds de eerste oefening (de mijlpaal heeft geen begin van de periode)"
    L = []
    L.append(f"# Evaluatie — {milestone['title']} — {klas}")
    L.append("")
    L.append(f"Opgesteld {now.strftime('%Y-%m-%d %H:%M')} UTC · regels `{rules.RULES_VERSION}` · sidecar `{json_path.name}`")
    L.append("")
    L.append(_expected_level(milestone["expectedDifficulty"]))
    L.append("")
    L.append("**Zo is het getal gemaakt.** Elke oefening uit `turn_history` is herspeeld met de regels van v1.1. Drie daarvan zijn op 23-09 met de leerkracht beslist: een fout op `hard` weegt ×0,6 en op `easy` ×1,4 (#169); een leerdoel dat ooit aan de drie beheersingsvoorwaarden voldeed blijft aangetoond (#168); een opmerking van de grader over een eerder subdoel telt niet als negatief bewijs (#167). Een oefening onder toezicht — in de lestijd van de klas, 10 minuten ervoor en erna inbegrepen, ook van vóór de app dat zo bijhield (#219) — weegt ×1,25, een oefening thuis ×1,0. Een leerdoel is aangetoond vanaf twee juiste antwoorden (bewijs ≥ 5,75, en alleen een vraag over het leerdoel zelf toont het aan) voor een oefening van een build vanaf 2.12.0; daarvoor volstond bewijs 4, zoals de app toen stempelde (#276). Voor een oefening van een build vanaf 2.13.0 krimpt vóór elk nieuw antwoord wat een leerdoel aan bewijs heeft met 0,7: oude antwoorden wegen minder naarmate er meer volgen, juist en fout (#278). Een opfris- of controlevraag telt zoals in de app: als rechtstreekse vraag over haar eigen leerdoel, en de andere signalen van die oefening tegenover het subdoel waar de leerling toen mee bezig was. Kern = aangetoond én hoogste niveau (waarop het doel juist beantwoord werd) ≥ verwacht niveau van de mijlpaal. `M = 50·k + 50·k·(0,6·u + 0,4·d)`, en het punt is `P = M`, zonder groeiterm (v1.0.16).")
    L.append("")
    L.append("**Wat hieronder géén invloed heeft op het getal:** alles onder *diagnostiek*. Dat is er om de leerkracht te informeren. Een aanpassing van het punt is een beslissing van de leerkracht en krijgt een reden in het vak *Aanpassing*; die reden gaat mee naar het rapport.")
    L.append("")
    L.append(f"**Mee op het voorstel, naast het getal** (de app toont ze bij het voorstel; ze raken het getal niet): *verouderd* telt de leerdoelen van de mijlpaal waarover de app langer dan {rules.WARM_UP_STALE_AFTER_DAYS} dagen vóór dit concept niets meer noteerde (ook een neutraal oordeel op een rechtstreekse vraag telt, al is het geen bewijs; een neutraal oordeel van opzij niet), of nog nooit iets — de drempel van de app, een andere vraag dan de fossielen in de diagnostiek. *Oefeningen deze periode* telt de beoordeelde oefeningen {since}, onder toezicht (in de lestijd van de klas, 10 minuten marge) of thuis, met dezelfde regel als de app (#219); heeft de klas geen lessen in de app, dan is elke oefening 'thuis' en toont de app die telling niet (#173), maar ze staat wel op het voorstel.")
    L.append("")
    L.append(
        "**Zo lees je de leerdoelen onder *Bijna* en *Ver*.** *herkomst*: waar μ vandaan komt — de vragen over het leerdoel en hoeveel daarvan juist,"
        " vervolgvragen, wat de grader er *incidenteel* over zei terwijl een ander leerdoel beoordeeld werd (na de filter van de app: hetzelfde doel,"
        " een eerder subdoel; een incidentele fout weegt niet, #167), en transfer-krediet. Alleen een vraag geeft een hoogste niveau en kan het leerdoel"
        " aangetoond maken; de rest beweegt alleen μ. *hoogste niveau*: het hoogste niveau waarop een vraag over het leerdoel juist beantwoord werd."
        f" *laatste vragen*: de laatste {dx.LAST_ANSWERS}, per dag — ✓ juist, ✗ fout, ○ neutraal; e/m/h makkelijk/gewoon/moeilijk; c een controlevraag,"
        " o een opfrisvraag (allebei gesteld terwijl de leerling aan een ander subdoel werkte); s nagekeken met de sleutel van de vragenbank, niet door de grader."
    )
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
        if p["lost"]["total"]:
            sig.append(f"{p['lost']['total']} oefeningen telden niet voor hun leerdoel")
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
        rel = p["reliability"]
        L.append(f"**Mee op het voorstel:** verouderd {rel.stale_lo_count} leerdoel(en) (nooit bevraagd: {sc.never_probed}) · oefeningen deze periode: {rel.supervised_turns} onder toezicht, {rel.home_turns} thuis.")
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
                thin = " — te weinig vragen om aan te tonen" if r["thin"] else ""
                if r["status"] == "nooit bevraagd":
                    L.append(f"- {_lo_label(r['lo'])} — nooit bevraagd{thin}")
                    continue
                L.append(f"- {_lo_label(r['lo'])} — μ {r['mean']:.2f} — {r['status']}{thin}")
                L.append(f"  - herkomst: {_herkomst(r)}")
                L.append(f"  - hoogste niveau: {_highest(r['ratchet'])}")
                L.append(f"  - laatste vragen: {_last_answers(r)}")
            L.append("")
        if far:
            L.append("**Ver:**")
            L.append("")
            for r in far:
                L.append(f"- {_lo_label(r['lo'])} — μ {r['mean']:.2f} · herkomst: {_herkomst(r)}{' — te weinig vragen om aan te tonen' if r['thin'] else ''}")
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
        lost = p["lost"]
        if lost["total"]:
            L.append(
                f"**Oefeningen die niet telden voor hun eigen leerdoel:** {lost['total']}, waarvan {lost['correct']} juist"
                f" ({lost['in_milestone']} over deze mijlpaal). Rechtstreekse vragen zonder oordeel op het gevraagde leerdoel:"
                " de app gooide het weg (#225) of de grader gaf het niet. Wat weg is, komt niet terug; alleen juist of fout bleef bewaard."
            )
            for r in lost["per"]:
                ms = " — mijlpaal" if r["in_milestone"] else ""
                L.append(
                    f"- {r['statement']} `{r['lo']}` ({r['subgoal_title']}) ×{r['n']}, {r['correct']} juist ({', '.join(r['days'])}){ms}"
                )
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
        "periodStart": milestone.get("periodStart"),
        # Kern counts from this highest level on (#189); `apply` does not read it.
        "expectedDifficulty": milestone["expectedDifficulty"],
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
                    "staleLoCount": p["reliability"].stale_lo_count,
                    "supervisedTurns": p["reliability"].supervised_turns,
                    "homeTurns": p["reliability"].home_turns,
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


# `--regels` (#281): the rules every oefening replays with on `validate` and
# `replay-beliefs`. Without it each oefening replays with the rules of the
# build that wrote it (`rules.CURRENT`); `1.1` replays every one with
# formula 1.1, the ones from before 2.13.0 too — what the one-time rewrite
# at the release of 1.1 writes, if the teacher chooses it (#278).
RULE_CHOICES = {"1.1": rules.Variant(as_11=True)}


def _variant(args) -> rules.Variant:
    return RULE_CHOICES[args.regels] if getattr(args, "regels", None) else rules.CURRENT


def _rules_flag(args) -> str:
    """The flag again, for a command line the output suggests."""
    return f" --regels {args.regels}" if getattr(args, "regels", None) else ""


def _replay_student(uid: str, goals: dict, variant: rules.Variant = rules.CURRENT) -> tuple[list[dict], dict, dict]:
    """One student's turn log, `lo_beliefs` docs and the replay `validate`
    compares them to: `rules.replay` with the provenance the app recorded,
    so with the weight the app wrote the docs with, and with [variant]
    (`--regels`). `replay-beliefs` writes this same replay (#242), so
    `validate` with the same `--regels` reads its docs back as matching."""
    turns = cosmos.turns(uid)
    return turns, cosmos.beliefs(uid), rules.replay(turns, goals, variant=variant)


def _last_build(turns: list[dict]) -> str:
    """The `clientVersion` on the last oefening (#165); `oud` for a build
    without the field, `geen` without oefeningen."""
    return (turns[-1].get("clientVersion") or "oud") if turns else "geen"


def cmd_validate(args) -> None:
    """Replays with the rules the app computes with now and compares to
    `lo_beliefs`. A student whose client computes the same, on docs no older
    replay rewrote, matches to the rounding.

    The replay is `rules.replay` as `draft` calls it, not a variant of its
    own: until #203 this passed the flags of the arithmetic from before #167
    and #169, and every doc with a negative on `easy` or `hard`, or an
    incidental negative, read as an old build. Which build wrote the last
    oefening is on the record since #165 (`clientVersion`); a record
    without it comes from a build that still computes the old way. The
    oefeningen are not replayed each with its own build's arithmetic: the
    one-time rewrite of `lo_beliefs` (2026-09-23) recomputed the docs of
    every student on a client since #108 from the whole log, with the
    arithmetic of #167 and #169. The old arithmetic lives on in storage only
    where an old build wrote after that, or on a doc the rewrite left alone,
    and that is the deviation this command is for (README, *validate*).

    Unlike `draft`, it weighs a turn as supervised only where the app
    recorded it so (#219): that is what the app weighed when it wrote the
    doc. The turns from before #219, which `draft` reads by the timetable,
    are all `home` here, as they are in `lo_beliefs`.

    With `--regels 1.1` (#281) every oefening replays with formula 1.1, the
    ones of a build from before 2.13.0 too: the replay `replay-beliefs
    --regels 1.1` writes. After that rewrite this is the comparison that
    matches; without the flag every doc it rewrote reads as a deviation.
    The highest level is compared to the higher of that replay's and the
    replay by build (`_kept_level`): a rewrite never lowers it."""
    goals = cosmos.goals()
    students = cosmos.accounts(args.klas)
    variant = _variant(args)
    print(f"{'leerling':26}{'docs':>6}{'vergeleken':>12}{'|d mean|>0.01':>14}{'hoogste niveau anders':>24}{'laatste build':>16}")
    for a in students:
        turns, stored, st = _replay_student(a["uid"], goals, variant)
        by_build = st if variant == rules.CURRENT else rules.replay(turns, goals)
        n = off = rat = 0
        for key, b in stored.items():
            s = st.get(key)
            if not s:
                continue
            n += 1
            if abs(s.mean - b["alpha"] / (b["alpha"] + b["beta"])) > 0.01:
                off += 1
            if b.get("highestPositiveDifficulty") and b["highestPositiveDifficulty"] != _kept_level(s, by_build.get(key)):
                rat += 1
        build = _last_build(turns)
        print(f"{a.get('firstName','')+' '+a.get('lastName',''):26}{len(stored):>6}{n:>12}{off:>14}{rat:>24}{build:>16}")
    print(
        f"\nHerspeeld met de regels van de app sinds #167 en #169 ({rules.RULES_VERSION})"
        + ("." if getattr(args, "regels", None) else ", zoals het concept.") +
        " Een afwijking wijst op een document dat een oude build schreef (laatste build 'oud': de laatste oefening"
        " kwam van een build zonder clientVersion, die nog met de oude rekenregels werkt), of op een document"
        " dat met een oudere herspeling herschreven werd."
        " Ze raken het concept niet, dat leest alleen turn_history."
        " Anders dan in het concept weegt een oefening hier alleen als 'onder toezicht' (×1,25) als de app ze zo"
        " bewaarde, want zo schreef de app het document; het concept leest ook de oefeningen van vóór #219 volgens"
        " het lesrooster van de klas."
    )
    print(_rules_note(args))


def _kept_level(state: rules.LoState, by_build: rules.LoState | None) -> str | None:
    """The highest level a doc keeps after a rewrite with [state]'s replay:
    the higher of it and the replay by build's ([by_build]). The level is
    one-way (#103), so `replay-beliefs` never lowers it, and a build from
    before #276 raised it on every direct signal, where 1.1 raises it only
    on the question's target. Without `--regels` the two are the same."""
    levels = [state.ratchet] + ([by_build.ratchet] if by_build is not None else [])
    return max(levels, key=lambda level: rules.DIFF_ORDER[level])


def _rules_note(args) -> str:
    """What `--regels` did to the replay, for `validate` and `replay-beliefs`."""
    if getattr(args, "regels", None):
        return (
            f"--regels {args.regels}: elke oefening herspeeld met de regels van {args.regels}, ook die van een build"
            " van vóór 2.13.0 (vergeten per antwoord, een meerkeuzevraag weegt de helft, de vierde voorwaarde"
            " voor de stempel), anders dan het concept, dat elke oefening met de regels van haar build herspeelt."
            " Zo herschrijft replay-beliefs --regels 1.1 de documenten bij de release."
        )
    return (
        "Elke oefening herspeeld met de regels van de build die ze schreef: een oefening van vóór 2.13.0 zonder"
        " vergeten. Na een herschrijving met replay-beliefs --regels 1.1: vergelijk met --regels 1.1."
    )


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

# Counted by `draft` since #171 (`rules.reliability`); `neverProbedCount`
# comes with the score.
RELIABILITY_FIELDS = ("staleLoCount", "supervisedTurns", "homeTurns")


def cmd_apply(args) -> None:
    data = json.loads(Path(args.draft).read_text(encoding="utf-8"))
    mid = data["milestoneId"]
    students = cosmos.accounts(data["klas"])
    by_uid = {a["uid"]: a for a in students}

    # No lesson guard, unlike `replay-beliefs`: the student app never opens
    # `grade_proposals`, so a write in the lesson collides with nothing a
    # student does, and a teacher editing the same proposal meets If-Match.
    todo = [s for s in data["students"] if not s.get("skip")]
    missing = [s["name"] for s in todo if not s.get("justification")]
    if missing and not args.force:
        sys.exit("Zonder verantwoording niet aftekenen (of --force):\n  " + ", ".join(missing))

    for s in todo:
        j = s.get("justification") or ""
        if "Verantwoording van je score" not in j or "\nFeedback" not in j:
            print(f"  let op: {s['name']}: de rapporttekst mist een van de twee koppen")
    # A sidecar drafted before these were counted has no value for them. A
    # missing field on the proposal is honest; a 0 the teacher then reads
    # as "0 thuis" beside 200 oefeningen is not.
    uncounted = [s["name"] for s in todo if any(f not in s["computed"] for f in RELIABILITY_FIELDS)]
    if uncounted:
        print("  let op: dit concept telt verouderde leerdoelen en oefeningen onder toezicht/thuis nog niet; die velden blijven weg in plaats van 0 (maak een nieuw concept om ze te tellen): " + ", ".join(uncounted))
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
            "mEnd": c["mEnd"],
            "proposal": c["proposal"],
            "coreTotal": c["coreTotal"], "coreCounted": c["coreCounted"],
            "extensionTotal": c["extensionTotal"], "extensionMastered": c["extensionMastered"],
            "masteredTotal": c["masteredTotal"], "hardCount": c["hardCount"],
            "neverProbedCount": c["neverProbedCount"],
            **{f: c[f] for f in RELIABILITY_FIELDS if f in c},
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


# ---- replay-beliefs (#242) ---------------------------------------------------

# What `replay-beliefs` writes on a `lo_beliefs` doc; `lastProbedAt` only
# where the doc has none (#275: "neem het mee"); the own-question counts of
# formula 1.1 (#278, #279) as the larger of stored and replayed (#281).
# Every other field — `lastUpdatedAt`, `regressedAt`, the calibration
# clock, and the session state of #275, `returnWrongAt` and `thinCheckedAt`
# (what the app did with a return, no belief a replay recomputes) — stays
# as the app wrote it.
BELIEF_FIELDS = (
    "alpha", "beta", "firstMasteredAt", "highestPositiveDifficulty", "lastProbedAt",
    "ownQuestions", "ownQuestionsRight", "ownQuestionsRightNonMcq",
)
# α + β from which an LO was "on the cap" until formula 1.1: not
# practiceable any more (CONDUCTOR_POLICY §2.1, §3.4 before #278). The dry
# run counts the docs a rewrite takes under it (#281).
SATURATED_EVIDENCE = 18.0
# α and β within this of the stored ones are the same numbers computed
# twice: the app decays to the moment it writes, a second or so after
# `turnAt`, and Dart and Python round apart in the last bits. On 6EWI
# (2026-10-07) that stayed under 1e-5, and every real deviation was over
# 1e-2. The doc keeps its own.
BELIEF_TOLERANCE = 1e-4


def _app_iso(at: dt.datetime) -> str:
    """[at] as the app stores a moment (`DateTime.toUtc().toIso8601String()`):
    milliseconds always, microseconds only when there are any, and `Z`."""
    utc = at.replace(tzinfo=dt.timezone.utc) if at.tzinfo is None else at.astimezone(dt.timezone.utc)
    micro = utc.microsecond % 1000
    return f"{utc:%Y-%m-%dT%H:%M:%S}.{utc.microsecond // 1000:03d}" + (f"{micro:03d}" if micro else "") + "Z"


def _stored_at(raw) -> dt.datetime | None:
    """A moment on a stored doc; None where the app would read none
    (`DateTime.tryParse` on a missing or unreadable value)."""
    if not isinstance(raw, str):
        return None
    try:
        at = rules.parse_at(raw)
    except ValueError:
        return None
    return at.replace(tzinfo=dt.timezone.utc) if at.tzinfo is None else at


def _stored_number(raw) -> float:
    """α or β on a stored doc; the prior where the app would read it so."""
    return float(raw) if isinstance(raw, (int, float)) and not isinstance(raw, bool) else rules.PRIOR


def _stored_count(raw) -> int | None:
    """A count on a stored doc; None where the app reads none, a missing or
    unreadable value: `ownQuestions` then reads 0, and the two right counts
    stay missing, which is not 0 (#279, #275)."""
    return int(raw) if isinstance(raw, (int, float)) and not isinstance(raw, bool) else None


# `LoBelief.fromCosmos` reads a doc without a readable `lastUpdatedAt` as
# written in 1970.
_APP_EPOCH = dt.datetime(1970, 1, 1, tzinfo=dt.timezone.utc)


def _app_state(doc: dict) -> rules.LoState:
    """[doc] as the app reads it, as a `rules.LoState` for the rules'
    judgements. A missing count reads 0 here; `_has_right_counts` tells the
    missing right counts apart."""
    return rules.LoState(
        alpha=_stored_number(doc.get("alpha")),
        beta=_stored_number(doc.get("beta")),
        last_at=_stored_at(doc.get("lastUpdatedAt")) or _APP_EPOCH,
        positive_at_calibrated_at=_stored_at(doc.get("lastPositiveAtCalibratedAt")),
        first_mastered_at=_stored_at(doc.get("firstMasteredAt")),
        own_questions=_stored_count(doc.get("ownQuestions")) or 0,
        own_right=_stored_count(doc.get("ownQuestionsRight")) or 0,
        own_right_open=_stored_count(doc.get("ownQuestionsRightNonMcq")) or 0,
    )


def _has_right_counts(doc: dict) -> bool:
    """`LoBelief.hasRightCounts`: false on a doc from before formula 1.1."""
    return any(_stored_count(doc.get(f)) is not None for f in ("ownQuestionsRight", "ownQuestionsRightNonMcq"))


def app_ever_mastered(doc: dict) -> bool:
    """`belief_math.everMasteredBelief`: the stamp, or on a doc without it
    the reading of an old one — conditions 1–3 of §4.1 on the stored
    numbers, and condition 4 where the doc keeps the counts (#279)."""
    s = _app_state(doc)
    if s.first_mastered_at is not None:
        return True
    if not s.mastered_at():
        return False
    return not _has_right_counts(doc) or (
        s.own_right >= rules.STAMP_OWN_RIGHT_MIN and s.own_right_open >= rules.STAMP_OWN_RIGHT_NON_MCQ_MIN
    )


def app_stamp(doc: dict) -> dt.datetime | None:
    """The stamp the app reads on [doc]: `firstMasteredAt`, or on an old doc
    without it that reads as mastered (`app_ever_mastered`) its
    `lastUpdatedAt`, which the app writes as the stamp at its next write."""
    at = _stored_at(doc.get("firstMasteredAt"))
    if at is None and app_ever_mastered(doc):
        at = _app_state(doc).last_at
    return at


def app_stuck(doc: dict, now: dt.datetime) -> bool:
    """Stuck as #275 brings it back (`Conductor`, `RecheckRule.stuck`): no
    stamp (`app_ever_mastered`), and `rules.is_stuck` on the doc decayed to
    [now] — at least 6 own questions and μ under 0.6. A doc without
    `ownQuestions` reads 0, so it is not stuck until the count is filled."""
    return not app_ever_mastered(doc) and rules.is_stuck(_app_state(doc), now)


def app_thin_stamp(doc: dict) -> bool:
    """`belief_math.isThinStamp`: a stamp on fewer than two right own
    questions, on a doc that keeps the counts. A stamp without them is no
    thin one, so filling them decides which stamps from before 1.1 are."""
    return _has_right_counts(doc) and rules.is_thin_stamp(_app_state(doc))


def on_the_cap(doc: dict) -> bool:
    """α + β at `SATURATED_EVIDENCE` or more: an LO the app did not ask any
    more until formula 1.1."""
    return _stored_number(doc.get("alpha")) + _stored_number(doc.get("beta")) >= SATURATED_EVIDENCE


def _on_a_later_oefening(replayed: dt.datetime, stored: dt.datetime, oefening_times: list[dt.datetime]) -> bool:
    """Whether the stored stamp fell on a later oefening than the replayed
    one: an oefening began after the replayed stamp and no later than the
    stored one. The replay stamps at the oefening's `turnAt`, the app when it
    writes the doc, a second or so later: on the same oefening the two differ
    without one being earlier."""
    i = bisect.bisect_right(oefening_times, replayed)
    return i < len(oefening_times) and oefening_times[i] <= stored


def replayed_belief(stored: dict, state: rules.LoState, oefening_times: list[dt.datetime]) -> dict:
    """[stored] with the fields the replay restores (#242, `BELIEF_FIELDS`),
    and nothing else changed. [oefening_times] are the student's oefeningen, by
    `turnAt`, sorted.

    - α and β: the replay's, unless they are the stored ones to within
      `BELIEF_TOLERANCE`;
    - `firstMasteredAt`: the earliest of the stored and the replayed stamp,
      by oefening — on the same oefening the app's own stamp stays
      (`_on_a_later_oefening`). Never cleared: a stamp the replay does not
      reach stays, and without either the field stays away. The stored
      stamp is the one the app reads (`app_stamp`): on an old doc without
      the field that reads as mastered, its `lastUpdatedAt`, which the app
      writes as the stamp at its next write. Where the counts below, or new
      α and β, would end that reading, it is written here, as the app
      would;
    - `highestPositiveDifficulty`: the highest of the stored and the
      replayed level. Never lowered; an unknown stored level reads as none,
      as the app reads it;
    - `lastProbedAt` (#275, the backfill of #187 the README describes):
      the replay's last direct probe, only on a doc without the field —
      what the app wrote goes first — and not at all when the replay has
      none (never asked directly, as the app already reads it). A doc
      without it reads `lastUpdatedAt`, at worst late; since #275 the
      recheck slot reaches earlier roots too, where those docs are;
    - `ownQuestions`, `ownQuestionsRight` and `ownQuestionsRightNonMcq`
      (#281): each the larger of the stored and the replayed count
      (`LoState.own_questions`, `own_right`, `own_right_open`). The replay
      counts every oefening in `turn_history`, the ones the app counted
      too. The two right counts are written together, also as 0 on a doc
      without them: missing is not 0 for the app (#279). `ownQuestions`
      reads 0 when missing, so a 0 leaves it away.

    The stamp, the level and the counts are one-way in the app too (#168,
    #103, #279): this restores what an old build never wrote, and takes
    nothing away. Filling the right counts does change one reading: a
    stamp on a doc without them is no thin stamp (#275), and with them it
    can be (`app_thin_stamp`)."""
    doc = dict(stored)
    alpha, beta = _stored_number(stored.get("alpha")), _stored_number(stored.get("beta"))
    if abs(state.alpha - alpha) > BELIEF_TOLERANCE or abs(state.beta - beta) > BELIEF_TOLERANCE:
        doc["alpha"], doc["beta"] = state.alpha, state.beta
    replayed, stamp = state.first_mastered_at, app_stamp(stored)
    if replayed is not None and (
        stamp is None or (replayed < stamp and _on_a_later_oefening(replayed, stamp, oefening_times))
    ):
        doc["firstMasteredAt"] = _app_iso(replayed)
    questions = _stored_count(stored.get("ownQuestions")) or 0
    if state.own_questions > questions:
        doc["ownQuestions"] = state.own_questions
    right = (_stored_count(stored.get("ownQuestionsRight")), _stored_count(stored.get("ownQuestionsRightNonMcq")))
    counts = (max(right[0] or 0, state.own_right), max(right[1] or 0, state.own_right_open))
    if counts != right:
        doc["ownQuestionsRight"], doc["ownQuestionsRightNonMcq"] = counts
    level = stored.get("highestPositiveDifficulty")
    rank = rules.DIFF_ORDER.get(level, -1) if isinstance(level, str) else -1
    if rules.DIFF_ORDER[state.ratchet] > rank:
        doc["highestPositiveDifficulty"] = state.ratchet
    if _stored_at(stored.get("lastProbedAt")) is None and state.last_direct_at is not None:
        doc["lastProbedAt"] = _app_iso(state.last_direct_at)
    if stamp is not None and app_stamp(doc) is None:
        # The stamp the app read on the old doc, which this write would end.
        doc["firstMasteredAt"] = _app_iso(stamp)
    return doc


def belief_changes(stored: dict, new: dict) -> set[str]:
    """What [new] changes on [stored]: `alpha/beta`, `stamp gained` (the app
    read none), `stamp earlier`, `stamp kept` (the stamp the app read on an
    old doc without the field, now written, `app_stamp`), `level raised`,
    `clock filled` (#275), `counts` (#281). Empty: nothing to write."""
    changes = set()
    if new.get("alpha") != stored.get("alpha") or new.get("beta") != stored.get("beta"):
        changes.add("alpha/beta")
    if new.get("firstMasteredAt") != stored.get("firstMasteredAt"):
        before = app_stamp(stored)
        if before is None:
            changes.add("stamp gained")
        else:
            changes.add("stamp kept" if _stored_at(new.get("firstMasteredAt")) == before else "stamp earlier")
    if new.get("highestPositiveDifficulty") != stored.get("highestPositiveDifficulty"):
        changes.add("level raised")
    if new.get("lastProbedAt") != stored.get("lastProbedAt"):
        changes.add("clock filled")
    if any(new.get(f) != stored.get(f) for f in ("ownQuestions", "ownQuestionsRight", "ownQuestionsRightNonMcq")):
        changes.add("counts")
    return changes


def belief_effects(stored: dict, new: dict, now: dt.datetime) -> set[str]:
    """What the app reads differently of [new] than of [stored] at [now]
    (#281, the dry run's last columns): `off the cap` (α + β was at
    `SATURATED_EVIDENCE` or more, now under it: practiceable again),
    `stuck` (`app_stuck`: comes back as a recheck, a notch lower first,
    #275) and `thin` (`app_thin_stamp`: one check question a week after its
    last direct probe; the stamp stays)."""
    effects = set()
    if on_the_cap(stored) and not on_the_cap(new):
        effects.add("off the cap")
    if app_stuck(new, now) and not app_stuck(stored, now):
        effects.add("stuck")
    if app_thin_stamp(new) and not app_thin_stamp(stored):
        effects.add("thin")
    return effects


def _class_at_work(students: list[dict], klas: str) -> list[str]:
    """Why a write to `lo_beliefs` now would race the class: its lesson time
    by the timetable (#219, the 10-minute margin included), or a student
    active in the last minutes, as `apply` refuses."""
    reasons = []
    if rules.during_lesson(rules.lessons_of(cosmos.classes(), klas), _now()):
        reasons.append(f"{klas} heeft nu les volgens het lesrooster")
    busy = _lesson_in_progress(students)
    if busy:
        reasons.append("de laatste minuten actief: " + ", ".join(busy))
    return reasons


def cmd_replay_beliefs(args) -> None:
    """Replays `lo_beliefs` from `turn_history` and restores α, β, the stamp
    and the highest level on the docs there (#242): for students whose
    client wrote docs without `firstMasteredAt` and `highestPositiveDifficulty`
    and whom the one-time rewrite of 2026-09-23 passed by. And it fills the
    direct-probe clock `lastProbedAt` on a doc without one (#275, the
    backfill of #187), and the own-question counts of formula 1.1 (#281).

    The replay is the one `validate` compares to (`_replay_student`), so
    `validate` with the same `--regels` shows no deviation on a doc this
    wrote. `--regels 1.1` replays every oefening with formula 1.1 (#281):
    the one-time rewrite the teacher can choose at the release, which takes
    LOs off the cap at once (#278). It only updates docs
    that exist: a replayed LO without a doc gets none (the app creates it on
    the next write), and a doc the replay does not reach stays as it is.

    The dry run also says what the app reads differently afterwards
    (`belief_effects`): LOs off the cap, LOs stuck and stamps thin — the
    last two come back as rechecks (#275), and filling the counts is what
    makes them so.

    A dry run unless `--apply`. With it: refuses in the lesson time of the
    class or while a student works (`--force` to go on), backs up every
    `lo_beliefs` and `grade_proposals` doc of the students it writes for to
    `BACKUP_DIR`, then upserts each changed doc with `If-Match` on the etag
    it was planned from — a doc the app wrote in between is skipped and
    named. Run it again for those."""
    goals = cosmos.goals()
    in_class = cosmos.accounts(args.klas)
    if not in_class:
        sys.exit(f"geen leerlingen met className={args.klas!r}")
    students = in_class
    if args.leerling:
        picked = [_pick_student(in_class, name, args.klas) for name in args.leerling]
        students = [a for a in in_class if any(p["uid"] == a["uid"] for p in picked)]

    print(
        f"{'leerling':26}{'docs':>6}{'herspeeld':>11}{'te schrijven':>14}{'stempel erbij':>15}"
        f"{'stempel vroeger':>17}{'niveau hoger':>14}{'α/β anders':>12}{'klok erbij':>12}{'tellingen':>11}"
        f"{'van plafond':>13}{'vastgelopen':>13}{'dun':>5}{'laatste build':>16}"
    )
    variant, now = _variant(args), _now()
    planned: list[tuple[dict, dict, dict]] = []  # (student, stored doc, new doc)
    totals = dict.fromkeys(
        ("stamp gained", "stamp earlier", "stamp kept", "level raised", "alpha/beta", "clock filled", "counts",
         "off the cap", "stuck", "thin"), 0,
    )
    old_build = []
    for a in students:
        turns, stored, st = _replay_student(a["uid"], goals, variant)
        oefening_times = sorted(rules.parse_at(t["turnAt"]) for t in turns if not rules.is_audit(t))
        replayed = mine = 0
        counts = dict.fromkeys(totals, 0)
        for key in sorted(stored):
            state = st.get(key)
            if state is None:
                continue
            replayed += 1
            new = replayed_belief(stored[key], state, oefening_times)
            changes = belief_changes(stored[key], new)
            if not changes:
                continue
            mine += 1
            planned.append((a, stored[key], new))
            for c in changes | belief_effects(stored[key], new, now):
                counts[c] += 1
                totals[c] += 1
        build = _last_build(turns)
        if build == "oud":
            old_build.append(_full_name(a))
        print(
            f"{_full_name(a):26}{len(stored):>6}{replayed:>11}{mine:>14}{counts['stamp gained']:>15}"
            f"{counts['stamp earlier']:>17}{counts['level raised']:>14}{counts['alpha/beta']:>12}"
            f"{counts['clock filled']:>12}{counts['counts']:>11}{counts['off the cap']:>13}"
            f"{counts['stuck']:>13}{counts['thin']:>5}{build:>16}"
        )
    writers = {a["uid"] for a, _, _ in planned}
    print(
        f"\nte schrijven: {len(planned)} documenten bij {len(writers)} leerling(en) — stempel erbij"
        f" {totals['stamp gained']}, stempel vroeger {totals['stamp earlier']}, hoogste niveau hoger"
        f" {totals['level raised']}, α/β anders {totals['alpha/beta']}, klok erbij {totals['clock filled']},"
        f" tellingen {totals['counts']}."
    )
    if args.regels and totals["stamp gained"]:
        print(
            f"stempel erbij met --regels {args.regels}: de regels van {args.regels} op de oude antwoorden. De app leest"
            " die leerdoelen daarna als aangetoond; het concept herspeelt elke oefening met de regels van haar build"
            f" en telt een stempel die alleen {args.regels} geeft niet."
        )
    if totals["stamp kept"]:
        print(
            f"stempel vastgelegd {totals['stamp kept']}: een oud document zonder firstMasteredAt dat de app als"
            " aangetoond leest, krijgt de stempel die de app er bij haar volgende schrijving op zet (lastUpdatedAt);"
            " met de tellingen of de nieuwe alpha en beta zou ze hem niet meer zo lezen."
        )
    stuck_mean = f"{rules.STUCK_MEAN}".replace(".", ",")
    print(
        f"Daarna in de app: van het plafond {totals['off the cap']} (α + β was {SATURATED_EVIDENCE:.0f} of meer,"
        f" nu minder: weer te oefenen, #278), vastgelopen {totals['stuck']} (geen stempel,"
        f" {rules.STUCK_OWN_QUESTIONS_MIN} of meer eigen vragen en μ onder {stuck_mean}: komt terug als"
        f" controlevraag, eerst een niveau lager, #275), dun {totals['thin']} (een stempel op minder dan"
        f" {rules.STAMP_OWN_RIGHT_MIN} juiste eigen vragen: één controlevraag een week na de laatste rechtstreekse"
        " vraag, de stempel blijft, #275)."
    )
    print(
        "Een stempel op een document zonder de tellingen van 1.1 is in de app nooit dun. Door de tellingen aan te"
        " vullen beslist deze herschrijving welke stempels van vóór 1.1 dun zijn; zonder herschrijving krijgt geen"
        " enkele een controlevraag. Een leerdoel zonder ownQuestions leest 0 eigen vragen en loopt pas na zes"
        " nieuwe vast."
    )
    print(
        f"Herspeeld met {rules.RULES_VERSION}, zoals validate{_rules_flag(args)}: een oefening weegt alleen als"
        " 'onder toezicht' als de app ze zo bewaarde. Alleen alpha, beta, firstMasteredAt (de vroegste, nooit"
        " leeg), highestPositiveDifficulty (het hoogste), lastProbedAt (alleen waar het ontbreekt) en de"
        " tellingen ownQuestions, ownQuestionsRight en ownQuestionsRightNonMcq (de grootste van opgeslagen en"
        " herspeeld) veranderen; een leerdoel zonder document krijgt er geen."
    )
    print(_rules_note(args))
    if old_build:
        print(
            "let op: de laatste oefening kwam van een build zonder clientVersion, die nog met de oude regels"
            " schrijft: " + ", ".join(old_build)
        )
    if not args.apply:
        keep = f" (met{_rules_flag(args)})" if args.regels else ""
        print(f"\nDroge run: er is niets geschreven. Schrijven: dezelfde opdracht{keep} met --apply erbij, buiten de lesuren.")
        return
    if not planned:
        print("\nNiets te schrijven.")
        return
    busy = _class_at_work(students, args.klas)
    if busy and not args.force:
        sys.exit("De klas werkt; niets geschreven. Wacht, of --force:\n  " + "\n  ".join(busy))
    path = _backup([a for a in students if a["uid"] in writers], None, BACKUP_DIR, f"{_slug(args.klas)}_replay-beliefs")
    print(f"\nback-up: {path}")

    written = conflicts = 0
    for a, stored, new in planned:
        try:
            cosmos.upsert("lo_beliefs", new, a["uid"], etag=stored.get("_etag"))
            written += 1
        except cosmos.Conflict:
            conflicts += 1
            print(f"  {_full_name(a)}: {stored['subgoalId']}/{stored['loId']} veranderde intussen — niet geschreven")
    print(f"geschreven {written}, conflicten {conflicts}" + (" (draai het opnieuw voor die)" if conflicts else ""))
    print(f"Controleer met: evaluate.py validate --klas {args.klas}{_rules_flag(args)}")


# ---- what-if -----------------------------------------------------------------


def _full_name(a: dict) -> str:
    return f"{a.get('firstName', '')} {a.get('lastName', '')}".strip()


def _pick_student(students: list[dict], arg: str, klas: str) -> dict:
    q = arg.strip().lower()
    hits = [a for a in students if a["uid"] == arg or _full_name(a).lower() == q]
    if not hits:
        hits = [a for a in students if q in _full_name(a).lower()]
    if len(hits) != 1:
        sys.exit(f"--leerling {arg!r} matcht {len(hits)} leerlingen in {klas}" + ("".join(f"\n  {_full_name(a)}" for a in hits)))
    return hits[0]


def _pick_los(los: list[rules.MilestoneLo], arg: str) -> list[rules.MilestoneLo]:
    picked = []
    for name in (x.strip() for x in arg.split(",")):
        if not name:
            continue
        hits = [lo for lo in los if name in (lo.lo_id, f"{lo.subgoal_id}/{lo.lo_id}")]
        if len(hits) != 1:
            sys.exit(
                f"--tel {name!r} matcht {len(hits)} leerdoelen van de mijlpaal (geef subdoel/leerdoel bij twee); de leerdoelen:\n  "
                + "\n  ".join(f"{lo.subgoal_id}/{lo.lo_id}" for lo in los)
            )
        if hits[0] not in picked:
            picked.append(hits[0])
    if not picked:
        sys.exit("--tel: geen leerdoelen")
    return picked


def cmd_what_if(args) -> None:
    """What the number becomes when the teacher counts LOs as demonstrated
    (#189): `rules.score_counting` on the replay `draft` grades on, so the
    number keeps coming from `rules.py` and nobody forces a state by hand.
    Reads only."""
    milestone = _pick_milestone(args.mijlpaal)
    goals = cosmos.goals()
    los = rules.milestone_los(milestone, goals)
    exp = milestone["expectedDifficulty"]
    a = _pick_student(cosmos.accounts(args.klas), args.leerling, args.klas)
    counted = _pick_los(los, args.tel)
    supervised = rules.by_timetable(rules.lessons_of(cosmos.classes(), args.klas))
    st = rules.replay([t for t in cosmos.turns(a["uid"]) if not rules.is_audit(t)], goals, supervised=supervised)
    now = rules.score(los, st, exp)
    then = rules.score_counting(los, st, exp, [lo.key for lo in counted])

    print(f"{_full_name(a)} · {milestone['title']} · verwacht niveau {exp} · regels {rules.RULES_VERSION}")
    print()
    print(f"{'':11}{'kern':>6}{'uitbr':>7}{'moeilijk':>10}{'M':>7}{'punt':>6}")
    for label, sc in (("nu", now), ("meegeteld", then)):
        print(
            f"{label:11}{f'{sc.core_counted}/{sc.core_total}':>6}{f'{sc.extension_mastered}/{sc.extension_total}':>7}"
            f"{f'{sc.hard_count}/{sc.mastered_total}':>10}{sc.m:>7.1f}{sc.proposal:>6}"
        )
    print()
    print(f"Meegeteld als aangetoond, met hoogste niveau minstens {exp}:")
    for lo in counted:
        s = st.get(lo.key)
        state = "nooit bevraagd" if s is None else f"μ {s.mean:.2f} · herkomst: {_herkomst(dx.evidence(s))} · hoogste niveau: {_highest(s.ratchet)}"
        change = []
        if not (s and s.demonstrated):
            change.append("aangetoond")
        if rules.DIFF_ORDER[s.ratchet if s else None] < rules.DIFF_ORDER[exp]:
            change.append(f"hoogste niveau {exp}")
        print(f"- {_lo_label(lo)} — {state} — " + ("telt al mee" if not change else "geteld als " + " en ".join(change)))


# ---- trace (#228) ------------------------------------------------------------

QUALITY_NL = {"correct": "juist", "partial": "deels juist", "wrong": "fout"}
SIGNAL_NL = {"positive": "positief", "negative": "negatief", "neutral": "neutraal"}
STRENGTH_NL = {"strong": "sterk", "moderate": "matig", "weak": "zwak"}
STATUS_NL = {
    "telt": "telt",
    "aanvaard": "aanvaard",
    "weggegooid": "weggegooid",
    "sleutel": "niet gebruikt (de sleutel besliste)",
    "terugval": "terugval (alle signalen weggegooid)",
}
WEEKDAY_NL = ("maandag", "dinsdag", "woensdag", "donderdag", "vrijdag", "zaterdag", "zondag")


def _parse_day(text: str) -> dt.date:
    try:
        return dt.date.fromisoformat(text)
    except ValueError:
        sys.exit(f"--dag {text!r} is geen datum (JJJJ-MM-DD)")


def _block(label: str, text: str) -> list[str]:
    """[text] after [label], its continuation lines indented to match."""
    lines = (text or "").splitlines() or [""]
    return [f"  {label:<9} {lines[0]}"] + [f"  {'':<9} {line}" for line in lines[1:]]


def _code(text: str) -> list[str]:
    return [f"  {'':<9} | {line}" for line in (text or "").splitlines()]


def _signal_line(s: dict) -> str:
    signal = SIGNAL_NL.get(s.get("signal"), s.get("signal"))
    strength = STRENGTH_NL.get(s.get("strength"), s.get("strength"))
    what = f"{s.get('subgoalId')}/{s.get('loId')} {signal}, {strength}"
    reason = s.get("reason")
    status = STATUS_NL.get(s["status"], s["status"])
    return f"{status:<11} {what}" + (f" — {dx.DROP_NL.get(reason, reason)}" if reason else "")


def _render_trace_row(r: dict) -> list[str]:
    kind = " · ".join(
        x
        for x in (
            r["type"],
            dx.DIFF_NL.get(r["difficulty"], r["difficulty"]) if r["difficulty"] else None,
            QUALITY_NL.get(r["quality"], r["quality"]) if r["quality"] else None,
            "vervolgvraag" if r["follow_up"] else None,
            "opwarmer" if r["warm_up"] else None,
            "hercontrole" if r["recheck"] else None,
            "beoordeeld met de sleutel" if r["graded_by_key"] else None,
        )
        if x
    )
    if r["statement"]:
        lo = f"{r['statement']} `{r['lo']}`"
    else:
        lo = f"`{r['lo']}`" if r["lo"] else "?"
    out = [f"{r['at']:%H:%M}  {r['subgoal_title']} · {lo} · {kind}"]
    if not r["has_turn"]:
        out.append("  (geen turn_history-record: gewist bij een reset?)")
    if not r["has_content"]:
        out.append("  (geen inhoud bewaard: van vóór #228, of de schrijving mislukte)")
    else:
        q = r["question"] or {}
        if q:
            out += _block("vraag", q.get("text", ""))
            out += _code(q.get("code"))
            if q.get("options"):
                key = f" — sleutel: {q['correctOption']}" if q.get("correctOption") else ""
                out.append(f"  {'':<9} opties: {' · '.join(q['options'])}{key}")
        else:
            out.append("  vraag     (onbekend: de app herstartte tussen vraag en antwoord)")
        a = r["answer"] or {}
        if "code" in a:
            out.append("  antwoord  code:")
            out += _code(a["code"])
        elif "picked" in a:
            out.append(f"  antwoord  gekozen: {a['picked']}")
        elif "text" in a:
            out += _block("antwoord", a["text"])
        else:
            out.append("  antwoord  (onbekend)")
        out += _block("feedback", r["feedback"] or "")
    sigs = r["signals"]
    if sigs:
        out.append(f"  signalen  {_signal_line(sigs[0])}")
        out += [f"  {'':<9} {_signal_line(s)}" for s in sigs[1:]]
    else:
        out.append("  signalen  geen")
    if r["has_content"]:
        ctx = r["context"]
        out.append(
            f"  context   hoofddoel {ctx.get('activeRootId')}, subdoel {ctx.get('activeSubgoalId')}"
            f" · begon met: {r['session_start']} · hints: {r['hints'] or 0}"
        )
        pref = [f"{k} {ctx[k]}" for k in ("preferredRootId", "preferredChildId") if ctx.get(k)]
        if pref:
            out.append(f"  {'':<9} voorkeur: {', '.join(pref)}")
    return out


def cmd_trace(args) -> None:
    """What happened on one student's oefeningen on one day (#228): the turn
    records and the content next to them, by `diagnostics.trace`. Reads only;
    prints to the terminal, writes no file."""
    day = _parse_day(args.dag)
    students = cosmos.accounts(args.klas) if args.klas else cosmos.all_accounts()
    a = _pick_student(students, args.leerling, args.klas or "de database")
    goals = cosmos.goals()

    def on_day(at: str) -> bool:
        return rules.belgian_time(rules.parse_at(at)).date() == day

    # The Belgian day lies inside the UTC days around it; `turnAt` is stored
    # as an ISO string, so the bounds compare as text.
    since = (day - dt.timedelta(days=1)).isoformat()
    until = (day + dt.timedelta(days=2)).isoformat()
    turns = [t for t in cosmos.turns(a["uid"]) if on_day(t["turnAt"])]
    contents = {
        cid: c for cid, c in cosmos.turn_contents(a["uid"], since, until).items() if on_day(c["turnAt"])
    }
    if args.subdoel:
        turns = [t for t in turns if t.get("subgoalId") == args.subdoel]
        contents = {cid: c for cid, c in contents.items() if c.get("subgoalId") == args.subdoel}
    rows = dx.trace(turns, contents, goals)

    title = f"{_full_name(a)} · {WEEKDAY_NL[day.weekday()]} {day.isoformat()}"
    if args.subdoel:
        title += f" · subdoel {(goals.get(args.subdoel) or {}).get('title') or args.subdoel} `{args.subdoel}`"
    print(f"{title} · {len(rows)} {'oefening' if len(rows) == 1 else 'oefeningen'}")
    without = sum(1 for r in rows if not r["has_content"])
    if without:
        print(f"zonder bewaarde inhoud: {without}")
    for r in rows:
        print()
        print("\n".join(_render_trace_row(r)))


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
    regels = {
        "choices": sorted(RULE_CHOICES),
        "help": "herspeel elke oefening met deze regels, ook die van een oudere build (zonder: per build)",
    }
    v = sub.add_parser("validate"); v.add_argument("--klas", required=True); v.add_argument("--regels", **regels)
    b = sub.add_parser("backup"); b.add_argument("--klas", required=True); b.add_argument("--out")
    a = sub.add_parser("apply"); a.add_argument("draft"); a.add_argument("--force", action="store_true")
    w = sub.add_parser("what-if"); w.add_argument("--klas", required=True); w.add_argument("--leerling", required=True)
    w.add_argument("--tel", required=True, help="leerdoelen, komma-gescheiden: lo_id of subdoel/lo_id"); w.add_argument("--mijlpaal")
    t = sub.add_parser("trace"); t.add_argument("--leerling", required=True); t.add_argument("--dag", required=True, help="JJJJ-MM-DD, Belgische tijd")
    t.add_argument("--subdoel"); t.add_argument("--klas", help="zoek de leerling alleen in deze klas")
    r = sub.add_parser("replay-beliefs"); r.add_argument("--klas", required=True)
    r.add_argument("--leerling", action="append", help="alleen deze leerling (naam, deel ervan of uid); herhaalbaar")
    r.add_argument("--regels", **regels)
    r.add_argument("--apply", action="store_true", help="na een back-up echt schrijven, buiten de lesuren")
    r.add_argument("--force", action="store_true", help="ook schrijven als de klas les heeft of werkt")
    args = ap.parse_args()
    commands = {
        "draft": cmd_draft, "validate": cmd_validate, "backup": cmd_backup, "apply": cmd_apply,
        "what-if": cmd_what_if, "trace": cmd_trace, "replay-beliefs": cmd_replay_beliefs,
    }
    commands[args.cmd](args)


if __name__ == "__main__":
    main()
