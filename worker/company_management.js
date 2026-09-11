import reportsWorker from './reports.js';

const SESSION_COOKIE = 'rk_session';

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    try {
      if (url.pathname === '/api/admin/companies' && request.method === 'GET') {
        return listCompanies(request, env);
      }
      if (url.pathname === '/api/admin/companies' && request.method === 'POST') {
        return createCompany(request, env);
      }

      const companyMatch = url.pathname.match(/^\/api\/admin\/companies\/(\d+)$/);
      if (companyMatch && request.method === 'PUT') {
        return updateCompany(request, env, Number(companyMatch[1]));
      }

      if (url.pathname === '/api/admin/users' && request.method === 'POST') {
        const body = await readJson(request);
        if (String(body.jawatan ?? '').trim().toLowerCase() === 'administration') {
          return createCompanyAdministration(request, env, body);
        }
        return reportsWorker.fetch(rebuildJsonRequest(request, body), env, ctx);
      }

      const userMatch = url.pathname.match(/^\/api\/admin\/users\/(\d+)$/);
      if (userMatch && request.method === 'PUT') {
        const body = await readJson(request);
        if (String(body.jawatan ?? '').trim().toLowerCase() === 'administration') {
          return updateCompanyAdministration(request, env, Number(userMatch[1]), body);
        }
        return reportsWorker.fetch(rebuildJsonRequest(request, body), env, ctx);
      }

      if (url.pathname === '/api/admin/departments' && request.method === 'POST') {
        const auth = await requireManagement(request, env);
        if (auth.response) return auth.response;
        const body = await readJson(request);
        const resolved = await resolveCompanyPayload(env, body);
        if (resolved.response) return resolved.response;
        return reportsWorker.fetch(rebuildJsonRequest(request, resolved.body), env, ctx);
      }

      const departmentMatch = url.pathname.match(/^\/api\/admin\/departments\/(\d+)$/);
      if (departmentMatch && request.method === 'PUT') {
        const auth = await requireManagement(request, env);
        if (auth.response) return auth.response;
        const body = await readJson(request);
        const resolved = await resolveCompanyPayload(env, body);
        if (resolved.response) return resolved.response;
        return reportsWorker.fetch(rebuildJsonRequest(request, resolved.body), env, ctx);
      }
    } catch (error) {
      console.error(error);
      return json({ error: 'Ralat pelayan. Sila cuba lagi.' }, 500);
    }

    return reportsWorker.fetch(request, env, ctx);
  },

  async scheduled(event, env, ctx) {
    if (typeof reportsWorker.scheduled === 'function') {
      return reportsWorker.scheduled(event, env, ctx);
    }
  },
};

async function listCompanies(request, env) {
  const auth = await requireManagement(request, env);
  if (auth.response) return auth.response;
  const result = await env.DB.prepare(`
    SELECT c.id, c.name, c.active, c.created_at, c.updated_at,
           COUNT(DISTINCT CASE WHEN d.active = 1 THEN d.id END) AS school_count,
           COUNT(DISTINCT CASE WHEN u.active = 1 AND LOWER(u.jawatan) = 'administration' THEN u.id END) AS administration_count
    FROM companies c
    LEFT JOIN departments d ON d.company_id = c.id
    LEFT JOIN users u ON u.company_id = c.id
    GROUP BY c.id
    ORDER BY c.active DESC, c.name COLLATE NOCASE ASC
  `).all();
  return json({ companies: (result.results ?? []).map(companyJson) });
}

async function createCompany(request, env) {
  const auth = await requireManagement(request, env);
  if (auth.response) return auth.response;
  const body = await readJson(request);
  const name = normalizeCompanyName(body.name);
  if (name.length < 2 || name.length > 180) {
    return json({ error: 'Nama Syarikat mesti antara 2 hingga 180 aksara.' }, 400);
  }
  const duplicate = await env.DB.prepare(
    'SELECT id FROM companies WHERE LOWER(name) = LOWER(?) LIMIT 1',
  ).bind(name).first();
  if (duplicate) return json({ error: 'Syarikat dengan nama ini sudah wujud.' }, 409);

  const result = await env.DB.prepare(
    `INSERT INTO companies (name, active, updated_at)
     VALUES (?, 1, CURRENT_TIMESTAMP)`,
  ).bind(name).run();
  const company = await getCompany(env, Number(result.meta?.last_row_id));
  return json({ company: companyJson(company) }, 201);
}

