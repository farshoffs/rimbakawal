import sosWorker from './sos.js';
import { sendPushToDepartment, sendPushToUser } from './push.js';

const SESSION_COOKIE = 'rk_session';
const MALAYSIA_OFFSET_MS = 8 * 60 * 60 * 1000;
const MAX_SELFIE_CHARS = 650000;
const DEFAULT_RADIUS_M = 150;

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    try {
      if (url.pathname === '/api/attendance/status' && request.method === 'GET') {
        return attendanceStatus(request, env);
      }
      if (url.pathname === '/api/attendance/punch' && request.method === 'POST') {
        return punchAttendance(request, env);
      }
      if (url.pathname === '/api/admin/attendance' && request.method === 'GET') {
        return adminAttendance(request, env, url);
      }
      const attendanceReviewMatch = url.pathname.match(/^\/api\/admin\/attendance\/(\d+)\/review$/);
      if (attendanceReviewMatch && request.method === 'POST') {
        return reviewAttendance(request, env, Number(attendanceReviewMatch[1]));
      }
      if (url.pathname === '/api/admin/departments' && request.method === 'GET') {
        return adminDepartments(request, env);
      }
      if (url.pathname === '/api/admin/departments' && request.method === 'POST') {
        return createDepartment(request, env);
      }

      const departmentMatch = url.pathname.match(/^\/api\/admin\/departments\/(\d+)$/);
      if (departmentMatch && request.method === 'PUT') {
        return updateDepartment(request, env, Number(departmentMatch[1]));
      }
      if (departmentMatch && request.method === 'DELETE') {
        return deleteDepartment(request, env, Number(departmentMatch[1]));
      }

      if (url.pathname === '/api/admin/command-center' && request.method === 'GET') {
        return commandCenterWithAttendance(request, env, ctx);
      }
    } catch (error) {
      console.error(JSON.stringify({
        scope: 'attendance-worker',
        path: url.pathname,
        message: error instanceof Error ? error.message : String(error),
      }));
      return json({ error: 'Ralat modul kehadiran. Sila cuba lagi.' }, 500);
    }
    return sosWorker.fetch(request, env, ctx);
  },
  async scheduled(event, env, ctx) {
    if (typeof sosWorker.scheduled === 'function') {
      return sosWorker.scheduled(event, env, ctx);
    }
  },
};

async function attendanceStatus(request, env) {
  const auth = await requireUser(request, env);
  if (auth.response) return auth.response;
  if (!auth.user.department_id) {
    return json({ error: 'Pengguna belum dipautkan kepada Sekolah.' }, 409);
  }

  const department = await getDepartment(env, auth.user.department_id);
  if (!department) return json({ error: 'Sekolah tidak ditemui.' }, 404);
  const workDate = malaysiaDateKey(new Date());
  const result = await env.DB.prepare(
    `SELECT id, punch_type, punched_at, latitude, longitude, accuracy_m, distance_m,
            face_status, face_score, face_model, face_reason
     FROM attendance_records
     WHERE user_id = ? AND work_date = ?
     ORDER BY punched_at ASC, id ASC`,
  ).bind(auth.user.id, workDate).all();
  const records = (result.results ?? []).map(attendanceJson);
  const latest = records.length ? records[records.length - 1] : null;

  return json({
    workDate,
    department: departmentJson(department),
    nextPunchType: latest?.punchType === 'IN' ? 'OUT' : 'IN',
    latest,
    records,
    profilePictureConfigured: Boolean(auth.user.profile_picture),
  });
}

