# Puntenformule — hoe je rapportcijfer tot stand komt

**Versie 1.0 (concept)** — nog niet van kracht; wordt eerst getoetst in een
schaduwperiode (zie §4). Laatste wijziging: 2026-09-24.

Dit document legt exact uit hoe de AI-tutor jouw kennis meet en hoe daaruit
een **puntvoorstel** voor het rapport wordt berekend. Het is geschreven voor
leerlingen (en ouders en de klassenraad), maar het is tegelijk de technische
specificatie die de app moet volgen: wat hier staat, is wat de code doet.

Drie afspraken vooraf:

1. **De formule is openbaar en geversioneerd.** Wijzigingen gaan alleen in
   bij het begin van een nieuwe rapportperiode, worden in de klas toegelicht
   met de reden, en gelden nooit met terugwerkende kracht (§5).
2. **Het voorstel is deterministisch.** Twee leerlingen met dezelfde data
   krijgen hetzelfde voorstel. Iedereen kan zijn eigen punt narekenen met
   dit document.
3. **De AI kiest nooit het punt.** De formule berekent het getal; de AI
   schrijft alleen de tekstuele verantwoording erbij; de leerkracht kan het
   voorstel aanpassen en zet de handtekening. Punten verschijnen pas op een
   rapportmoment, nooit live tijdens het werk: wanneer het punt op het
   rapport gaat, geeft de leerkracht het vrij en lees je in de app het
   afgetekende rapport met de verantwoording erbij (§2.9). Tussentijds zie
   je je voortgang, geen cijfer (§1.7).

---

## 1. Wat de tutor over je bijhoudt

### 1.1 Leerdoelen en overtuigingen

Het curriculum bestaat uit doelen → subdoelen → **leerdoelen** (LO's, van
*learning objectives*). Een leerdoel is één afgebakend ding dat je moet
kunnen, zoals "een for-lus schrijven" of "voorspellen wat een if/else
afdrukt".

Voor elk leerdoel houdt de app een **overtuiging** (belief) bij: hoe zeker
is het systeem dat jij dit beheerst? Die overtuiging is een
Beta-verdeling met twee tellers, **α** (alfa) en **β** (bèta):

- **α** telt het gewogen bewijs *vóór* beheersing (goede antwoorden).
- **β** telt het gewogen bewijs *tégen* beheersing (foute antwoorden).

Elk leerdoel start op **(α, β) = (1, 1)**: "geen idee, 50/50". Uit de twee
tellers volgen de twee getallen die overal in dit document terugkomen:

```
gemiddelde   μ = α / (α + β)        → hoe waarschijnlijk is beheersing?
bewijsmassa  n = α + β              → hoeveel bewijs ligt eronder?
```

Een leerdoel op (5, 1) heeft μ ≈ 0,83 met n = 6: waarschijnlijk beheerst,
redelijk wat bewijs. Een leerdoel op (1, 1) heeft ook een μ (0,5), maar
n = 2 zegt: dat gemiddelde betekent nog niets.

### 1.2 Wat één antwoord doet

Na elk antwoord beoordeelt het taalmodel (de "grader") welk leerdoel of
welke leerdoelen je antwoord raakte, en geeft per leerdoel een signaal:
**positief**, **negatief** of **neutraal**, met een sterkte **sterk**,
**matig** of **zwak**. Neutraal doet niets (het antwoord raakte het
leerdoel, maar bewees niets). Voor de rest geldt:

| sterkte | basisgewicht |
| --- | --- |
| sterk | 2,0 |
| matig | 1,0 |
| zwak | 0,5 |

Dat basisgewicht wordt vermenigvuldigd met de **moeilijkheidsfactor** van
de vraag — en die hangt sinds v1.0.14 af van het teken van het signaal:

| moeilijkheid | positief signaal | negatief signaal |
| --- | --- | --- |
| makkelijk | × 0,6 | × 1,4 |
| gemiddeld | × 1,0 | × 1,0 |
| moeilijk | × 1,4 | × 0,6 |

Het resultaat komt bij α (positief signaal) of bij β (negatief signaal).
Een sterk-positief antwoord op een moeilijke vraag telt dus voor
2,0 × 1,4 = 2,8 bij α; een sterk-negatief antwoord op diezelfde vraag
voor 2,0 × 0,6 = 1,2 bij β.

> **Belangrijk gevolg.** De moeilijkheidsfactor is *asymmetrisch*: een
> juist antwoord op een moeilijke vraag bewijst veel, een fout antwoord
> erop weinig — en op een makkelijke vraag is het net omgekeerd. Daardoor
> is je gemiddelde μ **niveaubewust**: dezelfde grens van 0,80 (§1.5)
> komt overeen met ongeveer 90% juist op makkelijke vragen, 80% op
> gemiddelde en ongeveer 63% op moeilijke. Wie op gemiddeld 76% haalt en
> daardoor naar moeilijk gepromoveerd wordt (§1.6), zakt daar naar
> ongeveer 60% juist — en μ blijft nagenoeg gelijk (≈ 0,78). Een promotie
> kan je dus niet meer uit je beheersing duwen, en een demotie naar
> makkelijk maakt beheersing niet goedkoper. Ook "vastgelopen" (§1.7)
> leest zo het niveau mee: op moeilijk ben je dat pas onder ongeveer 57%
> juist. Tot v1.0.13 gold de factor symmetrisch (ook een fout op moeilijk
> woog × 1,4) en was μ gewoon je scorepercentage, op welk niveau je ook
> zat; omdat de kalibratie je bewust parkeert waar je 40–75% scoort,
> eindigde een goed gekalibreerde leerling die lang genoeg bevraagd werd
> per ontwerp onder de beheersingsgrens. Moeilijkheid telt daarnaast nog
> apart mee in de puntformule, via de ratel van §2.5.

Antwoorden op **vervolgvragen** (de doorvraagjes na een gewoon antwoord)
tellen ook mee, maar afgetopt op sterkte *zwak* (0,5) en gerekend als
moeilijkheid *gemiddeld*. Ze zijn echt bewijs, maar de vraag was niet als
gekalibreerde meting ontworpen.

De grader mag een antwoord ook laten meetellen voor een leerdoel uit een
**eerder subdoel** van hetzelfde hoofddoel. Wat daarmee gebeurt, hangt
af van het teken. Een **positief** signaal (het antwoord toont dat een
ouder leerdoel zit) telt gewoon mee voor dat oudere leerdoel, met de
sterkte die de grader opgeeft, maar gerekend als moeilijkheid
*gemiddeld*: de moeilijkheid van de vraag was gekozen voor het leerdoel
dat bevraagd werd, niet voor het oudere. De ratel van §2.5 beweegt er
niet door, en de voortgangsbalkjes van het oudere subdoel evenmin;
alleen α en de decay-klok (§1.3) veranderen. Een **negatief** signaal
(een `print()` die misgaat in een lus-oefening) is sinds v1.0.13 géén
bewijs maar een **aanleiding**: het is het minst betrouwbare oordeel dat
het systeem kent — afgeleid uit een antwoord over iets anders, zonder
dat de vraag daarvoor ontworpen was — en het treft per definitie
leerdoelen die je al achter je hebt en die de tutor niet meer
rechtstreeks bevraagt, zodat het nooit meer weersproken zou worden. Het
verandert dus niets aan α, β of de decay-klok van het oudere leerdoel.
In plaats daarvan onthoudt de app dat er iets te controleren valt, en
stelt de eerstvolgende sessie er een opfrisvraag over (§2.8); *die*
rechtstreekse meting telt, met volle sterkte.

### 1.3 Vergeten (decay)

Kennis die je niet gebruikt, zakt weg — en de overtuigingen doen dat ook,
met een **halveringstijd van 60 dagen**. Bij elke lezing van een
overtuiging wordt eerst dit toegepast:

```
d = 0,5 ^ (verstreken dagen / 60)
α_effectief = 1 + (α − 1) × d
β_effectief = 1 + (β − 1) × d
```

De vorm `1 + (… − 1) × d` zorgt dat een onaangeroerd leerdoel terugzakt
naar de startwaarde (1, 1) — "we weten het niet meer" — en niet naar nul.
Ter referentie:

