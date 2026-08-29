from pathlib import Path

path = Path('lib/core/notifications/notification_service.dart')
text = path.read_text()
old = 'return _registerCurrentToken(user);'
count = text.count(old)
if count != 2:
    raise RuntimeError(f'Expected 2 registration returns, found {count}')
text = text.replace(old, 'return await _registerCurrentToken(user);')
path.write_text(text)
print('Push notification lint fixes applied.')
