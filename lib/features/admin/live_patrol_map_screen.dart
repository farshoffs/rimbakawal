import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/api_service.dart';

class LivePatrolMapScreen extends StatefulWidget {
  const LivePatrolMapScreen({required this.api, super.key});

  final ApiService api;

  @override
  State<LivePatrolMapScreen> createState() => _LivePatrolMapScreenState();
}

class _LivePatrolMapScreenState extends State<LivePatrolMapScreen> {
  final MapController _mapController = MapController();
  LiveMapData? _data;
  Timer? _timer;
  String? _error;
  bool _loading = true;
  bool _didFit = false;
  int? _selectedUserId;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _timer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(_refresh(silent: true)),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final data = await widget.api.getLiveMap();
      if (!mounted) return;
      setState(() {
        _data = data;
        _error = null;
        _loading = false;
      });
      if (!_didFit && _locatedPatrols.isNotEmpty) {
        _didFit = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => _fitAll());
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _patrols => _data?.patrols ?? const [];

  List<Map<String, dynamic>> get _locatedPatrols => _patrols
      .where((row) => row['latitude'] is num && row['longitude'] is num)
      .toList();

  void _fitAll() {
    if (!mounted || _locatedPatrols.isEmpty) return;
    final points = _locatedPatrols
        .map(
          (row) => LatLng(
            (row['latitude'] as num).toDouble(),
            (row['longitude'] as num).toDouble(),
          ),
        )
        .toList();
    if (points.length == 1) {
      _mapController.move(points.first, 16);
      return;
    }
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(points),
        padding: const EdgeInsets.fromLTRB(48, 130, 48, 220),
        maxZoom: 17,
      ),
    );
  }

  void _focus(Map<String, dynamic> patrol) {
    setState(() => _selectedUserId = (patrol['userId'] as num).toInt());
    if (patrol['latitude'] is! num || patrol['longitude'] is! num) {
      _showPatrol(patrol);
      return;
    }
    _mapController.move(
      LatLng(
        (patrol['latitude'] as num).toDouble(),
        (patrol['longitude'] as num).toDouble(),
      ),
      17,
    );
  }

  ImageProvider<Object>? _profileImage(Object? value) {
    final source = value as String?;
    if (source == null || source.isEmpty) return null;
    if (source.startsWith('data:image') && source.contains(',')) {
      try {
        return MemoryImage(base64Decode(source.split(',').last));
      } catch (_) {
        return null;
      }
    }
    final uri = Uri.tryParse(source);
    return uri != null && uri.hasScheme ? NetworkImage(source) : null;
  }

  String _time(Object? value) {
    final date = DateTime.tryParse(value as String? ?? '')?.toLocal();
    if (date == null) return 'Belum ada GPS fix';
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(date.hour)}:${two(date.minute)}:${two(date.second)}';
  }

  String _duration(Object? value) {
    final start = DateTime.tryParse(value as String? ?? '')?.toLocal();
    if (start == null) return '-';
    final diff = DateTime.now().difference(start);
    if (diff.inHours > 0) return '${diff.inHours}j ${diff.inMinutes % 60}m';
    return '${diff.inMinutes}m';
  }

  String _initial(Object? value) {
    final name = (value as String? ?? '').trim();
    return name.isEmpty ? '?' : name[0];
  }

  Color _stateColor(String state) => switch (state) {
        'live' => const Color(0xFF00B894),
        'delayed' => const Color(0xFFFDCB6E),
        'stale' => const Color(0xFFE17055),
        _ => const Color(0xFF74B9FF),
      };

  String _stateLabel(String state) => switch (state) {
        'live' => 'LIVE',
        'delayed' => 'DELAYED',
        'stale' => 'STALE',
        _ => 'MENUNGGU LOKASI',
      };

  List<LatLng> _trail(Map<String, dynamic> patrol) {
    final rows = patrol['trail'] as List<dynamic>? ?? const [];
    return rows.whereType<Map>().map((row) {
      final map = Map<String, dynamic>.from(row);
      return LatLng(
        (map['latitude'] as num).toDouble(),
        (map['longitude'] as num).toDouble(),
      );
    }).toList();
  }

  Future<void> _openExternalMap(Map<String, dynamic> patrol) async {
    if (patrol['latitude'] is! num || patrol['longitude'] is! num) return;
    final latitude = patrol['latitude'] as num;
    final longitude = patrol['longitude'] as num;
    final uri = Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': '$latitude,$longitude',
    });
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Peta luar tidak dapat dibuka.')),
      );
    }
  }

  void _showPatrol(Map<String, dynamic> patrol) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final image = _profileImage(patrol['profilePicture']);
        final state = patrol['liveState'] as String? ?? 'waiting_gps';
        final color = _stateColor(state);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundImage: image,
                      child: image == null
                          ? Text(
                              _initial(patrol['nama']),
                              style: const TextStyle(fontWeight: FontWeight.w900),
                            )
                          : null,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            patrol['nama'] as String? ?? '-',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                          Text(patrol['jabatan'] as String? ?? '-'),
                        ],
                      ),
                    ),
                    _LiveBadge(label: _stateLabel(state), color: color),
                  ],
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _InfoChip(
                      icon: Icons.schedule_rounded,
                      text: 'Ronda ${_duration(patrol['startedAt'])}',
                    ),
                    _InfoChip(
                      icon: Icons.my_location_rounded,
                      text: 'GPS ${_time(patrol['locationAt'])}',
                    ),
                    if (patrol['accuracy'] is num)
                      _InfoChip(
                        icon: Icons.gps_fixed_rounded,
                        text: '±${(patrol['accuracy'] as num).round()} m',
                      ),
                    _InfoChip(
                      icon: Icons.route_rounded,
                      text: '${_trail(patrol).length} titik trail',
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                if (patrol['latitude'] is num)
                  FilledButton.icon(
                    onPressed: () => _openExternalMap(patrol),
                    icon: const Icon(Icons.directions_rounded),
                    label: const Text('BUKA LOKASI'),
                  )
                else
                  const Text(
                    'Rondaan telah bermula tetapi telefon belum menghantar koordinat GPS. Semak permission lokasi pada telefon guard.',
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final patrols = _patrols;
    final located = _locatedPatrols;
    final initialCenter = located.isEmpty
        ? const LatLng(4.2105, 101.9758)
        : LatLng(
            (located.first['latitude'] as num).toDouble(),
            (located.first['longitude'] as num).toDouble(),
          );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Patrol Map'),
        actions: [
          IconButton(
            tooltip: 'Fit semua guard',
            onPressed: located.isEmpty ? null : _fitAll,
            icon: const Icon(Icons.center_focus_strong_rounded),
          ),
          IconButton(
            tooltip: 'Muat semula',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading && _data == null
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                Positioned.fill(
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: initialCenter,
                      initialZoom: located.isEmpty ? 5.4 : 15.5,
                      minZoom: 3,
                      maxZoom: 19,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'dev.rimbakawal.app',
                      ),
                      PolylineLayer(
                        polylines: patrols.expand((patrol) {
                          final points = _trail(patrol);
                          if (points.length < 2) return <Polyline>[];
                          final state = patrol['liveState'] as String? ?? 'waiting_gps';
                          return [
                            Polyline(
                              points: points,
                              strokeWidth: 5,
                              color: _stateColor(state).withValues(alpha: 0.76),
                            ),
                          ];
                        }).toList(),
                      ),
                      MarkerLayer(
                        markers: located.map((patrol) {
                          final point = LatLng(
                            (patrol['latitude'] as num).toDouble(),
                            (patrol['longitude'] as num).toDouble(),
                          );
                          final image = _profileImage(patrol['profilePicture']);
                          final state = patrol['liveState'] as String? ?? 'waiting_gps';
                          final color = _stateColor(state);
                          final selected = _selectedUserId == patrol['userId'];
                          return Marker(
                            point: point,
                            width: selected ? 94 : 82,
                            height: selected ? 104 : 94,
                            child: GestureDetector(
                              onTap: () {
                                _focus(patrol);
                                _showPatrol(patrol);
                              },
                              child: Column(
                                children: [
                                  Container(
                                    padding: EdgeInsets.all(selected ? 5 : 3),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: color,
                                      boxShadow: [
                                        BoxShadow(
                                          color: color.withValues(alpha: 0.35),
                                          blurRadius: selected ? 22 : 12,
                                        ),
                                      ],
                                    ),
                                    child: CircleAvatar(
                                      radius: selected ? 27 : 24,
                                      backgroundImage: image,
                                      child: image == null
                                          ? const Icon(Icons.directions_walk_rounded)
                                          : null,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Container(
                                    constraints: const BoxConstraints(maxWidth: 92),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xEE11131B),
                                      borderRadius: BorderRadius.circular(9),
                                    ),
                                    child: Text(
                                      patrol['nama'] as String? ?? '-',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      RichAttributionWidget(
                        attributions: [
                          TextSourceAttribution(
                            'OpenStreetMap contributors',
                            onTap: () => launchUrl(
                              Uri.parse('https://www.openstreetmap.org/copyright'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: _MapHeader(
                    total: patrols.length,
                    located: located.length,
                    generatedAt: _data?.generatedAt,
                  ),
                ),
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 12,
                  child: SizedBox(
                    height: 142,
                    child: patrols.isEmpty
                        ? const _NoPatrolCard()
                        : ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: patrols.length,
                            separatorBuilder: (_, _) => const SizedBox(width: 8),
                            itemBuilder: (context, index) {
                              final patrol = patrols[index];
                              return _PatrolMiniCard(
                                patrol: patrol,
                                selected: _selectedUserId == patrol['userId'],
                                image: _profileImage(patrol['profilePicture']),
                                stateColor: _stateColor(
                                  patrol['liveState'] as String? ?? 'waiting_gps',
                                ),
                                stateLabel: _stateLabel(
                                  patrol['liveState'] as String? ?? 'waiting_gps',
                                ),
                                onTap: () => _focus(patrol),
                              );
                            },
                          ),
                  ),
                ),
                if (_error != null)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 164,
                    child: Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(_error!),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _MapHeader extends StatelessWidget {
  const _MapHeader({
    required this.total,
    required this.located,
    required this.generatedAt,
  });
  final int total;
  final int located;
  final DateTime? generatedAt;

  @override
  Widget build(BuildContext context) => Card(
        color: const Color(0xF0141620),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: const Color(0xFF00B894).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.radar_rounded,
                  color: Color(0xFF55E6C1),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$total rondaan aktif • $located ada GPS',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    Text(
                      'Refresh 5s${generatedAt == null ? '' : ' • ${_headerTime(generatedAt!)}'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  static String _headerTime(DateTime value) {
    final local = value.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }
}

class _PatrolMiniCard extends StatelessWidget {
  const _PatrolMiniCard({
    required this.patrol,
    required this.selected,
    required this.image,
    required this.stateColor,
    required this.stateLabel,
    required this.onTap,
  });
  final Map<String, dynamic> patrol;
  final bool selected;
  final ImageProvider<Object>? image;
  final Color stateColor;
  final String stateLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 230,
        child: Card(
          color: selected ? const Color(0xFF252A3B) : const Color(0xF0141620),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 21,
                        backgroundImage: image,
                        child: image == null
                            ? const Icon(Icons.person_rounded, size: 20)
                            : null,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          patrol['nama'] as String? ?? '-',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  _LiveBadge(label: stateLabel, color: stateColor),
                  const SizedBox(height: 5),
                  Text(
                    patrol['latitude'] is num
                        ? 'GPS ${patrol['locationAgeSeconds'] ?? 0}s ago'
                        : 'Sesi aktif • menunggu GPS',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w900,
          ),
        ),
      );
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15),
            const SizedBox(width: 5),
            Text(text),
          ],
        ),
      );
}

class _NoPatrolCard extends StatelessWidget {
  const _NoPatrolCard();

  @override
  Widget build(BuildContext context) => const Card(
        color: Color(0xF0141620),
        child: Center(
          child: Text(
            'Tiada rondaan aktif sekarang.',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      );
}
