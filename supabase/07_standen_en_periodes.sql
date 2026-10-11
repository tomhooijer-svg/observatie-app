-- ═══════════════════════════════════════════════════════════════════════
--  07_standen_en_periodes.sql        STAP 1 van de bouw
--
--  Voegt toe: standen (met geschiedenis), periodes met sjablonen, focus,
--  en een zijtabel voor kindgegevens die het planbord niet heeft.
--
--  DE APP BLIJFT LOS: hij leest groepen/leerlingen/doelen/hoeken/profielen,
--  maar schrijft uitsluitend in zijn eigen observatie_*- en periode_*-tabellen.
--  Er gaat niets terug naar de planbord-tabel `observaties`. Zie sectie 7
--  voor de koppeling die klaarligt maar uit staat.
--
--  IDEMPOTENT. Raakt geen enkele bestaande tabel aan.
-- ═══════════════════════════════════════════════════════════════════════

begin;

-- ───────────────────────────────────────────────────────────────────────
--  1. PERIODE_SJABLONEN — de regel, niet de losse datum
--
--  In een instroomgroep wil je "welkomstgesprek zes weken na instroom"
--  één keer instellen, niet bij elk kind opnieuw. Een sjabloon is óf
--  schoolbreed met een vaste datum in het jaar, óf kindgebonden met een
--  aantal dagen na de instroomdatum.
-- ───────────────────────────────────────────────────────────────────────
create table if not exists public.periode_sjablonen (
  id              uuid primary key default gen_random_uuid(),
  groep_id        uuid references public.groepen(id) on delete cascade,
  naam            text not null,
  soort           text not null check (soort in ('school','kind')),

  -- schoolbreed: dag en maand, zodat het sjabloon elk schooljaar meegaat
  van_maand       int check (van_maand between 1 and 12),
  van_dag         int check (van_dag   between 1 and 31),
  tot_maand       int check (tot_maand between 1 and 12),
  tot_dag         int check (tot_dag   between 1 and 31),

  -- kindgebonden: geteld vanaf de instroomdatum van het kind
  start_na_dagen  int,
  duur_dagen      int,

  volgorde        int not null default 0,
  actief          boolean not null default true,
  door            uuid not null references public.profielen(id) on delete restrict,
  aangemaakt      timestamptz not null default now(),

  -- een sjabloon moet wél invulbaar zijn voor zijn eigen soort
  check (
    (soort = 'school' and van_maand is not null and van_dag is not null)
    or
    (soort = 'kind'   and start_na_dagen is not null)
  )
);


-- ───────────────────────────────────────────────────────────────────────
--  2. PERIODES — de concrete momenten
--
--  Uit een sjabloon gegenereerd, daarna gewoon te verschuiven. Generatie
--  die je mag bijsturen werkt in de praktijk beter dan een berekening die
--  vastligt: een welkomstgesprek verzet je nu eenmaal.
--
--  leerling_id leeg  = geldt voor de hele groep (rapport, oudergesprekken)
--  leerling_id gezet = het eigen spoor van dat kind
-- ───────────────────────────────────────────────────────────────────────
create table if not exists public.periodes (
  id              uuid primary key default gen_random_uuid(),
  groep_id        uuid not null references public.groepen(id)    on delete cascade,
  leerling_id     uuid references public.leerlingen(id)          on delete cascade,
  naam            text not null,
  soort           text not null check (soort in ('school','kind')),
  van             date not null,
  tot             date not null,
  uit_sjabloon    uuid references public.periode_sjablonen(id)   on delete set null,
  opmerking       text,
  door            uuid not null references public.profielen(id)  on delete restrict,
  aangemaakt      timestamptz not null default now(),
  bijgewerkt      timestamptz not null default now(),
  check (tot >= van)
);

create index if not exists periodes_groep_idx    on public.periodes(groep_id, van);
create index if not exists periodes_leerling_idx on public.periodes(leerling_id) where leerling_id is not null;

drop trigger if exists periodes_bijgewerkt on public.periodes;
create trigger periodes_bijgewerkt before update on public.periodes
  for each row execute function public.obs_bijgewerkt();


-- ───────────────────────────────────────────────────────────────────────
--  3. PERIODE_FOCUS — welke doelen wil ik deze periode bij wie zien
--
--  leerling_id leeg = dit doel geldt voor de hele groep.
-- ───────────────────────────────────────────────────────────────────────
create table if not exists public.periode_focus (
  id           uuid primary key default gen_random_uuid(),
  periode_id   uuid not null references public.periodes(id)    on delete cascade,
  doel_id      uuid not null references public.doelen(id)      on delete cascade,
  leerling_id  uuid references public.leerlingen(id)           on delete cascade,
  aangemaakt   timestamptz not null default now()
);

