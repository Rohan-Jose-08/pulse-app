-- AlterTable
ALTER TABLE "Pulse" ADD COLUMN     "expiresAt" TIMESTAMP(3);

-- CreateIndex
CREATE INDEX "Pulse_expiresAt_idx" ON "Pulse"("expiresAt");
