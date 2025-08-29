/*
  Warnings:

  - You are about to drop the column `location` on the `Pulse` table. All the data in the column will be lost.

*/
-- AlterTable
ALTER TABLE "public"."Pulse" DROP COLUMN "location",
ADD COLUMN     "latitude" DECIMAL(10,8),
ADD COLUMN     "longitude" DECIMAL(11,8);
