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
  CommandCenterData? _data;
  Timer? _timer;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _refresh(silent: true),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final data = await widget.api.getCommandCenter();
      if (!mounted) return;
      setState(() {
        _data = data;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _locatedPatrols => (_data?.patrols ?? const [])
      .where((row) => row['latitude'] is num && row['longitude'] is num)
      .toList();

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
    if (date == null) return 'Belum dikemas kini';
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(date.hour)}:${two(date.minute)}:${two(date.second)}';
  }

  String _initial(Object? value) {
    final name = (value as String? ?? '').trim();
    return name.isEmpty ? '?' : name[0];
  }

  Future<void> _openExternalMap(Map<String, dynamic> patrol) async {
    final latitude = patrol['latitude'] as num;
    final longitude = patrol['longitude'] as num;
    final uri = Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': '$latitude,$longitude',
    });
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
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
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
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
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        patrol['nama'] as String? ?? '-',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      Text(patrol['jabatan'] as String? ?? '-'),
                      Text('Lokasi terakhir: ${_time(patrol['locationAt'])}'),
                    ],
                  ),
                ),
                IconButton.filled(
                  tooltip: 'Buka peta luar',
                  onPressed: () => _openExternalMap(patrol),
                  icon: const Icon(Icons.directions_rounded),
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
    final patrols = _locatedPatrols;
    final initialCenter = patrols.isEmpty
        ? const LatLng(4.2105, 101.9758)
        : LatLng(
            (patrols.first['latitude'] as num).toDouble(),
            (patrols.first['longitude'] as num).toDouble(),
          );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Peta Rondaan Langsung'),
        actions: [
          IconButton(
            tooltip: 'Refresh lokasi',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading && _data == null
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                FlutterMap(
                  options: MapOptions(
                    initialCenter: initialCenter,
                    initialZoom: patrols.isEmpty ? 5.5 : 15,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'dev.rimbakawal.app',
                    ),
                    MarkerLayer(
                      markers: patrols.map((patrol) {
                        final point = LatLng(
                          (patrol['latitude'] as num).toDouble(),
                          (patrol['longitude'] as num).toDouble(),
                        );
                        final image = _profileImage(patrol['profilePicture']);
                        return Marker(
                          point: point,
                          width: 74,
                          height: 86,
                          child: GestureDetector(
                            onTap: () => _showPatrol(patrol),
                            child: Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Colors.black45,
                                        blurRadius: 8,
                                      ),
                                    ],
                                  ),
                                  child: CircleAvatar(
                                    radius: 24,
                                    backgroundImage: image,
                                    child: image == null
                                        ? const Icon(Icons.directions_walk)
                                        : null,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black87,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    patrol['nama'] as String? ?? '-',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
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
                            Uri.parse(
                              'https://www.openstreetmap.org/copyright',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: Card(
                    color: Theme.of(
                      context,
                    ).colorScheme.surface.withValues(alpha: 0.92),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          const Icon(Icons.location_searching_rounded),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              patrols.isEmpty
                                  ? 'Tiada lokasi peronda aktif diterima.'
                                  : '${patrols.length} peronda pada peta • kemas kini setiap 10 saat',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_error != null)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 24,
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
