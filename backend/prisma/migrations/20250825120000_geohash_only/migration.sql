-- Migration: Switch to geohash-only storage for Pulse and User locations
-- WARNING: This migration drops latitude/longitude columns. Backup data before applying in production.

-- 1. Backfill: Ensure all pulses have geohash using existing lat/long before dropping (PostgreSQL procedural block)
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN SELECT id, latitude, longitude, geohash FROM "Pulse" WHERE geohash IS NULL AND latitude IS NOT NULL AND longitude IS NOT NULL LOOP
    -- Simple inline geohash calculation not available in SQL; recommend running backfill via application script prior to migration.
    -- Placeholder: leave existing rows; application script will compute.
  END LOOP;
END$$;

-- 2. Drop indexes involving latitude/longitude if they exist
DROP INDEX IF EXISTS "Pulse_latitude_longitude_idx";
DROP INDEX IF EXISTS "User_locationGeohash_idx"; -- will recreate to ensure state

-- 3. Alter tables: drop columns
ALTER TABLE "Pulse" DROP COLUMN IF EXISTS latitude;
ALTER TABLE "Pulse" DROP COLUMN IF EXISTS longitude;
ALTER TABLE "User" DROP COLUMN IF EXISTS "locationLatitude";
ALTER TABLE "User" DROP COLUMN IF EXISTS "locationLongitude";
ALTER TABLE "User" DROP COLUMN IF EXISTS "locationAccuracy";

-- 4. (Optional) Make geohash NOT NULL for Pulse if desired (currently allowing NULL)
-- ALTER TABLE "Pulse" ALTER COLUMN geohash SET NOT NULL;

-- 5. Recreate indexes
CREATE INDEX IF NOT EXISTS "Pulse_geohash_idx" ON "Pulse"(geohash);
CREATE INDEX IF NOT EXISTS "User_locationGeohash_idx" ON "User"("locationGeohash");
