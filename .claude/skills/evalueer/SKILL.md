---
name: evalueer
description: Beoordeel een klas op een mijlpaal buiten de app — herspeel turn_history met de versioneerde regels (tooling/evaluation), maak een concept met diagnostiek, vraag de leerkracht om zijn klasobservaties en beslissingen, loop die beslissingen na over de hele klas (dezelfde maat voor iedereen), schrijf dan per leerling de rapporttekst (je-vorm, gewone taal, twee koppen, op de aangepaste tellingen), en schrijf pas na een expliciet "go" afgetekende voorstellen naar grade_proposals. Gebruik bij "/evalueer", "maak de rapporten voor 6WEWI", "beoordeel mijlpaal X", "evalueer de klas".
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
- **Stops.** Je loopt de beslissingen van de leerkracht pas na als hij ze
  gaf (stap 3), je schrijft de rapporttekst pas als hij de uitkomst
  daarvan zag, en je schrijft niets naar Cosmos vóór een expliciet "go" in
  dit gesprek.
- **De leerling en de ouders lezen mee.** `justification` en
  `adjustmentNote` staan letterlijk op het rapport in de app. Alles wat
  daarin komt is in je-vorm en in gewone taal. Wat de leerkracht moet
  weten in vaktaal, blijft in het concept.
- **Achtergrond blijft in het concept.** Wat de leerkracht over een
  leerling vertelt dat niet over zijn werk gaat (schoolverleden,
  thuissituatie, gezondheid), noteer je onder *Observatie leerkracht*; het
  helpt je zijn beslissing begrijpen. Het komt niet in `justification`,
  niet in `adjustmentNote` en niet in publieke tekst. Wat de leerling in
  de klas toonde ("je legde uit hoe …") mag wel in de reden.
- **Geen leerlingdata in de repo.** Concept en sidecar staan in
  `~/ai-tutor-evaluaties`, back-ups in `~/ai-tutor-backups`. Niets daarvan
  wordt gecommit.
- **Geen namen van echte leerlingen in publieke tekst.** De repo is
  publiek. Een issue, een PR, een commit, een opmerking op GitHub of een
  bestand in de repo noemt nooit de naam of de uid van een echte
  leerling, en niets van wat de leerkracht over hem vertelde. Schrijf "een
  leerling", "bij twee leerlingen", of een voorbeeldnaam die aan niemand
  gelinkt is; klasnamen (6WEWI) mogen. Het gesprek met de leerkracht en
  het concept mogen namen hebben: die zijn niet publiek.
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
iets anders dan een laag punt door zes gemiste kerndoelen). Noem een
bijna-doel met een hoge μ en weinig vragen niet "gekend" zonder te zeggen
waar μ vandaan komt (stap 3, onderdeel 4).

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

Noteer per leerling welke doelen meetellen. Een voorwaardelijke beslissing
("tel het mee als de laatste oefeningen juist zijn") noteer je als
voorwaarde: stap 3 beantwoordt ze uit de data.

**Stop hier** tot je die antwoorden hebt. De rapporttekst schrijf je met de
observaties erbij, niet ervoor.

### 3. Consistentie — en stop

Twee leerlingen met hetzelfde profiel krijgen hetzelfde punt. De leerkracht
beslist per leerling en ziet de klas niet naast elkaar; jij wel. Op 23-09
voldeden drie doelen bij drie leerlingen aan zijn maat zonder dat hij ze
noemde, en een voorwaardelijke beslissing kon alleen de data beantwoorden.
Zonder deze stap hadden die leerlingen een lager punt gekregen dan
klasgenoten met hetzelfde profiel. Deze stap komt dus elke keer, na zijn
beslissingen en vóór de eerste rapporttekst, ook als alles consistent
lijkt.

1. **Leid de maat af.** Lees bij elk doel dat hij meetelde in het concept
   wat het met de andere gemeen heeft: μ (de drempel; op 23-09 ongeveer
   0,78), het *hoogste niveau* tegenover het verwachte niveau in de kop,
   het aantal vragen en hoeveel daarvan juist (*herkomst*), de *laatste
   vragen*, signalen uit andere doelen (incidenteel en transfer-krediet in
   de herkomst, *signalen vanuit ander doel*), en de klasobservatie die hij
   erbij gaf. Zeg de maat in één zin, bv. "μ vanaf ongeveer 0,78, hoogste
   niveau minstens het verwachte, meer dan tien vragen, de laatste juist".
   Zeg ook welk deel alleen op klasobservatie rust: dat kun je in de data
   niet nalopen, dus vraag je het hem per kandidaat.
2. **Loop de hele klas na.** Voor elke leerling, elk doel onder *Bijna*
   dat aan dezelfde maat voldoet en niet genoemd is: noem de leerling, de
   eigen zin van het doel met zijn id, de gegevens waarop het aan de maat
   voldoet, en het punt als het meetelt. Dat punt komt uit de rij
   *meegeteld* van `what-if`, nooit uit eigen rekenwerk. Geef in `--tel`
   alle doelen die bij die leerling al meetellen, plus het nieuwe: het punt
   is geen som van losse doelen. Een doel dat al meetelt, meldt `what-if`
   als "telt al mee". Mist een doel de maat op één voorwaarde net, noem
   het apart als twijfelgeval en zeg welke voorwaarde. Voldoet een doel dat hij uitdrukkelijk
   niet telde toch aan de maat, of telde hij er een dat er niet aan
   voldoet, leg dat ook voor, zonder oordeel: er kan een reden zijn die
   niet in de data staat.
