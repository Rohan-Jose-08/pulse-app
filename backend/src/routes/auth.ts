import express from 'express';
import admin from '../firebase';
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();
const router = express.Router();

router.post('/', async (req, res) => {
  const authHeader = req.headers.authorization;
  if (!authHeader?.startsWith('Bearer ')) {
    return res.status(401).send('Missing or invalid token');
  }

  const idToken = authHeader.split(' ')[1];

  try {
    const checkRevoked = String(process.env.AUTH_CHECK_REVOKED ?? '').toLowerCase() === 'true';
    const decoded = await admin.auth().verifyIdToken(idToken, checkRevoked);
    const { uid, email, name, picture } = decoded;

    let user = await prisma.user.findUnique({ where: { firebaseUid: uid } });

    if (!user) {
      // Ensure email is unique by always using the Firebase UID in the email
      // This prevents conflicts with the @unique constraint on the email field
      const emailToUse = email && email.trim() !== '' ? `${uid}+${email}` : `${uid}@placeholder.com`;
      user = await prisma.user.create({
        data: {
          id: uid,
          firebaseUid: uid,
          email: emailToUse,
          displayName: name ?? '',
        },
      });
    }

    res.json({ user });
  } catch (err) {
    console.error('Error in auth route:', err);
    // Send a more detailed error message for debugging
    if (err instanceof Error) {
      res.status(500).json({ error: 'Internal server error', details: err.message });
    } else {
      res.status(500).json({ error: 'Internal server error', details: String(err) });
    }
  }
});

export default router;
