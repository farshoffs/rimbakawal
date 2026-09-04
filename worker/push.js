const MALAYSIA_OFFSET_MS = 8 * 60 * 60 * 1000;
let cachedAccessToken = null;
let cachedAccessTokenExpiresAt = 0;

export function pushConfigured(env) {
  return Boolean(
    env.FIREBASE_PROJECT_ID &&
    env.FIREBASE_SERVICE_ACCOUNT_EMAIL &&
    env.FIREBASE_SERVICE_ACCOUNT_PRIVATE_KEY
  );
}

export async function registerPushDevice(env, user, body) {
  const token = String(body?.token ?? '').trim();
  const platform = String(body?.platform ?? '').trim().toLowerCase();
  if (!token || token.length > 4096) throw new Error('Token push tidak sah.');
  if (!['web', 'android', 'ios'].includes(platform)) {
    throw new Error('Platform push tidak sah.');
  }
  const now = new Date().toISOString();
  await env.DB.prepare(
    `INSERT INTO push_devices (user_id, token, platform, active, created_at, updated_at)
     VALUES (?, ?, ?, 1, ?, ?)
     ON CONFLICT(token) DO UPDATE SET
       user_id = excluded.user_id,
       platform = excluded.platform,
       active = 1,
       updated_at = excluded.updated_at`,
  ).bind(user.id, token, platform, now, now).run();
  return { ok: true, configured: pushConfigured(env) };
}

export async function unregisterPushDevice(env, user, body) {
  const token = String(body?.token ?? '').trim();
  if (!token) return { ok: true };
  await env.DB.prepare(
    `UPDATE push_devices SET active = 0, updated_at = ?
     WHERE user_id = ? AND token = ?`,
  ).bind(new Date().toISOString(), user.id, token).run();
  return { ok: true };
}

export async function sendPushToDepartment(
  env,
  departmentId,
  { title, body, kind, data = {}, roles = null, excludeUserId = null },
) {
  if (!pushConfigured(env) || !departmentId) return { sent: 0, configured: false };
  const roleValues = Array.isArray(roles) ? roles.map((role) => String(role).toLowerCase()) : null;
  let sql = `SELECT pd.id, pd.token, pd.user_id
             FROM push_devices pd
             JOIN users u ON u.id = pd.user_id
             WHERE pd.active = 1 AND u.active = 1 AND u.department_id = ?`;
  const binds = [departmentId];
  if (excludeUserId != null) {
    sql += ' AND u.id <> ?';
    binds.push(excludeUserId);
  }
  if (roleValues && roleValues.length > 0) {
    sql += ` AND LOWER(u.jawatan) IN (${roleValues.map(() => '?').join(',')})`;
    binds.push(...roleValues);
  }
  const result = await env.DB.prepare(sql).bind(...binds).all();
  return sendToRows(env, result.results ?? [], { title, body, kind, data });
}

export async function sendPushToUser(env, userId, payload) {
  if (!pushConfigured(env) || !userId) return { sent: 0, configured: false };
  const result = await env.DB.prepare(
    `SELECT id, token, user_id FROM push_devices
     WHERE user_id = ? AND active = 1`,
  ).bind(userId).all();
  return sendToRows(env, result.results ?? [], payload);
}

export async function sendPushToDevice(env, userId, token, payload) {
  const deviceToken = String(token ?? '').trim();
  if (!pushConfigured(env) || !userId || !deviceToken) {
    return { sent: 0, configured: pushConfigured(env) };
  }
  const row = await env.DB.prepare(
    `SELECT id, token, user_id FROM push_devices
     WHERE user_id = ? AND token = ? AND active = 1
     LIMIT 1`,
  ).bind(userId, deviceToken).first();
  if (!row) return { sent: 0, configured: true, registered: false };
  return { ...(await sendToRows(env, [row], payload)), registered: true };
}