| tijd zonder oefenen | d | effect |
| --- | --- | --- |
| 1 week | ≈ 0,92 | nauwelijks zichtbaar |
| 2 weken (kerst/paasvakantie) | ≈ 0,85 | kleine dip |
| 10 weken (zomer) | ≈ 0,31 | fors: een (10, 2) wordt (3,8, 1,3), μ zakt van 0,83 naar 0,74 |

Decay is eerlijk als *meting* (programmeren vraagt regelmatig oefenen),
maar zou oneerlijk zijn als *puntenmechanisme* voor wie vroeg klaar was.
Daarom bestaan de opfris- en transfermechanismen van §2.8: tegen het
rapportmoment zijn je overtuigingen vers.

### 1.4 Het bewijsplafond

De bewijsmassa is begrensd: **α + β ≤ 20**. Zou nieuw bewijs daar overheen
gaan, dan wordt het bestaande bewijs (boven de startwaarde) eerst
evenredig gekrompen zodat het nieuwe bewijs er op vol gewicht bij kan. Het
gemiddelde μ blijft daarbij vrijwel gelijk; alleen de massa krimpt.

Gevolg: ook op een "vol" leerdoel blijft een nieuw antwoord de overtuiging
merkbaar bewegen. Eén sterk-negatief antwoord op een (18, 2) duwt μ van
0,90 naar 0,81. Recente prestaties blijven altijd tellen; je kunt niet op
oud bewijs blijven drijven.

### 1.5 Wanneer is een leerdoel "beheerst"?

Een leerdoel geldt als **beheerst** wanneer alle drie tegelijk waar zijn:

1. **μ ≥ 0,8** — het systeem is er redelijk zeker van;
2. **n = α + β ≥ 4** — die zekerheid steunt op echt bewijs, niet op één
   gelukstreffer (minstens ±2 punten bewijs bovenop de start);
3. **je hebt dit leerdoel minstens één keer positief aangetoond op het
   moeilijkheidsniveau waarop je toen gekalibreerd stond, of hoger.**

Voorwaarde 3 sluit het "makkelijke-vragen-farmen" af: wie alleen op
makkelijk juist antwoordt, haalt de beheersing niet, hoe hoog μ ook klimt.
Ze wordt bijgehouden als een **ratel** (ratchet): eenmaal aangetoond,
blijft aangetoond — een latere kalibratiedaling maakt dat niet ongedaan.

Beheersing wordt bij elke update opnieuw gecontroleerd: door decay of
nieuwe fouten kan een leerdoel terugvallen naar "niet beheerst"
(voorwaarden 1 en 2); alleen de ratel van voorwaarde 3 is blijvend. Dat
terugvallen stuurt wat de tutor doet — vraagkeuze, opfrisvragen — niet je
punt: de app onthoudt per leerdoel wanneer de drie voorwaarden voor het
eerst samen golden, en het is die stempel die de formule van deel 2 leest
(§2.2).

### 1.6 Jouw moeilijkheidsniveau (kalibratie)

Los van de leerdoelen houdt de app per leerling één globaal
moeilijkheidsniveau bij: **makkelijk / gemiddeld / moeilijk**. Iedereen
start op gemiddeld. Het systeem kijkt naar je laatste 10 antwoorden,
gefilterd op vragen die op je huidige niveau gesteld werden:

- **Promotie** (één trap omhoog): minstens 4 zulke antwoorden in het
  venster én minstens 75% volledig juist.
- **Demotie** (één trap omlaag): minstens 3 zulke antwoorden én minstens
  60% fout of half-juist. Demotie reageert bewust sneller dan promotie:
  te moeilijke vragen zijn frustrerend én vervuilen de metingen.

Daarnaast kan één specifiek leerdoel tijdelijk een trap lager bevraagd
worden als je er twee keer na elkaar sterk-fout op antwoordde — dat
verandert je globale niveau niet.

Dit kalibratieniveau stuurt welke vragen je krijgt. Het is *met opzet*
beweeglijk (één mindere week kan je een trap doen zakken) — en precies
daarom gaat het **niet** rechtstreeks in de puntformule (§2.5).

### 1.7 De voortgangsbalkjes

Het voortgangsbalkje van een subdoel toont de fractie van de
niet-optionele leerdoelen die beheerst zijn. Een leerdoel waarop je écht
bent vastgelopen (veel bewijs, μ blijft laag) blokkeert je doorstroming
niet — het systeem laat je verder — maar telt in het balkje eerlijk als
niet-beheerst. Schuif je zo met een vastgelopen leerdoel door naar het
volgende subdoel, dan blijft het balkje van het afgeronde subdoel dus
onder de 100% staan (bijvoorbeeld 4 van de 5); dat het subdoel afgerond
is, toont de app apart met een vinkje (sinds v1.0.15 een eigen stempel op
je voortgang, `advancedAt`), niet door het balkje vol te maken. Het
balkje van een hoofddoel is het gemiddelde van zijn subdoelen.

**De balkjes zijn geen punten.** Ze tonen live de stand van de
overtuigingen; het rapportpunt komt uit de formule van deel 2 en wordt
alleen op rapportmomenten berekend.

---

## 2. Van meting naar puntvoorstel

### 2.1 Mijlpalen en de 50-lijn (Angoff)