-- coalesce met een vaste uuid, zodat "hele groep" en "dit kind" allebei
-- maar één keer kunnen voorkomen
create unique index if not exists periode_focus_uniek
  on public.periode_focus (periode_id, doel_id,
       coalesce(leerling_id, '00000000-0000-0000-0000-000000000000'::uuid));


-- ───────────────────────────────────────────────────────────────────────
--  4. OBSERVATIE_LEERLING — kindgegevens die het planbord niet bijhoudt
--
--  Bewust een zijtabel en géén extra kolom in `leerlingen`: zo blijft het
--  planbord onaangeroerd en is alles in één keer terug te draaien.
--  Krijgt `leerlingen` later zelf een instroomdatum, dan stappen we over.
-- ───────────────────────────────────────────────────────────────────────
create table if not exists public.observatie_leerling (
  leerling_id    uuid primary key references public.leerlingen(id) on delete cascade,
  groep_id       uuid not null references public.groepen(id)       on delete cascade,
  instroomdatum  date,
  aandacht       boolean not null default false,   -- "focuskind deze periode"
  aantekening    text,
  bijgewerkt     timestamptz not null default now()
);

drop trigger if exists observatie_leerling_bijgewerkt on public.observatie_leerling;
create trigger observatie_leerling_bijgewerkt before update on public.observatie_leerling
  for each row execute function public.obs_bijgewerkt();


-- ───────────────────────────────────────────────────────────────────────
--  5. OBSERVATIE_STANDEN — het vakje met een teken en een datum
--
--  Append-only: elke beoordeling blijft staan, ook als je later bijstelt.
--  Dat is precies wat de planbord-tabel `observaties` NIET doet — die
--  overschrijft per kind+doel, dus daar zie je alleen de laatste stand.
--  Hier zie je de ontwikkeling door het jaar.
--
--  stand mag LEEG zijn: het doel is dan wel aangeraakt maar nog niet
--  beoordeeld. Dat is je "losse notitie, doel er later aan hangen", en
--  het onderscheid dat het keuzebord met isBeoordeeld() ook al maakt.
--
--  Waarden gelijk aan het keuzebord:
--     nog     = is aan het ontdekken
--     bezig   = kan het met hulp
--     behaald = kan het zelfstandig
-- ───────────────────────────────────────────────────────────────────────
create table if not exists public.observatie_standen (
  id           uuid primary key default gen_random_uuid(),
  groep_id     uuid not null references public.groepen(id)    on delete cascade,
  leerling_id  uuid not null references public.leerlingen(id) on delete cascade,
  doel_id      uuid not null references public.doelen(id)     on delete cascade,

  stand        text check (stand in ('nog','bezig','behaald')),

  ts           timestamptz not null default now(),
  door         uuid not null references public.profielen(id)  on delete restrict,

  notitie_id   uuid references public.observatie_notities(id) on delete set null,
  sessie_id    uuid,
  periode_id   uuid references public.periodes(id)            on delete set null,
  hoek_id      uuid references public.hoeken(id)              on delete set null,

  client_id    text unique,
  aangemaakt   timestamptz not null default now(),

  -- hoort de stand bij een ronde, dan moet die ronde in dezelfde groep
  -- zitten. Is sessie_id leeg, dan slaat Postgres deze controle over.
  foreign key (sessie_id, groep_id)
    references public.observatie_sessies(id, groep_id) on delete cascade
);

create index if not exists standen_kind_doel_idx on public.observatie_standen(leerling_id, doel_id, ts desc);
create index if not exists standen_groep_idx     on public.observatie_standen(groep_id, ts desc);
create index if not exists standen_periode_idx   on public.observatie_standen(periode_id) where periode_id is not null;
create index if not exists standen_doel_idx      on public.observatie_standen(doel_id);


-- ───────────────────────────────────────────────────────────────────────
--  6. observatie_notities.doel_id vervalt
--
--  Eén notitie kan over meerdere doelen gaan, met per doel een andere
--  stand. Dat past niet in één kolom; die koppeling zit nu in
--  observatie_standen. Er staat nog geen data in, dus dit kost niets.
--
--  De view kind_tijdlijn uit script 06 leest deze kolom, dus die moet
--  eerst weg. Hij wordt in sectie 8 opnieuw opgebouwd, nu mét de standen
--  erbij — ook de losse tikken uit het raster, die eerder ontbraken.
-- ───────────────────────────────────────────────────────────────────────
drop view if exists public.kind_tijdlijn;
alter table public.observatie_notities drop column if exists doel_id;


