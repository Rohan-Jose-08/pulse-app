import express from 'express';
import { authenticateUser } from '../middleware/auth';
import { getMLModelStats } from '../services/recommendation';
import { PrismaClient } from '@prisma/client';

const router = express.Router();
const prisma = new PrismaClient();

// Admin middleware (you should implement proper admin check)
const requireAdmin = (req: any, res: any, next: any) => {
  // TODO: Add proper admin authentication
  // For now, just check if user is authenticated
  if (!req.user) {
    return res.status(403).json({ error: 'Admin access required' });
  }
  next();
};

router.use(authenticateUser);
router.use(requireAdmin);

/**
 * GET /api/ml-analytics/dashboard
 * Get comprehensive ML analytics dashboard data
 */
router.get('/dashboard', async (req, res) => {
  try {
    // Get model stats from ML service
    const modelStats = await getMLModelStats();
    
    // Get recommendation metrics
    const totalRecommendations = await prisma.pulseRecommendation.count();
    const viewedRecommendations = await prisma.pulseRecommendation.count({
      where: { viewed: true },
    });
    const clickedRecommendations = await prisma.pulseRecommendation.count({
      where: { clicked: true },
    });
    
    // Get interaction metrics
    const totalInteractions = await prisma.pulseInteraction.count();
    const interactionsByType = await prisma.pulseInteraction.groupBy({
      by: ['interactionType'],
      _count: { interactionType: true },
    });
    
    // Get user metrics with cached features
    const usersWithFeatures = await prisma.userFeatureCache.count();
    const totalUsers = await prisma.user.count();
    
    // Recent activity
    const recentInteractions = await prisma.pulseInteraction.findMany({
      orderBy: { timestamp: 'desc' },
      take: 100,
    });
    
    // Calculate CTR by time period
    const last24h = new Date(Date.now() - 24 * 60 * 60 * 1000);
    const last7d = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);
    
    const recommendations24h = await prisma.pulseRecommendation.count({
      where: { generatedAt: { gte: last24h } },
    });
    const clicks24h = await prisma.pulseRecommendation.count({
      where: { generatedAt: { gte: last24h }, clicked: true },
    });
    
    const recommendations7d = await prisma.pulseRecommendation.count({
      where: { generatedAt: { gte: last7d } },
    });
    const clicks7d = await prisma.pulseRecommendation.count({
      where: { generatedAt: { gte: last7d }, clicked: true },
    });
    
    res.json({
      modelStatus: modelStats,
      recommendations: {
        total: totalRecommendations,
        viewed: viewedRecommendations,
        clicked: clickedRecommendations,
        ctr: totalRecommendations > 0 
          ? ((clickedRecommendations / totalRecommendations) * 100).toFixed(2) + '%'
          : '0%',
        ctr24h: recommendations24h > 0 
          ? ((clicks24h / recommendations24h) * 100).toFixed(2) + '%'
          : '0%',
        ctr7d: recommendations7d > 0 
          ? ((clicks7d / recommendations7d) * 100).toFixed(2) + '%'
          : '0%',
      },
      interactions: {
        total: totalInteractions,
        byType: Object.fromEntries(
          interactionsByType.map(i => [i.interactionType, i._count.interactionType])
        ),
      },
      users: {
        total: totalUsers,
        withFeatures: usersWithFeatures,
        coverage: totalUsers > 0 
          ? ((usersWithFeatures / totalUsers) * 100).toFixed(2) + '%'
          : '0%',
      },
      recentActivity: {
        last100Interactions: recentInteractions.length,
        lastInteractionAt: recentInteractions[0]?.timestamp || null,
      },
    });
  } catch (error) {
    console.error('Error fetching ML analytics:', error);
    res.status(500).json({ error: 'Failed to fetch ML analytics' });
  }
});

/**
 * GET /api/ml-analytics/top-recommendations
 * Get top performing recommendations
 */
