-- ═══════════════════════════════════════════════════════════════════════
--  02_observatie_schema.sql
--  Observatie-app "Kijk mee" — bovenop het bestaande planbord-project.
--
--  Draaien: Supabase → SQL Editor → plak → Run.
--  IDEMPOTENT: je mag hem meerdere keren draaien.
--  Hij WIJZIGT GEEN ENKELE bestaande planbord-tabel — alleen nieuwe
--  tabellen die naar groepen/leerlingen/profielen/doelen/hoeken verwijzen.
-- ═══════════════════════════════════════════════════════════════════════
--
--  WAT IK NIET AANMAAK, EN WAAROM
--
--  teachers        → je hebt al `profielen` (1-op-1 met auth.users, met
--                    naam/email/rol/school_id). Een tweede identiteitstabel
--                    zou betekenen dat elke leerkracht twee rijen heeft die
--                    uit de pas kunnen lopen.
--  teacher_groups  → je hebt al `groep_leden` (groep_id + profiel_id), mét
--                    policies "beheerder koppelt/ontkoppelt". Precies de
--                    afscherming die we nodig hebben, al gebouwd.
--  app_admins      → je hebt al `profielen.rol` en beheerderspolicies.
--
--  Gevolg: wie in het planbord aan een groep hangt, heeft in de
--  observatie-app automatisch toegang tot diezelfde groep. Eén waarheid.
-- ═══════════════════════════════════════════════════════════════════════

begin;

-- ───────────────────────────────────────────────────────────────────────
--  0. Hulpfuncties
-- ───────────────────────────────────────────────────────────────────────
create or replace function public.obs_bijgewerkt()
returns trigger language plpgsql as $$
begin
  new.bijgewerkt = now();
  return new;
end;
$$;

--  Toegangsvraag: hangt de ingelogde leerkracht aan deze groep?
--  Leest rechtstreeks uit de bestaande groep_leden-tabel, zodat de
--  observatie-app en het planbord nooit een andere mening kunnen hebben.
--  SECURITY DEFINER omdat de functie zelf langs RLS heen moet kijken;
--  search_path staat vast tegen schema-kaping.
--  LET OP: de definitie van obs_groep_toegang stond hier, maar is
--  verhuisd naar 12_herstel.sql. Daar delegeert hij aan de bestaande
--  mag_bij_groep(), zodat ook een schoolbeheerder zonder rij in
--  groep_leden toegang heeft. Zou hij hier blijven staan, dan maakte
--  een herhaling van dit script dat werk weer ongedaan.
--
--  Draai 12_herstel.sql als deze functie nog niet bestaat.


-- ───────────────────────────────────────────────────────────────────────
--  1. OBSERVATIE_SESSIES — één observatieronde
--
--  Kolomnamen volgen je planbord-conventie: `door` voor de leerkracht,
--  `aangemaakt`/`bijgewerkt` voor tijdstempels.
-- ───────────────────────────────────────────────────────────────────────
create table if not exists public.observatie_sessies (
  id                uuid primary key default gen_random_uuid(),
  groep_id          uuid not null references public.groepen(id)   on delete cascade,
  door              uuid not null references public.profielen(id) on delete restrict,

  titel             text not null,
  soort             text not null check (soort in ('spel','cognitief')),
  datum             timestamptz not null default now(),
  context           text,

  -- Koppeling aan wat het planbord al weet, in plaats van losse tekst:
  hoek_id           uuid references public.hoeken(id) on delete set null,
  hoek_vrij         text,          -- alleen als er geen hoek-record bestaat
  thema_id          uuid references public.themas(id) on delete set null,

  activiteit        text,          -- vrij_spel | begeleid_spel | kring | ...
  setting           text,          -- binnen | buiten

  -- momentopname van wie er meedeed; leeg = de hele groep
  leerling_ids      uuid[] not null default '{}',

  afgerond          boolean not null default false,
  gepauzeerd        boolean not null default false,
  reflectie         text,

  algemeen_notitie  text,
  algemeen_tags     text[] not null default '{}',
  algemeen_foto     text,          -- pad in de bucket, nooit de foto zelf

  -- door de app verzonnen vóór het uploaden; maakt de offline-wachtrij
  -- idempotent (twee keer versturen = één rij)
  client_id         text unique,

  aangemaakt        timestamptz not null default now(),
  bijgewerkt        timestamptz not null default now(),

  -- nodig voor de samengestelde foreign key vanuit observatie_notities
  unique (id, groep_id)
);

create index if not exists obs_sessies_groep_datum_idx
  on public.observatie_sessies(groep_id, datum desc);
create index if not exists obs_sessies_open_idx
  on public.observatie_sessies(groep_id) where not afgerond;

drop trigger if exists obs_sessies_bijgewerkt on public.observatie_sessies;
create trigger obs_sessies_bijgewerkt before update on public.observatie_sessies
  for each row execute function public.obs_bijgewerkt();


