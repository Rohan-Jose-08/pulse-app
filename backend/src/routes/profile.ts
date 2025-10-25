import express from 'express';
import { PrismaClient } from '@prisma/client';
import { haversineKm } from '../services/geolocation';

const router = express.Router();
const prisma = new PrismaClient();

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
    const admin = require('../firebase').default;
    const decoded = await admin.auth().verifyIdToken(idToken);
    const { uid } = decoded;
    
    // Check if user exists in our database
    const user = await prisma.user.findUnique({ where: { firebaseUid: uid } });
    if (!user) {
      return res.status(401).json({ error: 'User not found' });
    }
    
    req.user = user;
    next();
  } catch (err) {
    console.error(err);
    res.status(401).json({ error: 'Unauthorized' });
  }
};

// GET /api/profile - Get current user's profile
router.get('/', authenticateUser, async (req, res) => {
  try {
    const user = await prisma.user.findUnique({
      where: { id: req.user.id },
      include: {
        _count: {
          select: {
            followers: true,
            following: true,
            createdPulses: true,
            participatingPulses: true,
            posts: true,
          }
        }
      }
    });

    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    res.json(user);
  } catch (error) {
    console.error('Error fetching profile:', error);
    res.status(500).json({ error: 'Failed to fetch profile' });
  }
});

// PUT /api/profile - Update current user's profile
router.put('/', authenticateUser, async (req, res) => {
  try {
    const { 
      displayName, 
      bio, 
      profileImageUrl, 
      location, 
      website, 
      socialLinks, 
      interests,
      phoneNumber,
      dateOfBirth,
      gender,
      occupation,
      company,
      education,
      languages,
      timezone,
      preferences,
      placeId,
      latitude,
      longitude,
      accuracyMeters
    } = req.body;

    // Validate input
    if (displayName && (typeof displayName !== 'string' || displayName.length > 100)) {
      return res.status(400).json({ error: 'Display name must be a string with max 100 characters' });
    }

    if (bio && (typeof bio !== 'string' || bio.length > 500)) {
      return res.status(400).json({ error: 'Bio must be a string with max 500 characters' });
    }

    if (location && (typeof location !== 'string' || location.length > 100)) {
      return res.status(400).json({ error: 'Location must be a string with max 100 characters' });
    }

    if (website && (typeof website !== 'string' || website.length > 200)) {
      return res.status(400).json({ error: 'Website must be a string with max 200 characters' });
    }

    if (socialLinks && typeof socialLinks !== 'object') {
      return res.status(400).json({ error: 'Social links must be an object' });
    }

    if (interests && (!Array.isArray(interests) || interests.some((interest: any) => typeof interest !== 'string'))) {
      return res.status(400).json({ error: 'Interests must be an array of strings' });
    }

    if (languages && (!Array.isArray(languages) || languages.some((lang: any) => typeof lang !== 'string'))) {
      return res.status(400).json({ error: 'Languages must be an array of strings' });
    }

    if (preferences && typeof preferences !== 'object') {
      return res.status(400).json({ error: 'Preferences must be an object' });
    }

    // Optional structured location update
    let locationConnect: any = undefined;
    try {
      if (placeId) {
        const { placeDetails, parseLocationFromPlace } = require('../services/googlePlaces'); // dynamic to avoid cycles
        const details = await placeDetails(placeId);
        if (details) {
          const existingLoc = await prisma.location.findFirst({ where: { placeId: details.placeId } }).catch(()=>null);
          if (existingLoc) {
            locationConnect = { connect: { id: existingLoc.id } };
          } else {
            const parsed = parseLocationFromPlace(details);
            const loc = await prisma.location.create({ data: { ...parsed, placeId: details.placeId, formattedAddress: details.formattedAddress || null, raw: details.addressComponents as any, types: details.types || [], locationSource: 'GOOGLE_PLACES' } });
            locationConnect = { connect: { id: loc.id } };
          }
        }
      } else if (latitude !== undefined && longitude !== undefined) {
        const latNum = parseFloat(latitude); const lngNum = parseFloat(longitude);
        if (!isNaN(latNum) && !isNaN(lngNum)) {
          const { reverseGeocode } = require('../services/geolocation');
          const rev = await reverseGeocode(latNum, lngNum);
          if (rev) {
            const loc = await prisma.location.create({ data: { name: rev.location.name || rev.label, street: rev.location.street, city: rev.location.city, state: rev.location.state, postalCode: rev.location.postalCode, country: rev.location.country, latitude: rev.location.latitude, longitude: rev.location.longitude, locationSource: 'REVERSE_GEOCODE', accuracyMeters: typeof accuracyMeters === 'number' ? accuracyMeters : null } });
            locationConnect = { connect: { id: loc.id } };
          }
        }
      }
    } catch (locErr) { console.warn('Profile location update failed', locErr); }

    const updatedUser = await prisma.user.update({
      where: { id: req.user.id },
      data: {
        ...(displayName !== undefined && { displayName }),
        ...(bio !== undefined && { bio }),
        ...(profileImageUrl !== undefined && { profileImageUrl }),
        ...(location !== undefined && { locationLabel: location }),
        ...(locationConnect && { location: locationConnect, locationUpdatedAt: new Date() }),
        ...(website !== undefined && { website }),
        ...(socialLinks !== undefined && { socialLinks }),
        ...(interests !== undefined && { interests }),
        ...(phoneNumber !== undefined && { phoneNumber }),
        ...(dateOfBirth !== undefined && { dateOfBirth: dateOfBirth ? new Date(dateOfBirth) : null }),
        ...(gender !== undefined && { gender }),
        ...(occupation !== undefined && { occupation }),
        ...(company !== undefined && { company }),
        ...(education !== undefined && { education }),
        ...(languages !== undefined && { languages }),
        ...(timezone !== undefined && { timezone }),
        ...(preferences !== undefined && { preferences }),
      },
      include: {
        _count: {
          select: {
            followers: true,
            following: true,
            createdPulses: true,
            participatingPulses: true,
            posts: true,
          }
        }
      }
    });

    res.json(updatedUser);
  } catch (error) {
    console.error('Error updating profile:', error);
    res.status(500).json({ error: 'Failed to update profile' });
  }
});

