from pathlib import Path
p=Path('lib/features/admin/department_maintenance_screen.dart')
t=p.read_text(encoding='utf-8')
t=t.replace("title: const Text('Padam Sekolah?'),","title: const Text('Arkib Sekolah?'),")
t=t.replace("'Padam ${existing.name} daripada tetapan ZPatrol? Rekod sejarah akan dikekalkan. Pengguna aktif perlu dipindahkan atau dinyahaktifkan terlebih dahulu.',","'Arkib ${existing.name}? Sekolah, checkpoint dan akaun berkaitan akan dinyahaktifkan sementara. Rekod sejarah kekal untuk audit dan boleh dipulihkan semula.',")
t=t.replace("child: const Text('Padam Sekolah'),","child: const Text('Arkib Sekolah'),")
old="""              if (widget.department != null) ...[
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Sekolah aktif'),
                  value: _active,
                  onChanged: (value) => setState(() => _active = value),
                ),
              ],"""
new="""              if (widget.department != null) ...[
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: const Text('Status Sekolah'),
                  subtitle: const Text(
                    'Gunakan tindakan Arkib/Pulihkan supaya status pengguna dan checkpoint boleh dipulihkan dengan selamat.',
                  ),
                  trailing: Chip(label: Text(_active ? 'AKTIF' : 'DIARKIBKAN')),
                ),
              ],"""
if t.count(old)!=1: raise SystemExit(f'active switch {t.count(old)}')
p.write_text(t.replace(old,new,1),encoding='utf-8')
