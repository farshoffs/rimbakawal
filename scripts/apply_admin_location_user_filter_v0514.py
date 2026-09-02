from pathlib import Path


def read(path: str) -> str:
    return Path(path).read_text(encoding='utf-8')


def write(path: str, text: str) -> None:
    Path(path).write_text(text, encoding='utf-8')


def once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly one match, found {count}')
    return text.replace(old, new, 1)


# Version bump.
pubspec = read('pubspec.yaml')
pubspec = once(pubspec, 'version: 0.5.13+29', 'version: 0.5.14+30', 'version bump')
write('pubspec.yaml', pubspec)

# ---------------------------------------------------------------------------
# Department / checkpoint maintenance
# ---------------------------------------------------------------------------
path = 'lib/features/admin/department_maintenance_screen.dart'
t = read(path)

t = once(
    t,
    "import 'package:flutter/material.dart';\nimport 'package:flutter_map/flutter_map.dart';\nimport 'package:latlong2/latlong.dart';\n",
    "import 'dart:async';\nimport 'dart:convert';\n\nimport 'package:flutter/foundation.dart';\nimport 'package:flutter/material.dart';\nimport 'package:flutter_map/flutter_map.dart';\nimport 'package:geolocator/geolocator.dart';\nimport 'package:http/http.dart' as http;\nimport 'package:latlong2/latlong.dart';\n",
    'department imports',
)

t = once(
    t,
    "  late final TextEditingController _companyController;\n  late final TextEditingController _zoneController;\n  late TimeOfDay _startTime;\n",
    "  late final TextEditingController _companyController;\n  late final TextEditingController _zoneController;\n  late final TextEditingController _locationSearchController;\n  final MapController _mapController = MapController();\n  late TimeOfDay _startTime;\n",
    'department controllers',
)

t = once(
    t,
    "  double _radius = 150;\n  bool _saving = false;\n  String? _error;\n",
    "  double _radius = 150;\n  double? _deviceLatitude;\n  double? _deviceLongitude;\n  bool _saving = false;\n  bool _locating = false;\n  bool _searchingLocation = false;\n  List<_LocationSearchResult> _locationResults = const [];\n  String? _error;\n",
    'department location state',
)

t = once(
    t,
    "    _zoneController = TextEditingController(\n      text: widget.department?.zone ?? '',\n    );\n    final startMinutes = widget.department?.sessionStartMinutes ?? 420;\n",
    "    _zoneController = TextEditingController(\n      text: widget.department?.zone ?? '',\n    );\n    _locationSearchController = TextEditingController();\n    final startMinutes = widget.department?.sessionStartMinutes ?? 420;\n",
    'department search controller init',
)

t = once(
    t,
    "    _latitude = widget.department?.attendanceLatitude;\n    _longitude = widget.department?.attendanceLongitude;\n    _radius = (widget.department?.attendanceRadiusMeters ?? 150).toDouble();\n  }\n",
    "    _latitude = widget.department?.attendanceLatitude;\n    _longitude = widget.department?.attendanceLongitude;\n    _radius = (widget.department?.attendanceRadiusMeters ?? 150).toDouble();\n    WidgetsBinding.instance.addPostFrameCallback((_) {\n      if (!mounted) return;\n      unawaited(\n        _detectCurrentLocation(\n          auto: true,\n          applyToDepartment:\n              widget.department == null && (_latitude == null || _longitude == null),\n        ),\n      );\n    });\n  }\n",
    'department auto location init',
)

t = once(
    t,
    "    _locationLabelController.dispose();\n    _companyController.dispose();\n    _zoneController.dispose();\n    super.dispose();\n",
    "    _locationLabelController.dispose();\n    _companyController.dispose();\n    _zoneController.dispose();\n    _locationSearchController.dispose();\n    _mapController.dispose();\n    super.dispose();\n",
    'department dispose',
)

