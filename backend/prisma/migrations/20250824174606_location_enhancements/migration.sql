-- AlterTable
ALTER TABLE "public"."Pulse" ADD COLUMN     "geohash" VARCHAR(20);

-- AlterTable
ALTER TABLE "public"."User" ADD COLUMN     "locationAccuracy" INTEGER,
ADD COLUMN     "locationGeohash" VARCHAR(20),
ADD COLUMN     "locationLatitude" DECIMAL(10,8),
ADD COLUMN     "locationLongitude" DECIMAL(11,8),
ADD COLUMN     "locationUpdatedAt" TIMESTAMP(3);

-- CreateIndex
CREATE INDEX "Pulse_geohash_idx" ON "public"."Pulse"("geohash");

-- CreateIndex
CREATE INDEX "Pulse_latitude_longitude_idx" ON "public"."Pulse"("latitude", "longitude");

-- CreateIndex
CREATE INDEX "User_locationGeohash_idx" ON "public"."User"("locationGeohash");
