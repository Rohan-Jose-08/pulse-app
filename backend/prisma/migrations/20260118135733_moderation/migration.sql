-- CreateTable
CREATE TABLE "public"."ContentReport" (
    "id" TEXT NOT NULL,
    "reporterId" TEXT NOT NULL,
    "reportedUserId" TEXT,
    "reportedPulseId" TEXT,
    "reportedMessageId" TEXT,
    "reportedHighlightId" TEXT,
    "reportedPostId" TEXT,
    "category" TEXT NOT NULL,
    "subcategory" TEXT,
    "description" TEXT,
    "evidence" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "status" TEXT NOT NULL DEFAULT 'PENDING',
    "priority" TEXT NOT NULL DEFAULT 'NORMAL',
    "aiAnalyzed" BOOLEAN NOT NULL DEFAULT false,
    "aiConfidenceScore" DOUBLE PRECISION,
    "aiCategories" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "aiRecommendation" TEXT,
    "reviewedBy" TEXT,
    "reviewedAt" TIMESTAMP(3),
    "resolution" TEXT,
    "actionTaken" TEXT,
    "resolutionNote" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "ContentReport_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."ModerationAction" (
    "id" TEXT NOT NULL,
    "targetUserId" TEXT,
    "targetPulseId" TEXT,
    "targetMessageId" TEXT,
    "targetHighlightId" TEXT,
    "targetPostId" TEXT,
    "actionType" TEXT NOT NULL,
    "reason" TEXT NOT NULL,
    "category" TEXT,
    "duration" INTEGER,
    "expiresAt" TIMESTAMP(3),
    "performedBy" TEXT NOT NULL,
    "isAutomated" BOOLEAN NOT NULL DEFAULT false,
    "relatedReportId" TEXT,
    "appealStatus" TEXT,
    "appealNote" TEXT,
    "appealedAt" TIMESTAMP(3),
    "appealReviewedBy" TEXT,
    "appealReviewedAt" TIMESTAMP(3),
    "notificationSent" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ModerationAction_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."MutedUser" (
    "id" TEXT NOT NULL,
    "mutingUserId" TEXT NOT NULL,
    "mutedUserId" TEXT NOT NULL,
    "reason" TEXT,
    "muteMessages" BOOLEAN NOT NULL DEFAULT true,
    "mutePulses" BOOLEAN NOT NULL DEFAULT true,
    "mutePosts" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "MutedUser_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."ContentModerationFlag" (
    "id" TEXT NOT NULL,
    "pulseId" TEXT,
    "messageId" TEXT,
    "highlightId" TEXT,
    "postId" TEXT,
    "isHidden" BOOLEAN NOT NULL DEFAULT false,
    "isRemoved" BOOLEAN NOT NULL DEFAULT false,
    "reason" TEXT,
    "aiAnalyzedAt" TIMESTAMP(3),
    "aiToxicityScore" DOUBLE PRECISION,
    "aiSpamScore" DOUBLE PRECISION,
    "aiViolenceScore" DOUBLE PRECISION,
    "aiAdultScore" DOUBLE PRECISION,
    "aiCategories" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "hiddenAt" TIMESTAMP(3),
    "hiddenBy" TEXT,
    "removedAt" TIMESTAMP(3),
    "removedBy" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "ContentModerationFlag_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."UserModerationStatus" (
    "userId" TEXT NOT NULL,
    "warningCount" INTEGER NOT NULL DEFAULT 0,
    "lastWarningAt" TIMESTAMP(3),
    "trustScore" DOUBLE PRECISION NOT NULL DEFAULT 1.0,
    "isMuted" BOOLEAN NOT NULL DEFAULT false,
    "mutedUntil" TIMESTAMP(3),
    "muteReason" TEXT,
    "isSuspended" BOOLEAN NOT NULL DEFAULT false,
    "suspendedUntil" TIMESTAMP(3),
    "suspendReason" TEXT,
    "isBanned" BOOLEAN NOT NULL DEFAULT false,
    "bannedAt" TIMESTAMP(3),
    "banReason" TEXT,
    "canCreatePulses" BOOLEAN NOT NULL DEFAULT true,
    "canSendMessages" BOOLEAN NOT NULL DEFAULT true,
    "canPostHighlights" BOOLEAN NOT NULL DEFAULT true,
    "requiresModeration" BOOLEAN NOT NULL DEFAULT false,
    "lastAppealAt" TIMESTAMP(3),
    "appealCooldown" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "UserModerationStatus_pkey" PRIMARY KEY ("userId")
);

-- CreateTable
CREATE TABLE "public"."AdminUser" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "role" TEXT NOT NULL DEFAULT 'MODERATOR',
    "canViewReports" BOOLEAN NOT NULL DEFAULT true,
    "canResolveReports" BOOLEAN NOT NULL DEFAULT true,
    "canWarnUsers" BOOLEAN NOT NULL DEFAULT true,
    "canMuteUsers" BOOLEAN NOT NULL DEFAULT true,
    "canSuspendUsers" BOOLEAN NOT NULL DEFAULT false,
    "canBanUsers" BOOLEAN NOT NULL DEFAULT false,
    "canRemoveContent" BOOLEAN NOT NULL DEFAULT true,
    "canViewAnalytics" BOOLEAN NOT NULL DEFAULT false,
    "canManageAdmins" BOOLEAN NOT NULL DEFAULT false,
    "reportsReviewed" INTEGER NOT NULL DEFAULT 0,
    "actionsPerformed" INTEGER NOT NULL DEFAULT 0,
    "lastActiveAt" TIMESTAMP(3),
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "AdminUser_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."ModerationAuditLog" (
    "id" TEXT NOT NULL,
    "adminUserId" TEXT,
    "action" TEXT NOT NULL,
    "targetType" TEXT NOT NULL,
    "targetId" TEXT NOT NULL,
    "details" JSONB,
    "ipAddress" TEXT,
    "userAgent" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ModerationAuditLog_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "ContentReport_reporterId_idx" ON "public"."ContentReport"("reporterId");

-- CreateIndex
CREATE INDEX "ContentReport_reportedUserId_idx" ON "public"."ContentReport"("reportedUserId");

-- CreateIndex
CREATE INDEX "ContentReport_reportedPulseId_idx" ON "public"."ContentReport"("reportedPulseId");

-- CreateIndex
CREATE INDEX "ContentReport_reportedMessageId_idx" ON "public"."ContentReport"("reportedMessageId");

-- CreateIndex
CREATE INDEX "ContentReport_status_idx" ON "public"."ContentReport"("status");

-- CreateIndex
CREATE INDEX "ContentReport_priority_idx" ON "public"."ContentReport"("priority");

-- CreateIndex
CREATE INDEX "ContentReport_createdAt_idx" ON "public"."ContentReport"("createdAt");

-- CreateIndex
CREATE INDEX "ContentReport_aiRecommendation_idx" ON "public"."ContentReport"("aiRecommendation");

-- CreateIndex
CREATE INDEX "ModerationAction_targetUserId_idx" ON "public"."ModerationAction"("targetUserId");

-- CreateIndex
CREATE INDEX "ModerationAction_targetPulseId_idx" ON "public"."ModerationAction"("targetPulseId");

-- CreateIndex
CREATE INDEX "ModerationAction_actionType_idx" ON "public"."ModerationAction"("actionType");

-- CreateIndex
CREATE INDEX "ModerationAction_performedBy_idx" ON "public"."ModerationAction"("performedBy");

-- CreateIndex
CREATE INDEX "ModerationAction_createdAt_idx" ON "public"."ModerationAction"("createdAt");

-- CreateIndex
CREATE INDEX "ModerationAction_expiresAt_idx" ON "public"."ModerationAction"("expiresAt");

-- CreateIndex
CREATE INDEX "MutedUser_mutingUserId_idx" ON "public"."MutedUser"("mutingUserId");

-- CreateIndex
CREATE INDEX "MutedUser_mutedUserId_idx" ON "public"."MutedUser"("mutedUserId");

-- CreateIndex
CREATE UNIQUE INDEX "MutedUser_mutingUserId_mutedUserId_key" ON "public"."MutedUser"("mutingUserId", "mutedUserId");

-- CreateIndex
CREATE UNIQUE INDEX "ContentModerationFlag_pulseId_key" ON "public"."ContentModerationFlag"("pulseId");

-- CreateIndex
CREATE UNIQUE INDEX "ContentModerationFlag_messageId_key" ON "public"."ContentModerationFlag"("messageId");

-- CreateIndex
CREATE UNIQUE INDEX "ContentModerationFlag_highlightId_key" ON "public"."ContentModerationFlag"("highlightId");

-- CreateIndex
CREATE UNIQUE INDEX "ContentModerationFlag_postId_key" ON "public"."ContentModerationFlag"("postId");

-- CreateIndex
CREATE INDEX "ContentModerationFlag_isHidden_idx" ON "public"."ContentModerationFlag"("isHidden");

-- CreateIndex
CREATE INDEX "ContentModerationFlag_isRemoved_idx" ON "public"."ContentModerationFlag"("isRemoved");

-- CreateIndex
CREATE INDEX "ContentModerationFlag_aiToxicityScore_idx" ON "public"."ContentModerationFlag"("aiToxicityScore");

-- CreateIndex
CREATE INDEX "UserModerationStatus_isMuted_idx" ON "public"."UserModerationStatus"("isMuted");

-- CreateIndex
CREATE INDEX "UserModerationStatus_isSuspended_idx" ON "public"."UserModerationStatus"("isSuspended");

-- CreateIndex
CREATE INDEX "UserModerationStatus_isBanned_idx" ON "public"."UserModerationStatus"("isBanned");

-- CreateIndex
CREATE INDEX "UserModerationStatus_trustScore_idx" ON "public"."UserModerationStatus"("trustScore");

-- CreateIndex
CREATE UNIQUE INDEX "AdminUser_userId_key" ON "public"."AdminUser"("userId");

-- CreateIndex
CREATE INDEX "AdminUser_role_idx" ON "public"."AdminUser"("role");

-- CreateIndex
CREATE INDEX "AdminUser_isActive_idx" ON "public"."AdminUser"("isActive");

-- CreateIndex
CREATE INDEX "ModerationAuditLog_adminUserId_idx" ON "public"."ModerationAuditLog"("adminUserId");

-- CreateIndex
CREATE INDEX "ModerationAuditLog_targetType_targetId_idx" ON "public"."ModerationAuditLog"("targetType", "targetId");

-- CreateIndex
CREATE INDEX "ModerationAuditLog_createdAt_idx" ON "public"."ModerationAuditLog"("createdAt");
