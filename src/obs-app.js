/* ═══════════════════════════════════════════════════════════════════════
   Het hoofdscherm: groep kiezen, kinderen zien, observeren.

   Twee manieren van vastleggen:
     - tik op een kind  -> het observatieblad voor dat ene kind
     - "Lijst maken"    -> het raster: kinderen naast doelen, tik een vakje
                           en de stand schuift op. Dat is de digitale versie
                           van de papieren observatielijst.
   ═══════════════════════════════════════════════════════════════════════ */
(function () {
'use strict';

var $ = function (id) { return document.getElementById(id); };
var D = window.OBSDATA;

var ik = null, groep = null, kinderen = [], alleHoeken = [], alleDoelen = [],
    groepsDoelIds = [], standen = {}, modus = 'kinderen', rasterDoelen = [], rasterHoek = null;

var LAATSTE = 'obs_laatste_groep';
function onthoud(id){ try { localStorage.setItem(LAATSTE, id); } catch (e) {} }
function laatste(){ try { return localStorage.getItem(LAATSTE); } catch (e) { return null; } }

function veilig(t){
  return String(t == null ? '' : t).replace(/[&<>"']/g, function (c) {
    return { '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;' }[c];
  });
}
function initialen(naam){
  var d = String(naam || '').trim().split(/\s+/);
  if (!d[0]) return '?';
  return (d.length === 1 ? d[0].slice(0,2) : d[0][0] + d[d.length-1][0]).toUpperCase();
}
function fout(bericht, details){
  $('vel').innerHTML = '<div class="leeg"><div class="groot">⚠️</div><p><strong>' +
    veilig(bericht) + '</strong></p>' +
    (details ? '<p style="font-size:.85rem;margin-top:8px">' + veilig(details) + '</p>' : '') + '</div>';
}
function bezig(tekst){
  $('vel').innerHTML = '<div class="leeg"><div class="groot">⏳</div><p>' + veilig(tekst) + '</p></div>';
}
function stuk(e, wat){
  if (OBS.isVerlopen(e)) { OBS.terugNaarLogin('Je sessie is verlopen. Log opnieuw in.'); return; }
  if (e && e.offline) fout('Geen verbinding met de server.', 'Probeer het zo nog eens.');
  else fout(wat, (e && e.message) || '');
}

/* ── start ────────────────────────────────────────────────────────── */
if (OBS.zorgVoorLogin()) {
  SB.wieBenIk().then(function (uit) {
    ik = uit;
    if (!ik.profiel)            return fout('Er hoort nog geen profiel bij dit account.', 'Vraag de schoolbeheerder om je toe te voegen.');
    if (!ik.profiel.school_id)  return fout('Je account hangt nog niet aan een school.', 'De schoolbeheerder kan dit koppelen.');

    $('waar').textContent = (ik.school && ik.school.naam ? ik.school.naam + ' · ' : '') +
                            (ik.profiel.naam || ik.profiel.email || '');

    var groepen = ik.groepen || [];
    if (!groepen.length) return fout('Je ziet nog geen groepen.', 'Je bent aan geen enkele groep gekoppeld.');

    var terug = groepen.filter(function (g) { return g.id === laatste(); })[0];
    if (terug) kiesGroep(terug); else toonGroepen(groepen);
  }).catch(function (e) { stuk(e, 'Het ophalen is niet gelukt.'); });
}

/* ── groepen ──────────────────────────────────────────────────────── */
function kortVan(naam){
  var r = String(naam || '').replace(/^\s*groep\s*/i, '').trim();
  return (r || String(naam || '')).slice(0, 4);
}
function kleurVan(g){ var u = g.uiterlijk || {}; return u.kleur || u.accent || '#3b6ff0'; }

function toonGroepen(groepen){
  groep = null;
  $('titel').textContent = 'Kijk mee';
  var h = '<h2>Kies een groep</h2><p class="sub">' + groepen.length + ' ' +
          (groepen.length === 1 ? 'groep' : 'groepen') + '</p><div class="groepen">';
  groepen.forEach(function (g) {
    h += '<button class="groepkaart" data-id="' + g.id + '">' +
         '<span class="bol" style="background:' + kleurVan(g) + '">' + veilig(kortVan(g.naam)) + '</span>' +
         '<span class="gn">' + veilig(g.naam) + '</span>' +
         '<span class="gs">openen</span></button>';
  });
  $('vel').innerHTML = h + '</div>';
  Array.prototype.forEach.call($('vel').querySelectorAll('.groepkaart'), function (k) {
    k.onclick = function () {
      kiesGroep(groepen.filter(function (x) { return x.id === k.dataset.id; })[0]);
    };
  });
}

/* ── een groep openen: alles ophalen wat de rest nodig heeft ──────── */
function kiesGroep(g){
  if (!g) return;
  groep = g; onthoud(g.id);
  $('titel').textContent = g.naam;
  bezig('Groep ophalen…');

  Promise.all([
    SB.lees('leerlingen', {
      kies: 'id,naam,kleur,foto_pad,volgorde',
      waar: { groep_id: 'eq.' + g.id, actief: 'is.true' },
      volgorde: 'volgorde,naam'
    }),
    D.hoeken(g.id),
    D.doelen(),
    D.doelenVanGroep(g.id),
    D.standenVanGroep(g.id)
  ]).then(function (uit) {
    kinderen = uit[0] || []; alleHoeken = uit[1] || []; alleDoelen = uit[2] || [];
    groepsDoelIds = uit[3] || []; standen = uit[4] || {};
    modus = 'kinderen';
    teken();
  }).catch(function (e) { stuk(e, 'De groep kon niet worden opgehaald.'); });
}

function ververs(){
  return D.standenVanGroep(groep.id).then(function (s) { standen = s; teken(); });
}

/* ── tekenen ──────────────────────────────────────────────────────── */
function teken(){
  if (modus === 'raster') return tekenRaster();
  tekenKinderen();
}

function tekenKinderen(){
  var meer = (ik.groepen || []).length > 1;
  var h = '<h2>' + veilig(groep.naam) + '</h2>' +
          '<p class="sub">' + kinderen.length + ' ' + (kinderen.length === 1 ? 'kind' : 'kinderen') +
          ' · tik op een kind om te observeren</p>' +
          '<div class="knoprij">' +
          '<button class="knop knop-primair" id="naar-raster">Lijst maken</button>' +
          (meer ? '<button class="knop knop-stil" id="andere">Andere groep</button>' : '') +
          '</div>';

  if (!kinderen.length) {
    h += '<div class="leeg"><div class="groot">👶</div><p>Deze groep heeft nog geen kinderen.</p>' +
         '<p style="font-size:.85rem">Voeg ze toe in het Planbord.</p></div>';
    $('vel').innerHTML = h;
  } else {
    h += '<div class="kinderen">';
    kinderen.forEach(function (l) {
      var aantal = Object.keys(standen[l.id] || {}).length;
      h += '<div class="picto kind" data-id="' + l.id + '">' +
             (aantal ? '<span class="vink">' + aantal + '</span>' : '') +
             '<div class="picto-rond" id="rond-' + l.id + '" style="background-color:' +
               (l.kleur || '#8a94a6') + '">' + veilig(initialen(l.naam)) + '</div>' +
             '<div class="picto-naam">' + veilig(l.naam) + '</div>' +
           '</div>';
    });
    $('vel').innerHTML = h + '</div>';

    Array.prototype.forEach.call($('vel').querySelectorAll('.kind'), function (el) {
      el.onclick = function () {
        var kind = kinderen.filter(function (x) { return x.id === el.dataset.id; })[0];
        if (kind) observeer(kind);
      };
    });
    laadFotos();
  }

  var r = $('naar-raster'); if (r) r.onclick = naarRaster;
  var a = $('andere');      if (a) a.onclick = function () { toonGroepen(ik.groepen); };
}

function laadFotos(){
  kinderen.forEach(function (l) {
    if (!l.foto_pad) return;
    OBS.fotoLink(l.foto_pad, OBS.EMMER_KB).then(function (url) {
      var el = $('rond-' + l.id);
      if (el && url) { el.style.backgroundImage = 'url("' + url + '")'; el.textContent = ''; }
    });
  });
}

function observeer(kind){
  OBSBLAD.open({
    groep: groep, kind: kind,
    hoeken: alleHoeken, doelen: alleDoelen,
    groepsDoelIds: groepsDoelIds,
    standen: standen[kind.id] || {},
    klaar: ververs
  });
}

/* ── het raster ───────────────────────────────────────────────────── */
function naarRaster(){
  if (!rasterDoelen.length) {
    rasterDoelen = alleDoelen.filter(function (d) {
      return groepsDoelIds.indexOf(d.id) >= 0;
    }).slice(0, 8);
  }
  modus = 'raster';
  teken();
}

function tekenRaster(){
  var h = '<h2>Observatielijst</h2>' +
          '<p class="sub">Tik een vakje om de stand te wisselen: ontdekken → met hulp → zelfstandig → leeg.</p>' +
          '<div class="knoprij">' +
          '<button class="knop knop-stil" id="terug-kinderen">Terug</button>' +
          '<button class="knop knop-stil" id="kies-doelen">Doelen kiezen (' + rasterDoelen.length + ')</button>' +
          '</div>';

  if (!rasterDoelen.length) {
    h += '<div class="leeg"><div class="groot">🎯</div><p>Kies eerst een of meer doelen.</p></div>';
    $('vel').innerHTML = h;
    $('terug-kinderen').onclick = function () { modus = 'kinderen'; teken(); };
    $('kies-doelen').onclick = kiesRasterDoelen;
    return;
  }

  h += '<div class="rasterdoos"><table class="raster"><thead><tr><th>Kind</th>';
  rasterDoelen.forEach(function (d) {
    h += '<th>' + veilig(d.doel) + '</th>';
  });
  h += '</tr></thead><tbody>';
  kinderen.forEach(function (l) {
    h += '<tr><th>' + veilig(l.naam) + '</th>';
    rasterDoelen.forEach(function (d) {
      var st = (standen[l.id] || {})[d.id] || '';
      h += '<td><button class="vak' + (st ? ' gezet' : '') + '" data-kind="' + l.id +
           '" data-doel="' + d.id + '"><span class="bal"' +
           (st ? ' style="background:' + D.STAND_KLEUR[st] + '"' : '') + '>' +
           (st ? '●' : '') + '</span></button></td>';
    });
    h += '</tr>';
  });
  $('vel').innerHTML = h + '</tbody></table></div>';

  $('terug-kinderen').onclick = function () { modus = 'kinderen'; teken(); };
  $('kies-doelen').onclick = kiesRasterDoelen;

  Array.prototype.forEach.call($('vel').querySelectorAll('.vak'), function (b) {
    b.onclick = function () { tikVak(b); };
  });
}

/* Een tik schuift de stand op. We tekenen het vakje meteen bij en sturen
   het daarna pas op: wachten op de server voelt in de klas als haperen. */
function tikVak(b){
  var kindId = b.dataset.kind, doelId = b.dataset.doel;
  var nu = (standen[kindId] || {})[doelId] || '';
  var nieuw = D.volgendeStand(nu);

  standen[kindId] = standen[kindId] || {};
  if (nieuw) standen[kindId][doelId] = nieuw; else delete standen[kindId][doelId];

  var bal = b.querySelector('.bal');
  b.classList.toggle('gezet', !!nieuw);
  bal.style.background = nieuw ? D.STAND_KLEUR[nieuw] : '';
  bal.textContent = nieuw ? '●' : '';

  D.bewaarStand(groep.id, kindId, doelId, nieuw, rasterHoek).catch(function (e) {
    if (OBS.isVerlopen(e)) { OBS.terugNaarLogin('Je sessie is verlopen. Log opnieuw in.'); return; }
    OBSBLAD.melden(e && e.offline ? 'Geen verbinding — deze tik is nog niet bewaard.'
                                  : 'Opslaan lukte niet.');
  });
}

function kiesRasterDoelen(){
  var gekozen = rasterDoelen.map(function (d) { return d.id; });
  var zoek = '';

  function tekenKeus(){
    var lijst;
    if (zoek.trim().length >= 2) {
      var z = zoek.trim().toLowerCase();
      lijst = alleDoelen.filter(function (d) {
        return (d.doel || '').toLowerCase().indexOf(z) >= 0 ||
               (d.leerlijn || '').toLowerCase().indexOf(z) >= 0;
      }).slice(0, 40);
    } else {
      lijst = alleDoelen.filter(function (d) { return groepsDoelIds.indexOf(d.id) >= 0; });
      if (!lijst.length) lijst = alleDoelen.slice(0, 40);
    }

    var h = '<div class="bladkop"><div style="flex:1"><h3>Doelen voor de lijst</h3>' +
            '<div class="kl">' + gekozen.length + ' gekozen</div></div>' +
            '<button class="knop knop-stil knop-klein" id="keus-dicht">Sluiten</button></div>' +
            '<input class="zoek" id="keus-zoek" placeholder="Zoek een doel…" value="' + veilig(zoek) + '">' +
            '<div class="doelkeus" style="max-height:48vh">';
    lijst.forEach(function (d) {
      var aan = gekozen.indexOf(d.id) >= 0;
      h += '<button data-kies="' + d.id + '" style="' +
           (aan ? 'background:var(--accent-zacht)' : '') + '">' +
           (aan ? '✓ ' : '') + veilig(d.doel) +
           '<div class="mt">' + veilig([d.domein, d.leerlijn, d.niveau].filter(Boolean).join(' · ')) +
           '</div></button>';
    });
    h += '</div><div class="bladvoet"><button class="knop knop-primair" id="keus-klaar" style="flex:1">Klaar</button></div>';

    $('blad').innerHTML = h;
    $('keus-dicht').onclick = function () { $('overlay').classList.remove('open'); };
    $('keus-klaar').onclick = function () {
      rasterDoelen = alleDoelen.filter(function (d) { return gekozen.indexOf(d.id) >= 0; });
      $('overlay').classList.remove('open');
      teken();
    };
    var z = $('keus-zoek');
    z.oninput = function () { zoek = z.value; var p = z.selectionStart; tekenKeus();
                              var n = $('keus-zoek'); n.focus(); try { n.setSelectionRange(p,p); } catch(e){} };
    Array.prototype.forEach.call($('blad').querySelectorAll('[data-kies]'), function (b) {
      b.onclick = function () {
        var id = b.dataset.kies, i = gekozen.indexOf(id);
        if (i >= 0) gekozen.splice(i, 1); else gekozen.push(id);
        tekenKeus();
      };
    });
  }

  $('overlay').classList.add('open');
  tekenKeus();
}

/* ── schil ────────────────────────────────────────────────────────── */
$('verberg').onclick   = function () { $('deken').classList.add('aan'); };
$('deken-uit').onclick = function () { $('deken').classList.remove('aan'); };
$('uit').onclick       = function () { OBS.uitloggen(); };

})();
