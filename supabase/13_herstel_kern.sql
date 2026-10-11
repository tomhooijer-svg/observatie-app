-- ═══════════════════════════════════════════════════════════════════════
--  13_herstel_kern.sql
--
--  ÉÉN BESTAND, IN ZIJN GEHEEL DRAAIEN. Geen blokken, geen nagebootste
--  logins. Veilig om te herhalen. Onderaan komt één overzicht van wat er
--  daarna werkelijk in je database staat.
--
--  Dit is het laatste wat je in de SQL-editor hoeft te doen voordat we
--  de app gaan bouwen. De afscherming testen we daarna met een echte
--  login, want dan stuurt de browser een echt token mee.
--
--  Herstelt twee dingen, en schrijft NERGENS in een planbord-tabel:
--    1. obs_groep_toegang volgt nu echt mag_bij_groep  (één plek, geen DO-blok)
--    2. de foto-policies kunnen niet meer struikelen over een pad dat
--       niet met een uuid begint
--
--  Het invullen van profielen.school_id zat hier eerst bij. Dat bleek de
--  trigger profiel_bewaken() te raken, die updates weigert als er niemand
--  is ingelogd — en dat gooide de héle transactie weg, inclusief het
--  herstel hierboven. Die stap is nu losgetrokken: eerst kijken of het
--  überhaupt nodig is, zie het overzicht onderaan.
-- ═══════════════════════════════════════════════════════════════════════

begin;

-- ── 1. Veilig een uuid uit een tekst halen ───────────────────────────
--  Levert null in plaats van een fout als de tekst geen uuid is.
--  Nodig omdat storage.objects gedeeld wordt met kb-media: één bestand
--  met een pad dat niet met een groep-uuid begint, en een cast zou de
--  hele bucket onleesbaar maken met een harde fout.
create or replace function public.obs_uuid_of_null(t text)
returns uuid
language plpgsql
immutable
as $$
begin
  return t::uuid;
exception when others then
  return null;
end;
$$;


-- ── 2. De toegangsregel, nu op één plek ──────────────────────────────
--  mag_bij_groep(g uuid) doet:
--      groep.school_id = mijn_school()
--      EN (ben_schoolbeheerder() OF zit_in_groep(g))
--  Daarmee krijgt een schoolbeheerder toegang tot alle groepen van zijn
--  school, ook zonder rij in groep_leden. Precies wat het beheeraccount
--  nodig heeft.
create or replace function public.obs_groep_toegang(gid uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.mag_bij_groep(gid);
$$;


-- ── 3. Foto-policies opnieuw, met de veilige cast ────────────────────
drop policy if exists observatie_media_lezen       on storage.objects;
drop policy if exists observatie_media_toevoegen   on storage.objects;
drop policy if exists observatie_media_wijzigen    on storage.objects;
drop policy if exists observatie_media_verwijderen on storage.objects;

create policy observatie_media_lezen on storage.objects for select to authenticated
  using ( bucket_id = 'observatie-media'
          and public.obs_groep_toegang(
                public.obs_uuid_of_null((storage.foldername(name))[1]) ) );

create policy observatie_media_toevoegen on storage.objects for insert to authenticated
  with check ( bucket_id = 'observatie-media'
               and public.obs_groep_toegang(
                     public.obs_uuid_of_null((storage.foldername(name))[1]) ) );

create policy observatie_media_wijzigen on storage.objects for update to authenticated
  using ( bucket_id = 'observatie-media'
          and public.obs_groep_toegang(
                public.obs_uuid_of_null((storage.foldername(name))[1]) ) );

create policy observatie_media_verwijderen on storage.objects for delete to authenticated
  using ( bucket_id = 'observatie-media'
          and public.obs_groep_toegang(
                public.obs_uuid_of_null((storage.foldername(name))[1]) ) );


commit;


-- ═══════════════════════════════════════════════════════════════════════
--  HET OVERZICHT — dit is de enige uitkomst die je ziet
-- ═══════════════════════════════════════════════════════════════════════
with regels as (

  select 1 as blok, '' as s1, '' as s2,
         '── ACCOUNTS ────────────────────────────────────────────' as regel
  union all
  select 2, p.rol, coalesce(p.email,''),
         rpad(coalesce(p.email,'(geen email)'), 34) ||
         rpad(p.rol, 18) ||
         case when p.school_id is null then 'SCHOOL LEEG — ziet niets'
              else 'school ok' end ||
         '   groepen in groep_leden: ' ||
         (select count(*) from public.groep_leden gl where gl.profiel_id = p.id)::text ||
         '   verwachte toegang: ' ||
         (select count(*) from public.groepen g
           where g.school_id = p.school_id
             and (p.rol = 'schoolbeheerder'
                  or exists (select 1 from public.groep_leden gl
                             where gl.groep_id = g.id and gl.profiel_id = p.id)))::text ||
         ' groepen'
  from public.profielen p

  union all
  select 3, '', '', '── TOEGANGSREGEL ───────────────────────────────────────'
  union all
  select 4, '', '',
         'obs_groep_toegang volgt mag_bij_groep: ' ||
         case when pg_get_functiondef(p.oid) like '%mag_bij_groep%'
              then 'JA' else 'NEE — herstel niet gelukt' end
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'obs_groep_toegang'

  union all
  select 5, '', '', '── MIJN TABELLEN ───────────────────────────────────────'
  union all
  select 6, t.naam, '',
         rpad(t.naam, 30) || 'rijen: ' || t.aantal::text ||
         '   policies: ' ||
         (select count(*) from pg_policies pp
           where pp.schemaname='public' and pp.tablename = t.naam)::text
  from (
    select 'observatie_sessies'::text       as naam, (select count(*) from public.observatie_sessies)       as aantal
    union all select 'observatie_sessie_doelen', (select count(*) from public.observatie_sessie_doelen)
    union all select 'observatie_notities',      (select count(*) from public.observatie_notities)
    union all select 'observatie_standen',       (select count(*) from public.observatie_standen)
    union all select 'observatie_leerling',      (select count(*) from public.observatie_leerling)
    union all select 'periodes',                 (select count(*) from public.periodes)
    union all select 'periode_sjablonen',        (select count(*) from public.periode_sjablonen)
    union all select 'periode_focus',            (select count(*) from public.periode_focus)
  ) t

  union all
  select 7, '', '', '── FOTO-POLICIES ───────────────────────────────────────'
  union all
  select 8, pp.policyname, '',
         rpad(pp.policyname, 32) || pp.cmd || '   ' ||
         case when coalesce(pp.qual,'') || coalesce(pp.with_check,'') like '%obs_uuid_of_null%'
              then 'veilige cast' else 'LET OP: oude cast' end
  from pg_policies pp
  where pp.schemaname = 'storage' and pp.tablename = 'objects'
    and pp.policyname like 'observatie_media%'

  union all
  select 85, '', '', '── BEWAKING OP PROFIELEN ───────────────────────────────'
  union all
  select 86, t.tgname, '',
         rpad(t.tgname, 32) || 'trigger op profielen — blokkeert aanpassen buiten de app om'
  from pg_trigger t
  join pg_class c on c.oid = t.tgrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname='public' and c.relname='profielen' and not t.tgisinternal

  union all
  select 9, '', '', '── VIEWS ───────────────────────────────────────────────'
  union all
  select 10, c.relname, '',
         rpad(c.relname, 30) || 'bestaat'
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname='public' and c.relkind='v'
    and c.relname in ('kind_tijdlijn','huidige_stand','periode_dekking',
                      'periode_focus_open','koppeling_voorstel')
)
select regel from regels order by blok, s1, s2;
