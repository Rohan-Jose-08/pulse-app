-- CreateTable
CREATE TABLE "public"."PulseInteraction" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "pulseId" TEXT NOT NULL,
    "interactionType" TEXT NOT NULL,
    "duration" INTEGER,
    "timestamp" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "source" TEXT,
    "deviceType" TEXT,

    CONSTRAINT "PulseInteraction_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."PulseRecommendation" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "pulseId" TEXT NOT NULL,
    "score" DOUBLE PRECISION NOT NULL,
    "reason" TEXT,
    "generatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "viewed" BOOLEAN NOT NULL DEFAULT false,
    "clicked" BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT "PulseRecommendation_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."UserEmbedding" (
    "userId" TEXT NOT NULL,
    "embedding" DOUBLE PRECISION[],
    "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "UserEmbedding_pkey" PRIMARY KEY ("userId")
);

-- CreateTable
CREATE TABLE "public"."UserFeatureCache" (
    "userId" TEXT NOT NULL,
    "avgSessionDuration" DOUBLE PRECISION,
    "preferredCategories" TEXT[],
    "preferredTimeSlots" TEXT[],
    "socialActivityScore" DOUBLE PRECISION,
    "messagingFrequency" DOUBLE PRECISION,
    "inviteAcceptanceRate" DOUBLE PRECISION,
    "lastPulseJoinedAt" TIMESTAMP(3),
    "totalPulsesJoined" INTEGER NOT NULL DEFAULT 0,
    "totalPulsesCreated" INTEGER NOT NULL DEFAULT 0,
    "avgDistanceKm" DOUBLE PRECISION,
    "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "UserFeatureCache_pkey" PRIMARY KEY ("userId")
);

-- CreateIndex
CREATE INDEX "PulseInteraction_userId_idx" ON "public"."PulseInteraction"("userId");

-- CreateIndex
CREATE INDEX "PulseInteraction_pulseId_idx" ON "public"."PulseInteraction"("pulseId");

-- CreateIndex
CREATE INDEX "PulseInteraction_timestamp_idx" ON "public"."PulseInteraction"("timestamp");

-- CreateIndex
CREATE INDEX "PulseInteraction_userId_timestamp_idx" ON "public"."PulseInteraction"("userId", "timestamp");

-- CreateIndex
CREATE INDEX "PulseInteraction_interactionType_idx" ON "public"."PulseInteraction"("interactionType");

-- CreateIndex
CREATE INDEX "PulseRecommendation_userId_score_idx" ON "public"."PulseRecommendation"("userId", "score" DESC);

-- CreateIndex
CREATE INDEX "PulseRecommendation_generatedAt_idx" ON "public"."PulseRecommendation"("generatedAt");

-- CreateIndex
CREATE INDEX "PulseRecommendation_userId_generatedAt_idx" ON "public"."PulseRecommendation"("userId", "generatedAt");

-- CreateIndex
CREATE INDEX "UserEmbedding_updatedAt_idx" ON "public"."UserEmbedding"("updatedAt");

-- CreateIndex
CREATE INDEX "UserFeatureCache_updatedAt_idx" ON "public"."UserFeatureCache"("updatedAt");
