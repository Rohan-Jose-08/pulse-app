import express from 'express';
import { authenticateUser } from '../middleware/auth';
import {
  getPersonalizedRecommendations,
  trackPulseInteraction,
  markRecommendationViewed,
  markRecommendationClicked,
  generateUserFeatures,
} from '../services/recommendation';
import { PrismaClient } from '@prisma/client';

const router = express.Router();
const prisma = new PrismaClient();

// All routes require authentication
router.use(authenticateUser);

/**
 * GET /api/recommendations
 * Get personalized pulse recommendations for the authenticated user
 */
router.get('/', async (req, res) => {
  try {
    const userId = (req.user as any).id;
    const latitude = req.query.latitude ? parseFloat(req.query.latitude as string) : undefined;
    const longitude = req.query.longitude ? parseFloat(req.query.longitude as string) : undefined;

    console.log(`Getting recommendations for user ${userId}`);

    const recommendations = await getPersonalizedRecommendations(userId, latitude, longitude);

    // Fetch pulse details
    const pulseIds = recommendations.map(r => r.pulseId);
    const pulses = await prisma.pulse.findMany({
      where: { id: { in: pulseIds } },
      include: {
        author: {
          select: {
            id: true,
            displayName: true,
            profileImageUrl: true,
          },
        },
        location: true,
        participants: {
          select: { id: true },
        },
      },
    });

    // Enrich recommendations with pulse data
    const enriched = pulses.map(pulse => {
      const rec = recommendations.find(r => r.pulseId === pulse.id);
      return {
        ...pulse,
        participantCount: pulse.participants.length,
        recommendationScore: rec?.score,
        recommendationReason: rec?.reason,
      };
    });

    // Sort by recommendation score
    enriched.sort((a, b) => (b.recommendationScore || 0) - (a.recommendationScore || 0));

    // Mark as viewed
    if (enriched.length > 0) {
      await markRecommendationViewed(userId, enriched.map(p => p.id));
    }

    res.json({
      recommendations: enriched,
      count: enriched.length,
    });
  } catch (error) {
    console.error('Error getting recommendations:', error);
    res.status(500).json({ error: 'Failed to get recommendations' });
  }
});

/**
 * POST /api/recommendations/track
 * Track user interaction with a pulse
 */
router.post('/track', async (req, res) => {
  try {
    const userId = (req.user as any).id;
    const { pulseId, interactionType, duration, source, deviceType } = req.body;

    if (!pulseId || !interactionType) {
      return res.status(400).json({ error: 'pulseId and interactionType are required' });
    }

    const validInteractionTypes = [
      'view',
      'join',
      'message',
      'invite',
      'share',
      'recommendation_view',
      'recommendation_click',
    ];

    if (!validInteractionTypes.includes(interactionType)) {
      return res.status(400).json({ error: 'Invalid interaction type' });
    }

    await trackPulseInteraction(userId, pulseId, interactionType, duration, source);

    // If it's a recommendation click, mark it
    if (interactionType === 'recommendation_click') {
      await markRecommendationClicked(userId, pulseId);
    }

    res.json({ success: true });
  } catch (error) {
    console.error('Error tracking interaction:', error);
    res.status(500).json({ error: 'Failed to track interaction' });
  }
});

/**
 * GET /api/recommendations/features
 * Get cached user features for the authenticated user
 */
router.get('/features', async (req, res) => {
  try {
    const userId = (req.user as any).id;

    const features = await prisma.userFeatureCache.findUnique({
      where: { userId },
    });

    if (!features) {
      return res.status(404).json({ error: 'User features not found' });
    }

    res.json({
      userId: features.userId,
      features: {
        preferredCategories: features.preferredCategories,
        preferredTimeSlots: features.preferredTimeSlots,
        socialActivityScore: features.socialActivityScore,
        avgSessionDuration: features.avgSessionDuration,
        messagingFrequency: features.messagingFrequency,
        inviteAcceptanceRate: features.inviteAcceptanceRate,
        totalPulsesJoined: features.totalPulsesJoined,
        totalPulsesCreated: features.totalPulsesCreated,
        avgDistanceKm: features.avgDistanceKm,
      },
      updatedAt: features.updatedAt,
    });
  } catch (error) {
    console.error('Error getting user features:', error);
    res.status(500).json({ error: 'Failed to get user features' });
  }
});

