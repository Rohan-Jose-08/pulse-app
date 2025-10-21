-- CreateTable
CREATE TABLE "DirectConversation" (
    "id" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "lastMessageText" TEXT,
    "lastSenderId" TEXT,
    "name" TEXT,
    "avatarUrl" TEXT,

    CONSTRAINT "DirectConversation_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "PulseConversation" (
    "id" TEXT NOT NULL,
    "pulseId" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "lastMessageText" TEXT,
    "lastSenderId" TEXT,
    "name" TEXT,
    "avatarUrl" TEXT,

    CONSTRAINT "PulseConversation_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "_DirectConversationParticipants" (
    "A" TEXT NOT NULL,
    "B" TEXT NOT NULL,

    CONSTRAINT "_DirectConversationParticipants_AB_pkey" PRIMARY KEY ("A","B")
);

-- CreateTable
CREATE TABLE "_PulseConversationParticipants" (
    "A" TEXT NOT NULL,
    "B" TEXT NOT NULL,

    CONSTRAINT "_PulseConversationParticipants_AB_pkey" PRIMARY KEY ("A","B")
);

-- CreateIndex
CREATE INDEX "DirectConversation_updatedAt_idx" ON "DirectConversation"("updatedAt");

-- CreateIndex
CREATE UNIQUE INDEX "PulseConversation_pulseId_key" ON "PulseConversation"("pulseId");

-- CreateIndex
CREATE INDEX "PulseConversation_updatedAt_idx" ON "PulseConversation"("updatedAt");

-- CreateIndex
CREATE INDEX "_DirectConversationParticipants_B_index" ON "_DirectConversationParticipants"("B");

-- CreateIndex
CREATE INDEX "_PulseConversationParticipants_B_index" ON "_PulseConversationParticipants"("B");

-- AddForeignKey
ALTER TABLE "PulseConversation" ADD CONSTRAINT "PulseConversation_pulseId_fkey" FOREIGN KEY ("pulseId") REFERENCES "Pulse"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "_DirectConversationParticipants" ADD CONSTRAINT "_DirectConversationParticipants_A_fkey" FOREIGN KEY ("A") REFERENCES "DirectConversation"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "_DirectConversationParticipants" ADD CONSTRAINT "_DirectConversationParticipants_B_fkey" FOREIGN KEY ("B") REFERENCES "User"("firebase_uid") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "_PulseConversationParticipants" ADD CONSTRAINT "_PulseConversationParticipants_A_fkey" FOREIGN KEY ("A") REFERENCES "PulseConversation"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "_PulseConversationParticipants" ADD CONSTRAINT "_PulseConversationParticipants_B_fkey" FOREIGN KEY ("B") REFERENCES "User"("firebase_uid") ON DELETE CASCADE ON UPDATE CASCADE;
