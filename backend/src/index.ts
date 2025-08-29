import express from 'express';
import dotenv from 'dotenv';
import cors from 'cors';
import authRoute from './routes/auth';
import profileRoute from './routes/profile';
import { PrismaClient } from '@prisma/client';
import postsRoute from './routes/posts';
import messagesRoute from './routes/messages';
import admin from './firebase';
import http from 'http';
// Geolocation service (coordinate + reverse geocode utilities)
import { haversineKm, reverseGeocode } from './services/geolocation';
import { placesAutocomplete, placeDetails, parseLocationFromPlace } from './services/googlePlaces';
// Use require to avoid type resolution issues during build/lint
// eslint-disable-next-line @typescript-eslint/no-var-requires
const { Server } = require('socket.io');

dotenv.config();

export const app = express();
const prisma = new PrismaClient();

app.use(express.json());
// Enable CORS (open for development; tighten origins in production)
app.use(cors());

// Extend Express Request type to include user
declare global {
  namespace Express {
    interface Request {
      user?: any;
    }
  }
}

// Middleware to authenticate users
const authenticateUser = async (req: express.Request, res: express.Response, next: express.NextFunction) => {
  const authHeader = req.headers.authorization;
  if (!authHeader?.startsWith('Bearer ')) {
    return res.status(401).send('Missing or invalid token');
  }

  const idToken = authHeader.split(' ')[1];

  try {
    const decoded = await admin.auth().verifyIdToken(idToken);
    const { uid } = decoded;
    
    // Check if user exists in our database
    const user = await prisma.user.findUnique({ where: { firebaseUid: uid } });
    if (!user) {
      return res.status(401).json({ error: 'User not found' });
    }
    
    console.log('Auth middleware - User found:', {
      firebaseUid: uid,
      userId: user.id,
      userEmail: user.email
    });
    
    req.user = user;
    next();
  } catch (err) {
    console.error(err);
    res.status(401).json({ error: 'Unauthorized' });
  }
};

// Mount the auth routes directly without applying global authentication middleware
app.use('/api/auth', authRoute);

// Mount the profile routes
app.use('/api/profile', profileRoute);

// Mount posts routes
app.use('/api/posts', postsRoute);

// Messaging routes (REST helpers for conversations/messages)
app.use('/api', messagesRoute);

