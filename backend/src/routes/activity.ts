import { Router } from 'express';
import { PrismaClient } from '@prisma/client';
import admin from '../firebase';
import { getUserActivity, getOnlineUsers, setUserAway } from '../realtime';

const router = Router();
const prisma = new PrismaClient();

// Middleware to authenticate user
const authenticateUser = async (req: any, res: any, next: any) => {
  const authHeader = req.headers.authorization;
  if (!authHeader?.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Missing or invalid token' });
  }

  const idToken = authHeader.split(' ')[1];

  try {
    const decoded = await admin.auth().verifyIdToken(idToken);
    req.user = decoded;
    next();
  } catch (error) {
    return res.status(401).json({ error: 'Invalid token' });
  }
};

router.use(authenticateUser);

// Get activity status for specific users
router.post('/status', async (req: any, res: any) => {
  try {
    const { userIds } = req.body;
    
    if (!Array.isArray(userIds)) {
      return res.status(400).json({ error: 'userIds must be an array' });
    }

    // Check privacy settings for each user
    const users = await prisma.user.findMany({
      where: {
        id: { in: userIds }
      },
      select: {
        id: true,
        activityStatusVisible: true
      }
    });

    const statuses: any = {};
    
    for (const user of users) {
      // Only return status if user has made it visible
      if (user.activityStatusVisible) {
        const activity = getUserActivity(user.id);
        if (activity) {
          statuses[user.id] = {
            status: activity.status,
            lastSeen: activity.lastSeen
          };
        } else {
          statuses[user.id] = {
            status: 'offline',
            lastSeen: new Date()
          };
        }
      } else {
        // User has hidden their activity status
        statuses[user.id] = null;
      }
    }

    res.json({ statuses });
  } catch (error) {
    console.error('Error fetching activity statuses:', error);
    res.status(500).json({ error: 'Failed to fetch activity statuses' });
  }
});

// Get all online users (respecting privacy settings)
router.get('/online', async (req: any, res: any) => {
  try {
    const onlineUserIds = getOnlineUsers();
    
    // Filter by privacy settings
    const users = await prisma.user.findMany({
      where: {
        id: { in: onlineUserIds },
        activityStatusVisible: true
      },
      select: {
        id: true,
        displayName: true,
        profileImageUrl: true
      }
    });

    res.json({ users });
  } catch (error) {
    console.error('Error fetching online users:', error);
    res.status(500).json({ error: 'Failed to fetch online users' });
  }
});

// Manually set away status
router.post('/away', async (req: any, res: any) => {
  try {
    const userId = req.user.uid;
    setUserAway(userId);
    res.json({ success: true, status: 'away' });
  } catch (error) {
    console.error('Error setting away status:', error);
    res.status(500).json({ error: 'Failed to set away status' });
  }
});

export default router;
