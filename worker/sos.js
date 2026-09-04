import offlineWorker from './offline.js';
import { dispatchSessionStartNotifications, pushConfigured, registerPushDevice, sendPushToUser, unregisterPushDevice } from './push.js';

const SESSION_COOKIE = 'rk_session';

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    try {
      if (url.pathname === '/api/push/register' && request.method === 'POST') {
        const auth = await requireUser(request, env);
        if (auth.response) return auth.response;
        try {
          return json(await registerPushDevice(env, auth.user, await readJson(request)));
        } catch (error) {
          return json({ error: error instanceof Error ? error.message : 'Pendaftaran push gagal.' }, 400);
        }
      }
      if (url.pathname === '/api/push/unregister' && request.method === 'POST') {
        const auth = await requireUser(request, env);
        if (auth.response) return auth.response;
        return json(await unregisterPushDevice(env, auth.user, await readJson(request)));
      }
      if (url.pathname === '/api/push/status' && request.method === 'GET') {
        const auth = await requireUser(request, env);
        if (auth.response) return auth.response;
        return json({ configured: pushConfigured(env) });
      }
      if (url.pathname === '/api/sos/alerts' && request.method === 'GET') {
        return getSosAlerts(request, env);
      }
      if (url.pathname === '/api/sos/manage' && request.method === 'GET') {
        return getManagedSos(request, env);
      }

      const acknowledgeMatch = url.pathname.match(/^\/api\/sos\/(\d+)\/ack$/);
      if (acknowledgeMatch && request.method === 'POST') {
        return acknowledgeSos(request, env, Number(acknowledgeMatch[1]));
      }

      const resolveMatch = url.pathname.match(/^\/api\/sos\/(\d+)\/resolve$/);
      if (resolveMatch && request.method === 'PUT') {
        return resolveSos(request, env, Number(resolveMatch[1]));
      }
    } catch (error) {
      console.error(JSON.stringify({
        scope: 'sos-worker',
        path: url.pathname,
        message: error instanceof Error ? error.message : String(error),
      }));
      return json({ error: 'Ralat pelayan SOS. Sila cuba lagi.' }, 500);
    }

    return offlineWorker.fetch(request, env, ctx);
  },
  async scheduled(event, env, ctx) {
    ctx.waitUntil(dispatchSessionStartNotifications(env, new Date(event.scheduledTime)));
  },
};

async function getSosAlerts(request, env) {
  const auth = await requireUser(request, env);
  if (auth.response) return auth.response;
  if (!auth.user.department_id) {
    return json({ error: 'Pengguna belum dipautkan kepada Sekolah.' }, 409);
  }

  const result = await env.DB.prepare(
    `SELECT s.id, s.user_id, s.triggered_at, s.note,
            u.nama, u.jawatan, u.profile_picture,
            COALESCE(d.name, u.jabatan) AS jabatan
     FROM sos_events s
     JOIN users u ON u.id = s.user_id
     LEFT JOIN departments d ON d.id = s.department_id
     WHERE s.department_id = ?
       AND s.status = 'active'
       AND NOT EXISTS (
         SELECT 1 FROM sos_alert_receipts r
         WHERE r.sos_event_id = s.id AND r.user_id = ?
       )
     ORDER BY s.triggered_at ASC, s.id ASC
     LIMIT 10`,
  ).bind(auth.user.department_id, auth.user.id).all();

  return json({
    generatedAt: new Date().toISOString(),
    alerts: result.results ?? [],
  });
}

async function acknowledgeSos(request, env, sosId) {
  const auth = await requireUser(request, env);
  if (auth.response) return auth.response;
  if (!auth.user.department_id) {
    return json({ error: 'Pengguna belum dipautkan kepada Sekolah.' }, 409);
  }

  const event = await env.DB.prepare(
    `SELECT id FROM sos_events WHERE id = ? AND department_id = ? LIMIT 1`,
  ).bind(sosId, auth.user.department_id).first();
  if (!event) return json({ error: 'SOS tidak ditemui dalam Sekolah anda.' }, 404);

  const acknowledgedAt = new Date().toISOString();
  await env.DB.prepare(
    `INSERT INTO sos_alert_receipts (sos_event_id, user_id, acknowledged_at)
     VALUES (?, ?, ?)
     ON CONFLICT(sos_event_id, user_id) DO UPDATE SET
       acknowledged_at = excluded.acknowledged_at`,
  ).bind(sosId, auth.user.id, acknowledgedAt).run();

  return json({ ok: true, acknowledgedAt });
}

