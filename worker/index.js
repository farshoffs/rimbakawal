const SESSION_COOKIE = 'rk_session';
const SESSION_TTL_MS = 12 * 60 * 60 * 1000;
const MALAYSIA_OFFSET_MS = 8 * 60 * 60 * 1000;

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
      if (url.pathname === '/api/patrol/config' && request.method === 'GET') {
        return patrolConfig(request, env);
      }
      if (url.pathname === '/api/profile/picture' && request.method === 'POST') {
        return updateProfilePicture(request, env);
      }
      if (url.pathname === '/api/scans' && request.method === 'GET') {
        return getScans(request, env, url);
      }
      if (url.pathname === '/api/scans' && request.method === 'POST') {
        return createScan(request, env);
      }
      if (url.pathname === '/api/admin/users' && request.method === 'GET') {
        return adminUsers(request, env);
      }
      if (url.pathname === '/api/admin/departments' && request.method === 'GET') {
        return adminDepartments(request, env);
      }
      if (url.pathname === '/api/admin/departments' && request.method === 'POST') {
        return createDepartment(request, env);
      }
      if (url.pathname === '/api/admin/checkpoints' && request.method === 'GET') {
        return adminCheckpoints(request, env, url);
      }
      if (url.pathname === '/api/admin/checkpoints' && request.method === 'POST') {
        return createCheckpoint(request, env);
      }

      let match = url.pathname.match(/^\/api\/admin\/departments\/(\d+)$/);
      if (match && request.method === 'PUT') {
        return updateDepartment(request, env, Number(match[1]));
      }

      match = url.pathname.match(/^\/api\/admin\/checkpoints\/(\d+)$/);
      if (match && request.method === 'PUT') {
        return updateCheckpoint(request, env, Number(match[1]));
      }

      match = url.pathname.match(/^\/api\/admin\/users\/(\d+)$/);
      if (match && request.method === 'PUT') {
        return updateAdminUser(request, env, Number(match[1]));
      }

      match = url.pathname.match(/^\/api\/admin\/users\/(\d+)\/department$/);
      if (match && request.method === 'PUT') {
        return updateUserDepartment(request, env, Number(match[1]));
      }

      return json({ error: 'Not found' }, 404);
    } catch (error) {
      console.error(error);
      return json({ error: 'Ralat pelayan. Sila cuba lagi.' }, 500);
    }
  },
};

