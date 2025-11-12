import { Router, Request, Response } from 'express';
import { PrismaClient } from '@prisma/client';
import { getAuth } from 'firebase-admin/auth';
import { boundingBox, haversineKm } from '../services/geolocation';
import {
  getPersonalizedRecommendations,
  trackPulseInteraction,
  markRecommendationViewed,
  markRecommendationClicked,
} from '../services/recommendation';

const router = Router();
const prisma = new PrismaClient();

// GET /api/pulses - Get all pulses for the authenticated user
router.get('/', async (req: Request, res: Response) => {
  try {
    const authHeader = req.headers.authorization;
    
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const token = authHeader.split('Bearer ')[1];
    const decodedToken = await getAuth().verifyIdToken(token);
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
  } catch (error) {
    console.error('Error fetching pulses:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// GET /api/pulses/nearby?lat=&lng=&radiusKm=
router.get('/nearby', async (req: Request, res: Response) => {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({ error: 'Unauthorized' });
    }
    console.log('[GET] /pulses/nearby', req.query);
    const { lat, lng, radiusKm = '10' } = req.query as { lat?: string; lng?: string; radiusKm?: string };
    if (!lat || !lng) {
      console.log('Missing lat/lng');
      return res.status(400).json({ error: 'lat and lng are required' });
    }
    const latitude = parseFloat(lat); const longitude = parseFloat(lng); const radius = parseFloat(radiusKm as string);
    if ([latitude, longitude, radius].some(v => isNaN(v))) {
      console.log('Invalid numeric parameters', { latitude, longitude, radius });
      return res.status(400).json({ error: 'Invalid numeric parameters' });
    }

    const bbox = boundingBox(latitude, longitude, radius);
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
      if (!p.location) return null;
      const d = haversineKm(p.location.latitude, p.location.longitude, latitude, longitude);
      return d <= radius ? { ...p, distanceKm: d } : null;
    }).filter(Boolean) as any[];

    precise.sort((a,b)=>a.distanceKm - b.distanceKm);
    const response = { center: { latitude, longitude }, radiusKm: radius, count: precise.length, pulses: precise.slice(0,500) };
    console.log('Nearby pulses response:', JSON.stringify(response));
    return res.status(200).json(response);
  } catch (e) {
    console.error('nearby pulses error', e);
    res.status(500).json({ error: 'Failed nearby pulses search' });
  }
});

// POST /api/pulses/:id/join - Join a pulse
router.post('/:id/join', async (req: Request, res: Response) => {
  try {
    const { id } = req.params;
    const authHeader = req.headers.authorization;
    
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const token = authHeader.split('Bearer ')[1];
    const decodedToken = await getAuth().verifyIdToken(token);
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
    const isAlreadyParticipant = pulse.participants.some(
      (participant) => participant.id === user.id
    );

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
  } catch (error) {
    console.error('Error joining pulse:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// GET /api/pulses/:id/participants - Get pulse participants
router.get('/:id/participants', async (req: Request, res: Response) => {
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
  } catch (error) {
    console.error('Error fetching pulse participants:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================================
// ML RECOMMENDATION ENDPOINTS
// ============================================================================

// GET /api/pulses/personalized - Get ML-powered personalized recommendations
router.get('/personalized', async (req: Request, res: Response) => {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const token = authHeader.split('Bearer ')[1];
    const decodedToken = await getAuth().verifyIdToken(token);
    const firebaseUid = decodedToken.uid;

    const user = await prisma.user.findUnique({
      where: { firebaseUid },
    });

    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    const { latitude, longitude } = req.query as { latitude?: string; longitude?: string };
    const lat = latitude ? parseFloat(latitude) : undefined;
    const lng = longitude ? parseFloat(longitude) : undefined;

    console.log(`Getting personalized recommendations for user ${user.id}`);

    // Get ML recommendations
    const recommendations = await getPersonalizedRecommendations(
      user.id,
      lat,
      lng
    );

    // Enrich with full pulse data
    const pulseIds = recommendations.map(r => r.pulseId);
    const pulses = await prisma.pulse.findMany({
      where: {
        id: { in: pulseIds },
        activeUntil: { gte: new Date() },
      },
      include: {
        author: {
          select: {
            id: true,
            displayName: true,
            profileImageUrl: true,
            email: true,
          },
        },
        location: {
          select: {
            id: true,
            name: true,
            city: true,
            state: true,
            country: true,
            latitude: true,
            longitude: true,
          },
        },
        participants: {
          select: {
            id: true,
            displayName: true,
            profileImageUrl: true,
          },
        },
      },
    });

    // Add recommendation metadata
    const enriched = pulses.map(pulse => {
      const rec = recommendations.find(r => r.pulseId === pulse.id);
      return {
        ...pulse,
        recommendationScore: rec?.score,
        recommendationReason: rec?.reason,
        participantCount: pulse.participants?.length || 0,
      };
    });

    // Sort by recommendation score
    enriched.sort((a, b) => (b.recommendationScore || 0) - (a.recommendationScore || 0));

    // Track that recommendations were viewed
    if (enriched.length > 0) {
      await markRecommendationViewed(user.id, enriched.map(p => p.id));
    }

    res.json({
      recommendations: enriched,
      count: enriched.length,
    });
  } catch (error) {
    console.error('Personalized pulses error:', error);
    res.status(500).json({ error: 'Failed to get recommendations' });
  }
});

// POST /api/pulses/track-interaction - Track user interaction with a pulse
router.post('/track-interaction', async (req: Request, res: Response) => {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const token = authHeader.split('Bearer ')[1];
    const decodedToken = await getAuth().verifyIdToken(token);
    const firebaseUid = decodedToken.uid;

    const user = await prisma.user.findUnique({
      where: { firebaseUid },
    });

    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    const { pulseId, interactionType, duration, source } = req.body;

    if (!pulseId || !interactionType) {
      return res.status(400).json({ error: 'pulseId and interactionType are required' });
    }

    await trackPulseInteraction(
      user.id,
      pulseId,
      interactionType,
      duration,
      source
    );

    // If it's a recommendation click, mark it
    if (interactionType === 'recommendation_click') {
      await markRecommendationClicked(user.id, pulseId);
    }

    res.json({ success: true });
  } catch (error) {
    console.error('Error tracking interaction:', error);
    res.status(500).json({ error: 'Failed to track interaction' });
  }
});

export default router;
