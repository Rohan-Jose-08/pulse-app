import { PrismaClient } from '@prisma/client';
import axios from 'axios';

const prisma = new PrismaClient();

// ML Service URL (Python service)
const ML_SERVICE_URL = process.env.ML_SERVICE_URL || 'http://localhost:5001';

export interface UserFeatures {
  avgSessionDuration?: number;
  preferredCategories: string[];
  preferredTimeSlots: string[];
  socialActivityScore: number;
  messagingFrequency: number;
  inviteAcceptanceRate: number;
  lastPulseJoinedAt?: Date;
  totalPulsesJoined: number;
  totalPulsesCreated: number;
  avgDistanceKm?: number;
  locationPreference?: {
    latitude: number;
    longitude: number;
  };
}

export interface RecommendationResult {
  pulseId: string;
  score: number;
  reason: string;
  category?: string;
  distance?: number;
}

/**
 * Get personalized pulse recommendations for a user
 * Uses ML service with collaborative filtering, neural networks, and ensemble scoring
 */
export async function getPersonalizedRecommendations(
  userId: string,
  latitude?: number,
  longitude?: number
): Promise<RecommendationResult[]> {
  try {
    // Check cache first (recommendations valid for 15 minutes)
    const cachedRecommendations = await getCachedRecommendations(userId);
    if (cachedRecommendations && cachedRecommendations.length > 0) {
      console.log(`Using cached recommendations for user ${userId}`);
      return cachedRecommendations;
    }

    console.log(`Generating fresh recommendations for user ${userId}`);

    // Get user features
    const userFeatures = await generateUserFeatures(userId);

    // Get available pulses near user
    const availablePulses = await getAvailablePulses(userId, latitude, longitude);

    if (availablePulses.length === 0) {
      console.log('No available pulses found');
      return [];
    }

    // Try to get ML recommendations with enhanced features
    let recommendations: RecommendationResult[];
    try {
      const requestBody: any = {
        userId,
        userFeatures,
        availablePulses,
        maxResults: 30,
      };

      // Add user location if available
      if (latitude !== undefined && longitude !== undefined) {
        requestBody.userLocation = { latitude, longitude };
      }

      const response = await axios.post(
        `${ML_SERVICE_URL}/recommend`,
        requestBody,
        { timeout: 8000 } // 8 second timeout for enhanced ML
      );
      recommendations = response.data;
      console.log(`ML service returned ${recommendations.length} recommendations`);
    } catch (mlError) {
      console.error('ML service error, using fallback:', mlError);
      // Fallback to rule-based recommendations
      recommendations = await getFallbackRecommendations(userId, availablePulses, userFeatures);
    }

    // Cache recommendations (15 minutes)
    await cacheRecommendations(userId, recommendations);

    // Store in database for analytics
    await storeRecommendations(userId, recommendations);

    return recommendations;
  } catch (error) {
    console.error('Recommendation error:', error);
    // Final fallback
    return getFallbackRecommendations(userId, [], {} as UserFeatures);
  }
}

/**
 * Generate feature vector for a user
 */