router.get('/top-recommendations', async (req, res) => {
  try {
    const limit = req.query.limit ? parseInt(req.query.limit as string) : 10;
    
    // Get most clicked recommendations
    const topRecommendations = await prisma.pulseRecommendation.findMany({
      where: { clicked: true },
      orderBy: { score: 'desc' },
      take: limit,
    });
    
    // Get pulse details
    const pulseIds = [...new Set(topRecommendations.map(r => r.pulseId))];
    const pulses = await prisma.pulse.findMany({
      where: { id: { in: pulseIds } },
      select: {
        id: true,
        title: true,
        category: true,
        currentParticipants: true,
      },
    });
    
    const enriched = topRecommendations.map(rec => {
      const pulse = pulses.find(p => p.id === rec.pulseId);
      return {
        ...rec,
        pulse,
      };
    });
    
    res.json({ recommendations: enriched });
  } catch (error) {
    console.error('Error fetching top recommendations:', error);
    res.status(500).json({ error: 'Failed to fetch top recommendations' });
  }
});

/**
 * GET /api/ml-analytics/user-engagement
 * Analyze user engagement with recommendations
 */
router.get('/user-engagement', async (req, res) => {
  try {
    // Get users with their recommendation engagement
    const users = await prisma.userFeatureCache.findMany({
      take: 100,
      orderBy: { totalPulsesJoined: 'desc' },
    });
    
    const engagement = await Promise.all(
      users.map(async (user) => {
        const recommendations = await prisma.pulseRecommendation.count({
          where: { userId: user.userId },
        });
        const clicked = await prisma.pulseRecommendation.count({
          where: { userId: user.userId, clicked: true },
        });
        
        return {
          userId: user.userId,
          totalPulsesJoined: user.totalPulsesJoined,
          totalPulsesCreated: user.totalPulsesCreated,
          socialActivityScore: user.socialActivityScore,
          recommendationsReceived: recommendations,
          recommendationsClicked: clicked,
          engagementRate: recommendations > 0 ? (clicked / recommendations) * 100 : 0,
        };
      })
    );
    
    res.json({ users: engagement });
  } catch (error) {
    console.error('Error analyzing user engagement:', error);
    res.status(500).json({ error: 'Failed to analyze user engagement' });
  }
});

/**
 * GET /api/ml-analytics/category-performance
 * Analyze recommendation performance by category
 */
router.get('/category-performance', async (req, res) => {
  try {
    // Get all pulses with their recommendation stats
    const pulses = await prisma.pulse.findMany({
      select: {
        id: true,
        category: true,
      },
    });
    
    const categoryStats: Record<string, any> = {};
    
    for (const pulse of pulses) {
      const category = pulse.category || 'uncategorized';
      
      if (!categoryStats[category]) {
        categoryStats[category] = {
          category,
          totalRecommendations: 0,
          clicked: 0,
          viewed: 0,
          pulseCount: 0,
        };
      }
      
      const stats = await prisma.pulseRecommendation.aggregate({
        where: { pulseId: pulse.id },
        _count: { id: true },
      });
      
      const clicked = await prisma.pulseRecommendation.count({
        where: { pulseId: pulse.id, clicked: true },
      });
      
      const viewed = await prisma.pulseRecommendation.count({
        where: { pulseId: pulse.id, viewed: true },
      });
      
      categoryStats[category].totalRecommendations += stats._count.id;
      categoryStats[category].clicked += clicked;
      categoryStats[category].viewed += viewed;
      categoryStats[category].pulseCount += 1;
    }
    
    // Calculate CTR for each category
    const categories = Object.values(categoryStats).map((cat: any) => ({
      ...cat,
      ctr: cat.totalRecommendations > 0 
        ? ((cat.clicked / cat.totalRecommendations) * 100).toFixed(2) 
        : '0',
      viewRate: cat.totalRecommendations > 0 
        ? ((cat.viewed / cat.totalRecommendations) * 100).toFixed(2) 
        : '0',
    }));
    
    res.json({ categories });
  } catch (error) {
    console.error('Error analyzing category performance:', error);
    res.status(500).json({ error: 'Failed to analyze category performance' });
  }
});

export default router;
