-- 016_retention_14d.sql
-- Event duration presets change (2026-07-05): drop 24h from the OFFERED
-- presets, add 14 days (336h). Offered set becomes 72/168/336.
--
-- 24 stays in the CHECK on purpose (legacy shim): installed mobile builds
-- <=1.0.0+12 still send retention_hours=24 and live 24h rows may exist.
-- Tighten to (72, 168, 336) in v1.5 once old builds age out.
--
-- The original CHECK from 001_initial_schema.sql is inline/unnamed, so the
-- constraint name is discovered rather than assumed. Idempotent: re-running
-- finds the (re)named constraint and replaces it with the same definition.

DO $$
DECLARE c TEXT;
BEGIN
  SELECT conname INTO c FROM pg_constraint
  WHERE conrelid = 'events'::regclass AND contype = 'c'
    AND pg_get_constraintdef(oid) LIKE '%retention_hours%';
  IF c IS NOT NULL THEN
    EXECUTE format('ALTER TABLE events DROP CONSTRAINT %I', c);
  END IF;
END $$;

ALTER TABLE events ADD CONSTRAINT events_retention_hours_check
  CHECK (retention_hours IN (24, 72, 168, 336));
