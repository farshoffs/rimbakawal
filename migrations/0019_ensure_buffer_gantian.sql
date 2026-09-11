-- Pastikan akaun BUFFER digunakan sebagai pengawal gantian dalam Borang PKK 2.
UPDATE users
SET guard_status = 'Gantian'
WHERE UPPER(TRIM(nama)) = 'BUFFER';
