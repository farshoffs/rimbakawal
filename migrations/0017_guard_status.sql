-- Status pengawal untuk Borang PKK 2 dan pentadbiran pengguna.
ALTER TABLE users ADD COLUMN guard_status TEXT NOT NULL DEFAULT 'Tetap';

UPDATE users
SET guard_status = 'Gantian'
WHERE UPPER(TRIM(nama)) = 'BUFFER';
