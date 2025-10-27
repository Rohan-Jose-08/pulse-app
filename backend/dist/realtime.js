"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.io = exports.userActivityStatus = exports.userSockets = void 0;
exports.setIo = setIo;
exports.getIo = getIo;
exports.setUserOnline = setUserOnline;
exports.setUserOffline = setUserOffline;
exports.setUserAway = setUserAway;
exports.getUserActivity = getUserActivity;
exports.getOnlineUsers = getOnlineUsers;
exports.updateLastSeen = updateLastSeen;
let ioInstance = null;
exports.io = ioInstance;
// Global user sockets map (userId -> socketIds)
exports.userSockets = new Map();
// Map of userId to activity status
exports.userActivityStatus = new Map();
function setIo(instance) {
    exports.io = ioInstance = instance;
}
function getIo() {
    return ioInstance;
}
// Set user online
function setUserOnline(userId) {
    const activity = {
        userId,
        status: 'online',
        lastSeen: new Date(),
        socketCount: exports.userSockets.get(userId)?.size || 0,
    };
    exports.userActivityStatus.set(userId, activity);
    // Broadcast status to all connected users
    if (ioInstance) {
        ioInstance.emit('user:status', {
            userId,
            status: 'online',
            lastSeen: activity.lastSeen.toISOString(),
        });
    }
    return activity;
}
// Set user offline
function setUserOffline(userId) {
    const activity = {
        userId,
        status: 'offline',
        lastSeen: new Date(),
        socketCount: 0,
    };
    exports.userActivityStatus.set(userId, activity);
    // Broadcast status to all connected users
    if (ioInstance) {
        ioInstance.emit('user:status', {
            userId,
            status: 'offline',
            lastSeen: activity.lastSeen.toISOString(),
        });
    }
    return activity;
}
// Set user away (after idle timeout)
function setUserAway(userId) {
    const existing = exports.userActivityStatus.get(userId);
    if (existing && existing.status === 'online') {
        const activity = {
            userId,
            status: 'away',
            lastSeen: new Date(),
            socketCount: existing.socketCount,
        };
        exports.userActivityStatus.set(userId, activity);
        // Broadcast status to all connected users
        if (ioInstance) {
            ioInstance.emit('user:status', {
                userId,
                status: 'away',
                lastSeen: activity.lastSeen.toISOString(),
            });
        }
        return activity;
    }
}
// Get user activity status
function getUserActivity(userId) {
    return exports.userActivityStatus.get(userId) || null;
}
// Get all online users
function getOnlineUsers() {
    const onlineUsers = [];
    exports.userActivityStatus.forEach((activity, userId) => {
        if (activity.status === 'online') {
            onlineUsers.push(userId);
        }
    });
    return onlineUsers;
}
// Update last seen
function updateLastSeen(userId) {
    const activity = exports.userActivityStatus.get(userId);
    if (activity) {
        activity.lastSeen = new Date();
        exports.userActivityStatus.set(userId, activity);
    }
}
//# sourceMappingURL=realtime.js.map