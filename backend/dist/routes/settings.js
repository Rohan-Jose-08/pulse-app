"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = __importDefault(require("express"));
const client_1 = require("@prisma/client");
const router = express_1.default.Router();
const prisma = new client_1.PrismaClient();
// Middleware to authenticate users
const authenticateUser = async (req, res, next) => {
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
    }
    catch (err) {
        console.error(err);
        res.status(401).json({ error: 'Unauthorized' });
    }
};
// GET /api/settings - Get user settings
router.get('/', authenticateUser, async (req, res) => {
    try {
        const user = await prisma.user.findUnique({
            where: { id: req.user.id },
            select: {
                // Privacy settings
                profileVisibility: true,
                locationSharing: true,
                pulseHistoryVisibility: true,
                friendRequestsFrom: true,
                showOnlineStatus: true,
                allowMessageRequests: true,
                showInSearch: true,
                // Notification settings
                pushNotificationsEnabled: true,
                notifyNewPulsesNearby: true,
                notifyPulseInvitations: true,
                notifyPulseUpdates: true,
                notifyNewMessages: true,
                notifyNewFollowers: true,
                notifyFriendRequests: true,
                notifyPostReactions: true,
                // Appearance settings
                themePreference: true,
                languagePreference: true,
                textSizeScale: true,
                // Other settings
                hapticFeedbackEnabled: true,
                activityStatusVisible: true,
            }
        });
        if (!user) {
            return res.status(404).json({ error: 'User not found' });
        }
        res.json(user);
    }
    catch (error) {
        console.error('Error fetching settings:', error);
        res.status(500).json({ error: 'Failed to fetch settings' });
    }
});
// PUT /api/settings - Update user settings
router.put('/', authenticateUser, async (req, res) => {
    try {
        const { 
        // Privacy settings
        profileVisibility, locationSharing, pulseHistoryVisibility, friendRequestsFrom, showOnlineStatus, allowMessageRequests, showInSearch, 
        // Notification settings
        pushNotificationsEnabled, notifyNewPulsesNearby, notifyPulseInvitations, notifyPulseUpdates, notifyNewMessages, notifyNewFollowers, notifyFriendRequests, notifyPostReactions, 
        // Appearance settings
        themePreference, languagePreference, textSizeScale, 
        // Other settings
        hapticFeedbackEnabled, activityStatusVisible, } = req.body;
        const updateData = {};
        // Privacy settings
        if (profileVisibility !== undefined)
            updateData.profileVisibility = profileVisibility;
        if (locationSharing !== undefined)
            updateData.locationSharing = locationSharing;
        if (pulseHistoryVisibility !== undefined)
            updateData.pulseHistoryVisibility = pulseHistoryVisibility;
        if (friendRequestsFrom !== undefined)
            updateData.friendRequestsFrom = friendRequestsFrom;
        if (showOnlineStatus !== undefined)
            updateData.showOnlineStatus = showOnlineStatus;
        if (allowMessageRequests !== undefined)
            updateData.allowMessageRequests = allowMessageRequests;
        if (showInSearch !== undefined)
            updateData.showInSearch = showInSearch;
        // Notification settings
        if (pushNotificationsEnabled !== undefined)
            updateData.pushNotificationsEnabled = pushNotificationsEnabled;
        if (notifyNewPulsesNearby !== undefined)
            updateData.notifyNewPulsesNearby = notifyNewPulsesNearby;
        if (notifyPulseInvitations !== undefined)
            updateData.notifyPulseInvitations = notifyPulseInvitations;
        if (notifyPulseUpdates !== undefined)
            updateData.notifyPulseUpdates = notifyPulseUpdates;
        if (notifyNewMessages !== undefined)
            updateData.notifyNewMessages = notifyNewMessages;
        if (notifyNewFollowers !== undefined)
            updateData.notifyNewFollowers = notifyNewFollowers;
        if (notifyFriendRequests !== undefined)
            updateData.notifyFriendRequests = notifyFriendRequests;
        if (notifyPostReactions !== undefined)
            updateData.notifyPostReactions = notifyPostReactions;
        // Appearance settings
        if (themePreference !== undefined)
            updateData.themePreference = themePreference;
        if (languagePreference !== undefined)
            updateData.languagePreference = languagePreference;
        if (textSizeScale !== undefined) {
            // Validate text size scale (0.8 - 1.4)
            if (textSizeScale < 0.8 || textSizeScale > 1.4) {
                return res.status(400).json({ error: 'Text size scale must be between 0.8 and 1.4' });
            }
            updateData.textSizeScale = textSizeScale;
        }
        // Other settings
        if (hapticFeedbackEnabled !== undefined)
            updateData.hapticFeedbackEnabled = hapticFeedbackEnabled;
        if (activityStatusVisible !== undefined)
            updateData.activityStatusVisible = activityStatusVisible;
        const updatedUser = await prisma.user.update({
            where: { id: req.user.id },
            data: updateData,
            select: {
                // Privacy settings
                profileVisibility: true,
                locationSharing: true,
                pulseHistoryVisibility: true,
                friendRequestsFrom: true,
                showOnlineStatus: true,
                allowMessageRequests: true,
                showInSearch: true,
                // Notification settings
                pushNotificationsEnabled: true,
                notifyNewPulsesNearby: true,
                notifyPulseInvitations: true,
                notifyPulseUpdates: true,
                notifyNewMessages: true,
                notifyNewFollowers: true,
                notifyFriendRequests: true,
                notifyPostReactions: true,
                // Appearance settings
                themePreference: true,
                languagePreference: true,
                textSizeScale: true,
                // Other settings
                hapticFeedbackEnabled: true,
                activityStatusVisible: true,
            }
        });
        res.json(updatedUser);
    }
    catch (error) {
        console.error('Error updating settings:', error);
        res.status(500).json({ error: 'Failed to update settings' });
    }
});
// GET /api/settings/blocked-users - Get blocked users
router.get('/blocked-users', authenticateUser, async (req, res) => {
    try {
        const blockedUsers = await prisma.blockedUser.findMany({
            where: { blockingUserId: req.user.id },
            include: {
                blockedUser: {
                    select: {
                        id: true,
                        displayName: true,
                        email: true,
                        profileImageUrl: true,
                    }
                }
            },
            orderBy: { createdAt: 'desc' }
        });
        res.json(blockedUsers);
    }
    catch (error) {
        console.error('Error fetching blocked users:', error);
        res.status(500).json({ error: 'Failed to fetch blocked users' });
    }
});
// POST /api/settings/block-user - Block a user
router.post('/block-user', authenticateUser, async (req, res) => {
    try {
        const { userId, reason } = req.body;
        if (!userId) {
            return res.status(400).json({ error: 'User ID is required' });
        }
        if (userId === req.user.id) {
            return res.status(400).json({ error: 'Cannot block yourself' });
        }
        // Check if already blocked
        const existingBlock = await prisma.blockedUser.findUnique({
            where: {
                blockingUserId_blockedUserId: {
                    blockingUserId: req.user.id,
                    blockedUserId: userId,
                }
            }
        });
        if (existingBlock) {
            return res.status(400).json({ error: 'User is already blocked' });
        }
        const blockedUser = await prisma.blockedUser.create({
            data: {
                blockingUserId: req.user.id,
                blockedUserId: userId,
                reason,
            },
            include: {
                blockedUser: {
                    select: {
                        id: true,
                        displayName: true,
                        email: true,
                        profileImageUrl: true,
                    }
                }
            }
        });
        res.json(blockedUser);
    }
    catch (error) {
        console.error('Error blocking user:', error);
        res.status(500).json({ error: 'Failed to block user' });
    }
});
// DELETE /api/settings/unblock-user/:userId - Unblock a user
router.delete('/unblock-user/:userId', authenticateUser, async (req, res) => {
    try {
        const { userId } = req.params;
        if (!userId) {
            return res.status(400).json({ error: 'User ID is required' });
        }
        await prisma.blockedUser.delete({
            where: {
                blockingUserId_blockedUserId: {
                    blockingUserId: req.user.id,
                    blockedUserId: userId,
                }
            }
        });
        res.json({ message: 'User unblocked successfully' });
    }
    catch (error) {
        console.error('Error unblocking user:', error);
        res.status(500).json({ error: 'Failed to unblock user' });
    }
});
exports.default = router;
//# sourceMappingURL=settings.js.map