async function updateCompany(request, env, companyId) {
  const auth = await requireManagement(request, env);
  if (auth.response) return auth.response;
  if (!Number.isInteger(companyId) || companyId <= 0) {
    return json({ error: 'Syarikat tidak sah.' }, 400);
  }
  const existing = await getCompany(env, companyId);
  if (!existing) return json({ error: 'Syarikat tidak ditemui.' }, 404);

  const body = await readJson(request);
  const name = normalizeCompanyName(body.name ?? existing.name);
  const active = body.active === false ? 0 : 1;
  if (name.length < 2 || name.length > 180) {
    return json({ error: 'Nama Syarikat mesti antara 2 hingga 180 aksara.' }, 400);
  }
  const duplicate = await env.DB.prepare(
    'SELECT id FROM companies WHERE LOWER(name) = LOWER(?) AND id <> ? LIMIT 1',
  ).bind(name, companyId).first();
  if (duplicate) return json({ error: 'Syarikat dengan nama ini sudah wujud.' }, 409);

  if (!active) {
    const linked = await env.DB.prepare(`
      SELECT
        (SELECT COUNT(*) FROM departments WHERE company_id = ? AND active = 1) AS schools,
        (SELECT COUNT(*) FROM users WHERE company_id = ? AND active = 1 AND LOWER(jawatan) = 'administration') AS admins
    `).bind(companyId, companyId).first();
    if (Number(linked?.schools || 0) > 0 || Number(linked?.admins || 0) > 0) {
      return json({
        error: 'Pindahkan atau nyahaktifkan semua Sekolah dan Pentadbiran Syarikat aktif sebelum menyahaktifkan syarikat.',
      }, 409);
    }
  }

  await env.DB.batch([
    env.DB.prepare(
      `UPDATE companies SET name = ?, active = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?`,
    ).bind(name, active, companyId),
    env.DB.prepare(
      `UPDATE departments SET company_name = ?, updated_at = CURRENT_TIMESTAMP WHERE company_id = ?`,
    ).bind(name, companyId),
    env.DB.prepare(
      `UPDATE users SET jabatan = ? WHERE company_id = ? AND LOWER(jawatan) = 'administration'`,
    ).bind(name, companyId),
  ]);
  const company = await getCompany(env, companyId);
  return json({ company: companyJson(company) });
}

async function resolveCompanyPayload(env, original) {
  const body = { ...original };
  if (!Object.prototype.hasOwnProperty.call(body, 'companyId')) {
    return { body };
  }
  const companyId = Number(body.companyId ?? 0);
  if (!companyId) {
    body.companyName = '';
    return { body };
  }
  if (!Number.isInteger(companyId) || companyId <= 0) {
    return { response: json({ error: 'Syarikat tidak sah.' }, 400) };
  }
  const company = await env.DB.prepare(
    'SELECT id, name, active FROM companies WHERE id = ? LIMIT 1',
  ).bind(companyId).first();
  if (!company || Number(company.active) !== 1) {
    return { response: json({ error: 'Syarikat tidak ditemui atau tidak aktif.' }, 404) };
  }
  body.companyName = company.name;
  return { body };
}

