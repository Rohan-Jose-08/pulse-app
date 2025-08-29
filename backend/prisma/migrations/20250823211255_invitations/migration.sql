-- CreateTable
CREATE TABLE "public"."ConversationInvitation" (
    "id" TEXT NOT NULL,
    "conversationId" TEXT NOT NULL,
    "inviterId" TEXT NOT NULL,
    "inviteeId" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'PENDING',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "respondedAt" TIMESTAMP(3),

    CONSTRAINT "ConversationInvitation_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "ConversationInvitation_inviteeId_idx" ON "public"."ConversationInvitation"("inviteeId");

-- CreateIndex
CREATE INDEX "ConversationInvitation_conversationId_idx" ON "public"."ConversationInvitation"("conversationId");

-- CreateIndex
CREATE INDEX "ConversationInvitation_status_idx" ON "public"."ConversationInvitation"("status");

-- CreateIndex
CREATE UNIQUE INDEX "ConversationInvitation_conversationId_inviteeId_key" ON "public"."ConversationInvitation"("conversationId", "inviteeId");

-- AddForeignKey
ALTER TABLE "public"."ConversationInvitation" ADD CONSTRAINT "ConversationInvitation_conversationId_fkey" FOREIGN KEY ("conversationId") REFERENCES "public"."Conversation"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."ConversationInvitation" ADD CONSTRAINT "ConversationInvitation_inviterId_fkey" FOREIGN KEY ("inviterId") REFERENCES "public"."User"("firebase_uid") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."ConversationInvitation" ADD CONSTRAINT "ConversationInvitation_inviteeId_fkey" FOREIGN KEY ("inviteeId") REFERENCES "public"."User"("firebase_uid") ON DELETE CASCADE ON UPDATE CASCADE;