// GET /api/profile/nearby?lat=..&lng=..&radiusKm=.. - nearby users using Location bbox + haversine
router.get('/nearby', async (req, res) => {
  try {
    const { lat, lng, radiusKm = '5' } = req.query as { lat?: string; lng?: string; radiusKm?: string };
    if (!lat || !lng) return res.status(400).json({ error: 'lat and lng are required' });
    const latitude = parseFloat(lat); const longitude = parseFloat(lng); const radius = parseFloat(radiusKm);
    if ([latitude, longitude, radius].some(v => isNaN(v))) return res.status(400).json({ error: 'Invalid numeric parameters' });

    const latDelta = radius / 111; // degrees
    const lngDelta = radius / (111 * Math.cos(latitude * Math.PI/180));
    const minLat = latitude - latDelta; const maxLat = latitude + latDelta;
    const minLng = longitude - lngDelta; const maxLng = longitude + lngDelta;

    const users = await prisma.user.findMany({
      where: { location: { latitude: { gte: minLat, lte: maxLat }, longitude: { gte: minLng, lte: maxLng } } },
      select: { id: true, displayName: true, profileImageUrl: true, bio: true, locationLabel: true, locationUpdatedAt: true, location: { select: { id: true, name: true, city: true, country: true, latitude: true, longitude: true } } },
      take: 500
    });

    const within = users.map(u => {
      if (!u.location) return null;
      const d = haversineKm(u.location.latitude, u.location.longitude, latitude, longitude);
      return d <= radius ? { ...u, distanceKm: d } : null;
    }).filter(Boolean).sort((a: any,b: any)=>a.distanceKm-b.distanceKm).slice(0,200);

    res.json({ center: { latitude, longitude }, radiusKm: radius, count: within.length, users: within });
  } catch (e) {
    console.error('nearby users error', e);
    res.status(500).json({ error: 'Failed nearby users search' });
  }
});

