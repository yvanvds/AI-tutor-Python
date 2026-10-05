# Roadmap: doelen na "Lijsten en tuples"

Voorstel van 5 oktober 2026 voor de doelen die op doel 4 volgen. Dit
document is het naslagwerk bij het uitwerken van elk volgend doel: wat het
doel moet zijn, in welke volgorde, en welke afspraken onderweg gemaakt zijn.
Het is geen contract. Pas het aan wanneer een doel bij het uitwerken anders
uitvalt; `OVERVIEW.md` blijft de bron voor wat er effectief staat.

Bron van veel ideeën: de cursus van vorig schooljaar,
<https://yvanvds.github.io/CursusPython/main/intro.html>.

## Waar het om gaat

Het doel is niet leren software schrijven. Het gaat om algoritmisch denken,
om ontdekken hoe een wiskundig probleem met een computer anders aangepakt
wordt dan in de les wiskunde, en om zien hoe een beetje programmeren helpt
bij onderzoek in wetenschappen en economie.

Drie keuzes lopen door alle doelen:

- **Eerst simuleren of benaderen, dan vergelijken met de wiskundeles.**
  Leerlingen schatten een kans, een nulpunt of een oppervlakte met een lus
  en leggen die naast de formule.
- **Eerst zelf bouwen, dan de bibliotheek.** Een gemiddelde, een trendlijn
  of de trapeziumregel schrijven ze eerst zelf. Numpy is daarom uitgesteld.
- **Elke context in twee smaken.** De teachingTips laten de AI afwisselen
  tussen economie en wetenschappen, zodat beide klassen zich herkennen.

## Kernpad

| # | Doel | Status |
|---|---|---|
| 5 | Functies (`functies`) | live sinds 5 oktober 2026 |
| 6 | Toeval en simulatie (`toeval-simulatie`) | doelbestand en lessen geschreven, nog niet live |
| 7 | Grafieken maken | idee |
| 8 | Vergelijkingen oplossen door te zoeken | idee |
| 9 | De wereld in tijdstappen | idee |
| 10 | Dictionaries en gestructureerde data | idee |
| 11 | Echte data onderzoeken | idee |

### 5. Functies

Uitgewerkt; zie `goals/05-functies.json` en `lessons/05-functies/`. Een
functie is "iets erin, iets eruit": parameters en `return` vanaf het eerste
voorbeeld, nooit `print` of `input` in een functie. Een functie die met
turtle tekent is de enige uitzondering.

### 6. Toeval en simulatie

`random`; een kans schatten door een experiment duizenden keren te
herhalen; een oppervlakte schatten met toevallige punten (pi met
dartpijlen); toevalswandelingen; een beschreven situatie vertalen naar een
simulatie (verjaardagsparadox, het driedeurenspel).

- **Link:** kansrekening, eerst simuleren en dan narekenen; diffusie en
  radioactief verval; een beurskoers of een gokker als toevalswandeling.
- **Proefdoel.** Dit is het eerste doel buiten een typische programmeerles,
  en dus de test of de AI er goede oefeningen voor maakt. Zie "Afbakening
  in de teachingTips" hieronder.
- **Na de eerste leerlingen:** de gegenereerde oefeningen uit de vragenbank
  nakijken op drie punten: constructies die nog niet gezien zijn, variatie
  in contexten, en oefeningen die kennis vragen die er niet bij staat.

### 7. Grafieken maken

Matplotlib met gewone lijsten: lijn, punten, histogram, assen en legende;
de grafiek van een functie uit een zelfgemaakte waardetabel. Een kort doel
dat de volgende doelen zichtbaar maakt.

- **Link:** het histogram van de simulaties uit doel 6 (de som van twee
  dobbelstenen, de eindposities van toevalswandelingen); de waardetabellen
  uit doel 5.
- **Uit de oude cursus:** module 3, "Functies verkennen en visualiseren",
  maar zonder numpy.
- **Let op:** de beoordelaar ziet de grafiek niet. De LO's gaan over code
  schrijven en voorspellen wat er getekend wordt.