/**
 * POST /api/recommendations/compute-features
 * Compute and cache user features from interaction history
 */
router.post('/compute-features', async (req, res) => {
  try {
    const userId = (req.user as any).id;

    console.log(`Computing features for user ${userId}`);

    const features = await generateUserFeatures(userId);

    res.json({
      success: true,
      userId,
      features,
    });
  } catch (error) {
    console.error('Error computing user features:', error);
    res.status(500).json({ error: 'Failed to compute user features' });
  }
});

/**
 * GET /api/recommendations/interactions
 * Get user's interaction history
 */
router.get('/interactions', async (req, res) => {
  try {
    const userId = (req.user as any).id;
    const limit = req.query.limit ? parseInt(req.query.limit as string) : 50;

    const interactions = await prisma.pulseInteraction.findMany({
      where: { userId },
      orderBy: { timestamp: 'desc' },
      take: Math.min(limit, 100),
    });

    res.json({
      interactions,
      count: interactions.length,
    });
  } catch (error) {
    console.error('Error getting interactions:', error);
    res.status(500).json({ error: 'Failed to get interactions' });
  }
});

/**
 * GET /api/recommendations/stats
 * Get recommendation statistics for the authenticated user
 */
router.get('/stats', async (req, res) => {
  try {
    const userId = (req.user as any).id;

    // Get recommendation stats
    const totalRecommendations = await prisma.pulseRecommendation.count({
      where: { userId },
    });

    const viewedRecommendations = await prisma.pulseRecommendation.count({
      where: { userId, viewed: true },
    });

    const clickedRecommendations = await prisma.pulseRecommendation.count({
      where: { userId, clicked: true },
    });

    // Get interaction stats
    const totalInteractions = await prisma.pulseInteraction.count({
      where: { userId },
    });

    const interactionsByType = await prisma.pulseInteraction.groupBy({
      by: ['interactionType'],
      where: { userId },
      _count: { interactionType: true },
    });

    const interactionCounts = Object.fromEntries(
      interactionsByType.map(item => [item.interactionType, item._count.interactionType])
    );

    // Get user features
    const features = await prisma.userFeatureCache.findUnique({
      where: { userId },
    });

    res.json({
      recommendations: {
        total: totalRecommendations,
        viewed: viewedRecommendations,
        clicked: clickedRecommendations,
        clickThroughRate:
          viewedRecommendations > 0 ? (clickedRecommendations / viewedRecommendations) * 100 : 0,
      },
      interactions: {
        total: totalInteractions,
        byType: interactionCounts,
      },
      features: features
        ? {
            preferredCategories: features.preferredCategories,
            preferredTimeSlots: features.preferredTimeSlots,
            socialActivityScore: features.socialActivityScore,
            totalPulsesJoined: features.totalPulsesJoined,
            totalPulsesCreated: features.totalPulsesCreated,
          }
        : null,
    });
  } catch (error) {
    console.error('Error getting recommendation stats:', error);
    res.status(500).json({ error: 'Failed to get recommendation stats' });
  }
});

/**
 * DELETE /api/recommendations/cache
 * Clear recommendation cache for the authenticated user
 */
router.delete('/cache', async (req, res) => {
  try {
    const userId = (req.user as any).id;

    await prisma.pulseRecommendation.deleteMany({
      where: { userId },
    });

    await prisma.userFeatureCache.delete({
      where: { userId },
    }).catch(() => {}); // Ignore if doesn't exist

    res.json({ success: true, message: 'Cache cleared' });
  } catch (error) {
    console.error('Error clearing cache:', error);
    res.status(500).json({ error: 'Failed to clear cache' });
  }
});

// ============================================================================
// ADVANCED ML ENDPOINTS
// ============================================================================