// GET /api/profile/search - Search users by display name or email
router.get('/search', async (req, res) => {
  try {
    const { query } = req.query;

    if (!query || typeof query !== 'string') {
      return res.status(400).json({ error: 'Search query is required' });
    }

    const users = await prisma.user.findMany({
      where: {
        OR: [
          {
            displayName: {
              contains: query,
              mode: 'insensitive',
            },
          },
          {
            email: {
              contains: query,
              mode: 'insensitive',
            },
          },
          {
            bio: {
              contains: query,
              mode: 'insensitive',
            },
          },
        ],
      },
      select: {
        id: true,
        email: true,
        displayName: true,
        bio: true,
        profileImageUrl: true,
        location: true,
        isVerified: true,
        followersCount: true,
        followingCount: true,
        createdAt: true,
        _count: {
          select: {
            followers: true,
            following: true,
            createdPulses: true,
            participatingPulses: true,
          }
        }
      },
      take: 20, // Limit results
    });

    res.json(users);
  } catch (error) {
    console.error('Error searching users:', error);
    res.status(500).json({ error: 'Failed to search users' });
  }
});

// GET /api/profile/:userId - Get any user's profile by ID
router.get('/:userId', async (req, res) => {
  try {
    const { userId } = req.params;

    const user = await prisma.user.findUnique({
      where: { id: userId },
      select: {
        id: true,
        email: true,
        displayName: true,
        bio: true,
        profileImageUrl: true,
        locationLabel: true,
        website: true,
        socialLinks: true,
        interests: true,
        isVerified: true,
        followersCount: true,
        followingCount: true,
        createdAt: true,
        updatedAt: true,
        phoneNumber: true,
        dateOfBirth: true,
        gender: true,
        occupation: true,
        company: true,
        education: true,
        languages: true,
        timezone: true,
        _count: {
          select: {
            followers: true,
            following: true,
            createdPulses: true,
            participatingPulses: true,
            posts: true,
          }
        }
      }
    });

    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    res.json(user);
  } catch (error) {
    console.error('Error fetching user profile:', error);
    res.status(500).json({ error: 'Failed to fetch user profile' });
  }
});

// GET /api/profile/:userId/stats - Get user statistics
router.get('/:userId/stats', async (req, res) => {
  try {
    const { userId } = req.params;

    // Get user's created pulses count
    const createdPulsesCount = await prisma.pulse.count({
      where: { authorId: userId }
    });

    // Get user's participating pulses count (excluding created ones)
    const participatingPulsesCount = await prisma.pulse.count({
      where: {
        participants: {
          some: { id: userId }
        },
        authorId: { not: userId }
      }
    });

    // Get followers and following counts
    const followersCount = await prisma.follow.count({
      where: { followingId: userId }
    });

    const followingCount = await prisma.follow.count({
      where: { followerId: userId }
    });

    // Get posts count
    const postsCount = await prisma.post.count({
      where: { authorId: userId }
    });

    // Get total events count
    const totalEventsCount = createdPulsesCount + participatingPulsesCount;

    res.json({
      createdPulsesCount,
      participatingPulsesCount,
      totalEventsCount,
      followersCount,
      followingCount,
      postsCount,
    });
  } catch (error) {
    console.error('Error fetching user stats:', error);
    res.status(500).json({ error: 'Failed to fetch user stats' });
  }
});

// POST /api/profile/:userId/follow - Send follow request to a user
router.post('/:userId/follow', authenticateUser, async (req, res) => {
  try {
    const { userId } = req.params;
    const followerId = req.user.id;

    if (followerId === userId) {
      return res.status(400).json({ error: 'Cannot follow yourself' });
    }

    // Check if user exists
    const userToFollow = await prisma.user.findUnique({
      where: { id: userId }
    });

    if (!userToFollow) {
      return res.status(404).json({ error: 'User not found' });
    }

    // Check if already following
    const existingFollow = await prisma.follow.findUnique({
      where: {
        followerId_followingId: {
          followerId,
          followingId: userId
        }
      }
    });

    if (existingFollow) {
      return res.status(400).json({ error: 'Already following this user' });
    }

    // Check if follow request already exists
    const existingRequest = await prisma.conversationInvitation.findFirst({
      where: {
        inviterId: followerId,
        inviteeId: userId,
        invitationType: 'FOLLOW_REQUEST',
        status: 'PENDING'
      }
    });

    if (existingRequest) {
      return res.status(400).json({ error: 'Follow request already sent' });
    }

    // Create follow request invitation
    const followRequest = await prisma.conversationInvitation.create({
      data: {
        inviterId: followerId,
        inviteeId: userId,
        invitationType: 'FOLLOW_REQUEST',
        status: 'PENDING'
      },
      include: {
        inviter: {
          select: {
            id: true,
            displayName: true,
            profileImageUrl: true
          }
        },
        invitee: {
          select: {
            id: true,
            displayName: true,
            profileImageUrl: true
          }
        }
      }
    });

    // Create notification for the user being followed
    await prisma.notification.create({
      data: {
        userId: userId,
        type: 'FOLLOW_REQUEST',
        title: 'New Follow Request',
        message: `${req.user.displayName} sent you a follow request`,
        data: {
          requesterId: followerId,
          invitationId: followRequest.id
        }
      }
    });

    res.json({
      success: true,
      message: 'Follow request sent',
      followRequest
    });
  } catch (error) {
    console.error('Error sending follow request:', error);
    res.status(500).json({ error: 'Failed to send follow request' });
  }
});