// Health check endpoint to test database connection
app.get('/api/health', async (req, res) => {
  try {
    // Test database connection
    await prisma.$queryRaw`SELECT 1`;
    
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
  } catch (error) {
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
app.get('/api/places/autocomplete', async (req, res) => {
  try {
    const { input, sessionToken, language } = req.query as any;
    if (!input || !String(input).trim()) return res.json([]);
    const predictions = await placesAutocomplete(String(input), { sessionToken: sessionToken as string | undefined, language });
    res.json(predictions);
  } catch (e: any) {
    console.error('Places autocomplete error', e);
    res.status(500).json({ error: 'Autocomplete failed' });
  }
});

// Google Places details -> structured Location preview (not persisted)
// GET /api/places/:placeId
app.get('/api/places/details/:placeId', async (req, res) => {
  try {
    const { placeId } = req.params;
    if (!placeId) return res.status(400).json({ error: 'placeId required' });
    const details = await placeDetails(placeId);
    if (!details) return res.status(404).json({ error: 'Not found' });
    const loc = parseLocationFromPlace(details);
    res.json({ placeId: details.placeId, formattedAddress: details.formattedAddress, location: loc });
  } catch (e: any) {
    console.error('Place details error', e);
    res.status(500).json({ error: 'Place details failed' });
  }
});

// Legacy geohash decode endpoint (for backward compatibility tests)
app.get('/api/geohash/decode', (req, res) => {
  const { hash } = req.query as { hash?: string };
  if (!hash) return res.status(400).json({ error: 'hash required' });
  try {
    const { decodeCenter } = require('./services/geolocation');
    const center = decodeCenter(String(hash));
    if (!center) return res.status(404).json({ error: 'invalid hash' });
    return res.json({ center });
  } catch (e) {
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
app.get('/api/pulses', async (req, res) => {
  try {
  const { search, tags, lat, lng, radiusKm, before, after, limit, active } = req.query as Record<string, string | undefined>;

    // Base where clause (public pulses only for now)
    const where: any = { isPublic: true };

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
      if (!isNaN(d.getTime())) where.eventTime = { ...(where.eventTime||{}), lte: d };
    }
    if (after) {
      const d = new Date(after);
      if (!isNaN(d.getTime())) where.eventTime = { ...(where.eventTime||{}), gte: d };
    }

    // Distance prefilter via bounding box if lat/lng present
    let latitude: number | undefined; let longitude: number | undefined; let radius: number | undefined;
    if (lat !== undefined && lng !== undefined) {
      latitude = parseFloat(lat); longitude = parseFloat(lng);
      if (!isNaN(latitude) && !isNaN(longitude)) {
        radius = radiusKm ? parseFloat(radiusKm) : 25; // default 25 km
        if (isNaN(radius) || radius <= 0) radius = 25;
        const latDelta = (radius as number) / 111; // ~111km per degree latitude
        const lngDelta = (radius as number) / (111 * Math.cos(latitude * Math.PI/180));
        const minLat = latitude - latDelta; const maxLat = latitude + latDelta;
        const minLng = longitude - lngDelta; const maxLng = longitude + lngDelta;
        // Only pulses with a location inside bounding box (skip null location pulses)
        where.location = { is: { latitude: { gte: minLat, lte: maxLat }, longitude: { gte: minLng, lte: maxLng } } };
      }
    }

    const take = (() => {
      const raw = limit ? parseInt(limit, 10) : 100;
      if (isNaN(raw) || raw < 1) return 100;
      return Math.min(raw, 300);
    })();

    // Active window filtering
    const now = new Date();
    if (active === 'now') {
      where.AND = [...(where.AND || []), { activeFrom: { lte: now } }, { OR: [ { activeUntil: null }, { activeUntil: { gte: now } } ] }];
    } else if (active === 'future') {
      where.OR = [...(where.OR || []), { activeFrom: { gt: now } }];
    } else if (active === 'past') {
      where.AND = [...(where.AND || []), { activeUntil: { lt: now } }];
    }

    const pulses = await prisma.pulse.findMany({
      where,
      include: {
        author: { select: { id: true, displayName: true, email: true, profileImageUrl: true, locationLabel: true } },
        participants: { select: { id: true, displayName: true, email: true, profileImageUrl: true } },
        location: true,
      },
      orderBy: [ { activeFrom: 'asc' }, { eventTime: 'asc' } ],
      take,
    });

    // If coordinates provided, compute distanceKm & filter strictly by radius (haversine)
    if (latitude !== undefined && longitude !== undefined && radius !== undefined) {
      const enriched = pulses.map(p => {
        if (!p.location) return null; // skip pulses lacking structured location when distance filtering
        const d = haversineKm(p.location.latitude, p.location.longitude, latitude as number, longitude as number);
        if (d > (radius as number)) return null;
        (p as any).distanceKm = d;
        return p;
      }).filter(Boolean) as any[];
      enriched.sort((a,b) => (a.distanceKm ?? 0) - (b.distanceKm ?? 0));
      return res.json(enriched);
    }

    const now2 = new Date();
    res.json(pulses.map(p => ({
      ...p,
      isActive: p.activeFrom <= now2 && (!p.activeUntil || p.activeUntil >= now2),
      activeWindow: { from: p.activeFrom, until: p.activeUntil }
    })));
  } catch (error) {
    console.error('Error fetching pulses:', error);
    res.status(500).json({ error: 'Failed to fetch pulses' });
  }
});

// Geospatial: find nearby pulses using PostGIS. Query params: lat, lng, radiusKm (default 5)
// (Removed) nearby geospatial endpoint

// New route to get a specific pulse by ID (authentication required)
app.get('/api/pulses/:id', authenticateUser, async (req, res) => {
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
    const isParticipant = pulse.participants.some(
      (participant) => participant.id === req.user.id
    );

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
  } catch (error) {
    console.error('Error fetching pulse:', error);
    res.status(500).json({ error: 'Failed to fetch pulse' });
  }
});

// New route to search pulses (no authentication required for fetching)
app.get('/api/pulses/search', async (req, res) => {
  try {
    // Accept either ?query= or ?search= to align with various client expectations
    const qParam: any = (req.query as any).query ?? (req.query as any).search;
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
  } catch (error) {
    console.error('Error searching pulses:', error);
    res.status(500).json({ error: 'Failed to search pulses' });
  }
});

// New route to create a pulse (authentication required)
app.post('/api/pulses', authenticateUser, async (req, res) => {
  try {
  const { title, description, eventTime, isPublic, tags, imageUrl, placeId, activeFrom, activeUntil, activeDurationMinutes } = req.body;
    
    // Validate required fields
    if (!title || !eventTime) {
      return res.status(400).json({ error: 'Title and eventTime are required' });
    }

    // Active window validation (optional)
    let activeFromDate: Date | undefined;
    let activeUntilDate: Date | undefined;
    const eventTimeDate = new Date(eventTime);
    if (isNaN(eventTimeDate.getTime())) return res.status(400).json({ error: 'Invalid eventTime' });
    // Parse provided values if any
    if (activeFrom) {
      const d = new Date(activeFrom);
      if (isNaN(d.getTime())) return res.status(400).json({ error: 'Invalid activeFrom value' });
      activeFromDate = d;
    }
    if (activeUntil) {
      const d = new Date(activeUntil);
      if (isNaN(d.getTime())) return res.status(400).json({ error: 'Invalid activeUntil value' });
      activeUntilDate = d;
    }
    // If not provided, derive window: start at eventTime, end at eventTime + duration (default 120 min)
    const durationMinutesNum = (() => {
      if (activeDurationMinutes === undefined || activeDurationMinutes === null) return 120; // default 2h
      const n = parseInt(String(activeDurationMinutes), 10);
      return isNaN(n) || n < 1 ? 120 : Math.min(n, 24 * 60); // cap at 24h
    })();
    if (!activeFromDate) activeFromDate = eventTimeDate;
    if (!activeUntilDate) activeUntilDate = new Date(activeFromDate.getTime() + durationMinutesNum * 60 * 1000);
    if (activeFromDate && activeUntilDate && activeUntilDate < activeFromDate) {
      return res.status(400).json({ error: 'activeUntil must be after activeFrom' });
    }
    
    // Optional: placeId or raw coordinates -> create structured Location record
    let locationId: number | undefined;
    try {
      if (placeId) {
        const details = await placeDetails(placeId);
        if (details) {
          // Try reuse existing Location by placeId
          const existingLoc = await prisma.location.findFirst({ where: { placeId: details.placeId } }).catch(()=>null);
          if (existingLoc) {
            locationId = existingLoc.id;
          } else {
            const parsed = parseLocationFromPlace(details);
            const loc = await prisma.location.create({ data: {
              ...parsed,
              placeId: details.placeId,
              formattedAddress: details.formattedAddress || null,
              types: details.types || [],
              raw: details.addressComponents as any,
              locationSource: 'GOOGLE_PLACES'
            } });
            locationId = loc.id;
          }
        }
      } else if (req.body.latitude !== undefined && req.body.longitude !== undefined) {
        const latNum = parseFloat(req.body.latitude); const lngNum = parseFloat(req.body.longitude);
        if (!isNaN(latNum) && !isNaN(lngNum)) {
          const rev = await reverseGeocode(latNum, lngNum);
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
            }});
            locationId = loc.id;
          }
        }
      }
    } catch (e) {
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
      await (prisma as any).conversation.create({
        data: {
          pulse: { connect: { id: pulse.id } },
          isGroup: true,
          name: pulse.title,
          avatarUrl: pulse.imageUrl ?? null,
          participants: { connect: { id: pulse.authorId } },
        }
      });
    } catch (chatCreateErr: any) {
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
  } catch (error) {
    console.error('Error creating pulse:', error);
    res.status(500).json({ error: 'Failed to create pulse' });
  }
});

// GET /api/pulses/nearby?lat=..&lng=..&radiusKm=.. - public pulses nearby using bounding box + haversine on Location
app.get('/api/pulses/nearby', async (req, res) => {
  try {
    const { lat, lng, radiusKm = '5' } = req.query as { lat?: string; lng?: string; radiusKm?: string };
    if (!lat || !lng) return res.status(400).json({ error: 'lat and lng are required' });
    const latitude = parseFloat(lat); const longitude = parseFloat(lng); const radius = parseFloat(String(radiusKm));
    if ([latitude, longitude, radius].some(v => isNaN(v))) return res.status(400).json({ error: 'Invalid numeric parameters' });
    // Bounding box prefilter
    const latDelta = radius / 111; const lngDelta = radius / (111 * Math.cos(latitude * Math.PI/180));
    const minLat = latitude - latDelta; const maxLat = latitude + latDelta;
    const minLng = longitude - lngDelta; const maxLng = longitude + lngDelta;
    const pulses = await prisma.pulse.findMany({
      where: {
        isPublic: true,
        // Filter by related Location fields (only pulses that have a location within bbox)
        location: {
          is: {
            latitude: { gte: minLat, lte: maxLat },
            longitude: { gte: minLng, lte: maxLng },
          }
        }
      },
      include: {
        author: { select: { id: true, displayName: true, email: true, locationLabel: true, profileImageUrl: true } },
        participants: { select: { id: true, displayName: true, email: true, profileImageUrl: true } },
        location: true
      },
      take: 400
    });
    const within = pulses.map(p => {
      if (!p.location) return null;
      const d = haversineKm(p.location.latitude, p.location.longitude, latitude, longitude);
      (p as any).distanceKm = d;
      return d <= radius ? p : null;
    }).filter(Boolean).sort((a: any,b: any)=>a.distanceKm-b.distanceKm).slice(0,300);
    res.json({ center: { latitude, longitude }, radiusKm: radius, count: within.length, pulses: within });
  } catch (e) {
    console.error('nearby pulses error', e);
    res.status(500).json({ error: 'Failed nearby pulses search' });
  }
});

// New route to update a pulse (authentication required)
app.put('/api/pulses/:id', authenticateUser, async (req, res) => {
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
    let newLocationConnect: any = undefined;
    try {
      if (req.body.placeId) {
        const details = await placeDetails(req.body.placeId);
        if (details) {
          const existingLoc = await prisma.location.findFirst({ where: { placeId: details.placeId } }).catch(()=>null);
          if (existingLoc) {
            newLocationConnect = { connect: { id: existingLoc.id } };
          } else {
            const parsed = parseLocationFromPlace(details);
            const loc = await prisma.location.create({ data: { ...parsed, placeId: details.placeId, formattedAddress: details.formattedAddress || null, raw: details.addressComponents as any, types: details.types || [], locationSource: 'GOOGLE_PLACES' } });
            newLocationConnect = { connect: { id: loc.id } };
          }
        }
      } else if (req.body.latitude !== undefined && req.body.longitude !== undefined) {
        const latNum = parseFloat(req.body.latitude); const lngNum = parseFloat(req.body.longitude);
        if (!isNaN(latNum) && !isNaN(lngNum)) {
          const rev = await reverseGeocode(latNum, lngNum);
          if (rev) {
            const loc = await prisma.location.create({ data: { name: rev.location.name || rev.label, street: rev.location.street, city: rev.location.city, state: rev.location.state, postalCode: rev.location.postalCode, country: rev.location.country, latitude: rev.location.latitude, longitude: rev.location.longitude, locationSource: 'REVERSE_GEOCODE', accuracyMeters: typeof req.body.accuracyMeters === 'number' ? req.body.accuracyMeters : null } });
            newLocationConnect = { connect: { id: loc.id } };
          }
        }
      }
    } catch (e) { console.warn('Location update resolution failed', e); }

    // Active window validation
    let activeFromDate: Date | undefined;
    let activeUntilDate: Date | undefined;
    if (activeFrom !== undefined) {
      if (activeFrom === null || activeFrom === '') {
        activeFromDate = undefined; // will not change
      } else {
        const d = new Date(activeFrom);
        if (isNaN(d.getTime())) return res.status(400).json({ error: 'Invalid activeFrom value' });
        activeFromDate = d;
      }
    }
    if (activeUntil !== undefined) {
      if (activeUntil === null || activeUntil === '') {
        activeUntilDate = null as any; // explicit clear
      } else {
        const d = new Date(activeUntil);
        if (isNaN(d.getTime())) return res.status(400).json({ error: 'Invalid activeUntil value' });
        activeUntilDate = d;
      }
    }
    if (activeFromDate && activeUntilDate && activeUntilDate < activeFromDate) {
      return res.status(400).json({ error: 'activeUntil must be after activeFrom' });
    }

  const updatedPulse: any = await prisma.pulse.update({
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
        const convo = await (prisma as any).conversation.findFirst({ where: { pulseId: id } });
        if (convo) {
          await (prisma as any).conversation.update({
            where: { id: convo.id },
            data: {
              name: title !== undefined ? title : undefined,
              avatarUrl: imageUrl !== undefined ? imageUrl : undefined,
            }
          });
        }
      }
    } catch (e) {
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
  ...updatedPulse.participants.map((p: any) => ({ ...p, isAuthor: false }))
      ],
      isActive: updatedPulse.activeFrom <= nowPut && (!updatedPulse.activeUntil || updatedPulse.activeUntil >= nowPut),
      activeWindow: { from: updatedPulse.activeFrom, until: updatedPulse.activeUntil }
    };

    res.json(responseData);
  } catch (error) {
    console.error('Error updating pulse:', error);
    res.status(500).json({ error: 'Failed to update pulse' });
  }
});