async function sendToRows(env, rows, payload) {
  if (rows.length === 0) return { sent: 0, configured: true };
  const collapseKey = String(payload.collapseKey ?? '').trim().slice(0, 64);
  let accessToken;
  try {
    accessToken = await firebaseAccessToken(env);
  } catch (error) {
    console.error('FCM OAuth failed', error);
    return { sent: 0, configured: true };
  }
  let sent = 0;
  for (const row of rows) {
    try {
      const response = await fetch(
        `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(env.FIREBASE_PROJECT_ID)}/messages:send`,
        {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${accessToken}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            message: {
              token: row.token,
              notification: { title: payload.title, body: payload.body },
              data: stringifyData({
                ...payload.data,
                kind: payload.kind,
                title: payload.title,
                body: payload.body,
              }),
              android: {
                priority: 'HIGH',
                notification: {
                  sound: 'default',
                  ...(collapseKey ? { tag: collapseKey } : {}),
                },
              },
              apns: {
                headers: {
                  'apns-priority': '10',
                  ...(collapseKey ? { 'apns-collapse-id': collapseKey } : {}),
                },
                payload: { aps: { sound: 'default' } },
              },
              webpush: {
                headers: { Urgency: 'high' },
                notification: {
                  icon: '/icons/Icon-192.png',
                  badge: '/icons/Icon-192.png',
                  ...(collapseKey ? { tag: collapseKey } : {}),
                },
              },
            },
          }),
        },
      );
      if (response.ok) {
        sent += 1;
        continue;
      }
      const errorText = await response.text();
      if (response.status === 404 || response.status === 400 || errorText.includes('UNREGISTERED')) {
        await env.DB.prepare(
          'UPDATE push_devices SET active = 0, updated_at = ? WHERE id = ?',
        ).bind(new Date().toISOString(), row.id).run();
      }
      console.error('FCM send failed', response.status, errorText.slice(0, 500));
    } catch (error) {
      console.error('FCM device send exception', error);
    }
  }
  return { sent, configured: true };
}

export async function dispatchSessionStartNotifications(env, scheduledAt = new Date()) {
  if (!pushConfigured(env)) return;
  const departments = await env.DB.prepare(
    `SELECT id, name, session_interval_minutes, session_start_minutes
     FROM departments WHERE active = 1`,
  ).all();

  for (const department of departments.results ?? []) {
    const interval = Math.max(15, Math.min(1440, Number(department.session_interval_minutes || 120)));
    const startMinutes = Math.max(0, Math.min(1439, Number(department.session_start_minutes ?? 420)));
    const window = sessionWindowAt(scheduledAt, interval, startMinutes);
    const durationMinutes = Math.max(1, Math.round((window.end.getTime() - window.start.getTime()) / 60000));
    const minuteIntoSession = Math.max(0, Math.floor((scheduledAt.getTime() - window.start.getTime()) / 60000));
    const commonData = {
      sessionIndex: window.index + 1,
      sessionDate: malaysiaDateKey(window.start),
      departmentId: department.id,
    };

    if (minuteIntoSession === 0) {
      await autoCloseExpiredLivePatrols(env, department.id, window.start);
      const collapseSuffix = `${department.id}-${window.dayKey}-${window.index}`;
      if (await claimDispatch(env, `session-logout:${collapseSuffix}`, 'session_logout_warning')) {
        await sendPushToDepartment(env, department.id, {
          title: 'Sesi Baharu • Log Masuk Semula',
          body: `Sesi Rondaan ${window.index + 1} telah bermula. Peranti ini akan log keluar dan anda perlu log masuk semula.`,
          kind: 'session_logout_warning',
          data: commonData,
          roles: ['patrol', 'supervisor', 'management'],
          collapseKey: `rk-session-logout-${collapseSuffix}`,
        });
      }
      await new Promise((resolve) => setTimeout(resolve, 250));
      if (await claimDispatch(env, `session:${department.id}:${window.dayKey}:${window.index}`, 'session_start')) {
        await sendPushToDepartment(env, department.id, {
          title: `Sesi Rondaan ${window.index + 1} Bermula`,
          body: `${department.name} • ${hmFromDate(window.start)}–${hmFromDate(window.end)}. Sila log masuk semula dan mulakan rondaan.`,
          kind: 'session_start',
          data: commonData,
          roles: ['patrol', 'supervisor', 'management'],
          collapseKey: `rk-session-start-${collapseSuffix}`,
        });
      }
      const previous = sessionWindowAt(new Date(window.start.getTime() - 60000), interval, startMinutes);
      await dispatchPreviousOutcome(env, department, previous);
    }

    const notStartedMinute = Math.min(15, Math.max(5, Math.floor(durationMinutes / 4)));
    if (minuteIntoSession === notStartedMinute) {
      await dispatchNotStarted(env, department, window);
    }

    const warningLead = Math.max(2, Math.min(15, Math.floor(durationMinutes / 4)));
    const warningMinute = durationMinutes - warningLead;
    if (warningMinute > 0 && minuteIntoSession === warningMinute) {
      await dispatchEndingSoon(env, department, window, warningLead);
    }
  }

  const cutoff = new Date(Date.now() - 14 * 86400000).toISOString();
  await env.DB.prepare('DELETE FROM push_dispatch_log WHERE created_at < ?').bind(cutoff).run();
}