async function createCompanyAdministration(request, env, body) {
  const auth = await requireManagement(request, env);
  if (auth.response) return auth.response;

  const nama = String(body.nama ?? '').trim().toUpperCase();
  const identityCard = String(body.noKadPengenalan ?? '').replace(/\D/g, '');
  const companyId = Number(body.companyId ?? 0);
  if (nama.length < 3) return json({ error: 'Nama pengguna tidak sah.' }, 400);
  if (!/^\d{12}$/.test(identityCard)) {
    return json({ error: 'No. Kad Pengenalan mesti mengandungi 12 digit.' }, 400);
  }
  if (!Number.isInteger(companyId) || companyId <= 0) {
    return json({ error: 'Pilih Syarikat untuk Pentadbiran Syarikat.' }, 400);
  }
  const company = await env.DB.prepare(
    'SELECT id, name FROM companies WHERE id = ? AND active = 1 LIMIT 1',
  ).bind(companyId).first();
  if (!company) return json({ error: 'Syarikat tidak ditemui atau tidak aktif.' }, 404);
  const duplicate = await env.DB.prepare(
    'SELECT id FROM users WHERE no_kad_pengenalan = ? LIMIT 1',
  ).bind(identityCard).first();
  if (duplicate) return json({ error: 'No. Kad Pengenalan ini sudah berdaftar.' }, 409);

  const result = await env.DB.prepare(`
    INSERT INTO users (
      nama, no_kad_pengenalan, no_pk, guard_status, jawatan, profile_picture,
      jabatan, active, department_id, company_id
    ) VALUES (?, ?, NULL, 'Tetap', 'Administration', NULL, ?, 1, NULL, ?)
  `).bind(nama, identityCard, company.name, companyId).run();
  const user = await getUserById(env, Number(result.meta?.last_row_id));
  return json({ user: publicUser(user) }, 201);
}

async function updateCompanyAdministration(request, env, userId, body) {
  const auth = await requireManagement(request, env);
  if (auth.response) return auth.response;
  if (!Number.isInteger(userId) || userId <= 0) {
    return json({ error: 'Pengguna tidak sah.' }, 400);
  }
  const existing = await getUserById(env, userId);
  if (!existing) return json({ error: 'Pengguna tidak ditemui.' }, 404);

  const nama = String(body.nama ?? '').trim().toUpperCase();
  const companyId = Number(body.companyId ?? 0);
  if (nama.length < 3) return json({ error: 'Nama pengguna tidak sah.' }, 400);
  if (!Number.isInteger(companyId) || companyId <= 0) {
    return json({ error: 'Pilih Syarikat untuk Pentadbiran Syarikat.' }, 400);
  }
  const company = await env.DB.prepare(
    'SELECT id, name FROM companies WHERE id = ? AND active = 1 LIMIT 1',
  ).bind(companyId).first();
  if (!company) return json({ error: 'Syarikat tidak ditemui atau tidak aktif.' }, 404);

  let profilePicture = existing.profile_picture || null;
  if (body.clearProfilePicture === true) {
    profilePicture = null;
  } else if (Object.prototype.hasOwnProperty.call(body, 'profilePicture')) {
    const picture = String(body.profilePicture ?? '');
    if (!/^data:image\/(jpeg|png|webp);base64,/i.test(picture)) {
      return json({ error: 'Format gambar mesti JPEG, PNG atau WebP.' }, 400);
    }
    if (picture.length > 700000) {
      return json({ error: 'Gambar terlalu besar. Had selepas pemampatan ialah kira-kira 500 KB.' }, 413);
    }
    profilePicture = picture;
  }

  await env.DB.prepare(`
    UPDATE users
       SET nama = ?, jawatan = 'Administration', department_id = NULL,
           company_id = ?, jabatan = ?, profile_picture = ?, no_pk = NULL,
           guard_status = 'Tetap'
     WHERE id = ?
  `).bind(nama, companyId, company.name, profilePicture, userId).run();
  const updated = await getUserById(env, userId);
  return json({ user: publicUser(updated) });
}

async function getCompany(env, companyId) {
  return env.DB.prepare(`
    SELECT c.id, c.name, c.active, c.created_at, c.updated_at,
           (SELECT COUNT(*) FROM departments d WHERE d.company_id = c.id AND d.active = 1) AS school_count,
           (SELECT COUNT(*) FROM users u WHERE u.company_id = c.id AND u.active = 1 AND LOWER(u.jawatan) = 'administration') AS administration_count
      FROM companies c
     WHERE c.id = ? LIMIT 1
  `).bind(companyId).first();
}

