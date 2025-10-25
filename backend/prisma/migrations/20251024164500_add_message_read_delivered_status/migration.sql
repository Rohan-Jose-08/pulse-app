-- AlterTable
ALTER TABLE "Message" ADD COLUMN     "deliveredTo" TEXT[] DEFAULT ARRAY[]::TEXT[],
ADD COLUMN     "readBy" TEXT[] DEFAULT ARRAY[]::TEXT[];
