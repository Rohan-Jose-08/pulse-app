/*
  Warnings:

  - You are about to drop the column `expiresAt` on the `Pulse` table. All the data in the column will be lost.

*/
-- DropIndex
DROP INDEX "public"."Pulse_expiresAt_idx";

-- AlterTable
ALTER TABLE "Pulse" DROP COLUMN "expiresAt";