t = once(
    t,
    "  Future<void> _pickStartTime() async {\n    final selected = await showTimePicker(\n      context: context,\n      initialTime: _startTime,\n      helpText: 'Jam mula sesi rondaan',\n    );\n    if (selected != null && mounted) setState(() => _startTime = selected);\n  }\n\n  Future<void> _save() async {\n",
    "  Future<void> _pickStartTime() async {\n    final selected = await showTimePicker(\n      context: context,\n      initialTime: _startTime,\n      helpText: 'Pilih masa mula sesi rondaan',\n    );\n    if (selected != null && mounted) setState(() => _startTime = selected);\n  }\n\n  void _moveMap(double latitude, double longitude, {double zoom = 17}) {\n    try {\n      _mapController.move(LatLng(latitude, longitude), zoom);\n    } catch (_) {\n      // Map may still be attaching during the dialog's first frame.\n    }\n  }\n\n  Future<void> _detectCurrentLocation({\n    required bool auto,\n    required bool applyToDepartment,\n  }) async {\n    if (_locating) return;\n    if (mounted) {\n      setState(() {\n        _locating = true;\n        if (!auto) _error = null;\n      });\n    }\n    try {\n      if (!await Geolocator.isLocationServiceEnabled()) {\n        if (!auto && mounted) {\n          setState(() => _error = 'Aktifkan Location/GPS untuk mengesan lokasi semasa.');\n        }\n        return;\n      }\n      var permission = await Geolocator.checkPermission();\n      if (permission == LocationPermission.denied) {\n        permission = await Geolocator.requestPermission();\n      }\n      if (permission == LocationPermission.denied ||\n          permission == LocationPermission.deniedForever) {\n        if (!auto && mounted) {\n          setState(() => _error = 'Kebenaran lokasi diperlukan untuk menggunakan lokasi semasa.');\n        }\n        return;\n      }\n      final position = await Geolocator.getCurrentPosition(\n        locationSettings: const LocationSettings(\n          accuracy: LocationAccuracy.high,\n          timeLimit: Duration(seconds: 15),\n        ),\n      );\n      if (!mounted) return;\n      setState(() {\n        _deviceLatitude = position.latitude;\n        _deviceLongitude = position.longitude;\n        if (applyToDepartment) {\n          _latitude = position.latitude;\n          _longitude = position.longitude;\n        }\n        _error = null;\n      });\n      _moveMap(position.latitude, position.longitude);\n    } catch (error) {\n      if (!auto && mounted) {\n        setState(() => _error = 'Lokasi semasa tidak dapat dikesan: $error');\n      }\n    } finally {\n      if (mounted) setState(() => _locating = false);\n    }\n  }\n\n  Future<void> _searchLocation() async {\n    final query = _locationSearchController.text.trim();\n    if (query.length < 3 || _searchingLocation) {\n      if (query.length < 3) {\n        setState(() => _error = 'Masukkan sekurang-kurangnya 3 aksara untuk Cari Lokasi.');\n      }\n      return;\n    }\n    setState(() {\n      _searchingLocation = true;\n      _locationResults = const [];\n      _error = null;\n    });\n    try {\n      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {\n        'q': '$query, Malaysia',\n        'format': 'jsonv2',\n        'limit': '5',\n        'addressdetails': '1',\n      });\n      final response = await http.get(\n        uri,\n        headers: kIsWeb\n            ? const {'Accept-Language': 'ms,en;q=0.8'}\n            : const {\n                'User-Agent': 'RimbaKawal/0.5.14 (location search)',\n                'Accept-Language': 'ms,en;q=0.8',\n              },\n      );\n      if (response.statusCode != 200) {\n        throw StateError('Carian lokasi gagal (${response.statusCode}).');\n      }\n      final decoded = jsonDecode(response.body);\n      if (decoded is! List) throw StateError('Format carian lokasi tidak sah.');\n      final results = decoded\n          .whereType<Map<String, dynamic>>()\n          .map(_LocationSearchResult.fromJson)\n          .where((item) => item != null)\n          .cast<_LocationSearchResult>()\n          .toList();\n      if (!mounted) return;\n      setState(() {\n        _locationResults = results;\n        if (results.isEmpty) {\n          _error = 'Tiada lokasi ditemui. Cuba nama sekolah, jalan, bandar atau poskod.';\n        }\n      });\n    } catch (error) {\n      if (!mounted) return;\n      setState(() => _error = 'Cari Lokasi tidak berjaya: $error');\n    } finally {\n      if (mounted) setState(() => _searchingLocation = false);\n    }\n  }\n\n  void _selectLocationResult(_LocationSearchResult result) {\n    setState(() {\n      _latitude = result.latitude;\n      _longitude = result.longitude;\n      _locationResults = const [];\n      _locationLabelController.text = result.displayName;\n      _error = null;\n    });\n    _moveMap(result.latitude, result.longitude);\n  }\n\n  Future<void> _save() async {\n",
    'department location helpers',
)

