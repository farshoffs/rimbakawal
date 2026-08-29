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

async function sendToRows(env, rows, payload) {
  if (rows.length === 0) return { sent: 0, configured: true };
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
                notification: { sound: 'default' },
              },
              apns: {
                headers: { 'apns-priority': '10' },
                payload: { aps: { sound: 'default' } },
              },
              webpush: {
                headers: { Urgency: 'high' },
                notification: {
                  icon: '/icons/Icon-192.png',
                  badge: '/icons/Icon-192.png',
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
  const local = new Date(scheduledAt.getTime() + MALAYSIA_OFFSET_MS);
  const minuteOfDay = local.getUTCHours() * 60 + local.getUTCMinutes();
  const departments = await env.DB.prepare(
    `SELECT id, name, session_interval_minutes, session_start_minutes
     FROM departments WHERE active = 1`,
  ).all();

  for (const department of departments.results ?? []) {
    const interval = Math.max(15, Math.min(1440, Number(department.session_interval_minutes || 120)));
    const startMinutes = Math.max(0, Math.min(1439, Number(department.session_start_minutes ?? 420)));
    const relative = (minuteOfDay - startMinutes + 1440) % 1440;
    if (relative % interval !== 0) continue;
    const index = Math.floor(relative / interval);
    const scheduleDate = new Date(local.getTime());
    if (minuteOfDay < startMinutes) scheduleDate.setUTCDate(scheduleDate.getUTCDate() - 1);
    const dayKey = `${scheduleDate.getUTCFullYear()}-${two(scheduleDate.getUTCMonth() + 1)}-${two(scheduleDate.getUTCDate())}`;
    const dispatchKey = `session:${department.id}:${dayKey}:${index}`;
    const inserted = await env.DB.prepare(
      `INSERT OR IGNORE INTO push_dispatch_log (dispatch_key, kind, created_at)
       VALUES (?, 'session_start', ?)`,
    ).bind(dispatchKey, new Date().toISOString()).run();
    if (Number(inserted.meta?.changes || 0) === 0) continue;

    const start = (startMinutes + index * interval) % 1440;
    const end = (start + interval) % 1440;
    await sendPushToDepartment(env, department.id, {
      title: `Sesi Rondaan ${index + 1} Bermula`,
      body: `${department.name} • ${hm(start)}–${hm(end)}. Sila mulakan rondaan dan lengkapkan checkpoint.`,
      kind: 'session_start',
      data: { sessionIndex: index + 1, departmentId: department.id },
      roles: ['patrol', 'supervisor'],
    });
  }

  const cutoff = new Date(Date.now() - 14 * 86400000).toISOString();
  await env.DB.prepare('DELETE FROM push_dispatch_log WHERE created_at < ?').bind(cutoff).run();
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

function hm(minutes) {
  const normalized = ((minutes % 1440) + 1440) % 1440;
  return `${two(Math.floor(normalized / 60))}:${two(normalized % 60)}`;
}