-- ───────────────────────────────────────────────────────────────────────
--  2. OBSERVATIE_SESSIE_DOELEN — welke leerdoelen staan centraal
--
--  Je hebt al een doelenbibliotheek van ~480 rijen (domein, leerlijn,
--  aspect, niveau). Die gebruiken we, in plaats van dat de app zijn
--  eigen lijstje leerdoelen bijhoudt.
-- ───────────────────────────────────────────────────────────────────────
create table if not exists public.observatie_sessie_doelen (
  sessie_id  uuid not null references public.observatie_sessies(id) on delete cascade,
  doel_id    uuid not null references public.doelen(id)             on delete cascade,
  primary key (sessie_id, doel_id)
);

create index if not exists obs_sessie_doelen_doel_idx
  on public.observatie_sessie_doelen(doel_id);


-- ───────────────────────────────────────────────────────────────────────
--  3. OBSERVATIE_NOTITIES — één waarneming bij één kind
--
--  Bewust een nieuwe tabel naast je bestaande `observaties`, niet een
--  uitbreiding daarvan: `observaties` is de korte doel-observatie van het
--  planbord (doel + stand + notitie, allebei NOT NULL). Daar kolommen aan
--  toevoegen raakt een tabel waar het planbord live in schrijft. Zie
--  sectie 6 voor de view die beide bronnen weer samenvoegt.
--
--  groep_id staat hier ook in, dubbelop met de sessie. Dat is bewust: de
--  RLS-policy kan daardoor op de rij zelf beslissen zonder join. De
--  samengestelde foreign key naar (sessie_id, groep_id) garandeert dat die
--  kopie nooit uit de pas loopt — de database weigert een foute combinatie.
-- ───────────────────────────────────────────────────────────────────────
create table if not exists public.observatie_notities (
  id                uuid primary key default gen_random_uuid(),
  sessie_id         uuid not null,
  groep_id          uuid not null references public.groepen(id)    on delete cascade,
  leerling_id       uuid not null references public.leerlingen(id) on delete cascade,
  door              uuid not null references public.profielen(id)  on delete restrict,

  status            text not null check (status in ('ok','niet_gezien','notitie')),

  tags              text[] not null default '{}',
  eigen_tags        text[] not null default '{}',
  notitie           text,
  transcript        text,
  portfolio_zin     text,
  overdracht_zin    text,

  sociaal           text check (sociaal in ('alleen','duo','groep')),
  hoek_id           uuid references public.hoeken(id) on delete set null,
  hoek_vrij         text,
  doel_id           uuid references public.doelen(id) on delete set null,

  foto              text,                            -- pad in de bucket
  foto_alleen_zelf  boolean not null default true,   -- true = buiten élke export

  ts                timestamptz not null default now(),
  client_id         text unique,
  aangemaakt        timestamptz not null default now(),
  bijgewerkt        timestamptz not null default now(),

  foreign key (sessie_id, groep_id)
    references public.observatie_sessies(id, groep_id) on delete cascade
);

create index if not exists obs_notities_sessie_idx   on public.observatie_notities(sessie_id);
create index if not exists obs_notities_leerling_idx on public.observatie_notities(leerling_id, ts desc);
create index if not exists obs_notities_groep_idx    on public.observatie_notities(groep_id, ts desc);

drop trigger if exists obs_notities_bijgewerkt on public.observatie_notities;
create trigger obs_notities_bijgewerkt before update on public.observatie_notities
  for each row execute function public.obs_bijgewerkt();


-- ───────────────────────────────────────────────────────────────────────
--  4. ROW LEVEL SECURITY
--
--  Zien:     alles van de groepen waaraan je via groep_leden hangt.
--  Bewerken: alleen je eigen observaties. Een duo-collega leest mee,
--            maar wijzigt jouw waarnemingen niet.
--  Dit wordt door de database afgedwongen — ook wie rechtstreeks met
--  curl de API aanroept komt er niet langs.
-- ───────────────────────────────────────────────────────────────────────
alter table public.observatie_sessies       enable row level security;
alter table public.observatie_sessie_doelen enable row level security;
alter table public.observatie_notities      enable row level security;

-- ── observatie_sessies ──
drop policy if exists obs_sessies_lezen on public.observatie_sessies;
create policy obs_sessies_lezen on public.observatie_sessies for select to authenticated
  using ( public.obs_groep_toegang(groep_id) );

drop policy if exists obs_sessies_toevoegen on public.observatie_sessies;
create policy obs_sessies_toevoegen on public.observatie_sessies for insert to authenticated
  with check ( public.obs_groep_toegang(groep_id) and door = auth.uid() );

drop policy if exists obs_sessies_wijzigen on public.observatie_sessies;
create policy obs_sessies_wijzigen on public.observatie_sessies for update to authenticated
  using      ( public.obs_groep_toegang(groep_id) and door = auth.uid() )
  with check ( public.obs_groep_toegang(groep_id) and door = auth.uid() );

drop policy if exists obs_sessies_verwijderen on public.observatie_sessies;
create policy obs_sessies_verwijderen on public.observatie_sessies for delete to authenticated
  using ( public.obs_groep_toegang(groep_id) and door = auth.uid() );