export async function generateUserFeatures(userId: string): Promise<UserFeatures> {
  // Check if we have cached features (valid for 1 hour)
  const cached = await prisma.userFeatureCache.findUnique({
    where: { userId },
  });

  const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000);
  if (cached && cached.updatedAt > oneHourAgo) {
    return {
      avgSessionDuration: cached.avgSessionDuration || undefined,
      preferredCategories: cached.preferredCategories || [],
      preferredTimeSlots: cached.preferredTimeSlots || [],
      socialActivityScore: cached.socialActivityScore || 0,
      messagingFrequency: cached.messagingFrequency || 0,
      inviteAcceptanceRate: cached.inviteAcceptanceRate || 0,
      lastPulseJoinedAt: cached.lastPulseJoinedAt || undefined,
      totalPulsesJoined: cached.totalPulsesJoined || 0,
      totalPulsesCreated: cached.totalPulsesCreated || 0,
      avgDistanceKm: cached.avgDistanceKm || undefined,
    };
  }

  // Calculate fresh features
  const interactions = await prisma.pulseInteraction.findMany({
    where: { userId },
    orderBy: { timestamp: 'desc' },
    take: 100,
  });

  const joinInteractions = interactions.filter(i => i.interactionType === 'join');
  const viewInteractions = interactions.filter(i => i.interactionType === 'view');

  // Calculate average session duration
  const durations = viewInteractions
    .filter(i => i.duration && i.duration > 0)
    .map(i => i.duration!);
  const avgSessionDuration = durations.length > 0
    ? durations.reduce((a, b) => a + b, 0) / durations.length
    : undefined;

  // Get preferred categories (from pulses user joined)
  const joinedPulses = await prisma.pulse.findMany({
    where: {
      participants: { some: { id: userId } },
    },
    select: { category: true },
  });
  const categoryCount = new Map<string, number>();
  joinedPulses.forEach(p => {
    if (p.category) {
      categoryCount.set(p.category, (categoryCount.get(p.category) || 0) + 1);
    }
  });
  const preferredCategories = Array.from(categoryCount.entries())
    .sort((a, b) => b[1] - a[1])
    .slice(0, 5)
    .map(([category]) => category);

  // Get preferred time slots
  const timeSlots = joinInteractions.map(i => {
    const hour = new Date(i.timestamp).getHours();
    if (hour >= 6 && hour < 12) return 'morning';
    if (hour >= 12 && hour < 17) return 'afternoon';
    if (hour >= 17 && hour < 21) return 'evening';
    return 'night';
  });
  const timeSlotCount = new Map<string, number>();
  timeSlots.forEach(slot => {
    timeSlotCount.set(slot, (timeSlotCount.get(slot) || 0) + 1);
  });
  const preferredTimeSlots = Array.from(timeSlotCount.entries())
    .sort((a, b) => b[1] - a[1])
    .slice(0, 2)
    .map(([slot]) => slot);

  // Social activity score
  const messageCount = await prisma.message.count({
    where: { senderId: userId },
  });
  const followersCount = await prisma.follow.count({
    where: { followingId: userId },
  });
  const socialActivityScore = Math.min(1.0, (messageCount * 0.01 + followersCount * 0.05) / 10);

  // Messaging frequency
  const recentMessages = await prisma.message.count({
    where: {
      senderId: userId,
      createdAt: { gte: new Date(Date.now() - 7 * 24 * 60 * 60 * 1000) }, // Last 7 days
    },
  });
  const messagingFrequency = recentMessages / 7;

  // Invite acceptance rate
  const invites = await prisma.conversationInvitation.findMany({
    where: { inviteeId: userId },
  });
  const acceptedInvites = invites.filter(i => i.status === 'ACCEPTED').length;
  const inviteAcceptanceRate = invites.length > 0 ? acceptedInvites / invites.length : 0.5;

  // Pulse statistics
  const totalPulsesJoined = await prisma.pulse.count({
    where: { participants: { some: { id: userId } } },
  });

  const totalPulsesCreated = await prisma.pulse.count({
    where: { authorId: userId },
  });

  const lastPulseJoined = await prisma.pulse.findFirst({
    where: { participants: { some: { id: userId } } },
    orderBy: { createdAt: 'desc' },
  });

  const features: UserFeatures = {
    avgSessionDuration,
    preferredCategories,
    preferredTimeSlots,
    socialActivityScore,
    messagingFrequency,
    inviteAcceptanceRate,
    lastPulseJoinedAt: lastPulseJoined?.createdAt,
    totalPulsesJoined,
    totalPulsesCreated,
  };

  // Cache the features
  await prisma.userFeatureCache.upsert({
    where: { userId },
    create: {
      userId,
      ...features,
      updatedAt: new Date(),
    },
    update: {
      ...features,
      updatedAt: new Date(),
    },
  });

  return features;
}

/**
 * Get available pulses near user
 */
async function getAvailablePulses(
  userId: string,
  latitude?: number,
  longitude?: number,
  radiusKm: number = 50
) {
  const now = new Date();

  // Get pulses that are active
  let pulses = await prisma.pulse.findMany({
    where: {
      activeUntil: { gte: now },
      authorId: { not: userId }, // Don't recommend user's own pulses
      participants: {
        none: { id: userId }, // Don't recommend pulses user already joined
      },
    },
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
    orderBy: { createdAt: 'desc' },
    take: 100,
  });

  // Filter by location if provided
  if (latitude !== undefined && longitude !== undefined) {
    pulses = pulses.filter(pulse => {
      const location = pulse.location as { latitude: number; longitude: number } | null;
      if (!location) return false;
      const distance = haversineDistance(
        latitude,
        longitude,
        location.latitude,
        location.longitude
      );
      return distance <= radiusKm;
    });
  }

  return pulses.map(p => {
    const location = p.location as { latitude: number; longitude: number; city: string } | null;
    const participants = p.participants as { id: string }[];
    return {
      id: p.id,
      title: p.title,
      description: p.description,
      category: p.category,
      eventTime: p.eventTime,
      authorId: p.authorId,
      participantCount: participants.length,
      location: location ? {
        latitude: location.latitude,
        longitude: location.longitude,
        city: location.city,
        distance: latitude && longitude
          ? haversineDistance(latitude, longitude, location.latitude, location.longitude)
          : undefined,
      } : undefined,
    };
  });
}

