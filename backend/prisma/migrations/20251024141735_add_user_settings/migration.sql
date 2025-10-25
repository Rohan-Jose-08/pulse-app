-- AlterTable
ALTER TABLE "User" ADD COLUMN     "activityStatusVisible" BOOLEAN NOT NULL DEFAULT true,
ADD COLUMN     "allowMessageRequests" BOOLEAN NOT NULL DEFAULT true,
ADD COLUMN     "friendRequestsFrom" TEXT DEFAULT 'everyone',
ADD COLUMN     "hapticFeedbackEnabled" BOOLEAN NOT NULL DEFAULT true,
ADD COLUMN     "languagePreference" TEXT DEFAULT 'en_US',
ADD COLUMN     "locationSharing" TEXT DEFAULT 'friends',
ADD COLUMN     "notifyFriendRequests" BOOLEAN NOT NULL DEFAULT true,
ADD COLUMN     "notifyNewFollowers" BOOLEAN NOT NULL DEFAULT true,
ADD COLUMN     "notifyNewMessages" BOOLEAN NOT NULL DEFAULT true,
ADD COLUMN     "notifyNewPulsesNearby" BOOLEAN NOT NULL DEFAULT true,
ADD COLUMN     "notifyPostReactions" BOOLEAN NOT NULL DEFAULT true,
ADD COLUMN     "notifyPulseInvitations" BOOLEAN NOT NULL DEFAULT true,
ADD COLUMN     "notifyPulseUpdates" BOOLEAN NOT NULL DEFAULT true,
ADD COLUMN     "profileVisibility" TEXT DEFAULT 'public',
ADD COLUMN     "pulseHistoryVisibility" TEXT DEFAULT 'friends',
ADD COLUMN     "pushNotificationsEnabled" BOOLEAN NOT NULL DEFAULT true,
ADD COLUMN     "showInSearch" BOOLEAN NOT NULL DEFAULT true,
ADD COLUMN     "showOnlineStatus" BOOLEAN NOT NULL DEFAULT true,
ADD COLUMN     "textSizeScale" DOUBLE PRECISION DEFAULT 1.0,
ADD COLUMN     "themePreference" TEXT DEFAULT 'system';

-- CreateTable
CREATE TABLE "BlockedUser" (
    "id" TEXT NOT NULL,
    "blockingUserId" TEXT NOT NULL,
    "blockedUserId" TEXT NOT NULL,
    "reason" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "BlockedUser_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "BlockedUser_blockingUserId_idx" ON "BlockedUser"("blockingUserId");

-- CreateIndex
CREATE INDEX "BlockedUser_blockedUserId_idx" ON "BlockedUser"("blockedUserId");

-- CreateIndex
CREATE UNIQUE INDEX "BlockedUser_blockingUserId_blockedUserId_key" ON "BlockedUser"("blockingUserId", "blockedUserId");

-- AddForeignKey
ALTER TABLE "BlockedUser" ADD CONSTRAINT "BlockedUser_blockingUserId_fkey" FOREIGN KEY ("blockingUserId") REFERENCES "User"("firebase_uid") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "BlockedUser" ADD CONSTRAINT "BlockedUser_blockedUserId_fkey" FOREIGN KEY ("blockedUserId") REFERENCES "User"("firebase_uid") ON DELETE CASCADE ON UPDATE CASCADE;
