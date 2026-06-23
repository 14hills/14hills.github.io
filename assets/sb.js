/* ============================================================
 *  14hills 공통 인증/연결 모듈  (SaiZen ops saizen-ops.js 인증부 포팅)
 *  · 연결정보(Project URL + Publishable key) 내장 — 사용자는 로그인만
 *  · 로그인 / 가입(계정 발급) 요청 / me_access(역할·카드) / 페이지 가드 / 초대 비번설정
 *  · Publishable key는 공개 가능(RLS로 보호). Secret key는 절대 넣지 않음.
 *  · 의존: <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
 * ============================================================ */
(function (global) {
  'use strict';

  // ── 연결정보 내장 (14hills 전용) ──────────────────────────
  var SB_URL = 'https://frnvhogtyuwkssoqadxp.supabase.co';
  var SB_KEY = 'sb_publishable_r-oEDKnG8sSzeqOfZLObNQ_Uh6xIeKa';
  try {
    if (!localStorage.getItem('14h_sb_url')) localStorage.setItem('14h_sb_url', SB_URL);
    if (!localStorage.getItem('14h_sb_key')) localStorage.setItem('14h_sb_key', SB_KEY);
  } catch (e) {}
  function cfgUrl() { try { return localStorage.getItem('14h_sb_url') || SB_URL; } catch (e) { return SB_URL; } }
  function cfgKey() { try { return localStorage.getItem('14h_sb_key') || SB_KEY; } catch (e) { return SB_KEY; } }

  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"]/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]; }); }

  var _client = null;
  function client() {
    if (_client) return _client;
    if (!global.supabase || !global.supabase.createClient) return null;
    try { _client = global.supabase.createClient(cfgUrl(), cfgKey(), { auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true, storageKey: '14h_sb_auth' } }); }
    catch (e) { return null; }
    return _client;
  }

  // ── me_access (역할·카드·이름·부서·직급) — 캐시 ──
  var _meP = null;
  function me() {
    if (_meP) return _meP;
    var c = client();
    if (!c) { _meP = Promise.resolve(null); return _meP; }
    _meP = c.auth.getSession().then(function (r) {
      if (!r || !r.data || !r.data.session) return null;
      var email = (r.data.session.user || {}).email || '';
      return c.rpc('me_access').then(function (rr) {
        if (rr.error || !rr.data || !rr.data[0]) return { role: 'staff', areas: [], name: '', dept: '', title: '', email: email };
        var a = rr.data[0];
        return { role: a.role, areas: a.areas || [], name: a.name || '', dept: a.dept || '', title: a.title || '', email: email };
      }).catch(function () { return { role: 'staff', areas: [], name: '', dept: '', title: '', email: email }; });
    }).catch(function () { return null; });
    return _meP;
  }
  function signOut() { var c = client(); if (c) c.auth.signOut().then(function () { location.reload(); }).catch(function () { location.reload(); }); }
  function canArea(acc, area) { return !!acc && (acc.role === 'admin' || acc.role === 'manager' || (acc.areas || []).indexOf(area) >= 0); }

  // ── 스타일 ──
  var IN = 'padding:11px 13px;border:1px solid var(--border,#cfd9d6);border-radius:9px;font-size:14px;font-family:inherit;background:var(--surface,#fff);color:var(--text,#1f2a18);width:100%;box-sizing:border-box';
  var BTN = 'width:100%;padding:11px;border:1px solid var(--accent,#475569);background:var(--accent,#475569);color:#fff;font-weight:800;font-size:14.5px;border-radius:9px;cursor:pointer;font-family:inherit';
  var LINK = 'color:var(--accent,#475569);font-weight:700;font-size:12px;text-decoration:none;cursor:pointer';

  function overlay(id) {
    var d = document.createElement('div'); if (id) d.id = id;
    d.setAttribute('style', 'position:fixed;inset:0;z-index:9000;background:rgba(20,30,28,.55);display:flex;align-items:center;justify-content:center;text-align:center;padding:24px;backdrop-filter:blur(2px)');
    return d;
  }
  function cardBox(w) {
    var c = document.createElement('div');
    c.setAttribute('style', 'background:var(--surface,#fff);border:1px solid var(--border,#cfd9d6);border-radius:14px;box-shadow:0 12px 44px rgba(20,30,28,.16);padding:30px 28px;width:' + (w || 330) + 'px;max-width:92vw;text-align:center');
    return c;
  }

  // ── 로그인 카드 ──
  function renderLogin(card, title) {
    var em = ''; try { em = localStorage.getItem('14h_last_email') || ''; } catch (e) {}
    card.innerHTML =
        '<div style="font-size:20px;font-weight:800;color:var(--accent2,#374151)">로그인</div>'
      + '<div style="margin-top:6px;color:var(--text2,#566049);font-size:12.5px">' + esc(title || '14hills 운영 통합 시스템') + '</div>'
      + '<input id="sbx-em" type="email" placeholder="이메일" autocomplete="username" spellcheck="false" value="' + esc(em) + '" style="margin-top:18px;' + IN + '">'
      + '<input id="sbx-pw" type="password" placeholder="비밀번호" autocomplete="current-password" style="margin-top:10px;' + IN + '">'
      + '<label style="display:flex;align-items:center;gap:6px;margin-top:11px;font-size:12.5px;color:var(--text2,#566049);cursor:pointer;user-select:none"><input id="sbx-rm" type="checkbox"' + (em ? ' checked' : '') + ' style="width:15px;height:15px;accent-color:var(--accent,#475569);cursor:pointer">아이디 기억</label>'
      + '<div id="sbx-err" style="display:none;margin-top:10px;color:#b13b2c;font-size:12.5px;font-weight:600"></div>'
      + '<button type="button" id="sbx-go" style="margin-top:14px;' + BTN + '">로그인</button>'
      + '<div style="margin-top:14px;color:var(--text3,#8a937c);font-size:11.5px">계정은 마스터(관리자)가 발급합니다.</div>'
      + '<div style="margin-top:6px"><a id="sbx-req" style="' + LINK + '">처음이세요? 가입(계정) 요청 →</a></div>';
    var emI = card.querySelector('#sbx-em'), pw = card.querySelector('#sbx-pw'), rm = card.querySelector('#sbx-rm'), err = card.querySelector('#sbx-err'), btn = card.querySelector('#sbx-go');
    function fail(m) { err.textContent = m; err.style.display = 'block'; btn.disabled = false; btn.textContent = '로그인'; }
    function go() {
      var c = client(), e = emI.value.trim(), p = pw.value;
      if (!c) { fail('연결 정보가 없습니다.'); return; }
      if (!e || !p) { fail('이메일과 비밀번호를 입력하세요.'); return; }
      err.style.display = 'none'; btn.disabled = true; btn.textContent = '로그인 중…';
      try { if (rm.checked) localStorage.setItem('14h_last_email', e); else localStorage.removeItem('14h_last_email'); } catch (x) {}
      c.auth.signInWithPassword({ email: e, password: p }).then(function (res) {
        if (res && res.error) { fail('로그인 실패: ' + res.error.message); return; }
        location.reload();
      }).catch(function (x) { fail('로그인 오류: ' + x.message); });
    }
    btn.addEventListener('click', go);
    pw.addEventListener('keydown', function (e) { if (e.key === 'Enter') { e.preventDefault(); go(); } });
    emI.addEventListener('keydown', function (e) { if (e.key === 'Enter') { e.preventDefault(); pw.focus(); } });
    card.querySelector('#sbx-req').addEventListener('click', function () { renderRequest(card, title); });
    setTimeout(function () { try { (em ? pw : emI).focus(); } catch (e) {} }, 40);
  }

  // ── 가입(계정 발급) 요청 — access_requests insert ──
  function renderRequest(card, title) {
    card.innerHTML =
        '<div style="font-size:19px;font-weight:800;color:var(--accent2,#374151)">가입 요청</div>'
      + '<div style="margin-top:6px;color:var(--text2,#566049);font-size:12px;line-height:1.5">계정이 없으시면 아래로 요청을 보내세요.<br>마스터(관리자) 확인 후 계정이 발급됩니다.</div>'
      + '<input id="sbx-rnm" type="text" placeholder="이름" autocomplete="name" style="margin-top:16px;' + IN + '">'
      + '<input id="sbx-rem" type="email" placeholder="이메일(계정으로 사용할 주소)" autocomplete="email" spellcheck="false" style="margin-top:10px;' + IN + '">'
      + '<input id="sbx-rdept" type="text" placeholder="부서·메모 (선택)" style="margin-top:10px;' + IN + '">'
      + '<div id="sbx-rerr" style="display:none;margin-top:10px;color:#b13b2c;font-size:12.5px;font-weight:600"></div>'
      + '<button type="button" id="sbx-rgo" style="margin-top:16px;' + BTN + '">요청 보내기</button>'
      + '<div style="margin-top:12px"><a id="sbx-rback" style="' + LINK + '">← 로그인으로</a></div>';
    var nm = card.querySelector('#sbx-rnm'), em = card.querySelector('#sbx-rem'), dp = card.querySelector('#sbx-rdept'), err = card.querySelector('#sbx-rerr'), btn = card.querySelector('#sbx-rgo');
    function fail(m) { err.textContent = m; err.style.display = 'block'; btn.disabled = false; btn.textContent = '요청 보내기'; }
    function go() {
      var c = client(), n = nm.value.trim(), e = em.value.trim();
      if (!c) { fail('연결 정보가 없습니다.'); return; }
      if (!n || !e) { fail('이름과 이메일을 입력하세요.'); return; }
      if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(e)) { fail('이메일 형식을 확인하세요.'); return; }
      err.style.display = 'none'; btn.disabled = true; btn.textContent = '보내는 중…';
      c.from('access_requests').insert({ name: n, email: e, dept: dp.value.trim() || null }).then(function (res) {
        if (res && res.error) { fail('요청 실패: ' + res.error.message); return; }
        card.innerHTML = '<div style="font-size:34px">✓</div><div style="margin-top:8px;font-size:17px;font-weight:800;color:var(--accent2,#374151)">요청이 접수되었습니다</div><div style="margin-top:8px;color:var(--text2,#566049);font-size:13px;line-height:1.55">마스터(관리자) 확인 후 <b>' + esc(e) + '</b><br>으로 계정이 발급됩니다.</div><button type="button" id="sbx-rok" style="margin-top:18px;' + BTN + '">로그인으로</button>';
        card.querySelector('#sbx-rok').addEventListener('click', function () { renderLogin(card, title); });
      }).catch(function (x) { fail('요청 오류: ' + x.message); });
    }
    btn.addEventListener('click', go);
    card.querySelector('#sbx-rback').addEventListener('click', function () { renderLogin(card, title); });
    setTimeout(function () { try { nm.focus(); } catch (e) {} }, 40);
  }

  function loginCard(title) { var c = cardBox(330); renderLogin(c, title); return c; }
  function denyCard(home) {
    var w = cardBox(360);
    w.innerHTML = '<div style="font-size:18px;font-weight:800;color:#b13b2c">접근 권한이 없습니다</div><div style="margin-top:10px;color:var(--text2,#566049);font-size:13.5px">이 페이지 권한이 없습니다.<br>마스터(관리자)에게 문의하세요.</div><div style="margin-top:16px"><a href="' + esc(home || '../app/') + '" style="color:var(--accent2,#374151);font-weight:700;text-decoration:none">← 홈으로</a></div>';
    return w;
  }

  // ── 초대/비번재설정(#type=invite|recovery / ?code=) → 비밀번호 설정 ──
  function setPasswordCard(c) {
    var d = overlay('sbx-gate'); var card = cardBox(330);
    card.innerHTML = '<div style="font-size:20px;font-weight:800;color:var(--accent2,#374151)">비밀번호 설정</div><div style="margin-top:6px;color:var(--text2,#566049);font-size:12.5px">초대받은 계정의 비밀번호를 설정하세요.</div><input id="sbx-np" type="password" placeholder="새 비밀번호(6자 이상)" autocomplete="new-password" style="margin-top:16px;' + IN + '"><div id="sbx-pe" style="display:none;margin-top:10px;color:#b13b2c;font-size:12.5px;font-weight:600"></div><button type="button" id="sbx-pgo" style="margin-top:14px;' + BTN + '">설정하고 시작</button>';
    d.appendChild(card); document.body.appendChild(d);
    var np = card.querySelector('#sbx-np'), pe = card.querySelector('#sbx-pe'), btn = card.querySelector('#sbx-pgo');
    function go() {
      var p = np.value;
      if (!p || p.length < 6) { pe.textContent = '6자 이상 입력하세요.'; pe.style.display = 'block'; return; }
      btn.disabled = true; btn.textContent = '설정 중…';
      c.auth.updateUser({ password: p }).then(function (res) {
        if (res && res.error) { pe.textContent = '실패: ' + res.error.message; pe.style.display = 'block'; btn.disabled = false; btn.textContent = '설정하고 시작'; return; }
        try { history.replaceState(null, '', location.pathname); } catch (e) {}
        location.reload();
      }).catch(function (x) { pe.textContent = '오류: ' + x.message; pe.style.display = 'block'; btn.disabled = false; btn.textContent = '설정하고 시작'; });
    }
    btn.addEventListener('click', go);
    np.addEventListener('keydown', function (e) { if (e.key === 'Enter') go(); });
    setTimeout(function () { try { np.focus(); } catch (e) {} }, 40);
  }
  function handleInvite() {
    var h = location.hash || '', q = location.search || '';
    if (!/type=(invite|recovery|signup)/.test(h) && !(/[?&]code=/.test(q) && !/error/.test(q))) return false;
    var c = client(); if (!c) return false;
    var shown = false;
    function show() { if (!shown) { shown = true; setPasswordCard(c); } }
    try { c.auth.onAuthStateChange(function (evt) { if (evt === 'PASSWORD_RECOVERY' || evt === 'SIGNED_IN' || evt === 'USER_UPDATED') show(); }); } catch (e) {}
    if (/[?&]code=/.test(q) && c.auth.exchangeCodeForSession) { c.auth.exchangeCodeForSession(q).then(show).catch(show); }
    else { show(); }
    return true;
  }

  // ── 페이지 가드 ── opts:{area, title, home}
  //   area 없음 → 로그인만 요구. area 지정 → 그 카드 권한 필요('admin'은 마스터 전용).
  //   반환: Promise<acc|null>  (acc=권한정보, null=미로그인/초대흐름)
  function guard(opts) {
    opts = opts || {};
    if (handleInvite()) return Promise.resolve(null);
    var c = client();
    if (!c) return Promise.resolve(null);   // supabase 미로드 → 차단 안 함
    return me().then(function (acc) {
      if (!acc) { var d = overlay('sbx-gate'); d.appendChild(loginCard(opts.title)); document.body.appendChild(d); return null; }
      if (opts.area) {
        var ok = (opts.area === 'admin') ? (acc.role === 'admin') : canArea(acc, opts.area);
        if (!ok) { var d2 = overlay('sbx-gate'); d2.appendChild(denyCard(opts.home)); document.body.appendChild(d2); return acc; }
      }
      return acc;
    });
  }

  global.SB14 = {
    client: client, me: me, signOut: signOut, guard: guard, canArea: canArea,
    loginCard: loginCard, url: cfgUrl, key: cfgKey, esc: esc,
    AREAS: ['data', 'dispatch', 'nametag', 'dinner', 'settle']
  };
})(window);