async function punchAttendance(request, env) {
  const auth = await requireUser(request, env);
  if (auth.response) return auth.response;
  if (!auth.user.department_id) {
    return json({ error: 'Pengguna belum dipautkan kepada Sekolah.' }, 409);
  }
  if (!auth.user.profile_picture) {
    return json({
      error: 'Gambar profil diperlukan sebagai rujukan pengecaman wajah. Sila kemas kini Profil dahulu.',
    }, 409);
  }

  const department = await getDepartment(env, auth.user.department_id);
  if (!department) return json({ error: 'Sekolah tidak ditemui.' }, 404);
  const centerLat = Number(department.attendance_latitude);
  const centerLng = Number(department.attendance_longitude);
  const radius = Math.max(30, Number(department.attendance_radius_m || DEFAULT_RADIUS_M));
  if (!Number.isFinite(centerLat) || !Number.isFinite(centerLng)) {
    return json({ error: 'Admin belum menetapkan kawasan kehadiran Sekolah pada peta.' }, 409);
  }

  const body = await readJson(request);
  const latitude = Number(body.latitude);
  const longitude = Number(body.longitude);
  const accuracy = Number(body.accuracy ?? 9999);
  const selfie = String(body.selfie ?? '');
  if (!validCoordinate(latitude, longitude)) {
    return json({ error: 'Lokasi semasa tidak sah.' }, 400);
  }
  if (!Number.isFinite(accuracy) || accuracy < 0 || accuracy > 100) {
    return json({
      error: 'Ketepatan GPS belum mencukupi. Cuba bergerak ke kawasan terbuka dan cuba semula.',
    }, 422);
  }
  if (!/^data:image\/(jpeg|jpg|png|webp);base64,/i.test(selfie)) {
    return json({ error: 'Selfie kehadiran tidak sah.' }, 400);
  }
  if (selfie.length > MAX_SELFIE_CHARS) {
    return json({ error: 'Selfie terlalu besar. Ambil gambar semula.' }, 413);
  }

  const distance = haversineMeters(latitude, longitude, centerLat, centerLng);
  if (distance > radius) {
    return json({
      error: `Anda berada ${Math.round(distance)}m dari pusat kawasan. Had Sekolah ialah ${Math.round(radius)}m.`,
      distanceMeters: distance,
      radiusMeters: radius,
    }, 403);
  }

  const workDate = malaysiaDateKey(new Date());
  const latest = await env.DB.prepare(
    `SELECT id, punch_type, punched_at
     FROM attendance_records
     WHERE user_id = ? AND work_date = ?
     ORDER BY punched_at DESC, id DESC LIMIT 1`,
  ).bind(auth.user.id, workDate).first();
  if (latest && Date.now() - Date.parse(latest.punched_at) < 60000) {
    return json({ error: 'Punch terlalu rapat. Tunggu sekurang-kurangnya 1 minit.' }, 429);
  }
  const punchType = latest?.punch_type === 'IN' ? 'OUT' : 'IN';

  const face = await verifyFace(env, auth.user.profile_picture, selfie);
  if (face.status === 'different' && Number(face.score || 0) >= 80) {
    return json({
      error: 'Pengesahan wajah tidak sepadan dengan gambar profil. Cuba ambil selfie semula dengan pencahayaan yang jelas.',
      faceVerification: face,
    }, 403);
  }

  const punchedAt = new Date().toISOString();
  const profileHash = await sha256(auth.user.profile_picture);
  const insert = await env.DB.prepare(
    `INSERT INTO attendance_records (
       user_id, department_id, work_date, punch_type, punched_at,
       latitude, longitude, accuracy_m, distance_m, selfie_data,
       profile_picture_hash, face_status, face_score, face_model, face_reason
     ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
  ).bind(
    auth.user.id,
    auth.user.department_id,
    workDate,
    punchType,
    punchedAt,
    latitude,
    longitude,
    accuracy,
    distance,
    selfie,
    profileHash,
    face.status,
    face.score,
    face.model,
    face.reason,
  ).run();

  const attendanceId = Number(insert.meta?.last_row_id || 0);
  try {
    await sendPushToUser(env, auth.user.id, {
      title: punchType === 'IN' ? 'Kehadiran Masuk Direkod' : 'Kehadiran Keluar Direkod',
      body: `${department.name} • ${punchType} berjaya direkod.`,
      kind: 'attendance_punch',
      data: { attendanceId, workDate, punchType },
    });
    if (face.status !== 'matched') {
      await sendPushToDepartment(env, auth.user.department_id, {
        title: 'Kehadiran Perlu Semakan Wajah',
        body: `${auth.user.nama} • ${punchType} memerlukan semakan wajah (${face.status}).`,
        kind: 'attendance_review',
        data: { attendanceId, workDate, punchType, faceStatus: face.status },
        roles: ['management', 'supervisor'],
        excludeUserId: auth.user.id,
      });
    }
  } catch (error) {
    console.error('Attendance push failed', error);
  }

  return json({
    record: {
      id: attendanceId,
      punchType,
      punchedAt,
      latitude,
      longitude,
      accuracyMeters: accuracy,
      distanceMeters: distance,
      faceStatus: face.status,
      faceScore: face.score,
      faceModel: face.model,
      faceReason: face.reason,
      selfieData: selfie,
    },
    nextPunchType: punchType === 'IN' ? 'OUT' : 'IN',
  }, 201);
}

async function verifyFace(env, reference, selfie) {
  if (!env.AI) {
    return {
      status: 'review_required',
      score: null,
      model: 'manual-fallback',
      reason: 'Workers AI binding tidak tersedia; selfie disimpan untuk semakan Admin.',
    };
  }
  const prompt = [
    'You are a biometric face verification assistant for attendance.',
    'Compare IMAGE 1 (registered profile) and IMAGE 2 (live attendance selfie).',
    'Return only JSON with keys samePerson (boolean), confidence (0-1), clearFace (boolean), reason (short string).',
    'Be conservative. If either image is unclear, set clearFace=false and confidence below 0.6.',
  ].join(' ');
  try {
    const result = await env.AI.run('@cf/google/gemma-4-26b-a4b-it', {
      messages: [{
        role: 'user',
        content: [
          { type: 'text', text: prompt },
          { type: 'image_url', image_url: { url: reference } },
          { type: 'image_url', image_url: { url: selfie } },
        ],
      }],
      temperature: 0,
      max_completion_tokens: 120,
    });
    const parsed = parseAiJson(result);
    if (parsed) {
      const confidence = Math.max(0, Math.min(1, Number(parsed.confidence || 0)));
      const score = Math.round(confidence * 100);
      if (parsed.clearFace === false) {
        return {
          status: 'review_required',
          score,
          model: '@cf/google/gemma-4-26b-a4b-it',
          reason: String(parsed.reason || 'Wajah tidak cukup jelas untuk pengesahan automatik.'),
        };
      }
      return {
        status: parsed.samePerson === true && confidence >= 0.65 ? 'matched' : 'different',
        score,
        model: '@cf/google/gemma-4-26b-a4b-it',
        reason: String(parsed.reason || ''),
      };
    }
  } catch (error) {
    console.error('face comparison unavailable', error);
  }

  try {
    const result = await env.AI.run('@cf/google/gemma-4-26b-a4b-it', {
      prompt: 'Check whether this attendance selfie contains one clear, front-facing human face. Reply with short JSON: {"clearFace":true|false,"reason":"..."}.',
      image: selfie,
      temperature: 0,
      max_completion_tokens: 80,
    });
    const parsed = parseAiJson(result);
    if (parsed?.clearFace === false) {
      return {
        status: 'different',
        score: 85,
        model: '@cf/google/gemma-4-26b-a4b-it',
        reason: String(parsed.reason || 'Wajah tidak jelas.'),
      };
    }
    return {
      status: 'review_required',
      score: null,
      model: '@cf/google/gemma-4-26b-a4b-it',
      reason: 'Wajah dikesan tetapi perbandingan dua imej tidak tersedia; Admin perlu semak padanan.',
    };
  } catch (error) {
    console.error('face detection unavailable', error);
    return {
      status: 'review_required',
      score: null,
      model: 'manual-fallback',
      reason: 'Pengesahan AI tidak tersedia sementara; selfie disimpan untuk semakan Admin.',
    };
  }
}

function parseAiJson(result) {
  const candidates = [
    result?.response,
    result?.result,
    result?.choices?.[0]?.message?.content,
    typeof result === 'string' ? result : null,
  ].filter(Boolean);
  for (const value of candidates) {
    if (typeof value === 'object') return value;
    const text = String(value).trim();
    const match = text.match(/\{[\s\S]*\}/);
    if (!match) continue;
    try { return JSON.parse(match[0]); } catch (_) {}
  }
  return null;
}

async function reviewAttendance(request, env, attendanceId) {
  const auth = await requireManagement(request, env);
  if (auth.response) return auth.response;
  if (!Number.isInteger(attendanceId) || attendanceId <= 0) {
    return json({ error: 'Rekod kehadiran tidak sah.' }, 400);
  }
  const existing = await env.DB.prepare(
    'SELECT id, reviewed_at FROM attendance_records WHERE id = ? LIMIT 1',
  ).bind(attendanceId).first();
  if (!existing) return json({ error: 'Rekod kehadiran tidak ditemui.' }, 404);
  if (!existing.reviewed_at) {
    await env.DB.prepare(
      'UPDATE attendance_records SET reviewed_at = ?, reviewed_by = ? WHERE id = ?',
    ).bind(new Date().toISOString(), auth.user.id, attendanceId).run();
  }
  const row = await env.DB.prepare(
    `SELECT a.*, u.nama, u.jawatan, u.profile_picture,
            COALESCE(d.name, u.jabatan) AS department_name,
            reviewer.nama AS reviewed_by_name
     FROM attendance_records a
     JOIN users u ON u.id = a.user_id
     LEFT JOIN departments d ON d.id = a.department_id
     LEFT JOIN users reviewer ON reviewer.id = a.reviewed_by
     WHERE a.id = ? LIMIT 1`,
  ).bind(attendanceId).first();
  return json({ record: adminAttendanceJson(row) });
}

async function adminAttendance(request, env, url) {
  const auth = await requireManagement(request, env);
  if (auth.response) return auth.response;
  const date = url.searchParams.get('date') || malaysiaDateKey(new Date());
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) return json({ error: 'Tarikh tidak sah.' }, 400);
  const departmentId = Number(url.searchParams.get('departmentId') || 0);

  const where = ['a.work_date = ?'];
  const binds = [date];
  if (departmentId > 0) {
    where.push('a.department_id = ?');
    binds.push(departmentId);
  }
  const result = await env.DB.prepare(
    `SELECT a.*, u.nama, u.jawatan, u.profile_picture,
            COALESCE(d.name, u.jabatan) AS department_name,
            reviewer.nama AS reviewed_by_name
     FROM attendance_records a
     JOIN users u ON u.id = a.user_id
     LEFT JOIN departments d ON d.id = a.department_id
     LEFT JOIN users reviewer ON reviewer.id = a.reviewed_by
     WHERE ${where.join(' AND ')}
     ORDER BY a.punched_at DESC, a.id DESC
     LIMIT 500`,
  ).bind(...binds).all();

  const summary = await attendanceSummary(env, date, departmentId || null);
  return json({
    date,
    summary,
    records: (result.results ?? []).map(adminAttendanceJson),
  });
}

async function commandCenterWithAttendance(request, env, ctx) {
  const downstream = await sosWorker.fetch(request, env, ctx);
  if (!downstream.ok) return downstream;
  const auth = await requireMonitor(request, env);
  if (auth.response) return auth.response;
  const payload = await downstream.json();
  const date = malaysiaDateKey(new Date());
  const scopeDepartment = String(auth.user.jawatan || '').toLowerCase() === 'management'
    ? null
    : Number(auth.user.department_id || 0) || null;
  payload.attendanceSummary = await attendanceSummary(env, date, scopeDepartment);
  const recentResult = await env.DB.prepare(
    `SELECT a.id, a.user_id, a.punch_type, a.punched_at, a.distance_m,
            a.face_status, a.face_score, u.nama,
            COALESCE(d.name, u.jabatan) AS department_name
     FROM attendance_records a
     JOIN users u ON u.id = a.user_id
     LEFT JOIN departments d ON d.id = a.department_id
     WHERE a.work_date = ? ${scopeDepartment ? 'AND a.department_id = ?' : ''}
     ORDER BY a.punched_at DESC, a.id DESC LIMIT 12`,
  ).bind(...(scopeDepartment ? [date, scopeDepartment] : [date])).all();
  payload.attendanceRecent = (recentResult.results ?? []).map((row) => ({
    id: Number(row.id),
    userId: Number(row.user_id),
    userName: row.nama,
    department: row.department_name,
    punchType: row.punch_type,
    punchedAt: row.punched_at,
    distanceMeters: Number(row.distance_m || 0),
    faceStatus: row.face_status,
    faceScore: row.face_score == null ? null : Number(row.face_score),
  }));

  const presentResult = await env.DB.prepare(
    `SELECT a.user_id, a.department_id, a.punched_at
     FROM attendance_records a
     JOIN users u ON u.id = a.user_id
     JOIN (
       SELECT user_id, MAX(punched_at) AS max_time
       FROM attendance_records
       WHERE work_date = ? ${scopeDepartment ? 'AND department_id = ?' : ''}
       GROUP BY user_id
     ) latest ON latest.user_id = a.user_id AND latest.max_time = a.punched_at
     WHERE a.work_date = ? ${scopeDepartment ? 'AND a.department_id = ?' : ''}
       AND a.punch_type = 'IN'
       AND u.active = 1
       AND LOWER(u.jawatan) IN ('patrol', 'supervisor')`,
  ).bind(...(scopeDepartment
    ? [date, scopeDepartment, date, scopeDepartment]
    : [date, date])).all();

  const presentByUser = new Map(
    (presentResult.results ?? []).map((row) => [Number(row.user_id), row]),
  );
  const rows = (payload.patrols ?? []).map((row) => ({
    ...row,
    present: presentByUser.has(Number(row.userId)),
    attendanceAt: presentByUser.get(Number(row.userId))?.punched_at ?? null,
    isSessionPatroller: false,
  }));

  // Walaupun beberapa peranti tersilap memulakan rondaan serentak, paparan Status
  // Pengawal hanya memilih seorang peronda untuk setiap Sekolah bagi sesi semasa.
  const chosenByDepartment = new Map();
  for (const row of rows) {
    if (!row.present) continue;
    if (Number(row.scannedCount || 0) <= 0 && row.patrolSessionId == null) continue;
    const departmentId = Number(row.departmentId || 0);
    if (departmentId <= 0) continue;
    const stamp = Math.max(
      Date.parse(row.lastScanAt || '') || 0,
      Date.parse(row.sessionStartedAt || '') || 0,
    );
    const existing = chosenByDepartment.get(departmentId);
    if (!existing || stamp > existing.stamp) {
      chosenByDepartment.set(departmentId, { userId: Number(row.userId), stamp });
    }
  }
  payload.patrols = rows.map((row) => ({
    ...row,
    isSessionPatroller:
      chosenByDepartment.get(Number(row.departmentId || 0))?.userId === Number(row.userId),
  }));

  return json(payload);
}

async function attendanceSummary(env, date, departmentId = null) {
  const usersSql = departmentId
    ? `SELECT COUNT(*) AS total FROM users WHERE active = 1 AND department_id = ?`
    : `SELECT COUNT(*) AS total FROM users WHERE active = 1`;
  const users = await env.DB.prepare(usersSql).bind(...(departmentId ? [departmentId] : [])).first();

  const scope = departmentId ? 'AND department_id = ?' : '';
  const bindings = departmentId ? [date, departmentId] : [date];
  const present = await env.DB.prepare(
    `SELECT COUNT(DISTINCT user_id) AS total FROM attendance_records
     WHERE work_date = ? ${scope} AND punch_type = 'IN'`,
  ).bind(...bindings).first();
  const reviews = await env.DB.prepare(
    `SELECT COUNT(*) AS total FROM attendance_records
     WHERE work_date = ? ${scope} AND face_status = 'review_required' AND reviewed_at IS NULL`,
  ).bind(...bindings).first();
  const currentlyInResult = await env.DB.prepare(
    `SELECT COUNT(*) AS total FROM (
       SELECT a.user_id, a.punch_type
       FROM attendance_records a
       JOIN (
         SELECT user_id, MAX(punched_at) AS max_time
         FROM attendance_records
         WHERE work_date = ? ${scope}
         GROUP BY user_id
       ) latest ON latest.user_id = a.user_id AND latest.max_time = a.punched_at
       WHERE a.work_date = ? ${scope} AND a.punch_type = 'IN'
     )`,
  ).bind(...(departmentId ? [date, departmentId, date, departmentId] : [date, date])).first();

  const totalUsers = Number(users?.total || 0);
  const presentUsers = Number(present?.total || 0);
  return {
    date,
    totalUsers,
    presentUsers,
    absentUsers: Math.max(0, totalUsers - presentUsers),
    currentlyIn: Number(currentlyInResult?.total || 0),
    faceReviewRequired: Number(reviews?.total || 0),
  };
}

async function adminDepartments(request, env) {
  const auth = await requireManagement(request, env);
  if (auth.response) return auth.response;
  const result = await env.DB.prepare(
    `SELECT d.id, d.name, d.session_interval_minutes, d.session_start_minutes, d.active,
            d.attendance_latitude, d.attendance_longitude, d.attendance_radius_m,
            d.attendance_location_label, d.company_name, d.zone,
            COUNT(CASE WHEN c.active = 1 THEN 1 END) AS checkpoint_count
     FROM departments d
     LEFT JOIN checkpoints c ON c.department_id = d.id
     WHERE d.active = 1
     GROUP BY d.id
     ORDER BY d.name ASC`,
  ).all();
  return json({ departments: (result.results ?? []).map(departmentJson) });
}

async function createDepartment(request, env) {
  const auth = await requireManagement(request, env);
  if (auth.response) return auth.response;
  const body = await readJson(request);
  const parsed = validateDepartmentBody(body);
  if (parsed.error) return json({ error: parsed.error }, 400);
  const duplicate = await env.DB.prepare(
    'SELECT id FROM departments WHERE LOWER(name) = LOWER(?) AND active = 1 LIMIT 1',
  ).bind(parsed.name).first();
  if (duplicate) return json({ error: 'Sekolah dengan nama ini sudah wujud.' }, 409);
  const result = await env.DB.prepare(
    `INSERT INTO departments (
       name, session_interval_minutes, session_start_minutes, active, updated_at,
       attendance_latitude, attendance_longitude, attendance_radius_m, attendance_location_label,
       company_name, zone
     ) VALUES (?, ?, ?, 1, CURRENT_TIMESTAMP, ?, ?, ?, ?, ?, ?)`,
  ).bind(
    parsed.name,
    parsed.interval,
    parsed.startMinutes,
    parsed.latitude,
    parsed.longitude,
    parsed.radius,
    parsed.locationLabel,
    parsed.companyName || null,
    parsed.zone || null,
  ).run();
  return json({ department: departmentJson(await getDepartment(env, result.meta?.last_row_id)) }, 201);
}

async function updateDepartment(request, env, departmentId) {
  const auth = await requireManagement(request, env);
  if (auth.response) return auth.response;
  const body = await readJson(request);
  const parsed = validateDepartmentBody(body);
  if (parsed.error) return json({ error: parsed.error }, 400);
  const active = body.active === false ? 0 : 1;
  const existing = await getDepartment(env, departmentId);
  if (!existing) return json({ error: 'Sekolah tidak ditemui.' }, 404);
  const duplicate = await env.DB.prepare(
    'SELECT id FROM departments WHERE LOWER(name) = LOWER(?) AND id <> ? AND active = 1 LIMIT 1',
  ).bind(parsed.name, departmentId).first();
  if (duplicate) return json({ error: 'Sekolah dengan nama ini sudah wujud.' }, 409);
  await env.DB.batch([
    env.DB.prepare(
      `UPDATE departments SET
         name = ?, session_interval_minutes = ?, session_start_minutes = ?, active = ?,
         attendance_latitude = ?, attendance_longitude = ?, attendance_radius_m = ?,
         attendance_location_label = ?, company_name = ?, zone = ?, updated_at = CURRENT_TIMESTAMP
       WHERE id = ?`,
    ).bind(
      parsed.name,
      parsed.interval,
      parsed.startMinutes,
      active,
      parsed.latitude,
      parsed.longitude,
      parsed.radius,
      parsed.locationLabel,
      parsed.companyName || null,
      parsed.zone || null,
      departmentId,
    ),
    env.DB.prepare('UPDATE users SET jabatan = ? WHERE department_id = ?').bind(parsed.name, departmentId),
  ]);
  return json({ department: departmentJson(await getDepartment(env, departmentId)) });
}

async function deleteDepartment(request, env, departmentId) {
  const auth = await requireManagement(request, env);
  if (auth.response) return auth.response;
  if (!Number.isInteger(departmentId) || departmentId <= 0) {
    return json({ error: 'Sekolah tidak sah.' }, 400);
  }
  const existing = await getDepartment(env, departmentId);
  if (!existing) return json({ error: 'Sekolah tidak ditemui.' }, 404);

  const assigned = await env.DB.prepare(
    'SELECT COUNT(*) AS total FROM users WHERE department_id = ? AND active = 1',
  ).bind(departmentId).first();
  if (Number(assigned?.total || 0) > 0) {
    return json({
      error: 'Pindahkan atau nyahaktifkan semua pengguna aktif sekolah ini sebelum memadam sekolah.',
    }, 409);
  }

  await env.DB.batch([
    env.DB.prepare(
      'UPDATE departments SET active = 0, updated_at = CURRENT_TIMESTAMP WHERE id = ?',
    ).bind(departmentId),
    env.DB.prepare(
      'UPDATE checkpoints SET active = 0, updated_at = CURRENT_TIMESTAMP WHERE department_id = ?',
    ).bind(departmentId),
  ]);
  return json({ ok: true, deleted: true });
}

function validateDepartmentBody(body) {
  const name = String(body.name ?? '').trim();
  const interval = Number(body.sessionIntervalMinutes ?? 120);
  const startMinutes = Number(body.sessionStartMinutes ?? 420);
  const latitude = Number(body.attendanceLatitude);
  const longitude = Number(body.attendanceLongitude);
  const radius = Number(body.attendanceRadiusMeters ?? DEFAULT_RADIUS_M);
  const locationLabel = String(body.attendanceLocationLabel ?? '').trim().slice(0, 160);
  const companyName = String(body.companyName ?? '').trim().slice(0, 180);
  const zone = String(body.zone ?? '').trim().slice(0, 100);
  if (name.length < 2) return { error: 'Nama Sekolah terlalu pendek.' };
  if (!Number.isInteger(interval) || interval < 15 || interval > 1440) {
    return { error: 'Tempoh sesi mesti antara 15 hingga 1440 minit.' };
  }
  if (!Number.isInteger(startMinutes) || startMinutes < 0 || startMinutes > 1439) {
    return { error: 'Jam mula sesi tidak sah.' };
  }
  if (!validCoordinate(latitude, longitude)) {
    return { error: 'Tandakan pusat kawasan sekolah pada peta.' };
  }
  if (!Number.isFinite(radius) || radius < 30 || radius > 1000) {
    return { error: 'Radius kehadiran mesti antara 30m hingga 1000m.' };
  }
  return { name, interval, startMinutes, latitude, longitude, radius: Math.round(radius), locationLabel, companyName, zone };
}

async function getDepartment(env, id) {
  if (!Number.isInteger(Number(id)) || Number(id) <= 0) return null;
  return env.DB.prepare(
    `SELECT d.id, d.name, d.session_interval_minutes, d.session_start_minutes, d.active,
            d.attendance_latitude, d.attendance_longitude, d.attendance_radius_m,
            d.attendance_location_label, d.company_name, d.zone,
            COUNT(CASE WHEN c.active = 1 THEN 1 END) AS checkpoint_count
     FROM departments d
     LEFT JOIN checkpoints c ON c.department_id = d.id
     WHERE d.id = ?
     GROUP BY d.id LIMIT 1`,
  ).bind(Number(id)).first();
}

function departmentJson(row) {
  return {
    id: Number(row.id),
    name: row.name,
    sessionIntervalMinutes: Number(row.session_interval_minutes || 120),
    sessionStartMinutes: Number(row.session_start_minutes ?? 420),
    active: Number(row.active) === 1,
    checkpointCount: Number(row.checkpoint_count || 0),
    attendanceLatitude: row.attendance_latitude == null ? null : Number(row.attendance_latitude),
    attendanceLongitude: row.attendance_longitude == null ? null : Number(row.attendance_longitude),
    attendanceRadiusMeters: Number(row.attendance_radius_m || DEFAULT_RADIUS_M),
    attendanceLocationLabel: row.attendance_location_label || '',
    companyName: row.company_name || '',
    zone: row.zone || '',
  };
}

function attendanceJson(row) {
  return {
    id: Number(row.id),
    punchType: row.punch_type,
    punchedAt: row.punched_at,
    latitude: Number(row.latitude),
    longitude: Number(row.longitude),
    accuracyMeters: row.accuracy_m == null ? null : Number(row.accuracy_m),
    distanceMeters: Number(row.distance_m || 0),
    faceStatus: row.face_status,
    faceScore: row.face_score == null ? null : Number(row.face_score),
    faceModel: row.face_model || null,
    faceReason: row.face_reason || null,
  };
}

function adminAttendanceJson(row) {
  return {
    ...attendanceJson(row),
    userId: Number(row.user_id),
    userName: row.nama,
    jobTitle: row.jawatan,
    departmentId: Number(row.department_id),
    department: row.department_name,
    profilePicture: row.profile_picture || null,
    selfieData: row.selfie_data,
    reviewedAt: row.reviewed_at || null,
    reviewedBy: row.reviewed_by == null ? null : Number(row.reviewed_by),
    reviewedByName: row.reviewed_by_name || null,
  };
}

async function requireManagement(request, env) {
  const auth = await requireUser(request, env);
  if (auth.response) return auth;
  if (String(auth.user.jawatan || '').toLowerCase() !== 'management') {
    return { response: json({ error: 'Akses Admin hanya untuk Management.' }, 403) };
  }
  return auth;
}

async function requireMonitor(request, env) {
  const auth = await requireUser(request, env);
  if (auth.response) return auth;
  const role = String(auth.user.jawatan || '').toLowerCase();
  if (role !== 'management' && role !== 'supervisor') {
    return { response: json({ error: 'Akses pemantauan tidak dibenarkan.' }, 403) };
  }
  return auth;
}

async function requireUser(request, env) {
  const token = getSessionToken(request);
  if (!token) return { response: json({ error: 'Sesi tidak sah. Sila log masuk.' }, 401) };
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
  if (!user) return { response: json({ error: 'Sesi telah tamat. Sila log masuk semula.' }, 401) };
  return { user };
}

function getSessionToken(request) {
  const authorization = request.headers.get('Authorization') ?? '';
  if (authorization.startsWith('Bearer ')) return authorization.slice(7).trim();
  const cookie = request.headers.get('Cookie') ?? '';
  for (const part of cookie.split(';')) {
    const [name, ...value] = part.trim().split('=');
    if (name === SESSION_COOKIE) {
      try { return decodeURIComponent(value.join('=')); } catch (_) { return value.join('='); }
    }
  }
  return null;
}

function validCoordinate(lat, lng) {
  return Number.isFinite(lat) && Number.isFinite(lng) && lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;
}

function haversineMeters(lat1, lon1, lat2, lon2) {
  const toRad = (value) => value * Math.PI / 180;
  const earth = 6371000;
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a = Math.sin(dLat / 2) ** 2
    + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2;
  return earth * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function malaysiaDateKey(date) {
  const local = new Date(date.getTime() + MALAYSIA_OFFSET_MS);
  const two = (v) => String(v).padStart(2, '0');
  return `${local.getUTCFullYear()}-${two(local.getUTCMonth() + 1)}-${two(local.getUTCDate())}`;
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
