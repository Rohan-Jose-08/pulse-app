/*
  Warnings:

  - You are about to drop the `Post` table. If the table is not empty, all the data it contains will be lost.

*/
-- DropForeignKey
ALTER TABLE "public"."Post" DROP CONSTRAINT "Post_authorId_fkey";

-- DropTable
DROP TABLE "public"."Post";

-- CreateTable
CREATE TABLE "public"."Pulse" (
    "id" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "description" TEXT NOT NULL,
    "location" TEXT,
    "eventTime" TIMESTAMP(3) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "isPublic" BOOLEAN NOT NULL DEFAULT true,
    "tags" TEXT[],
    "authorId" TEXT NOT NULL,

    CONSTRAINT "Pulse_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."_PulseParticipants" (
    "A" TEXT NOT NULL,
    "B" TEXT NOT NULL,

    CONSTRAINT "_PulseParticipants_AB_pkey" PRIMARY KEY ("A","B")
);

-- CreateIndex
CREATE INDEX "_PulseParticipants_B_index" ON "public"."_PulseParticipants"("B");

-- AddForeignKey
ALTER TABLE "public"."Pulse" ADD CONSTRAINT "Pulse_authorId_fkey" FOREIGN KEY ("authorId") REFERENCES "public"."User"("firebase_uid") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."_PulseParticipants" ADD CONSTRAINT "_PulseParticipants_A_fkey" FOREIGN KEY ("A") REFERENCES "public"."Pulse"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."_PulseParticipants" ADD CONSTRAINT "_PulseParticipants_B_fkey" FOREIGN KEY ("B") REFERENCES "public"."User"("firebase_uid") ON DELETE CASCADE ON UPDATE CASCADE;
