import type { Server } from 'socket.io';

let ioInstance: Server | null = null;

// Global user sockets map (userId -> socketIds)
export const userSockets = new Map<string, Set<string>>();

export function setIo(instance: Server) {
  ioInstance = instance;
}

export function getIo(): Server | null {
  return ioInstance;
}

// Named export for convenient import
export { ioInstance as io };
