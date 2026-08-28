export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (!url.pathname.startsWith('/api/')) {
      return env.ASSETS.fetch(request);
    }

    try {
      if (url.pathname === '/api/auth/login' && request.method === 'POST') {
        return login(request, env);
      }
      if (url.pathname === '/api/auth/session' && request.method === 'GET') {
        const auth = await requireUser(request, env);
        return auth.response ?? json({ user: publicUser(auth.user) });
      }
      if (url.pathname === '/api/auth/logout' && request.method === 'POST') {
        return logout(request, env);
      }
      if (url.pathname === '/api/scans' && request.method === 'GET') {
        return getScans(request, env);
      }
      if (url.pathname === '/api/scans' && request.method === 'POST') {
        return createScan(request, env);
      }
      if (url.pathname === '/api/admin/users' && request.method === 'GET') {
        return adminUsers(request, env);
      }

      return json({ error: 'Not found' }, 404);
    } catch (error) {
      console.error(error);
      return json({ error: 'Ralat pelayan. Sila cuba lagi.' }, 500);
    }
  },
};

const SESSION_COOKIE = 'rk_session';
const SESSION_TTL_MS = 12 * 60 * 60 * 1000;

async function login(request, env) {
  const body = await readJson(request);
  const identityCard = String(body.identityCard ?? '').replace(/\D/g, '');

  if (!/^\d{12}$/.test(identityCard)) {
    return json({ error: 'No. Kad Pengenalan mesti mengandungi 12 digit.' }, 400);
  }

  const user = await env.DB.prepare(
    `SELECT id, nama, no_kad_pengenalan, jawatan, profile_picture, jabatan
     FROM users
     WHERE no_kad_pengenalan = ? AND active = 1
     LIMIT 1`,
  ).bind(identityCard).first();

  if (!user) {
    return json({ error: 'Pengguna tidak berdaftar.' }, 401);
  }

  const token = randomToken();
  const tokenHash = await sha256(token);
  const expiresAtMs = Date.now() + SESSION_TTL_MS;

  await env.DB.batch([
    env.DB.prepare('DELETE FROM sessions WHERE expires_at_ms <= ?').bind(Date.now()),
    env.DB.prepare(
      'INSERT INTO sessions (token_hash, user_id, expires_at_ms) VALUES (?, ?, ?)',
    ).bind(tokenHash, user.id, expiresAtMs),
  ]);

  const response = json({
    user: publicUser(user),
    sessionToken: token,
  });
  response.headers.append(
    'Set-Cookie',
    `${SESSION_COOKIE}=${token}; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=${Math.floor(SESSION_TTL_MS / 1000)}`,
  );
  return response;
}

async function logout(request, env) {
  const token = getSessionToken(request);
  if (token) {
    await env.DB.prepare('DELETE FROM sessions WHERE token_hash = ?')
      .bind(await sha256(token))
      .run();
  }

  const response = json({ ok: true });
  response.headers.append(
    'Set-Cookie',
    `${SESSION_COOKIE}=; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=0`,
  );
  return response;
}

async function getScans(request, env) {
  const auth = await requireUser(request, env);
  if (auth.response) return auth.response;

  const result = await env.DB.prepare(
    `SELECT id, nfc_uid, scanned_at
     FROM nfc_scans
     WHERE user_id = ?
     ORDER BY scanned_at DESC, id DESC
     LIMIT 200`,
  ).bind(auth.user.id).all();

  return json({ scans: result.results ?? [] });
}

async function createScan(request, env) {
  const auth = await requireUser(request, env);
  if (auth.response) return auth.response;

  const body = await readJson(request);
  const nfcUid = String(body.nfcUid ?? '').trim();
  if (!nfcUid || nfcUid.length > 128) {
    return json({ error: 'UID NFC tidak sah.' }, 400);
  }

  const scannedAt = new Date().toISOString();
  const result = await env.DB.prepare(
    `INSERT INTO nfc_scans (user_id, nfc_uid, scanned_at)
     VALUES (?, ?, ?)`,
  ).bind(auth.user.id, nfcUid, scannedAt).run();

  return json({
    scan: {
      id: result.meta?.last_row_id ?? null,
      nfc_uid: nfcUid,
      scanned_at: scannedAt,
    },
  }, 201);
}

async function adminUsers(request, env) {
  const auth = await requireUser(request, env);
  if (auth.response) return auth.response;

  if (String(auth.user.jawatan).toLowerCase() !== 'management') {
    return json({ error: 'Akses Admin hanya untuk Management.' }, 403);
  }

  const result = await env.DB.prepare(
    `SELECT id, nama, no_kad_pengenalan, jawatan, profile_picture, jabatan, active
     FROM users
     ORDER BY nama ASC`,
  ).all();

  return json({ users: (result.results ?? []).map(publicUser) });
}

async function requireUser(request, env) {
  const token = getSessionToken(request);
  if (!token) {
    return { response: json({ error: 'Sesi tidak sah. Sila log masuk.' }, 401) };
  }

  const tokenHash = await sha256(token);
  const user = await env.DB.prepare(
    `SELECT u.id, u.nama, u.no_kad_pengenalan, u.jawatan, u.profile_picture, u.jabatan
     FROM sessions s
     JOIN users u ON u.id = s.user_id
     WHERE s.token_hash = ? AND s.expires_at_ms > ? AND u.active = 1
     LIMIT 1`,
  ).bind(tokenHash, Date.now()).first();

  if (!user) {
    return { response: json({ error: 'Sesi telah tamat. Sila log masuk semula.' }, 401) };
  }

  return { user };
}

function publicUser(user) {
  return {
    id: user.id,
    nama: user.nama,
    noKadPengenalan: user.no_kad_pengenalan,
    jawatan: user.jawatan,
    profilePicture: user.profile_picture,
    jabatan: user.jabatan,
    active: user.active === undefined ? true : Boolean(user.active),
  };
}

function getSessionToken(request) {
  const authorization = request.headers.get('Authorization') ?? '';
  if (authorization.startsWith('Bearer ')) {
    return authorization.slice(7).trim();
  }

  const cookie = request.headers.get('Cookie') ?? '';
  for (const part of cookie.split(';')) {
    const [name, ...value] = part.trim().split('=');
    if (name === SESSION_COOKIE) return value.join('=');
  }
  return null;
}

async function readJson(request) {
  try {
    return await request.json();
  } catch (_) {
    return {};
  }
}

function randomToken() {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return [...bytes].map((value) => value.toString(16).padStart(2, '0')).join('');
}

async function sha256(value) {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('');
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff',
    },
  });
}
