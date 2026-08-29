from pathlib import Path
import re

path = Path('lib/features/patrol/patrol_screen.dart')
text = path.read_text(encoding='utf-8')

old_scan_call = """              const SizedBox(height: 14),
              _ScanCard(
                scanning: _scanning,
                mockMode: widget.mockMode,
                nextName: next?.name,
                onScan: _scanCheckpoint,
              ),
"""
if old_scan_call not in text:
    raise SystemExit('scan card call not found')
text = text.replace(old_scan_call, "", 1)

old_bottom = """      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: SizedBox(
          height: 66,
          child: FilledButton.icon(
            onPressed: _ending ? null : _finishPatrol,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFC0392B),
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFF6F2A25),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            icon: const Icon(Icons.stop_circle_rounded, size: 30),
            label: Text(
              _ending ? 'MENAMATKAN RONDAAN…' : 'TAMAT RONDAAN',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ),
      body: SafeArea(
"""
new_bottom = """      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: SizedBox(
          height: 66,
          child: FilledButton.icon(
            onPressed: _ending ? null : _finishPatrol,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFC0392B),
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFF6F2A25),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            icon: const Icon(Icons.stop_circle_rounded, size: 30),
            label: Text(
              _ending ? 'MENAMATKAN RONDAAN…' : 'TAMAT RONDAAN',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: SizedBox(
        width: 270,
        height: 62,
        child: FloatingActionButton.extended(
          heroTag: 'scan-checkpoint-fab',
          onPressed: _scanning || _ending ? null : _scanCheckpoint,
          elevation: 10,
          backgroundColor: const Color(0xFFFFD54F),
          foregroundColor: const Color(0xFF181818),
          disabledElevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: Colors.white.withValues(alpha: 0.22),
            ),
          ),
          icon: Icon(
            _scanning ? Icons.radar_rounded : Icons.nfc_rounded,
            size: 28,
          ),
          label: Text(
            _scanning ? 'MENGIMBAS…' : 'IMBAS CHECKPOINT',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
      body: SafeArea(
"""
if old_bottom not in text:
    raise SystemExit('bottom navigation scaffold block not found')
text = text.replace(old_bottom, new_bottom, 1)

old_padding = "padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),"
if old_padding not in text:
    raise SystemExit('list padding not found')
text = text.replace(
    old_padding,
    "padding: const EdgeInsets.fromLTRB(16, 8, 16, 118),",
    1,
)

pattern = re.compile(
    r"\nclass _ScanCard extends StatelessWidget \{.*?\n\}\n\nclass _TimelineEvent extends StatelessWidget \{",
    re.S,
)
text, count = pattern.subn(
    "\nclass _TimelineEvent extends StatelessWidget {",
    text,
    count=1,
)
if count != 1:
    raise SystemExit('ScanCard class block not found')

path.write_text(text, encoding='utf-8')
