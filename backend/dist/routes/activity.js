"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const client_1 = require("@prisma/client");
const firebase_1 = __importDefault(require("../firebase"));
const realtime_1 = require("../realtime");
const router = (0, express_1.Router)();
const prisma = new client_1.PrismaClient();
// Middleware to authenticate user
const authenticateUser = async (req, res, next) => {
    const authHeader = req.headers.authorization;
    if (!authHeader?.startsWith('Bearer ')) {
        return res.status(401).json({ error: 'Missing or invalid token' });
    }
    const idToken = authHeader.split(' ')[1];
    try {
        const decoded = await firebase_1.default.auth().verifyIdToken(idToken);
        req.user = decoded;
        next();
    }
    catch (error) {
        return res.status(401).json({ error: 'Invalid token' });
    }
};
router.use(authenticateUser);
// Get activity status for specific users
router.post('/status', async (req, res) => {
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
        const statuses = {};
        for (const user of users) {
            // Only return status if user has made it visible
            if (user.activityStatusVisible) {
                const activity = (0, realtime_1.getUserActivity)(user.id);
                if (activity) {
                    statuses[user.id] = {
                        status: activity.status,
                        lastSeen: activity.lastSeen
                    };
                }
                else {
                    statuses[user.id] = {
                        status: 'offline',
                        lastSeen: new Date()
                    };
                }
            }
            else {
                // User has hidden their activity status
                statuses[user.id] = null;
            }
        }
        res.json({ statuses });
    }
    catch (error) {
        console.error('Error fetching activity statuses:', error);
        res.status(500).json({ error: 'Failed to fetch activity statuses' });
    }
});
// Get all online users (respecting privacy settings)
router.get('/online', async (req, res) => {
    try {
        const onlineUserIds = (0, realtime_1.getOnlineUsers)();
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
    }
    catch (error) {
        console.error('Error fetching online users:', error);
        res.status(500).json({ error: 'Failed to fetch online users' });
    }
});
// Manually set away status
router.post('/away', async (req, res) => {
    try {
        const userId = req.user.uid;
        (0, realtime_1.setUserAway)(userId);
        res.json({ success: true, status: 'away' });
    }
    catch (error) {
        console.error('Error setting away status:', error);
        res.status(500).json({ error: 'Failed to set away status' });
    }
});
exports.default = router;
//# sourceMappingURL=activity.js.map