-- ───────────────────────────────────────────────────────────────────────
--  7. RLS — zelfde regel als de rest: zien per groep, bewerken wat van jou is
-- ───────────────────────────────────────────────────────────────────────
alter table public.periode_sjablonen    enable row level security;
alter table public.periodes             enable row level security;
alter table public.periode_focus        enable row level security;
alter table public.observatie_leerling  enable row level security;
alter table public.observatie_standen   enable row level security;

-- periode_sjablonen: groep leeg = schoolbreed sjabloon, voor iedereen leesbaar
drop policy if exists sjablonen_lezen on public.periode_sjablonen;
create policy sjablonen_lezen on public.periode_sjablonen for select to authenticated
  using ( groep_id is null or public.obs_groep_toegang(groep_id) );

drop policy if exists sjablonen_schrijven on public.periode_sjablonen;
create policy sjablonen_schrijven on public.periode_sjablonen for all to authenticated
  using      ( door = auth.uid() )
  with check ( door = auth.uid()
               and (groep_id is null or public.obs_groep_toegang(groep_id)) );

-- periodes
drop policy if exists periodes_lezen on public.periodes;
create policy periodes_lezen on public.periodes for select to authenticated
  using ( public.obs_groep_toegang(groep_id) );

drop policy if exists periodes_schrijven on public.periodes;
create policy periodes_schrijven on public.periodes for all to authenticated
  using      ( public.obs_groep_toegang(groep_id) and door = auth.uid() )
  with check ( public.obs_groep_toegang(groep_id) and door = auth.uid() );

-- periode_focus: volgt de periode waar het aan hangt
drop policy if exists focus_lezen on public.periode_focus;
create policy focus_lezen on public.periode_focus for select to authenticated
  using ( exists (select 1 from public.periodes p
                  where p.id = periode_id and public.obs_groep_toegang(p.groep_id)) );

drop policy if exists focus_schrijven on public.periode_focus;
create policy focus_schrijven on public.periode_focus for all to authenticated
  using      ( exists (select 1 from public.periodes p
                       where p.id = periode_id and p.door = auth.uid()) )
  with check ( exists (select 1 from public.periodes p
                       where p.id = periode_id and p.door = auth.uid()) );

-- observatie_leerling: een instroomdatum is een feit, geen mening —
-- iedere leerkracht van de groep mag hem zetten
drop policy if exists leerling_extra_lezen on public.observatie_leerling;
create policy leerling_extra_lezen on public.observatie_leerling for select to authenticated
  using ( public.obs_groep_toegang(groep_id) );

drop policy if exists leerling_extra_schrijven on public.observatie_leerling;
create policy leerling_extra_schrijven on public.observatie_leerling for all to authenticated
  using      ( public.obs_groep_toegang(groep_id) )
  with check ( public.obs_groep_toegang(groep_id) );

-- observatie_standen
drop policy if exists standen_lezen on public.observatie_standen;
create policy standen_lezen on public.observatie_standen for select to authenticated
  using ( public.obs_groep_toegang(groep_id) );

drop policy if exists standen_toevoegen on public.observatie_standen;
create policy standen_toevoegen on public.observatie_standen for insert to authenticated
  with check ( public.obs_groep_toegang(groep_id) and door = auth.uid() );

drop policy if exists standen_wijzigen on public.observatie_standen;
create policy standen_wijzigen on public.observatie_standen for update to authenticated
  using      ( public.obs_groep_toegang(groep_id) and door = auth.uid() )
  with check ( public.obs_groep_toegang(groep_id) and door = auth.uid() );

drop policy if exists standen_verwijderen on public.observatie_standen;
create policy standen_verwijderen on public.observatie_standen for delete to authenticated
  using ( public.obs_groep_toegang(groep_id) and door = auth.uid() );

grant usage on schema public to authenticated;
grant select, insert, update, delete on
  public.periode_sjablonen, public.periodes, public.periode_focus,
  public.observatie_leerling, public.observatie_standen
  to authenticated;


-- ───────────────────────────────────────────────────────────────────────
--  8. VIEWS voor de app
-- ───────────────────────────────────────────────────────────────────────

--  Waar staat dit kind nu op dit doel? De nieuwste beoordeelde rij.
create or replace view public.huidige_stand
with (security_invoker = true) as
select distinct on (s.leerling_id, s.doel_id)
  s.leerling_id, s.doel_id, s.groep_id,
  s.stand, s.ts, s.door, s.id as stand_id
from public.observatie_standen s
where s.stand is not null
order by s.leerling_id, s.doel_id, s.ts desc;

grant select on public.huidige_stand to authenticated;


