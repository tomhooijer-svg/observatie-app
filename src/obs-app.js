/* ═══════════════════════════════════════════════════════════════════════
   Het beginscherm: welke groepen mag ik zien, en wie zitten daarin.

   Dit scherm is bewust klein gehouden. Het doel is te laten zien dat de
   afscherming klopt met een échte login: zie je hier je groepen en je
   kinderen, dan doen de rechtenregels in de database wat ze moeten doen.
   ═══════════════════════════════════════════════════════════════════════ */
(function () {
'use strict';

var $ = function (id) { return document.getElementById(id); };
var ik = null;
var gekozenGroep = null;

/* Welke groep stond er de vorige keer open? Alleen een gemak, dus als
   localStorage niet werkt gaan we gewoon door. */
var LAATSTE = 'obs_laatste_groep';
function onthoud(id){ try { localStorage.setItem(LAATSTE, id); } catch (e) {} }
function laatste(){ try { return localStorage.getItem(LAATSTE); } catch (e) { return null; } }

function tekst(el, t){ el.textContent = t; }

function fout(bericht, details){
  $('blad').innerHTML =
    '<div class="leeg"><div class="groot">⚠️</div>' +
    '<p><strong>' + bericht + '</strong></p>' +
    (details ? '<p style="font-size:.85rem;margin-top:8px">' + details + '</p>' : '') +
    '</div>';
}

/* ── start ─────────────────────────────────────────────────────────── */
if (!OBS.zorgVoorLogin()) { /* we worden doorgestuurd */ }
else {
  SB.wieBenIk().then(function (uit) {
    ik = uit;
    if (!ik.profiel) {
      fout('Je bent ingelogd, maar er hoort nog geen profiel bij dit account.',
           'Vraag de schoolbeheerder om je toe te voegen.');
      return;
    }
    if (!ik.profiel.school_id) {
      fout('Je account hangt nog niet aan een school.',
           'Daardoor is er nog niets te zien. De schoolbeheerder kan dit koppelen.');
      return;
    }
    tekst($('waar'), (ik.school && ik.school.naam ? ik.school.naam + ' · ' : '') +
                     (ik.profiel.naam || ik.profiel.email || '') +
                     (ik.profiel.rol === 'schoolbeheerder' ? ' · beheer' : ''));

    var groepen = ik.groepen || [];
    if (!groepen.length) {
      fout('Je ziet nog geen groepen.',
           'Dat betekent dat je aan geen enkele groep gekoppeld bent, of dat de ' +
           'groepen bij een andere school horen.');
      return;
    }
    var terug = laatste();
    var eerder = groepen.filter(function (g) { return g.id === terug; })[0];
    if (eerder) toonKinderen(eerder); else toonGroepen(groepen);
  }).catch(function (e) {
    if (OBS.isVerlopen(e)) {
      OBS.terugNaarLogin('Je sessie is verlopen. Log opnieuw in.');
    } else if (e && e.offline) {
      fout('Geen verbinding met de server.', 'Probeer het zo nog eens.');
    } else {
      fout('Het ophalen is niet gelukt.', (e && e.message) || '');
    }
  });
}

/* ── de groepen ────────────────────────────────────────────────────── */
function kleurVan(groep){
  var u = groep.uiterlijk || {};
  return u.kleur || u.accent || '#3b6ff0';
}
function kortVan(naam){
  var r = String(naam || '').replace(/^\s*groep\s*/i, '').trim();
  return (r || String(naam || '')).slice(0, 4);
}

function toonGroepen(groepen){
  gekozenGroep = null;
  var h = '<h2>Kies een groep</h2>' +
          '<p class="sub">' + groepen.length + ' ' +
          (groepen.length === 1 ? 'groep' : 'groepen') + ' waar jij bij mag.</p>' +
          '<div class="groepen">';
  groepen.forEach(function (g) {
    h += '<button class="groepkaart" data-id="' + g.id + '">' +
           '<span class="bol" style="background:' + kleurVan(g) + '">' +
             veilig(kortVan(g.naam)) + '</span>' +
           '<span class="gn">' + veilig(g.naam) + '</span>' +
           '<span class="gs">kinderen bekijken</span>' +
         '</button>';
  });
  h += '</div>';
  $('blad').innerHTML = h;

  /* Per knop een luisteraar, niet één op het blad: dat blad blijft staan
     terwijl de inhoud wisselt, en dan stapelen de luisteraars zich op. */
  Array.prototype.forEach.call($('blad').querySelectorAll('.groepkaart'), function (k) {
    k.addEventListener('click', function () {
      var g = groepen.filter(function (x) { return x.id === k.dataset.id; })[0];
      if (g) toonKinderen(g);
    });
  });
}

/* ── de kinderen van één groep ─────────────────────────────────────── */
function toonKinderen(groep){
  gekozenGroep = groep;
  onthoud(groep.id);
  $('blad').innerHTML = '<div class="leeg"><div class="groot">⏳</div><p>Kinderen ophalen…</p></div>';

  SB.lees('leerlingen', {
    kies: 'id,naam,kleur,foto_pad,volgorde,actief',
    waar: { groep_id: 'eq.' + groep.id, actief: 'is.true' },
    volgorde: 'volgorde,naam'
  }).then(function (rijen) {
    var kinderen = rijen || [];
    var meer = (ik.groepen || []).length > 1;

    var h = '<h2>' + veilig(groep.naam) + '</h2>' +
            '<p class="sub">' + kinderen.length + ' ' +
            (kinderen.length === 1 ? 'kind' : 'kinderen') +
            (meer ? ' · <button class="knop knop-stil knop-klein" id="andere">andere groep</button>' : '') +
            '</p>';

    if (!kinderen.length) {
      h += '<div class="leeg"><div class="groot">👶</div>' +
           '<p>Deze groep heeft nog geen kinderen.</p>' +
           '<p style="font-size:.85rem">Voeg ze toe in het Planbord; ze verschijnen hier vanzelf.</p></div>';
    } else {
      h += '<div class="kinderen">';
      kinderen.forEach(function (l) {
        h += '<div class="picto kind" data-id="' + l.id + '">' +
               '<div class="picto-rond" id="rond-' + l.id + '" ' +
                    'style="background-color:' + (l.kleur || '#8a94a6') + '">' +
                 veilig(initialen(l.naam)) +
               '</div>' +
               '<div class="picto-naam">' + veilig(l.naam) + '</div>' +
             '</div>';
      });
      h += '</div>';
    }
    $('blad').innerHTML = h;

    var andere = $('andere');
    if (andere) andere.addEventListener('click', function () { toonGroepen(ik.groepen); });

    /* Foto's komen uit de afgesloten emmer van het Keuzebord, dus met een
       tijdelijke link per kind. Dat gebeurt na het tekenen: de lijst staat
       er dan al, en de gezichten vallen erin zodra ze binnen zijn. */
    kinderen.forEach(function (l) {
      if (!l.foto_pad) return;
      OBS.fotoLink(l.foto_pad, OBS.EMMER_KB).then(function (url) {
        var el = $('rond-' + l.id);
        if (!el || !url) return;
        el.style.backgroundImage = 'url("' + url + '")';
        el.textContent = '';
      });
    });
  }).catch(function (e) {
    if (OBS.isVerlopen(e)) OBS.terugNaarLogin('Je sessie is verlopen. Log opnieuw in.');
    else if (e && e.offline) fout('Geen verbinding met de server.', 'Probeer het zo nog eens.');
    else fout('De kinderen konden niet worden opgehaald.', (e && e.message) || '');
  });
}

function initialen(naam){
  var d = String(naam || '').trim().split(/\s+/);
  if (!d[0]) return '?';
  return (d.length === 1 ? d[0].slice(0, 2) : d[0][0] + d[d.length - 1][0]).toUpperCase();
}

function veilig(t){
  return String(t == null ? '' : t).replace(/[&<>"']/g, function (c) {
    return { '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;' }[c];
  });
}

/* ── scherm verbergen ──────────────────────────────────────────────── */
/* Kinderen kijken mee. Eén tik en alles is weg; hij blijft ook weg als je
   per ongeluk ergens anders tikt. */
$('verberg').addEventListener('click', function () { $('deken').classList.add('aan'); });
$('deken-uit').addEventListener('click', function () { $('deken').classList.remove('aan'); });

$('uit').addEventListener('click', function () {
  OBS.uitloggen();
});

})();
