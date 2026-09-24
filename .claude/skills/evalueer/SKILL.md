---
name: evalueer
description: Beoordeel een klas op een mijlpaal buiten de app — herspeel turn_history met de versioneerde regels (tooling/evaluation), maak een concept met diagnostiek, vraag de leerkracht om zijn klasobservaties en beslissingen, schrijf dan per leerling de rapporttekst (je-vorm, gewone taal, twee koppen), en schrijf pas na een expliciet "go" afgetekende voorstellen naar grade_proposals. Gebruik bij "/evalueer", "maak de rapporten voor 6WEWI", "beoordeel mijlpaal X", "evalueer de klas".
---

# /evalueer <klas> [mijlpaal]

Je werkt voor een leerkracht Python die de app zelf schrijft en volledige
toegang heeft tot de leerlingdata. Het punt wordt hier berekend, niet in de
app, omdat alleen hier de ruwe oefeningen, de diagnostiek en zijn eigen
klasobservaties samenkomen. Lees eerst `tooling/evaluation/README.md`: daar
staat het contract en de regelversie. Dit bestand zegt wat jij doet, in
welke volgorde, en wat je níet doet.

## Wat vaststaat

- **Het getal komt uit `rules.py`.** Jij berekent niets zelf en stelt het
  getal niet in vraag. Wil de leerkracht een ander getal, dan is dat een
  *aanpassing* met een *reden*, en die schrijf je zo weg.
- **Twee stops.** Je schrijft de rapporttekst pas ná de observaties van de
  leerkracht, en je schrijft niets naar Cosmos vóór een expliciet "go" in
  dit gesprek.
- **De leerling en de ouders lezen mee.** `justification` en
  `adjustmentNote` staan letterlijk op het rapport in de app. Alles wat
  daarin komt is in je-vorm en in gewone taal. Wat de leerkracht moet
  weten in vaktaal, blijft in het concept.
- **Geen leerlingdata in de repo.** Concept en sidecar staan in
  `~/ai-tutor-evaluaties`, back-ups in `~/ai-tutor-backups`. Niets daarvan
  wordt gecommit.
- **Niet tijdens een les.** `apply` weigert als leerlingen de laatste
  minuten actief waren; probeer dat niet te omzeilen.
- **Woorden, ook in het gesprek met de leerkracht.** Een turn uit
  `turn_history` is een *oefening*, nooit een beurt. Een directe vraag
  over een leerdoel is een *vraag*, niet een meting. Het hoogste niveau
  waarop een leerdoel juist beantwoord werd, is het *hoogste niveau*,
  nooit "ratel" (dat woord in PUNTENFORMULE §2.5 is een verkeerde
  vertaling van *ratchet* en zegt de leerkracht niets).

## Stappen

### 1. Concept maken

```
python tooling/evaluation/evaluate.py draft --klas <klas> [--mijlpaal <id|deel van titel>]
```

Bij meerdere mijlpalen vraagt het script om `--mijlpaal`; kies dan met de
leerkracht. Het script print het overzicht en de paden van het concept
(`.md`) en de sidecar (`.json`). Lees het concept volledig.

De kop noemt het *verwachte niveau* van de mijlpaal: vanaf welk hoogste
niveau een aangetoond kerndoel als kern telt (in de sidecar
`expectedDifficulty`). Onder *Bijna* staan per leerdoel de *herkomst* van
μ (hoeveel vragen en hoeveel daarvan juist, en wat van elders kwam:
vervolgvragen, incidentele signalen, transfer-krediet), het *hoogste
niveau* en de *laatste vragen*; onder *Ver* de herkomst. Hoe je ze leest,
staat in de kop van het concept en in de README (*Wat de diagnostiek
kan*).

Draai ook `validate --klas <klas>` en meld kort of de replay de opslag
reproduceert. Een afwijking wijst op een client op een oude build (kolom
*laatste build* `oud`) of op documenten die met een oudere herspeling
herschreven zijn; de README (*validate*) zegt hoe je dat leest. Het raakt
het concept niet, maar de leerkracht wil het weten.

### 2. Voor de leerkracht — en stop

