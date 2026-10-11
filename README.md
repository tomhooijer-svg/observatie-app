# Kijk mee — observatie-app

Observeren in de kleutergroep. Hoort bij het Keuzebord en het Planbord en
draait op dezelfde Supabase-database, zodat groepen, kinderen, doelen en
hoeken maar op één plek staan.

Geen bouwstap, geen pakketten: losse bestanden die je rechtstreeks op
GitHub Pages zet.

## Wat erin zit

| Bestand | Wat het doet |
|---|---|
| `inloggen.html` | Inloggen met een e-maillink (of met wachtwoord) |
| `index.html` | Je groepen, en de kinderen in de gekozen groep |
| `src/kb-stijl.css` | De vormtaal, gekopieerd uit het Keuzebord |
| `src/kb-supabase.js` | De verbinding met de server, gekopieerd uit het Keuzebord |
| `src/obs-sessie.js` | Magic link, uitloggen, foto-links |
| `src/obs-app.js` | Het beginscherm |
| `src/VERSCHIL-MET-KEUZEBORD.md` | Wat er is aangepast aan de gekopieerde bestanden |

## Gedeelde login

Beide apps staan op `tomhooijer-svg.github.io` en bewaren de sessie onder
dezelfde sleutel. Ben je ingelogd in het Keuzebord, dan ben je hier ook
ingelogd. Uitloggen geldt voor allebei.

## De database

De tabellen staan in hetzelfde Supabase-project als het Planbord:
`observatie_sessies`, `observatie_notities`, `observatie_standen`,
`periodes`, `periode_sjablonen`, `periode_focus`, `observatie_leerling`,
plus de emmer `observatie-media`.

Wie wat mag zien wordt bepaald door `mag_bij_groep()` — dezelfde regel als
in het Planbord. De app schrijft nooit in een Planbord-tabel.

De migraties staan in `supabase/`, op volgorde genummerd.

## Op GitHub Pages zetten

```sh
cd observatie-app
git init
git add .
git commit -m "Kijk mee: inloggen en groepsoverzicht"
git branch -M main
git remote add origin https://github.com/tomhooijer-svg/observatie-app.git
git push -u origin main
```

Daarna in GitHub: **Settings → Pages → Source: Deploy from a branch →
`main` / `(root)` → Save**. Na een minuut staat hij op
`https://tomhooijer-svg.github.io/observatie-app/`.

## Supabase instellen

In het Supabase-dashboard onder **Authentication → URL Configuration** moet
dit adres bij **Redirect URLs** staan, anders weigert de inloglink:

```
https://tomhooijer-svg.github.io/observatie-app/inloggen.html
```

## Lokaal proberen

```sh
python3 -m http.server 8913
```

Let op: een inloglink stuurt je altijd naar het adres dat hierboven in
Supabase staat, dus magic link werkt alleen op de echte site. Lokaal kun je
met wachtwoord inloggen.