-- ── observatie_sessie_doelen (volgt de sessie) ──
drop policy if exists obs_sessie_doelen_lezen on public.observatie_sessie_doelen;
create policy obs_sessie_doelen_lezen on public.observatie_sessie_doelen for select to authenticated
  using ( exists (select 1 from public.observatie_sessies s
                  where s.id = sessie_id and public.obs_groep_toegang(s.groep_id)) );

drop policy if exists obs_sessie_doelen_schrijven on public.observatie_sessie_doelen;
create policy obs_sessie_doelen_schrijven on public.observatie_sessie_doelen for all to authenticated
  using      ( exists (select 1 from public.observatie_sessies s
                       where s.id = sessie_id and s.door = auth.uid()) )
  with check ( exists (select 1 from public.observatie_sessies s
                       where s.id = sessie_id and s.door = auth.uid()) );

-- ── observatie_notities ──
drop policy if exists obs_notities_lezen on public.observatie_notities;
create policy obs_notities_lezen on public.observatie_notities for select to authenticated
  using ( public.obs_groep_toegang(groep_id) );

drop policy if exists obs_notities_toevoegen on public.observatie_notities;
create policy obs_notities_toevoegen on public.observatie_notities for insert to authenticated
  with check ( public.obs_groep_toegang(groep_id) and door = auth.uid() );

drop policy if exists obs_notities_wijzigen on public.observatie_notities;
create policy obs_notities_wijzigen on public.observatie_notities for update to authenticated
  using      ( public.obs_groep_toegang(groep_id) and door = auth.uid() )
  with check ( public.obs_groep_toegang(groep_id) and door = auth.uid() );

drop policy if exists obs_notities_verwijderen on public.observatie_notities;
create policy obs_notities_verwijderen on public.observatie_notities for delete to authenticated
  using ( public.obs_groep_toegang(groep_id) and door = auth.uid() );

grant usage on schema public to authenticated;
grant select, insert, update, delete
  on public.observatie_sessies, public.observatie_sessie_doelen, public.observatie_notities
  to authenticated;


-- ───────────────────────────────────────────────────────────────────────
--  5. FOTO-BUCKET
--
--  Aparte bucket naast je bestaande kb-media, omdat observatiefoto's een
--  eigen privacyregel hebben: `foto_alleen_zelf` houdt ze buiten élke
--  export. Die regel wil je niet vermengen met gewone klasmedia.
--  Privé, dus alleen op te halen met een tijdelijke signed URL.
--  Padafspraak:  <groep_id>/<sessie_id>/<bestandsnaam>
-- ───────────────────────────────────────────────────────────────────────
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('observatie-media', 'observatie-media', false, 5242880,
        array['image/jpeg','image/png','image/webp'])
on conflict (id) do update
  set public             = false,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists observatie_media_lezen on storage.objects;
create policy observatie_media_lezen on storage.objects for select to authenticated
  using ( bucket_id = 'observatie-media'
          and public.obs_groep_toegang( ((storage.foldername(name))[1])::uuid ) );

drop policy if exists observatie_media_toevoegen on storage.objects;
create policy observatie_media_toevoegen on storage.objects for insert to authenticated
  with check ( bucket_id = 'observatie-media'
               and public.obs_groep_toegang( ((storage.foldername(name))[1])::uuid ) );

drop policy if exists observatie_media_wijzigen on storage.objects;
create policy observatie_media_wijzigen on storage.objects for update to authenticated
  using ( bucket_id = 'observatie-media'
          and public.obs_groep_toegang( ((storage.foldername(name))[1])::uuid ) );

drop policy if exists observatie_media_verwijderen on storage.objects;
create policy observatie_media_verwijderen on storage.objects for delete to authenticated
  using ( bucket_id = 'observatie-media'
          and public.obs_groep_toegang( ((storage.foldername(name))[1])::uuid ) );


-- ───────────────────────────────────────────────────────────────────────
--  6. KIND_TIJDLIJN — beide observatiebronnen in één overzicht
--
--  Zo blijft `observaties` (planbord) intact én ziet de leerkracht in de
--  observatie-app tóch één doorlopende tijdlijn per kind.
--  Een view erft de RLS van de onderliggende tabellen.
-- ───────────────────────────────────────────────────────────────────────
create or replace view public.kind_tijdlijn
with (security_invoker = true) as
  select
    n.leerling_id, n.groep_id, n.door,
    n.ts                        as moment,
    'kijk-mee'::text            as bron,
    n.status,
    coalesce(n.portfolio_zin, n.notitie) as tekst,
    n.tags,
    n.doel_id,
    n.id                        as bron_id
  from public.observatie_notities n
union all
  select
    o.leerling_id, o.groep_id, o.door,
    o.datum::timestamptz        as moment,
    'planbord'::text            as bron,
    o.stand                     as status,
    o.notitie                   as tekst,
    '{}'::text[]                as tags,
    o.doel_id,
    o.id                        as bron_id
  from public.observaties o;

grant select on public.kind_tijdlijn to authenticated;

commit;

-- ═══════════════════════════════════════════════════════════════════════
--  KLAAR. Draai daarna 03_controle.sql om te zien dat het klopt.
-- ═══════════════════════════════════════════════════════════════════════
