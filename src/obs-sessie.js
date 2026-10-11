/* ═══════════════════════════════════════════════════════════════════════
   De sessie van de observatie-app

   Leunt volledig op kb-supabase.js. Wat hier bij komt is het stukje dat
   het Keuzebord nooit nodig had: terugkomen uit een magic link.

   Supabase stuurt je na het klikken op de e-maillink terug naar deze app
   met het token in de hash van het adres:

       .../inloggen.html#access_token=...&refresh_token=...&expires_in=3600

   Die hash wordt nooit naar een server gestuurd -- hij staat alleen in de
   browser. We lezen hem uit, zetten de sessie, en halen hem daarna meteen
   uit de adresbalk zodat hij niet in de geschiedenis blijft staan.
   ═══════════════════════════════════════════════════════════════════════ */
(function (global) {
'use strict';

var EMMER     = 'observatie-media';   /* onze eigen foto's */
var EMMER_KB  = 'kb-media';           /* de foto's van kinderen en hoeken */

/* ── het token uitpakken ──────────────────────────────────────────────
   Een access_token is een JWT: drie stukken, gescheiden door punten, en
   het middelste stuk is base64 met de inhoud. Daar staat 'sub' in, het id
   van de gebruiker. Dat uitlezen scheelt een extra aanroep naar de server
   -- en belangrijker: zonder dat id pakt wieBenIk() straks het verkeerde
   profiel, want die valt dan terug op de eerste rij die hij mag zien. */
function uitToken(token){
  try {
    var deel = token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/');
    var json = decodeURIComponent(atob(deel).split('').map(function (c) {
      return '%' + ('00' + c.charCodeAt(0).toString(16)).slice(-2);
    }).join(''));
    return JSON.parse(json);
  } catch (e) { return null; }
}

function hashDelen(){
  var h = String(location.hash || '').replace(/^#/, '');
  var uit = {};
  if (!h) return uit;
  h.split('&').forEach(function (deel) {
    var i = deel.indexOf('=');
    if (i > 0) uit[decodeURIComponent(deel.slice(0, i))] =
                 decodeURIComponent(deel.slice(i + 1).replace(/\+/g, ' '));
  });
  return uit;
}

function schoonAdres(){
  try { history.replaceState(null, '', location.pathname + location.search); }
  catch (e) { location.hash = ''; }
}

/* Geeft terug: 'ingelogd' als er net een sessie uit de link kwam,
   'niets' als er geen link was, of werpt een fout met een leesbare tekst. */
function verwerkLink(){
  var p = hashDelen();

  if (p.error_description || p.error) {
    schoonAdres();
    var t = p.error_description || p.error;
    if (/expired|invalid/i.test(t)) {
      return Promise.reject(new Error('Deze inloglink is verlopen of al gebruikt. Vraag een nieuwe aan.'));
    }
    return Promise.reject(new Error(t));
  }

  if (!p.access_token) return Promise.resolve('niets');

  var inhoud = uitToken(p.access_token);
  if (!inhoud || !inhoud.sub) {
    schoonAdres();
    return Promise.reject(new Error('De inloglink leverde geen bruikbaar token op.'));
  }

  try {
    SB.zetSessieUitAntwoord({
      access_token:  p.access_token,
      refresh_token: p.refresh_token,
      expires_in:    Number(p.expires_in || 3600),
      user:          { id: inhoud.sub, email: inhoud.email || null }
    });
  } catch (e) {
    schoonAdres();
    return Promise.reject(e);
  }

  schoonAdres();
  return Promise.resolve('ingelogd');
}

/* ── bewaken ──────────────────────────────────────────────────────────
   Elke pagina behalve het inlogscherm roept dit als eerste aan. */
function zorgVoorLogin(){
  if (SB.ingelogd()) return true;
  location.replace('inloggen.html');
  return false;
}

function uitloggen(){
  return SB.afmelden().catch(function () {}).then(function () {
    location.replace('inloggen.html');
  });
}

/* ── foto's ───────────────────────────────────────────────────────────
   Een afgesloten emmer geeft alleen tijdelijke links. We onthouden ze een
   kwartier, zodat een lijst met 28 kinderen niet 28 keer opnieuw vraagt. */
var linkCache = {};
function fotoLink(pad, emmer){
  if (!pad) return Promise.resolve(null);
  emmer = emmer || EMMER_KB;
  var sleutel = emmer + '|' + pad;
  var nu = Date.now();
  if (linkCache[sleutel] && linkCache[sleutel].tot > nu) {
    return Promise.resolve(linkCache[sleutel].url);
  }
  return SB.bestandLink(pad, 3600, emmer).then(function (url) {
    linkCache[sleutel] = { url: url, tot: nu + 15 * 60 * 1000 };
    return url;
  }).catch(function () { return null; });
}

/* ── een sessie die niet meer geldt ───────────────────────────────────
   Een token verloopt, of je logt in het Keuzebord uit terwijl deze app
   nog openstaat. De server zegt dan 401. Dat is geen storing waar je een
   foutmelding voor wilt zien -- je hoort gewoon opnieuw in te loggen. */
function isVerlopen(e){
  if (!e) return false;
  if (e.status === 401) return true;
  return /jwt|token|expired|not authenticated|suitable key/i.test(e.message || '');
}

function terugNaarLogin(reden){
  try { localStorage.setItem('obs_login_reden', reden || ''); } catch (e) {}
  SB.afmelden().catch(function () {}).then(function () {
    location.replace('inloggen.html');
  });
}

function loginReden(){
  try {
    var r = localStorage.getItem('obs_login_reden');
    localStorage.removeItem('obs_login_reden');
    return r || '';
  } catch (e) { return ''; }
}

global.OBS = {
  EMMER: EMMER, EMMER_KB: EMMER_KB,
  verwerkLink: verwerkLink,
  zorgVoorLogin: zorgVoorLogin,
  uitloggen: uitloggen,
  fotoLink: fotoLink,
  isVerlopen: isVerlopen,
  terugNaarLogin: terugNaarLogin,
  loginReden: loginReden
};

})(window);