async function login(request, env) {
  const body = await readJson(request);
  const identityCard = String(body.identityCard ?? '').replace(/\D/g, '');

  if (!/^\d{12}$/.test(identityCard)) {
    return json({ error: 'No. Kad Pengenalan mesti mengandungi 12 digit.' }, 400);
  }

  const user = await env.DB.prepare(
    `${userSelect()}
     WHERE u.no_kad_pengenalan = ? AND u.active = 1
     LIMIT 1`,
  ).bind(identityCard).first();

  if (!user) {
    return json({ error: 'Pengguna tidak berdaftar.' }, 401);
  }

  const token = `${Date.now().toString(36)}.${randomToken()}`;
  const tokenHash = await sha256(token);
  const expiresAtMs = Date.now() + SESSION_TTL_MS;

  await env.DB.batch([
    env.DB.prepare('DELETE FROM sessions WHERE expires_at_ms <= ?').bind(Date.now()),
    env.DB.prepare(
      'INSERT INTO sessions (token_hash, user_id, expires_at_ms) VALUES (?, ?, ?)',
    ).bind(tokenHash, user.id, expiresAtMs),
  ]);

  const response = json({ user: publicUser(user), sessionToken: token });
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

async function patrolConfig(request, env) {
  const auth = await requireUser(request, env);
  if (auth.response) return auth.response;

  if (!auth.user.department_id) {
    return json({ error: 'Pengguna belum dipautkan kepada Jabatan.' }, 409);
  }

  const checkpoints = await env.DB.prepare(
    `SELECT id, name, position
     FROM checkpoints
     WHERE department_id = ? AND active = 1
     ORDER BY position ASC, id ASC`,
  ).bind(auth.user.department_id).all();

  return json({
    department: {
      id: auth.user.department_id,
      name: auth.user.jabatan,
      sessionIntervalMinutes: Number(auth.user.session_interval_minutes || 120),
      sessionStartMinutes: Number(auth.user.session_start_minutes ?? 420),
    },
    checkpoints: checkpoints.results ?? [],
  });
}

async function updateProfilePicture(request, env) {
  const auth = await requireUser(request, env);
  if (auth.response) return auth.response;

  const body = await readJson(request);
  const picture = String(body.profilePicture ?? '');
  if (!/^data:image\/(jpeg|png|webp);base64,/i.test(picture)) {
    return json({ error: 'Format gambar mesti JPEG, PNG atau WebP.' }, 400);
  }
  if (picture.length > 700000) {
    return json({ error: 'Gambar terlalu besar. Had selepas pemampatan ialah kira-kira 500 KB.' }, 413);
  }

  await env.DB.prepare('UPDATE users SET profile_picture = ? WHERE id = ?')
    .bind(picture, auth.user.id)
    .run();

  const updated = await getUserById(env, auth.user.id);
  return json({ user: publicUser(updated) });
}

async function getScans(request, env, url) {
  const auth = await requireUser(request, env);
  if (auth.response) return auth.response;

  const requestedDate = url.searchParams.get('date') || malaysiaDateKey(new Date());
  if (!/^\d{4}-\d{2}-\d{2}$/.test(requestedDate)) {
    return json({ error: 'Tarikh tidak sah.' }, 400);
  }

  const role = String(auth.user.jawatan || '').trim().toLowerCase();
  const requestedDepartment = url.searchParams.get('departmentId');
  let departmentId = Number(auth.user.department_id || 0);
  if (requestedDepartment != null && requestedDepartment !== '') {
    const parsed = Number(requestedDepartment);
    if (!Number.isInteger(parsed) || parsed <= 0) {
      return json({ error: 'Jabatan tidak sah.' }, 400);
    }
    if (role !== 'management' && parsed !== departmentId) {
      return json({ error: 'Anda hanya boleh melihat Sejarah Rondaan Jabatan sendiri.' }, 403);
    }
    departmentId = parsed;
  }
  if (!departmentId) {
    return json({ error: 'Pengguna belum dipautkan kepada Jabatan.' }, 409);
  }

  const department = await env.DB.prepare(
    `SELECT id, name, session_interval_minutes, session_start_minutes
     FROM departments WHERE id = ? LIMIT 1`,
  ).bind(departmentId).first();
  if (!department) return json({ error: 'Jabatan tidak ditemui.' }, 404);

  const calendarBounds = malaysiaDayBounds(requestedDate);
  if (!calendarBounds) return json({ error: 'Tarikh tidak sah.' }, 400);

  const sessionStartMinutes = Math.max(
    0,
    Math.min(1439, Number(department.session_start_minutes ?? 420)),
  );
  const interval = Math.max(
    15,
    Math.min(1440, Number(department.session_interval_minutes || 120)),
  );
  const firstWindow = sessionWindow(
    new Date(calendarBounds.startMs),
    interval,
    sessionStartMinutes,
  );
  const lastWindow = sessionWindow(
    new Date(calendarBounds.endMs - 1),
    interval,
    sessionStartMinutes,
  );
  const queryStartIso = new Date(firstWindow.startMs).toISOString();
  const queryEndIso = new Date(lastWindow.endMs).toISOString();
  const calendarStartIso = new Date(calendarBounds.startMs).toISOString();
  const calendarEndIso = new Date(calendarBounds.endMs).toISOString();

  const [checkpointResult, scanResult, patrolResult, trailResult] = await Promise.all([
    env.DB.prepare(
      `SELECT id, name, position
       FROM checkpoints
       WHERE department_id = ? AND active = 1
       ORDER BY position ASC, id ASC`,
    ).bind(departmentId).all(),
    env.DB.prepare(
      `SELECT s.id, s.user_id, s.nfc_uid, s.scanned_at, s.checkpoint_id,
              s.session_index, c.name AS checkpoint_name,
              u.nama AS user_name, u.profile_picture
       FROM nfc_scans s
       JOIN users u ON u.id = s.user_id
       LEFT JOIN checkpoints c ON c.id = s.checkpoint_id
       WHERE COALESCE(c.department_id, u.department_id) = ?
         AND s.scanned_at >= ? AND s.scanned_at < ?
       ORDER BY s.scanned_at ASC, s.id ASC`,
    ).bind(departmentId, queryStartIso, queryEndIso).all(),
    env.DB.prepare(
      `SELECT h.user_id, h.client_session_id, h.started_at, h.ended_at,
              u.nama AS user_name, u.profile_picture
       FROM patrol_session_history h
       JOIN users u ON u.id = h.user_id
       WHERE h.department_id = ?
         AND h.started_at >= ? AND h.started_at < ?
       ORDER BY h.started_at DESC, h.id DESC`,
    ).bind(departmentId, calendarStartIso, calendarEndIso).all(),
    env.DB.prepare(
      `SELECT t.user_id, t.client_session_id, t.latitude, t.longitude,
              t.accuracy, t.recorded_at
       FROM live_patrol_trail t
       JOIN patrol_session_history h
         ON h.user_id = t.user_id
        AND h.client_session_id = t.client_session_id
       WHERE h.department_id = ?
         AND h.started_at >= ? AND h.started_at < ?
       ORDER BY t.user_id ASC, t.client_session_id ASC, t.recorded_at ASC`,
    ).bind(departmentId, calendarStartIso, calendarEndIso).all(),
  ]);

  const checkpoints = checkpointResult.results ?? [];
  const scans = scanResult.results ?? [];
  const trails = new Map();
  for (const row of trailResult.results ?? []) {
    const key = `${Number(row.user_id)}:${row.client_session_id}`;
    const list = trails.get(key) ?? [];
    list.push({
      latitude: Number(row.latitude),
      longitude: Number(row.longitude),
      accuracy: row.accuracy == null ? null : Number(row.accuracy),
      recordedAt: row.recorded_at,
    });
    trails.set(key, list);
  }

  const patrolRuns = (patrolResult.results ?? []).map((row) => {
    const key = `${Number(row.user_id)}:${row.client_session_id}`;
    const allTrail = trails.get(key) ?? [];
    const trail = compactTrail(allTrail, 500);
    const startMs = Date.parse(row.started_at);
    const endedAt = row.ended_at || null;
    const endMs = endedAt ? Date.parse(endedAt) : null;
    const runWindow = sessionWindow(new Date(startMs), interval, sessionStartMinutes);
    return {
      userId: Number(row.user_id),
      userName: row.user_name,
      profilePicture: row.profile_picture || null,
      clientSessionId: row.client_session_id,
      sessionIndex: runWindow.index,
      startedAt: row.started_at,
      endedAt,
      durationSeconds: endMs == null ? null : Math.max(0, Math.floor((endMs - startMs) / 1000)),
      trailPointCount: allTrail.length,
      trail,
    };
  });

  const nowMs = Date.now();
  const todayKey = malaysiaDateKey(new Date());
  const isPastDay = requestedDate < todayKey;
  const isFutureDay = requestedDate > todayKey;
  const sessions = [];

  if (!isFutureDay) {
    let cursor = firstWindow.startMs;
    while (cursor < calendarBounds.endMs) {
      const window = sessionWindow(
        new Date(cursor),
        interval,
        sessionStartMinutes,
      );
      const startMs = window.startMs;
      const endMs = window.endMs;
      if (startMs >= calendarBounds.endMs) break;
      if (requestedDate === todayKey && startMs > nowMs) break;

      const fullSessionScans = scans.filter((scan) => {
        const time = Date.parse(scan.scanned_at);
        return time >= startMs && time < endMs;
      });
      const calendarScans = fullSessionScans.filter((scan) => {
        const time = Date.parse(scan.scanned_at);
        return time >= calendarBounds.startMs && time < calendarBounds.endMs;
      });
      const scannedCheckpointIds = new Set(
        fullSessionScans
          .map((scan) => Number(scan.checkpoint_id || 0))
          .filter((id) => id > 0),
      );
      const missing = checkpoints.filter(
        (checkpoint) => !scannedCheckpointIds.has(Number(checkpoint.id)),
      );

      let status = 'in_progress';
      if (checkpoints.length === 0) status = 'no_checkpoints';
      else if (missing.length === 0) status = 'complete';
      else if (isPastDay || endMs <= nowMs) status = 'missed';

      const scannerIds = [...new Set(
        calendarScans
          .map((scan) => Number(scan.user_id || 0))
          .filter((id) => id > 0),
      )];
      const scannerNames = [...new Set(
        calendarScans
          .map((scan) => String(scan.user_name || '').trim())
          .filter(Boolean),
      )];
      const firstScan = calendarScans[0] ?? null;

      sessions.push({
        userId: scannerIds.length === 1 ? scannerIds[0] : 0,
        userName: scannerNames.length > 0
          ? scannerNames.join(', ')
          : 'Tiada pengawal direkodkan',
        profilePicture: scannerIds.length === 1
          ? (firstScan?.profile_picture || null)
          : null,
        index: window.index,
        startAt: new Date(startMs).toISOString(),
        endAt: new Date(endMs).toISOString(),
        status,
        expectedCount: checkpoints.length,
        scannedCount: scannedCheckpointIds.size,
        missingCheckpoints: missing.map((checkpoint) => ({
          id: checkpoint.id,
          name: checkpoint.name,
          position: checkpoint.position,
        })),
        scans: calendarScans.map(scanJson),
      });

      if (endMs <= cursor) break;
      cursor = endMs;
    }
    sessions.sort((left, right) => Date.parse(right.startAt) - Date.parse(left.startAt));
  }

  return json({
    date: requestedDate,
    departmentId: Number(department.id),
    department: department.name,
    sessionIntervalMinutes: interval,
    sessionStartMinutes,
    checkpoints,
    patrolRuns,
    sessions,
  });
}

function compactTrail(points, maxPoints = 500) {
  if (points.length <= maxPoints) return points;
  const step = Math.ceil(points.length / maxPoints);
  return points.filter((_, index) => index === 0 || index === points.length - 1 || index % step === 0);
}

async function createScan(request, env) {
  const auth = await requireUser(request, env);
  if (auth.response) return auth.response;

  if (!auth.user.department_id) {
    return json({ error: 'Pengguna belum dipautkan kepada Jabatan.' }, 409);
  }

  const body = await readJson(request);
  const nfcUid = normalizeUid(body.nfcUid);
  if (!nfcUid || nfcUid.length > 128) {
    return json({ error: 'UID NFC tidak sah.' }, 400);
  }

  const checkpoint = await env.DB.prepare(
    `SELECT id, name, position
     FROM checkpoints
     WHERE department_id = ? AND UPPER(nfc_uid) = UPPER(?) AND active = 1
     LIMIT 1`,
  ).bind(auth.user.department_id, nfcUid).first();

  if (!checkpoint) {
    return json({
      error: 'Tag ini tidak berdaftar sebagai checkpoint untuk Jabatan anda.',
    }, 403);
  }

  const scannedAt = new Date().toISOString();
  const interval = Math.max(15, Math.min(1440, Number(auth.user.session_interval_minutes || 120)));
  const sessionIndex = currentSessionIndex(new Date(), interval, auth.user.session_start_minutes);

  const result = await env.DB.prepare(
    `INSERT INTO nfc_scans (user_id, nfc_uid, scanned_at, checkpoint_id, session_index)
     VALUES (?, ?, ?, ?, ?)`,
  ).bind(auth.user.id, nfcUid, scannedAt, checkpoint.id, sessionIndex).run();

  return json({
    scan: {
      id: result.meta?.last_row_id ?? null,
      nfc_uid: nfcUid,
      scanned_at: scannedAt,
      checkpoint_id: checkpoint.id,
      checkpoint_name: checkpoint.name,
      session_index: sessionIndex,
    },
  }, 201);
}

async function adminUsers(request, env) {
  const auth = await requireManagement(request, env);
  if (auth.response) return auth.response;

  const result = await env.DB.prepare(
    `${userSelect()}
     ORDER BY u.nama ASC`,
  ).all();
  return json({ users: (result.results ?? []).map(publicUser) });
}

async function adminDepartments(request, env) {
  const auth = await requireManagement(request, env);
  if (auth.response) return auth.response;

  const result = await env.DB.prepare(
    `SELECT d.id, d.name, d.session_interval_minutes, d.session_start_minutes, d.active,
            COUNT(CASE WHEN c.active = 1 THEN 1 END) AS checkpoint_count
     FROM departments d
     LEFT JOIN checkpoints c ON c.department_id = d.id
     GROUP BY d.id
     ORDER BY d.name ASC`,
  ).all();

  return json({ departments: (result.results ?? []).map(departmentJson) });
}

async function createDepartment(request, env) {
  const auth = await requireManagement(request, env);
  if (auth.response) return auth.response;

  const body = await readJson(request);
  const name = String(body.name ?? '').trim();
  const interval = Number(body.sessionIntervalMinutes ?? 120);
  const startMinutes = Number(body.sessionStartMinutes ?? 420);
  const validation = validateDepartment(name, interval, startMinutes);
  if (validation) return json({ error: validation }, 400);

  const duplicate = await env.DB.prepare('SELECT id FROM departments WHERE LOWER(name) = LOWER(?) LIMIT 1')
    .bind(name)
    .first();
  if (duplicate) return json({ error: 'Jabatan dengan nama ini sudah wujud.' }, 409);

  const result = await env.DB.prepare(
    `INSERT INTO departments (name, session_interval_minutes, session_start_minutes, active, updated_at)
     VALUES (?, ?, ?, 1, CURRENT_TIMESTAMP)`,
  ).bind(name, interval, startMinutes).run();
  const department = await getDepartmentById(env, result.meta?.last_row_id);
  return json({ department: departmentJson(department) }, 201);
}

async function updateDepartment(request, env, departmentId) {
  const auth = await requireManagement(request, env);
  if (auth.response) return auth.response;

  const body = await readJson(request);
  const name = String(body.name ?? '').trim();
  const interval = Number(body.sessionIntervalMinutes ?? 120);
  const startMinutes = Number(body.sessionStartMinutes ?? 420);
  const active = body.active === false ? 0 : 1;
  const validation = validateDepartment(name, interval, startMinutes);
  if (validation) return json({ error: validation }, 400);

  const duplicate = await env.DB.prepare(
    'SELECT id FROM departments WHERE LOWER(name) = LOWER(?) AND id <> ? LIMIT 1',
  ).bind(name, departmentId).first();
  if (duplicate) return json({ error: 'Jabatan dengan nama ini sudah wujud.' }, 409);

  const existing = await getDepartmentById(env, departmentId);
  if (!existing) return json({ error: 'Jabatan tidak ditemui.' }, 404);

  await env.DB.batch([
    env.DB.prepare(
      `UPDATE departments
       SET name = ?, session_interval_minutes = ?, session_start_minutes = ?, active = ?, updated_at = CURRENT_TIMESTAMP
       WHERE id = ?`,
    ).bind(name, interval, startMinutes, active, departmentId),
    env.DB.prepare('UPDATE users SET jabatan = ? WHERE department_id = ?').bind(name, departmentId),
  ]);

  const department = await getDepartmentById(env, departmentId);
  return json({ department: departmentJson(department) });
}

async function adminCheckpoints(request, env, url) {
  const auth = await requireManagement(request, env);
  if (auth.response) return auth.response;

  const departmentId = Number(url.searchParams.get('departmentId'));
  if (!Number.isInteger(departmentId) || departmentId <= 0) {
    return json({ error: 'Jabatan tidak sah.' }, 400);
  }

  const result = await env.DB.prepare(
    `SELECT id, department_id, name, nfc_uid, position, active
     FROM checkpoints
     WHERE department_id = ?
     ORDER BY position ASC, id ASC`,
  ).bind(departmentId).all();
  return json({ checkpoints: (result.results ?? []).map(checkpointJson) });
}

async function createCheckpoint(request, env) {
  const auth = await requireManagement(request, env);
  if (auth.response) return auth.response;

  const body = await readJson(request);
  const departmentId = Number(body.departmentId);
  const name = String(body.name ?? '').trim();
  const nfcUid = normalizeUid(body.nfcUid);
  const position = Number(body.position ?? 1);
  const validation = validateCheckpoint(departmentId, name, nfcUid, position);
  if (validation) return json({ error: validation }, 400);

  const department = await getDepartmentById(env, departmentId);
  if (!department) return json({ error: 'Jabatan tidak ditemui.' }, 404);

  const duplicate = await findCheckpointDuplicate(env, departmentId, name, nfcUid, 0);
  if (duplicate) return json({ error: duplicate }, 409);

  const result = await env.DB.prepare(
    `INSERT INTO checkpoints (department_id, name, nfc_uid, position, active, updated_at)
     VALUES (?, ?, ?, ?, 1, CURRENT_TIMESTAMP)`,
  ).bind(departmentId, name, nfcUid, position).run();
  const checkpoint = await getCheckpointById(env, result.meta?.last_row_id);
  return json({ checkpoint: checkpointJson(checkpoint) }, 201);
}

async function updateCheckpoint(request, env, checkpointId) {
  const auth = await requireManagement(request, env);
  if (auth.response) return auth.response;

  const existing = await getCheckpointById(env, checkpointId);
  if (!existing) return json({ error: 'Checkpoint tidak ditemui.' }, 404);

  const body = await readJson(request);
  const departmentId = Number(body.departmentId ?? existing.department_id);
  const name = String(body.name ?? '').trim();
  const nfcUid = normalizeUid(body.nfcUid);
  const position = Number(body.position ?? 1);
  const active = body.active === false ? 0 : 1;
  const validation = validateCheckpoint(departmentId, name, nfcUid, position);
  if (validation) return json({ error: validation }, 400);

  const duplicate = await findCheckpointDuplicate(env, departmentId, name, nfcUid, checkpointId);
  if (duplicate) return json({ error: duplicate }, 409);

  await env.DB.prepare(
    `UPDATE checkpoints
     SET department_id = ?, name = ?, nfc_uid = ?, position = ?, active = ?, updated_at = CURRENT_TIMESTAMP
     WHERE id = ?`,
  ).bind(departmentId, name, nfcUid, position, active, checkpointId).run();
  const checkpoint = await getCheckpointById(env, checkpointId);
  return json({ checkpoint: checkpointJson(checkpoint) });
}

async function updateAdminUser(request, env, userId) {
  const auth = await requireManagement(request, env);
  if (auth.response) return auth.response;

  const body = await readJson(request);
  const nama = String(body.nama ?? '').trim().toUpperCase();
  const jawatan = String(body.jawatan ?? '').trim();
  const departmentId = Number(body.departmentId);

  if (nama.length < 3) return json({ error: 'Nama pengguna tidak sah.' }, 400);
  if (!['Patrol', 'Supervisor', 'Management'].includes(jawatan)) {
    return json({ error: 'Jawatan pengguna tidak sah.' }, 400);
  }
  if (!Number.isInteger(departmentId) || departmentId <= 0) {
    return json({ error: 'Pilih Jabatan pengguna.' }, 400);
  }

  const department = await env.DB.prepare(
    'SELECT id, name, active FROM departments WHERE id = ? LIMIT 1',
  ).bind(departmentId).first();
  if (!department || Number(department.active) !== 1) {
    return json({ error: 'Jabatan aktif tidak ditemui.' }, 404);
  }

  const user = await getUserById(env, userId);
  if (!user) return json({ error: 'Pengguna tidak ditemui.' }, 404);

  let profilePicture = user.profile_picture || null;
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

  await env.DB.prepare(
    `UPDATE users
     SET nama = ?, jawatan = ?, department_id = ?, jabatan = ?, profile_picture = ?
     WHERE id = ?`,
  ).bind(nama, jawatan, departmentId, department.name, profilePicture, userId).run();

  const updated = await getUserById(env, userId);
  return json({ user: publicUser(updated) });
}

async function updateUserDepartment(request, env, userId) {
  const auth = await requireManagement(request, env);
  if (auth.response) return auth.response;

  const body = await readJson(request);
  const departmentId = Number(body.departmentId);
  const department = await getDepartmentById(env, departmentId);
  if (!department || Number(department.active) !== 1) {
    return json({ error: 'Jabatan aktif tidak ditemui.' }, 404);
  }

  const user = await getUserById(env, userId);
  if (!user) return json({ error: 'Pengguna tidak ditemui.' }, 404);

  await env.DB.prepare('UPDATE users SET department_id = ?, jabatan = ? WHERE id = ?')
    .bind(departmentId, department.name, userId)
    .run();
  const updated = await getUserById(env, userId);
  return json({ user: publicUser(updated) });
}

async function requireManagement(request, env) {
  const auth = await requireUser(request, env);
  if (auth.response) return auth;
  if (String(auth.user.jawatan).toLowerCase() !== 'management') {
    return { response: json({ error: 'Akses Admin hanya untuk Management.' }, 403) };
  }
  return auth;
}

async function requireUser(request, env) {
  const token = getSessionToken(request);
  if (!token) {
    return { response: json({ error: 'Sesi tidak sah. Sila log masuk.' }, 401) };
  }

  const tokenHash = await sha256(token);
  const session = await env.DB.prepare(
    `SELECT user_id, expires_at_ms, created_at
     FROM sessions
     WHERE token_hash = ? AND expires_at_ms > ?
     LIMIT 1`,
  ).bind(tokenHash, Date.now()).first();

  if (!session) {
    return { response: json({ error: 'Sesi telah tamat. Sila log masuk semula.' }, 401) };
  }

  const user = await getUserById(env, session.user_id);
  if (!user || Number(user.active) !== 1) {
    await env.DB.prepare('DELETE FROM sessions WHERE token_hash = ?').bind(tokenHash).run();
    return { response: json({ error: 'Pengguna tidak aktif. Sila log masuk semula.' }, 401) };
  }

  const interval = Math.max(15, Math.min(1440, Number(user.session_interval_minutes || 120)));
  const window = sessionWindow(new Date(), interval, user.session_start_minutes);
  const rawCreatedAt = String(session.created_at || '').trim().replace(' ', 'T');
  const createdAtMs = Date.parse(rawCreatedAt.endsWith('Z') ? rawCreatedAt : `${rawCreatedAt}Z`);

  if (!Number.isFinite(createdAtMs) || createdAtMs < window.startMs) {
    await env.DB.prepare('DELETE FROM sessions WHERE token_hash = ?').bind(tokenHash).run();
    return {
      response: json(
        { error: 'Sesi Rondaan baharu telah bermula. Sila log masuk semula.' },
        401,
      ),
    };
  }

  return { user };
}

function userSelect() {
  return `SELECT u.id, u.nama, u.no_kad_pengenalan, u.jawatan, u.profile_picture,
                 u.jabatan, u.department_id, u.active,
                 COALESCE(d.name, u.jabatan) AS department_name,
                 COALESCE(d.session_interval_minutes, 120) AS session_interval_minutes,
                 COALESCE(d.session_start_minutes, 420) AS session_start_minutes
          FROM users u
          LEFT JOIN departments d ON d.id = u.department_id`;
}

async function getUserById(env, id) {
  return env.DB.prepare(`${userSelect()} WHERE u.id = ? LIMIT 1`).bind(id).first();
}

async function getDepartmentById(env, id) {
  if (!Number.isInteger(Number(id)) || Number(id) <= 0) return null;
  return env.DB.prepare(
    `SELECT d.id, d.name, d.session_interval_minutes, d.session_start_minutes, d.active,
            COUNT(CASE WHEN c.active = 1 THEN 1 END) AS checkpoint_count
     FROM departments d
     LEFT JOIN checkpoints c ON c.department_id = d.id
     WHERE d.id = ?
     GROUP BY d.id
     LIMIT 1`,
  ).bind(Number(id)).first();
}

async function getCheckpointById(env, id) {
  if (!Number.isInteger(Number(id)) || Number(id) <= 0) return null;
  return env.DB.prepare(
    `SELECT id, department_id, name, nfc_uid, position, active
     FROM checkpoints WHERE id = ? LIMIT 1`,
  ).bind(Number(id)).first();
}

async function findCheckpointDuplicate(env, departmentId, name, nfcUid, exceptId) {
  const byName = await env.DB.prepare(
    `SELECT id FROM checkpoints
     WHERE department_id = ? AND LOWER(name) = LOWER(?) AND id <> ? LIMIT 1`,
  ).bind(departmentId, name, exceptId).first();
  if (byName) return 'Nama checkpoint ini sudah digunakan dalam Jabatan tersebut.';

  const byUid = await env.DB.prepare(
    `SELECT id FROM checkpoints
     WHERE department_id = ? AND UPPER(nfc_uid) = UPPER(?) AND id <> ? LIMIT 1`,
  ).bind(departmentId, nfcUid, exceptId).first();
  if (byUid) return 'UID NFC ini sudah didaftarkan dalam Jabatan tersebut.';
  return null;
}

function publicUser(user) {
  return {
    id: Number(user.id),
    nama: user.nama,
    noKadPengenalan: user.no_kad_pengenalan,
    jawatan: user.jawatan,
    profilePicture: user.profile_picture,
    jabatan: user.department_name || user.jabatan || 'Belum ditetapkan',
    departmentId: user.department_id == null ? null : Number(user.department_id),
    sessionIntervalMinutes: Number(user.session_interval_minutes || 120),
    sessionStartMinutes: Number(user.session_start_minutes ?? 420),
    active: user.active === undefined ? true : Boolean(user.active),
  };
}

function departmentJson(row) {
  return {
    id: Number(row.id),
    name: row.name,
    sessionIntervalMinutes: Number(row.session_interval_minutes || 120),
    sessionStartMinutes: Number(row.session_start_minutes ?? 420),
    active: Boolean(row.active),
    checkpointCount: Number(row.checkpoint_count || 0),
  };
}

function checkpointJson(row) {
  return {
    id: Number(row.id),
    departmentId: Number(row.department_id),
    name: row.name,
    nfcUid: row.nfc_uid,
    position: Number(row.position || 1),
    active: Boolean(row.active),
  };
}

function scanJson(scan) {
  return {
    id: Number(scan.id),
    nfc_uid: scan.nfc_uid,
    scanned_at: scan.scanned_at,
    checkpoint_id: scan.checkpoint_id == null ? null : Number(scan.checkpoint_id),
    checkpoint_name: scan.checkpoint_name || null,
    session_index: scan.session_index == null ? null : Number(scan.session_index),
    user_id: scan.user_id == null ? null : Number(scan.user_id),
    user_name: scan.user_name || null,
    profile_picture: scan.profile_picture || null,
  };
}

function validateDepartment(name, interval, startMinutes) {
  if (name.length < 2 || name.length > 150) return 'Nama Jabatan mesti antara 2 hingga 150 aksara.';
  if (!Number.isInteger(interval) || interval < 15 || interval > 1440) {
    return 'Tempoh sesi mesti antara 15 hingga 1440 minit.';
  }
  if (!Number.isInteger(startMinutes) || startMinutes < 0 || startMinutes > 1439) {
    return 'Jam mula rondaan tidak sah.';
  }
  return null;
}

function validateCheckpoint(departmentId, name, nfcUid, position) {
  if (!Number.isInteger(departmentId) || departmentId <= 0) return 'Jabatan tidak sah.';
  if (name.length < 1 || name.length > 100) return 'Nama checkpoint tidak sah.';
  if (!nfcUid || nfcUid.length > 128) return 'UID NFC tidak sah.';
  if (!Number.isInteger(position) || position < 1 || position > 999) return 'Susunan checkpoint mesti antara 1 hingga 999.';
  return null;
}

function normalizeUid(value) {
  return String(value ?? '').trim().toUpperCase();
}

function scheduleDayWindow(value, startMinutes = 420) {
  const shifted = new Date(value.getTime() + MALAYSIA_OFFSET_MS);
  const minuteOfDay = shifted.getUTCHours() * 60 + shifted.getUTCMinutes();
  const safeStart = Math.max(0, Math.min(1439, Number(startMinutes ?? 420)));
  const localMidnightUtc = Date.UTC(shifted.getUTCFullYear(), shifted.getUTCMonth(), shifted.getUTCDate());
  let startMs = localMidnightUtc - MALAYSIA_OFFSET_MS + safeStart * 60000;
  if (minuteOfDay < safeStart) startMs -= 86400000;
  return { startMs, endMs: startMs + 86400000 };
}

function sessionWindow(value, interval, startMinutes = 420) {
  const day = scheduleDayWindow(value, startMinutes);
  const safeInterval = Math.max(15, Math.min(1440, Number(interval || 120)));
  const index = Math.floor((value.getTime() - day.startMs) / 60000 / safeInterval);
  const startMs = day.startMs + index * safeInterval * 60000;
  return { index, startMs, endMs: Math.min(day.endMs, startMs + safeInterval * 60000) };
}

function currentSessionIndex(value, interval, startMinutes = 420) {
  const day = scheduleDayWindow(value, startMinutes);
  const safeInterval = Math.max(15, Math.min(1440, Number(interval || 120)));
  return Math.floor((value.getTime() - day.startMs) / 60000 / safeInterval);
}

function scheduleDateKey(value, startMinutes = 420) {
  const day = scheduleDayWindow(value, startMinutes);
  return malaysiaDateKey(new Date(day.startMs));
}

function malaysiaDateKey(date) {
  const shifted = new Date(date.getTime() + MALAYSIA_OFFSET_MS);
  const y = shifted.getUTCFullYear();
  const m = String(shifted.getUTCMonth() + 1).padStart(2, '0');
  const d = String(shifted.getUTCDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

function malaysiaDayBounds(dateText) {
  const parts = dateText.split('-').map(Number);
  if (parts.length !== 3) return null;
  const [year, month, day] = parts;
  const localMidnightAsUtc = Date.UTC(year, month - 1, day, 0, 0, 0, 0);
  const startMs = localMidnightAsUtc - MALAYSIA_OFFSET_MS;
  const check = new Date(localMidnightAsUtc);
  if (
    check.getUTCFullYear() !== year ||
    check.getUTCMonth() !== month - 1 ||
    check.getUTCDate() !== day
  ) return null;
  const endMs = startMs + 24 * 60 * 60 * 1000;
  return {
    startMs,
    endMs,
    startIso: new Date(startMs).toISOString(),
    endIso: new Date(endMs).toISOString(),
  };
}

function getSessionToken(request) {
  const authorization = request.headers.get('Authorization') ?? '';
  if (authorization.startsWith('Bearer ')) return authorization.slice(7).trim();

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
