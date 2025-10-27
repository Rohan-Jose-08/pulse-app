"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.app = void 0;
const express_1 = __importDefault(require("express"));
const dotenv_1 = __importDefault(require("dotenv"));
const cors_1 = __importDefault(require("cors"));
const auth_1 = __importDefault(require("./routes/auth"));
const profile_1 = __importDefault(require("./routes/profile"));
const client_1 = require("@prisma/client");
const posts_1 = __importDefault(require("./routes/posts"));
const messages_1 = __importDefault(require("./routes/messages"));
const pulse_invitations_1 = __importDefault(require("./routes/pulse_invitations"));
const invitations_1 = __importDefault(require("./routes/invitations"));
const settings_1 = __importDefault(require("./routes/settings"));
const activity_1 = __importDefault(require("./routes/activity"));
const highlights_1 = __importDefault(require("./routes/highlights"));
const firebase_1 = __importDefault(require("./firebase"));
const http_1 = __importDefault(require("http"));
const realtime_1 = require("./realtime");
const auth_2 = require("./middleware/auth");
// Geolocation service (coordinate + reverse geocode utilities)
const geolocation_1 = require("./services/geolocation");
const googlePlaces_1 = require("./services/googlePlaces");
// Use require to avoid type resolution issues during build/lint
// eslint-disable-next-line @typescript-eslint/no-var-requires
const { Server } = require('socket.io');
dotenv_1.default.config();
exports.app = (0, express_1.default)();
const prisma = new client_1.PrismaClient();
exports.app.use(express_1.default.json());
// Enable CORS (open for development; tighten origins in production)
exports.app.use((0, cors_1.default)());
// Mount the auth routes directly without applying global authentication middleware
exports.app.use('/api/auth', auth_1.default);
// Mount the profile routes
exports.app.use('/api/profile', profile_1.default);
// Mount posts routes
exports.app.use('/api/posts', posts_1.default);
// Messaging routes (REST helpers for conversations/messages)
exports.app.use('/api', messages_1.default);
// Pulse invitations routes (legacy, specific to pulses)
exports.app.use('/api/pulses', pulse_invitations_1.default);
// Unified invitations routes (all invitation types)
exports.app.use('/api/invitations', invitations_1.default);
// Settings routes
exports.app.use('/api/settings', settings_1.default);
// Activity status routes
exports.app.use('/api/activity', activity_1.default);
// Highlights routes
exports.app.use('/api/highlights', highlights_1.default);
// --- Notifications REST endpoints ---
// List notifications for the authenticated user (paged)
exports.app.get('/api/notifications', auth_2.authenticateUser, async (req, res) => {
    try {
        const me = req.user.id;
        const pageRaw = String(req.query.page ?? '0');
        const sizeRaw = String(req.query.size ?? '20');
        const page = Math.max(0, parseInt(pageRaw, 10) || 0);
        const size = Math.min(100, Math.max(1, parseInt(sizeRaw, 10) || 20));
        const notifications = await prisma.notification.findMany({
            where: { userId: me },
            orderBy: { createdAt: 'desc' },
            skip: page * size,
            take: size,
        });
        // Enrich invitation notifications: if related invitation is ACCEPTED, tweak text
        const inviteNotifs = notifications.filter((n) => n.type === 'INVITE' && n.data && n.data.invitationId);
        if (inviteNotifs.length) {
            const ids = Array.from(new Set(inviteNotifs.map((n) => String(n.data.invitationId))));
            try {
                const invites = await prisma.conversationInvitation.findMany({
                    where: { id: { in: ids } },
                    select: { id: true, status: true },
                });
                const statusById = new Map(invites.map(i => [i.id, i.status]));
                // mutate a mapped copy to avoid altering original objects shape
                const enriched = notifications.map((n) => {
                    if (n.type !== 'INVITE')
                        return n;
                    const invId = n?.data?.invitationId ? String(n.data.invitationId) : undefined;
                    if (!invId)
                        return n;
                    const status = statusById.get(invId);
                    if (status === 'ACCEPTED') {
                        return {
                            ...n,
                            title: 'Invitation accepted',
                            message: 'You accepted this invitation',
                            data: { ...n.data, status: 'ACCEPTED' },
                        };
                    }
                    return n;
                });
                return res.json(enriched);
            }
            catch (enrichErr) {
                console.warn('Failed to enrich invite notifications', enrichErr);
                // Fall through to return raw notifications
            }
        }
        res.json(notifications);
    }
    catch (e) {
        console.error('list notifications error', e);
        res.status(500).json({ error: 'Failed to fetch notifications' });
    }
});
// Mark a single notification as read
exports.app.post('/api/notifications/:id/read', auth_2.authenticateUser, async (req, res) => {
    try {
        const me = req.user.id;
        const { id } = req.params;
        const found = await prisma.notification.findUnique({ where: { id } });
        if (!found || found.userId !== me) {
            return res.status(404).json({ error: 'Notification not found' });
        }
        await prisma.notification.update({ where: { id }, data: { isRead: true } });
        res.json({ ok: true });
    }
    catch (e) {
        console.error('mark notification read error', e);
        res.status(500).json({ error: 'Failed to update notification' });
    }
});
// Mark all notifications as read for the authenticated user
exports.app.post('/api/notifications/mark-all-read', auth_2.authenticateUser, async (req, res) => {
    try {
        const me = req.user.id;
        await prisma.notification.updateMany({ where: { userId: me, isRead: false }, data: { isRead: true } });
        res.json({ ok: true });
    }
    catch (e) {
        console.error('mark all notifications read error', e);
        res.status(500).json({ error: 'Failed to update notifications' });
    }
});
// Health check endpoint to test database connection
exports.app.get('/api/health', async (req, res) => {
    try {
        // Test database connection
        await prisma.$queryRaw `SELECT 1`;
        // Test user table
        const userCount = await prisma.user.count();
        const pulseCount = await prisma.pulse.count();
        res.json({
            status: 'healthy',
            database: 'connected',
            tables: {
                users: userCount,
                pulses: pulseCount
            },
            timestamp: new Date().toISOString()
        });
    }
    catch (error) {
        console.error('Health check failed:', error);
        res.status(500).json({
            status: 'unhealthy',
            error: error instanceof Error ? error.message : 'Unknown error',
            timestamp: new Date().toISOString()
        });
    }
});
// Google Places autocomplete proxy (rate limit & API key protection handled server-side)
// GET /api/places/autocomplete?input=...&sessionToken=optional
exports.app.get('/api/places/autocomplete', async (req, res) => {
    try {
        const { input, sessionToken, language } = req.query;
        if (!input || !String(input).trim())
            return res.json([]);
        const predictions = await (0, googlePlaces_1.placesAutocomplete)(String(input), { sessionToken: sessionToken, language });
        res.json(predictions);
    }
    catch (e) {
        console.error('Places autocomplete error', e);
        res.status(500).json({ error: 'Autocomplete failed' });
    }
});
// Google Places details -> structured Location preview (not persisted)
// GET /api/places/:placeId
exports.app.get('/api/places/details/:placeId', async (req, res) => {
    try {
        const { placeId } = req.params;
        if (!placeId)
            return res.status(400).json({ error: 'placeId required' });
        const details = await (0, googlePlaces_1.placeDetails)(placeId);
        if (!details)
            return res.status(404).json({ error: 'Not found' });
        const loc = (0, googlePlaces_1.parseLocationFromPlace)(details);
        res.json({ placeId: details.placeId, formattedAddress: details.formattedAddress, location: loc });
    }
    catch (e) {
        console.error('Place details error', e);
        res.status(500).json({ error: 'Place details failed' });
    }
});
// Legacy geohash decode endpoint (for backward compatibility tests)
exports.app.get('/api/geohash/decode', (req, res) => {
    const { hash } = req.query;
    if (!hash)
        return res.status(400).json({ error: 'hash required' });
    try {
        const { decodeCenter } = require('./services/geolocation');
        const center = decodeCenter(String(hash));
        if (!center)
            return res.status(404).json({ error: 'invalid hash' });
        return res.json({ center });
    }
    catch (e) {
        return res.status(500).json({ error: 'decode failed' });
    }
});
// Enhanced pulses listing with optional filters & distance sorting
// Query params supported:
//   search=free text (matches title/description/tags)
//   tags=comma,separated,list (matches any)
//   lat=..&lng=..&radiusKm=.. (distance prefilter + distanceKm field + sort)
//   before=ISO8601 (eventTime before)
//   after=ISO8601 (eventTime after)
//   limit=number (default 100, max 300)
exports.app.get('/api/pulses', async (req, res) => {
    try {
        const { search, tags, lat, lng, radiusKm, before, after, limit, active } = req.query;
        // Base where clause (public pulses only for now)
        const where = { isPublic: true };
        // Text search
        if (search && search.trim()) {
            where.OR = [
                { title: { contains: search, mode: 'insensitive' } },
                { description: { contains: search, mode: 'insensitive' } },
                { tags: { has: search } }, // direct tag exact match
            ];
        }
        // Tag filtering (ANY of provided tags)
        if (tags) {
            const tagList = tags.split(',').map(t => t.trim()).filter(Boolean);
            if (tagList.length) {
                where.tags = { hasSome: tagList };
            }
        }
        // Time window filters
        if (before) {
            const d = new Date(before);
            if (!isNaN(d.getTime()))
                where.eventTime = { ...(where.eventTime || {}), lte: d };
        }
        if (after) {
            const d = new Date(after);
            if (!isNaN(d.getTime()))
                where.eventTime = { ...(where.eventTime || {}), gte: d };
        }
        // Distance prefilter via bounding box if lat/lng present
        let latitude;
        let longitude;
        let radius;
        if (lat !== undefined && lng !== undefined) {
            latitude = parseFloat(lat);
            longitude = parseFloat(lng);
            if (!isNaN(latitude) && !isNaN(longitude)) {
                radius = radiusKm ? parseFloat(radiusKm) : 25; // default 25 km
                if (isNaN(radius) || radius <= 0)
                    radius = 25;
                const latDelta = radius / 111; // ~111km per degree latitude
                const lngDelta = radius / (111 * Math.cos(latitude * Math.PI / 180));
                const minLat = latitude - latDelta;
                const maxLat = latitude + latDelta;
                const minLng = longitude - lngDelta;
                const maxLng = longitude + lngDelta;
                // Only pulses with a location inside bounding box (skip null location pulses)
                where.location = { is: { latitude: { gte: minLat, lte: maxLat }, longitude: { gte: minLng, lte: maxLng } } };
            }
        }
        const take = (() => {
            const raw = limit ? parseInt(limit, 10) : 100;
            if (isNaN(raw) || raw < 1)
                return 100;
            return Math.min(raw, 300);
        })();
        // Active window filtering
        const now = new Date();
        if (active === 'now') {
            where.AND = [...(where.AND || []), { activeFrom: { lte: now } }, { OR: [{ activeUntil: null }, { activeUntil: { gte: now } }] }];
        }
        else if (active === 'future') {
            where.OR = [...(where.OR || []), { activeFrom: { gt: now } }];
        }
        else if (active === 'past') {
            where.AND = [...(where.AND || []), { activeUntil: { lt: now } }];
        }
        const pulses = await prisma.pulse.findMany({
            where,
            include: {
                author: { select: { id: true, displayName: true, email: true, profileImageUrl: true, locationLabel: true } },
                participants: { select: { id: true, displayName: true, email: true, profileImageUrl: true } },
                location: true,
            },
            orderBy: [{ activeFrom: 'asc' }, { eventTime: 'asc' }],
            take,
        });
        // If coordinates provided, compute distanceKm & filter strictly by radius (haversine)
        if (latitude !== undefined && longitude !== undefined && radius !== undefined) {
            const enriched = pulses.map(p => {
                if (!p.location)
                    return null; // skip pulses lacking structured location when distance filtering
                const d = (0, geolocation_1.haversineKm)(p.location.latitude, p.location.longitude, latitude, longitude);
                if (d > radius)
                    return null;
                p.distanceKm = d;
                return p;
            }).filter(Boolean);
            enriched.sort((a, b) => (a.distanceKm ?? 0) - (b.distanceKm ?? 0));
            return res.json(enriched);
        }
        const now2 = new Date();
        res.json(pulses.map(p => ({
            ...p,
            isActive: p.activeFrom <= now2 && (!p.activeUntil || p.activeUntil >= now2),
            activeWindow: { from: p.activeFrom, until: p.activeUntil }
        })));
    }
    catch (error) {
        console.error('Error fetching pulses:', error);
        res.status(500).json({ error: 'Failed to fetch pulses' });
    }
});
// Geospatial: find nearby pulses using bounding box + haversine (public pulses only)
// NOTE: Must be defined BEFORE parameterized '/api/pulses/:id' to avoid 'nearby' being treated as an id.
exports.app.get('/api/pulses/nearby', async (req, res) => {
    try {
        const { lat, lng, radiusKm = '5' } = req.query;
        if (!lat || !lng)
            return res.status(400).json({ error: 'lat and lng are required' });
        const latitude = parseFloat(lat);
        const longitude = parseFloat(lng);
        const radius = parseFloat(String(radiusKm));
        if ([latitude, longitude, radius].some(v => isNaN(v)))
            return res.status(400).json({ error: 'Invalid numeric parameters' });
        const latDelta = radius / 111;
        const lngDelta = radius / (111 * Math.cos(latitude * Math.PI / 180));
        const minLat = latitude - latDelta;
        const maxLat = latitude + latDelta;
        const minLng = longitude - lngDelta;
        const maxLng = longitude + lngDelta;
        const pulses = await prisma.pulse.findMany({
            where: { isPublic: true, location: { is: { latitude: { gte: minLat, lte: maxLat }, longitude: { gte: minLng, lte: maxLng } } } },
            include: { author: { select: { id: true, displayName: true, email: true, profileImageUrl: true } }, participants: { select: { id: true, displayName: true, email: true, profileImageUrl: true } }, location: true },
            take: 400
        });
        const within = pulses.map(p => {
            if (!p.location)
                return null;
            const d = (0, geolocation_1.haversineKm)(p.location.latitude, p.location.longitude, latitude, longitude);
            p.distanceKm = d;
            return d <= radius ? p : null;
        }).filter(Boolean).sort((a, b) => a.distanceKm - b.distanceKm).slice(0, 300);
        res.json({ center: { latitude, longitude }, radiusKm: radius, count: within.length, pulses: within });
    }
    catch (e) {
        console.error('nearby pulses error', e);
        res.status(500).json({ error: 'Failed nearby pulses search' });
    }
});
// Combined map overview (public pulses + users) for dual-layer map
// GET /api/map/overview?lat=&lng=&radiusKm=5&layers=events,people
// layers param optional (comma list) default both. Returns pulses (public, within radius) and users (with location, within radius)
exports.app.get('/api/map/overview', async (req, res) => {
    try {
        const { lat, lng, radiusKm = '5', layers } = req.query;
        if (!lat || !lng)
            return res.status(400).json({ error: 'lat and lng are required' });
        const latitude = parseFloat(lat);
        const longitude = parseFloat(lng);
        let radius = parseFloat(String(radiusKm));
        if ([latitude, longitude, radius].some(v => isNaN(v)))
            return res.status(400).json({ error: 'Invalid numeric parameters' });
        if (radius <= 0)
            radius = 5;
        // bounding box
        const latDelta = radius / 111;
        const lngDelta = radius / (111 * Math.cos(latitude * Math.PI / 180));
        const minLat = latitude - latDelta;
        const maxLat = latitude + latDelta;
        const minLng = longitude - lngDelta;
        const maxLng = longitude + lngDelta;
        const wantEvents = !layers || layers.split(',').includes('events') || layers.split(',').includes('pulses');
        const wantPeople = !layers || layers.split(',').includes('people') || layers.split(',').includes('users');
        const now = new Date();
        const promises = [];
        if (wantEvents) {
            const p = prisma.pulse.findMany({
                where: {
                    isPublic: true,
                    location: { is: { latitude: { gte: minLat, lte: maxLat }, longitude: { gte: minLng, lte: maxLng } } }
                },
                include: { author: { select: { id: true, displayName: true, profileImageUrl: true } }, participants: { select: { id: true } }, location: true },
                take: 500
            }).then(list => list.map(p => {
                if (!p.location)
                    return null;
                const d = (0, geolocation_1.haversineKm)(p.location.latitude, p.location.longitude, latitude, longitude);
                if (d > radius)
                    return null;
                return {
                    id: p.id,
                    title: p.title,
                    category: p.category || (p.tags && p.tags.length ? p.tags[0] : undefined),
                    location: { lat: p.location.latitude, lng: p.location.longitude },
                    attendeeCount: (p.participants?.length || 0) + 1,
                    eventTime: p.eventTime,
                    activeFrom: p.activeFrom,
                    activeUntil: p.activeUntil,
                    isActive: p.activeFrom <= now && (!p.activeUntil || p.activeUntil >= now),
                    distanceKm: d,
                };
            }).filter(Boolean).sort((a, b) => a.distanceKm - b.distanceKm));
            promises.push(p);
        }
        else {
            promises.push(Promise.resolve([]));
        }
        if (wantPeople) {
            const u = prisma.user.findMany({
                where: { location: { latitude: { gte: minLat, lte: maxLat }, longitude: { gte: minLng, lte: maxLng } } },
                select: { id: true, displayName: true, profileImageUrl: true, bio: true, locationUpdatedAt: true, location: { select: { latitude: true, longitude: true } } },
                take: 800
            }).then(list => list.map(u => {
                if (!u.location)
                    return null;
                const d = (0, geolocation_1.haversineKm)(u.location.latitude, u.location.longitude, latitude, longitude);
                if (d > radius)
                    return null;
                return {
                    id: u.id,
                    name: u.displayName,
                    avatarUrl: u.profileImageUrl,
                    status: u.bio,
                    location: { lat: u.location.latitude, lng: u.location.longitude },
                    distanceKm: d,
                    isActive: u.locationUpdatedAt ? (now.getTime() - new Date(u.locationUpdatedAt).getTime()) < 10 * 60 * 1000 : false,
                };
            }).filter(Boolean).sort((a, b) => a.distanceKm - b.distanceKm));
            promises.push(u);
        }
        else {
            promises.push(Promise.resolve([]));
        }
        const [pulses, users] = await Promise.all(promises);
        res.json({ center: { latitude, longitude }, radiusKm: radius, counts: { pulses: pulses.length, users: users.length }, pulses, users });
    }
    catch (e) {
        console.error('map overview error', e);
        res.status(500).json({ error: 'Failed map overview' });
    }
});
// Public pulses listing (global discovery) limited, only pulses with a location
exports.app.get('/api/pulses/public', async (req, res) => {
    try {
        const limitRaw = String(req.query.limit ?? '50');
        const limit = Math.min(Math.max(parseInt(limitRaw, 10) || 50, 1), 200);
        const pulses = await prisma.pulse.findMany({
            where: { isPublic: true, location: { isNot: null } },
            include: {
                author: { select: { id: true, displayName: true, profileImageUrl: true } },
                participants: { select: { id: true, displayName: true, profileImageUrl: true } },
                location: { select: { id: true, name: true, city: true, country: true, latitude: true, longitude: true } }
            },
            orderBy: { createdAt: 'desc' },
            take: limit
        });
        res.json({ count: pulses.length, pulses });
    }
    catch (e) {
        console.error('public pulses list error', e);
        res.status(500).json({ error: 'Failed public pulses list' });
    }
});
// New route to get a specific pulse by ID (authentication required)
exports.app.get('/api/pulses/:id', auth_2.authenticateUser, async (req, res) => {
    try {
        const { id } = req.params;
        const userId = req.user.id;
        // Find the pulse with author and participants information
        const pulse = await prisma.pulse.findUnique({
            where: { id },
            include: {
                author: {
                    select: {
                        id: true,
                        displayName: true,
                        email: true,
                        profileImageUrl: true,
                    }
                },
                participants: {
                    select: {
                        id: true,
                        displayName: true,
                        email: true,
                        profileImageUrl: true,
                    }
                },
                location: true,
            }
        });
        if (!pulse) {
            return res.status(404).json({ error: 'Pulse not found' });
        }
        // Check if the current user is a participant
        const isParticipant = pulse.participants.some((participant) => participant.id === req.user.id);
        // Check if the current user is the author
        const isAuthor = pulse.authorId === req.user.id;
        // Author is also considered a participant
        const isParticipantOrAuthor = isParticipant || isAuthor;
        // Calculate total participants (author + participants)
        const totalParticipants = pulse.participants.length + 1; // +1 for author
        // Check if pulse has reached max participants
        const isFullyBooked = pulse.maxParticipants ? totalParticipants >= pulse.maxParticipants : false;
        // Add user-specific information to the response
        const nowDetail = new Date();
        const responseData = {
            ...pulse,
            isParticipant: isParticipantOrAuthor, // Author is also considered a participant
            isAuthor,
            canJoin: !isParticipantOrAuthor && pulse.isPublic && !isFullyBooked,
            totalParticipants,
            isFullyBooked,
            isActive: pulse.activeFrom <= nowDetail && (!pulse.activeUntil || pulse.activeUntil >= nowDetail),
            activeWindow: { from: pulse.activeFrom, until: pulse.activeUntil },
            // Include all participants including author for display
            allParticipants: [
                {
                    id: pulse.author.id,
                    displayName: pulse.author.displayName,
                    email: pulse.author.email,
                    profileImageUrl: pulse.author.profileImageUrl,
                    isAuthor: true,
                },
                ...pulse.participants.map(p => ({
                    ...p,
                    isAuthor: false,
                }))
            ]
        };
        console.log('Pulse detail response:', {
            pulseId: id,
            userId,
            userIdType: typeof userId,
            userFirebaseUid: req.user.firebaseUid,
            isParticipant: isParticipantOrAuthor,
            isAuthor,
            canJoin: responseData.canJoin,
            isPublic: pulse.isPublic,
            totalParticipants,
            isFullyBooked,
            maxParticipants: pulse.maxParticipants,
            participantIds: pulse.participants.map(p => p.id),
            participantIdTypes: pulse.participants.map(p => typeof p.id),
            authorId: pulse.authorId,
            authorIdType: typeof pulse.authorId,
            // Additional debug info
            isParticipantCheck: pulse.participants.some(p => p.id === req.user.id),
            isAuthorCheck: pulse.authorId === req.user.id,
            isParticipantOrAuthorCheck: isParticipantOrAuthor,
            canJoinCalculation: {
                notParticipantOrAuthor: !isParticipantOrAuthor,
                isPublic: pulse.isPublic,
                notFullyBooked: !isFullyBooked,
                finalCanJoin: !isParticipantOrAuthor && pulse.isPublic && !isFullyBooked
            }
        });
        res.json(responseData);
    }
    catch (error) {
        console.error('Error fetching pulse:', error);
        res.status(500).json({ error: 'Failed to fetch pulse' });
    }
});
// New route to search pulses (no authentication required for fetching)
exports.app.get('/api/pulses/search', async (req, res) => {
    try {
        // Accept either ?query= or ?search= to align with various client expectations
        const qParam = req.query.query ?? req.query.search;
        const term = typeof qParam === 'string' ? qParam.trim() : '';
        if (!term) {
            return res.json([]); // empty term -> empty list (avoid 400 so UI can debounce)
        }
        const pulses = await prisma.pulse.findMany({
            where: {
                isPublic: true,
                OR: [
                    { title: { contains: term, mode: 'insensitive' } },
                    { description: { contains: term, mode: 'insensitive' } },
                    { tags: { has: term } },
                ],
            },
            include: {
                author: { select: { id: true, displayName: true, email: true, profileImageUrl: true, locationLabel: true } },
                participants: { select: { id: true, displayName: true, email: true, profileImageUrl: true } },
                location: true,
            },
            orderBy: { eventTime: 'asc' },
            take: 100,
        });
        res.json(pulses);
    }
    catch (error) {
        console.error('Error searching pulses:', error);
        res.status(500).json({ error: 'Failed to search pulses' });
    }
});
// New route to create a pulse (authentication required)
exports.app.post('/api/pulses', auth_2.authenticateUser, async (req, res) => {
    try {
        const { title, description, eventTime, isPublic, tags, imageUrl, placeId, activeFrom, activeUntil, activeDurationMinutes } = req.body;
        // Validate required fields
        if (!title || !eventTime) {
            return res.status(400).json({ error: 'Title and eventTime are required' });
        }
        // Active window validation (optional)
        let activeFromDate;
        let activeUntilDate;
        const eventTimeDate = new Date(eventTime);
        if (isNaN(eventTimeDate.getTime()))
            return res.status(400).json({ error: 'Invalid eventTime' });
        // Parse provided values if any
        if (activeFrom) {
            const d = new Date(activeFrom);
            if (isNaN(d.getTime()))
                return res.status(400).json({ error: 'Invalid activeFrom value' });
            activeFromDate = d;
        }
        if (activeUntil) {
            const d = new Date(activeUntil);
            if (isNaN(d.getTime()))
                return res.status(400).json({ error: 'Invalid activeUntil value' });
            activeUntilDate = d;
        }
        // If not provided, derive window: start at eventTime, end at eventTime + duration (default 120 min)
        const durationMinutesNum = (() => {
            if (activeDurationMinutes === undefined || activeDurationMinutes === null)
                return 120; // default 2h
            const n = parseInt(String(activeDurationMinutes), 10);
            return isNaN(n) || n < 1 ? 120 : Math.min(n, 24 * 60); // cap at 24h
        })();
        if (!activeFromDate)
            activeFromDate = eventTimeDate;
        if (!activeUntilDate)
            activeUntilDate = new Date(activeFromDate.getTime() + durationMinutesNum * 60 * 1000);
        if (activeFromDate && activeUntilDate && activeUntilDate < activeFromDate) {
            return res.status(400).json({ error: 'activeUntil must be after activeFrom' });
        }
        // Optional: placeId or raw coordinates -> create structured Location record
        let locationId;
        try {
            if (placeId) {
                const details = await (0, googlePlaces_1.placeDetails)(placeId);
                if (details) {
                    // Try reuse existing Location by placeId
                    const existingLoc = await prisma.location.findFirst({ where: { placeId: details.placeId } }).catch(() => null);
                    if (existingLoc) {
                        locationId = existingLoc.id;
                    }
                    else {
                        const parsed = (0, googlePlaces_1.parseLocationFromPlace)(details);
                        const loc = await prisma.location.create({ data: {
                                ...parsed,
                                placeId: details.placeId,
                                formattedAddress: details.formattedAddress || null,
                                types: details.types || [],
                                raw: details.addressComponents,
                                locationSource: 'GOOGLE_PLACES'
                            } });
                        locationId = loc.id;
                    }
                }
            }
            else if (req.body.latitude !== undefined && req.body.longitude !== undefined) {
                const latNum = parseFloat(req.body.latitude);
                const lngNum = parseFloat(req.body.longitude);
                if (!isNaN(latNum) && !isNaN(lngNum)) {
                    const rev = await (0, geolocation_1.reverseGeocode)(latNum, lngNum);
                    if (rev) {
                        const loc = await prisma.location.create({ data: {
                                name: rev.location.name || rev.label,
                                street: rev.location.street,
                                city: rev.location.city,
                                state: rev.location.state,
                                postalCode: rev.location.postalCode,
                                country: rev.location.country,
                                latitude: rev.location.latitude,
                                longitude: rev.location.longitude,
                                locationSource: 'REVERSE_GEOCODE',
                                accuracyMeters: typeof req.body.accuracyMeters === 'number' ? req.body.accuracyMeters : null
                            } });
                        locationId = loc.id;
                    }
                }
            }
        }
        catch (e) {
            console.warn('Location resolution failed', e);
        }
        const pulse = await prisma.pulse.create({
            data: {
                title,
                description: description || '',
                eventTime: eventTimeDate,
                activeFrom: activeFromDate,
                activeUntil: activeUntilDate,
                isPublic: isPublic !== undefined ? isPublic : true,
                tags: Array.isArray(tags) ? tags : (tags || []),
                imageUrl: imageUrl || null,
                author: { connect: { id: req.user.id } },
                ...(locationId ? { location: { connect: { id: locationId } } } : {})
            },
            include: {
                author: {
                    select: { id: true, displayName: true, email: true, locationLabel: true }
                },
                location: true
            }
        });
        // Ensure a backing group conversation exists for this pulse (non-fatal if fails)
        try {
            await prisma.conversation.create({
                data: {
                    pulse: { connect: { id: pulse.id } },
                    isGroup: true,
                    name: pulse.title,
                    avatarUrl: pulse.imageUrl ?? null,
                    participants: { connect: { id: pulse.authorId } },
                }
            });
        }
        catch (chatCreateErr) {
            // Unique constraint on pulseId prevents duplicates; ignore if already exists
            if (process.env.NODE_ENV !== 'production') {
                console.warn('Pulse conversation creation skipped/failed:', chatCreateErr?.message || chatCreateErr);
            }
        }
        const now = new Date();
        const response = {
            ...pulse,
            isActive: pulse.activeFrom <= now && (!pulse.activeUntil || pulse.activeUntil >= now),
            activeWindow: { from: pulse.activeFrom, until: pulse.activeUntil },
            defaultsApplied: { derivedActiveFrom: !!(!activeFrom && activeFromDate), derivedActiveUntil: !!(!activeUntil && activeUntilDate), durationMinutes: durationMinutesNum }
        };
        res.status(201).json(response);
    }
    catch (error) {
        console.error('Error creating pulse:', error);
        res.status(500).json({ error: 'Failed to create pulse' });
    }
});
// (Duplicate nearby route removed; definition moved earlier before parameter route)
// New route to update a pulse (authentication required)
exports.app.put('/api/pulses/:id', auth_2.authenticateUser, async (req, res) => {
    try {
        const { id } = req.params;
        const { title, description, eventTime, isPublic, tags, imageUrl, activeFrom, activeUntil } = req.body;
        // Check if pulse exists and user is the author
        const existingPulse = await prisma.pulse.findUnique({
            where: { id },
            include: { author: true }
        });
        if (!existingPulse) {
            return res.status(404).json({ error: 'Pulse not found' });
        }
        if (existingPulse.authorId !== req.user.id) {
            return res.status(403).json({ error: 'Not authorized to update this pulse' });
        }
        // Update structured location if placeId or coordinates provided
        let newLocationConnect = undefined;
        try {
            if (req.body.placeId) {
                const details = await (0, googlePlaces_1.placeDetails)(req.body.placeId);
                if (details) {
                    const existingLoc = await prisma.location.findFirst({ where: { placeId: details.placeId } }).catch(() => null);
                    if (existingLoc) {
                        newLocationConnect = { connect: { id: existingLoc.id } };
                    }
                    else {
                        const parsed = (0, googlePlaces_1.parseLocationFromPlace)(details);
                        const loc = await prisma.location.create({ data: { ...parsed, placeId: details.placeId, formattedAddress: details.formattedAddress || null, raw: details.addressComponents, types: details.types || [], locationSource: 'GOOGLE_PLACES' } });
                        newLocationConnect = { connect: { id: loc.id } };
                    }
                }
            }
            else if (req.body.latitude !== undefined && req.body.longitude !== undefined) {
                const latNum = parseFloat(req.body.latitude);
                const lngNum = parseFloat(req.body.longitude);
                if (!isNaN(latNum) && !isNaN(lngNum)) {
                    const rev = await (0, geolocation_1.reverseGeocode)(latNum, lngNum);
                    if (rev) {
                        const loc = await prisma.location.create({ data: { name: rev.location.name || rev.label, street: rev.location.street, city: rev.location.city, state: rev.location.state, postalCode: rev.location.postalCode, country: rev.location.country, latitude: rev.location.latitude, longitude: rev.location.longitude, locationSource: 'REVERSE_GEOCODE', accuracyMeters: typeof req.body.accuracyMeters === 'number' ? req.body.accuracyMeters : null } });
                        newLocationConnect = { connect: { id: loc.id } };
                    }
                }
            }
        }
        catch (e) {
            console.warn('Location update resolution failed', e);
        }
        // Active window validation
        let activeFromDate;
        let activeUntilDate;
        if (activeFrom !== undefined) {
            if (activeFrom === null || activeFrom === '') {
                activeFromDate = undefined; // will not change
            }
            else {
                const d = new Date(activeFrom);
                if (isNaN(d.getTime()))
                    return res.status(400).json({ error: 'Invalid activeFrom value' });
                activeFromDate = d;
            }
        }
        if (activeUntil !== undefined) {
            if (activeUntil === null || activeUntil === '') {
                activeUntilDate = null; // explicit clear
            }
            else {
                const d = new Date(activeUntil);
                if (isNaN(d.getTime()))
                    return res.status(400).json({ error: 'Invalid activeUntil value' });
                activeUntilDate = d;
            }
        }
        if (activeFromDate && activeUntilDate && activeUntilDate < activeFromDate) {
            return res.status(400).json({ error: 'activeUntil must be after activeFrom' });
        }
        const updatedPulse = await prisma.pulse.update({
            where: { id },
            data: {
                title: title !== undefined ? title : existingPulse.title,
                description: description !== undefined ? description : existingPulse.description,
                eventTime: eventTime !== undefined ? new Date(eventTime) : existingPulse.eventTime,
                isPublic: isPublic !== undefined ? isPublic : existingPulse.isPublic,
                tags: tags !== undefined ? tags : existingPulse.tags,
                imageUrl: imageUrl !== undefined ? imageUrl : existingPulse.imageUrl,
                ...(activeFromDate !== undefined && { activeFrom: activeFromDate }),
                ...(activeUntilDate !== undefined && { activeUntil: activeUntilDate }),
                ...(newLocationConnect && { location: newLocationConnect }),
            },
            include: {
                author: {
                    select: {
                        id: true,
                        displayName: true,
                        email: true,
                        profileImageUrl: true,
                        locationLabel: true,
                    }
                },
                participants: {
                    select: {
                        id: true,
                        displayName: true,
                        email: true,
                        profileImageUrl: true,
                    }
                },
                location: true,
            }
        });
        // Sync conversation metadata if needed (non-fatal)
        try {
            if (title !== undefined || imageUrl !== undefined) {
                const convo = await prisma.conversation.findFirst({ where: { pulseId: id } });
                if (convo) {
                    await prisma.conversation.update({
                        where: { id: convo.id },
                        data: {
                            name: title !== undefined ? title : undefined,
                            avatarUrl: imageUrl !== undefined ? imageUrl : undefined,
                        }
                    });
                }
            }
        }
        catch (e) {
            console.error('Failed to sync conversation metadata after pulse PUT edit', e);
        }
        // Return consistent enriched response like GET /api/pulses/:id
        const totalParticipants = updatedPulse.participants.length + 1; // +1 for author
        const isFullyBooked = updatedPulse.maxParticipants ? totalParticipants >= updatedPulse.maxParticipants : false;
        const nowPut = new Date();
        const responseData = {
            ...updatedPulse,
            isParticipant: true, // author is participant
            isAuthor: true,
            canJoin: false,
            totalParticipants,
            isFullyBooked,
            allParticipants: [
                {
                    id: updatedPulse.author.id,
                    displayName: updatedPulse.author.displayName,
                    email: updatedPulse.author.email,
                    profileImageUrl: updatedPulse.author.profileImageUrl,
                    isAuthor: true,
                },
                ...updatedPulse.participants.map((p) => ({ ...p, isAuthor: false }))
            ],
            isActive: updatedPulse.activeFrom <= nowPut && (!updatedPulse.activeUntil || updatedPulse.activeUntil >= nowPut),
            activeWindow: { from: updatedPulse.activeFrom, until: updatedPulse.activeUntil }
        };
        res.json(responseData);
    }
    catch (error) {
        console.error('Error updating pulse:', error);
        res.status(500).json({ error: 'Failed to update pulse' });
    }
});
// PATCH variant (partial update) for pulse edits – some clients may use PATCH instead of PUT
exports.app.patch('/api/pulses/:id', auth_2.authenticateUser, async (req, res) => {
    try {
        const { id } = req.params;
        const { title, description, eventTime, isPublic, tags, imageUrl, maxParticipants, category, difficulty, price, currency, activeFrom, activeUntil } = req.body;
        const existingPulse = await prisma.pulse.findUnique({ where: { id } });
        if (!existingPulse)
            return res.status(404).json({ error: 'Pulse not found' });
        if (existingPulse.authorId !== req.user.id)
            return res.status(403).json({ error: 'Not authorized to update this pulse' });
        // Validate numeric / geo fields only if present
        if (req.body.latitude !== undefined) {
            const latNum = parseFloat(req.body.latitude);
            if (isNaN(latNum) || latNum < -90 || latNum > 90)
                return res.status(400).json({ error: 'Invalid latitude value' });
        }
        if (req.body.longitude !== undefined) {
            const lngNum = parseFloat(req.body.longitude);
            if (isNaN(lngNum) || lngNum < -180 || lngNum > 180)
                return res.status(400).json({ error: 'Invalid longitude value' });
        }
        if (price !== undefined && price !== null) {
            const priceNum = parseFloat(price);
            if (isNaN(priceNum) || priceNum < 0)
                return res.status(400).json({ error: 'Invalid price value' });
        }
        if (maxParticipants !== undefined && maxParticipants !== null) {
            const mp = parseInt(maxParticipants, 10);
            if (isNaN(mp) || mp < 1)
                return res.status(400).json({ error: 'Invalid maxParticipants value' });
        }
        // Prepare data object only with provided keys
        const data = {};
        if (title !== undefined)
            data.title = title;
        if (description !== undefined)
            data.description = description;
        if (eventTime !== undefined)
            data.eventTime = new Date(eventTime);
        if (isPublic !== undefined)
            data.isPublic = isPublic;
        if (tags !== undefined) {
            if (!Array.isArray(tags))
                return res.status(400).json({ error: 'Tags must be an array' });
            data.tags = tags;
        }
        if (imageUrl !== undefined)
            data.imageUrl = imageUrl;
        if (maxParticipants !== undefined)
            data.maxParticipants = parseInt(maxParticipants, 10);
        if (category !== undefined)
            data.category = category;
        if (difficulty !== undefined)
            data.difficulty = difficulty;
        if (price !== undefined)
            data.price = parseFloat(price);
        if (currency !== undefined)
            data.currency = currency;
        if (activeFrom !== undefined) {
            if (activeFrom === null || activeFrom === '') {
                // no-op, cannot unset because field non-nullable; ignore
            }
            else {
                const d = new Date(activeFrom);
                if (isNaN(d.getTime()))
                    return res.status(400).json({ error: 'Invalid activeFrom value' });
                data.activeFrom = d;
            }
        }
        if (activeUntil !== undefined) {
            if (activeUntil === null || activeUntil === '') {
                data.activeUntil = null;
            }
            else {
                const d = new Date(activeUntil);
                if (isNaN(d.getTime()))
                    return res.status(400).json({ error: 'Invalid activeUntil value' });
                data.activeUntil = d;
            }
        }
        if (data.activeFrom && data.activeUntil && data.activeUntil < data.activeFrom) {
            return res.status(400).json({ error: 'activeUntil must be after activeFrom' });
        }
        // If placeId or coordinates provided, attach new Location
        try {
            if (req.body.placeId) {
                const details = await (0, googlePlaces_1.placeDetails)(req.body.placeId);
                if (details) {
                    const existingLoc = await prisma.location.findFirst({ where: { placeId: details.placeId } }).catch(() => null);
                    if (existingLoc) {
                        data.location = { connect: { id: existingLoc.id } };
                    }
                    else {
                        const parsed = (0, googlePlaces_1.parseLocationFromPlace)(details);
                        const loc = await prisma.location.create({ data: { ...parsed, placeId: details.placeId, formattedAddress: details.formattedAddress || null, raw: details.addressComponents, types: details.types || [], locationSource: 'GOOGLE_PLACES' } });
                        data.location = { connect: { id: loc.id } };
                    }
                }
            }
            else if (req.body.latitude !== undefined && req.body.longitude !== undefined) {
                const latNum = parseFloat(req.body.latitude);
                const lngNum = parseFloat(req.body.longitude);
                if (!isNaN(latNum) && !isNaN(lngNum)) {
                    const rev = await (0, geolocation_1.reverseGeocode)(latNum, lngNum);
                    if (rev) {
                        const loc = await prisma.location.create({ data: { name: rev.location.name || rev.label, street: rev.location.street, city: rev.location.city, state: rev.location.state, postalCode: rev.location.postalCode, country: rev.location.country, latitude: rev.location.latitude, longitude: rev.location.longitude, locationSource: 'REVERSE_GEOCODE', accuracyMeters: typeof req.body.accuracyMeters === 'number' ? req.body.accuracyMeters : null } });
                        data.location = { connect: { id: loc.id } };
                    }
                }
            }
        }
        catch (e) {
            console.warn('Location patch resolution failed', e);
        }
        const updated = await prisma.pulse.update({
            where: { id },
            data,
            include: {
                author: { select: { id: true, displayName: true, email: true, profileImageUrl: true, locationLabel: true } },
                participants: { select: { id: true, displayName: true, email: true, profileImageUrl: true } },
                location: true
            }
        });
        // If title/image changed, sync the pulse conversation metadata (non-fatal)
        try {
            if (data.title !== undefined || data.imageUrl !== undefined) {
                const convo = await prisma.conversation.findFirst({ where: { pulseId: id } });
                if (convo) {
                    await prisma.conversation.update({
                        where: { id: convo.id },
                        data: {
                            name: data.title !== undefined ? data.title : undefined,
                            avatarUrl: data.imageUrl !== undefined ? data.imageUrl : undefined,
                        }
                    });
                }
            }
        }
        catch (e) {
            console.error('Failed to sync conversation metadata after pulse edit', e);
        }
        // Mirror detailed response style from GET /api/pulses/:id
        const isAuthor = true; // already verified
        const isParticipant = true; // author implicitly participant
        const nowPatch = new Date();
        const responseData = {
            ...updated,
            isParticipant,
            isAuthor,
            canJoin: false,
            totalParticipants: updated.participants.length + 1,
            isFullyBooked: updated.maxParticipants ? (updated.participants.length + 1) >= updated.maxParticipants : false,
            allParticipants: [
                { id: updated.author.id, displayName: updated.author.displayName, email: updated.author.email, profileImageUrl: updated.author.profileImageUrl, isAuthor: true },
                ...updated.participants.map((p) => ({ ...p, isAuthor: false }))
            ],
            isActive: updated.activeFrom <= nowPatch && (!updated.activeUntil || updated.activeUntil >= nowPatch),
            activeWindow: { from: updated.activeFrom, until: updated.activeUntil }
        };
        res.json(responseData);
    }
    catch (err) {
        console.error('Error patching pulse:', err);
        res.status(500).json({ error: 'Failed to update pulse' });
    }
});
// New route to join a pulse (authentication required)
exports.app.post('/api/pulses/:id/join', auth_2.authenticateUser, async (req, res) => {
    try {
        const { id } = req.params;
        const userId = req.user.id;
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
        const isAlreadyParticipant = pulse.participants.some((participant) => participant.id === req.user.id);
        if (isAlreadyParticipant) {
            return res.status(400).json({ error: 'Already joined this pulse' });
        }
        // Check if user is the author
        if (pulse.authorId === req.user.id) {
            return res.status(400).json({ error: 'Cannot join your own pulse' });
        }
        // Add user as participant and update participant count
        const updatedPulse = await prisma.pulse.update({
            where: { id },
            data: {
                participants: {
                    connect: { id: req.user.id },
                },
                currentParticipants: {
                    increment: 1,
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
        // Ensure a pulse group conversation exists and add the joining user
        try {
            let convo = await prisma.conversation.findFirst({
                where: { pulseId: id },
                include: { participants: true },
            });
            if (!convo) {
                convo = await prisma.conversation.create({
                    data: {
                        pulse: { connect: { id } },
                        isGroup: true,
                        name: updatedPulse.title,
                        avatarUrl: updatedPulse.imageUrl ?? null,
                        participants: {
                            connect: [{ id: updatedPulse.authorId }, { id: userId }],
                        },
                    },
                    include: { participants: true },
                });
                // Also add any existing participants if there are more than two
                const others = updatedPulse.participants
                    .map((p) => p.id)
                    .filter((pid) => pid !== updatedPulse.authorId && pid !== userId);
                if (others.length > 0) {
                    await prisma.conversation.update({
                        where: { id: convo.id },
                        data: { participants: { connect: others.map((pid) => ({ id: pid })) } },
                    });
                }
            }
            else {
                const isInConvo = convo.participants.some((p) => p.id === userId);
                if (!isInConvo) {
                    await prisma.conversation.update({
                        where: { id: convo.id },
                        data: { participants: { connect: { id: userId } } },
                    });
                }
            }
            // Emit conversation:updated so clients refresh list
            try {
                // @ts-ignore
                convo.participants.forEach(p => {
                    // @ts-ignore userSockets
                    const sockets = realtime_1.userSockets.get(p.id);
                    if (!sockets)
                        return;
                    // @ts-ignore io
                    sockets.forEach((sid) => io.to(sid).emit('conversation:updated', { conversationId: convo.id }));
                });
            }
            catch (emitErr) {
                console.warn('joinPulse emit conversation:updated failed', emitErr);
            }
        }
        catch (chatErr) {
            console.error('Failed to ensure/add to pulse conversation:', chatErr);
            // Non-fatal
        }
        // Create a notification for the pulse author about the new participant
        try {
            const joinerName = req.user.displayName || req.user.email || 'Someone';
            await prisma.notification.create({
                data: {
                    type: 'PulseJoin',
                    title: 'New participant joined',
                    message: `${joinerName} joined your pulse "${updatedPulse.title}"`,
                    user: { connect: { id: updatedPulse.authorId } },
                    data: {
                        pulseId: updatedPulse.id,
                        participantId: req.user.id,
                    },
                },
            });
        }
        catch (notifyErr) {
            console.error('Failed to create join notification:', notifyErr);
            // Do not fail the main request due to notification errors
        }
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
// New route to leave a pulse (authentication required)
exports.app.post('/api/pulses/:id/leave', auth_2.authenticateUser, async (req, res) => {
    try {
        const { id } = req.params;
        const userId = req.user.id;
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
        // Check if user is a participant
        const isParticipant = pulse.participants.some((participant) => participant.id === req.user.id);
        if (!isParticipant) {
            return res.status(400).json({ error: 'Not a participant of this pulse' });
        }
        // Check if user is the author
        if (pulse.authorId === req.user.id) {
            return res.status(400).json({ error: 'Cannot leave your own pulse' });
        }
        // Remove user as participant and update participant count
        const updatedPulse = await prisma.pulse.update({
            where: { id },
            data: {
                participants: {
                    disconnect: { id: req.user.id },
                },
                currentParticipants: {
                    decrement: 1,
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
        // Remove user from pulse group conversation
        try {
            const convo = await prisma.conversation.findFirst({
                where: { pulseId: id },
            });
            if (convo) {
                await prisma.conversation.update({
                    where: { id: convo.id },
                    data: { participants: { disconnect: { id: userId } } },
                });
            }
        }
        catch (chatErr) {
            console.error('Failed to remove from pulse conversation:', chatErr);
            // Non-fatal
        }
        // Create a notification for the pulse author about the participant leaving
        try {
            const leaverName = req.user.displayName || req.user.email || 'Someone';
            await prisma.notification.create({
                data: {
                    type: 'PulseLeave',
                    title: 'Participant left',
                    message: `${leaverName} left your pulse "${updatedPulse.title}"`,
                    user: { connect: { id: updatedPulse.authorId } },
                    data: {
                        pulseId: updatedPulse.id,
                        participantId: req.user.id,
                    },
                },
            });
        }
        catch (notifyErr) {
            console.error('Failed to create leave notification:', notifyErr);
            // Do not fail the main request due to notification errors
        }
        res.json({
            success: true,
            message: 'Successfully left pulse',
            pulse: updatedPulse,
        });
    }
    catch (error) {
        console.error('Error leaving pulse:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});
// Get pulse participants with detailed information
exports.app.get('/api/pulses/:id/participants', auth_2.authenticateUser, async (req, res) => {
    try {
        const { id } = req.params;
        // Find the pulse with author and participants information
        const pulse = await prisma.pulse.findUnique({
            where: { id },
            include: {
                author: {
                    select: {
                        id: true,
                        displayName: true,
                        email: true,
                        profileImageUrl: true,
                        bio: true,
                        location: true,
                        isVerified: true,
                    }
                },
                participants: {
                    select: {
                        id: true,
                        displayName: true,
                        email: true,
                        profileImageUrl: true,
                        bio: true,
                        location: true,
                        isVerified: true,
                    }
                }
            }
        });
        if (!pulse) {
            return res.status(404).json({ error: 'Pulse not found' });
        }
        // Calculate total participants (author + participants)
        const totalParticipants = pulse.participants.length + 1; // +1 for author
        // Create comprehensive participant list
        const allParticipants = [
            {
                ...pulse.author,
                isAuthor: true,
                joinedAt: pulse.createdAt, // Author joined when pulse was created
            },
            ...pulse.participants.map(p => ({
                ...p,
                isAuthor: false,
                joinedAt: null, // We could add a joinedAt field to the participants relation in the future
            }))
        ];
        const nowParticipants = new Date();
        const responseData = {
            pulseId: id,
            totalParticipants,
            maxParticipants: pulse.maxParticipants,
            isFullyBooked: pulse.maxParticipants ? totalParticipants >= pulse.maxParticipants : false,
            participants: allParticipants,
            author: pulse.author,
            participantCount: pulse.participants.length,
            isActive: pulse.activeFrom <= nowParticipants && (!pulse.activeUntil || pulse.activeUntil >= nowParticipants),
            activeWindow: { from: pulse.activeFrom, until: pulse.activeUntil }
        };
        res.json(responseData);
    }
    catch (error) {
        console.error('Error fetching pulse participants:', error);
        res.status(500).json({ error: 'Failed to fetch pulse participants' });
    }
});
// Get or create the pulse group chat conversation and return its metadata
exports.app.post('/api/pulses/:id/chat', auth_2.authenticateUser, async (req, res) => {
    try {
        const { id } = req.params;
        const me = req.user.id;
        const pulse = await prisma.pulse.findUnique({
            where: { id },
            include: { participants: true, author: true },
        });
        if (!pulse)
            return res.status(404).json({ error: 'Pulse not found' });
        const isParticipant = pulse.participants.some((p) => p.id === me) || pulse.authorId === me;
        if (!isParticipant)
            return res.status(403).json({ error: 'Not a participant' });
        let convo = await prisma.conversation.findFirst({
            where: { pulseId: id },
            include: { participants: { select: { id: true, displayName: true, profileImageUrl: true } } },
        });
        if (!convo) {
            convo = await prisma.conversation.create({
                data: {
                    pulse: { connect: { id } },
                    isGroup: true,
                    name: pulse.title,
                    avatarUrl: pulse.imageUrl ?? null,
                    participants: { connect: [{ id: pulse.authorId }, ...pulse.participants.map((p) => ({ id: p.id }))] },
                },
                include: { participants: { select: { id: true, displayName: true, profileImageUrl: true } } },
            });
        }
        else {
            // Ensure caller is connected (in case they were added to pulse later)
            const inConvo = convo.participants.some((p) => p.id === me);
            if (!inConvo) {
                await prisma.conversation.update({
                    where: { id: convo.id },
                    data: { participants: { connect: { id: me } } },
                });
                // re-read
                convo = await prisma.conversation.findUnique({
                    where: { id: convo.id },
                    include: { participants: { select: { id: true, displayName: true, profileImageUrl: true } } },
                });
            }
        }
        res.json({
            conversationId: convo.id,
            name: convo.name ?? pulse.title,
            avatarUrl: convo.avatarUrl ?? pulse.imageUrl ?? null,
            participants: convo.participants,
        });
        try {
            // @ts-ignore
            convo.participants.forEach(p => {
                // @ts-ignore userSockets
                const sockets = realtime_1.userSockets.get(p.id);
                if (!sockets)
                    return;
                // @ts-ignore io
                sockets.forEach((sid) => io.to(sid).emit('conversation:updated', { conversationId: convo.id }));
            });
        }
        catch (emitErr) {
            console.warn('pulse chat POST emit failed', emitErr);
        }
    }
    catch (e) {
        console.error('pulse chat error', e);
        res.status(500).json({ error: 'Internal server error' });
    }
});
// Idempotent GET variant to fetch pulse chat metadata (mirrors POST semantics without side effects other than ensuring membership)
exports.app.get('/api/pulses/:id/chat', auth_2.authenticateUser, async (req, res) => {
    // Delegate to POST handler logic by calling next route internally
    // Simpler duplicate implementation to avoid refactor now
    try {
        const { id } = req.params;
        const me = req.user.id;
        const pulse = await prisma.pulse.findUnique({ where: { id }, include: { participants: true, author: true } });
        if (!pulse)
            return res.status(404).json({ error: 'Pulse not found' });
        const isParticipant = pulse.participants.some(p => p.id === me) || pulse.authorId === me;
        if (!isParticipant)
            return res.status(403).json({ error: 'Not a participant' });
        let convo = await prisma.conversation.findFirst({ where: { pulseId: id }, include: { participants: { select: { id: true, displayName: true, profileImageUrl: true } } } });
        if (!convo) {
            convo = await prisma.conversation.create({ data: { pulse: { connect: { id } }, isGroup: true, name: pulse.title, avatarUrl: pulse.imageUrl ?? null, participants: { connect: [{ id: pulse.authorId }, ...pulse.participants.map(p => ({ id: p.id }))] } }, include: { participants: { select: { id: true, displayName: true, profileImageUrl: true } } } });
        }
        else {
            const inConvo = convo.participants.some(p => p.id === me);
            if (!inConvo) {
                await prisma.conversation.update({ where: { id: convo.id }, data: { participants: { connect: { id: me } } } });
                convo = await prisma.conversation.findUnique({ where: { id: convo.id }, include: { participants: { select: { id: true, displayName: true, profileImageUrl: true } } } });
            }
        }
        res.json({ conversationId: convo.id, name: convo.name ?? pulse.title, avatarUrl: convo.avatarUrl ?? pulse.imageUrl ?? null, participants: convo.participants });
        try {
            // @ts-ignore
            convo.participants.forEach(p => {
                // @ts-ignore userSockets
                const sockets = realtime_1.userSockets.get(p.id);
                if (!sockets)
                    return;
                // @ts-ignore io
                sockets.forEach((sid) => io.to(sid).emit('conversation:updated', { conversationId: convo.id }));
            });
        }
        catch (emitErr) {
            console.warn('pulse chat GET emit failed', emitErr);
        }
    }
    catch (e) {
        console.error('pulse chat GET error', e);
        res.status(500).json({ error: 'Internal server error' });
    }
});
// Paginated fetch of messages for a pulse's group chat conversation
exports.app.get('/api/pulses/:id/chat/messages', auth_2.authenticateUser, async (req, res) => {
    try {
        const { id } = req.params;
        const me = req.user.id;
        const { cursor, limit = '30' } = req.query;
        const take = Math.max(1, Math.min(parseInt(String(limit), 10) || 30, 100));
        const pulse = await prisma.pulse.findUnique({ where: { id }, include: { participants: true, author: true } });
        if (!pulse)
            return res.status(404).json({ error: 'Pulse not found' });
        const isParticipant = pulse.participants.some(p => p.id === me) || pulse.authorId === me;
        if (!isParticipant)
            return res.status(403).json({ error: 'Not a participant' });
        const convo = await prisma.conversation.findFirst({ where: { pulseId: id } });
        if (!convo)
            return res.json({ messages: [], nextCursor: null });
        const messages = await prisma.message.findMany({ where: { conversationId: convo.id }, orderBy: { createdAt: 'desc' }, take, cursor: cursor ? { id: cursor } : undefined, skip: cursor ? 1 : 0 });
        const ids = messages.map((m) => m.id);
        let reactions = [];
        if (ids.length) {
            reactions = await prisma.messageReaction.findMany({ where: { messageId: { in: ids } }, select: { messageId: true, emoji: true, userId: true } });
        }
        const reactionMap = {};
        reactions.forEach(r => { if (!reactionMap[r.messageId])
            reactionMap[r.messageId] = {}; if (!reactionMap[r.messageId][r.emoji])
            reactionMap[r.messageId][r.emoji] = []; reactionMap[r.messageId][r.emoji].push(r.userId); });
        res.json({ messages: messages.reverse().map((m) => ({ ...m, reactions: reactionMap[m.id] || {} })), nextCursor: messages.length === take ? messages[messages.length - 1].id : null });
    }
    catch (e) {
        console.error('pulse chat messages error', e);
        res.status(500).json({ error: 'Internal server error' });
    }
});
// Post a message to pulse group chat (for clients without WebSocket capability)
exports.app.post('/api/pulses/:id/chat/messages', auth_2.authenticateUser, async (req, res) => {
    try {
        const { id } = req.params;
        const me = req.user.id;
        const { text, imageUrl, videoUrl } = req.body || {};
        if (!text && !imageUrl && !videoUrl)
            return res.status(400).json({ error: 'text or media required' });
        const pulse = await prisma.pulse.findUnique({ where: { id }, include: { participants: true, author: true } });
        if (!pulse)
            return res.status(404).json({ error: 'Pulse not found' });
        const isParticipant = pulse.participants.some(p => p.id === me) || pulse.authorId === me;
        if (!isParticipant)
            return res.status(403).json({ error: 'Not a participant' });
        let convo = await prisma.conversation.findFirst({ where: { pulseId: id }, include: { participants: true } });
        if (!convo) {
            convo = await prisma.conversation.create({ data: { pulse: { connect: { id } }, isGroup: true, name: pulse.title, avatarUrl: pulse.imageUrl ?? null, participants: { connect: [{ id: pulse.authorId }, ...pulse.participants.map(p => ({ id: p.id }))] } } });
        }
        else {
            const inConvo = convo.participants.some((p) => p.id === me);
            if (!inConvo)
                await prisma.conversation.update({ where: { id: convo.id }, data: { participants: { connect: { id: me } } } });
        }
        const msg = await prisma.message.create({ data: { conversationId: convo.id, senderId: me, text: text ?? null, imageUrl: imageUrl ?? null, videoUrl: videoUrl ?? null } });
        await prisma.conversation.update({ where: { id: convo.id }, data: { updatedAt: new Date(), lastMessageText: text ?? (videoUrl ? '[video]' : (imageUrl ? '[image]' : '')), lastSenderId: me } });
        // Emit realtime updates
        try {
            io.to(`conversation:${convo.id}`).emit('message:new', {
                id: msg.id,
                conversationId: msg.conversationId,
                senderId: msg.senderId,
                text: msg.text,
                imageUrl: msg.imageUrl,
                createdAt: msg.createdAt,
                videoUrl: msg.videoUrl,
            });
            convo.participants.forEach(p => {
                const sockets = realtime_1.userSockets.get(p.id);
                if (!sockets)
                    return;
                sockets.forEach((sid) => io.to(sid).emit('conversation:updated', { conversationId: convo.id }));
            });
        }
        catch (_) { }
        res.status(201).json({ message: msg });
    }
    catch (e) {
        console.error('pulse chat message post error', e);
        res.status(500).json({ error: 'Internal server error' });
    }
});
const PORT = process.env.PORT || 3000;
const server = http_1.default.createServer(exports.app);
// Socket.IO setup with CORS for dev
const io = new Server(server, {
    cors: {
        origin: '*',
        methods: ['GET', 'POST']
    }
});
(0, realtime_1.setIo)(io);
// In-memory map of userId -> socketIds (multi-device) is provided by realtime.ts
// In-memory group call rooms: conversationId -> Set<userId>
const activeGroupCalls = new Map();
// Optional metadata for group calls
const groupCallMeta = new Map();
// In-memory dedupe for chat messages: key -> lastTimestamp
// Key format: `${conversationId}|${senderId}|${text}|${imageUrl}|${videoUrl}`
// Entries expire quickly to keep memory bounded.
const recentMessageKeys = new Map();
const MESSAGE_DEDUPE_WINDOW_MS = 2000; // 2 seconds tolerance
io.use(async (socket, next) => {
    try {
        const token = socket.handshake.auth?.token || socket.handshake.headers['authorization']?.toString().replace('Bearer ', '');
        if (!token)
            return next(new Error('Unauthorized'));
        const decoded = await firebase_1.default.auth().verifyIdToken(token);
        const uid = decoded.uid;
        const user = await prisma.user.findUnique({ where: { firebaseUid: uid } });
        if (!user)
            return next(new Error('User not found'));
        socket.user = user;
        try {
            console.log('[socket] auth ok', { userId: user.id, socketId: socket.id });
        }
        catch (_) { }
        next();
    }
    catch (e) {
        next(new Error('Unauthorized'));
    }
});
io.on('connection', (socket) => {
    const user = socket.user;
    if (!user)
        return socket.disconnect(true);
    // Track connections
    if (!realtime_1.userSockets.has(user.id))
        realtime_1.userSockets.set(user.id, new Set());
    realtime_1.userSockets.get(user.id).add(socket.id);
    try {
        console.log('[socket] connected', { userId: user.id, socketId: socket.id, socketsForUser: Array.from(realtime_1.userSockets.get(user.id) || []) });
    }
    catch (_) { }
    // Set user online and broadcast status
    (0, realtime_1.setUserOnline)(user.id);
    socket.on('join:conversation', (conversationId) => {
        socket.join(`conversation:${conversationId}`);
        try {
            console.log('[socket] join:conversation', { userId: user.id, socketId: socket.id, conversationId });
        }
        catch (_) { }
    });
    socket.on('leave:conversation', (conversationId) => {
        socket.leave(`conversation:${conversationId}`);
    });
    socket.on('message:send', async (payload) => {
        try {
            let { conversationId, text, imageUrl, videoUrl, repliedToId } = payload;
            // Basic validation
            if (!conversationId || (!text && !imageUrl && !videoUrl)) {
                try {
                    socket.emit('message:error', { conversationId: conversationId || null, reason: 'INVALID_PAYLOAD' });
                }
                catch (_) { }
                try {
                    console.warn('[socket] message:send invalid payload', { userId: user.id, conversationId, hasText: !!text, hasImage: !!imageUrl, hasVideo: !!videoUrl });
                }
                catch (_) { }
                return;
            }
            // Load by conversationId; if not found, try interpreting it as a DirectConversation id,
            // a PulseConversation id, or even a pulseId. If needed, create the legacy conversation.
            let conversation = await prisma.conversation.findUnique({
                where: { id: conversationId },
                include: { participants: true, pulse: { select: { id: true } } },
            });
            if (!conversation) {
                // 1) DirectConversation id fallback
                const dconv = await prisma.directConversation.findUnique({ where: { id: conversationId }, include: { participants: { select: { id: true } } } }).catch(() => null);
                if (dconv) {
                    conversation = await prisma.conversation.findUnique({ where: { id: conversationId }, include: { participants: true, pulse: { select: { id: true } } } });
                    if (!conversation) {
                        // create legacy conversation aligned to direct id
                        conversation = await prisma.conversation.create({
                            data: {
                                id: dconv.id,
                                isGroup: false,
                                participants: { connect: dconv.participants.map((u) => ({ id: u.id })) },
                                name: dconv.name ?? undefined,
                                avatarUrl: dconv.avatarUrl ?? undefined,
                            },
                            include: { participants: true, pulse: { select: { id: true } } },
                        });
                    }
                }
            }
            if (!conversation) {
                // 2) PulseConversation id fallback
                const pconv = await prisma.pulseConversation.findUnique({ where: { id: conversationId }, include: { participants: { select: { id: true } }, pulse: { select: { id: true, title: true, imageUrl: true } } } }).catch(() => null);
                if (pconv) {
                    // prefer a legacy conversation with SAME id, else any conversation for this pulse, else create
                    let c = await prisma.conversation.findUnique({ where: { id: pconv.id }, include: { participants: true, pulse: { select: { id: true } } } });
                    if (!c && pconv.pulse?.id) {
                        c = await prisma.conversation.findFirst({ where: { pulseId: pconv.pulse.id }, include: { participants: true, pulse: { select: { id: true } } } });
                    }
                    if (!c && pconv.pulse?.id) {
                        c = await prisma.conversation.create({
                            data: {
                                id: pconv.id, // align ids to simplify client usage
                                isGroup: true,
                                pulse: { connect: { id: pconv.pulse.id } },
                                participants: { connect: pconv.participants.map((u) => ({ id: u.id })) },
                                name: pconv.pulse?.title ?? undefined,
                                avatarUrl: pconv.pulse?.imageUrl ?? undefined,
                            },
                            include: { participants: true, pulse: { select: { id: true } } },
                        });
                    }
                    if (c) {
                        conversation = c;
                        conversationId = c.id;
                    }
                }
            }
            if (!conversation) {
                // 2b) GroupConversation id fallback
                const gconv = await prisma.groupConversation.findUnique({ where: { id: conversationId }, include: { participants: { select: { id: true } } } }).catch(() => null);
                if (gconv) {
                    conversation = await prisma.conversation.findUnique({ where: { id: conversationId }, include: { participants: true, pulse: { select: { id: true } } } });
                    if (!conversation) {
                        // create legacy conversation aligned to group id
                        conversation = await prisma.conversation.create({
                            data: {
                                id: gconv.id,
                                isGroup: true,
                                participants: { connect: gconv.participants.map((u) => ({ id: u.id })) },
                                name: gconv.name,
                                avatarUrl: gconv.avatarUrl ?? undefined,
                            },
                            include: { participants: true, pulse: { select: { id: true } } },
                        });
                    }
                }
            }
            if (!conversation) {
                // 3) Interpret as pulseId
                const pulse = await prisma.pulse.findUnique({ where: { id: conversationId } });
                if (pulse) {
                    const c = await prisma.conversation.findFirst({ where: { pulseId: conversationId }, include: { participants: true, pulse: { select: { id: true } } } });
                    if (c) {
                        conversation = c;
                        conversationId = c.id; // normalize
                    }
                }
            }
            if (!conversation) {
                try {
                    socket.emit('message:error', { conversationId, reason: 'CONVERSATION_NOT_FOUND' });
                }
                catch (_) { }
                try {
                    console.warn('[socket] message:send conversation not found', { userId: user.id, requestedId: conversationId });
                }
                catch (_) { }
                return;
            }
            try {
                console.log('[socket] message:send conversation resolved', { userId: user.id, conversationId: conversation.id, pulseId: conversation.pulse?.id || null });
            }
            catch (_) { }
            let isParticipant = conversation.participants.some((p) => p.id === user.id);
            // If not a participant but this is a pulse chat, auto-connect if the user is part of the pulse
            if (!isParticipant && conversation.pulse?.id) {
                try {
                    const pulse = await prisma.pulse.findUnique({
                        where: { id: conversation.pulse.id },
                        include: { participants: { select: { id: true } }, author: { select: { id: true } } },
                    });
                    const isPulseMember = !!pulse && (pulse.author.id === user.id || pulse.participants.some((p) => p.id === user.id));
                    if (isPulseMember) {
                        await prisma.conversation.update({ where: { id: conversationId }, data: { participants: { connect: { id: user.id } } } });
                        isParticipant = true;
                    }
                }
                catch (autoJoinErr) {
                    // ignore auto-join errors; fall through to membership check
                }
            }
            if (!isParticipant) {
                try {
                    socket.emit('message:error', { conversationId, reason: 'NOT_PARTICIPANT' });
                }
                catch (_) { }
                try {
                    console.warn('[socket] message:send not participant', { userId: user.id, conversationId });
                }
                catch (_) { }
                return;
            }
            // Simple in-memory dedupe to avoid accidental double-sends within a short window
            const normalizedText = (text ?? '').trim();
            const key = `${conversationId}|${user.id}|${normalizedText}|${imageUrl ?? ''}|${videoUrl ?? ''}`;
            const now = Date.now();
            const last = recentMessageKeys.get(key) || 0;
            if (now - last < MESSAGE_DEDUPE_WINDOW_MS) {
                // Ignore as duplicate
                return;
            }
            recentMessageKeys.set(key, now);
            // Opportunistic cleanup: remove stale entries occasionally
            if (recentMessageKeys.size > 5000) {
                const cutoff = now - MESSAGE_DEDUPE_WINDOW_MS * 4;
                for (const [k, ts] of recentMessageKeys.entries()) {
                    if (ts < cutoff)
                        recentMessageKeys.delete(k);
                }
            }
            const msg = await prisma.message.create({
                data: {
                    conversationId,
                    senderId: user.id,
                    text: text ?? null,
                    imageUrl: imageUrl ?? null,
                    videoUrl: videoUrl ?? null,
                    repliedToId: repliedToId ?? null,
                },
                include: {
                    sender: {
                        select: {
                            id: true,
                            displayName: true,
                            profileImageUrl: true,
                        }
                    },
                    repliedTo: {
                        select: {
                            id: true,
                            text: true,
                            imageUrl: true,
                            videoUrl: true,
                            senderId: true,
                            sender: {
                                select: {
                                    id: true,
                                    displayName: true,
                                }
                            }
                        }
                    }
                }
            });
            // Ack to sender so client can confirm persistence
            try {
                socket.emit('message:ack', { conversationId, id: msg.id, createdAt: msg.createdAt });
            }
            catch (_) { }
            try {
                console.log('[socket] message:send persisted', { userId: user.id, conversationId, messageId: msg.id });
            }
            catch (_) { }
            // Update conversation last message metadata
            await prisma.conversation.update({
                where: { id: conversationId },
                data: {
                    updatedAt: new Date(),
                    lastMessageText: text ?? (videoUrl ? '[video]' : (imageUrl ? '[image]' : '')),
                    lastSenderId: user.id,
                },
            });
            // Best-effort: mirror last message metadata to new separated models if present
            try {
                await prisma.directConversation.update({
                    where: { id: conversationId },
                    data: {
                        updatedAt: new Date(),
                        lastMessageText: text ?? (videoUrl ? '[video]' : (imageUrl ? '[image]' : '')),
                        lastSenderId: user.id,
                    },
                }).catch(() => null);
                await prisma.pulseConversation.update({
                    where: { id: conversationId },
                    data: {
                        updatedAt: new Date(),
                        lastMessageText: text ?? (videoUrl ? '[video]' : (imageUrl ? '[image]' : '')),
                        lastSenderId: user.id,
                    },
                }).catch(() => null);
                await prisma.groupConversation.update({
                    where: { id: conversationId },
                    data: {
                        updatedAt: new Date(),
                        lastMessageText: text ?? (videoUrl ? '[video]' : (imageUrl ? '[image]' : '')),
                        lastSenderId: user.id,
                    },
                }).catch(() => null);
            }
            catch (_) { /* ignore */ }
            io.to(`conversation:${conversationId}`).emit('message:new', {
                id: msg.id,
                conversationId: msg.conversationId,
                senderId: msg.senderId,
                senderName: msg.sender?.displayName || null,
                senderPhotoUrl: msg.sender?.profileImageUrl || null,
                text: msg.text,
                imageUrl: msg.imageUrl,
                createdAt: msg.createdAt,
                videoUrl: msg.videoUrl,
                deliveredTo: msg.deliveredTo || [],
                readBy: msg.readBy || [],
                repliedTo: msg.repliedTo ? {
                    id: msg.repliedTo.id,
                    text: msg.repliedTo.text,
                    imageUrl: msg.repliedTo.imageUrl,
                    videoUrl: msg.repliedTo.videoUrl,
                    senderId: msg.repliedTo.senderId,
                    senderName: msg.repliedTo.sender?.displayName || 'Unknown',
                } : null,
            });
            try {
                console.log('[socket] message:new emitted to room', { conversationId });
            }
            catch (_) { }
            // Auto-mark as delivered for online participants
            const onlineRecipients = [];
            conversation.participants.forEach((p) => {
                if (p.id !== user.id && realtime_1.userSockets.has(p.id)) {
                    onlineRecipients.push(p.id);
                }
            });
            if (onlineRecipients.length > 0) {
                // Update message with deliveredTo for online users
                await prisma.message.update({
                    where: { id: msg.id },
                    data: {
                        deliveredTo: onlineRecipients,
                    },
                }).catch((e) => console.error('Auto-deliver update failed:', e));
                // Notify sender about delivery
                socket.emit('message:status-update', {
                    conversationId,
                    messageId: msg.id,
                    deliveredTo: onlineRecipients,
                    status: 'delivered',
                });
            }
            // Notify participants of conversation update (for message list refresh)
            conversation.participants.forEach((p) => {
                const sockets = realtime_1.userSockets.get(p.id);
                if (!sockets)
                    return;
                sockets.forEach((sid) => io.to(sid).emit('conversation:updated', { conversationId }));
            });
        }
        catch (e) {
            console.error('message:send error', e);
        }
    });
    // Toggle / add reaction
    socket.on('message:react', async (payload) => {
        try {
            const { conversationId, messageId, emoji } = payload;
            if (!conversationId || !messageId || !emoji)
                return;
            const conversation = await prisma.conversation.findUnique({
                where: { id: conversationId },
                include: { participants: true },
            });
            if (!conversation)
                return;
            const isParticipant = conversation.participants.some((p) => p.id === user.id);
            if (!isParticipant)
                return;
            // Check if reaction exists
            const existing = await prisma.messageReaction.findFirst({
                where: { messageId, userId: user.id, emoji },
            });
            if (existing) {
                await prisma.messageReaction.delete({ where: { id: existing.id } });
            }
            else {
                await prisma.messageReaction.create({
                    data: { messageId, userId: user.id, emoji },
                });
            }
            // Aggregate reactions for the message
            const grouped = await prisma.messageReaction.groupBy({
                by: ['emoji'],
                where: { messageId },
                _count: { emoji: true },
            });
            const users = await prisma.messageReaction.findMany({
                where: { messageId },
                select: { emoji: true, userId: true },
            });
            const map = {};
            users.forEach((r) => {
                if (!map[r.emoji])
                    map[r.emoji] = [];
                map[r.emoji].push(r.userId);
            });
            io.to(`conversation:${conversationId}`).emit('message:new', {
                conversationId,
                messageId,
                id: messageId, // maintain compatibility
                reactions: map,
                emoji,
                userId: user.id,
                type: 'reaction',
            });
        }
        catch (e) {
            console.error('message:react error', e);
        }
    });
    // Mark message as delivered
    socket.on('message:delivered', async (payload) => {
        try {
            const { conversationId, messageId } = payload;
            if (!conversationId || !messageId)
                return;
            const conversation = await prisma.conversation.findUnique({
                where: { id: conversationId },
                include: { participants: true },
            });
            if (!conversation)
                return;
            const isParticipant = conversation.participants.some((p) => p.id === user.id);
            if (!isParticipant)
                return;
            const message = await prisma.message.findUnique({
                where: { id: messageId },
            });
            if (!message || message.conversationId !== conversationId)
                return;
            // Don't mark own messages as delivered by self
            if (message.senderId === user.id)
                return;
            // Add user to deliveredTo array if not already there
            const deliveredTo = message.deliveredTo || [];
            if (!deliveredTo.includes(user.id)) {
                await prisma.message.update({
                    where: { id: messageId },
                    data: {
                        deliveredTo: { push: user.id },
                    },
                });
                // Notify sender that message was delivered
                const senderSockets = realtime_1.userSockets.get(message.senderId);
                if (senderSockets) {
                    senderSockets.forEach((sid) => io.to(sid).emit('message:status-update', {
                        conversationId,
                        messageId,
                        deliveredTo: [...deliveredTo, user.id],
                        userId: user.id,
                        status: 'delivered',
                    }));
                }
            }
        }
        catch (e) {
            console.error('message:delivered error', e);
        }
    });
    // Mark message as read
    socket.on('message:read', async (payload) => {
        try {
            const { conversationId, messageId } = payload;
            if (!conversationId || !messageId)
                return;
            const conversation = await prisma.conversation.findUnique({
                where: { id: conversationId },
                include: { participants: true },
            });
            if (!conversation)
                return;
            const isParticipant = conversation.participants.some((p) => p.id === user.id);
            if (!isParticipant)
                return;
            const message = await prisma.message.findUnique({
                where: { id: messageId },
            });
            if (!message || message.conversationId !== conversationId)
                return;
            // Don't mark own messages as read by self
            if (message.senderId === user.id)
                return;
            // Add user to readBy array if not already there
            const readBy = message.readBy || [];
            const deliveredTo = message.deliveredTo || [];
            if (!readBy.includes(user.id)) {
                const updates = {
                    readBy: { push: user.id },
                };
                // Also ensure user is in deliveredTo
                if (!deliveredTo.includes(user.id)) {
                    updates.deliveredTo = { push: user.id };
                }
                await prisma.message.update({
                    where: { id: messageId },
                    data: updates,
                });
                const newReadBy = [...readBy, user.id];
                const newDeliveredTo = deliveredTo.includes(user.id) ? deliveredTo : [...deliveredTo, user.id];
                // Notify sender that message was read
                const senderSockets = realtime_1.userSockets.get(message.senderId);
                if (senderSockets) {
                    senderSockets.forEach((sid) => io.to(sid).emit('message:status-update', {
                        conversationId,
                        messageId,
                        readBy: newReadBy,
                        deliveredTo: newDeliveredTo,
                        userId: user.id,
                        status: 'read',
                    }));
                }
            }
        }
        catch (e) {
            console.error('message:read error', e);
        }
    });
    socket.on('typing', ({ conversationId, isTyping }) => {
        socket.to(`conversation:${conversationId}`).emit('typing', { conversationId, userId: user.id, isTyping });
    });
    socket.on('disconnect', () => {
        const set = realtime_1.userSockets.get(user.id);
        if (set) {
            set.delete(socket.id);
            if (set.size === 0) {
                realtime_1.userSockets.delete(user.id);
                // Set user offline when all their sockets disconnect
                (0, realtime_1.setUserOffline)(user.id);
            }
        }
        // Remove user from any active group calls and notify rooms
        try {
            for (const [cid, members] of activeGroupCalls.entries()) {
                if (members.delete(user.id)) {
                    io.to(`conversation:${cid}`).emit('groupcall:participant-left', {
                        conversationId: cid,
                        userId: user.id,
                    });
                    if (members.size === 0) {
                        activeGroupCalls.delete(cid);
                        const meta = groupCallMeta.get(cid);
                        groupCallMeta.delete(cid);
                        io.to(`conversation:${cid}`).emit('groupcall:stopped', {
                            conversationId: cid,
                            reason: 'empty',
                            isVideo: meta?.isVideo ?? true,
                        });
                    }
                }
            }
        }
        catch (e) {
            // ignore cleanup errors
        }
    });
    // --- WebRTC signaling: simple 1:1 call forwarding via Socket.IO ---
    // Initiate a call (notify callee to present incoming UI)
    socket.on('call:initiate', async (payload) => {
        try {
            const { toUserId, conversationId, isVideo } = payload || {};
            if (!toUserId)
                return;
            const targets = realtime_1.userSockets.get(toUserId);
            if (!targets)
                return;
            const data = {
                fromUserId: user.id,
                conversationId: conversationId ?? null,
                isVideo: !!isVideo,
                timestamp: Date.now(),
            };
            targets.forEach((sid) => io.to(sid).emit('call:incoming', data));
        }
        catch (e) {
            console.error('call:initiate error', e);
        }
    });
    // Forward SDP offer to callee
    socket.on('call:offer', async (payload) => {
        try {
            const { toUserId, sdp, conversationId, isVideo } = payload || {};
            if (!toUserId || !sdp)
                return;
            const targets = realtime_1.userSockets.get(toUserId);
            if (!targets)
                return;
            const data = { fromUserId: user.id, sdp, conversationId: conversationId ?? null, isVideo: !!isVideo };
            targets.forEach((sid) => io.to(sid).emit('call:offer', data));
        }
        catch (e) {
            console.error('call:offer error', e);
        }
    });
    // Forward SDP answer to caller
    socket.on('call:answer', async (payload) => {
        try {
            const { toUserId, sdp, conversationId } = payload || {};
            if (!toUserId || !sdp)
                return;
            const targets = realtime_1.userSockets.get(toUserId);
            if (!targets)
                return;
            const data = { fromUserId: user.id, sdp, conversationId: conversationId ?? null };
            targets.forEach((sid) => io.to(sid).emit('call:answer', data));
        }
        catch (e) {
            console.error('call:answer error', e);
        }
    });
    // Forward ICE candidates both ways
    socket.on('call:ice-candidate', async (payload) => {
        try {
            const { toUserId, candidate } = payload || {};
            if (!toUserId || !candidate)
                return;
            const targets = realtime_1.userSockets.get(toUserId);
            if (!targets)
                return;
            const data = { fromUserId: user.id, candidate };
            targets.forEach((sid) => io.to(sid).emit('call:ice-candidate', data));
        }
        catch (e) {
            console.error('call:ice-candidate error', e);
        }
    });
    // End a call (notify peer)
    socket.on('call:end', async (payload) => {
        try {
            const { toUserId, reason } = payload || {};
            if (!toUserId)
                return;
            const targets = realtime_1.userSockets.get(toUserId);
            if (!targets)
                return;
            const data = { fromUserId: user.id, reason: reason ?? null };
            targets.forEach((sid) => io.to(sid).emit('call:ended', data));
        }
        catch (e) {
            console.error('call:end error', e);
        }
    });
    // --- Group Call Signaling (mesh) ---
    // Start a group call in a conversation (does not auto-join users)
    socket.on('groupcall:start', async (payload) => {
        try {
            const { conversationId, isVideo } = payload || {};
            if (!conversationId)
                return;
            const conversation = await prisma.conversation.findUnique({
                where: { id: conversationId }, include: { participants: true }
            });
            if (!conversation)
                return;
            const isParticipant = conversation.participants.some((p) => p.id === user.id);
            if (!isParticipant)
                return;
            if (!activeGroupCalls.has(conversationId)) {
                activeGroupCalls.set(conversationId, new Set());
            }
            groupCallMeta.set(conversationId, { isVideo: !!isVideo, startedBy: user.id, startedAt: Date.now() });
            io.to(`conversation:${conversationId}`).emit('groupcall:started', {
                conversationId,
                isVideo: !!isVideo,
                startedBy: user.id,
                startedAt: Date.now(),
            });
        }
        catch (e) {
            console.error('groupcall:start error', e);
        }
    });
    // Stop an active group call
    socket.on('groupcall:stop', async (payload) => {
        try {
            const { conversationId, reason } = payload || {};
            if (!conversationId)
                return;
            const members = activeGroupCalls.get(conversationId);
            if (!members)
                return;
            activeGroupCalls.delete(conversationId);
            const meta = groupCallMeta.get(conversationId);
            groupCallMeta.delete(conversationId);
            io.to(`conversation:${conversationId}`).emit('groupcall:stopped', {
                conversationId,
                reason: reason ?? null,
                isVideo: meta?.isVideo ?? true,
            });
        }
        catch (e) {
            console.error('groupcall:stop error', e);
        }
    });
    // Join an active group call; returns current participants (excluding self)
    socket.on('groupcall:join', async (payload) => {
        try {
            const { conversationId } = payload || {};
            if (!conversationId)
                return;
            // Ensure a call has been started for this conversation
            if (!activeGroupCalls.has(conversationId)) {
                activeGroupCalls.set(conversationId, new Set());
            }
            const members = activeGroupCalls.get(conversationId);
            // Validate membership in conversation
            const conversation = await prisma.conversation.findUnique({
                where: { id: conversationId }, include: { participants: true }
            });
            if (!conversation)
                return;
            const isParticipant = conversation.participants.some((p) => p.id === user.id);
            if (!isParticipant)
                return;
            // Notify others, then add (so they see this user as joined)
            io.to(`conversation:${conversationId}`).emit('groupcall:participant-joining', {
                conversationId,
                userId: user.id,
            });
            members.add(user.id);
            // Send current participants to this socket only
            const others = Array.from(members).filter((id) => id !== user.id);
            io.to(socket.id).emit('groupcall:participants', {
                conversationId,
                participants: others,
            });
            // Broadcast that this user joined
            io.to(`conversation:${conversationId}`).emit('groupcall:participant-joined', {
                conversationId,
                userId: user.id,
            });
        }
        catch (e) {
            console.error('groupcall:join error', e);
        }
    });
    // Leave the group call
    socket.on('groupcall:leave', async (payload) => {
        try {
            const { conversationId } = payload || {};
            if (!conversationId)
                return;
            const members = activeGroupCalls.get(conversationId);
            if (!members)
                return;
            if (members.delete(user.id)) {
                io.to(`conversation:${conversationId}`).emit('groupcall:participant-left', {
                    conversationId,
                    userId: user.id,
                });
                if (members.size === 0) {
                    activeGroupCalls.delete(conversationId);
                    const meta = groupCallMeta.get(conversationId);
                    groupCallMeta.delete(conversationId);
                    io.to(`conversation:${conversationId}`).emit('groupcall:stopped', {
                        conversationId,
                        reason: 'empty',
                        isVideo: meta?.isVideo ?? true,
                    });
                }
            }
        }
        catch (e) {
            console.error('groupcall:leave error', e);
        }
    });
    // Signaling between participants (offer/answer/ice)
    socket.on('groupcall:signal', async (payload) => {
        try {
            const { conversationId, toUserId, kind, data } = payload || {};
            if (!conversationId || !toUserId || !kind || data === undefined)
                return;
            const members = activeGroupCalls.get(conversationId);
            if (!members)
                return;
            // Ensure both sender and receiver are in the call
            if (!members.has(user.id) || !members.has(toUserId))
                return;
            const targets = realtime_1.userSockets.get(toUserId);
            if (!targets)
                return;
            const forwarded = { conversationId, fromUserId: user.id, kind, data };
            targets.forEach((sid) => io.to(sid).emit('groupcall:signal', forwarded));
        }
        catch (e) {
            console.error('groupcall:signal error', e);
        }
    });
});
// Only start server if not running inside a test environment
if (process.env.JEST_WORKER_ID === undefined) {
    server.listen(PORT, () => {
        console.log(`Server running on http://localhost:${PORT}`);
    });
}
//# sourceMappingURL=index.js.map