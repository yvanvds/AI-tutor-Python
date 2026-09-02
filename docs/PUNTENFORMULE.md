# Puntenformule — hoe je rapportcijfer tot stand komt

**Versie 1.0 (concept)** — nog niet van kracht; wordt eerst getoetst in een
schaduwperiode (zie §4). Laatste wijziging: 2026-09-02.

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
   voorstel aanpassen en zet de handtekening. Punten verschijnen alleen op
   het rapport, nooit live in de app.

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
de vraag:

| moeilijkheid | factor |
| --- | --- |
| makkelijk | × 0,6 |
| gemiddeld | × 1,0 |
| moeilijk | × 1,4 |

Het resultaat komt bij α (positief signaal) of bij β (negatief signaal).
Een sterk-positief antwoord op een moeilijke vraag telt dus voor
2,0 × 1,4 = 2,8 bij α.

> **Belangrijk gevolg.** De moeilijkheidsfactor geldt *symmetrisch*: ook een
> fout antwoord op een moeilijke vraag weegt × 1,4. Daardoor bepaalt de
> moeilijkheid hoe *snel* je bewijs opbouwt, maar niet waar je gemiddelde μ
> naartoe gaat: twee leerlingen die elk 80% juist antwoorden, de ene op
> makkelijke en de andere op moeilijke vragen, komen op *dezelfde* μ uit.
> Moeilijkheid is dus onzichtbaar in μ — en daarom telt ze in de
> puntformule apart mee, via een eigen mechanisme (§2.5).

Antwoorden op **vervolgvragen** (de doorvraagjes na een gewoon antwoord)
tellen ook mee, maar afgetopt op sterkte *zwak* (0,5) en gerekend als
moeilijkheid *gemiddeld*. Ze zijn echt bewijs, maar de vraag was niet als
gekalibreerde meting ontworpen.

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
(voorwaarden 1 en 2); alleen de ratel van voorwaarde 3 is blijvend.

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
niet-beheerst. Het balkje van een hoofddoel is het gemiddelde van zijn
subdoelen.

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

- **beheerst?** — de drie voorwaarden van §1.5, na decay (dus de verse
  stand; §2.8 zorgt dat "vers" ook eerlijk is);
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

### 2.4 Groeiscore G

De beheersingsscore alleen zou een trage starter dubbel straffen: het
lage beginpunt blijft in het voortschrijdend gemiddelde staan, ook als de
achterstand volledig is ingehaald. Daarom telt naast de *stand* ook de
*beweging*:

```
G = (M_eind − M_start) / (100 − M_start)      begrensd op [0, 1]
```

met M_start de beheersingsscore aan het begin van de periode (uit de
opgeslagen historiek) en M_eind die op het rapportmoment. G meet **welk
deel van jouw persoonlijke kloof naar de mijlpaal je deze periode hebt
gedicht** — wie van ver komt en veel inhaalt, scoort hier hoog, precies
even hoog als wie van dichtbij hetzelfde relatieve deel dicht. Stond je
aan het begin al op 100, dan is G = 1 (er viel geen kloof meer te
dichten). Achteruitgang (M_eind < M_start) telt als G = 0, niet negatief:
de gezakte M_eind weegt al in de beheersingscomponent.

### 2.5 De rol van moeilijkheid

Moeilijkheid verdient een eigen plek in het punt — maar via het juiste
signaal.