### 8. Vergelijkingen oplossen door te zoeken

Bisectie ("warm, koud, warmer"), de wortelmethode van Heron, Newton, een
stopcriterium met een tolerantie, en waarom `0.1 + 0.2 != 0.3`.

- **Link:** vergelijkingen zonder oplossingsformule, zoals x³ - x - 1 = 0;
  in de economie het break-evenpunt en de interne opbrengstvoet, waarvoor
  geen formule bestaat; in de wetenschappen het tijdstip waarop een model
  een waarde bereikt.
- **Aansluiting:** de tekenwissel in een waardetabel uit doel 5 is de eerste
  stap van bisectie.
- **Nieuw in Python:** een functie doorgeven als argument, zodat
  `bisectie(f, a, b)` voor elke functie werkt.
- **Uit de oude cursus:** module 3, "Bisectie en Newton-Raphson".

### 9. De wereld in tijdstappen

Eén idee: de nieuwe toestand is de oude plus de verandering maal de
tijdstap. Daarmee een spaarplan en een lening aflossen, exponentiële en
logistische groei, afkoeling, een val met luchtweerstand, een epidemie, en
prooi en roofdier. De oppervlakte onder een grafiek als som van kleine
stukjes hoort hier ook.

- **Link:** differentiaalvergelijkingen en integralen zonder analyse.
- **Uit de oude cursus:** module 3, "Rekenen met integralen"
  (rechthoeken, trapeziumregel); de rest is nieuw.

### 10. Dictionaries en gestructureerde data

De dictionary, lijsten van dictionaries, tellen met een dictionary
(frequentietabel), geneste structuren lezen, JSON, en live data ophalen
(de positie van het ISS, aardbevingen).

- **Uit de oude cursus:** module 4, "Werken met JSON".
- **Let op:** een oefening kan niet afhangen van live data. De oefeningen
  werken op letterlijke voorbeeldstructuren; de ISS-tracker is beleving.

### 11. Echte data onderzoeken

Een CSV-bestand inlezen, filteren, een voortschrijdend gemiddelde en een
trendlijn eerst zelf schrijven en dan met pandas; de weg van vraag over
datacontrole en grafiek naar conclusie.

- **Link:** klimaatdata, een rechte door labometingen, inflatie.
- **Uit de oude cursus:** module 4, "Klimaatdata begrijpen en verkennen".

## Keuzedoelen

Nog niet geplaatst in de volgorde. Elk kan als `optional` doel na het doel
waarop het steunt.

| Doel | Wat leerlingen doen | Link | Steunt op |
|---|---|---|---|
| Geheimschrift en controlegetallen | Stringmethodes, `ord` en `chr`, modulo; Caesar kraken met letterfrequenties; IBAN en rijksregisternummer (mod 97) | Modulorekenen; bankwezen | doel 5 |
| Zoeken, sorteren en efficiëntie | Lineair en binair zoeken, bubble en insertion sort, stappen tellen, n² tegenover n·log n | Zelfde idee als bisectie; logaritmen | doel 5 |
| Recursie en fractalen | Faculteit, ggd van Euclides, trage Fibonacci, torens van Hanoi, fractaalboom en Koch met turtle | Recursieve rijen; zelfgelijkenis | doel 5 |
| Het beste zoeken | Alle mogelijkheden aflopen, de prijs met maximale winst zonder afgeleide, knapzak met budget, "geblinddoekt bergaf" | Extremumvraagstukken; hoe AI leert | doel 5, liefst doel 8 |
| Simpele regels, complex gedrag | Game of Life, bosbrand, het segregatiemodel van Schelling, een toernooi van het gevangenendilemma | Emergentie in biologie en economie | doel 6 |
| Golven en geluid | Sampling, sinus, boventonen, klankkleur, envelopes | Fysica; goniometrie | doel 5, zie hieronder |

**Golven en geluid** (module 5 van de oude cursus) heeft geluidsuitvoer
nodig. De Python-bundel van de app bevat numpy, pandas, matplotlib en
requests, maar geen sounddevice. Dat vraagt een nieuwe release, of een
omweg via `wave` en `winsound` uit de standaardbibliotheek, die nog niet
getest is.