Per leerling met data schrijf je in het concept onder *Voor de leerkracht
(concept)* twee tot vier zinnen. Vaktaal mag hier; het blijft in het
concept en gaat nergens heen. Wat erin hoort: wat de leerkracht moet weten
om te beslissen — welke doelen bijna gehaald zijn en hoe dicht, een
fossiel (lang niet meer bevraagd terwijl recent werk op zijn niveau goed
is), een afwezigheid, een profiel dat op iets specifieks wijst, doelen
die *te weinig bevraagd* zijn om aangetoond te kunnen worden (het concept
markeert ze; een laag punt door drie extra doelen met elk twee vragen is
iets anders dan een laag punt door zes gemiste kerndoelen).

Geef de leerkracht dan in het gesprek:

- het overzicht (naam, kern, extra, moeilijk, punt, wat nog nodig is om te
  slagen), gesorteerd op punt;
- per leerling je tekst *Voor de leerkracht*;
- de paden van concept en sidecar.

Vraag per leerling om zijn **klasobservatie** en zijn **beslissing**:
*aftekenen*, *uitstellen* (bv. ziek geweest, mag inhalen — niet aftekenen,
later opnieuw) of *overslaan*, en bij een aanpassing van het punt het getal
en de reden. Noteer alles in het concept.

Zegt hij welke doelen alsnog meetellen, dan komt het getal uit `what-if`,
nooit uit eigen rekenwerk. Het rekent met `rules.py`, met die doelen als
aangetoond en hun hoogste niveau op minstens het verwachte:

```
python tooling/evaluation/evaluate.py what-if --klas <klas> --leerling <naam> --tel <lo_id>[,<lo_id>...]
```

**Stop hier** tot je die antwoorden hebt. De rapporttekst schrijf je met de
observaties erbij, niet ervoor.

### 3. Tekst voor het rapport — en stop

Per leerling die afgetekend wordt, schrijf je de tekst die de leerling en
de ouders te lezen krijgen. Zet ze in het concept onder *Tekst voor het
rapport (concept)* én in de sidecar in het veld `justification` van die
leerling — identiek. De sidecar is wat geschreven wordt.

**Vorm.** Platte tekst: de app rendert geen markdown. Geen sterretjes,
geen `#`, geen opsommingstekens. Twee koppen, elk op een eigen regel,
gevolgd door een lege regel:

```
Verantwoording van je score

<3 à 5 zinnen>

Feedback

<4 à 8 zinnen>
```

Het geheel hoogstens zo'n 200 woorden. Je-vorm, altijd: "je hebt", "je
toonde", nooit "Arjen heeft". Aanspreken zonder aanhef.