async function dispatchNotStarted(env, department, window) {
  const total = await checkpointTotal(env, department.id);
  if (total <= 0) return;
  const users = await patrolUsersWithProgress(env, department.id, window.start, window.end);
  for (const user of users) {
    if (user.started || user.scanCount > 0) continue;
    const key = `not-started:${department.id}:${window.dayKey}:${window.index}:${user.id}`;
    if (!await claimDispatch(env, key, 'patrol_not_started')) continue;
    await sendPushToUser(env, user.id, {
      title: 'Rondaan Belum Dimulakan',
      body: `Sesi Rondaan ${window.index + 1} sedang berjalan. Anda belum merekod sebarang checkpoint.`,
      kind: 'patrol_not_started',
      data: {
        sessionIndex: window.index + 1,
        sessionDate: malaysiaDateKey(window.start),
        departmentId: department.id,
      },
    });
  }
}

async function dispatchEndingSoon(env, department, window, warningLead) {
  const total = await checkpointTotal(env, department.id);
  if (total <= 0) return;
  const users = await patrolUsersWithProgress(env, department.id, window.start, window.end);
  for (const user of users) {
    if (user.scanCount >= total) continue;
    const key = `ending:${department.id}:${window.dayKey}:${window.index}:${user.id}`;
    if (!await claimDispatch(env, key, 'session_ending')) continue;
    await sendPushToUser(env, user.id, {
      title: `Sesi Hampir Tamat • ${warningLead} minit`,
      body: `${user.scanCount}/${total} checkpoint direkod. Lengkapkan baki checkpoint sebelum sesi tamat.`,
      kind: 'session_ending',
      data: {
        sessionIndex: window.index + 1,
        sessionDate: malaysiaDateKey(window.start),
        departmentId: department.id,
        scanned: user.scanCount,
        total,
      },
    });
  }
}

async function dispatchPreviousOutcome(env, department, window) {
  const total = await checkpointTotal(env, department.id);
  if (total <= 0) return;
  const users = await patrolUsersWithProgress(env, department.id, window.start, window.end);
  let missed = 0;
  let incomplete = 0;
  for (const user of users) {
    if (user.scanCount >= total) continue;
    const kind = user.scanCount === 0 ? 'session_missed' : 'session_incomplete';
    if (kind === 'session_missed') missed += 1;
    else incomplete += 1;
    const key = `outcome:${department.id}:${window.dayKey}:${window.index}:${user.id}`;
    if (!await claimDispatch(env, key, kind)) continue;
    await sendPushToUser(env, user.id, {
      title: kind === 'session_missed' ? 'Sesi Rondaan Terlepas' : 'Sesi Rondaan Tidak Lengkap',
      body: `${user.scanCount}/${total} checkpoint direkod sebelum sesi tamat.`,
      kind,
      data: {
        sessionIndex: window.index + 1,
        sessionDate: malaysiaDateKey(window.start),
        departmentId: department.id,
        scanned: user.scanCount,
        total,
      },
    });
  }

  if (missed + incomplete > 0) {
    const key = `outcome-admin:${department.id}:${window.dayKey}:${window.index}`;
    if (await claimDispatch(env, key, 'session_outcome_summary')) {
      await sendPushToDepartment(env, department.id, {
        title: 'Ringkasan Sesi Rondaan',
        body: `${missed} terlepas • ${incomplete} tidak lengkap bagi sesi yang baru tamat.`,
        kind: 'session_incomplete',
        data: {
          sessionIndex: window.index + 1,
          sessionDate: malaysiaDateKey(window.start),
          departmentId: department.id,
          missed,
          incomplete,
        },
        roles: ['management', 'supervisor'],
      });
    }
  }
}

async function autoCloseExpiredLivePatrols(env, departmentId, currentStart) {
  const stale = await env.DB.prepare(
    `SELECT user_id, client_session_id
     FROM live_patrol_presence
     WHERE department_id = ? AND active = 1 AND started_at < ?`,
  ).bind(departmentId, currentStart.toISOString()).all();
  const endedAt = currentStart.toISOString();
  for (const row of stale.results ?? []) {
    await env.DB.prepare(
      `UPDATE live_patrol_presence
       SET active = 0, ended_at = ?, updated_at = ?
       WHERE user_id = ? AND client_session_id = ? AND active = 1`,
    ).bind(endedAt, endedAt, row.user_id, row.client_session_id).run();
    await env.DB.prepare(
      `UPDATE patrol_session_history
       SET ended_at = COALESCE(ended_at, ?), updated_at = ?
       WHERE user_id = ? AND client_session_id = ?`,
    ).bind(endedAt, endedAt, row.user_id, row.client_session_id).run();
  }
}

