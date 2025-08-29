-- Option B: This migration now introduces the enrichment columns (moved earlier for clean ordering).
-- Idempotent so it won't fail if re-applied in a dev reset.

ALTER TABLE "public"."Location"
	ADD COLUMN IF NOT EXISTS "placeId" TEXT,
	ADD COLUMN IF NOT EXISTS "formattedAddress" TEXT,
	ADD COLUMN IF NOT EXISTS "types" TEXT[] DEFAULT ARRAY[]::TEXT[],
	ADD COLUMN IF NOT EXISTS "raw" JSONB,
	ADD COLUMN IF NOT EXISTS "locationSource" TEXT,
	ADD COLUMN IF NOT EXISTS "accuracyMeters" INTEGER;

SELECT 1; -- done