// PATCH variant (partial update) for pulse edits – some clients may use PATCH instead of PUT
app.patch('/api/pulses/:id', authenticateUser, async (req, res) => {
  try {
    const { id } = req.params;
    const { title, description, eventTime, isPublic, tags, imageUrl, maxParticipants, category, difficulty, price, currency, activeFrom, activeUntil } = req.body;

    const existingPulse = await prisma.pulse.findUnique({ where: { id } });
    if (!existingPulse) return res.status(404).json({ error: 'Pulse not found' });
    if (existingPulse.authorId !== req.user.id) return res.status(403).json({ error: 'Not authorized to update this pulse' });

    // Validate numeric / geo fields only if present
    if (req.body.latitude !== undefined) {
      const latNum = parseFloat(req.body.latitude);
      if (isNaN(latNum) || latNum < -90 || latNum > 90) return res.status(400).json({ error: 'Invalid latitude value' });
    }
    if (req.body.longitude !== undefined) {
      const lngNum = parseFloat(req.body.longitude);
      if (isNaN(lngNum) || lngNum < -180 || lngNum > 180) return res.status(400).json({ error: 'Invalid longitude value' });
    }
    if (price !== undefined && price !== null) {
      const priceNum = parseFloat(price);
      if (isNaN(priceNum) || priceNum < 0) return res.status(400).json({ error: 'Invalid price value' });
    }
    if (maxParticipants !== undefined && maxParticipants !== null) {
      const mp = parseInt(maxParticipants, 10);
      if (isNaN(mp) || mp < 1) return res.status(400).json({ error: 'Invalid maxParticipants value' });
    }

    // Prepare data object only with provided keys
    const data: any = {};
    if (title !== undefined) data.title = title;
    if (description !== undefined) data.description = description;
  if (eventTime !== undefined) data.eventTime = new Date(eventTime);
    if (isPublic !== undefined) data.isPublic = isPublic;
    if (tags !== undefined) {
      if (!Array.isArray(tags)) return res.status(400).json({ error: 'Tags must be an array' });
      data.tags = tags;
    }
    if (imageUrl !== undefined) data.imageUrl = imageUrl;
    if (maxParticipants !== undefined) data.maxParticipants = parseInt(maxParticipants, 10);
    if (category !== undefined) data.category = category;
    if (difficulty !== undefined) data.difficulty = difficulty;
    if (price !== undefined) data.price = parseFloat(price);
    if (currency !== undefined) data.currency = currency;
    if (activeFrom !== undefined) {
      if (activeFrom === null || activeFrom === '') {
        // no-op, cannot unset because field non-nullable; ignore
      } else {
        const d = new Date(activeFrom);
        if (isNaN(d.getTime())) return res.status(400).json({ error: 'Invalid activeFrom value' });
  data.activeFrom = d;
      }
    }
    if (activeUntil !== undefined) {
      if (activeUntil === null || activeUntil === '') {
  data.activeUntil = null;
      } else {
        const d = new Date(activeUntil);
        if (isNaN(d.getTime())) return res.status(400).json({ error: 'Invalid activeUntil value' });
  data.activeUntil = d;
      }
    }
  if (data.activeFrom && data.activeUntil && data.activeUntil < data.activeFrom) {
      return res.status(400).json({ error: 'activeUntil must be after activeFrom' });
    }

    // If placeId or coordinates provided, attach new Location
    try {
      if (req.body.placeId) {
        const details = await placeDetails(req.body.placeId);
        if (details) {
          const existingLoc = await prisma.location.findFirst({ where: { placeId: details.placeId } }).catch(()=>null);
          if (existingLoc) {
            data.location = { connect: { id: existingLoc.id } };
          } else {
            const parsed = parseLocationFromPlace(details);
            const loc = await prisma.location.create({ data: { ...parsed, placeId: details.placeId, formattedAddress: details.formattedAddress || null, raw: details.addressComponents as any, types: details.types || [], locationSource: 'GOOGLE_PLACES' } });
            data.location = { connect: { id: loc.id } };
          }
        }
      } else if (req.body.latitude !== undefined && req.body.longitude !== undefined) {
        const latNum = parseFloat(req.body.latitude); const lngNum = parseFloat(req.body.longitude);
        if (!isNaN(latNum) && !isNaN(lngNum)) {
          const rev = await reverseGeocode(latNum, lngNum);
          if (rev) {
            const loc = await prisma.location.create({ data: { name: rev.location.name || rev.label, street: rev.location.street, city: rev.location.city, state: rev.location.state, postalCode: rev.location.postalCode, country: rev.location.country, latitude: rev.location.latitude, longitude: rev.location.longitude, locationSource: 'REVERSE_GEOCODE', accuracyMeters: typeof req.body.accuracyMeters === 'number' ? req.body.accuracyMeters : null } });
            data.location = { connect: { id: loc.id } };
          }
        }
      }
    } catch (e) { console.warn('Location patch resolution failed', e); }

  const updated: any = await prisma.pulse.update({
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
        const convo = await (prisma as any).conversation.findFirst({ where: { pulseId: id } });
        if (convo) {
          await (prisma as any).conversation.update({
            where: { id: convo.id },
            data: {
              name: data.title !== undefined ? data.title : undefined,
              avatarUrl: data.imageUrl !== undefined ? data.imageUrl : undefined,
            }
          });
        }
      }
    } catch (e) {
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
  ...updated.participants.map((p: any) => ({ ...p, isAuthor: false }))
      ],
      isActive: updated.activeFrom <= nowPatch && (!updated.activeUntil || updated.activeUntil >= nowPatch),
      activeWindow: { from: updated.activeFrom, until: updated.activeUntil }
    };

    res.json(responseData);
  } catch (err) {
    console.error('Error patching pulse:', err);
    res.status(500).json({ error: 'Failed to update pulse' });
  }
});

