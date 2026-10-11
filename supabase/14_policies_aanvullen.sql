-- ═══════════════════════════════════════════════════════════════════════
--  14_policies_aanvullen.sql
--
--  ÉÉN BESTAND, IN ZIJN GEHEEL DRAAIEN. Veilig om te herhalen.
--
--  observatie_sessies, observatie_notities en observatie_sessie_doelen
--  hadden RLS aan staan met nul policies. In Postgres betekent dat: alles
--  geweigerd, voor iedereen, ook voor de eigenaar van de rij. Dat was de
--  echte reden dat de insert op observatie_sessies faalde.
--
--  Deze policies stonden in script 02 maar zijn daar niet aangekomen.
--  Hier staan ze opnieuw, woordelijk hetzelfde:
--      lezen   = iedereen met toegang tot de groep
--      maken   = idem, en op je eigen naam
--      wijzigen/verwijderen = alleen je eigen observaties
--
--  Schrijft nergens in een planbord-tabel.
-- ═══════════════════════════════════════════════════════════════════════

begin;

alter table public.observatie_sessies       enable row level security;
alter table public.observatie_sessie_doelen enable row level security;
alter table public.observatie_notities      enable row level security;

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

commit;


-- ═══════════════════════════════════════════════════════════════════════
--  CONTROLE — alle policies op de observatie-tabellen, bij naam.
--  Geen tellingen meer: je ziet precies wat er staat.
-- ═══════════════════════════════════════════════════════════════════════
select rpad(t.tabel, 28) ||
       case when p.policyname is null
            then '!! GEEN POLICIES — tabel is op slot'
            else rpad(p.policyname, 32) || p.cmd
       end as regel
from (values
        ('observatie_sessies'), ('observatie_sessie_doelen'), ('observatie_notities'),
        ('observatie_standen'), ('observatie_leerling'),
        ('periodes'), ('periode_sjablonen'), ('periode_focus')
     ) as t(tabel)
left join pg_policies p
       on p.schemaname = 'public' and p.tablename = t.tabel
order by t.tabel, p.cmd, p.policyname;
