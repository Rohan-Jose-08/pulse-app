-- CreateTable
CREATE TABLE "GroupConversation" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "description" TEXT,
    "avatarUrl" TEXT,
    "creatorId" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "lastMessageText" TEXT,
    "lastSenderId" TEXT,

    CONSTRAINT "GroupConversation_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "_GroupConversationParticipants" (
    "A" TEXT NOT NULL,
    "B" TEXT NOT NULL,

    CONSTRAINT "_GroupConversationParticipants_AB_pkey" PRIMARY KEY ("A","B")
);

-- CreateIndex
CREATE INDEX "GroupConversation_updatedAt_idx" ON "GroupConversation"("updatedAt");

-- CreateIndex
CREATE INDEX "GroupConversation_creatorId_idx" ON "GroupConversation"("creatorId");

-- CreateIndex
CREATE INDEX "_GroupConversationParticipants_B_index" ON "_GroupConversationParticipants"("B");

-- AddForeignKey
ALTER TABLE "GroupConversation" ADD CONSTRAINT "GroupConversation_creatorId_fkey" FOREIGN KEY ("creatorId") REFERENCES "User"("firebase_uid") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "_GroupConversationParticipants" ADD CONSTRAINT "_GroupConversationParticipants_A_fkey" FOREIGN KEY ("A") REFERENCES "GroupConversation"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "_GroupConversationParticipants" ADD CONSTRAINT "_GroupConversationParticipants_B_fkey" FOREIGN KEY ("B") REFERENCES "User"("firebase_uid") ON DELETE CASCADE ON UPDATE CASCADE;
