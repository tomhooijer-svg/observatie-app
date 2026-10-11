/* ═══════════════════════════════════════════════════════════════════════
   Het observatieblad: één kind, een hoek, een of meer doelen, een notitie.

   Dit is het scherm dat snel moet zijn. Je staat in de klas, met één hand,
   en je wilt in een paar tikken klaar zijn. Daarom: de doelen van deze
   groep staan er al, de standknoppen zijn groot, en opslaan kan ook met
   alleen een notitie of alleen een stand.
   ═══════════════════════════════════════════════════════════════════════ */
(function (global) {
'use strict';

var D = null;        /* OBSDATA, pas beschikbaar als alles geladen is */
var staat = null;

function $(id){ return document.getElementById(id); }
function veilig(t){
  return String(t == null ? '' : t).replace(/[&<>"']/g, function (c) {
    return { '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;' }[c];
  });
}

function melden(tekst){
  var m = $('melding');
  m.textContent = tekst;
  m.classList.add('zichtbaar');
  setTimeout(function () { m.classList.remove('zichtbaar'); }, 2600);
}

function sluit(){
  $('overlay').classList.remove('open');
  staat = null;
}

/* ── openen ───────────────────────────────────────────────────────── */
function open(opt){
  /* opt = { groep, kind, hoeken, doelen, groepsDoelIds, standen, klaar } */
  D = global.OBSDATA;
  staat = {
    groep: opt.groep, kind: opt.kind,
    hoeken: opt.hoeken || [], doelen: opt.doelen || [],
    groepsDoelIds: opt.groepsDoelIds || [],
    bestaand: opt.standen || {},
    hoek: null, gekozen: [], standen: {}, notitie: '',
    zoek: '', klaar: opt.klaar || function () {}
  };
  /* Niets staat open. Het blad moet kort beginnen: een notitie typen en
     opslaan is de meest voorkomende handeling, en daar wil je niet eerst
     langs zes opengeklapte doelen voor scrollen. Een doel klap je open
     door het aan te tikken. */
  staat.gekozen = [];

  $('overlay').classList.add('open');
  teken();
}

/* ── tekenen ──────────────────────────────────────────────────────── */
function teken(){
  var s = staat;
  if (!s) return;
  var k = s.kind;

  var h = '<div class="bladkop">' +
    '<div class="rond" id="blad-rond" style="background-color:' + (k.kleur || '#8a94a6') + '">' +
      veilig(initialen(k.naam)) + '</div>' +
    '<div style="flex:1;min-width:0">' +
      '<h3>' + veilig(k.naam) + '</h3>' +
      '<div class="kl">' + veilig(s.groep.naam) + '</div>' +
    '</div>' +
    '<button class="knop knop-stil knop-klein" id="blad-dicht">Sluiten</button>' +
  '</div>';

  /* ── waar ── */
  if (s.hoeken.length) {
    h += '<div class="kop">Waar?</div><div class="chips">';
    s.hoeken.forEach(function (hk) {
      var aan = s.hoek && s.hoek.id === hk.id;
      h += '<button class="chip' + (aan ? ' aan' : '') + '" data-hoek="' + hk.id + '"' +
           (aan && hk.kleur ? ' style="background:' + hk.kleur + '"' : '') + '>' +
           veilig(hk.naam) + '</button>';
    });
    h += '</div>';
  }

  /* ── notitie: staat bovenaan want dit is het meest gebruikt ── */
  h += '<div class="kop">Wat zie je?</div>' +
       '<textarea class="notitie" id="blad-notitie" ' +
       'placeholder="Korte notitie — wat deed dit kind?">' + veilig(s.notitie) + '</textarea>' +
       '<div style="margin-top:8px"><button class="knop knop-stil knop-klein" id="blad-mic">🎙 Inspreken</button></div>';

  /* ── doelen ── */
  h += '<div class="kop">Een doel erbij? <span class="dm">(hoeft niet)</span></div>';

  /* De doelen van deze groep als chips: één tik en hij klapt open met de
     drie standknoppen eronder. */
  var snel = s.doelen.filter(function (d) {
    return s.groepsDoelIds.indexOf(d.id) >= 0 &&
           !s.gekozen.some(function (g) { return g.id === d.id; });
  });
  if (snel.length) {
    h += '<div class="chips">' + snel.map(function (d) {
      return '<button class="chip" data-kies="' + d.id + '">' + veilig(kort(d.doel)) + '</button>';
    }).join('') + '</div>';
  }

  s.gekozen.forEach(function (d) {
    var nu = s.standen[d.id] || '';
    var eerder = s.bestaand[d.id];
    h += '<div class="doelrij">' +
      '<div class="dn">' + veilig(d.doel) +
        ' <button class="knop knop-stil knop-klein" data-weg="' + d.id + '" ' +
        'style="float:right;margin-left:8px">×</button></div>' +
      '<div class="dm" style="margin-bottom:8px">' + veilig(d.leerlijn || d.domein || '') +
        (eerder ? ' · nu: ' + veilig(D.STAND_KORT[eerder] || eerder) : '') + '</div>' +
      '<div class="standrij">' +
      D.STANDEN.map(function (st) {
        var aan = nu === st;
        return '<button class="standknop' + (aan ? ' aan' : '') + '" data-doel="' + d.id +
               '" data-stand="' + st + '"' +
               (aan ? ' style="background:' + D.STAND_KLEUR[st] + '"' : '') + '>' +
               veilig(D.STAND_KORT[st]) + '</button>';
      }).join('') +
      '</div></div>';
  });

  h += '<input class="zoek" id="blad-zoek" placeholder="Zoek een doel…" value="' + veilig(s.zoek) + '">';
  var lijst = voorstellen();
  if (lijst.length) {
    h += '<div class="doelkeus">' + lijst.map(function (d) {
      return '<button data-kies="' + d.id + '">' + veilig(d.doel) +
             '<div class="mt">' + veilig([d.domein, d.leerlijn, d.niveau].filter(Boolean).join(' · ')) +
             '</div></button>';
    }).join('') + '</div>';
  }

  h += '<div class="bladvoet">' +
       '<button class="knop knop-stil" id="blad-annuleer">Annuleren</button>' +
       '<button class="knop knop-primair" id="blad-bewaar" style="flex:1">Opslaan</button>' +
       '</div>';

  $('blad').innerHTML = h;
  koppel();
}

function initialen(naam){
  var d = String(naam || '').trim().split(/\s+/);
  if (!d[0]) return '?';
  return (d.length === 1 ? d[0].slice(0,2) : d[0][0] + d[d.length-1][0]).toUpperCase();
}

/* Een doelnaam is vaak een hele zin. Op een chip past alleen het begin. */
function kort(t){
  t = String(t || '');
  return t.length > 38 ? t.slice(0, 37).replace(/\s+\S*$/, '') + '…' : t;
}

/* Welke doelen bied ik aan? Zoek je, dan de treffers. Zoek je niet, dan de
   doelen die bij de gekozen hoek horen -- dat is meestal precies wat je
   nodig hebt. */
function voorstellen(){
  var s = staat;
  var gekozenIds = s.gekozen.map(function (d) { return d.id; });
  var bron;
  if (s.zoek.trim().length >= 2) {
    var z = s.zoek.trim().toLowerCase();
    bron = s.doelen.filter(function (d) {
      return (d.doel || '').toLowerCase().indexOf(z) >= 0 ||
             (d.leerlijn || '').toLowerCase().indexOf(z) >= 0;
    });
  } else if (s.hoek) {
    bron = D.doelenBijHoek(s.hoek, s.doelen);
  } else {
    return [];
  }
  return bron.filter(function (d) { return gekozenIds.indexOf(d.id) < 0; }).slice(0, 25);
}

/* ── knoppen ──────────────────────────────────────────────────────── */
function koppel(){
  var s = staat;
  var blad = $('blad');

  $('blad-dicht').onclick = sluit;
  $('blad-annuleer').onclick = sluit;

  Array.prototype.forEach.call(blad.querySelectorAll('[data-hoek]'), function (b) {
    b.onclick = function () {
      var id = b.dataset.hoek;
      s.hoek = (s.hoek && s.hoek.id === id) ? null
             : s.hoeken.filter(function (x) { return x.id === id; })[0];
      teken();
    };
  });

  Array.prototype.forEach.call(blad.querySelectorAll('[data-stand]'), function (b) {
    b.onclick = function () {
      var d = b.dataset.doel, st = b.dataset.stand;
      s.standen[d] = (s.standen[d] === st) ? '' : st;
      if (!s.standen[d]) delete s.standen[d];
      teken();
    };
  });

  Array.prototype.forEach.call(blad.querySelectorAll('[data-weg]'), function (b) {
    b.onclick = function () {
      var id = b.dataset.weg;
      s.gekozen = s.gekozen.filter(function (d) { return d.id !== id; });
      delete s.standen[id];
      teken();
    };
  });

  Array.prototype.forEach.call(blad.querySelectorAll('[data-kies]'), function (b) {
    b.onclick = function () {
      var d = s.doelen.filter(function (x) { return x.id === b.dataset.kies; })[0];
      if (d) s.gekozen.push(d);
      s.zoek = '';
      teken();
    };
  });

  var zoek = $('blad-zoek');
  zoek.oninput = function () {
    s.zoek = zoek.value;
    var pos = zoek.selectionStart;
    teken();
    var nieuw = $('blad-zoek');
    nieuw.focus();
    try { nieuw.setSelectionRange(pos, pos); } catch (e) {}
  };

  $('blad-notitie').oninput = function () { s.notitie = this.value; };

  $('blad-mic').onclick = inspreken;
  $('blad-bewaar').onclick = bewaren;

  if (s.kind.foto_pad) {
    OBS.fotoLink(s.kind.foto_pad, OBS.EMMER_KB).then(function (url) {
      var el = $('blad-rond');
      if (el && url) { el.style.backgroundImage = 'url("' + url + '")'; el.textContent = ''; }
    });
  }
}

/* ── inspreken ────────────────────────────────────────────────────── */
var luisteraar = null;
function inspreken(){
  var API = global.SpeechRecognition || global.webkitSpeechRecognition;
  if (!API) { melden('Inspreken werkt niet in deze browser.'); return; }

  if (luisteraar) { try { luisteraar.stop(); } catch (e) {} luisteraar = null; return; }
  luisteraar = new API();
  luisteraar.lang = 'nl-NL';
  luisteraar.continuous = true;
  luisteraar.interimResults = false;
  luisteraar.onresult = function (ev) {
    var t = '';
    for (var i = ev.resultIndex; i < ev.results.length; i++) {
      if (ev.results[i].isFinal) t += ev.results[i][0].transcript;
    }
    if (t && staat) {
      staat.notitie = (staat.notitie + ' ' + t).trim();
      var n = $('blad-notitie');
      if (n) n.value = staat.notitie;
    }
  };
  luisteraar.onend = function () { luisteraar = null; var b = $('blad-mic'); if (b) b.textContent = '🎙 Inspreken'; };
  luisteraar.onerror = function () { luisteraar = null; melden('Inspreken lukte niet.'); };
  try { luisteraar.start(); $('blad-mic').textContent = '⏹ Stoppen'; }
  catch (e) { luisteraar = null; melden('Inspreken lukte niet.'); }
}

/* ── opslaan ──────────────────────────────────────────────────────── */
function bewaren(){
  var s = staat;
  var knop = $('blad-bewaar');
  var ietsIngevuld = (s.notitie && s.notitie.trim()) || Object.keys(s.standen).length;
  if (!ietsIngevuld) { melden('Er is nog niets ingevuld.'); return; }

  knop.disabled = true;
  knop.textContent = 'Bezig…';

  D.bewaarObservatie({
    groepId: s.groep.id, leerlingId: s.kind.id, hoek: s.hoek,
    notitie: s.notitie, standen: s.standen
  }).then(function () {
    var naam = s.kind.naam;
    var klaar = s.klaar;
    sluit();
    melden('Opgeslagen bij ' + naam + '.');
    klaar();
  }).catch(function (e) {
    knop.disabled = false;
    knop.textContent = 'Opslaan';
    if (OBS.isVerlopen(e)) { OBS.terugNaarLogin('Je sessie is verlopen. Log opnieuw in.'); return; }
    melden(e && e.offline ? 'Geen verbinding — nog niet opgeslagen.'
                          : 'Opslaan lukte niet: ' + ((e && e.message) || ''));
  });
}

$('overlay').addEventListener('click', function (e) {
  if (e.target.id === 'overlay') sluit();
});

global.OBSBLAD = { open: open, sluit: sluit, melden: melden };

})(window);
