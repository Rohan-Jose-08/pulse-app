-- AlterTable
ALTER TABLE "ConversationInvitation" ADD COLUMN     "invitationType" TEXT NOT NULL DEFAULT 'GROUP_CHAT';

-- CreateIndex
CREATE INDEX "ConversationInvitation_invitationType_idx" ON "ConversationInvitation"("invitationType");