import {
  trainMLModels,
  getSimilarUsers,
  explainRecommendation,
  getMLModelStats,
  createABTest,
  batchRecommendations,
} from '../services/recommendation';

/**
 * POST /api/recommendations/train
 * Trigger ML model training (admin only)
 */
router.post('/train', async (req, res) => {
  try {
    const { model = 'all', days = 30 } = req.body;

    console.log(`Training ML models: ${model}, using ${days} days of data`);

    const result = await trainMLModels(model, days);

    res.json(result);
  } catch (error) {
    console.error('Error training ML models:', error);
    res.status(500).json({ error: 'Failed to train ML models' });
  }
});

/**
 * GET /api/recommendations/similar-users
 * Get users similar to the authenticated user
 */
router.get('/similar-users', async (req, res) => {
  try {
    const userId = (req.user as any).id;
    const limit = req.query.limit ? parseInt(req.query.limit as string) : 10;

    const similarUsers = await getSimilarUsers(userId, limit);

    // Fetch user details for similar users
    const userDetails = await prisma.user.findMany({
      where: { id: { in: similarUsers.map(u => u.userId) } },
      select: {
        id: true,
        displayName: true,
        profileImageUrl: true,
      },
    });

    const enrichedUsers = similarUsers.map(su => {
      const details = userDetails.find(u => u.id === su.userId);
      return {
        ...su,
        displayName: details?.displayName,
        profileImageUrl: details?.profileImageUrl,
      };
    });

    res.json({
      userId,
      similarUsers: enrichedUsers,
    });
  } catch (error) {
    console.error('Error getting similar users:', error);
    res.status(500).json({ error: 'Failed to get similar users' });
  }
});

/**
 * GET /api/recommendations/explain/:pulseId
 * Get explanation for why a pulse was recommended
 */
router.get('/explain/:pulseId', async (req, res) => {
  try {
    const userId = (req.user as any).id;
    const { pulseId } = req.params;

    const explanation = await explainRecommendation(userId, pulseId);

    if (explanation) {
      res.json(explanation);
    } else {
      res.status(404).json({ error: 'Explanation not available' });
    }
  } catch (error) {
    console.error('Error explaining recommendation:', error);
    res.status(500).json({ error: 'Failed to explain recommendation' });
  }
});

/**
 * GET /api/recommendations/model-stats
 * Get ML model statistics
 */
router.get('/model-stats', async (req, res) => {
  try {
    const stats = await getMLModelStats();

    if (stats) {
      res.json(stats);
    } else {
      res.status(503).json({ error: 'ML service unavailable' });
    }
  } catch (error) {
    console.error('Error getting model stats:', error);
    res.status(500).json({ error: 'Failed to get model stats' });
  }
});

/**
 * POST /api/recommendations/ab-test
 * Create an A/B test experiment (admin only)
 */
router.post('/ab-test', async (req, res) => {
  try {
    const { name, variants } = req.body;

    if (!name || !variants || !Array.isArray(variants)) {
      return res.status(400).json({ error: 'name and variants array are required' });
    }

    const success = await createABTest(name, variants);

    if (success) {
      res.json({ success: true, experiment: name });
    } else {
      res.status(500).json({ error: 'Failed to create A/B test' });
    }
  } catch (error) {
    console.error('Error creating A/B test:', error);
    res.status(500).json({ error: 'Failed to create A/B test' });
  }
});

/**
 * POST /api/recommendations/batch
 * Get batch recommendations for multiple users (admin/system use)
 */
router.post('/batch', async (req, res) => {
  try {
    const { userIds, maxResults = 10 } = req.body;

    if (!userIds || !Array.isArray(userIds)) {
      return res.status(400).json({ error: 'userIds array is required' });
    }

    const recommendations = await batchRecommendations(userIds, maxResults);

    res.json({
      success: true,
      userCount: Object.keys(recommendations).length,
      recommendations,
    });
  } catch (error) {
    console.error('Error getting batch recommendations:', error);
    res.status(500).json({ error: 'Failed to get batch recommendations' });
  }
});

export default router;
