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
- **Diagnostiek raakt het getal niet.** Ze informeert de leerkracht. Een
  wijziging die alleen de diagnostiek raakt, krijgt dus geen nieuwe
  regelversie.
- **Een aanpassing is een beslissing van de leerkracht**, met een reden
  in `adjustmentNote`. Dat is het bestaande model van #99.
- **Niets wordt geschreven zonder bespreking.** `draft`, `validate` en
  `what-if` lezen alleen. `apply` maakt eerst een back-up, weigert als
  de klas nu werkt, weigert zonder verantwoording, en gebruikt `If-Match`.
- **Geen leerlingdata in de repo.** Concepten en back-ups staan buiten de
  repo (`~/ai-tutor-evaluaties`, `~/ai-tutor-backups`). De repo is publiek:
  ook een issue, PR of commit noemt geen echte leerling (#190).

## Gebruik

```
python tooling/evaluation/evaluate.py draft    --klas 6WEWI            # concept + sidecar
python tooling/evaluation/evaluate.py validate --klas 6WEWI            # replay vs. opslag
python tooling/evaluation/evaluate.py backup   --klas 6WEWI            # volledige dump
python tooling/evaluation/evaluate.py apply    ~/ai-tutor-evaluaties/<...>.json
python tooling/evaluation/evaluate.py what-if  --klas 6WEWI --leerling <naam> --tel lo_a,lo_b   # punt als die doelen meetellen
```

Alleen standaardbibliotheek; leest `COSMOS_ENDPOINT`/`COSMOS_KEY` uit `.env`.
De `az` CLI kan geen documenten lezen of schrijven, vandaar de REST-client.

De skill `/evalueer` (in `.claude/skills/evalueer/`) voert de stappen in
volgorde uit: concept en `validate`, de observaties en beslissingen van de
leerkracht, een vaste consistentiestap die zijn maat over de hele klas
naloopt (met `what-if`, hieronder), de rapportteksten op de aangepaste
tellingen, en pas na een "go" `apply`.

## Bestanden

| | |
|---|---|
| `cosmos.py` | REST-client: query met continuation, read, upsert met etag |
| `rules.py` | de regel: replay van `turn_history`, stempel, hoogste niveau, M en P; de signalen die mee op het voorstel gaan; het punt met doelen meegeteld (`score_counting`) |
| `diagnostics.py` | tijdlijn, afwezigheid, bijna-lijst met herkomst en laatste vragen, profiel, fossielen, weggegooide signalen |
| `evaluate.py` | de vijf commando's; rendert concept en sidecar |
| `tests/` | de commando's tegen een nep-Cosmos met verzonnen leerlingen: `python -m unittest discover -s tooling/evaluation/tests` |

## Mee op het voorstel

Naast het getal zet `apply` de betrouwbaarheidssignalen van PUNTENFORMULE
§3.2 op het voorstel, zoals de app ze telt; `draft` rekent ze uit en toont
ze in concept en sidecar, dus de leerkracht ziet ze voor het "go":

- **verouderd** (`staleLoCount`): leerdoelen van de mijlpaal waarop de
  herspeling langer dan 30 dagen vóór het concept niets meer schreef, plus
  de nooit bevraagde. Zoals in de app telt elke schrijving, ook een
  neutraal signaal: dat verzet de klok zonder bewijs toe te voegen (#202).
  Dezelfde drempel als de app (`PolicyConstants.warmUpStaleAfter`), een
  andere vraag dan de fossielen;
- **nooit bevraagd** (`neverProbedCount`): leerdoelen zonder document in de
  app. Een neutraal signaal maakt er een, op de prior;
- **oefeningen deze periode** (`supervisedTurns`, `homeTurns`): de
  beoordeelde oefeningen sinds `periodStart` van de mijlpaal, per
  `provenance`; zonder veld telt een oefening als thuis, zoals in de app.

Bij een sidecar van vóór deze tellingen laat `apply` `staleLoCount`,
`supervisedTurns` en `homeTurns` weg in plaats van ze op 0 te zetten: een
ontbrekend veld is eerlijker dan een verzonnen nul.

## Regelversie `1.0.18-eval4`

PUNTENFORMULE v1.0.18, herspeeld uit `turn_history`. `eval4`
(2026-09-24, #202) herspeelt een **neutraal signaal** zoals de app het
schrijft (CONDUCTOR_POLICY §3.1). Het weegt niets, maar het is wel een
schrijving: μ en het bewijs vervallen tot dat moment, de klok verspringt,
en een leerdoel zonder document krijgt er een op de prior. Een
rechtstreeks neutraal signaal verzet ook de klok van de controlevraag
(`lastProbedAt`) en wist de markering voor een opfrisvraag
(`regressedAt`), welke kant het antwoord ook uitging. `eval3` sloeg
neutrale signalen over. Het gaf dan een te vroege klok als de laatste
schrijving neutraal was. Een leerdoel dat alleen neutrale signalen
kreeg, stond als nooit bevraagd en verouderd, terwijl de app er een
document voor heeft. M en P veranderen niet: een neutraal signaal weegt
niets, en verval na verval is exact hetzelfde verval. Wel kunnen
*verouderd* en *nooit bevraagd* op het voorstel veranderen, en in de
diagnostiek het aantal vragen en de datum van de laatste vraag. Een
getrouwheidscorrectie, geen regelwijziging.

v1.0.17 en v1.0.18
(#187, #188) veranderen niets aan M of P; ze voegen de **controlevraag**
toe: een rechtstreekse vraag over een leerdoel van een eerder subdoel,
midden in het werk aan een ander. `eval3` (2026-09-24, #195) leest die
oefeningen, en de **opfrisvragen** die op dezelfde manier werken, zoals de
app ze verwerkt (`rules.turn_scope`): de vraag telt rechtstreeks voor haar
eigen leerdoel, en elk ander signaal van die oefening telt tegenover het
subdoel waar de leerling mee bezig was (`activeSubgoalId`). `eval2` nam
het oude subdoel (`subgoalId`) voor het actieve: een ander leerdoel van
dat oude subdoel telde als rechtstreekse vraag (op het gevraagde niveau,
met hoogste niveau en stempel), en een leerdoel van het subdoel dat echt
actief was, viel weg als verwijzing vooruit. Ook de diagnostiek leest zo
(*weggegooide signalen*, *onderdelen afgerond*). Een
getrouwheidscorrectie, geen regelwijziging.

`eval2` (2026-09-23) veranderde evenmin iets aan de formule: de
herspeling past sindsdien ook het transfer-krediet toe dat de app logde
(`transferCredits`, CONDUCTOR_POLICY
§3.7) en dat `eval1` oversloeg — een getrouwheidscorrectie op de
herspeling, geen regelwijziging. Voor het overige rekent ze exact wat
`1.0.10-eval1` rekende: dat was v1.0.10 met drie afwijkingen (beslist
2026-09-23, zie #167, #168, #169) en één kader, en de formule heeft ze
intussen alle vier overgenomen (v1.0.12–v1.0.14 en v1.0.16):

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
4. **P = M.** Het punt is de beheersingsscore op de stempels. In
   `1.0.10-eval1` was dat een kader (M_start = 0 voor een eerste rapport,
   dus G = M/100 en het 60/40-mengsel viel samen tot M); sinds v1.0.16
   (#191) is het de regel: de groeiterm G en M_start zijn uit de formule,
   in de app net zo.

Verder identiek aan de app: prior (1,1), plafond 20 met krimp-dan-optel,
decay bij elke schrijving (halveringstijd 60 d), vervolgvragen afgetopt op
zwak en gerekend als gemiddeld, incidentele signalen alleen binnen hetzelfde
doel en alleen naar een eerder subdoel, transfer-krediet zoals gelogd (een
zwak positief op gemiddeld), opfris- en controlevragen als rechtstreekse
meting van hun leerdoel (sinds `eval3`), een neutraal signaal als
schrijving zonder gewicht (sinds `eval4`), kern telt alleen met hoogste
niveau ≥ verwacht niveau, `M = 50·k + 50·k·(0,6·u + 0,4·d)`.

## Wat de diagnostiek kan dat de app niet kan

- **per lesdag**: oefeningen, % juist, kalibratie, afgeronde subdoelen — een
  leerling die van 60% naar 84% ging, zie je hier en nergens anders;
- **afwezigheid**: dagen waarop de klas werkte en deze leerling niet;
- **verwacht niveau** (#189): in de kop van het concept en als
  `expectedDifficulty` in de sidecar, met wat het betekent: een aangetoond
  kerndoel telt pas als kern vanaf dat hoogste niveau;
- **bijna-lijst**: welke leerdoelen op 0,70–0,80 staan en hoeveel
  kernstempels nog nodig zijn om te slagen; doelen met te weinig vragen
  om ooit aangetoond te kunnen worden staan gemarkeerd — een laag punt
  door dun bevraagde extra doelen is iets anders dan een laag punt door
  gemiste kerndoelen. Per leerdoel drie regels (#189):
  - *herkomst*: waar μ vandaan komt — de vragen en hoeveel daarvan
    juist, vervolgvragen, incidentele signalen (na de filter van de app:
    hetzelfde doel, een eerder subdoel; een incidentele fout weegt niet,
    #167) en transfer-krediet, geteld door de herspeling zelf. "μ 0,93,
    2 vragen" las op 23-09 als twee juiste antwoorden; het waren twee
    foute en 27 incidentele juiste (#188). Alleen een vraag geeft een
    hoogste niveau en kan een leerdoel aangetoond maken;
  - *hoogste niveau*, of "nog geen rechtstreeks juist antwoord";
  - *laatste vragen*: de laatste vijf uit `direct_signals`, per dag:
    ✓ juist, ✗ fout, ○ neutraal, met het niveau (e/m/h), `c` voor een
    controlevraag, `o` voor een opfrisvraag en `s` als de sleutel van de
    vragenbank besliste (`gradedByKey`). Staan er aan het eind meer
    juiste op rij dan er getoond worden, dan staat dat erbij ("de laatste
    8 juist").

  De ver-lijst toont de herkomst op één regel;
- **profiel**: denktijd, deels-juist-aandeel, score per vraagtype en per
  soort leerdoel (`recall` / `predict` / `write` / `fix`) — "leest code
  maar schrijft ze niet" staat hier in cijfers;
- **fossielen**: leerdoelen die niet aangetoond zijn en al een week niet
  bevraagd, terwijl recent werk op zijn niveau goed is (niveaugewogen
  zoals μ onder #169: 63% juist op hard telt als 0,80) — de 30-dagenregel
  voor opfrisvragen is daar te traag voor. Sinds PUNTENFORMULE v1.0.17
  (#187) stelt de app zelf een controlevraag over zo'n leerdoel wanneer μ
  op 0,70–0,80 staat (CONDUCTOR_POLICY §2.6), en sinds v1.0.18 (#188)
  ook wanneer μ boven 0,80 staat zonder rechtstreeks juist antwoord op
  niveau (of zonder ratel); een fossiel dat hier nog opduikt, lag
  daarbuiten of kreeg die vraag nog niet;
- **weggegooide signalen**: oordelen van de grader over de leerdoelen van
  deze mijlpaal terwijl de leerling in een ander doel werkte; de app laat
  ze vallen. Let op: hun frequentie verschilt sterk per sessie (vraagtype?
  grader-versie?) — informatief, geen bewijs.

## `what-if`: wat een aanpassing oplevert

Telt de leerkracht een doel mee dat de regel niet telt, dan geeft
`what-if` het getal: `rules.score` op dezelfde herspeling als `draft`,
met de genoemde leerdoelen als aangetoond geteld en hun hoogste niveau
opgetrokken tot het verwachte als het lager of leeg is
(`rules.score_counting`, #189). Zo komt ook het getal van een aanpassing
uit `rules.py`, en forceert niemand zelf een toestand.

```
python tooling/evaluation/evaluate.py what-if --klas 6WEWI --leerling <naam> --tel write_simple_script,sg-id/lo_id
```

`--leerling` is de volledige naam, een deel ervan of de uid; `--tel` een
of meer leerdoelen van de mijlpaal, als `lo_id` of `subdoel/lo_id`. Het
commando toont kern, uitbreiding, moeilijk, M en punt, nu en met die
doelen meegeteld, en per doel de herkomst en wat er geteld werd. Het
leest alleen; de aanpassing zelf gaat, met haar reden, als
`adjustedGrade` en `adjustmentNote` in de sidecar.

De skill gebruikt het ook na de beslissingen van de leerkracht (#190):
voldoet een doel bij een andere leerling aan dezelfde maat (μ, hoogste
niveau, aantal vragen, laatste vragen, signalen van elders), dan noemt ze
het met het punt van `what-if`. Geef in `--tel` alle doelen die bij die
leerling meetellen samen; het punt is geen som van losse doelen. De rij
*meegeteld* is ook wat de verantwoording noemt ("18 van de 19"): de
leerling ziet `adjustedGrade` met de verantwoording en de reden. Het
voorstel zelf houdt de tellingen van de regel (`computed` in de sidecar),
en die toont het rapport dichtgeklapt onder *Hoe dit punt berekend is*;
de reden zegt welke doelen meetellen en waarom.

## Woorden

De leerkracht leest het concept, dus de app-woorden zijn daar vertaald.
Een turn uit `turn_history` is een **oefening**, behalve een
**auditrecord**: wat de app schrijft bij lege leerdoelen of een
doorverwijzing na een verwijderd subdoel (CONDUCTOR_POLICY §8.1). Er werd
geen vraag gesteld (`questionType` is leeg), en zijn `wrong` en `medium`
zijn opvulling. De app telt het nergens mee, en het concept laat het
overal weg (`rules.is_audit`, #201): niet in de tijdlijn, het profiel of
de fossielen, niet als lesdag of aanwezigheid, niet als niveau, niet in
de tellingen op het voorstel. Een directe vraag over
een leerdoel is een **vraag**. Het hoogste niveau waarop een leerdoel
juist beantwoord werd (`highestPositiveDifficulty`; PUNTENFORMULE §2.5
noemt dat "ratel", een vertaling van *ratchet* die niemand herkent) is
het **hoogste niveau**.

## `lastProbedAt` aanvullen na de release

Sinds #187 bewaart de app per leerdoel `lastProbedAt`: de laatste
rechtstreekse vraag, de klok van de controlevraag. Een ouder document
heeft dat veld niet. De app leest dan `lastUpdatedAt` wanneer het
leerdoel ooit zelf bevraagd werd, dus komt een controlevraag hoogstens
te laat, nooit te vroeg. `LoState.last_direct_at` is dezelfde klok,
herspeeld uit `turn_history`.

Het aanvullen hoort bij de eenmalige herspeling van `lo_beliefs` na de
release, die de gebruiker zelf draait (#195). `evaluate.py` krijgt er geen
commando voor: deze tooling schrijft alleen naar `grade_proposals`, en
alleen na een "go". Voor die herspeling geldt:

- herspeel met `eval4` of later. `eval2` gaf de andere leerdoelen van
  het subdoel van een opfris- of controlevraag een te late klok, en een
  leerdoel van het actieve subdoel een te vroege of geen klok. `eval3`
  sloeg neutrale signalen over, die de app wel als rechtstreekse vraag
  telt (#202). Was de laatste rechtstreekse vraag neutraal, dan gaf het
  een te vroege klok: hoogstens één controlevraag te vroeg. Een leerdoel
  met alleen neutrale rechtstreekse vragen kreeg geen klok;
- schrijf het veld alleen op documenten die het nog niet hebben. Wat de
  app zelf schreef, gaat voor;
- laat het weg als `last_direct_at` leeg is. Dan werd het leerdoel nooit
  rechtstreeks bevraagd, en zo leest de app het al;
- zoals bij de vorige herspeling: eerst `backup`, dan `If-Match`, en
  buiten de lesuren.

## `validate`: de herspeling tegenover de opslag

`validate` herspeelt elke leerling met dezelfde `rules.replay` als
`draft`, en telt per leerling de documenten in `lo_beliefs` waarvan μ
meer dan 0,01 afwijkt of het hoogste niveau anders is. Tot #203
herspeelde het met de rekenregels van vóór #167 en #169 (symmetrische
factor, incidentele negatieven als bewijs). Dan telde elk document met
een fout op `easy` of `hard`, of met een incidenteel negatief, als
afwijking, ook bij een leerling op de huidige build. Tot `eval4` (#202)
sloeg de herspeling neutrale signalen over. Een document dat de app het
laatst op een neutraal signaal schreef, week dan af: de app liet μ tot
dat moment vervallen, de herspeling niet. En een document dat alleen
neutrale signalen kreeg, werd niet vergeleken.

De kolom **laatste build** is de `clientVersion` op de laatste oefening
(#165). Elke build die dat veld schrijft (vanaf 2.6.0) rekent met #167 en
#169. `oud` is een build zonder dat veld, die nog met de oude regels
rekent; `geen` betekent geen oefeningen.

**Waarom niet elke oefening met de regels van haar eigen build.** De
eenmalige herschrijving van `lo_beliefs` op 2026-09-23 rekende de
documenten van elke leerling op een client sinds #108 opnieuw uit, uit de
hele log en met de regels van #167 en #169. Wat er nog van de oude regels
in de opslag staat, schreef een oude build daarna, of het staat op een
document dat de herschrijving oversloeg. Dat moet `validate` tonen. Wie
de oefeningen zonder `clientVersion` met de oude regels herspeelt, ziet
elk herschreven document als afwijking.

Een afwijking betekent dus:

- een oude build schreef het document na de herschrijving (laatste build
  `oud`), of een client van vóór #108, die nog niet herschreven is
  (Grenzen);
- het document werd met een oudere herspeling herschreven. De
  herschrijving van 2026-09-23 gebruikte `eval2`, dat een opfrisvraag
  anders las dan `eval3` (#195) en neutrale signalen oversloeg (#202).
  Zulke documenten kunnen afwijken tot de herspeling na de release, met
  `eval4` of later (hierboven);
- iets wat de log niet draagt: een signaal meer of minder dan gelogd.

## Grenzen

- De replay leest `loSignals` en `transferCredits` (sinds `eval2`; `eval1`
  sloeg het transfer-krediet over en las elk doc dat er kreeg te laag).
  Wat buiten haar bereik blijft, zijn oefeningen van clients van vóór #108,
  die een andere set signalen toepasten dan de conductor nu; `validate`
  toont hoe groot dat is.
- Een opfrisvraag van een build van vóór #187 heeft geen
  `activeSubgoalId`. De herspeling leidt het actieve subdoel dan af uit
  `loStatusAfter`, waar de app de leerdoelen van het actieve subdoel
  opsomt: het is het enige andere subdoel van hetzelfde doel dat ze
  allemaal bevat. Lukt dat niet (geen status, of het doel is sindsdien
  aangepast), dan geldt het bevraagde subdoel als actief, zoals in
  `eval2`. Controlevragen hebben het veld altijd.
- De regel vraagt geen vast aantal vragen per leerdoel: wie vroeg goed
  antwoordt, wordt niet meer bevraagd. De stempel is daar de eerlijkste
  maat voor, niet een perfecte. Zie de discussie bij #169.
- Eén persoon in de lus per rapport. Dat is de bedoeling, geen gebrek.