- **Niet via μ:** door de symmetrische moeilijkheidsfactor (§1.2) is
  moeilijkheid onzichtbaar in de gemiddelden.
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
P = w_M · M  +  w_G · (100 · G)
```

De gewichten w_M + w_G = 1 kunnen per periode verschillen en staan vooraf
vast in dit document (§4). In vroege periodes weegt groei zwaarder (het
eerste jaar is een ijkjaar en beginposities verschillen sterk); later
verschuift het gewicht richting beheersing, omdat het rapport uiteindelijk
beheersing van de leerstof certificeert.

Het voorstel P wordt afgerond op een geheel punt en gaat, samen met de
verantwoording, naar de leerkracht. De verantwoording wordt door de AI
geschreven op basis van je statusrapporten en je voortgangshistoriek en
legt uit *waarom* de cijfers zijn wat ze zijn — ze bevat geen eigen
oordeel over het punt. De leerkracht kan het voorstel aanpassen voor
context die het systeem niet ziet, en tekent af. Het getekende punt is
het rapportpunt.

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

Twee mechanismen zorgen dat de decay van §1.3 op het rapportmoment
niemand oneerlijk raakt:

- **Transfer-krediet.** Oudere leerdoelen zitten vaak impliciet in nieuw
  werk: wie in december een while-lus schrijft, gebruikt daarin nog
  steeds `print()` en variabelen. Wanneer de grader ziet dat je een
  eerder beheerst leerdoel uit een *ander* subdoel correct gebruikt in een
  werkende oplossing van een nieuwe oefening, krijgt dat oude leerdoel een
  klein positief signaal: de decay-klok wordt teruggezet én de overtuiging
  stijgt licht. Dit werkt alleen positief (een foute of half-juiste
  oplossing telt niet tegen het oude leerdoel — en levert het ook niets
  op), alleen voor leerdoelen die eerder door directe bevraging beheerst
  raakten (de app onthoudt per leerdoel wanneer dat voor het eerst
  gebeurde), en met klein gewicht — de Beta-wiskunde zorgt zelf voor
  afnemende meeropbrengst. De moeilijkheidsratel van §2.5 beweegt er
  niet door: de moeilijkheid van de oefening was voor het nieuwe
  leerdoel gekozen, niet voor het oude.
- **Opfrisvragen.** Leerdoelen die *niet* vanzelf in nieuwe leerstof
  terugkeren en lang niet bevraagd zijn, krijgen af en toe een korte
  opfrisvraag in de gewone oefenflow. Dat is meteen goede didactiek
  (ophaaloefening) én houdt de meting vers.

Samen betekenen ze: wie vroeg klaar was en gewoon is blijven werken,
staat er op het rapportmoment vers en terecht goed voor.

---

## 3. Eerlijkheid en spelregels

### 3.1 Waarom een trage start je rapport niet blijft achtervolgen

Het klassieke probleem van permanente evaluatie: een laag punt in
september blijft in het voortschrijdend gemiddelde staan, ook al is de
achterstand in oktober ingehaald. Deze formule vangt dat drievoudig op:
de groeiscore G normaliseert op je *eigen* beginpositie (§2.4), de
overtuigingen zelf zijn — anders dan een vastgezet cijfer — altijd
herzienbaar door nieuw bewijs, en de leerkracht bepaalt de frequentie van
de rapportpunten, zodat latere punten vroege punten verdunnen.

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
- **Stilvallen na een goede start.** Decay laat beheersing eerlijk
  wegzakken; de opfrisvragen geven je de kans om te tonen dat het er nog
  is — wie ook dat laat liggen, zakt terecht.

---

## 4. Open parameters en de schaduwrun

De **structuur** hierboven ligt vast. De **getalwaarden** hieronder worden
geijkt met een schaduwrun: in periode 1 rekent de formule parallel mee met
de punten die de leerkracht op de klassieke manier geeft. Daarna worden de
parameters gefit op die vergelijking, vastgelegd in versie 1.1 van dit
document, en bevroren. Pas vanaf dan telt de formule echt mee.

| parameter | betekenis | v1-status |
| --- | --- | --- |
| C(k) | curve onder de 50 | voorlopig C(k) = k; vorm na schaduwrun |
| w_u, w_d | gewicht uitbreiding vs. moeilijkheid boven de 50 | TBD (som = 1) |
| koppeling boven-50 | lineair met k, of hardere kerndrempel | voorlopig lineair met k |
| w_M, w_G per periode | mix beheersing/groei | TBD; vroege periodes groei-zwaarder |
| s | gewichtsfactor bewijs onder toezicht | voorlopig s = 1,25 in de code; definitief na schaduwrun (bescheiden, s ≥ 1) |
| transfergewicht | grootte van het transfer-krediet (§2.8) | voorlopig het zwak-gewicht 0,5 (gerekend als gemiddeld) × s in de code; definitief na schaduwrun (klein; ≤ 0,5) |

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
| moeilijkheidsfactor | 0,6 / 1,0 / 1,4 | makkelijk / gemiddeld / moeilijk, symmetrisch (§1.2) |
| vervolgvraag-cap | 0,5, als "gemiddeld" | maximumgewicht vervolgvragen (§1.2) |
| toezichtfactor s | × 1,25 (voorlopig, §4) | bewijs binnen een Anchor-sessie; thuis × 1,0 (§2.7) |
| transfer-krediet | 0,5 (zwak, als gemiddeld) × s, alleen op α (voorlopig, §4) | eerder beheerst leerdoel uit een ander subdoel, correct gebruikt in een juiste oplossing (§2.8) |
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

De drietraps-moeilijkheidsratel van §2.5 staat sinds v1.0.2 in de code:
per leerdoel bewaart de app `highestPositiveDifficulty` (makkelijk /
gemiddeld / moeilijk), gezet op de moeilijkheid die *werkelijk gevraagd*
werd bij elk positief signaal, alleen omhoog, nooit aangepast door een
kalibratiewijziging en niet door vervolgvragen (§1.2). Oudere opgeslagen
leerdoelen zonder dit veld lezen als "gemiddeld" wanneer de ratel van §1.5
gezet was, anders als "nog niets aangetoond" — er wordt niets met
terugwerkende kracht ingevuld. De formule van deel 2 leest dit veld; de
tutor zelf gebruikt het niet. Van §2.8 staat sinds v1.0.3 het
**transfer-krediet** in de code: de grader noemt bij een juiste oplossing
de leerdoelen uit andere subdoelen die de code correct gebruikt
(`transferLOs`), en de tutor kent alleen aan leerdoelen die ooit beheerst
raakten (`firstMasteredAt` per leerdoel; oudere opgeslagen leerdoelen
zonder dat veld gelden als "beheerst bij de laatste rechtstreekse
meting" wanneer hun opgeslagen α, β en ratel aan §1.5 voldoen) een
zwak-positief signaal toe, gerekend als gemiddeld en gewogen met s; het
wordt op het beurtrecord vermeld. De **opfrisvragen** van §2.8 zijn op
datum van v1.0.3 nog specificatie, geen werkende code; hun implementatie
volgt dit document. Van §2.7 staat de weging in de code
(elke beurt krijgt een herkomst *thuis* of *onder toezicht*, en de factor
s weegt mee), maar de koppeling met de Anchor-sessieregistratie nog niet:
tot die er is, telt elke beurt als thuis en verandert s niets.

## Bijlage B — rekenvoorbeeld

Mijlpaal: 8 kernleerdoelen, 3 uitbreidingsleerdoelen, verwacht niveau
*gemiddeld*. Ter illustratie met voorbeeldwaarden (géén vastgelegde
parameters): C(k) = k, w_u = 0,6, w_d = 0,4, w_M = 0,6, w_G = 0,4.

**Leerling A** startte de periode op M_start = 40. Op het rapportmoment:
kern 8/8 beheerst op niveau (k = 1), uitbreiding 2/3 (u = 0,667), en 4 van
de 10 beheerste leerdoelen op *moeilijk* aangetoond (d = 0,4).

```
M = 50·1 + 50·1·(0,6·0,667 + 0,4·0,4) = 50 + 28,0 = 78,0
G = (78,0 − 40) / (100 − 40) = 0,633
P = 0,6·78,0 + 0,4·63,3 = 72,1  →  voorstel 72
```

**Leerling B** kwam van ver: M_start = 10. Op het rapportmoment: kern 7/8
(k = 0,875), uitbreiding 1/3 (u = 0,333), niets op moeilijk (d = 0).

```
M = 50·0,875 + 50·0,875·(0,6·0,333 + 0,4·0) = 43,75 + 8,75 = 52,5
G = (52,5 − 10) / (100 − 10) = 0,472
P = 0,6·52,5 + 0,4·47,2 = 50,4  →  voorstel 50
```

B haalt ondanks de trage start een voldoende — niet uit medelijden, maar
omdat B aantoonbaar bijna de helft van een grote persoonlijke kloof heeft
gedicht én de kern nagenoeg beheerst. A's hogere punt komt waar het
vandaan hoort te komen: meer beheersing, uitbreiding, en aantonen op
moeilijk.

---

*Voor de implementatie: dit document is de spec voor de issues #99
(puntvoorstel + verantwoording), #100 (bewijsherkomst/Anchor), #101
(transfer-krediet), #102 (opfrisvragen) en #103 (drietraps-ratel). Bij
tegenspraak tussen code en dit document wordt de afwijking gemeld en
beslist de leerkracht welke kant aangepast wordt — stilzwijgend afwijken
mag niet.*
