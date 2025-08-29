"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.authenticateFirebaseToken = void 0;
const firebaseAdmin_1 = require("../firebaseAdmin"); // Adjust path as needed
;
const authenticateFirebaseToken = async (req, res, next) => {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
        return res.status(401).json({ message: 'No authentication token provided.' });
    }
    const idToken = authHeader.split('Bearer ')[1];
    try {
        const decodedToken = await firebaseAdmin_1.auth.verifyIdToken(idToken);
        req.user = {
            uid: decodedToken.uid,
            email: decodedToken.email,
            // You can add other decoded token properties here if needed
        };
        next();
    }
    catch (error) {
        console.error('Error verifying Firebase ID token:', error);
        return res.status(403).json({ message: 'Invalid or expired token.' });
    }
};
exports.authenticateFirebaseToken = authenticateFirebaseToken;
//# sourceMappingURL=authMiddleware.js.map