/**
 * Fallback rule-based recommendations
 */
async function getFallbackRecommendations(
  userId: string,
  availablePulses: any[],
  userFeatures: UserFeatures
): Promise<RecommendationResult[]> {
  // If no available pulses provided, get them
  if (availablePulses.length === 0) {
    const user = await prisma.user.findUnique({
      where: { id: userId },
      include: { following: true },
    });

    if (!user) return [];

    // Get pulses from followed users
    const followedPulses = await prisma.pulse.findMany({
      where: {
        authorId: { in: user.following.map(f => f.id) },
        activeUntil: { gte: new Date() },
        participants: { none: { id: userId } },
      },
      orderBy: { createdAt: 'desc' },
      take: 20,
    });

    return followedPulses.map(p => ({
      pulseId: p.id,
      score: 0.7,
      reason: 'From people you follow',
    }));
  }

  // Rule-based scoring
  const scored = availablePulses.map(pulse => {
    let score = 0.5; // Base score
    let reasons: string[] = [];

    // Category match
    if (pulse.category && userFeatures.preferredCategories.includes(pulse.category)) {
      score += 0.2;
      reasons.push('Matches your interests');
    }

    // Distance bonus
    if (pulse.location?.distance !== undefined) {
      if (pulse.location.distance < 2) {
        score += 0.15;
        reasons.push('Nearby');
      } else if (pulse.location.distance < 10) {
        score += 0.05;
      }
    }

    // Popularity bonus
    if (pulse.participantCount > 5) {
      score += 0.1;
      reasons.push('Popular event');
    }

    // Time relevance
    const eventTime = new Date(pulse.eventTime);
    const hoursUntilEvent = (eventTime.getTime() - Date.now()) / (1000 * 60 * 60);
    if (hoursUntilEvent < 4 && hoursUntilEvent > 0) {
      score += 0.1;
      reasons.push('Starting soon');
    }

    return {
      pulseId: pulse.id,
      score: Math.min(1.0, score),
      reason: reasons.length > 0 ? reasons.join(' • ') : 'Recommended for you',
    };
  });

  // Sort by score and return top 20
  return scored.sort((a, b) => b.score - a.score).slice(0, 20);
}

/**
 * Get cached recommendations
 */
async function getCachedRecommendations(userId: string): Promise<RecommendationResult[] | null> {
  const fifteenMinutesAgo = new Date(Date.now() - 15 * 60 * 1000);

  const cached = await prisma.pulseRecommendation.findMany({
    where: {
      userId,
      generatedAt: { gte: fifteenMinutesAgo },
    },
    orderBy: { score: 'desc' },
    take: 20,
  });

  if (cached.length === 0) return null;

  return cached.map(c => ({
    pulseId: c.pulseId,
    score: c.score,
    reason: c.reason || 'Recommended for you',
  }));
}

/**
 * Cache recommendations
 */
async function cacheRecommendations(userId: string, recommendations: RecommendationResult[]) {
  // Delete old recommendations
  await prisma.pulseRecommendation.deleteMany({
    where: { userId },
  });

  // Insert new recommendations
  await prisma.pulseRecommendation.createMany({
    data: recommendations.map(r => ({
      userId,
      pulseId: r.pulseId,
      score: r.score,
      reason: r.reason,
    })),
  });
}

/**
 * Store recommendations for analytics
 */
async function storeRecommendations(userId: string, recommendations: RecommendationResult[]) {
  // Already stored in cache, no need to duplicate
  return;
}

/**
 * Track user interaction with a pulse
 */
