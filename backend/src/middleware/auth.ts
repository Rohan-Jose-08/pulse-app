import express from 'express';
import admin from 'firebase-admin';
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

// Middleware to authenticate users
export const authenticateUser = async (req: express.Request, res: express.Response, next: express.NextFunction) => {
  const authHeader = req.headers.authorization;
  if (!authHeader?.startsWith('Bearer ')) {
    return res.status(401).send('Missing or invalid token');
  }

  const idToken = authHeader.split(' ')[1];

  try {
    const checkRevoked = String(process.env.AUTH_CHECK_REVOKED ?? '').toLowerCase() === 'true';
    const decoded = await admin.auth().verifyIdToken(idToken, checkRevoked);
    const { uid } = decoded;
    
    // Check if user exists in our database
    const user = await prisma.user.findUnique({ where: { firebaseUid: uid } });
    if (!user) {
      return res.status(401).json({ error: 'User not found' });
    }
    
    console.log('Auth middleware - User found:', { firebaseUid: uid, userId: user.id });
    
    req.user = user;
    next();
  } catch (err) {
    console.error(err);
    res.status(401).json({ error: 'Unauthorized' });
  }
};
