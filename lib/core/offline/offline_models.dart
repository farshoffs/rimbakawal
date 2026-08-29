import '../api/app_user.dart';

class CachedCheckpoint {
  const CachedCheckpoint({
    required this.id,
    required this.name,
    required this.nfcUid,
    required this.position,
    this.instruction,
  });

  final int id;
  final String name;
  final String nfcUid;
  final int position;
  final String? instruction;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'nfcUid': nfcUid,
        'position': position,
        'instruction': instruction,
      };

  factory CachedCheckpoint.fromJson(Map<String, dynamic> json) =>
      CachedCheckpoint(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String,
        nfcUid: json['nfcUid'] as String,
        position: (json['position'] as num).toInt(),
        instruction: json['instruction'] as String?,
      );
}

class OfflineBootstrap {
  const OfflineBootstrap({
    required this.generatedAt,
    required this.user,
    required this.departmentId,
    required this.departmentName,
    required this.sessionIntervalMinutes,
    this.sessionStartMinutes = 420,
    required this.routeOrderEnforced,
    required this.checkpoints,
  });

  final DateTime generatedAt;
  final AppUser user;
  final int departmentId;
  final String departmentName;
  final int sessionIntervalMinutes;
  final int sessionStartMinutes;
  final bool routeOrderEnforced;
  final List<CachedCheckpoint> checkpoints;

  Map<String, dynamic> toJson() => {
        'generatedAt': generatedAt.toUtc().toIso8601String(),
        'user': {
          'id': user.id,
          'nama': user.nama,
          'noKadPengenalan': user.noKadPengenalan,
          'jawatan': user.jawatan,
          'jabatan': user.jabatan,
          'profilePicture': user.profilePicture,
          'departmentId': user.departmentId,
          'sessionIntervalMinutes': user.sessionIntervalMinutes,
          'active': user.active,
        },
        'department': {
          'id': departmentId,
          'name': departmentName,
          'sessionIntervalMinutes': sessionIntervalMinutes,
          'sessionStartMinutes': sessionStartMinutes,
          'routeOrderEnforced': routeOrderEnforced,
        },
        'checkpoints': checkpoints.map((item) => item.toJson()).toList(),
      };

  factory OfflineBootstrap.fromJson(Map<String, dynamic> json) {
    final department = Map<String, dynamic>.from(json['department'] as Map);
    final rows = json['checkpoints'] as List<dynamic>? ?? const [];
    return OfflineBootstrap(
      generatedAt: DateTime.tryParse(json['generatedAt'] as String? ?? '') ??
          DateTime.now().toUtc(),
      user: AppUser.fromJson(Map<String, dynamic>.from(json['user'] as Map)),
      departmentId: (department['id'] as num).toInt(),
      departmentName: department['name'] as String,
      sessionIntervalMinutes:
          (department['sessionIntervalMinutes'] as num?)?.toInt() ?? 120,
      sessionStartMinutes:
          (department['sessionStartMinutes'] as num?)?.toInt() ?? 420,
      routeOrderEnforced:
          department['routeOrderEnforced'] as bool? ?? true,
      checkpoints: rows
          .map((item) =>
              CachedCheckpoint.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList(),
    );
  }
}

class OfflineEvent {
  const OfflineEvent({
    required this.id,
    required this.userId,
    required this.type,
    required this.occurredAt,
    required this.payload,
    required this.status,
    required this.attempts,
    this.location,
    this.lastError,
    this.syncedAt,
  });

  final String id;
  final int userId;
  final String type;
  final DateTime occurredAt;
  final Map<String, dynamic> payload;
  final Map<String, dynamic>? location;
  final String status;
  final int attempts;
  final String? lastError;
  final DateTime? syncedAt;

  bool get isPending => status == 'pending';
  bool get isFailed => status == 'failed';
  bool get isSynced => status == 'synced';

  OfflineEvent copyWith({
    String? status,
    int? attempts,
    String? lastError,
    bool clearError = false,
    DateTime? syncedAt,
  }) =>
      OfflineEvent(
        id: id,
        userId: userId,
        type: type,
        occurredAt: occurredAt,
        payload: payload,
        location: location,
        status: status ?? this.status,
        attempts: attempts ?? this.attempts,
        lastError: clearError ? null : (lastError ?? this.lastError),
        syncedAt: syncedAt ?? this.syncedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'type': type,
        'occurredAt': occurredAt.toUtc().toIso8601String(),
        'payload': payload,
        'location': location,
        'status': status,
        'attempts': attempts,
        'lastError': lastError,
        'syncedAt': syncedAt?.toUtc().toIso8601String(),
      };

  Map<String, dynamic> toSyncJson() => {
        'id': id,
        'type': type,
        'occurredAt': occurredAt.toUtc().toIso8601String(),
        'payload': payload,
        'location': location,
      };

  factory OfflineEvent.fromJson(Map<String, dynamic> json) => OfflineEvent(
        id: json['id'] as String,
        userId: (json['userId'] as num).toInt(),
        type: json['type'] as String,
        occurredAt: DateTime.parse(json['occurredAt'] as String),
        payload: Map<String, dynamic>.from(json['payload'] as Map? ?? const {}),
        location: json['location'] is Map
            ? Map<String, dynamic>.from(json['location'] as Map)
            : null,
        status: json['status'] as String? ?? 'pending',
        attempts: (json['attempts'] as num?)?.toInt() ?? 0,
        lastError: json['lastError'] as String?,
        syncedAt: DateTime.tryParse(json['syncedAt'] as String? ?? ''),
      );
}
