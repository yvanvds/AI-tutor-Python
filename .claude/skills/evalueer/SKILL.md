---
name: evalueer
description: Beoordeel een klas op een mijlpaal buiten de app — herspeel turn_history met de versioneerde regels (tooling/evaluation), maak een concept met diagnostiek en verantwoording per leerling, bespreek het met de leerkracht, en schrijf pas na een expliciet "go" afgetekende voorstellen naar grade_proposals. Gebruik bij "/evalueer", "maak de rapporten voor 6WEWI", "beoordeel mijlpaal X", "evalueer de klas".
---

# /evalueer <klas> [mijlpaal]

Je werkt voor een leerkracht Python die de app zelf schrijft en volledige
toegang heeft tot de leerlingdata. Het punt wordt hier berekend, niet in de
app, omdat alleen hier de ruwe beurten, de diagnostiek en zijn eigen
klasobservaties samenkomen. Lees eerst `tooling/evaluation/README.md`: daar
staat het contract en de regelversie. Dit bestand zegt wat jij doet, in
welke volgorde, en wat je níet doet.

## Wat vaststaat

- **Het getal komt uit `rules.py`.** Jij berekent niets zelf en stelt het
  getal niet in vraag. Wil de leerkracht een ander getal, dan is dat een
  *aanpassing* met een *reden*, en die schrijf je zo weg.
- **Je schrijft niets naar Cosmos vóór een expliciet "go"** van de
  leerkracht in dit gesprek, nadat hij het concept gezien heeft.
- **Geen leerlingdata in de repo.** Concept en sidecar staan in
  `~/ai-tutor-evaluaties`, back-ups in `~/ai-tutor-backups`. Niets daarvan
  wordt gecommit.
- **Niet tijdens een les.** `apply` weigert als leerlingen de laatste
  minuten actief waren; probeer dat niet te omzeilen.

## Stappen

### 1. Concept maken

```
python tooling/evaluation/evaluate.py draft --klas <klas> [--mijlpaal <id|deel van titel>]
```

Bij meerdere mijlpalen vraagt het script om `--mijlpaal`; kies dan met de
leerkracht. Het script print het overzicht en de paden van het concept
(`.md`) en de sidecar (`.json`). Lees het concept volledig.

Draai ook `validate --klas <klas>` en meld kort of de replay de opslag
reproduceert. Grote afwijkingen bij één leerling wijzen meestal op een
client op een oude build; dat raakt het concept niet, maar de leerkracht
wil het weten.

### 2. Verantwoording schrijven

Per leerling met data schrijf je in het concept, onder *Verantwoording
(concept)*, twee tot vier korte alinea's. Regels, dezelfde als de prompt in
de app (`grade_justification.dart`):

- aan de leerkracht, over de leerling in de derde persoon bij voornaam, in
  het Nederlands, gewone lopende tekst zonder koppen of opsommingen;
- **het getal staat vast**: je verklaart uit de diagnostiek *waarom de
  metingen zijn wat ze zijn*, je oordeelt niet of het hoger of lager zou
  moeten;
- gegrond in wat er staat: de tijdlijn, de bijna-lijst, het profiel,
  afwezigheid, fossielen. Verzin geen gebeurtenissen;
- benoem wat de leerkracht moet weten om te beslissen: een leerling die
  bijna slaagt en waar precies; een fossiel; een afwezigheid; een profiel
  dat op iets specifieks wijst (leest wel, schrijft niet; kiest goed,
  produceert slecht); veel weggegooide positieven;
- de kalibratie is context, geen argument. Het aantal vragen is geen
  argument: de tutor stopt met vragen zodra beheersing vaststaat.

Zet dezelfde tekst in de sidecar, veld `justification` van die leerling.
De sidecar is wat `apply` schrijft; het concept is voor mensen. Houd ze
gelijk.

### 3. Bespreken — en stoppen

Geef de leerkracht in het gesprek:

- het overzicht (naam, kern, uitbreiding, moeilijk, punt, wat nog nodig
  is om te slagen), gesorteerd op punt;
- per leerling onder de 50: één zin over wat de diagnostiek zegt;
- elke leerling met een signaal: afwezig, fossiel, geen data;
- de paden van concept en sidecar.

Vraag dan om zijn observaties en beslissingen per leerling: *aftekenen*,
*uitstellen* (bv. ziek geweest, mag inhalen — niet aftekenen, later
opnieuw), of *overslaan*. Voor een aanpassing van het punt vraag je het
getal en de reden. Werk het concept en de sidecar bij:

- `adjustedGrade` en `adjustmentNote` bij een aanpassing;
- `skip: true` met `skipReason` bij uitstellen of overslaan;
- `justificationSource: "edited"` als de leerkracht de verantwoording zelf
  herschreef.

**Stop hier.** Schrijf niets tot de leerkracht "go" zegt.

### 4. Schrijven

```
python tooling/evaluation/evaluate.py apply ~/ai-tutor-evaluaties/<bestand>.json
```

Het script maakt eerst een back-up van de bestaande voorstellen, weigert
als de klas werkt of als een verantwoording ontbreekt, slaat al afgetekende
voorstellen over, en meldt per leerling wat er geschreven is. Een
`CONFLICT` betekent dat het doc intussen veranderde: meld het, schrijf niet
opnieuw zonder overleg.

Vrijgeven naar de leerlingen gebeurt daarna in de app: Rapporten →
Vrijgeven. Dat kopieert alleen afgetekende voorstellen. Zeg dat.

### 5. Terugkoppelen

Vat samen wat geschreven is, wat uitgesteld, en wat opviel dat de regel of
de diagnostiek zou moeten veranderen. De leerkracht bespreekt de skill in
een ander gesprek; wat jij hier leert, hoort in die samenvatting.

## Als iets niet klopt

- `geen .env gevonden`: je zit niet in de repo-root, of `.env` ontbreekt.
- `meerdere mijlpalen`: geef `--mijlpaal`.
- Een leerling met *geen data*: staat op `skip`; niet beoordelen, wel
  melden.
- Het concept toont een leerling met veel *weggegooide positieven*: dat is
  informatie voor de leerkracht ("ze kan het intussen"), geen reden om het
  getal te veranderen — hoogstens om een aanpassing voor te stellen, mét
  reden.
- De regel zelf ter discussie? Niet hier aanpassen. Dat is een wijziging
  aan `rules.py` met een nieuwe `RULES_VERSION`, in een apart gesprek.
