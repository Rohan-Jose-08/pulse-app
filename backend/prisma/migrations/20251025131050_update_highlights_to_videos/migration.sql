/*
  Warnings:

  - You are about to drop the column `coverUrl` on the `Highlight` table. All the data in the column will be lost.
  - You are about to drop the column `position` on the `Highlight` table. All the data in the column will be lost.
  - You are about to drop the column `title` on the `Highlight` table. All the data in the column will be lost.
  - You are about to drop the `_HighlightPulses` table. If the table is not empty, all the data it contains will be lost.
  - Added the required column `duration` to the `Highlight` table without a default value. This is not possible if the table is not empty.
  - Added the required column `pulseId` to the `Highlight` table without a default value. This is not possible if the table is not empty.
  - Added the required column `videoUrl` to the `Highlight` table without a default value. This is not possible if the table is not empty.

*/
-- DropForeignKey
ALTER TABLE "public"."_HighlightPulses" DROP CONSTRAINT "_HighlightPulses_A_fkey";

-- DropForeignKey
ALTER TABLE "public"."_HighlightPulses" DROP CONSTRAINT "_HighlightPulses_B_fkey";

-- DropIndex
DROP INDEX "public"."Highlight_userId_position_idx";

-- AlterTable
ALTER TABLE "Highlight" DROP COLUMN "coverUrl",
DROP COLUMN "position",
DROP COLUMN "title",
ADD COLUMN     "caption" TEXT,
ADD COLUMN     "duration" INTEGER NOT NULL,
ADD COLUMN     "isPublic" BOOLEAN NOT NULL DEFAULT true,
ADD COLUMN     "pulseId" TEXT NOT NULL,
ADD COLUMN     "thumbnailUrl" TEXT,
ADD COLUMN     "videoUrl" TEXT NOT NULL,
ADD COLUMN     "viewCount" INTEGER NOT NULL DEFAULT 0;

-- DropTable
DROP TABLE "public"."_HighlightPulses";

-- CreateIndex
CREATE INDEX "Highlight_pulseId_idx" ON "Highlight"("pulseId");

-- CreateIndex
CREATE INDEX "Highlight_createdAt_idx" ON "Highlight"("createdAt");

-- AddForeignKey
ALTER TABLE "Highlight" ADD CONSTRAINT "Highlight_pulseId_fkey" FOREIGN KEY ("pulseId") REFERENCES "Pulse"("id") ON DELETE CASCADE ON UPDATE CASCADE;
