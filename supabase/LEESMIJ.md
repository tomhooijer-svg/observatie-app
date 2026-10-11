# Migraties

Op volgorde gedraaid in de SQL-editor van Supabase. De nummers zijn de
volgorde waarin ze zijn uitgevoerd; er zitten gaten in waar scripts
onderweg zijn vervallen.

| Script | Wat het doet | Status |
|---|---|---|
| `01_verkenning.sql` | Leest alleen: welke tabellen heeft het Planbord. | eenmalig, mag blijven staan |
| `02_observatie_schema.sql` | `observatie_sessies`, `observatie_sessie_doelen`, `observatie_notities`, emmer `observatie-media`, view `kind_tijdlijn`. | gedraaid |
| `06_toegang_delegeren.sql` | Eerste poging om `obs_groep_toegang` aan `mag_bij_groep` te laten delegeren, en de splitsing van `status` en `stand` in `kind_tijdlijn`. | gedraaid; de delegatie is later alsnog in 13 gezet |
| `07_standen_en_periodes.sql` | `observatie_standen` (met geschiedenis), `periodes`, `periode_sjablonen`, `periode_focus`, `observatie_leerling`, en de views. | gedraaid |
| `13_herstel_kern.sql` | `obs_groep_toegang` volgt nu echt `mag_bij_groep`, en de foto-policies struikelen niet meer over een pad dat niet met een uuid begint. | gedraaid |
| `14_policies_aanvullen.sql` | De tien policies die bij 02 niet zijn aangekomen. Zonder deze stonden drie tabellen volledig op slot. | gedraaid |
| `09_sjablonen_startset.sql` | Zes periodesjablonen voor een instroomgroep. Schrijft wél weg. | optioneel |

## Wat niet in deze map staat

Een paar scripts waren diagnoses of doodlopende wegen en zijn weggegooid.
Daar zat ook een aanpak bij die niet deugde: een ingelogde leerkracht
nabootsen in de SQL-editor met `set local request.jwt.claims`. Dat leverde
telkens nul rijen op, wat er precies zo uitziet als een werkende
afscherming terwijl er in werkelijkheid niemand is ingelogd.

**De rechtenregels test je met de app zelf**, met een echte login. Zie je
daar je eigen groepen, dan klopt het.

## Twee regels voor volgende migraties

1. Nooit een schrijfactie op een Planbord-tabel in dezelfde transactie als
   iets wat moet slagen. De trigger `profiel_op_slot` weigert aanpassingen
   buiten de app om, en sleept dan de hele transactie mee.
2. RLS aanzetten zonder policies is geen halve afscherming maar een
   volledig slot — ook voor de eigenaar van de rij. Controleer na elke
   migratie of elke tabel met RLS ook policies heeft.
