-- Migration: Add PulseMember model for role-based pulse management
-- This migration adds support for user roles within pulses

-- Add new columns to Pulse table for management features
ALTER TABLE "Pulse" ADD COLUMN IF NOT EXISTS "allowGuestInvites" BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE "Pulse" ADD COLUMN IF NOT EXISTS "requireApproval" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "Pulse" ADD COLUMN IF NOT EXISTS "isArchived" BOOLEAN NOT NULL DEFAULT false;

-- Create index for archived pulses
CREATE INDEX IF NOT EXISTS "Pulse_isArchived_idx" ON "Pulse"("isArchived");

-- Create PulseMember table for role-based membership
CREATE TABLE IF NOT EXISTS "PulseMember" (
    "id" TEXT NOT NULL,
    "pulseId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "role" TEXT NOT NULL DEFAULT 'MEMBER',
    "joinedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "invitedBy" TEXT,
    "canInvite" BOOLEAN,
    "canRemove" BOOLEAN,
    "canEdit" BOOLEAN,
    "canManageChat" BOOLEAN,
    "isMuted" BOOLEAN NOT NULL DEFAULT false,
    "isBanned" BOOLEAN NOT NULL DEFAULT false,
    "bannedAt" TIMESTAMP(3),
    "bannedReason" TEXT,

    CONSTRAINT "PulseMember_pkey" PRIMARY KEY ("id")
);

-- Create unique constraint on pulseId + userId
CREATE UNIQUE INDEX IF NOT EXISTS "PulseMember_pulseId_userId_key" ON "PulseMember"("pulseId", "userId");

-- Create indexes for PulseMember
CREATE INDEX IF NOT EXISTS "PulseMember_pulseId_idx" ON "PulseMember"("pulseId");
CREATE INDEX IF NOT EXISTS "PulseMember_userId_idx" ON "PulseMember"("userId");
CREATE INDEX IF NOT EXISTS "PulseMember_role_idx" ON "PulseMember"("role");

-- Add foreign key constraints
ALTER TABLE "PulseMember" ADD CONSTRAINT "PulseMember_pulseId_fkey" 
    FOREIGN KEY ("pulseId") REFERENCES "Pulse"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- Note: The User table uses firebase_uid as the id column
-- Make sure this matches your schema

-- Migrate existing participants to PulseMember table
-- This will create OWNER entries for pulse authors and MEMBER entries for participants
INSERT INTO "PulseMember" ("id", "pulseId", "userId", "role", "joinedAt")
SELECT 
    gen_random_uuid()::text,
    p.id,
    p."authorId",
    'OWNER',
    p."createdAt"
FROM "Pulse" p
WHERE NOT EXISTS (
    SELECT 1 FROM "PulseMember" pm 
    WHERE pm."pulseId" = p.id AND pm."userId" = p."authorId"
)
ON CONFLICT DO NOTHING;

-- Migrate existing participants
INSERT INTO "PulseMember" ("id", "pulseId", "userId", "role", "joinedAt")
SELECT 
    gen_random_uuid()::text,
    pp."A",
    pp."B",
    'MEMBER',
    CURRENT_TIMESTAMP
FROM "_PulseParticipants" pp
WHERE NOT EXISTS (
    SELECT 1 FROM "PulseMember" pm 
    WHERE pm."pulseId" = pp."A" AND pm."userId" = pp."B"
)
ON CONFLICT DO NOTHING;

-- Add comment for documentation
COMMENT ON TABLE "PulseMember" IS 'Stores pulse membership with roles. Roles: OWNER (creator), ADMIN (co-organizer), MODERATOR (chat manager), MEMBER (participant)';
COMMENT ON COLUMN "PulseMember"."role" IS 'User role in the pulse: OWNER, ADMIN, MODERATOR, or MEMBER';
COMMENT ON COLUMN "PulseMember"."canInvite" IS 'Override permission: can invite new members (null = use role default)';
COMMENT ON COLUMN "PulseMember"."canRemove" IS 'Override permission: can remove other members (null = use role default)';
COMMENT ON COLUMN "PulseMember"."canEdit" IS 'Override permission: can edit pulse details (null = use role default)';
COMMENT ON COLUMN "PulseMember"."canManageChat" IS 'Override permission: can manage chat (null = use role default)';
