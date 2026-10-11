-- ═══════════════════════════════════════════════════════════════════════
--  01_verkenning.sql   —   ALLEEN LEZEN, verandert niets
--
--  Doel: uitvinden hoe je planbord-tabellen heten, zodat de nieuwe
--  observatie-tabellen daar met echte foreign keys naar kunnen verwijzen.
--
--  Plak dit in Supabase → SQL Editor → Run, en stuur de uitvoer terug.
--  Er staat geen enkele leerlingnaam of andere persoonsgegevens in:
--  alleen tabel- en kolomnamen, datatypes en RLS-status.
-- ═══════════════════════════════════════════════════════════════════════

with tabellen as (
  select c.oid, c.relname, c.relrowsecurity
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'r'
),
regels as (

  -- 1. welke tabellen bestaan er, en staat RLS aan?
  select 1 as blok, t.relname as sorteer1, '' as sorteer2,
         'TABEL     ' || rpad(t.relname, 28) ||
         case when t.relrowsecurity then 'RLS: aan' else 'RLS: UIT' end ||
         '   rijen±' || coalesce((select reltuples::bigint from pg_class where oid = t.oid), 0)::text as regel
  from tabellen t

  union all

  -- 2. kolommen + datatypes (dit bepaalt het type van mijn foreign keys)
  select 2, t.relname, a.attname,
         'KOLOM     ' || rpad(t.relname || '.' || a.attname, 40) ||
         format_type(a.atttypid, a.atttypmod) ||
         case when a.attnotnull then ' NOT NULL' else '' end
  from tabellen t
  join pg_attribute a on a.attrelid = t.oid
  where a.attnum > 0 and not a.attisdropped

  union all

  -- 3. primary keys en foreign keys tussen je bestaande tabellen
  select 3, t.relname, con.conname,
         'SLEUTEL   ' || rpad(t.relname, 24) ||
         case con.contype when 'p' then 'PK  ' when 'f' then 'FK  ' when 'u' then 'UNIQ' end ||
         pg_get_constraintdef(con.oid)
  from pg_constraint con
  join tabellen t on t.oid = con.conrelid
  where con.contype in ('p','f','u')

  union all

  -- 4. bestaande RLS-policies (mijn policies mogen hier niet mee botsen)
  select 4, p.tablename, p.policyname,
         'POLICY    ' || rpad(p.tablename, 24) || p.policyname || '  [' || p.cmd || ']'
  from pg_policies p
  where p.schemaname = 'public'

  union all

  -- 5. storage buckets die er al zijn
  select 5, b.id, '',
         'BUCKET    ' || rpad(b.id, 28) || case when b.public then 'openbaar' else 'privé' end
  from storage.buckets b
)
select regel from regels order by blok, sorteer1, sorteer2;