async function getManagedSos(request, env) {
  const auth = await requireMonitor(request, env);
  if (auth.response) return auth.response;
  if (!auth.user.department_id) {
    return json({ error: 'Pengguna belum dipautkan kepada Sekolah.' }, 409);
  }

  const result = await env.DB.prepare(
    `SELECT s.id, s.user_id, s.triggered_at, s.note, s.status,
            s.resolved_at, s.resolution_note,
            u.nama, u.jawatan, u.profile_picture,
            COALESCE(d.name, u.jabatan) AS jabatan,
            ru.nama AS resolved_by_name
     FROM sos_events s
     JOIN users u ON u.id = s.user_id
     LEFT JOIN users ru ON ru.id = s.resolved_by_user_id
     LEFT JOIN departments d ON d.id = s.department_id
     WHERE s.department_id = ?
     ORDER BY CASE WHEN s.status = 'active' THEN 0 ELSE 1 END,
              s.triggered_at DESC, s.id DESC
     LIMIT 50`,
  ).bind(auth.user.department_id).all();

  return json({
    generatedAt: new Date().toISOString(),
    events: result.results ?? [],
  });
}

async function resolveSos(request, env, sosId) {
  const auth = await requireMonitor(request, env);
  if (auth.response) return auth.response;
  if (!auth.user.department_id) {
    return json({ error: 'Pengguna belum dipautkan kepada Sekolah.' }, 409);
  }

  const body = await readJson(request);
  const resolutionNote = String(body.note ?? '').trim().slice(0, 500);
  if (!resolutionNote) {
    return json({ error: 'Catatan penyelesaian SOS diperlukan.' }, 400);
  }

  const current = await env.DB.prepare(
    `SELECT id, user_id, status, resolved_at, resolution_note
     FROM sos_events
     WHERE id = ? AND department_id = ?
     LIMIT 1`,
  ).bind(sosId, auth.user.department_id).first();
  if (!current) return json({ error: 'SOS tidak ditemui dalam Sekolah anda.' }, 404);

  if (current.status === 'resolved') {
    return json({
      ok: true,
      alreadyResolved: true,
      event: {
        id: sosId,
        status: 'resolved',
        resolvedAt: current.resolved_at,
        resolutionNote: current.resolution_note,
      },
    });
  }

  const resolvedAt = new Date().toISOString();
  await env.DB.prepare(
    `UPDATE sos_events
     SET status = 'resolved', resolved_at = ?, resolved_by_user_id = ?, resolution_note = ?
     WHERE id = ? AND department_id = ? AND status = 'active'`,
  ).bind(
    resolvedAt,
    auth.user.id,
    resolutionNote,
    sosId,
    auth.user.department_id,
  ).run();

  await env.DB.prepare(
    `INSERT INTO sos_alert_receipts (sos_event_id, user_id, acknowledged_at)
     VALUES (?, ?, ?)
     ON CONFLICT(sos_event_id, user_id) DO UPDATE SET
       acknowledged_at = excluded.acknowledged_at`,
  ).bind(sosId, auth.user.id, resolvedAt).run();

  try {
    await sendPushToUser(env, Number(current.user_id), {
      title: 'SOS Telah Diselesaikan',
      body: `SOS anda telah ditandakan selesai oleh ${auth.user.nama}.`,
      kind: 'sos_resolved',
      data: { sosId },
    });
  } catch (error) {
    console.error('SOS resolution push failed', error);
  }

  return json({
    ok: true,
    event: {
      id: sosId,
      status: 'resolved',
      resolvedAt,
      resolvedBy: auth.user.nama,
      resolutionNote,
    },
  });
}

async function requireMonitor(request, env) {
  const auth = await requireUser(request, env);
  if (auth.response) return auth;
  const role = String(auth.user.jawatan ?? '').toLowerCase();
  if (role !== 'management' && role !== 'supervisor') {
    return {
      response: json({ error: 'Hanya Management atau Supervisor boleh mengurus SOS.' }, 403),
    };
  }
  return auth;
}

async function requireUser(request, env) {
  const token = getSessionToken(request);
  if (!token) {
    return { response: json({ error: 'Sesi tidak sah. Sila log masuk.' }, 401) };
  }

  const user = await env.DB.prepare(
    `SELECT u.id, u.nama, u.no_kad_pengenalan, u.jawatan, u.profile_picture,
            u.jabatan, u.active, u.department_id,
            COALESCE(d.session_interval_minutes, 120) AS session_interval_minutes
     FROM sessions s
     JOIN users u ON u.id = s.user_id
     LEFT JOIN departments d ON d.id = u.department_id
     WHERE s.token_hash = ? AND s.expires_at_ms > ? AND u.active = 1
     LIMIT 1`,
  ).bind(await sha256(token), Date.now()).first();

  if (!user) {
    return { response: json({ error: 'Sesi telah tamat. Sila log masuk semula.' }, 401) };
  }
  return { user };
}

function getSessionToken(request) {
  const authorization = request.headers.get('Authorization') ?? '';
  if (authorization.startsWith('Bearer ')) return authorization.slice(7).trim();

  const cookie = request.headers.get('Cookie') ?? '';
  for (const part of cookie.split(';')) {
    const [name, ...value] = part.trim().split('=');
    if (name === SESSION_COOKIE) {
      try {
        return decodeURIComponent(value.join('='));
      } catch (_) {
        return value.join('=');
      }
    }
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

async function sha256(value) {
  const digest = await crypto.subtle.digest(
    'SHA-256',
    new TextEncoder().encode(value),
  );
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
    },
  });
}