# Improve time wording/control. This also prevents the confusing repeated "Jam" wording.
t = once(t, "                        'Jam mula rondaan',", "                        'Masa mula rondaan',", 'time wording')
t = once(
    t,
    "                    label: Text(_startTime.format(context)),",
    "                    label: Text('Pilih masa • ${_startTime.format(context)}'),",
    'time button label',
)

# Insert location controls between explanation and map.
t = once(
    t,
    "              const Text(\n                'Tekan pada peta untuk menetapkan pusat sekolah. Bulatan menunjukkan radius yang dibenarkan untuk punch masuk/keluar.',\n              ),\n              const SizedBox(height: 10),\n              ClipRRect(\n",
    "              const Text(\n                'Lokasi semasa akan cuba dikesan secara automatik. Anda juga boleh guna lokasi semasa secara manual, cari lokasi lain, atau tekan terus pada peta. Bulatan menunjukkan radius yang dibenarkan untuk punch masuk/keluar.',\n              ),\n              const SizedBox(height: 10),\n              TextField(\n                controller: _locationSearchController,\n                textInputAction: TextInputAction.search,\n                onSubmitted: (_) => _searchLocation(),\n                decoration: const InputDecoration(\n                  labelText: 'Cari Lokasi',\n                  hintText: 'Nama sekolah, tempat, jalan, bandar atau poskod',\n                  prefixIcon: Icon(Icons.search_rounded),\n                ),\n              ),\n              const SizedBox(height: 8),\n              LayoutBuilder(\n                builder: (context, constraints) {\n                  final currentButton = FilledButton.tonalIcon(\n                    onPressed: _locating\n                        ? null\n                        : () => _detectCurrentLocation(\n                            auto: false,\n                            applyToDepartment: true,\n                          ),\n                    icon: _locating\n                        ? const SizedBox(\n                            width: 18,\n                            height: 18,\n                            child: CircularProgressIndicator(strokeWidth: 2),\n                          )\n                        : const Icon(Icons.my_location_rounded),\n                    label: Text(_locating ? 'MENGESAN…' : 'GUNA LOKASI SEMASA'),\n                  );\n                  final searchButton = OutlinedButton.icon(\n                    onPressed: _searchingLocation ? null : _searchLocation,\n                    icon: _searchingLocation\n                        ? const SizedBox(\n                            width: 18,\n                            height: 18,\n                            child: CircularProgressIndicator(strokeWidth: 2),\n                          )\n                        : const Icon(Icons.travel_explore_rounded),\n                    label: Text(\n                      _searchingLocation ? 'MENCARI…' : 'CARI LOKASI',\n                    ),\n                  );\n                  if (constraints.maxWidth < 470) {\n                    return Column(\n                      crossAxisAlignment: CrossAxisAlignment.stretch,\n                      children: [\n                        currentButton,\n                        const SizedBox(height: 8),\n                        searchButton,\n                      ],\n                    );\n                  }\n                  return Row(\n                    children: [\n                      Expanded(child: currentButton),\n                      const SizedBox(width: 8),\n                      Expanded(child: searchButton),\n                    ],\n                  );\n                },\n              ),\n              if (_deviceLatitude != null && _deviceLongitude != null) ...[\n                const SizedBox(height: 8),\n                Text(\n                  'Lokasi semasa dikesan: ${_deviceLatitude!.toStringAsFixed(5)}, ${_deviceLongitude!.toStringAsFixed(5)}',\n                  style: const TextStyle(fontSize: 12),\n                ),\n              ],\n              if (_locationResults.isNotEmpty) ...[\n                const SizedBox(height: 8),\n                Card(\n                  child: Column(\n                    children: _locationResults\n                        .map(\n                          (result) => ListTile(\n                            dense: true,\n                            leading: const Icon(Icons.location_on_outlined),\n                            title: Text(\n                              result.displayName,\n                              maxLines: 2,\n                              overflow: TextOverflow.ellipsis,\n                            ),\n                            onTap: () => _selectLocationResult(result),\n                          ),\n                        )\n                        .toList(),\n                  ),\n                ),\n              ],\n              const SizedBox(height: 10),\n              ClipRRect(\n",
    'department location controls UI',
)