// New route to join a pulse (authentication required)
app.post('/api/pulses/:id/join', authenticateUser, async (req, res) => {
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
    const isAlreadyParticipant = pulse.participants.some(
      (participant) => participant.id === req.user.id
    );

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
      let convo = await (prisma as any).conversation.findFirst({
        where: { pulseId: id },
        include: { participants: true },
      });
      if (!convo) {
        convo = await (prisma as any).conversation.create({
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
          await (prisma as any).conversation.update({
            where: { id: convo.id },
            data: { participants: { connect: others.map((pid: string) => ({ id: pid })) } },
          });
        }
      } else {
        const isInConvo = (convo.participants as any[]).some((p) => p.id === userId);
        if (!isInConvo) {
          await (prisma as any).conversation.update({
            where: { id: convo.id },
            data: { participants: { connect: { id: userId } } },
          });
        }
      }
      // Emit conversation:updated so clients refresh list
      try {
        // @ts-ignore
        (convo.participants as any[]).forEach(p => {
          // @ts-ignore userSockets
            const sockets = userSockets.get(p.id);
            if (!sockets) return;
            // @ts-ignore io
            sockets.forEach((sid: string) => io.to(sid).emit('conversation:updated', { conversationId: convo.id }));
        });
      } catch (emitErr) {
        console.warn('joinPulse emit conversation:updated failed', emitErr);
      }
    } catch (chatErr) {
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
           } as any,
         },
       });
    } catch (notifyErr) {
      console.error('Failed to create join notification:', notifyErr);
      // Do not fail the main request due to notification errors
    }

    res.json({
      success: true,
      message: 'Successfully joined pulse',
      pulse: updatedPulse,
    });
  } catch (error) {
    console.error('Error joining pulse:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// New route to leave a pulse (authentication required)
app.post('/api/pulses/:id/leave', authenticateUser, async (req, res) => {
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
    const isParticipant = pulse.participants.some(
      (participant) => participant.id === req.user.id
    );

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
      const convo = await (prisma as any).conversation.findFirst({
        where: { pulseId: id },
      });
      if (convo) {
        await (prisma as any).conversation.update({
          where: { id: convo.id },
          data: { participants: { disconnect: { id: userId } } },
        });
      }
    } catch (chatErr) {
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
          } as any,
        },
      });
    } catch (notifyErr) {
      console.error('Failed to create leave notification:', notifyErr);
      // Do not fail the main request due to notification errors
    }

    res.json({
      success: true,
      message: 'Successfully left pulse',
      pulse: updatedPulse,
    });
  } catch (error) {
    console.error('Error leaving pulse:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Get pulse participants with detailed information
app.get('/api/pulses/:id/participants', authenticateUser, async (req, res) => {
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
  } catch (error) {
    console.error('Error fetching pulse participants:', error);
    res.status(500).json({ error: 'Failed to fetch pulse participants' });
  }
});

// Get or create the pulse group chat conversation and return its metadata
app.post('/api/pulses/:id/chat', authenticateUser, async (req, res) => {
  try {
    const { id } = req.params;
    const me = req.user.id as string;
    const pulse = await prisma.pulse.findUnique({
      where: { id },
      include: { participants: true, author: true },
    });
    if (!pulse) return res.status(404).json({ error: 'Pulse not found' });
    const isParticipant = pulse.participants.some((p) => p.id === me) || pulse.authorId === me;
    if (!isParticipant) return res.status(403).json({ error: 'Not a participant' });

    let convo = await (prisma as any).conversation.findFirst({
      where: { pulseId: id },
      include: { participants: { select: { id: true, displayName: true, profileImageUrl: true } } },
    });
    if (!convo) {
      convo = await (prisma as any).conversation.create({
        data: {
          pulse: { connect: { id } },
          isGroup: true,
          name: pulse.title,
          avatarUrl: pulse.imageUrl ?? null,
          participants: { connect: [{ id: pulse.authorId }, ...pulse.participants.map((p) => ({ id: p.id }))] },
        },
        include: { participants: { select: { id: true, displayName: true, profileImageUrl: true } } },
      });
    } else {
      // Ensure caller is connected (in case they were added to pulse later)
      const inConvo = (convo.participants as any[]).some((p) => p.id === me);
      if (!inConvo) {
        await (prisma as any).conversation.update({
          where: { id: convo.id },
          data: { participants: { connect: { id: me } } },
        });
        // re-read
        convo = await (prisma as any).conversation.findUnique({
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
      (convo.participants as any[]).forEach(p => {
        // @ts-ignore userSockets
        const sockets = userSockets.get(p.id);
        if (!sockets) return;
        // @ts-ignore io
        sockets.forEach((sid: string) => io.to(sid).emit('conversation:updated', { conversationId: convo.id }));
      });
    } catch (emitErr) {
      console.warn('pulse chat POST emit failed', emitErr);
    }
  } catch (e) {
    console.error('pulse chat error', e);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Idempotent GET variant to fetch pulse chat metadata (mirrors POST semantics without side effects other than ensuring membership)
app.get('/api/pulses/:id/chat', authenticateUser, async (req, res) => {
  // Delegate to POST handler logic by calling next route internally
  // Simpler duplicate implementation to avoid refactor now
  try {
    const { id } = req.params; const me = req.user.id as string;
    const pulse = await prisma.pulse.findUnique({ where: { id }, include: { participants: true, author: true } });
    if (!pulse) return res.status(404).json({ error: 'Pulse not found' });
    const isParticipant = pulse.participants.some(p=>p.id===me) || pulse.authorId === me;
    if (!isParticipant) return res.status(403).json({ error: 'Not a participant' });
    let convo = await (prisma as any).conversation.findFirst({ where: { pulseId: id }, include: { participants: { select: { id: true, displayName: true, profileImageUrl: true } } } });
    if (!convo) {
      convo = await (prisma as any).conversation.create({ data: { pulse: { connect: { id } }, isGroup: true, name: pulse.title, avatarUrl: pulse.imageUrl ?? null, participants: { connect: [{ id: pulse.authorId }, ...pulse.participants.map(p=>({ id: p.id }))] } }, include: { participants: { select: { id: true, displayName: true, profileImageUrl: true } } } });
    } else {
      const inConvo = (convo.participants as any[]).some(p=>p.id===me);
      if (!inConvo) {
        await (prisma as any).conversation.update({ where: { id: convo.id }, data: { participants: { connect: { id: me } } } });
        convo = await (prisma as any).conversation.findUnique({ where: { id: convo.id }, include: { participants: { select: { id: true, displayName: true, profileImageUrl: true } } } });
      }
    }
    res.json({ conversationId: convo.id, name: convo.name ?? pulse.title, avatarUrl: convo.avatarUrl ?? pulse.imageUrl ?? null, participants: convo.participants });
    try {
      // @ts-ignore
      (convo.participants as any[]).forEach(p => {
        // @ts-ignore userSockets
        const sockets = userSockets.get(p.id);
        if (!sockets) return;
        // @ts-ignore io
        sockets.forEach((sid: string) => io.to(sid).emit('conversation:updated', { conversationId: convo.id }));
      });
    } catch (emitErr) {
      console.warn('pulse chat GET emit failed', emitErr);
    }
  } catch (e) {
    console.error('pulse chat GET error', e);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Paginated fetch of messages for a pulse's group chat conversation
app.get('/api/pulses/:id/chat/messages', authenticateUser, async (req, res) => {
  try {
    const { id } = req.params; const me = req.user.id as string;
    const { cursor, limit = '30' } = req.query as { cursor?: string; limit?: string };
    const take = Math.max(1, Math.min(parseInt(String(limit),10) || 30, 100));
    const pulse = await prisma.pulse.findUnique({ where: { id }, include: { participants: true, author: true } });
    if (!pulse) return res.status(404).json({ error: 'Pulse not found' });
    const isParticipant = pulse.participants.some(p=>p.id===me) || pulse.authorId === me;
    if (!isParticipant) return res.status(403).json({ error: 'Not a participant' });
    const convo = await (prisma as any).conversation.findFirst({ where: { pulseId: id } });
    if (!convo) return res.json({ messages: [], nextCursor: null });
    const messages = await (prisma as any).message.findMany({ where: { conversationId: convo.id }, orderBy: { createdAt: 'desc' }, take, cursor: cursor ? { id: cursor } : undefined, skip: cursor ? 1 : 0 });
    const ids = messages.map((m: any)=>m.id);
    let reactions: any[] = [];
    if (ids.length) {
      reactions = await (prisma as any).messageReaction.findMany({ where: { messageId: { in: ids } }, select: { messageId: true, emoji: true, userId: true } });
    }
    const reactionMap: Record<string, Record<string, string[]>> = {};
    reactions.forEach(r=>{ if(!reactionMap[r.messageId]) reactionMap[r.messageId] = {}; if(!reactionMap[r.messageId][r.emoji]) reactionMap[r.messageId][r.emoji] = []; reactionMap[r.messageId][r.emoji].push(r.userId); });
    res.json({ messages: messages.reverse().map((m:any)=>({ ...m, reactions: reactionMap[m.id] || {} })), nextCursor: messages.length === take ? messages[messages.length - 1].id : null });
  } catch (e) {
    console.error('pulse chat messages error', e);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Post a message to pulse group chat (for clients without WebSocket capability)
app.post('/api/pulses/:id/chat/messages', authenticateUser, async (req, res) => {
  try {
    const { id } = req.params; const me = req.user.id as string; const { text, imageUrl, videoUrl } = req.body || {};
    if (!text && !imageUrl && !videoUrl) return res.status(400).json({ error: 'text or media required' });
    const pulse = await prisma.pulse.findUnique({ where: { id }, include: { participants: true, author: true } });
    if (!pulse) return res.status(404).json({ error: 'Pulse not found' });
    const isParticipant = pulse.participants.some(p=>p.id===me) || pulse.authorId === me;
    if (!isParticipant) return res.status(403).json({ error: 'Not a participant' });
    let convo = await (prisma as any).conversation.findFirst({ where: { pulseId: id }, include: { participants: true } });
    if (!convo) {
      convo = await (prisma as any).conversation.create({ data: { pulse: { connect: { id } }, isGroup: true, name: pulse.title, avatarUrl: pulse.imageUrl ?? null, participants: { connect: [{ id: pulse.authorId }, ...pulse.participants.map(p=>({ id: p.id }))] } } });
    } else {
      const inConvo = (convo.participants as any[]).some((p:any)=>p.id===me);
      if (!inConvo) await (prisma as any).conversation.update({ where: { id: convo.id }, data: { participants: { connect: { id: me } } } });
    }
    const msg = await (prisma as any).message.create({ data: { conversationId: convo.id, senderId: me, text: text ?? null, imageUrl: imageUrl ?? null, videoUrl: videoUrl ?? null } });
    await (prisma as any).conversation.update({ where: { id: convo.id }, data: { updatedAt: new Date(), lastMessageText: text ?? (videoUrl ? '[video]' : (imageUrl ? '[image]' : '')), lastSenderId: me } });
    res.status(201).json({ message: msg });
  } catch (e) {
    console.error('pulse chat message post error', e);
    res.status(500).json({ error: 'Internal server error' });
  }
});

const PORT = process.env.PORT || 3000;
const server = http.createServer(app);

// Socket.IO setup with CORS for dev
const io = new Server(server, {
  cors: {
    origin: '*',
    methods: ['GET', 'POST']
  }
});

// In-memory map of userId -> socketIds (multi-device)
const userSockets = new Map<string, Set<string>>();

io.use(async (socket: any, next: any) => {
  try {
    const token = socket.handshake.auth?.token || socket.handshake.headers['authorization']?.toString().replace('Bearer ', '');
    if (!token) return next(new Error('Unauthorized'));
    const decoded = await admin.auth().verifyIdToken(token);
    const uid = decoded.uid;
    const user = await prisma.user.findUnique({ where: { firebaseUid: uid } });
    if (!user) return next(new Error('User not found'));
    (socket as any).user = user;
    next();
  } catch (e) {
    next(new Error('Unauthorized'));
  }
});

io.on('connection', (socket: any) => {
  const user = (socket as any).user as { id: string };
  if (!user) return socket.disconnect(true);

  // Track connections
  if (!userSockets.has(user.id)) userSockets.set(user.id, new Set());
  userSockets.get(user.id)!.add(socket.id);

  socket.on('join:conversation', (conversationId: string) => {
    socket.join(`conversation:${conversationId}`);
  });

  socket.on('leave:conversation', (conversationId: string) => {
    socket.leave(`conversation:${conversationId}`);
  });

  socket.on('message:send', async (payload: { conversationId: string; text?: string; imageUrl?: string; videoUrl?: string }) => {
    try {
      const { conversationId, text, imageUrl, videoUrl } = payload;
      // Basic validation
      if (!conversationId || (!text && !imageUrl && !videoUrl)) return;

      const conversation = await (prisma as any).conversation.findUnique({
        where: { id: conversationId },
        include: { participants: true },
      });
      if (!conversation) return;
      const isParticipant = conversation.participants.some((p: any) => p.id === user.id);
      if (!isParticipant) return;

      const msg = await (prisma as any).message.create({
        data: {
          conversationId,
          senderId: user.id,
          text: text ?? null,
          imageUrl: imageUrl ?? null,
          videoUrl: videoUrl ?? null,
        },
      });

      // Update conversation last message metadata
      await (prisma as any).conversation.update({
        where: { id: conversationId },
        data: {
          updatedAt: new Date(),
          lastMessageText: text ?? (videoUrl ? '[video]' : (imageUrl ? '[image]' : '')),
          lastSenderId: user.id,
        },
      });

      io.to(`conversation:${conversationId}`).emit('message:new', {
        id: msg.id,
        conversationId: msg.conversationId,
        senderId: msg.senderId,
        text: msg.text,
        imageUrl: msg.imageUrl,
        createdAt: msg.createdAt,
        videoUrl: msg.videoUrl,
      });

      // Also notify participants who are not in the room
      conversation.participants.forEach((p: any) => {
        const sockets = userSockets.get(p.id);
        if (!sockets) return;
        sockets.forEach((sid) => io.to(sid).emit('conversation:updated', { conversationId }));
      });
    } catch (e) {
      console.error('message:send error', e);
    }
  });

  // Toggle / add reaction
  socket.on('message:react', async (payload: { conversationId: string; messageId: string; emoji: string }) => {
    try {
      const { conversationId, messageId, emoji } = payload;
      if (!conversationId || !messageId || !emoji) return;
      const conversation = await (prisma as any).conversation.findUnique({
        where: { id: conversationId },
        include: { participants: true },
      });
      if (!conversation) return;
      const isParticipant = conversation.participants.some((p: any) => p.id === user.id);
      if (!isParticipant) return;

      // Check if reaction exists
      const existing = await (prisma as any).messageReaction.findFirst({
        where: { messageId, userId: user.id, emoji },
      });
      if (existing) {
        await (prisma as any).messageReaction.delete({ where: { id: existing.id } });
      } else {
        await (prisma as any).messageReaction.create({
          data: { messageId, userId: user.id, emoji },
        });
      }

      // Aggregate reactions for the message
      const grouped = await (prisma as any).messageReaction.groupBy({
        by: ['emoji'],
        where: { messageId },
        _count: { emoji: true },
      });
      const users = await (prisma as any).messageReaction.findMany({
        where: { messageId },
        select: { emoji: true, userId: true },
      });
      const map: Record<string, string[]> = {};
      users.forEach((r: any) => {
        if (!map[r.emoji]) map[r.emoji] = [];
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
    } catch (e) {
      console.error('message:react error', e);
    }
  });

  socket.on('typing', ({ conversationId, isTyping }: { conversationId: string; isTyping: boolean }) => {
    socket.to(`conversation:${conversationId}`).emit('typing', { conversationId, userId: user.id, isTyping });
  });

  socket.on('disconnect', () => {
    const set = userSockets.get(user.id);
    if (set) {
      set.delete(socket.id);
      if (set.size === 0) userSockets.delete(user.id);
    }
  });
});

// Only start server if not running inside a test environment
if (process.env.JEST_WORKER_ID === undefined) {
  server.listen(PORT, () => {
    console.log(`Server running on http://localhost:${PORT}`);
  });
}
