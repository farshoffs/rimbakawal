from pathlib import Path

path = Path('lib/features/patrol/patrol_screen.dart')
text = path.read_text(encoding='utf-8')

old = (
    "      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,\n"
    "      floatingActionButton: SizedBox(\n"
    "        width: 270,\n"
    "        height: 62,\n"
    "        child: FloatingActionButton.extended(\n"
)
new = (
    "      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,\n"
    "      floatingActionButton: SizedBox(\n"
    "        width: MediaQuery.sizeOf(context).width - 32,\n"
    "        height: 66,\n"
    "        child: FloatingActionButton.extended(\n"
)
if old not in text:
    raise SystemExit('Scan button size marker not found')
text = text.replace(old, new, 1)

old_shape = "borderRadius: BorderRadius.circular(20),"
if old_shape not in text:
    raise SystemExit('Scan button shape marker not found')
text = text.replace(old_shape, "borderRadius: BorderRadius.circular(18),", 1)

old_icon = (
    "          icon: Icon(\n"
    "            _scanning ? Icons.radar_rounded : Icons.nfc_rounded,\n"
    "            size: 28,\n"
    "          ),\n"
)
new_icon = (
    "          icon: Icon(\n"
    "            _scanning ? Icons.radar_rounded : Icons.nfc_rounded,\n"
    "            size: 30,\n"
    "          ),\n"
)
if old_icon not in text:
    raise SystemExit('Scan button icon marker not found')
text = text.replace(old_icon, new_icon, 1)

old_font = (
    "            style: const TextStyle(\n"
    "              fontSize: 16,\n"
    "              fontWeight: FontWeight.w900,\n"
)
new_font = (
    "            style: const TextStyle(\n"
    "              fontSize: 18,\n"
    "              fontWeight: FontWeight.w900,\n"
)
if old_font not in text:
    raise SystemExit('Scan button font marker not found')
text = text.replace(old_font, new_font, 1)

path.write_text(text, encoding='utf-8')
print('Checkpoint scan button now matches finish patrol button size.')