# Attach controller, improve manual map placement, and show current device position.
t = once(
    t,
    "                  child: FlutterMap(\n                    options: MapOptions(\n",
    "                  child: FlutterMap(\n                    mapController: _mapController,\n                    options: MapOptions(\n",
    'map controller',
)
t = once(
    t,
    "                      onTap: (_, point) => setState(() {\n                        _latitude = point.latitude;\n                        _longitude = point.longitude;\n                      }),\n",
    "                      onTap: (_, point) => setState(() {\n                        _latitude = point.latitude;\n                        _longitude = point.longitude;\n                        _locationResults = const [];\n                      }),\n",
    'manual map selection',
)
t = once(
    t,
    "                      if (_latitude != null && _longitude != null)\n                        MarkerLayer(\n                          markers: [\n                            Marker(\n                              point: LatLng(_latitude!, _longitude!),\n                              width: 48,\n                              height: 48,\n                              child: const Icon(Icons.school_rounded, size: 38),\n                            ),\n                          ],\n                        ),\n",
    "                      if (_latitude != null && _longitude != null)\n                        MarkerLayer(\n                          markers: [\n                            Marker(\n                              point: LatLng(_latitude!, _longitude!),\n                              width: 48,\n                              height: 48,\n                              child: const Icon(Icons.school_rounded, size: 38),\n                            ),\n                            if (_deviceLatitude != null &&\n                                _deviceLongitude != null)\n                              Marker(\n                                point: LatLng(\n                                  _deviceLatitude!,\n                                  _deviceLongitude!,\n                                ),\n                                width: 42,\n                                height: 42,\n                                child: const Icon(\n                                  Icons.my_location_rounded,\n                                  size: 30,\n                                  color: Color(0xFF54A0FF),\n                                ),\n                              ),\n                          ],\n                        ),\n",
    'device location marker',
)

# Add a small data class before the checkpoint dialog.
t = once(
    t,
    "class _CheckpointDialog extends StatefulWidget {\n",
    "class _LocationSearchResult {\n  const _LocationSearchResult({\n    required this.displayName,\n    required this.latitude,\n    required this.longitude,\n  });\n\n  final String displayName;\n  final double latitude;\n  final double longitude;\n\n  static _LocationSearchResult? fromJson(Map<String, dynamic> json) {\n    final displayName = json['display_name']?.toString().trim() ?? '';\n    final latitude = double.tryParse(json['lat']?.toString() ?? '');\n    final longitude = double.tryParse(json['lon']?.toString() ?? '');\n    if (displayName.isEmpty || latitude == null || longitude == null) {\n      return null;\n    }\n    return _LocationSearchResult(\n      displayName: displayName,\n      latitude: latitude,\n      longitude: longitude,\n    );\n  }\n}\n\nclass _CheckpointDialog extends StatefulWidget {\n",
    'location result class',
)

write(path, t)

# ---------------------------------------------------------------------------
# Patrol end confirmation: make Teruskan Rondaan a real secondary button.
# ---------------------------------------------------------------------------
path = 'lib/features/patrol/patrol_screen.dart'
t = read(path)
t = once(
    t,
    "        actions: [\n          TextButton(\n            onPressed: () => Navigator.pop(context, false),\n            child: const Text('Teruskan ronda'),\n          ),\n          FilledButton(\n            onPressed: () => Navigator.pop(context, true),\n            child: const Text('Tamat Rondaan'),\n          ),\n        ],\n",
    "        actions: [\n          SizedBox(\n            width: double.infinity,\n            child: Column(\n              crossAxisAlignment: CrossAxisAlignment.stretch,\n              mainAxisSize: MainAxisSize.min,\n              children: [\n                FilledButton.icon(\n                  onPressed: () => Navigator.pop(context, true),\n                  icon: const Icon(Icons.stop_circle_outlined),\n                  label: const Text('Tamat Rondaan'),\n                ),\n                const SizedBox(height: 8),\n                OutlinedButton.icon(\n                  onPressed: () => Navigator.pop(context, false),\n                  icon: const Icon(Icons.directions_walk_rounded),\n                  label: const Text('Teruskan Rondaan'),\n                ),\n              ],\n            ),\n          ),\n        ],\n",
    'patrol end actions',
)
write(path, t)

# ---------------------------------------------------------------------------
# User list department filter.
# ---------------------------------------------------------------------------
path = 'lib/features/admin/user_maintenance_screen.dart'
t = read(path)
t = once(
    t,
    "class _UserMaintenanceScreenState extends State<UserMaintenanceScreen> {\n  late Future<_UserAdminData> _future;\n",
    "class _UserMaintenanceScreenState extends State<UserMaintenanceScreen> {\n  late Future<_UserAdminData> _future;\n  int _departmentFilterId = -1;\n",
    'user filter state',
)

