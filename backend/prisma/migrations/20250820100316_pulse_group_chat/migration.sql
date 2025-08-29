/*
  Warnings:

  - A unique constraint covering the columns `[pulseId]` on the table `Conversation` will be added. If there are existing duplicate values, this will fail.

*/
-- AlterTable
ALTER TABLE "public"."Conversation" ADD COLUMN     "avatarUrl" TEXT,
ADD COLUMN     "isGroup" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "name" TEXT,
ADD COLUMN     "pulseId" TEXT;

-- AlterTable
ALTER TABLE "public"."Message" ADD COLUMN     "videoUrl" TEXT;

-- CreateIndex
CREATE UNIQUE INDEX "Conversation_pulseId_key" ON "public"."Conversation"("pulseId");

-- AddForeignKey
ALTER TABLE "public"."Conversation" ADD CONSTRAINT "Conversation_pulseId_fkey" FOREIGN KEY ("pulseId") REFERENCES "public"."Pulse"("id") ON DELETE CASCADE ON UPDATE CASCADE;
