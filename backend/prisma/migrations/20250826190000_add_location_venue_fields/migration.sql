-- Columns were added earlier (20250826172106_exactloc). This migration now only ensures indexes exist.

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE c.relkind='i' AND c.relname='Location_placeId_key'
  ) THEN
    EXECUTE 'CREATE UNIQUE INDEX "Location_placeId_key" ON "public"."Location"("placeId") WHERE "placeId" IS NOT NULL';
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE c.relkind='i' AND c.relname='Location_placeId_idx'
  ) THEN
    EXECUTE 'CREATE INDEX "Location_placeId_idx" ON "public"."Location"("placeId")';
  END IF;
END $$;

SELECT 1; -- done