function companyJson(row) {
  return {
    id: Number(row.id),
    name: row.name,
    active: Number(row.active) === 1,
    schoolCount: Number(row.school_count || 0),
    administrationCount: Number(row.administration_count || 0),
    createdAt: row.created_at || null,
    updatedAt: row.updated_at || null,
  };
}

async function getUserById(env, id) {
  return env.DB.prepare(`
    SELECT u.id, u.nama, u.no_kad_pengenalan, u.no_pk, u.guard_status, u.jawatan,
           u.profile_picture, u.jabatan, u.department_id, u.active,
           COALESCE(d.name, u.jabatan) AS department_name,
           COALESCE(u.company_id, d.company_id) AS company_id,
           COALESCE(co.name, d.company_name, '') AS company_name,
           COALESCE(d.session_interval_minutes, 120) AS session_interval_minutes,
           COALESCE(d.session_start_minutes, 420) AS session_start_minutes
      FROM users u
      LEFT JOIN departments d ON d.id = u.department_id
      LEFT JOIN companies co ON co.id = COALESCE(u.company_id, d.company_id)
     WHERE u.id = ? LIMIT 1
  `).bind(id).first();
}

function publicUser(user) {
  return {
    id: Number(user.id),
    nama: user.nama,
    noKadPengenalan: user.no_kad_pengenalan,
    noPk: user.no_pk || '',
    guardStatus: user.guard_status || 'Tetap',
    jawatan: user.jawatan,
    profilePicture: user.profile_picture,
    jabatan: user.department_name || user.jabatan || user.company_name || 'Belum ditetapkan',
    departmentId: user.department_id == null ? null : Number(user.department_id),
    companyId: user.company_id == null ? null : Number(user.company_id),
    companyName: user.company_name || '',
    sessionIntervalMinutes: Number(user.session_interval_minutes || 120),
    sessionStartMinutes: Number(user.session_start_minutes ?? 420),
    active: Number(user.active) === 1,
  };
}

async function requireManagement(request, env) {
  const token = getSessionToken(request);
  if (!token) return { response: json({ error: 'Sesi tidak sah. Sila log masuk.' }, 401) };
  const tokenHash = await sha256(token);
  const user = await env.DB.prepare(`
    SELECT u.id, u.jawatan
      FROM sessions s
      JOIN users u ON u.id = s.user_id
     WHERE s.token_hash = ? AND s.expires_at_ms > ? AND u.active = 1
     LIMIT 1
  `).bind(tokenHash, Date.now()).first();
  if (!user) return { response: json({ error: 'Sesi telah tamat. Sila log masuk semula.' }, 401) };
  if (String(user.jawatan || '').toLowerCase() !== 'management') {
    return { response: json({ error: 'Akses Admin hanya untuk Admin Sistem.' }, 403) };
  }
  return { user };
}

function getSessionToken(request) {
  const auth = request.headers.get('Authorization') || '';
  if (/^Bearer\s+/i.test(auth)) return auth.replace(/^Bearer\s+/i, '').trim();
  const cookies = request.headers.get('Cookie') || '';
  for (const part of cookies.split(';')) {
    const [key, ...rest] = part.trim().split('=');
    if (key === SESSION_COOKIE) return rest.join('=');
  }
  return null;
}

function rebuildJsonRequest(request, body) {
  const headers = new Headers(request.headers);
  headers.set('Content-Type', 'application/json; charset=utf-8');
  return new Request(request.url, {
    method: request.method,
    headers,
    body: JSON.stringify(body),
  });
}

function normalizeCompanyName(value) {
  return String(value ?? '').trim().replace(/\s+/g, ' ');
}

async function readJson(request) {
  try { return await request.json(); } catch (_) { return {}; }
}

async function sha256(value) {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'no-store',
    },
  });
}