// DELETE /api/profile/:userId/follow - Unfollow a user
router.delete('/:userId/follow', authenticateUser, async (req, res) => {
  try {
    const { userId } = req.params;
    const followerId = req.user.id;

    // Check if following relationship exists
    const existingFollow = await prisma.follow.findUnique({
      where: {
        followerId_followingId: {
          followerId,
          followingId: userId
        }
      }
    });

    if (!existingFollow) {
      return res.status(400).json({ error: 'Not following this user' });
    }

    // Delete follow relationship
    await prisma.follow.delete({
      where: {
        followerId_followingId: {
          followerId,
          followingId: userId
        }
      }
    });

    // Update follower counts
    await prisma.user.update({
      where: { id: userId },
      data: { followersCount: { decrement: 1 } }
    });

    await prisma.user.update({
      where: { id: followerId },
      data: { followingCount: { decrement: 1 } }
    });

    res.json({
      success: true,
      message: 'Successfully unfollowed user'
    });
  } catch (error) {
    console.error('Error unfollowing user:', error);
    res.status(500).json({ error: 'Failed to unfollow user' });
  }
});

// GET /api/profile/:userId/followers - Get user's followers
router.get('/:userId/followers', async (req, res) => {
  try {
    const { userId } = req.params;
    const { page = 1, limit = 20 } = req.query;

    const skip = (Number(page) - 1) * Number(limit);

    const followers = await prisma.follow.findMany({
      where: { followingId: userId },
      include: {
        follower: {
          select: {
            id: true,
            displayName: true,
            profileImageUrl: true,
            bio: true,
            locationLabel: true,
            isVerified: true
          }
        }
      },
      skip,
      take: Number(limit),
      orderBy: { createdAt: 'desc' }
    });

    const totalFollowers = await prisma.follow.count({
      where: { followingId: userId }
    });

    res.json({
      followers: followers.map(f => f.follower),
      totalFollowers,
      hasMore: skip + followers.length < totalFollowers
    });
  } catch (error) {
    console.error('Error fetching followers:', error);
    res.status(500).json({ error: 'Failed to fetch followers' });
  }
});

// GET /api/profile/:userId/following - Get users that this user is following
router.get('/:userId/following', async (req, res) => {
  try {
    const { userId } = req.params;
    const { page = 1, limit = 20 } = req.query;

    const skip = (Number(page) - 1) * Number(limit);

    const following = await prisma.follow.findMany({
      where: { followerId: userId },
      include: {
        following: {
          select: {
            id: true,
            displayName: true,
            profileImageUrl: true,
            bio: true,
            locationLabel: true,
            isVerified: true
          }
        }
      },
      skip,
      take: Number(limit),
      orderBy: { createdAt: 'desc' }
    });

    const totalFollowing = await prisma.follow.count({
      where: { followerId: userId }
    });

    res.json({
      following: following.map(f => f.following),
      totalFollowing,
      hasMore: skip + following.length < totalFollowing
    });
  } catch (error) {
    console.error('Error fetching following:', error);
    res.status(500).json({ error: 'Failed to fetch following' });
  }
});

// (Location details route moved above and geohash legacy endpoints removed)

export default router;