t = once(
    t,
    "          final data = snapshot.data!;\n          return ListView.separated(\n            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),\n            itemCount: data.users.length,\n            separatorBuilder: (_, _) => const SizedBox(height: 8),\n            itemBuilder: (context, index) {\n              final user = data.users[index];\n              return Card(\n                child: ListTile(\n                  onTap: () => _editUser(user, data.departments),\n                  leading: CircleAvatar(\n                    backgroundImage: _imageProvider(user.profilePicture),\n                    child: _imageProvider(user.profilePicture) == null\n                        ? Text(user.nama.isEmpty ? '?' : user.nama[0])\n                        : null,\n                  ),\n                  title: Text(\n                    user.nama,\n                    style: const TextStyle(fontWeight: FontWeight.w800),\n                  ),\n                  subtitle: Text(\n                    '${user.noKadPengenalan}${user.noPk.isEmpty ? '' : ' • No. PK ${user.noPk}'}\\n${user.jawatanPaparan} • ${user.jabatan}',\n                  ),\n                  isThreeLine: true,\n                  trailing: const Icon(Icons.edit_rounded),\n                ),\n              );\n            },\n          );\n",
    "          final data = snapshot.data!;\n          final filteredUsers = _departmentFilterId == -1\n              ? data.users\n              : data.users\n                    .where((user) => user.departmentId == _departmentFilterId)\n                    .toList();\n          return Column(\n            children: [\n              Padding(\n                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),\n                child: DropdownButtonFormField<int>(\n                  initialValue: _departmentFilterId,\n                  decoration: const InputDecoration(\n                    labelText: 'Filter Jabatan',\n                    prefixIcon: Icon(Icons.filter_alt_rounded),\n                  ),\n                  items: [\n                    const DropdownMenuItem<int>(\n                      value: -1,\n                      child: Text('Semua Jabatan'),\n                    ),\n                    ...data.departments.map(\n                      (department) => DropdownMenuItem<int>(\n                        value: department.id,\n                        child: Text(department.name),\n                      ),\n                    ),\n                  ],\n                  onChanged: (value) => setState(\n                    () => _departmentFilterId = value ?? -1,\n                  ),\n                ),\n              ),\n              Padding(\n                padding: const EdgeInsets.symmetric(horizontal: 18),\n                child: Align(\n                  alignment: Alignment.centerLeft,\n                  child: Text(\n                    '${filteredUsers.length} pengguna',\n                    style: Theme.of(context).textTheme.bodySmall,\n                  ),\n                ),\n              ),\n              const SizedBox(height: 4),\n              Expanded(\n                child: filteredUsers.isEmpty\n                    ? const Center(\n                        child: Text('Tiada pengguna untuk Jabatan ini.'),\n                      )\n                    : ListView.separated(\n                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),\n                        itemCount: filteredUsers.length,\n                        separatorBuilder: (_, _) =>\n                            const SizedBox(height: 8),\n                        itemBuilder: (context, index) {\n                          final user = filteredUsers[index];\n                          return Card(\n                            child: ListTile(\n                              onTap: () =>\n                                  _editUser(user, data.departments),\n                              leading: CircleAvatar(\n                                backgroundImage:\n                                    _imageProvider(user.profilePicture),\n                                child:\n                                    _imageProvider(user.profilePicture) == null\n                                    ? Text(\n                                        user.nama.isEmpty ? '?' : user.nama[0],\n                                      )\n                                    : null,\n                              ),\n                              title: Text(\n                                user.nama,\n                                style: const TextStyle(\n                                  fontWeight: FontWeight.w800,\n                                ),\n                              ),\n                              subtitle: Text(\n                                '${user.noKadPengenalan}${user.noPk.isEmpty ? '' : ' • No. PK ${user.noPk}'}\\n${user.jawatanPaparan} • ${user.jabatan}',\n                              ),\n                              isThreeLine: true,\n                              trailing: const Icon(Icons.edit_rounded),\n                            ),\n                          );\n                        },\n                      ),\n              ),\n            ],\n          );\n",
    'user list filter UI',
)
write(path, t)

print('Applied RimbaKawal v0.5.14+30 admin location, patrol-button, and user-filter upgrade.')
