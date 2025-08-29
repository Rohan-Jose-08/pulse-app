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
// POST /api/posts - Create a new post
router.post('/', authenticateUser, async (req, res) => {
    try {
        const { content, imageUrl, isPublic } = req.body;
        if (!content || typeof content !== 'string' || content.trim().length === 0) {
            return res.status(400).json({ error: 'Content is required' });
        }
        if (content.length > 1000) {
            return res.status(400).json({ error: 'Content too long (max 1000 characters)' });
        }
        if (imageUrl && (typeof imageUrl !== 'string' || !imageUrl.startsWith('http'))) {
            return res.status(400).json({ error: 'imageUrl must be a valid URL' });
        }
        const post = await prisma.post.create({
            data: {
                content: content.trim(),
                imageUrl: imageUrl || null,
                isPublic: isPublic !== undefined ? Boolean(isPublic) : true,
                author: { connect: { id: req.user.id } },
            },
            include: {
                author: {
                    select: { id: true, displayName: true, profileImageUrl: true },
                },
            },
        });
        res.status(201).json(post);
    }
    catch (error) {
        console.error('Error creating post:', error);
        res.status(500).json({ error: 'Failed to create post' });
    }
});
// GET /api/posts/me - Get current user's posts
router.get('/me', authenticateUser, async (req, res) => {
    try {
        const posts = await prisma.post.findMany({
            where: { authorId: req.user.id },
            orderBy: { createdAt: 'desc' },
        });
        res.json(posts);
    }
    catch (error) {
        console.error('Error fetching my posts:', error);
        res.status(500).json({ error: 'Failed to fetch posts' });
    }
});
// GET /api/posts/user/:userId - Get public posts by user
router.get('/user/:userId', async (req, res) => {
    try {
        const { userId } = req.params;
        const posts = await prisma.post.findMany({
            where: { authorId: userId, isPublic: true },
            orderBy: { createdAt: 'desc' },
        });
        res.json(posts);
    }
    catch (error) {
        console.error('Error fetching user posts:', error);
        res.status(500).json({ error: 'Failed to fetch posts' });
    }
});
// DELETE /api/posts/:id - Delete a post (author only)
router.delete('/:id', authenticateUser, async (req, res) => {
    try {
        const { id } = req.params;
        const post = await prisma.post.findUnique({ where: { id } });
        if (!post) {
            return res.status(404).json({ error: 'Post not found' });
        }
        if (post.authorId !== req.user.id) {
            return res.status(403).json({ error: 'Not authorized to delete this post' });
        }
        await prisma.post.delete({ where: { id } });
        res.json({ success: true });
    }
    catch (error) {
        console.error('Error deleting post:', error);
        res.status(500).json({ error: 'Failed to delete post' });
    }
});
exports.default = router;
//# sourceMappingURL=posts.js.map