Per rapportperiode legt de leerkracht een **mijlpaal** vast: de verzameling
leerdoelen die tegen dat rapport gekend hoort te zijn ("deze doelen
verwacht ik begin oktober"). Voor elke mijlpaal beantwoordt de leerkracht
vooraf, per leerdoel, de Angoff-vraag: *beheerst een leerling die nog nét
geslaagd is dit leerdoel?*

- Ja → **kernleerdoel** (set K);
- Nee → **uitbreidingsleerdoel** (set U).

Daarnaast legt de mijlpaal het **verwachte moeilijkheidsniveau** vast
(makkelijk / gemiddeld / moeilijk) waarop de kern aangetoond hoort te zijn.

Zo is de betekenis van de 50 vastgeklikt: **de volledige kern beheersen op
het verwachte niveau = 50/100.** Alles daarboven komt uit uitbreiding en
uit aantonen op hogere moeilijkheid.

### 2.2 Welke gegevens de formule gebruikt

Op het rapportmoment leest de formule per leerdoel van de mijlpaal:

- **beheerst?** — of dit leerdoel **ooit** aan de drie voorwaarden van
  §1.5 heeft voldaan. De app zet per leerdoel een eenmalige stempel op het
  moment dat ze voor het eerst samen gelden, en sinds v1.0.12 leest de
  formule die stempel — niet de overtuiging zoals ze nu staat. Een latere
  meting die tegenvalt, een signaal vanuit een ander subdoel (§1.2) of
  decay (§1.3) kan de stempel niet meer wegnemen; die sturen de tutor
  (§1.5, §2.8), niet je punt. Verder werken kan je punt dus nooit
  verlagen. En het punt rust daarmee niet op weinig oordelen: de stempel
  valt pas wanneer het *opgebouwde* bewijs — alle rechtstreekse metingen
  tot dan — de grens passeert, dus één verkeerd oordeel van de AI kan hem
  hoogstens uitstellen, nooit wegnemen;
- **hoogste aangetoonde moeilijkheid** — de drietraps-ratel van §2.5.

Daaruit volgen drie fracties:

```
k = beheerste fractie van de kernleerdoelen K,
    waarbij een kernleerdoel alleen meetelt als het beheerst is
    én de ratel ≥ het verwachte niveau van de mijlpaal staat
u = beheerste fractie van de uitbreidingsleerdoelen U
d = fractie van alle beheerste mijlpaal-leerdoelen (K ∪ U)
    waarvan de ratel op "moeilijk" staat
```

### 2.3 Beheersingsscore M

```
M = 50 · C(k)  +  50 · k · ( w_u · u + w_d · d )        (op 100)
```

- **C(k)** is een stijgende curve met C(0) = 0 en C(1) = 1: zij bepaalt
  hoe streng onvolledige kernbeheersing wordt afgerekend onder de 50. In
  v1 is C(k) = k (recht evenredig); de definitieve vorm wordt in de
  schaduwrun bepaald (§4).
- Het deel boven de 50 is alleen te verdienen via **uitbreiding** (u) en
  **moeilijkheid** (d), met gewichten w_u + w_d = 1 (waarden: §4).
- De factor **k** vóór het boven-50-deel koppelt de top aan de kern: wie
  de kern maar half beheerst, kan met uitbreidingswerk niet alsnog naar
  een topscore. Een hardere afsluiting (bv. boven-50 pas vanaf een
  kerndrempel) is een open parameter voor de schaduwrun.

Volledige kern, volledige uitbreiding, alles op moeilijk aangetoond
→ M = 100.

### 2.4 Groeiscore G — vervallen sinds v1.0.16

Tot v1.0.15 telde naast de stand M ook een **groeiscore G** mee: welk deel
van je persoonlijke kloof naar de mijlpaal je in de periode had gedicht,
gemeten tegen een momentopname van je beheersing bij de periodestart. Die
term is geschrapt; het punt is sindsdien de beheersingsscore zelf (§2.6).

Waarom. De trage starter die G moest beschermen, is al beschermd door wat
M leest: de stempel van §2.2 zegt *of* je een leerdoel hebt aangetoond,
niet *wanneer*, dus een leerdoel dat je in de laatste week aantoonde telt
precies even zwaar als een uit de eerste week (§3.1). G voegde daar vooral
ruis aan toe — een getal dat afhing van het moment waarop de momentopname
toevallig genomen werd — en liet de app anders rekenen dan de evaluatie
buiten de app, die al P = M gebruikte. Hoe een mijlpaal met verwachtingen
per periode om moet gaan met wat je vóór die periode al kon, is een
latere herziening van deel 2 (§4).

### 2.5 De rol van moeilijkheid

Moeilijkheid verdient een eigen plek in het punt — maar via het juiste
signaal.

- **Niet alleen via μ:** sinds v1.0.14 leest μ het niveau mee (de
  asymmetrische factor van §1.2), maar μ zegt alleen *of* je de lat op
  jouw niveau haalt, niet *hoe hoog* die lat lag. Dat laatste onthoudt de
  ratel hieronder. Moeilijkheid telt zo voorlopig twee keer — een
  soepelere μ op moeilijk én de bonus via d — en dat blijft bewust zo tot
  de herziening van deel 2 (§4).
- **Niet via je globale kalibratieniveau (§1.6):** dat is bewust
  beweeglijk. Eén mindere week doet je zakken — maar de foute antwoorden
  van die week hebben je overtuigingen dan al verlaagd. Het niveau er
  bovenop laten meetellen zou dezelfde slechte week twee keer aanrekenen.
- **Wel via de drietraps-ratel per leerdoel:** de app onthoudt per
  leerdoel het **hoogste niveau (makkelijk / gemiddeld / moeilijk) waarop
  je ooit een positief signaal verdiende** — per trap éénrichting, net als
  de bestaande ratel van §1.5 (waarvan dit de uitbreiding is; voor ouder
  opgeslagen data zonder trapinformatie geldt de oude betekenis
  "aangetoond op niet-makkelijk" als "gemiddeld").

In de formule werkt dat uitsluitend **boven de 50-lijn**: de kern op het
verwachte niveau opent de 50 (via k), volgehouden aantonen op *moeilijk*
koopt de topband (via d). Moeilijkheid is een differentiator naar boven,
nooit een extra poort naar beneden.

### 2.6 Het puntvoorstel

```
P = M
```

Het puntvoorstel is de beheersingsscore van §2.3 op het moment van
berekenen — sinds v1.0.16 zonder groeiterm en zonder beginpunt van de
periode (§2.4). Het rapport certificeert beheersing van de leerstof, en
dat is wat M meet.

Het voorstel P wordt afgerond op een geheel punt en gaat, samen met de
verantwoording, naar de leerkracht. De verantwoording wordt door de AI
geschreven op basis van je statusrapporten en je voortgangshistoriek en
legt uit *waarom* de cijfers zijn wat ze zijn — ze bevat geen eigen
oordeel over het punt. De leerkracht kan het voorstel aanpassen voor
context die het systeem niet ziet, kan de verantwoording ook zelf
herschrijven — ook nog na het aftekenen, wanneer een gesprek met jou de
eerste formulering achterhaald heeft — en tekent af. Het getekende punt is
het rapportpunt; aan het getal verandert een herschreven tekst niets
(§3.3).

### 2.7 Herkomst van bewijs: klas en thuis

Niet al het bewijs is even hard. Werk in de klas onder actief toezicht
(via de Anchor-klassenomgeving geregistreerd) krijgt een **bescheiden
hoger bewijsgewicht** dan werk thuis: het gewicht van §1.2 wordt met een
factor **s ≥ 1** vermenigvuldigd voor antwoorden binnen een
toezichtsessie (waarde van s: §4). Er is geen knop per antwoord; de
sessie-registratie bepaalt het automatisch.

Thuiskrediet is daarbij **voorlopig in de goede zin**: het telt meteen
volledig mee (thuis doorwerken loont), maar het wordt bevestigd — of
tegengesproken — door je latere prestaties onder toezicht op dezelfde
leerdoelen. Wie thuis "briljant" presteert maar dat in de klas nooit kan
tonen, ziet die overtuigingen door de klasantwoorden vanzelf terugzakken.
Dit is geen geheim controlemechanisme maar open beleid: het maakt eerlijk
thuiswerk waardevol en oneerlijk thuiswerk zinloos.

### 2.8 Oude leerstof: opfrissen en transfer

**Decay telt niet mee in het punt (sinds v1.0.10).** Decay bestaat om je
terug naar oude leerstof te sturen — ze stuurt de opfrisvragen hieronder,
en daar hoort ze thuis. Een punt is een verslag van wat je hebt aangetoond,
geen schatting van wat je intussen misschien vergeten bent: een leerdoel
dat je in september aantoonde, héb je aangetoond, wat de rapportdatum ook
is. Ze toepassen op het punt strafte bovendien precies de verkeerde
leerling. De tutor stopt met doorvragen zodra beheersing vaststaat (§3.2),
dus een sterke leerling eindigt met **dunne** bewijsmassa — α ≈ 4 à 5, de
beheersingsdrempel zelf — en zo'n overtuiging zakt binnen één tot drie
weken onder gemiddelde 0,80, terwijl de vaak herhaalde overtuiging van een
worstelende leerling genoeg massa draagt om het uit te zingen. Dat keerde
§3.2 om in plaats van ze te eerbiedigen. Sinds v1.0.12 volgt dit vanzelf
uit §2.2: het punt leest de stempel, en aan een stempel valt niets te
vervallen.

De mechanismen hieronder houden je *overtuigingen* vers — zij bepalen
wanneer de tutor je opnieuw bevraagt:

- **Transfer-krediet.** Oudere leerdoelen zitten vaak impliciet in nieuw
  werk: wie in december een while-lus schrijft, gebruikt daarin nog
  steeds `print()` en variabelen. Wanneer de grader ziet dat je een
  eerder beheerst leerdoel uit een *ander* subdoel correct gebruikt in een
  werkende oplossing van een nieuwe oefening, krijgt dat oude leerdoel een
  klein positief signaal: de decay-klok wordt teruggezet én de overtuiging
  stijgt licht. Dit werkt alleen positief (een foute of half-juiste
  oplossing telt langs deze weg niet tegen het oude leerdoel — en levert
  het ook niets op; wijst de fout wél duidelijk op een gat in dat oude
  leerdoel, dan geeft de grader daar een gewoon negatief signaal op, zie
  §1.2), alleen voor leerdoelen die eerder door directe bevraging beheerst
  raakten (de app onthoudt per leerdoel wanneer dat voor het eerst
  gebeurde), en met klein gewicht — de Beta-wiskunde zorgt zelf voor
  afnemende meeropbrengst. De moeilijkheidsratel van §2.5 beweegt er
  niet door: de moeilijkheid van de oefening was voor het nieuwe
  leerdoel gekozen, niet voor het oude.
- **Opfrisvragen.** Leerdoelen die *niet* vanzelf in nieuwe leerstof
  terugkeren en lang niet bevraagd zijn, krijgen af en toe een korte
  opfrisvraag in de gewone oefenflow. Dat is meteen goede didactiek
  (ophaaloefening) én houdt de meting vers. Concreet: een sessie kan
  openen met **één** opfrisvraag (de app kondigt ze aan) over een eerder
  beheerst leerdoel uit een ander subdoel van hetzelfde hoofddoel waarvan
  de overtuiging al **30 dagen** niet meer geschreven is — het langst
  onaangeroerde leerdoel eerst. Omdat ook transfer-krediet een schrijving
  is, komen leerdoelen die je in nieuw werk blijft gebruiken hier
  vanzelf niet in terecht. Eén uitzondering op de 30 dagen: wees een
  latere oefening op een mogelijk gat in zo'n eerder beheerst leerdoel
  (een negatief signaal op een eerder subdoel, §1.2 — dat sinds v1.0.13
  de overtuiging zelf niet raakt), dan wordt het bij de eerstvolgende
  sessiestart opgefrist, ook al is het pas geschreven — de app onthoudt
  die vraag tot het leerdoel opnieuw rechtstreeks bevraagd is;
  transfer-krediet of een positief signaal van opzij heft ze niet op,
  want de vraag wordt beantwoord door ze te stellen. Zulke leerdoelen
  gaan voor op de gewoon-verouderde; de opfrisvraag zelf (goed of fout
  beantwoord) zet het leerdoel daarna terug op de gewone klok van 30
  dagen. Het antwoord telt als een gewone
  meting van
  dat leerdoel (§1.2, op je huidige moeilijkheidsniveau, met de
  herkomst van §2.7): een juist antwoord verhoogt de overtuiging en
  beweegt ook de ratel van §2.5, een fout antwoord verlaagt ze. De vraag
  telt niet mee voor je kalibratieniveau (§1.6) en verandert niets aan
  de voortgangsbalkjes.
- **Controlevragen (sinds v1.0.17).** Een subdoel kan doorschuiven terwijl
  één leerdoel erin nog niet aangetoond is: de andere zijn beheerst, of
  je liep er even op vast (§1.7). De gewone oefeningen gaan alleen over
  het subdoel waar je nu mee bezig bent, en de opfrisvraag hierboven
  alleen over leerdoelen die je al aantoonde — zo'n leerdoel kwam dus
  nooit meer aan de beurt, en omdat decay een overtuiging nooit óver de
  grens trekt, kon je de stempel van §2.2 er niet meer zelf voor
  verdienen. Daarom stelt de tutor af en toe, midden in het oefenen,
  **één controlevraag** (de app kondigt ze aan) over een leerdoel uit een
  eerder subdoel van hetzelfde hoofddoel dat je nog niet aantoonde,
  waarvan de overtuiging **net onder de grens** staat (μ vanaf 0,70 en
  onder 0,80) en dat al **minstens 7 dagen niet meer rechtstreeks
  bevraagd** is — een signaal van opzij (§1.2) telt daarbij niet als
  vraag. Alleen wanneer je recente werk op je niveau goed gaat: van je
  laatste tien antwoorden is het deel juist, gewogen zoals μ (een juist
  antwoord op moeilijk telt zwaarder, een fout op moeilijk lichter),
  minstens 0,75 — ongeveer 56% juist op moeilijk volstaat, op makkelijk
  is het ongeveer 88%. Wie het nu moeilijk heeft, wordt dus niet naar
  oude leerstof teruggestuurd. Tussen twee vragen over een ander subdoel
  (controle- of opfrisvraag) liggen minstens vijf gewone oefeningen; het
  leerdoel dat het langst niet meer rechtstreeks bevraagd is, komt eerst.
  Het antwoord telt als een gewone meting van dat leerdoel op je huidige
  niveau (§1.2, met de ratel van §2.5 en de herkomst van §2.7): een juist
  antwoord kan het leerdoel over de drie voorwaarden van §1.5 tillen, en
  dan krijgt het de stempel die het punt leest; een fout antwoord verlaagt
  de overtuiging. Goed of fout, daarna wacht dat leerdoel weer minstens
  een week. Zoals de opfrisvraag telt de controlevraag niet mee voor je
  kalibratieniveau (§1.6) en verandert ze niets aan de voortgangsbalkjes.

Samen betekenen ze: wie vroeg klaar was en gewoon is blijven werken,
staat er op het rapportmoment vers en terecht goed voor — en wie een
leerdoel net niet haalde maar intussen verder is gegroeid, krijgt de kans
om dat zelf te tonen.

### 2.9 Je rapport in de app

Het afgetekende punt blijft niet bij de leerkracht liggen. Per mijlpaal
geeft de leerkracht de afgetekende rapporten in één keer vrij — op het
moment dat de punten op het rapport gaan, zodat niemand zijn punt dagen
vóór een klasgenoot te zien krijgt. Wat vrijgegeven is, staat in de app
onder **Mijn rapporten**: alleen je eigen rapporten, nieuwste eerst.

Bovenaan staat waar het om gaat: het punt en de verantwoording erbij, plus
de opmerking van de leerkracht als die er een schreef. Daaronder,
opgevouwen tot je ze opent, de cijfers om het na te rekenen — M, en k, u en d met de kern- en uitbreidingsaantallen en het
verwachte niveau van de mijlpaal. Dit document nodigt je uit om je eigen
punt na te rekenen, dus horen die cijfers erbij; maar een rapport opent met
een punt en een uitleg, niet met een formule.

Er staat ook **berekend op [datum]**. Dat is niet automatisch de datum van
de mijlpaal: de leerkracht kiest zelf wanneer de berekening loopt. Wie tot
dat moment is blijven doorwerken, zag dat werk nog meetellen — daarom
staat die datum erbij, zodat een verschil met een klasgenoot geen raadsel
is.

Twee dingen staan er bewust *niet* op: hoeveel beurten je in de klas dan
wel thuis maakte, en hoeveel mijlpaal-leerdoelen als verouderd of
nooit-bevraagd gemeld werden. Het eerste is een principe dat §2.7 al
openlijk uitlegt, het tweede is een betrouwbaarheidssignaal voor de
leerkracht (§3.2). Geen van beide gaat in het getal, en op je eigen
rapportpagina zouden ze lezen als een tellertje over jou in plaats van als
een punt met een uitleg. Wat wél vrijgegeven is, ligt vast: het wordt niet
herrekend wanneer je daarna verder werkt (§5). Herschrijft de leerkracht
achteraf nog de verantwoording, dan wordt die kopie met de nieuwe tekst
opnieuw vrijgegeven; het punt blijft wat het was.

---

## 3. Eerlijkheid en spelregels

### 3.1 Waarom een trage start je rapport niet blijft achtervolgen

Het klassieke probleem van permanente evaluatie: een laag punt in
september blijft in het voortschrijdend gemiddelde staan, ook al is de
achterstand in oktober ingehaald. Deze formule vangt dat drievoudig op:
het punt leest per leerdoel *of* je het aangetoond hebt, niet *wanneer*
(de stempel van §2.2) — wat je in de laatste week inhaalt, telt even zwaar
als wat je in de eerste week al kon, en een trage start laat in M geen
spoor na; de overtuigingen zelf zijn — anders dan een vastgezet cijfer —
altijd herzienbaar door nieuw bewijs; en de leerkracht bepaalt de
frequentie van de rapportpunten, zodat latere punten vroege punten
verdunnen.

### 3.2 Weinig vragen gekregen ≠ verdacht

De tutor stopt met doorvragen zodra beheersing vaststaat. Snelle, sterke
leerlingen hebben dus per leerdoel *weinig* metingen — dat is een gevolg
van goed presteren, geen gebrek aan bewijs tegen hen. Smalle bewijsmassa
is in deze formule daarom nooit een minpunt. De eerlijke
onzekerheidssignalen zijn andere: hoe *vers* het bewijs is (decay, §1.3,
opgevangen door §2.8) en *waar* het vandaan komt (toezicht, §2.7).

### 3.3 Wat niet werkt (en waarom)

- **Makkelijke vragen farmen.** Laag gewicht (× 0,6), voorwaarde 3 van
  §1.5, en de moeilijkheidsratel die op "makkelijk" blijft staan: je haalt
  er de 50 niet mee, laat staan de top.
- **Thuis laten voorzeggen (ChatGPT, klasgenoot).** Thuiskrediet is
  voorlopig; de eerstvolgende klassessie op dezelfde leerdoelen spreekt
  het tegen, en overtuigingen bewegen altijd mee met nieuw bewijs (§1.4).
- **De AI ompraten.** De verantwoordingstekst is geen input voor het
  getal: het punt komt uit de formule, en de leerkracht leest de
  verantwoording zelf na.
- **Stilvallen na een goede start.** Wat je aantoonde, blijft aangetoond
  (§2.2) — maar stilvallen brengt ook niets meer op: een volgende mijlpaal
  verwacht meer leerdoelen op een hoger niveau (§2.1, §2.5). Intussen
  blijven de opfrisvragen van §2.8 komen, want de tutor volgt wél de
  levende overtuiging.

---

## 4. Open parameters en de schaduwrun

De **structuur** hierboven ligt vast. De **getalwaarden** hieronder worden
geijkt met een schaduwrun: in periode 1 rekent de formule parallel mee met
de punten die de leerkracht op de klassieke manier geeft. Daarna worden de
parameters gefit op die vergelijking, vastgelegd in versie 1.1 van dit
document, en bevroren. Pas vanaf dan telt de formule echt mee.

| parameter | betekenis | v1-status |
| --- | --- | --- |
| C(k) | curve onder de 50 | voorlopig C(k) = k in de code; vorm na schaduwrun |
| w_u, w_d | gewicht uitbreiding vs. moeilijkheid boven de 50 | voorlopig 0,6 / 0,4 in de code (de waarden van bijlage B); definitief na schaduwrun (som = 1) |
| koppeling boven-50 | lineair met k, of hardere kerndrempel | voorlopig lineair met k in de code |
| s | gewichtsfactor bewijs onder toezicht | voorlopig s = 1,25 in de code; definitief na schaduwrun (bescheiden, s ≥ 1) |
| transfergewicht | grootte van het transfer-krediet (§2.8) | voorlopig het zwak-gewicht 0,5 (gerekend als gemiddeld) × s in de code; definitief na schaduwrun (klein; ≤ 0,5) |
| opfrisdrempel | hoe lang een beheerst leerdoel onaangeroerd moet zijn voor een opfrisvraag (§2.8) | voorlopig 30 dagen (de halve halveringstijd) in de code; definitief na schaduwrun |
| controlevraag | wanneer een nog niet aangetoond leerdoel uit een eerder subdoel een controlevraag krijgt (§2.8) | voorlopig 7 dagen zonder rechtstreekse vraag, μ van 0,70 tot 0,80, recent werk niveaugewogen ≥ 0,75, minstens 5 oefeningen ertussen in de code; te herbekijken na de volgende rapportronde |

Alle overige getallen in dit document (§1) zijn de vandaag werkende
waarden uit de app; bijlage A somt ze op met hun vindplaats in de code.

---

## 5. Versiebeheer

- Elke wijziging aan dit document krijgt een nieuw versienummer en een
  regel in de log hieronder.
- Wijzigingen gaan alleen in bij de start van een rapportperiode, worden
  vooraf in de klas toegelicht met de reden, en gelden nooit retroactief:
  punten die al op een rapport staan, worden nooit herrekend.

| versie | datum | wijziging |
| --- | --- | --- |
| 1.0 | 2026-09-02 | Eerste versie: structuur vastgelegd, parameters TBD tot na de schaduwrun. |
| 1.0.1 | 2026-09-02 | Geen structuurwijziging. §4 en bijlage A: de voorlopige codewaarde van s (1,25) vermeld en de stand van §2.7 in de code beschreven (#100). |
| 1.0.2 | 2026-09-02 | Geen structuurwijziging. Bijlage A: de drietraps-ratel van §2.5 staat nu in de code (`highestPositiveDifficulty` per leerdoel), met de oude-data-regel zoals §2.5 ze beschrijft (#103). |
| 1.0.3 | 2026-09-02 | Geen structuurwijziging. §2.8 transfer-krediet staat nu in de code: alleen bij een volledig juiste oplossing, alleen voor eerder beheerste leerdoelen uit een ander subdoel, gewicht voorlopig 0,5 × s (§4, bijlage A); de ratel van §2.5 beweegt er niet door (#101). |
| 1.0.4 | 2026-09-02 | Geen structuurwijziging. §2.8 opfrisvragen staan nu in de code: hoogstens één per sessie, bij het begin, over het langst onaangeroerde eerder beheerste leerdoel uit een ander subdoel (drempel voorlopig 30 dagen, §4); het antwoord telt als gewone meting van dat leerdoel, inclusief de ratel van §2.5, maar niet voor het kalibratieniveau (#102). |
| 1.0.6 | 2026-09-03 | Geen structuurwijziging. §1.2: signalen van de grader op een leerdoel uit een eerder subdoel tellen nu ook echt mee in de code (voorheen liet de tutor ze vallen): met de opgegeven sterkte, gerekend als gemiddeld, zonder de ratel van §2.5 of de voortgangsbalkjes te bewegen. §2.8 verduidelijkt dat een benoemd gat in oude leerstof via zo'n signaal loopt, niet via transfer-krediet (#108). |
| 1.0.7 | 2026-09-03 | Geen structuurwijziging. §2.4: M_start komt nu uit een exacte momentopname per leerdoel bij de periodestart (beheerst? en ratel, teruggerekend naar dat moment), geschreven door de app bij de eerste sessie na de periodestart, en volgt uit dezelfde formule als M_eind, verwacht niveau inbegrepen. De regel van v1.0.5 (fractie per subdoel uit de historiek, d_start = 0) blijft alleen als overgangsregel voor een periode zonder momentopname; het voorstel vermeldt welke van de twee gebruikt is (#110). |
| 1.0.8 | 2026-09-11 | Geen structuurwijziging. §2.8 en bijlage A: een opfrisvraag wacht niet langer altijd 30 dagen — een eerder beheerst leerdoel waarin een later signaal op een eerder subdoel (§1.2) een gat blootlegt, wordt bij de eerstvolgende sessiestart opgefrist (markering `regressedAt`, gewist door de eerstvolgende rechtstreekse meting of door een onrechtstreekse schrijving die de beheersing herstelt) en gaat voor op de gewoon-verouderde leerdoelen. Beschrijft gedrag dat sinds #112 in de code staat; de formule van deel 2 verandert niet (#113). |
| 1.0.9 | 2026-09-22 | Geen structuurwijziging. De app is nu ook het kanaal waarlangs je je rapport leest (#148–#151), dus afspraak 3 vooraan zegt "punten verschijnen pas op een rapportmoment, nooit live tijdens het werk" in plaats van "alleen op het rapport, nooit live in de app": de regel van #99 blijft dezelfde — een vrijgegeven, bevroren rapport *is* het rapportmoment — en §1.7 blijft onaangeroerd. Nieuw §2.9: wat je onder "Mijn rapporten" ziet (punt en verantwoording eerst, de berekening opgevouwen eronder, **berekend op [datum]** omdat de leerkracht zelf kiest wanneer gerekend wordt) en wat er bewust niet op staat (beurten klas/thuis, verouderde of nooit-bevraagde leerdoelen). §2.6: de leerkracht kan de verantwoording ook zelf herschrijven, ook na het aftekenen, zonder het getal te raken (#149). Bijlage A: de Rapporten-pagina en de berekening per klas, `justificationSource`, de container `reports` en de leerlingpagina. Omdat dit een afspraak herformuleert, gaat ze zoals §5 vraagt in bij het begin van een rapportperiode en wordt ze in de klas toegelicht (#152). |
| 1.0.10 | 2026-09-23 | Geen structuurwijziging aan M of P. §2.2 en §2.8: de decay van §1.3 telt niet langer mee in de puntberekening — "beheerst?" leest de overtuiging zoals ze opgeslagen staat. De conductor past decay nog steeds toe bij elke meting, dus wat wegvalt is alleen het verval tussen de laatste meting en het rapportmoment. Decay blijft onveranderd voor de opfrisvragen van §2.8. Reden: de tutor stopt met doorvragen zodra beheersing vaststaat, dus de sterkste leerling eindigt met de dunste bewijsmassa en verloor daardoor als eerste haar beheersing — het omgekeerde van wat §3.2 belooft. §2.4 zelf verandert niet, maar de momentopname leest om dezelfde reden de opgeslagen waarde in plaats van ze naar de periodestart terug te rekenen. |
| 1.0.11 | 2026-09-23 | Geen structuurwijziging. Bijlage A: een ouder opgeslagen leerdoel zonder trapinformatie (§2.5) leest de formule nog steeds als "gemiddeld" wanneer de ratel van §1.5 gezet was, maar de app schrijft die lezing niet meer weg als was ze gemeten — het veld blijft leeg tot een nieuw positief signaal het werkelijk gevraagde niveau vastlegt. Voordien versteende de gok bij de eerstvolgende beurt, en wie het leerdoel vóór v1.0.2 op moeilijk had aangetoond verloor dat blijvend, ten koste van d (#164). De formule van deel 2 en de punten veranderen niet; de getroffen data is eenmalig, buiten de app, uit de beurthistoriek hersteld. |
| 1.0.12 | 2026-09-23 | Geen structuurwijziging aan M of P. §2.2: "beheerst?" leest niet langer de overtuiging zoals ze nu staat, maar de eenmalige stempel die de app zet wanneer de drie voorwaarden van §1.5 voor het eerst samen gelden (`firstMasteredAt`, in de code sinds v1.0.3 als poort voor het transfer-krediet). De overtuiging zelf verandert niet en blijft de tutor sturen (vraagkeuze, vastgelopen-detectie, opfrisvragen); alleen het punt leest de stempel. Gevolg: een latere tegenvallende meting, een signaal op een eerder subdoel (§1.2) of decay kan een aangetoond leerdoel niet meer uit het punt halen — verder werken kan het punt nooit verlagen; §1.5, §2.4, §2.8 en §3.3 zeggen dat nu ook. Reden: de overtuiging is een voortschrijdend gemiddelde en hoort dat te zijn, maar omdat de tutor beheerste leerdoelen niet meer rechtstreeks bevraagt, bleef élk later negatief signaal onweersproken staan; de klasdata toonde leerlingen die vroeg fouten maakten en later niet meer, en toch onder de grens eindigden. Bijlage A: een leerdoel zonder stempel telt niet als beheerst; oudere opgeslagen leerdoelen krijgen hun stempel eenmalig, buiten de app, uit de beurthistoriek (#168). |
| 1.0.13 | 2026-09-23 | Geen structuurwijziging aan M of P; het punt verandert niet (het leest sinds v1.0.12 de stempel en de ratel, en geen van beide werd door deze signalen ooit geraakt). §1.2: een **negatief** signaal op een leerdoel uit een eerder subdoel is geen bewijs meer maar een aanleiding — het schrijft niets naar de overtuiging (geen β, geen decay-klok, geen nieuw document) en zet alleen de markering van §2.8 op een ooit beheerst leerdoel, zodat de eerstvolgende sessie er een opfrisvraag over stelt; die rechtstreekse meting telt met volle sterkte. Een positief signaal blijft wat het was. §2.8: de markering wordt alleen nog gewist door een rechtstreekse meting, niet meer door transfer-krediet of een positief signaal van opzij. Reden: zo'n negatief is het minst betrouwbare oordeel dat het systeem kent (afgeleid uit een antwoord over iets anders, zonder dat de vraag daarvoor ontworpen was) en treft per definitie leerdoelen die de tutor niet meer rechtstreeks bevraagt, dus het werd nooit meer getoetst; in de klasdata haalde het een zesmaal op rij aangetoond leerdoel een week later blijvend van 0,82 naar 0,65, en het stuurde zo de vraagkeuze, de vastgelopen-detectie en de voortgangsbalkjes op een nooit gecontroleerd oordeel (#167). Bijlage A zegt hoe de tutor het nu verwerkt; bestaande overtuigingen van leerlingen op de nieuwe build worden eenmalig, buiten de app, uit de beurthistoriek herspeeld zonder deze signalen. |
| 1.0.14 | 2026-09-23 | Geen structuurwijziging aan M of P, maar de metingen eronder veranderen: de moeilijkheidsfactor van §1.2 is niet langer symmetrisch. Een positief signaal weegt zoals voorheen (makkelijk × 0,6, gemiddeld × 1,0, moeilijk × 1,4); een negatief signaal krijgt het spiegelbeeld (makkelijk × 1,4, gemiddeld × 1,0, moeilijk × 0,6). Daardoor is μ niveaubewust: dezelfde grens van 0,80 is ongeveer 90% juist op makkelijk, 80% op gemiddeld en ongeveer 63% op moeilijk; een promotie op de kalibratieladder (§1.6) verandert μ nauwelijks meer en kan je dus niet meer uit je beheersing duwen, en "vastgelopen" (§1.7) leest het niveau vanzelf mee. De "belangrijk gevolg"-alinea van §1.2 keert daarmee om; §2.5 zegt dat moeilijkheid voorlopig twee keer telt (via μ en via de ratel), te herbekijken bij de herziening van deel 2. Reden: de kalibratie parkeert een leerling bewust waar hij 40–75% scoort, terwijl beheersing μ ≥ 0,80 vraagt en "vastgelopen" μ < 0,75 is — met een symmetrische factor was μ gewoon het scorepercentage, zodat een goed gekalibreerde leerling die lang genoeg bevraagd werd per ontwerp onder de grens eindigde (in de klasdata: 154 vragen op moeilijk, 65% juist, en toch "vastgelopen" en niet beheerst). De bestaande overtuigingen worden eenmalig, buiten de app, uit de beurthistoriek herspeeld met de nieuwe factor (alleen α, β en de stempel van §2.2), ná de verplichte client-update en vóór deze versie in gebruik gaat (#169). |
| 1.0.15 | 2026-09-23 | Geen structuurwijziging aan M of P. §1.7: het voortgangsbalkje van een subdoel blijft ook na het doorschuiven de echte fractie beheerste leerdoelen tonen. Voorheen zette de app de opgeslagen fractie hard op 1,0 zodra een subdoel doorschoof, ook wanneer dat met een vastgelopen leerdoel gebeurde: het balkje stond dan op 100% terwijl het punt, dat per leerdoel meet, het gat wél zag. "Afgerond" is nu een eigen stempel op het voortgangsdocument (`advancedAt`), waarop de tutor de keuze van het volgende subdoel en de app het vinkje baseren; de fractie zelf beweegt er niet door. Gevolg voor §2.4: de overgangsregel van v1.0.5 leest diezelfde fractie uit de voortgangshistoriek en kende zo aan élk leerdoel van een doorgeschoven subdoel 1,0 toe, het vastgelopen inbegrepen, waardoor M_start te hoog uitkwam en de groei G op 0 viel; vanaf nu staat in de historiek de echte fractie. Eerder opgeslagen historiek wordt niet herschreven (#161). |
| 1.0.17 | 2026-09-24 | Geen structuurwijziging aan M of P. §2.8: nieuw mechanisme, de **controlevraag**. Een leerdoel uit een eerder subdoel dat je nog niet aantoonde, dat net onder de grens staat (μ vanaf 0,70 en onder 0,80) en dat al een week niet meer rechtstreeks bevraagd is, krijgt af en toe één vraag midden in het oefenen, zolang je recente werk op je niveau goed gaat (niveaugewogen ≥ 0,75 over je laatste tien antwoorden), met minstens vijf gewone oefeningen tussen twee vragen over een ander subdoel. Het antwoord telt als gewone meting van dat leerdoel, dus een juist antwoord kan de stempel van §2.2 alsnog opleveren; het telt niet voor je kalibratieniveau en raakt de voortgangsbalkjes niet. Reden: in de eerste rapportronde paste de leerkracht tien van de vijftien rapporten aan voor precies zulke leerdoelen (μ 0,74–0,80, op moeilijk bevraagd, daarna 12 tot 19 dagen niet meer terwijl de leerling later werk goed deed); de tutor vroeg er nooit meer naar, en decay trekt een overtuiging nooit over de grens, dus de leerling kon de stempel niet meer zelf verdienen (#187). §4 en bijlage A: de voorlopige waarden en de klok `lastProbedAt`. |
| 1.0.16 | 2026-09-23 | **Structuurwijziging aan P.** §2.6: het puntvoorstel is de beheersingsscore, P = M; de groeiscore G (§2.4) vervalt, en daarmee M_start, de momentopname bij de periodestart (v1.0.7) en de overgangsregel uit de voortgangshistoriek (v1.0.5). §4: de open parameter w_M / w_G vervalt; bijlage A en B volgen. §2.9: "Mijn rapporten" toont M, k, u en d, geen beginscore of groei meer. §3.1 en §3.3 steunen niet langer op G: een trage start laat in M geen spoor na omdat de stempel van §2.2 niet vraagt wanneer je iets aantoonde. Reden: de app rekende 60/40 met G, terwijl de evaluatie buiten de app (regelset `1.0.10-eval1`, kader 4) al P = M schreef in dezelfde puntvoorstellen — wie in de app op "Opnieuw berekenen" drukte, kreeg een ander getal dan wat er stond; en G hing af van een momentopname die het ene keer exact en het andere keer een schatting was. De container `period_start_snapshots` wordt niet meer geschreven of gelezen; oude voorstellen en rapporten met `mStart` en `g` blijven leesbaar en worden niet herschreven (#191). |
| 1.0.5 | 2026-09-02 | Geen structuurwijziging. Deel 2 staat nu in de code (#99): mijlpalen met Angoff-splitsing en verwacht niveau (§2.1), het puntvoorstel P uit M en G met de voorlopige gewichten van bijlage B (§4), de verantwoording door de AI rond het vaste getal, en de aanpassing en aftekening door de leerkracht. Nieuw in §2.4: de regel waarmee M_start uit de opgeslagen historiek gelezen wordt (fractie per subdoel op de periodestart, toegekend aan elk leerdoel; d_start = 0). Bijlage A: de nieuwe constanten en hun vindplaats. |

---

## Bijlage A — de werkende constanten uit de app

Voor wie het narekent of implementeert: de waarden van §1 zoals ze vandaag
in de code staan. Eén bronmodule bevat ze allemaal:
`lib/services/tutor/policy_constants.dart`; de bijhorende wiskunde staat in
`lib/services/tutor/belief_math.dart`, de opslag per leerdoel in
`lib/services/student_state/lo_belief.dart` en het ontwerp in
`docs/CONDUCTOR_POLICY.md` (§3–§5) en `docs/STUDENT_MODEL.md`.

| constante | waarde | betekenis (§) |
| --- | --- | --- |
| prior | (1, 1) | startovertuiging per leerdoel (§1.1) |
| gewicht sterk / matig / zwak | 2,0 / 1,0 / 0,5 | basisgewicht per signaal (§1.2) |
| moeilijkheidsfactor, positief signaal | 0,6 / 1,0 / 1,4 | makkelijk / gemiddeld / moeilijk (§1.2) |
| moeilijkheidsfactor, negatief signaal | 1,4 / 1,0 / 0,6 | makkelijk / gemiddeld / moeilijk — het spiegelbeeld, sinds v1.0.14 (§1.2) |
| vervolgvraag-cap | 0,5, als "gemiddeld" | maximumgewicht vervolgvragen (§1.2) |
| toezichtfactor s | × 1,25 (voorlopig, §4) | bewijs binnen een Anchor-sessie; thuis × 1,0 (§2.7) |
| transfer-krediet | 0,5 (zwak, als gemiddeld) × s, alleen op α (voorlopig, §4) | eerder beheerst leerdoel uit een ander subdoel, correct gebruikt in een juiste oplossing (§2.8) |
| opfrisdrempel | 30 dagen zonder schrijving (voorlopig, §4) | wanneer een eerder beheerst leerdoel uit een ander subdoel een opfrisvraag krijgt — een leerdoel dat voor controle gemarkeerd is (`regressedAt`, zie onder) komt eerder aan de beurt; hoogstens één per sessie (§2.8) |
| controlevraag: klok | 7 dagen zonder rechtstreekse vraag (`lastProbedAt`; voorlopig, §4) | wanneer een nog niet aangetoond leerdoel uit een eerder subdoel een controlevraag kan krijgen (§2.8) |
| controlevraag: band | 0,70 ≤ μ < 0,80 (voorlopig, §4) | "net onder de grens", met decay zoals de tutor ze leest (§2.8) |
| controlevraag: recent werk | ≥ 0,75, niveaugewogen over een vol kalibratievenster (voorlopig, §4) | juist × positieve factor, half/fout × negatieve factor van §1.2 (§2.8) |
| controlevraag: tussenruimte | ≥ 5 gewone oefeningen (voorlopig, §4) | tussen twee vragen over een ander subdoel, controle- of opfrisvraag (§2.8) |
| halveringstijd decay | 60 dagen | vergeten, lazy bij lezing (§1.3) |
| bewijsplafond | α + β ≤ 20 | krimp-dan-toevoegen (§1.4) |
| beheersing: μ-drempel | 0,8 | voorwaarde 1 (§1.5) |
| beheersing: bewijsminimum | α + β ≥ 4 | voorwaarde 2 (§1.5) |
| kalibratievenster | 10 antwoorden | §1.6 |
| promotie | ≥ 4 op niveau, ≥ 75% juist | §1.6 |
| demotie | ≥ 3 op niveau, ≥ 60% fout/half | §1.6 |
| per-LO trapverlaging | 2 sterk-fout op niveau, zonder tussentijds positief | §1.6 |
| vastgelopen (klassiek) | α + β ≥ 8 én μ < 0,6 | telt voor doorstroming, niet als beheerst (§1.7) |
| vastgelopen (verzadigd) | α + β ≥ 18 én μ < 0,75 | idem, bij vol bewijsplafond (§1.7) |
| C(k) | k | curve onder de 50 (§2.3; voorlopig, §4) |
| w_u / w_d | 0,6 / 0,4 | uitbreiding vs. moeilijkheid boven de 50 (§2.3; voorlopig, §4) |
| verouderd-drempel | 30 dagen (= opfrisdrempel) | wanneer een mijlpaal-leerdoel in het voorstel als "verouderd" gemeld wordt (§3.2) |

De constanten van deel 2 staan sinds v1.0.5 in
`lib/services/grading/grade_formula.dart` (`GradingConstants`), de
berekening zelf ook daar (sinds v1.0.16 P = M, `proposalScore`); het
lezen van de leerlingdata en de opslag in
`lib/services/grading/grade_proposal_service.dart`; de tekst van de verantwoording in `lib/services/grading/grade_justification.dart`.
Elk opgeslagen voorstel draagt het versienummer van dit document waarmee
het berekend werd (`formulaVersion`); een afgetekend voorstel wordt nooit
herrekend (§5).

De drietraps-moeilijkheidsratel van §2.5 staat sinds v1.0.2 in de code:
per leerdoel bewaart de app `highestPositiveDifficulty` (makkelijk /
gemiddeld / moeilijk), gezet op de moeilijkheid die *werkelijk gevraagd*
werd bij elk positief signaal, alleen omhoog, nooit aangepast door een
kalibratiewijziging en niet door vervolgvragen (§1.2). Oudere opgeslagen
leerdoelen zonder dit veld leest de *formule* als "gemiddeld" wanneer de
ratel van §1.5 gezet was, anders als "nog niets aangetoond" — die lezing
gebeurt alleen bij het berekenen en wordt sinds v1.0.11 niet meer
weggeschreven: het veld blijft leeg tot een nieuw positief signaal het
werkelijk gevraagde niveau vastlegt (#164). Voordien schreef de app de
lezing "gemiddeld" bij de eerstvolgende beurt weg alsof ze gemeten was,
waardoor een leerdoel dat vóór v1.0.2 op moeilijk was aangetoond blijvend
op gemiddeld bleef staan; die data is eenmalig, buiten de app, uit de
beurthistoriek hersteld. De app zelf vult niets met terugwerkende kracht
in. De formule van deel 2 leest dit veld; de tutor zelf gebruikt het niet.
Van §2.8 staat sinds v1.0.3 het
**transfer-krediet** in de code: de grader noemt bij een juiste oplossing
de leerdoelen uit andere subdoelen die de code correct gebruikt
(`transferLOs`), en de tutor kent alleen aan leerdoelen die ooit beheerst
raakten (`firstMasteredAt` per leerdoel; oudere opgeslagen leerdoelen
zonder dat veld gelden als "beheerst bij de laatste rechtstreekse
meting" wanneer hun opgeslagen α, β en ratel aan §1.5 voldoen) een
zwak-positief signaal toe, gerekend als gemiddeld en gewogen met s; het
wordt op het beurtrecord vermeld. Sinds v1.0.12 leest ook de **formule
van deel 2** die stempel als "beheerst?" (§2.2; `LoGradeInput.fromBelief`
in `grade_formula.dart`, de enige lezer van de leerlingdata voor het punt,
): gezet, dan beheerst; niet gezet, dan
niet — ook wanneer de opgeslagen α, β en ratel vandaag aan §1.5 voldoen.
De oude-data-regel van daarnet is dus een regel voor de tutor (transfer,
opfrissen), niet voor het punt: ze is een lezing van de levende
overtuiging, en precies die mag het punt niet meer sturen. Leerdoelen die
vóór v1.0.3 of door een oudere client zonder het veld (#165) geschreven
zijn, krijgen hun stempel eenmalig, buiten de app, uit de beurthistoriek
(`loStatusAfter[].mastered` is letterlijk de beslissing van de tutor op
dat moment), vóór deze versie in gebruik gaat; de app zelf vult niets in
(#168). Sinds v1.0.6 verwerkt de tutor ook de
**signalen op een eerder subdoel** van §1.2 (voorheen liet hij ze
vallen), sinds v1.0.13 alleen nog de positieve als bewijs: met de sterkte
van de grader, gerekend als gemiddeld en gewogen met s, zonder ratel,
teller of voortgangsbalkje te bewegen. Een negatief signaal op een eerder
subdoel schrijft niets naar de overtuiging (ook geen nieuw document voor
een nooit bevraagd leerdoel) en zet alleen de markering `regressedAt` op
een ooit beheerst leerdoel (zie onder); elk verwerkt signaal staat met
zijn subdoel op het beurtrecord (`appliedSignals`), elk gemarkeerd
leerdoel onder `reviewFlags`. De **opfrisvragen** van §2.8 staan
sinds v1.0.4 in de code: bij het begin van een sessie kiest de tutor
hoogstens één eerder beheerst leerdoel (`firstMasteredAt`, met dezelfde
oude-data-regel als hierboven) uit een ander subdoel van het hoofddoel
waarvan `lastUpdatedAt` minstens 30 dagen oud is — het oudste eerst — en
stelt daarover de zachtste vraagvorm voor dat soort leerdoel op je
huidige niveau. Sinds v1.0.8 telt daarnaast een leerdoel met de markering
`regressedAt` als aan de beurt, ongeacht `lastUpdatedAt`: de tutor zet
die markering wanneer een negatief signaal op een eerder subdoel (§1.2)
een ooit beheerst leerdoel treft — sinds v1.0.13 ongeacht wat de
overtuiging doet, want het signaal raakt ze niet meer (voordien alleen
wanneer het ze onder de voorwaarden 1 en 2 van §1.5 liet zakken); een
reeds gezette markering blijft staan, zodat de oudste vraag eerst komt.
Ze wordt gewist bij elke rechtstreekse meting van dat leerdoel (de
opfrisvraag zelf, goed of fout, of een gewone vraag zodra het subdoel
weer actief is); transfer-krediet en een positief signaal van opzij laten
ze staan (tot v1.0.13 wisten die ze wanneer ze de overtuiging weer aan
die voorwaarden lieten voldoen). Gemarkeerde leerdoelen gaan voor op
verouderde (oudste markering eerst), daarna het oudste `lastUpdatedAt`,
bij gelijke stand de laagste μ; het beurtrecord vermeldt welke van de
twee regels het leerdoel koos. Het antwoord wordt verwerkt als een gewone meting van
dat leerdoel (gewicht van §1.2, herkomst van §2.7, ratel van §2.5), telt
niet mee voor het kalibratieniveau van §1.6, en het beurtrecord markeert
de beurt als opfrisvraag (`isWarmUp`). De **controlevragen** van §2.8
staan sinds v1.0.17 in de code (`Conductor._planRecheck`, de regels in
`_recheckRuleFor`): per leerdoel bewaart de app sindsdien
`lastProbedAt`, het moment van de laatste rechtstreekse meting — de
vraag over dat leerdoel, of een signaal erop terwijl zijn eigen subdoel
actief is; een vervolgvraag, een signaal van opzij of transfer-krediet
laten het staan. Een ouder opgeslagen leerdoel zonder dat veld leest
`lastUpdatedAt` wanneer het ooit zelf bevraagd werd (`lastQuestionType`
gezet), anders geldt het als nooit rechtstreeks bevraagd. Het antwoord
wordt verwerkt als een gewone meting van dat leerdoel, net als een
opfrisvraag, en het beurtrecord markeert de beurt als controlevraag
(`isRecheck`) en noemt het subdoel waar je op dat moment mee bezig was
(`activeSubgoalId`). Deel 2 staat sinds v1.0.5 in de
code: de leerkracht legt mijlpalen vast (subdoelen, per leerdoel kern of
uitbreiding, verwacht niveau, periode), berekent per leerling het voorstel —
per leerdoel de stempel van §2.2 en de ratel van §2.5, zoals ze op het
moment van berekenen opgeslagen staan — vraagt de
verantwoording aan de AI (die het getal als vaststaand feit meekrijgt,
samen met de statusrapporten uit de periode en het verloop per subdoel),
past aan en tekent af. Het voorstel meldt ook de eerlijke
onzekerheidssignalen van §3.2: hoeveel mijlpaal-leerdoelen al langer dan
30 dagen niet meer geschreven zijn (of nooit bevraagd), en hoeveel beurten
in de periode onder toezicht dan wel thuis gebeurden. Sinds v1.0.9 staat de
rest van de rapportketen erbij: de leerkracht rekent, verantwoordt, past aan
en tekent af op de Rapporten-pagina
(`lib/features/reports/reports_page.dart`, de berekening voor een hele klas
in `lib/services/grading/report_batch.dart`) — het "moment van berekenen"
is het moment waarop die pagina de berekening start, niet de vervaldatum van
de mijlpaal; de verantwoording is daar ook met de hand herschrijfbaar, vóór
en na het aftekenen (`justificationSource` = `ai` of `edited`: alleen
herkomst, nooit input voor het getal, §3.3); en het vrijgeven van een
mijlpaal schrijft per leerling een bevroren kopie in de container `reports`
(`lib/services/grading/published_report.dart` en
`published_report_service.dart`) met precies de velden van §2.9, dus zonder
`supervisedTurns`/`homeTurns` en zonder `staleLoCount`/`neverProbedCount`.
De leerling leest die kopie — en alleen de eigen kopie — in
`lib/features/my_reports/my_reports_page.dart`; een herschreven
verantwoording overschrijft ze (`updatedAt` beweegt, `publishedAt` niet)
zonder het punt te raken. Van §2.7 staat de weging in de code
(elke beurt krijgt een herkomst *thuis* of *onder toezicht*, en de factor
s weegt mee), maar de koppeling met de Anchor-sessieregistratie nog niet:
tot die er is, telt elke beurt als thuis en verandert s niets.

## Bijlage B — rekenvoorbeeld

Mijlpaal: 8 kernleerdoelen, 3 uitbreidingsleerdoelen, verwacht niveau
*gemiddeld*. Ter illustratie met voorbeeldwaarden (géén vastgelegde
parameters): C(k) = k, w_u = 0,6, w_d = 0,4.

**Leerling A**, op het rapportmoment:
kern 8/8 beheerst op niveau (k = 1), uitbreiding 2/3 (u = 0,667), en 4 van
de 10 beheerste leerdoelen op *moeilijk* aangetoond (d = 0,4).

```
M = 50·1 + 50·1·(0,6·0,667 + 0,4·0,4) = 50 + 28,0 = 78,0
P = M = 78,0  →  voorstel 78
```

**Leerling B** kwam van ver. Op het rapportmoment: kern 7/8
(k = 0,875), uitbreiding 1/3 (u = 0,333), niets op moeilijk (d = 0).

```
M = 50·0,875 + 50·0,875·(0,6·0,333 + 0,4·0) = 43,75 + 8,75 = 52,5
P = M = 52,5  →  voorstel 53
```

B haalt ondanks de trage start een voldoende — niet uit medelijden, maar
omdat B de kern nagenoeg beheerst; waar B vandaan kwam, telt niet mee,
in de ene noch de andere richting (§3.1). A's hogere punt komt waar het
vandaan hoort te komen: meer beheersing, uitbreiding, en aantonen op
moeilijk.

---

*Voor de implementatie: dit document is de spec voor de issues #99
(puntvoorstel + verantwoording), #100 (bewijsherkomst/Anchor), #101
(transfer-krediet), #102 (opfrisvragen) en #103 (drietraps-ratel). Bij
tegenspraak tussen code en dit document wordt de afwijking gemeld en
beslist de leerkracht welke kant aangepast wordt — stilzwijgend afwijken
mag niet.*