--  De tijdlijn per kind: geschreven notities, losse tikken uit het raster,
--  en wat het planbord al wist. Drie bronnen, één chronologisch overzicht.
--  Een notitie met twee doelen levert twee regels op — één per doel, elk
--  met zijn eigen stand. Een notitie zonder doel komt er één keer in.
create view public.kind_tijdlijn
with (security_invoker = true) as
  select
    n.leerling_id, n.groep_id, n.door,
    n.ts                                  as moment,
    'kijk-mee'::text                      as bron,
    n.status                              as status,
    s.stand                               as stand,
    coalesce(n.portfolio_zin, n.notitie)  as tekst,
    n.tags,
    s.doel_id,
    n.id                                  as bron_id
  from public.observatie_notities n
  left join public.observatie_standen s on s.notitie_id = n.id
union all
  select
    s.leerling_id, s.groep_id, s.door,
    s.ts                                  as moment,
    'lijst'::text                         as bron,
    null::text                            as status,
    s.stand                               as stand,
    null::text                            as tekst,
    '{}'::text[]                          as tags,
    s.doel_id,
    s.id                                  as bron_id
  from public.observatie_standen s
  where s.notitie_id is null
union all
  select
    o.leerling_id, o.groep_id, o.door,
    o.datum::timestamptz                  as moment,
    'planbord'::text                      as bron,
    null::text                            as status,
    o.stand                               as stand,
    nullif(o.notitie, '')                 as tekst,
    '{}'::text[]                          as tags,
    o.doel_id,
    o.id                                  as bron_id
  from public.observaties o;

grant select on public.kind_tijdlijn to authenticated;


--  Wie heb ik deze periode nog nauwelijks gezien?
create or replace view public.periode_dekking
with (security_invoker = true) as
select
  p.id        as periode_id,
  p.groep_id,
  p.naam      as periode,
  p.van, p.tot,
  l.id        as leerling_id,
  l.naam      as leerling,
  count(distinct n.id)                                     as notities,
  count(distinct s.doel_id) filter (where s.stand is not null) as beoordeelde_doelen,
  max(greatest(n.ts, s.ts))                                as laatst_gezien
from public.periodes p
join public.leerlingen l
  on l.groep_id = p.groep_id
 and l.actief
 and (p.leerling_id is null or p.leerling_id = l.id)
left join public.observatie_notities n
  on n.leerling_id = l.id and n.ts::date between p.van and p.tot
left join public.observatie_standen s
  on s.leerling_id = l.id and s.ts::date between p.van and p.tot
group by p.id, p.groep_id, p.naam, p.van, p.tot, l.id, l.naam;

grant select on public.periode_dekking to authenticated;


--  Welke focusdoelen staan nog open, en bij wie?
create or replace view public.periode_focus_open
with (security_invoker = true) as
select
  f.periode_id, p.groep_id, p.naam as periode,
  f.doel_id, d.doel, d.leerlijn, d.domein, d.niveau,
  l.id as leerling_id, l.naam as leerling
from public.periode_focus f
join public.periodes   p on p.id = f.periode_id
join public.doelen     d on d.id = f.doel_id
join public.leerlingen l
  on l.groep_id = p.groep_id
 and l.actief
 and (f.leerling_id is null or f.leerling_id = l.id)
left join public.huidige_stand hs
  on hs.leerling_id = l.id and hs.doel_id = f.doel_id
where hs.stand is null;

grant select on public.periode_focus_open to authenticated;


-- ───────────────────────────────────────────────────────────────────────
--  9. DE KOPPELING DIE KLAARLIGT MAAR UIT STAAT
--
--  Deze view laat zien wat er naar de planbord-tabel `observaties` zou
--  gaan als je de apps later wilt laten samenvallen: per kind en doel de
--  nieuwste stand, in precies de vorm die `observaties` gebruikt.
--
--  Er wordt NIETS geschreven. Dit is alleen te lezen. Wil je het later
--  aanzetten, dan is dat een bewuste stap, en moet kb-sync.js eerst leren
--  om deze waarden niet blind te overschrijven.
-- ───────────────────────────────────────────────────────────────────────
create or replace view public.koppeling_voorstel
with (security_invoker = true) as
select
  hs.leerling_id,
  hs.doel_id,
  hs.groep_id,
  hs.stand,
  hs.ts::date                     as datum,
  hs.door,
  o.stand                         as stand_in_planbord,
  case when o.leerling_id is null then 'nieuw'
       when o.stand is distinct from hs.stand then 'wijkt af'
       else 'gelijk' end          as verschil
from public.huidige_stand hs
left join public.observaties o
  on o.leerling_id = hs.leerling_id and o.doel_id = hs.doel_id;

grant select on public.koppeling_voorstel to authenticated;

commit;
