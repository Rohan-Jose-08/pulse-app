"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.authenticateUser = void 0;
const firebase_admin_1 = __importDefault(require("firebase-admin"));
const client_1 = require("@prisma/client");
const prisma = new client_1.PrismaClient();
// Middleware to authenticate users
const authenticateUser = async (req, res, next) => {
    const authHeader = req.headers.authorization;
    if (!authHeader?.startsWith('Bearer ')) {
        return res.status(401).send('Missing or invalid token');
    }
    const idToken = authHeader.split(' ')[1];
    try {
        const decoded = await firebase_admin_1.default.auth().verifyIdToken(idToken);
        const { uid } = decoded;
        // Check if user exists in our database
        const user = await prisma.user.findUnique({ where: { firebaseUid: uid } });
        if (!user) {
            return res.status(401).json({ error: 'User not found' });
        }
        console.log('Auth middleware - User found:', {
            firebaseUid: uid,
            userId: user.id,
            userEmail: user.email
        });
        req.user = user;
        next();
    }
    catch (err) {
        console.error(err);
        res.status(401).json({ error: 'Unauthorized' });
    }
};
exports.authenticateUser = authenticateUser;
//# sourceMappingURL=auth.js.map