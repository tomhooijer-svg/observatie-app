-- ═══════════════════════════════════════════════════════════════════════
--  06_toegang_delegeren.sql
--
--  Rondt het openstaande punt af: obs_groep_toegang() gaat de bestaande
--  mag_bij_groep() volgen, zodat de observatie-app exact dezelfde
--  toegangsregel hanteert als het planbord. Eén regel, één plek.
--
--  Het blok hieronder zoekt mag_bij_groep zelf op en past zich aan de
--  signatuur aan. Vindt hij hem niet, dan blijft de oude regel staan en
--  zegt hij dat — er gaat niets stuk.
--
--  IDEMPOTENT. Draai in de SQL Editor en lees de NOTICE-regels.
-- ═══════════════════════════════════════════════════════════════════════

do $$
declare
  argumenten text;
  retour     text;
  definer    boolean;
begin
  select pg_get_function_identity_arguments(p.oid),
         pg_catalog.format_type(p.prorettype, null),
         p.prosecdef
    into argumenten, retour, definer
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'mag_bij_groep'
  order by p.oid
  limit 1;

  if argumenten is null then
    raise notice 'LET OP: mag_bij_groep() niet gevonden. obs_groep_toegang blijft op groep_leden.';

  elsif retour <> 'boolean' then
    raise notice 'LET OP: mag_bij_groep geeft % terug in plaats van boolean. Niets gewijzigd.', retour;

  elsif argumenten !~ '^[a-z_ ]*uuid$' then
    raise notice 'LET OP: onverwachte signatuur mag_bij_groep(%). Niets gewijzigd — stuur deze regel door.', argumenten;

  else
    execute $f$
      create or replace function public.obs_groep_toegang(gid uuid)
      returns boolean
      language sql stable security definer
      set search_path = public, pg_temp
      as 'select public.mag_bij_groep(gid)';
    $f$;
    raise notice 'OK: obs_groep_toegang volgt nu mag_bij_groep(%) [%].',
      argumenten, case when definer then 'security definer' else 'invoker' end;
  end if;
end $$;


-- ───────────────────────────────────────────────────────────────────────
--  Daarnaast: kind_tijdlijn had een fout die ik bij het lezen van je
--  keuzebord-code ontdekte.
--
--  Ik zette observaties.stand in dezelfde kolom als mijn eigen status.
--  Dat zijn twee verschillende dingen:
--      status  = heb ik dit kind deze ronde gezien?   ok | niet_gezien | notitie
--      stand   = waar staat dit kind op dit doel?     nog | bezig | behaald
--  In één kolom gemengd leest geen enkele export ze nog goed uit elkaar.
--  Daarom nu twee aparte kolommen.
-- ───────────────────────────────────────────────────────────────────────
drop view if exists public.kind_tijdlijn;

create view public.kind_tijdlijn
with (security_invoker = true) as
  select
    n.leerling_id, n.groep_id, n.door,
    n.ts                                  as moment,
    'kijk-mee'::text                      as bron,
    n.status                              as status,
    null::text                            as stand,
    coalesce(n.portfolio_zin, n.notitie)  as tekst,
    n.tags,
    n.doel_id,
    n.id                                  as bron_id
  from public.observatie_notities n
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


-- ───────────────────────────────────────────────────────────────────────
--  Controle: ziet het schoolbeheerdersaccount nu hetzelfde als in het
--  planbord? De twee kolommen horen gelijk op te lopen.
-- ───────────────────────────────────────────────────────────────────────
begin;
  set local role authenticated;
  set local request.jwt.claims =
    '{"sub":"be2d3d9d-fac4-498f-8001-4c15e1ef4f5d","role":"authenticated"}';

  select 'schoolbeheerder' as account,
         (select count(*) from public.groepen)              as planbord_groepen,
         (select count(*) from public.observatie_sessies)   as kijkmee_sessies,
         (select count(*) from public.groepen g
           where public.obs_groep_toegang(g.id))            as groepen_volgens_mij;
rollback;

begin;
  set local role authenticated;
  set local request.jwt.claims =
    '{"sub":"816f1e70-fd8d-44d9-985e-2656728a743b","role":"authenticated"}';

  select 'leerkracht' as account,
         (select count(*) from public.groepen)              as planbord_groepen,
         (select count(*) from public.groepen g
           where public.obs_groep_toegang(g.id))            as groepen_volgens_mij;
rollback;