3. **Voorwaardelijke beslissingen.** "Tel het mee als de laatste
   oefeningen juist zijn" beantwoord jij, uit de data, per doel. De regel
   *laatste vragen* in het concept komt uit `direct_signals` van de
   herspeling: de laatste vijf vragen over dat doel, per dag, en "(de
   laatste N juist)" als de reeks juiste langer is. Geef per doel de
   voorwaarde, die regel zoals ze in het concept staat, en je antwoord:
   voldaan (dan telt het, met het punt uit `what-if`) of niet. Een
   vervolgvraag of een incidenteel signaal is geen vraag en staat er niet
   in. Kan de regel de voorwaarde niet beantwoorden (ze vraagt meer dan de
   laatste vijf, of het doel staat onder *Ver*, zonder die regel), zeg dat
   en vraag het hem; vul het niet zelf in.
4. **Een hoge μ met weinig vragen.** Voor je een bijna-doel "gekend"
   noemt, zeg je waar μ vandaan komt: de *herkomst*. μ 0,91 op "2 vragen
   (0 juist) · incidenteel 14 juist" zegt dat de grader het doel juist zag
   gebruiken bij iets anders, niet dat de leerling een vraag erover juist
   beantwoordde; er is geen hoogste niveau. De leerkracht mag het
   meetellen, maar dan weet hij waarop.
5. **Leg het voor en stop.** Geef in het gesprek de maat, per leerling de
   extra doelen met hun punt, de twijfelgevallen, het antwoord op elke
   voorwaardelijke beslissing en de doelen met een hoge μ van elders.
   **Stop** tot hij antwoordt. Noteer daarna in het concept, per leerling,
   welke doelen meetellen, het `what-if`-commando met al die doelen en zijn
   rij *meegeteld*. Die rij geeft het punt voor `adjustedGrade` en de
   tellingen voor de verantwoording (stap 4).

### 4. Tekst voor het rapport — en stop

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
toonde", nooit "hij heeft" of een naam. Aanspreken zonder aanhef.

**Verantwoording van je score.** Waar het punt uit bestaat, in woorden en
met hooguit een paar hele getallen: hoeveel van de kerndoelen je hebt
aangetoond en hoeveel van de extra doelen; of je dat deed met makkelijke,
gewone of moeilijke oefeningen; wanneer je de onderdelen afrondde ("op 15
september had je alle onderdelen af"; "de eerste onderdelen had je begin
september, het laatste op de 22e"). Benoem wat nog ontbreekt met de eigen
zin van het leerdoel uit het concept ("Je kan invoer omzetten naar een
getal wanneer …"), kort herformuleerd als hij te lang is; hoogstens drie.
Het punt zelf noem je niet — dat staat erboven.

**Op de aangepaste tellingen.** Het punt op het rapport is `adjustedGrade`,
anders het voorstel (`published_report.dart`), met eronder de
verantwoording en de reden van de aanpassing ("Opmerking van je leraar:
…"). Telt de leerkracht doelen mee, dan schrijf je de verantwoording op
de rij *meegeteld* van `what-if` met al die doelen (stap 3), niet op het
concept: "18 van de 19 kerndoelen", en ook hoeveel op moeilijk uit die
rij. Een doel dat meetelt, staat niet bij wat nog ontbreekt. Past hij het
punt aan zonder doelen mee te tellen, dan blijven de tellingen die van
het concept en zegt de reden waarom het punt anders is.

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
(`adjustmentNote`): die staat ook op het rapport, in je-vorm. Telt een
doel mee, dan zegt de reden welk, met zijn eigen zin, en waarom ("Ook 'Je
kan …' telt mee: je laatste negen vragen daarover waren juist, en je
legde het in de klas uit"). Onder *Hoe dit punt berekend is* toont het
rapport, dichtgeklapt, de tellingen van het voorstel, zonder die doelen
(17 van de 19); de reden is wat het verschil met de verantwoording
uitlegt. Achtergrond die de leerkracht over de leerling vertelde, komt er
niet in (*Wat vaststaat*).

Toon de leerkracht alle rapportteksten in het gesprek. **Stop.** Pas zijn
opmerkingen toe in concept én sidecar; zet `justificationSource` op
`"edited"` als hij de tekst zelf herschreef, `skip: true` met `skipReason`
bij uitstellen of overslaan, `adjustedGrade` (het punt van de rij
*meegeteld* als hij doelen meetelt) en `adjustmentNote` bij een
aanpassing. Laat `computed` staan: dat is het getal van de regel, en
`apply` schrijft het als voorstel. Schrijf niets tot hij "go" zegt.

### 5. Schrijven

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

### 6. Terugkoppelen

Vat samen wat geschreven is, wat uitgesteld, en wat opviel dat de regel,
de diagnostiek of deze skill zou moeten veranderen. De leerkracht bespreekt
dat in een ander gesprek; wat jij hier leert, hoort in die samenvatting.

Wat daaruit een issue of een wijziging in de repo wordt, is publiek: geen
namen of uid's van echte leerlingen, en geen achtergrond (*Wat
vaststaat*). Beschrijf het geval met de gegevens: "bij één leerling
`write_simple_script` op 0,78 op `hard` na 29 vragen, de laatste negen
juist". De klasnaam mag erbij; een voorbeeldnaam die aan niemand gelinkt
is ook.

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
