# Evaluatie buiten de app

Rekent het puntvoorstel voor een klas op een mijlpaal uit `turn_history`, met
diagnostiek die de app niet toont, en schrijft na bespreking afgetekende
voorstellen naar `grade_proposals`. De leerling ziet het resultaat in
"Mijn rapporten" zonder dat de app verandert.

Waarom hier en niet in de app: de eerste rapportronde (2026-09-23) keerde
de klas om, en elke oorzaak — verouderde clients, gewiste hoogste niveaus,
incidentele signalen, de kalibratieband tegenover de beheersingsgrens —
werd pas zichtbaar door de ruwe oefeningen te herspelen. Die herspeling, plus
de klasobservaties van de leerkracht, is wat een faire beoordeling nodig
heeft. De app blijft het onderwijs sturen; het punt komt van hier.

## Contract

- **Het getal is deterministisch.** `rules.py` is de regel, met een
  versienummer dat op elk voorstel komt (`formulaVersion`). Een leerling kan
  het narekenen; de AI kiest het getal niet (PUNTENFORMULE §3.3).
- **Diagnostiek raakt het getal niet.** Ze informeert de leerkracht.
- **Een aanpassing is een beslissing van de leerkracht**, met een reden
  in `adjustmentNote`. Dat is het bestaande model van #99.
- **Niets wordt geschreven zonder bespreking.** `draft` en `validate`
  lezen alleen. `apply` maakt eerst een back-up, weigert als de klas nu
  werkt, weigert zonder verantwoording, en gebruikt `If-Match`.
- **Geen leerlingdata in de repo.** Concepten en back-ups staan buiten de
  repo (`~/ai-tutor-evaluaties`, `~/ai-tutor-backups`). De repo is publiek.

## Gebruik

```
python tooling/evaluation/evaluate.py draft    --klas 6WEWI            # concept + sidecar
python tooling/evaluation/evaluate.py validate --klas 6WEWI            # replay vs. opslag
python tooling/evaluation/evaluate.py backup   --klas 6WEWI            # volledige dump
python tooling/evaluation/evaluate.py apply    ~/ai-tutor-evaluaties/<...>.json
```

Alleen standaardbibliotheek; leest `COSMOS_ENDPOINT`/`COSMOS_KEY` uit `.env`.
De `az` CLI kan geen documenten lezen of schrijven, vandaar de REST-client.

De skill `/evalueer` (in `.claude/skills/evalueer/`) voert de stappen in
volgorde uit en schrijft de verantwoordingen in het concept.

## Bestanden

| | |
|---|---|
| `cosmos.py` | REST-client: query met continuation, read, upsert met etag |
| `rules.py` | de regel: replay van `turn_history`, stempel, hoogste niveau, M en P |
| `diagnostics.py` | tijdlijn, afwezigheid, bijna-lijst, profiel, fossielen, weggegooide signalen |
| `evaluate.py` | de vier commando's; rendert concept en sidecar |

## Regelversie `1.0.10-eval1`

PUNTENFORMULE v1.0.10 met drie afwijkingen (beslist 2026-09-23, zie #167,
#168, #169) en één kader:

1. **Asymmetrische moeilijkheidsfactor.** Fout op `hard` ×0,6, op `easy`
   ×1,4; juist ongewijzigd. μ wordt niveaubewust: 0,80 = ~63% op hard, 80%
   op medium, ~90% op easy. De kalibratieladder (die je tussen 40% en 75%
   parkeert) kan je zo niet meer uit je beheersing duwen.
2. **Eenrichtingsstempel.** Aangetoond = ooit aan de drie voorwaarden
   voldaan (μ ≥ 0,80, bewijs ≥ 4, positief op kalibratie). Latere daling
   telt niet voor het punt; ze stuurt de opfrisvragen.
3. **Incidentele negatieven zijn geen bewijs.** Een opmerking van de grader
   over een leerdoel uit een eerder subdoel, terwijl een ander antwoord
   beoordeeld werd, schrijft niets naar β. Positieven blijven (transfer).
4. **P = M.** M_start = 0 voor een eerste rapport over alles sinds de start
   van het jaar; dan is G = M/100 en valt het 60/40-mengsel samen tot M. De
   groeiterm zelf wordt herdacht.

Verder identiek aan de app: prior (1,1), plafond 20 met krimp-dan-optel,
decay bij elke schrijving (halveringstijd 60 d), vervolgvragen afgetopt op
zwak en gerekend als gemiddeld, incidentele signalen alleen binnen hetzelfde
doel en alleen naar een eerder subdoel, kern telt alleen met hoogste niveau ≥
verwacht niveau, `M = 50·k + 50·k·(0,6·u + 0,4·d)`.

## Wat de diagnostiek kan dat de app niet kan

- **per lesdag**: oefeningen, % juist, kalibratie, afgeronde subdoelen — een
  leerling die van 60% naar 84% ging, zie je hier en nergens anders;
- **afwezigheid**: dagen waarop de klas werkte en deze leerling niet;
- **bijna-lijst**: welke leerdoelen op 0,70–0,80 staan en hoeveel
  kernstempels nog nodig zijn om te slagen; doelen met te weinig vragen
  om ooit aangetoond te kunnen worden staan gemarkeerd — een laag punt
  door dun bevraagde extra doelen is iets anders dan een laag punt door
  gemiste kerndoelen;
- **profiel**: denktijd, deels-juist-aandeel, score per vraagtype en per
  soort leerdoel (`recall` / `predict` / `write` / `fix`) — "leest code
  maar schrijft ze niet" staat hier in cijfers;
- **fossielen**: leerdoelen die niet aangetoond zijn en al een week niet
  bevraagd, terwijl recent werk op zijn niveau goed is (niveaugewogen
  zoals μ onder #169: 63% juist op hard telt als 0,80) — de 30-dagenregel
  voor opfrisvragen is daar te traag voor;
- **weggegooide signalen**: oordelen van de grader over de leerdoelen van
  deze mijlpaal terwijl de leerling in een ander doel werkte; de app laat
  ze vallen. Let op: hun frequentie verschilt sterk per sessie (vraagtype?
  grader-versie?) — informatief, geen bewijs.

## Woorden

De leerkracht leest het concept, dus de app-woorden zijn daar vertaald.
Een turn uit `turn_history` is een **oefening**. Een directe vraag over
een leerdoel is een **vraag**. Het hoogste niveau waarop een leerdoel
juist beantwoord werd (`highestPositiveDifficulty`; PUNTENFORMULE §2.5
noemt dat "ratel", een vertaling van *ratchet* die niemand herkent) is
het **hoogste niveau**.

## Grenzen

- De replay leest `loSignals`. Transfer-krediet dat alleen als
  `appliedSignals` gelogd is, ontbreekt; `validate` toont hoe groot dat is.
- De regel vraagt geen vast aantal vragen per leerdoel: wie vroeg goed
  antwoordt, wordt niet meer bevraagd. De stempel is daar de eerlijkste
  maat voor, niet een perfecte. Zie de discussie bij #169.
- Eén persoon in de lus per rapport. Dat is de bedoeling, geen gebrek.
