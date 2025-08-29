-- Add active window columns to Pulse
-- Safe / idempotent style for dev iteration
ALTER TABLE "public"."Pulse"
  ADD COLUMN IF NOT EXISTS "activeFrom" TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
  ADD COLUMN IF NOT EXISTS "activeUntil" TIMESTAMP WITH TIME ZONE;

-- Indexes to support filtering
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE c.relkind='i' AND c.relname='Pulse_activeFrom_idx'
  ) THEN
    EXECUTE 'CREATE INDEX "Pulse_activeFrom_idx" ON "public"."Pulse"("activeFrom")';
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE c.relkind='i' AND c.relname='Pulse_activeUntil_idx'
  ) THEN
    EXECUTE 'CREATE INDEX "Pulse_activeUntil_idx" ON "public"."Pulse"("activeUntil")';
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE c.relkind='i' AND c.relname='Pulse_activeFrom_activeUntil_idx'
  ) THEN
    EXECUTE 'CREATE INDEX "Pulse_activeFrom_activeUntil_idx" ON "public"."Pulse"("activeFrom", "activeUntil")';
  END IF;
END $$;

SELECT 1;
