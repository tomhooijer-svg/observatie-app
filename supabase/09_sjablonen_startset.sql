-- ═══════════════════════════════════════════════════════════════════════
--  09_sjablonen_startset.sql   —   OPTIONEEL, schrijft wél weg
--
--  Een startset periodesjablonen voor een instroomgroep. Alles is daarna
--  gewoon aan te passen of weg te gooien in de app.
--
--  Draait alleen als er nog geen sjablonen staan, dus herhalen is veilig.
-- ═══════════════════════════════════════════════════════════════════════

do $$
declare
  mijn_id  uuid := '816f1e70-fd8d-44d9-985e-2656728a743b';   -- tomhooijer@gmail.com
  mijn_grp uuid;
begin
  select groep_id into mijn_grp
  from public.groep_leden where profiel_id = mijn_id limit 1;

  if mijn_grp is null then
    raise exception 'Geen groep gevonden voor dit profiel.';
  end if;

  if exists (select 1 from public.periode_sjablonen where groep_id = mijn_grp) then
    raise notice 'Er staan al sjablonen voor deze groep — niets gedaan.';
    return;
  end if;

  insert into public.periode_sjablonen
    (groep_id, naam, soort, van_maand, van_dag, tot_maand, tot_dag,
     start_na_dagen, duur_dagen, volgorde, door)
  values
    -- schoolbrede momenten
    (mijn_grp, 'Startgesprekken',        'school',  9,  1, 10, 15, null, null, 1, mijn_id),
    (mijn_grp, 'Midden van het jaar',    'school',  1, 15,  2, 28, null, null, 2, mijn_id),
    (mijn_grp, 'Einde van het jaar',     'school',  6,  1,  7, 15, null, null, 3, mijn_id),

    -- het eigen spoor van een instromend kind, geteld vanaf de instroomdatum
    (mijn_grp, 'Wenperiode',             'kind',  null, null, null, null,   0, 30, 4, mijn_id),
    (mijn_grp, 'Welkomstgesprek',        'kind',  null, null, null, null,  42, 14, 5, mijn_id),
    (mijn_grp, 'Evaluatie na 3 maanden', 'kind',  null, null, null, null,  90, 21, 6, mijn_id);

  raise notice 'Zes sjablonen klaargezet voor groep %.', mijn_grp;
end $$;

select naam, soort,
       case when soort = 'school'
            then van_dag || '/' || van_maand || ' t/m ' || tot_dag || '/' || tot_maand
            else 'vanaf dag ' || start_na_dagen || ', ' || duur_dagen || ' dagen'
       end as wanneer,
       volgorde
from public.periode_sjablonen
order by volgorde;