export async function trackPulseInteraction(
  userId: string,
  pulseId: string,
  interactionType: string,
  duration?: number,
  source?: string
) {
  try {
    await prisma.pulseInteraction.create({
      data: {
        userId,
        pulseId,
        interactionType,
        duration,
        source,
        timestamp: new Date(),
      },
    });

    // If user joined a pulse, invalidate their feature cache
    if (interactionType === 'join') {
      await prisma.userFeatureCache.delete({
        where: { userId },
      }).catch(() => {}); // Ignore if doesn't exist
    }
  } catch (error) {
    console.error('Error tracking pulse interaction:', error);
  }
}

/**
 * Mark recommendation as viewed
 */
export async function markRecommendationViewed(userId: string, pulseIds: string[]) {
  await prisma.pulseRecommendation.updateMany({
    where: {
      userId,
      pulseId: { in: pulseIds },
    },
    data: {
      viewed: true,
    },
  });
}

/**
 * Mark recommendation as clicked
 */
export async function markRecommendationClicked(userId: string, pulseId: string) {
  await prisma.pulseRecommendation.updateMany({
    where: {
      userId,
      pulseId,
    },
    data: {
      clicked: true,
    },
  });
}

/**
 * Haversine distance calculation
 */
function haversineDistance(
  lat1: number,
  lon1: number,
  lat2: number,
  lon2: number
): number {
  const R = 6371; // Earth's radius in km
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) *
    Math.sin(dLon / 2) * Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

function toRad(degrees: number): number {
  return degrees * (Math.PI / 180);
}

// ============================================================================
// ADVANCED ML SERVICE INTEGRATION
// ============================================================================

/**
 * Train ML models with recent interaction data
 */
export async function trainMLModels(
  model: 'all' | 'collaborative' | 'neural' = 'all',
  days: number = 30
): Promise<{ success: boolean; message: string; modelsTrainedCount?: number }> {
  try {
    const response = await axios.post(
      `${ML_SERVICE_URL}/train`,
      { model, days, force: false },
      { timeout: 60000 } // 60 second timeout for training
    );
    
    return {
      success: true,
      message: `Training completed: ${response.data.models_trained?.join(', ') || 'unknown'}`,
      modelsTrainedCount: response.data.models_trained?.length || 0,
    };
  } catch (error) {
    console.error('Error training ML models:', error);
    return {
      success: false,
      message: 'Failed to train ML models',
    };
  }
}

/**
 * Get similar users for a given user (collaborative filtering)
 */
export async function getSimilarUsers(
  userId: string,
  limit: number = 10
): Promise<Array<{ userId: string; similarity: number }>> {
  try {
    const response = await axios.get(
      `${ML_SERVICE_URL}/similar-users/${userId}?limit=${limit}`,
      { timeout: 5000 }
    );
    
    return response.data.similarUsers || [];
  } catch (error) {
    console.error('Error getting similar users:', error);
    return [];
  }
}

/**
 * Get explanation for why a pulse was recommended
 */
export async function explainRecommendation(
  userId: string,
  pulseId: string
): Promise<any> {
  try {
    const response = await axios.get(
      `${ML_SERVICE_URL}/explain/${userId}/${pulseId}`,
      { timeout: 5000 }
    );
    
    return response.data;
  } catch (error) {
    console.error('Error explaining recommendation:', error);
    return null;
  }
}

/**
 * Get ML model statistics
 */
export async function getMLModelStats(): Promise<any> {
  try {
    const response = await axios.get(
      `${ML_SERVICE_URL}/model-stats`,
      { timeout: 5000 }
    );
    
    return response.data;
  } catch (error) {
    console.error('Error getting ML model stats:', error);
    return null;
  }
}

/**
 * Create or update an A/B test experiment
 */
export async function createABTest(
  name: string,
  variants: Array<{ name: string; weights: Record<string, number> }>
): Promise<boolean> {
  try {
    await axios.post(
      `${ML_SERVICE_URL}/ab-test`,
      { name, variants },
      { timeout: 5000 }
    );
    
    return true;
  } catch (error) {
    console.error('Error creating A/B test:', error);
    return false;
  }
}

/**
 * Batch generate recommendations for multiple users
 */
export async function batchRecommendations(
  userIds: string[],
  maxResults: number = 10
): Promise<Record<string, RecommendationResult[]>> {
  try {
    const response = await axios.post(
      `${ML_SERVICE_URL}/batch-recommend`,
      { userIds, maxResults },
      { timeout: 30000 } // 30 second timeout for batch
    );
    
    return response.data.recommendations || {};
  } catch (error) {
    console.error('Error getting batch recommendations:', error);
    return {};
  }
}
