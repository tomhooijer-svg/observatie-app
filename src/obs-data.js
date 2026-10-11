/* ═══════════════════════════════════════════════════════════════════════
   De gegevens: doelen, hoeken, en het wegschrijven van een observatie.

   De standenschaal is dezelfde als in het Keuzebord, zodat beide bronnen
   in de tijdlijn op dezelfde manier te lezen zijn.
   ═══════════════════════════════════════════════════════════════════════ */
(function (global) {
'use strict';

var STANDEN = ['nog', 'bezig', 'behaald'];
var STAND_NAAM = { nog: 'is aan het ontdekken',
                   bezig: 'kan het met hulp',
                   behaald: 'kan het zelfstandig' };
var STAND_KORT = { nog: 'ontdekken', bezig: 'met hulp', behaald: 'zelfstandig' };
var STAND_KLEUR = { nog: 'var(--let-op)', bezig: 'var(--accent)', behaald: 'var(--goed)' };

function volgendeStand(huidig){
  var i = STANDEN.indexOf(huidig);
  if (i < 0) return 'nog';                 /* nog niets -> eerste trede */
  if (i === STANDEN.length - 1) return ''; /* voorbij de laatste -> weer leeg */
  return STANDEN[i + 1];
}

/* ── ophalen ──────────────────────────────────────────────────────── */

/* De doelen van deze groep staan vooraan: dat zijn de doelen waar je op
   dit moment mee bezig bent. De rest van de bibliotheek komt daaronder,
   te vinden via zoeken. */
function doelenVanGroep(groepId){
  return SB.lees('groep_doelen', { kies: 'doel_id', waar: { groep_id: 'eq.' + groepId } })
    .then(function (rijen) {
      return (rijen || []).map(function (r) { return r.doel_id; });
    });
}

var alleDoelen = null;
function doelen(){
  if (alleDoelen) return Promise.resolve(alleDoelen);
  return SB.lees('doelen', {
    kies: 'id,doel,domein,leerlijn,aspect,niveau,code,ster',
    volgorde: 'domein,leerlijn,niveau'
  }).then(function (rijen) { alleDoelen = rijen || []; return alleDoelen; });
}

var hoekenCache = {};
function hoeken(groepId){
  if (hoekenCache[groepId]) return Promise.resolve(hoekenCache[groepId]);
  /* Een hoek hoort bij een groep, of bij de school (dan is groep_id leeg
     en geldt hij voor iedereen). PostgREST schrijft dat zo: */
  return SB.lees('hoeken', {
    kies: 'id,naam,kleur,icoon,leerlijnen,volgorde,groep_id',
    waar: { or: '(groep_id.eq.' + groepId + ',groep_id.is.null)' },
    volgorde: 'volgorde,naam'
  }).then(function (rijen) {
    hoekenCache[groepId] = rijen || [];
    return hoekenCache[groepId];
  }).catch(function () { return []; });
}

/* Welke doelen passen bij deze hoek? De hoek weet zijn eigen leerlijnen,
   dus dat is gewoon een kwestie van daarop filteren. */
function doelenBijHoek(hoek, lijst){
  var ll = (hoek && hoek.leerlijnen) || [];
  if (!ll.length) return [];
  return lijst.filter(function (d) { return ll.indexOf(d.leerlijn) >= 0; });
}

/* De huidige stand per doel voor één kind. */
function standenVanKind(leerlingId){
  return SB.lees('huidige_stand', {
    kies: 'doel_id,stand,ts',
    waar: { leerling_id: 'eq.' + leerlingId }
  }).then(function (r) {
    var uit = {};
    (r || []).forEach(function (s) { uit[s.doel_id] = s.stand; });
    return uit;
  }).catch(function () { return {}; });
}

/* De huidige stand voor een hele groep in één keer -- dat scheelt bij een
   raster met 28 kinderen 28 aanvragen. */
function standenVanGroep(groepId){
  return SB.lees('huidige_stand', {
    kies: 'leerling_id,doel_id,stand',
    waar: { groep_id: 'eq.' + groepId }
  }).then(function (r) {
    var uit = {};
    (r || []).forEach(function (s) {
      (uit[s.leerling_id] = uit[s.leerling_id] || {})[s.doel_id] = s.stand;
    });
    return uit;
  }).catch(function () { return {}; });
}

/* ── wegschrijven ─────────────────────────────────────────────────── */

function mijnId(){
  var s = SB.sessie();
  return s && s.gebruiker && s.gebruiker.id;
}

function clientId(){
  return 'c' + Date.now().toString(36) + Math.random().toString(36).slice(2, 8);
}

/* De tijd van het tikken, niet van het aankomen.

   Tik je twee keer snel achter elkaar op hetzelfde vakje, dan gaan er twee
   verzoeken tegelijk naar de server. Die kunnen in omgekeerde volgorde
   binnenkomen, en omdat `huidige_stand` de nieuwste rij pakt, zou dan de
   verkeerde stand blijven staan. Door de tijd hier vast te leggen bepaalt
   de volgorde van tikken wie er wint, en niet het netwerk. */
function nu(){ return new Date().toISOString(); }

function vandaag(){
  var d = new Date();
  return d.getFullYear() + '-' + ('0' + (d.getMonth() + 1)).slice(-2) + '-' + ('0' + d.getDate()).slice(-2);
}

/* Een ronde wordt niet door de leerkracht aangemaakt maar vanzelf: per dag
   en per hoek één. Observeer je 's ochtends drie kinderen in de bouwhoek,
   dan horen die bij elkaar, zonder dat je daar iets voor hoeft te doen. */
var sessieCache = {};
function zorgVoorRonde(groepId, hoek){
  var sleutel = groepId + '|' + (hoek ? hoek.id : 'los') + '|' + vandaag();
  if (sessieCache[sleutel]) return Promise.resolve(sessieCache[sleutel]);

  var titel = hoek ? hoek.naam : 'Losse observaties';
  return SB.lees('observatie_sessies', {
    kies: 'id',
    waar: { groep_id: 'eq.' + groepId, client_id: 'eq.' + sleutel },
    hoeveel: 1
  }).then(function (bestaand) {
    if (bestaand && bestaand[0]) { sessieCache[sleutel] = bestaand[0].id; return bestaand[0].id; }
    return SB.schrijf('observatie_sessies', [{
      groep_id: groepId,
      door: mijnId(),
      titel: titel,
      soort: 'spel',
      hoek_id: hoek ? hoek.id : null,
      client_id: sleutel
    }]).then(function (uit) {
      var id = uit && uit[0] && uit[0].id;
      sessieCache[sleutel] = id;
      return id;
    });
  });
}

/* Eén observatie: een notitie, een stel standen, of allebei. */
function bewaarObservatie(opt){
  /* opt = { groepId, leerlingId, hoek, notitie, standen:{doelId:stand} } */
  var standen = opt.standen || {};
  var doelIds = Object.keys(standen);
  var heeftNotitie = !!(opt.notitie && opt.notitie.trim());

  if (!heeftNotitie && !doelIds.length) return Promise.resolve(null);

  return zorgVoorRonde(opt.groepId, opt.hoek).then(function (sessieId) {
    var werk = Promise.resolve(null);

    if (heeftNotitie) {
      werk = SB.schrijf('observatie_notities', [{
        sessie_id:   sessieId,
        groep_id:    opt.groepId,
        leerling_id: opt.leerlingId,
        door:        mijnId(),
        status:      'notitie',
        ts:          nu(),
        notitie:     opt.notitie.trim(),
        hoek_id:     opt.hoek ? opt.hoek.id : null,
        client_id:   clientId()
      }]).then(function (uit) { return uit && uit[0] && uit[0].id; });
    }

    return werk.then(function (notitieId) {
      if (!doelIds.length) return { sessieId: sessieId, notitieId: notitieId };
      var tijd = nu();
      var rijen = doelIds.map(function (did) {
        return {
          ts:          tijd,
          groep_id:    opt.groepId,
          leerling_id: opt.leerlingId,
          doel_id:     did,
          stand:       standen[did] || null,
          door:        mijnId(),
          sessie_id:   sessieId,
          notitie_id:  notitieId || null,
          hoek_id:     opt.hoek ? opt.hoek.id : null,
          client_id:   clientId()
        };
      });
      return SB.schrijf('observatie_standen', rijen).then(function () {
        return { sessieId: sessieId, notitieId: notitieId };
      });
    });
  });
}

/* Eén tik in het raster: alleen een stand, geen notitie. */
function bewaarStand(groepId, leerlingId, doelId, stand, hoek){
  /* meteen vastleggen, vóór het wachten op de ronde */
  var tijd = nu();
  return zorgVoorRonde(groepId, hoek).then(function (sessieId) {
    return SB.schrijf('observatie_standen', [{
      ts: tijd,
      groep_id: groepId, leerling_id: leerlingId, doel_id: doelId,
      stand: stand || null, door: mijnId(), sessie_id: sessieId,
      hoek_id: hoek ? hoek.id : null, client_id: clientId()
    }]);
  });
}

/* ── de tijdlijn van één kind ─────────────────────────────────────── */
function tijdlijn(leerlingId){
  return SB.lees('kind_tijdlijn', {
    kies: 'moment,bron,status,stand,tekst,doel_id',
    waar: { leerling_id: 'eq.' + leerlingId },
    volgorde: 'moment.desc',
    hoeveel: 120
  }).catch(function () { return []; });
}

global.OBSDATA = {
  STANDEN: STANDEN, STAND_NAAM: STAND_NAAM, STAND_KORT: STAND_KORT, STAND_KLEUR: STAND_KLEUR,
  volgendeStand: volgendeStand,
  doelen: doelen, doelenVanGroep: doelenVanGroep, doelenBijHoek: doelenBijHoek,
  hoeken: hoeken,
  standenVanKind: standenVanKind, standenVanGroep: standenVanGroep,
  bewaarObservatie: bewaarObservatie, bewaarStand: bewaarStand,
  tijdlijn: tijdlijn, mijnId: mijnId
};

})(window);
