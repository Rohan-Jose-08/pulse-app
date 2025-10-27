"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const client_1 = require("@prisma/client");
/*
  Seed script: creates (or reuses) a test user and several public pulses with
  Location rows around a center (default San Francisco) so /api/pulses/nearby
  returns markers for the Flutter discovery map.

  Usage:
    npm run seed:pulses

  Environment:
    Requires DATABASE_URL to point to your dev Postgres and (optionally)
    TEST_FIREBASE_UID for deterministic user id (falls back to random UUID).
*/
const prisma = new client_1.PrismaClient();
async function main() {
    const centerLat = 37.7749; // SF default
    const centerLng = -122.4194;
    const userFirebaseUid = process.env.TEST_FIREBASE_UID || 'test-seed-user-uid';
    const userEmail = 'seed.user@example.com';
    // Ensure user exists
    let user = await prisma.user.findUnique({ where: { firebaseUid: userFirebaseUid } });
    if (!user) {
        user = await prisma.user.create({
            data: {
                id: userFirebaseUid,
                firebaseUid: userFirebaseUid,
                email: userEmail,
                displayName: 'Seed User',
                locationLabel: 'San Francisco, CA'
            }
        });
        console.log('Created seed user', user.id);
    }
    else {
        console.log('Reusing existing user', user.id);
    }
    const pulseTitles = [
        'Morning Run',
        'Coffee Meetup',
        'Sunset Hike',
        'Board Games Night',
        'Tech Talk Jam'
    ];
    for (let i = 0; i < pulseTitles.length; i++) {
        const title = pulseTitles[i];
        // Skip if pulse with same title by author exists
        const existing = await prisma.pulse.findFirst({ where: { title, authorId: user.id } });
        if (existing) {
            console.log('Pulse exists, skipping', title);
            continue;
        }
        // Slight random offset within ~1km
        const latOffset = (Math.random() - 0.5) * 0.02; // ~2.2km span
        const lngOffset = (Math.random() - 0.5) * 0.02;
        const location = await prisma.location.create({
            data: {
                name: title + ' Spot',
                street: '123 Example St',
                city: 'San Francisco',
                state: 'CA',
                postalCode: '94103',
                country: 'USA',
                latitude: centerLat + latOffset,
                longitude: centerLng + lngOffset,
                formattedAddress: `${title} Spot, San Francisco, CA`,
                types: ['seed'],
                locationSource: 'SEED'
            }
        });
        const now = new Date();
        const eventTime = new Date(now.getTime() + (i + 1) * 60 * 60 * 1000); // stagger hours
        const pulse = await prisma.pulse.create({
            data: {
                title,
                description: `Auto-seeded pulse: ${title}`,
                authorId: user.id,
                locationId: location.id,
                eventTime,
                activeFrom: new Date(now.getTime() - 15 * 60 * 1000),
                activeUntil: new Date(eventTime.getTime() + 2 * 60 * 60 * 1000),
                isPublic: true,
                tags: ['seed', 'demo'],
            }
        });
        console.log('Created pulse', pulse.title, pulse.id, 'at', location.latitude, location.longitude);
    }
    console.log('Seed complete.');
}
main().catch(e => { console.error(e); process.exit(1); }).finally(async () => { await prisma.$disconnect(); });
//# sourceMappingURL=seed_test_pulses.js.map