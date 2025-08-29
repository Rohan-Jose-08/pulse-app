/*
  Warnings:

  - You are about to drop the column `geohash` on the `Pulse` table. All the data in the column will be lost.
  - You are about to drop the column `location` on the `User` table. All the data in the column will be lost.
  - You are about to drop the column `locationGeohash` on the `User` table. All the data in the column will be lost.

*/
-- DropIndex
DROP INDEX "public"."Pulse_geohash_idx";

-- DropIndex
DROP INDEX "public"."User_locationGeohash_idx";

-- AlterTable
ALTER TABLE "public"."Pulse" DROP COLUMN "geohash",
ADD COLUMN     "locationId" INTEGER;

-- AlterTable
ALTER TABLE "public"."User" DROP COLUMN "location",
DROP COLUMN "locationGeohash",
ADD COLUMN     "locationId" INTEGER,
ADD COLUMN     "locationLabel" TEXT;

-- CreateTable
CREATE TABLE "public"."Location" (
    "id" SERIAL NOT NULL,
    "name" TEXT NOT NULL,
    "street" TEXT NOT NULL,
    "city" TEXT NOT NULL,
    "state" TEXT NOT NULL,
    "postalCode" TEXT NOT NULL,
    "country" TEXT NOT NULL,
    "latitude" DOUBLE PRECISION NOT NULL,
    "longitude" DOUBLE PRECISION NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Location_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "Location_latitude_longitude_idx" ON "public"."Location"("latitude", "longitude");

-- CreateIndex
CREATE INDEX "Location_city_idx" ON "public"."Location"("city");

-- CreateIndex
CREATE INDEX "Location_country_idx" ON "public"."Location"("country");

-- CreateIndex
CREATE INDEX "Pulse_locationId_idx" ON "public"."Pulse"("locationId");

-- CreateIndex
CREATE INDEX "User_locationId_idx" ON "public"."User"("locationId");

-- AddForeignKey
ALTER TABLE "public"."User" ADD CONSTRAINT "User_locationId_fkey" FOREIGN KEY ("locationId") REFERENCES "public"."Location"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."Pulse" ADD CONSTRAINT "Pulse_locationId_fkey" FOREIGN KEY ("locationId") REFERENCES "public"."Location"("id") ON DELETE SET NULL ON UPDATE CASCADE;
