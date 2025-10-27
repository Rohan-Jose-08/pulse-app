"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const client_1 = require("@prisma/client");
const auth_1 = require("firebase-admin/auth");
const geolocation_1 = require("../services/geolocation");
const router = (0, express_1.Router)();
const prisma = new client_1.PrismaClient();
// GET /api/pulses - Get all pulses for the authenticated user
router.get('/', async (req, res) => {
    try {
        const authHeader = req.headers.authorization;
        if (!authHeader || !authHeader.startsWith('Bearer ')) {
            return res.status(401).json({ error: 'Unauthorized' });
        }
        const token = authHeader.split('Bearer ')[1];
        const decodedToken = await (0, auth_1.getAuth)().verifyIdToken(token);
        const firebaseUid = decodedToken.uid;
        // Find user by firebaseUid
        const user = await prisma.user.findUnique({
            where: { firebaseUid },
        });
        if (!user) {
            return res.status(404).json({ error: 'User not found' });
        }
        // Fetch all pulses where user is either author or participant
        const pulses = await prisma.pulse.findMany({
            where: {
                OR: [
                    { authorId: user.id },
                    { participants: { some: { id: user.id } } }
                ]
            },
            include: {
                author: { select: { id: true, displayName: true, email: true } },
                participants: { select: { id: true, displayName: true, email: true } },
                location: { select: { id: true, name: true, city: true, country: true, latitude: true, longitude: true } }
            },
            orderBy: { eventTime: 'asc' }
        });
        res.json(pulses);
    }
    catch (error) {
        console.error('Error fetching pulses:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});
// GET /api/pulses/nearby?lat=&lng=&radiusKm=
router.get('/nearby', async (req, res) => {
    try {
        const authHeader = req.headers.authorization;
        if (!authHeader || !authHeader.startsWith('Bearer ')) {
            return res.status(401).json({ error: 'Unauthorized' });
        }
        console.log('[GET] /pulses/nearby', req.query);
        const { lat, lng, radiusKm = '10' } = req.query;
        if (!lat || !lng) {
            console.log('Missing lat/lng');
            return res.status(400).json({ error: 'lat and lng are required' });
        }
        const latitude = parseFloat(lat);
        const longitude = parseFloat(lng);
        const radius = parseFloat(radiusKm);
        if ([latitude, longitude, radius].some(v => isNaN(v))) {
            console.log('Invalid numeric parameters', { latitude, longitude, radius });
            return res.status(400).json({ error: 'Invalid numeric parameters' });
        }
        const bbox = (0, geolocation_1.boundingBox)(latitude, longitude, radius);
        // Bounding box search via related Location, only public pulses
        const rough = await prisma.pulse.findMany({
            where: {
                location: { latitude: { gte: bbox.minLat, lte: bbox.maxLat }, longitude: { gte: bbox.minLng, lte: bbox.maxLng } },
                isPublic: true,
            },
            include: {
                author: { select: { id: true, displayName: true, email: true } },
                participants: { select: { id: true, displayName: true, email: true } },
                location: { select: { id: true, name: true, city: true, country: true, latitude: true, longitude: true } }
            },
            take: 1000
        });
        const precise = rough.map(p => {
            if (!p.location)
                return null;
            const d = (0, geolocation_1.haversineKm)(p.location.latitude, p.location.longitude, latitude, longitude);
            return d <= radius ? { ...p, distanceKm: d } : null;
        }).filter(Boolean);
        precise.sort((a, b) => a.distanceKm - b.distanceKm);
        const response = { center: { latitude, longitude }, radiusKm: radius, count: precise.length, pulses: precise.slice(0, 500) };
        console.log('Nearby pulses response:', JSON.stringify(response));
        return res.status(200).json(response);
    }
    catch (e) {
        console.error('nearby pulses error', e);
        res.status(500).json({ error: 'Failed nearby pulses search' });
    }
});
// POST /api/pulses/:id/join - Join a pulse
router.post('/:id/join', async (req, res) => {
    try {
        const { id } = req.params;
        const authHeader = req.headers.authorization;
        if (!authHeader || !authHeader.startsWith('Bearer ')) {
            return res.status(401).json({ error: 'Unauthorized' });
        }
        const token = authHeader.split('Bearer ')[1];
        const decodedToken = await (0, auth_1.getAuth)().verifyIdToken(token);
        const firebaseUid = decodedToken.uid;
        // Find user by firebaseUid
        const user = await prisma.user.findUnique({
            where: { firebaseUid },
        });
        if (!user) {
            return res.status(404).json({ error: 'User not found' });
        }
        // Check if pulse exists
        const pulse = await prisma.pulse.findUnique({
            where: { id },
            include: {
                participants: true,
                author: true,
            },
        });
        if (!pulse) {
            return res.status(404).json({ error: 'Pulse not found' });
        }
        // Check if user is already a participant
        const isAlreadyParticipant = pulse.participants.some((participant) => participant.id === user.id);
        if (isAlreadyParticipant) {
            return res.status(400).json({ error: 'Already joined this pulse' });
        }
        // Check if user is the author
        if (pulse.authorId === user.id) {
            return res.status(400).json({ error: 'Cannot join your own pulse' });
        }
        // Add user as participant
        const updatedPulse = await prisma.pulse.update({
            where: { id },
            data: {
                participants: {
                    connect: { id: user.id },
                },
            },
            include: {
                participants: {
                    select: {
                        id: true,
                        displayName: true,
                        email: true,
                    },
                },
                author: {
                    select: {
                        id: true,
                        displayName: true,
                        email: true,
                    },
                },
            },
        });
        res.json({
            success: true,
            message: 'Successfully joined pulse',
            pulse: updatedPulse,
        });
    }
    catch (error) {
        console.error('Error joining pulse:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});
// GET /api/pulses/:id/participants - Get pulse participants
router.get('/:id/participants', async (req, res) => {
    try {
        const { id } = req.params;
        const pulse = await prisma.pulse.findUnique({
            where: { id },
            include: {
                participants: {
                    select: {
                        id: true,
                        displayName: true,
                        email: true,
                    },
                },
            },
        });
        if (!pulse) {
            return res.status(404).json({ error: 'Pulse not found' });
        }
        res.json({
            participants: pulse.participants,
            participantCount: pulse.participants.length,
        });
    }
    catch (error) {
        console.error('Error fetching pulse participants:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});
exports.default = router;
//# sourceMappingURL=pulses.js.map