async function patrolUsersWithProgress(env, departmentId, start, end) {
  const result = await env.DB.prepare(
    `SELECT u.id, u.nama,
            COUNT(DISTINCT n.checkpoint_id) AS scan_count,
            CASE WHEN EXISTS (
              SELECT 1 FROM patrol_session_history p
              WHERE p.user_id = u.id
                AND p.started_at >= ? AND p.started_at < ?
            ) THEN 1 ELSE 0 END AS started
     FROM users u
     LEFT JOIN nfc_scans n
       ON n.user_id = u.id
      AND n.scanned_at >= ? AND n.scanned_at < ?
      AND n.checkpoint_id IS NOT NULL
     WHERE u.department_id = ? AND u.active = 1
       AND LOWER(u.jawatan) IN ('patrol', 'supervisor')
     GROUP BY u.id, u.nama
     ORDER BY u.id`,
  ).bind(
    start.toISOString(),
    end.toISOString(),
    start.toISOString(),
    end.toISOString(),
    departmentId,
  ).all();
  return (result.results ?? []).map((row) => ({
    id: Number(row.id),
    nama: row.nama,
    scanCount: Number(row.scan_count || 0),
    started: Number(row.started || 0) === 1,
  }));
}

async function checkpointTotal(env, departmentId) {
  const row = await env.DB.prepare(
    `SELECT COUNT(*) AS total FROM checkpoints
     WHERE department_id = ? AND active = 1`,
  ).bind(departmentId).first();
  return Number(row?.total || 0);
}

async function claimDispatch(env, key, kind) {
  const inserted = await env.DB.prepare(
    `INSERT OR IGNORE INTO push_dispatch_log (dispatch_key, kind, created_at)
     VALUES (?, ?, ?)`,
  ).bind(key, kind, new Date().toISOString()).run();
  return Number(inserted.meta?.changes || 0) > 0;
}

function sessionWindowAt(value, interval, startMinutes) {
  const shifted = new Date(value.getTime() + MALAYSIA_OFFSET_MS);
  const minuteOfDay = shifted.getUTCHours() * 60 + shifted.getUTCMinutes();
  const localMidnightUtc = Date.UTC(
    shifted.getUTCFullYear(),
    shifted.getUTCMonth(),
    shifted.getUTCDate(),
  );
  let dayStartMs = localMidnightUtc - MALAYSIA_OFFSET_MS + startMinutes * 60000;
  if (minuteOfDay < startMinutes) dayStartMs -= 86400000;
  const index = Math.max(0, Math.floor((value.getTime() - dayStartMs) / (interval * 60000)));
  const startMs = dayStartMs + index * interval * 60000;
  const endMs = Math.min(dayStartMs + 86400000, startMs + interval * 60000);
  const dayLocal = new Date(dayStartMs + MALAYSIA_OFFSET_MS);
  const dayKey = `${dayLocal.getUTCFullYear()}-${two(dayLocal.getUTCMonth() + 1)}-${two(dayLocal.getUTCDate())}`;
  return { index, dayKey, start: new Date(startMs), end: new Date(endMs) };
}

function malaysiaDateKey(value) {
  const shifted = new Date(value.getTime() + MALAYSIA_OFFSET_MS);
  return `${shifted.getUTCFullYear()}-${two(shifted.getUTCMonth() + 1)}-${two(shifted.getUTCDate())}`;
}

function hmFromDate(value) {
  const shifted = new Date(value.getTime() + MALAYSIA_OFFSET_MS);
  return `${two(shifted.getUTCHours())}:${two(shifted.getUTCMinutes())}`;
}

async function firebaseAccessToken(env) {
  if (cachedAccessToken && Date.now() < cachedAccessTokenExpiresAt - 60000) {
    return cachedAccessToken;
  }
  const now = Math.floor(Date.now() / 1000);
  const header = base64UrlJson({ alg: 'RS256', typ: 'JWT' });
  const claim = base64UrlJson({
    iss: env.FIREBASE_SERVICE_ACCOUNT_EMAIL,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  });
  const unsigned = `${header}.${claim}`;
  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToArrayBuffer(env.FIREBASE_SERVICE_ACCOUNT_PRIVATE_KEY),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(unsigned),
  );
  const assertion = `${unsigned}.${base64UrlBytes(new Uint8Array(signature))}`;
  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  });
  if (!response.ok) throw new Error(`OAuth ${response.status}: ${(await response.text()).slice(0, 300)}`);
  const json = await response.json();
  cachedAccessToken = json.access_token;
  cachedAccessTokenExpiresAt = Date.now() + Number(json.expires_in || 3600) * 1000;
  return cachedAccessToken;
}

function pemToArrayBuffer(value) {
  const normalized = String(value || '').replace(/\\n/g, '\n');
  const base64 = normalized
    .replace(/-----BEGIN PRIVATE KEY-----/g, '')
    .replace(/-----END PRIVATE KEY-----/g, '')
    .replace(/\s+/g, '');
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

function base64UrlJson(value) {
  return base64UrlBytes(new TextEncoder().encode(JSON.stringify(value)));
}

function base64UrlBytes(bytes) {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}

function stringifyData(data) {
  return Object.fromEntries(
    Object.entries(data || {}).map(([key, value]) => [key, String(value ?? '')]),
  );
}

function two(value) {
  return String(value).padStart(2, '0');
}
