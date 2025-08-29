"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = __importDefault(require("express"));
const client_1 = require("@prisma/client");
const firebase_1 = __importDefault(require("../firebase"));
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
        const decoded = await firebase_1.default.auth().verifyIdToken(idToken);
        const { uid } = decoded;
        const user = await prisma.user.findUnique({ where: { firebaseUid: uid } });
        if (!user)
            return res.status(401).json({ error: 'User not found' });
        req.user = user;
        next();
    }
    catch (err) {
        console.error(err);
        res.status(401).json({ error: 'Unauthorized' });
    }
};
// Create or get a one-to-one conversation between current user and target user
router.post('/conversations/with/:otherUserId', authenticateUser, async (req, res) => {
    try {
        const otherUserId = req.params.otherUserId;
        const me = req.user.id;
        if (otherUserId === me)
            return res.status(400).json({ error: 'Cannot create conversation with yourself' });
        // Find existing conversation with both participants (naive check)
        let convo = await prisma.conversation.findFirst({
            where: {
                AND: [
                    { participants: { some: { id: me } } },
                    { participants: { some: { id: otherUserId } } },
                ],
            },
            include: { participants: true },
        });
        if (!convo) {
            convo = await prisma.conversation.create({
                data: {
                    participants: {
                        connect: [{ id: me }, { id: otherUserId }],
                    },
                },
                include: { participants: true },
            });
        }
        res.json(convo);
    }
    catch (e) {
        console.error('create/get conversation error', e);
        res.status(500).json({ error: 'Internal server error' });
    }
});
// List my conversations
router.get('/conversations', authenticateUser, async (req, res) => {
    try {
        const me = req.user.id;
        const convos = await prisma.conversation.findMany({
            where: { participants: { some: { id: me } } },
            orderBy: { updatedAt: 'desc' },
            include: {
                participants: { select: { id: true, displayName: true, profileImageUrl: true } },
                pulse: { select: { id: true, title: true, imageUrl: true } },
            },
        });
        res.json(convos.map((c) => ({
            id: c.id,
            participants: c.participants,
            updatedAt: c.updatedAt,
            createdAt: c.createdAt,
            lastMessageText: c.lastMessageText,
            lastSenderId: c.lastSenderId,
            isGroup: c.isGroup,
            name: c.name || c.pulse?.title || null,
            avatarUrl: c.avatarUrl || c.pulse?.imageUrl || null,
            pulseId: c.pulseId,
        })));
    }
    catch (e) {
        console.error('list conversations error', e);
        res.status(500).json({ error: 'Internal server error' });
    }
});
// Get paginated messages for a conversation
router.get('/conversations/:id/messages', authenticateUser, async (req, res) => {
    try {
        const me = req.user.id;
        const { id } = req.params;
        const { cursor, limit = '30' } = req.query;
        const take = Math.max(1, Math.min(parseInt(limit, 10) || 30, 100));
        const convo = await prisma.conversation.findUnique({
            where: { id },
            include: { participants: true },
        });
        if (!convo)
            return res.status(404).json({ error: 'Conversation not found' });
        const isParticipant = convo.participants.some((p) => p.id === me);
        if (!isParticipant)
            return res.status(403).json({ error: 'Forbidden' });
        const messages = await prisma.message.findMany({
            where: { conversationId: id },
            orderBy: { createdAt: 'desc' },
            take,
            cursor: cursor ? { id: cursor } : undefined,
            skip: cursor ? 1 : 0,
        });
        // Fetch reactions for these messages
        const ids = messages.map(m => m.id);
        let reactions = [];
        if (ids.length) {
            // @ts-ignore - messageReaction available after prisma generate
            reactions = await prisma.messageReaction.findMany({
                where: { messageId: { in: ids } },
                select: { messageId: true, emoji: true, userId: true },
            });
        }
        const reactionMap = {};
        reactions.forEach(r => {
            if (!reactionMap[r.messageId])
                reactionMap[r.messageId] = {};
            if (!reactionMap[r.messageId][r.emoji])
                reactionMap[r.messageId][r.emoji] = [];
            reactionMap[r.messageId][r.emoji].push(r.userId);
        });
        res.json({
            messages: messages.reverse().map(m => ({
                ...m,
                reactions: reactionMap[m.id] || {},
            })),
            nextCursor: messages.length === take ? messages[messages.length - 1].id : null,
        });
    }
    catch (e) {
        console.error('list messages error', e);
        res.status(500).json({ error: 'Internal server error' });
    }
});
// Invite members to a conversation (creates pending invitations + notification)
router.post('/conversations/:id/invitations', authenticateUser, async (req, res) => {
    try {
        const me = req.user.id;
        const { id } = req.params;
        const { userIds } = req.body;
        if (!Array.isArray(userIds) || userIds.length === 0) {
            return res.status(400).json({ error: 'userIds required' });
        }
        const convo = await prisma.conversation.findUnique({ where: { id }, include: { participants: true } });
        if (!convo)
            return res.status(404).json({ error: 'Conversation not found' });
        const isParticipant = convo.participants.some(p => p.id === me);
        if (!isParticipant)
            return res.status(403).json({ error: 'Forbidden' });
        const created = [];
        for (const targetId of userIds) {
            if (!targetId || targetId === me)
                continue;
            const alreadyParticipant = convo.participants.some(p => p.id === targetId);
            if (alreadyParticipant)
                continue;
            try {
                const invite = await prisma.conversationInvitation.upsert({
                    where: { conversationId_inviteeId: { conversationId: id, inviteeId: targetId } },
                    update: { status: 'PENDING' },
                    create: { conversationId: id, inviterId: me, inviteeId: targetId },
                });
                // Create notification for invitee
                await prisma.notification.create({
                    data: {
                        userId: targetId,
                        type: 'INVITE',
                        title: 'Pulse Chat Invitation',
                        message: 'You have been invited to join a chat',
                        data: { conversationId: id, inviterId: me, invitationId: invite.id },
                    },
                });
                created.push(invite);
            }
            catch (e) {
                console.error('Invite create error', e);
            }
        }
        res.json({ ok: true, created });
    }
    catch (e) {
        console.error('invite members error', e);
        res.status(500).json({ error: 'Internal server error' });
    }
});
// List my pending invitations
router.get('/invitations', authenticateUser, async (req, res) => {
    try {
        const me = req.user.id;
        const list = await prisma.conversationInvitation.findMany({
            where: { inviteeId: me, status: 'PENDING' },
            include: { conversation: true },
            orderBy: { createdAt: 'desc' },
        });
        res.json(list);
    }
    catch (e) {
        console.error('list invites error', e);
        res.status(500).json({ error: 'Internal server error' });
    }
});
// Accept or decline an invitation
router.post('/invitations/:invitationId/respond', authenticateUser, async (req, res) => {
    try {
        const me = req.user.id;
        const { invitationId } = req.params;
        const { action } = req.body;
        const normalized = (action || '').toUpperCase();
        if (!['ACCEPT', 'DECLINE'].includes(normalized)) {
            return res.status(400).json({ error: 'Invalid action' });
        }
        const invitation = await prisma.conversationInvitation.findUnique({ where: { id: invitationId } });
        if (!invitation || invitation.inviteeId !== me) {
            return res.status(404).json({ error: 'Invitation not found' });
        }
        if (invitation.status !== 'PENDING') {
            return res.status(400).json({ error: 'Invitation already responded' });
        }
        if (normalized === 'ACCEPT') {
            // Add user to conversation participants
            await prisma.conversation.update({
                where: { id: invitation.conversationId },
                data: { participants: { connect: { id: me } } },
            });
            await prisma.conversationInvitation.update({
                where: { id: invitationId },
                data: { status: 'ACCEPTED', respondedAt: new Date() },
            });
            return res.json({ ok: true, status: 'ACCEPTED' });
        }
        else {
            await prisma.conversationInvitation.update({
                where: { id: invitationId },
                data: { status: 'DECLINED', respondedAt: new Date() },
            });
            return res.json({ ok: true, status: 'DECLINED' });
        }
    }
    catch (e) {
        console.error('respond invite error', e);
        res.status(500).json({ error: 'Internal server error' });
    }
});
exports.default = router;
//# sourceMappingURL=messages.js.map