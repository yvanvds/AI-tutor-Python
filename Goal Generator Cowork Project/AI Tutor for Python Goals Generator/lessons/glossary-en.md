# Woordenlijst Nederlands → Engels (lessen en doelteksten, #209)

Eén vertaling per term, in alle lessen (`lessons/<module>/en/`) en in alle
doelteksten (`goals/en/goal-texts.json`). Waar de Engelse interface
(`lib/l10n/app_en.arb`) een woord al vastlegt, volgt de vertaling de
interface; dat staat in de kolom *UI*.

Spelling: Amerikaans (*color*, *math*, *recognize*), zodat de tekst past bij
Pythons eigen namen (`t.pencolor`). De leerling wordt aangesproken met
*you*; een onbepaalde leerling of gebruiker is *they*.

## Leeromgeving

| Nederlands | Engels | UI |
|---|---|---|
| oefening | exercise | ✓ |
| les | lesson | ✓ |
| lesinhoud | lesson content | ✓ |
| uitleg | explanation | ✓ |
| doel | goal | ✓ |
| subdoel | subgoal | ✓ |
| leerdoel | learning objective (LO) | ✓ |
| leerpad | learning path | ✓ |
| opgave | task | |
| probleemstelling | problem | |
| hoofdstuk | chapter | |

## Programma's en uitvoering

| Nederlands | Engels | UI |
|---|---|---|
| uitvoer; "Uitvoer:" boven een uitvoerblok | output; "Output:" | ✓ |
| (een script) uitvoeren, draaien | run | ✓ |
| invoer | input | ✓ |
| script | script | |
| programma | program | |
| broncode | source code | |
| gebruiker | user | |
| prompt (bij `input`) | prompt | |
| omzetten (invoer naar een getal), conversie | convert, conversion | |
| omzetten (elementen naar een nieuwe lijst) | transform | |
| teruggeven | give back / return | |
| aanroep, aanroepen | call | |
| functie | function | |
| methode | method | |
| sleutelwoord | keyword | |
| tekst plakken met `+` | glue (text together) | |
| scherm | screen | |
| turtle-venster, tekenvenster | turtle window | ✓ |

## Waarden en variabelen

| Nederlands | Engels |
|---|---|
| variabele | variable |
| toekennen, toekenning | assign, assignment |
| herwijzen | reassign |
| overschrijven | overwrite |
| waarde | value |
| tekst | text |
| string | string |
| aanhalingstekens | quotation marks |
| getal | number |
| geheel getal | whole number (`int`) |
| kommagetal | decimal number (`float`) |
| decimale komma / punt | decimal comma / point (de Belgische komma blijft vermeld) |
| haakjes (rond) | parentheses |
| vierkante haken | square brackets |
| expressie | expression |
| operator | operator |
| bewerking | operation |
| volgorde van bewerkingen | order of operations |
| optellen, aftrekken, vermenigvuldigen, delen | addition, subtraction, multiplication, division |
| gehele deling (`//`) | integer division |
| rest bij deling (`%`) | remainder after division (modulo) |
| machtsverheffing (`**`) | exponentiation |

## Beslissingen

| Nederlands | Engels |
|---|---|
| vergelijking | comparison |
| vergelijkingsoperator | comparison operator |
| voorwaarde, conditie | condition |
| samengestelde voorwaarde | compound condition |
| waar / onwaar | true / false (`True` / `False`) |
| tak | branch |
| blok | block |
| insprong, inspringen | indentation, indent |
| if/elif/else-keten | if/elif/else chain |
| grensgeval | boundary case |
| minstens / hoogstens / meer dan | at least / at most / more than |

## Herhaling, testen

| Nederlands | Engels |
|---|---|
| lus | loop |
| herhaling, herhalen | repetition, repeat |
| doorloop (van een lus) | iteration |
| lusvariabele | loop variable |
| teller | counter |
| oneindige lus | infinite loop |
| zolang / totdat | as long as / until |
| testgeval | test case |
| randgeval | edge case |
| fout | error (in code); mistake (van de leerling) |
| foutmelding | error message |
| syntaxfout, runtimefout, logische fout | syntax error, runtime error, logic error |
| debuggen | debug |
| opsporen en verbeteren | find and fix |
| voorspellen | predict |
| traceren | trace |

## Lijsten en tuples

| Nederlands | Engels |
|---|---|
| lijst | list |
| element | element |
| index, indexen | index, indexes |
| negatieve index | negative index |
| slicing, een slice | slicing, a slice |
| (een lijst) doorlopen | loop over / loop through (a list) |
| filteren | filter |
| tuple | tuple |
| uitpakken | unpack |
| (on)veranderbaar, onveranderbaarheid | mutable / immutable, immutability |
| hulpvariabele | temporary variable |
| geneste lus | nested loop |
| buitenste / binnenste lus | outer / inner loop |
| raster, rooster | grid |
| rij, kolom | row, column |

## Turtle

| Nederlands | Engels |
|---|---|
| schildpad | turtle |
| tekenopdracht (aan de turtle) | drawing instruction |
| tekenopdracht (een opgave: "teken een rij van…") | drawing task |
| pen omhoog / omlaag | pen up / pen down |
| kijkrichting | the direction the turtle is facing |
| buitenhoek / binnenhoek | exterior angle / interior angle |
| (regelmatige) veelhoek | (regular) polygon |
| figuur | shape |

## Namen in de code

Nederlandse variabelenamen, strings en commentaar in de voorbeelden zijn mee
vertaald, zodat code en uitleg bij elkaar passen en bij de Engelse
oefeningen van de tutor (#117). Persoonsnamen (Mira, Aya, Bram, Chloë,
Dries) blijven.

| Nederlands | Engels | Nederlands | Engels |
|---|---|---|---|
| `naam`, `namen` | `name`, `names` | `leeftijd` | `age` |
| `getal`, `getallen` | `number`, `numbers` | `mag_stemmen` | `can_vote` |
| `totaal` | `total` | `teller` | `counter` |
| `gemiddelde` | `average` | `antwoord` | `answer` |
| `prijs`, `aantal` | `price`, `quantity` | `gewicht` | `weight` |
| `temperatuur`, `temperaturen` | `temperature`, `temperatures` | `kleur`, `kleuren` | `color`, `colors` |
| `punten` (scores in een lijst) | `scores` | `punt`, `punten` (coördinaat) | `point`, `points` |
| `dagen` (`"ma"`…`"vr"`) | `days` (`"Mon"`…`"Fri"`) | `woord` | `word` |
| `boodschappen` | `groceries` | `kwadraten` | `squares` |
| `laatste` | `last` | `lengtes` | `lengths` |
| `groot`, `dubbel` | `big`, `doubled` | `grootste` | `largest` |
| `aantal_even` | `even_count` | `zoek` | `target` |
| `gevonden`, `positie` | `found`, `position` | `hulp` | `temp` |
| `rooster` | `grid` | `raster` (nieuw opgebouwd) | `new_grid` |
| `rij`, `k` (kolom) | `row`, `c` (column) | `lijst` (als voorbeeldnaam) | `my_list` (nooit `list`: dat is Pythons eigen naam) |

Zo wordt `rooster[r][k]` in de Engelse les en doeltekst `grid[r][c]`.