## Geschrapt

**Code controleren die je niet zelf schreef** (AI als code-assistent, module
4 van de oude cursus). Zo werkt niemand: je gebruikt de software en maakt
een issue aan als iets niet klopt. Wat overblijft, merken dat een resultaat
niet kan kloppen en precies zeggen wat er mis is, zit in de andere doelen:
een simulatie naast de formule leggen, een resultaat op grootteorde
beoordelen, een functie testen met een geval waarvan je het antwoord kent.

## Randvoorwaarden van de app

- **De beoordelaar ziet alleen de code of de tekst van de leerling.** Geen
  uitvoer, geen grafiek, geen geluid. Bij toeval, grafieken en live data
  gaan de LO's dus over schrijven en voorspellen, zoals bij turtle.
- **De AI krijgt bij het maken van een oefening alleen** de titel van het
  doel, de titel van het subdoel, de LO's waarop de oefening mikt en de
  teachingTips. Geen lijst van wat leerlingen al kennen, en geen lesinhoud.
- **Beschikbaar in de app:** de standaardbibliotheek (`turtle`, `random`,
  `math`), numpy, pandas, matplotlib en requests.

## Afspraken bij het uitwerken

### Afbakening in de teachingTips

Omdat de AI geen lijst van voorkennis krijgt, staat in de teachingTips van
elk subdoel wat mag en wat nog niet gezien is. Vanaf doel 6 zijn dat twee
vaste alinea's per subdoel:

- **Python:** welke nieuwe functies mogen, en wat niet (zie de lijst
  hieronder). Altijd ook: functies geven hun resultaat terug en bevatten
  geen `print` of `input`.
- **Vakkennis en vraagvorm:** elke oefening geeft zelf alle spelregels en
  formules; de leerling heeft geen theorie nodig om te antwoorden. Bij
  toeval vraagt een oefening nooit naar "de uitvoer", maar naar wat
  mogelijk is, rond welke waarde een schatting ligt, of wat er gebeurt bij
  gegeven toevalswaarden.

Als die alinea's in elk subdoel als een lap tekst terugkomen en de
oefeningen toch buiten de lijntjes gaan, is dat het signaal dat de app zelf
een voorkennislijst moet meesturen. Dat wordt pas gebouwd als de proef met
doel 6 erom vraagt.

### Nog niet gezien na doel 6

f-strings, `break`, `+=`, `range` met een stap, stringmethodes,
`try`/`except`, `global`, recursie, `lambda`, list comprehensions,
dictionaries, sets, een functie als argument, numpy en matplotlib.

Wel gezien, naast doel 1 tot 4: `def` en `return`, standaardwaarden,
`import math` (`math.sqrt`, `math.pi`, `math.sin`, `math.cos`), `round`,
`abs`, en uit `random` alleen `randint`, `random`, `choice` en `uniform`.

### Woordgebruik

- **Aanroepen**, niet oproepen: zo staat het in doel 1 tot 4.
- De vertaling van elke term staat in `lessons/glossary-en.md`; nieuwe
  termen en namen uit de code komen daar bij.

### Van doelbestand tot live

1. Doelbestand in `goals/`, daarna `OVERVIEW.md` opnieuw maken.
2. Lessen in `lessons/NN-<doel-id>/`, met de Engelse versie in `en/` in
   dezelfde beurt: `python tooling/translations/check_lessons.py` faalt
   zolang een Nederlandse les geen Engelse tegenhanger met dezelfde
   HTML-structuur heeft.
3. De Engelse titels en beschrijvingen in `goals/en/goal-texts.json`.
4. Live zetten: `python tooling/curriculum/push_goal.py plan NN-<doel-id>`,
   dan `push`. Het script maakt alleen aan en overschrijft niets.
5. De Engelse teksten: `python tooling/translations/translations.py push`.

Een doel dat al live staat wijzig je via de import in de app. De id's van
subdoelen en LO's dragen de voortgang van de leerlingen.
