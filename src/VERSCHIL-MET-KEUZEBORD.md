# Wat er is veranderd aan de gekopieerde bestanden

Deze twee bestanden komen uit `tomhooijer-svg/keuzebord-app` en zijn
bewust gekopieerd in plaats van gelinkt: een deploy van het Keuzebord mag
de observatie-app niet kunnen breken. Wel moeten ze af en toe bijgewerkt
worden. Hieronder staat precies wat er is aangepast, zodat dat kan zonder
de wijzigingen kwijt te raken.

## src/kb-stijl.css
Ongewijzigd. Letterlijke kopie.

## src/kb-supabase.js
Vier kleine aanpassingen, allemaal uitbreidend — geen bestaand gedrag
veranderd, dus deze versie werkt ook gewoon in het Keuzebord.

1. `bestandOp(pad, blob, emmer)` — derde parameter toegevoegd.
2. `bestandLink(pad, seconden, emmer)` — derde parameter toegevoegd.
3. `bestandWeg(paden, emmer)` — tweede parameter toegevoegd.

   Reden: de observatie-app schrijft foto's naar `observatie-media`, maar
   moet de kinderfoto's uit `leerlingen.foto_pad` lezen uit `kb-media`.
   Twee emmers dus. Laat je de parameter weg, dan gebruikt hij `kb-media`
   zoals voorheen.

4. `SB.zetSessieUitAntwoord` toegevoegd aan het API-oppervlak.

   Reden: het Keuzebord logt in met wachtwoord en hoefde daarom nooit een
   token uit een terugkeerlink te verwerken. De observatie-app gebruikt
   magic link, en moet de sessie dus zelf kunnen zetten. De onderliggende
   functie `bewaarUitAntwoord` bestond al; alleen was hij niet bereikbaar.

## Gedeelde sessie
Beide apps draaien op `tomhooijer-svg.github.io` en bewaren de sessie onder
dezelfde sleutel `kb_sessie`. Omdat localStorage per herkomst werkt en niet
per map, betekent dat: **ben je ingelogd in het Keuzebord, dan ben je ook
ingelogd in de observatie-app.** Uitloggen geldt ook voor allebei. Dat is
bewust — het hoort één familie te zijn.
