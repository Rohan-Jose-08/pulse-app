-- DropIndex
DROP INDEX "public"."ConversationInvitation_conversationId_inviteeId_key";

-- AlterTable
ALTER TABLE "ConversationInvitation" ALTER COLUMN "conversationId" DROP NOT NULL;

-- CreateIndex
CREATE INDEX "ConversationInvitation_inviterId_inviteeId_invitationType_idx" ON "ConversationInvitation"("inviterId", "inviteeId", "invitationType");
