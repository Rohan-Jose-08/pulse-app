import type { Server } from 'socket.io';

let ioInstance: Server | null = null;

// Global user sockets map (userId -> socketIds)
export const userSockets = new Map<string, Set<string>>();

// Activity status tracking
interface UserActivity {
  userId: string;
  status: 'online' | 'offline' | 'away';
  lastSeen: Date;
  socketCount: number;
}

// Map of userId to activity status
export const userActivityStatus = new Map<string, UserActivity>();

export function setIo(instance: Server) {
  ioInstance = instance;
}

export function getIo(): Server | null {
  return ioInstance;
}

// Set user online
export function setUserOnline(userId: string) {
  const activity: UserActivity = {
    userId,
    status: 'online',
    lastSeen: new Date(),
    socketCount: userSockets.get(userId)?.size || 0,
  };
  userActivityStatus.set(userId, activity);
  
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
export function setUserOffline(userId: string) {
  const activity: UserActivity = {
    userId,
    status: 'offline',
    lastSeen: new Date(),
    socketCount: 0,
  };
  userActivityStatus.set(userId, activity);
  
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
export function setUserAway(userId: string) {
  const existing = userActivityStatus.get(userId);
  if (existing && existing.status === 'online') {
    const activity: UserActivity = {
      userId,
      status: 'away',
      lastSeen: new Date(),
      socketCount: existing.socketCount,
    };
    userActivityStatus.set(userId, activity);
    
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
export function getUserActivity(userId: string): UserActivity | null {
  return userActivityStatus.get(userId) || null;
}

// Get all online users
export function getOnlineUsers(): string[] {
  const onlineUsers: string[] = [];
  userActivityStatus.forEach((activity, userId) => {
    if (activity.status === 'online') {
      onlineUsers.push(userId);
    }
  });
  return onlineUsers;
}

// Update last seen
export function updateLastSeen(userId: string) {
  const activity = userActivityStatus.get(userId);
  if (activity) {
    activity.lastSeen = new Date();
    userActivityStatus.set(userId, activity);
  }
}

// Named export for convenient import
export { ioInstance as io };
