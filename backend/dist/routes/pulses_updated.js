"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const client_1 = require("@prisma/client");
const auth_1 = require("firebase-admin/auth");
const router = (0, express_1.Router)();
const prisma = new client_1.PrismaClient();
// GET /api/pulses - Get all pulses for the authenticated user with filtering
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
        // Extract query parameters for filtering
        const { tags, search, location, eventTime, latitude, longitude, radiusKm } = req.query;
        // Build where clause
        let whereClause = {
            OR: [
                { authorId: user.id },
                { participants: { some: { id: user.id } } }
            ]
        };
        // Add tag filtering if provided
        if (tags) {
            const tagArray = Array.isArray(tags) ? tags : [tags];
            whereClause.tags = {
                hasSome: tagArray.map(tag => String(tag))
            };
        }
        // Add text search if provided
        if (search && typeof search === 'string') {
            whereClause.OR = [
                { title: { contains: search, mode: 'insensitive' } },
                { description: { contains: search, mode: 'insensitive' } }
            ];
        }
        // Add coordinate radius filtering (bounding box approximation) if provided
        if (latitude !== undefined && longitude !== undefined && radiusKm !== undefined) {
            const latNum = parseFloat(String(latitude));
            const lngNum = parseFloat(String(longitude));
            const rNum = parseFloat(String(radiusKm));
            if (!isNaN(latNum) && !isNaN(lngNum) && !isNaN(rNum) && rNum > 0) {
                const latDelta = rNum / 111; // ~111 km per degree latitude
                const lngDelta = rNum / (111 * Math.cos(latNum * Math.PI / 180));
                whereClause.latitude = { gte: latNum - latDelta, lte: latNum + latDelta };
                whereClause.longitude = { gte: lngNum - lngDelta, lte: lngNum + lngDelta };
            }
        }
        else if (location && typeof location === 'string') {
            // Legacy textual location search placeholder (no-op)
        }
        // Add event time filtering if provided
        if (eventTime && typeof eventTime === 'string') {
            const date = new Date(eventTime);
            if (!isNaN(date.getTime())) {
                whereClause.eventTime = {
                    gte: date
                };
            }
        }
        // Fetch filtered pulses
        const pulses = await prisma.pulse.findMany({
            where: whereClause,
            include: {
                author: {
                    select: {
                        id: true,
                        displayName: true,
                        email: true,
                    }
                },
                participants: {
                    select: {
                        id: true,
                        displayName: true,
                        email: true,
                    }
                }
            },
            orderBy: {
                eventTime: 'asc'
            }
        });
        res.json(pulses);
    }
    catch (error) {
        console.error('Error fetching pulses:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});
// GET /api/pulses/tags - Get all unique tags
router.get('/tags', async (req, res) => {
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
        // Get all unique tags from pulses the user has access to
        const pulses = await prisma.pulse.findMany({
            where: {
                OR: [
                    { authorId: user.id },
                    { participants: { some: { id: user.id } } }
                ]
            },
            select: {
                tags: true
            }
        });
        // Extract unique tags
        const allTags = new Set();
        pulses.forEach((pulse) => {
            pulse.tags.forEach((tag) => allTags.add(tag));
        });
        res.json(Array.from(allTags).sort());
    }
    catch (error) {
        console.error('Error fetching tags:', error);
        res.status(500).json({ error: 'Internal server error' });
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
//# sourceMappingURL=pulses_updated.js.map