**Verantwoording van je score.** Waar het punt uit bestaat, in woorden en
met hooguit een paar hele getallen: hoeveel van de kerndoelen je hebt
aangetoond en hoeveel van de extra doelen; of je dat deed met makkelijke,
gewone of moeilijke oefeningen; wanneer je de onderdelen afrondde ("op 15
september had je alle onderdelen af"; "de eerste onderdelen had je begin
september, het laatste op de 22e"). Benoem wat nog ontbreekt met de eigen
zin van het leerdoel uit het concept ("Je kan invoer omzetten naar een
getal wanneer …"), kort herformuleerd als hij te lang is; hoogstens drie.
Het punt zelf noem je niet — dat staat erboven.

**Feedback.** Wat goed ging, concreet, één of twee dingen. Of er een lijn
zit in wat fout gaat, in gewone woorden en alleen als ze duidelijk is
("voorspellen wat een stukje code doet lukt je minder goed dan zelf code
schrijven"; "bij het uitleggen van code haak je af"). Groei, en dat is hier
níet een scorepercentage — dat daalt vaak juist terwijl iemand vooruitgaat,
omdat de latere onderdelen moeilijker zijn en de oefeningen meegroeien.
Groei is wat je wanneer aantoonde en op welk niveau: "begin september
werkte je met gewone oefeningen, vanaf de tweede week met moeilijke", "de
eerste onderdelen had je na twee lessen af, het laatste op de 15e". Het
concept geeft de afronddata en het niveau per leerling. Dan wat je kan
doen voor een betere score de volgende keer: één tot drie concrete
dingen, gekoppeld aan de doelen die het dichtst bij zijn, plus één
gewoonte als het profiel daar aanleiding toe geeft ("neem iets meer tijd
per oefening"; "lees de opgave twee keer"). Eindig met waar je nu zit in
de cursus. Positief, eerlijk, zonder verwijt: "je antwoordt snel" wordt
"neem wat meer tijd".

**De app kiest waarover de leerling vragen krijgt, de leerling niet.**
Schrijf dus nooit "maak meer oefeningen over X" of "oefen op X", en
verklaar een ontbrekend doel nooit met "daar maakte je te weinig
oefeningen over"; dat wordt "daarover kreeg je nog weinig vragen". Advies
is een aanpak voor wanneer die vragen terugkomen: "de app komt erop
terug; reken het dan eerst op papier uit", "loop het script regel voor
regel na", "denk eraan dat input altijd tekst geeft". Tempo en aandacht
mogen wel ("maak meer oefeningen per les", "neem meer tijd"): dat kiest de
leerling zelf.

**Woorden die niet in de rapporttekst mogen** — begrippen uit de app die
ouders niet kennen, of getallen die niemand kan plaatsen: mijlpaal (zeg:
dit rapport, dit onderdeel van de cursus), beurt of beurten (zeg:
oefeningen), signaal, kalibratie, niveau van de tutor, hoogste niveau
van een doel, stempel, bewijs, meting of "na acht metingen",
overtuiging, μ of een waarde als
0,74, k / u / d / M, percentages per vraagtype, de Engelse soorten recall /
predict / write / fix / explain / reason en vraagtypes als mc /
completeCode, en elke vergelijking met wat de app wel of niet meetelde
("tien positieve signalen die de app wegliet").

**Wat wel mag:** kerndoelen en extra doelen; oefeningen; makkelijke,
gewone en moeilijke oefeningen; aangetoond; data; "16 van de 19"; het
niveau waarop je begon en eindigde; de eigen zin van een leerdoel; de
namen van de onderdelen van de cursus ("variabelen", "invoer met input").

Dezelfde regels gelden voor de **reden van een aanpassing**
(`adjustmentNote`): die staat ook op het rapport, in je-vorm ("Je legde
in de klas uit hoe … werkt; daarom telt dat doel mee").

Toon de leerkracht alle rapportteksten in het gesprek. **Stop.** Pas zijn
opmerkingen toe in concept én sidecar; zet `justificationSource` op
`"edited"` als hij de tekst zelf herschreef, `skip: true` met `skipReason`
bij uitstellen of overslaan, `adjustedGrade` en `adjustmentNote` bij een
aanpassing. Schrijf niets tot hij "go" zegt.

### 4. Schrijven

```
python tooling/evaluation/evaluate.py apply ~/ai-tutor-evaluaties/<bestand>.json
```

Het script maakt eerst een back-up van de bestaande voorstellen, weigert
als de klas werkt of als een rapporttekst ontbreekt, waarschuwt als een
tekst een van de twee koppen mist, slaat al afgetekende voorstellen over,
en meldt per leerling wat er geschreven is. Een `CONFLICT` betekent dat
het doc intussen veranderde: meld het, schrijf niet opnieuw zonder overleg.

Vrijgeven naar de leerlingen gebeurt daarna in de app: Rapporten →
Vrijgeven. Dat kopieert alleen afgetekende voorstellen. Zeg dat.

### 5. Terugkoppelen

Vat samen wat geschreven is, wat uitgesteld, en wat opviel dat de regel,
de diagnostiek of deze skill zou moeten veranderen. De leerkracht bespreekt
dat in een ander gesprek; wat jij hier leert, hoort in die samenvatting.

## Als iets niet klopt

- `geen .env gevonden`: je zit niet in de repo-root, of `.env` ontbreekt.
- `meerdere mijlpalen`: geef `--mijlpaal`.
- Een leerling met *geen data*: staat op `skip`; niet beoordelen, wel
  melden.
- Het concept toont bij een leerling veel *weggegooide positieven*: dat is
  informatie voor de leerkracht ("ze kan het intussen"), geen reden om het
  getal te veranderen — hoogstens om hem een aanpassing voor te stellen,
  mét reden. In de rapporttekst komt het niet.
- De regel zelf ter discussie? Niet hier aanpassen. Dat is een wijziging
  aan `rules.py` met een nieuwe `RULES_VERSION`, in een apart gesprek.
