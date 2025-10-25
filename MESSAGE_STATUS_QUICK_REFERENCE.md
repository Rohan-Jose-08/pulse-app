# Message Status Quick Reference

## Visual Indicators

When you send a message, you'll see one of these status indicators next to the timestamp:

### ✓ Single Gray Check
**Meaning:** Message has been sent to the server but not yet delivered to the recipient(s)
- The message is stored in the database
- Recipient(s) may be offline or haven't received it yet

### ✓✓ Double Gray Check  
**Meaning:** Message has been delivered to at least one recipient
- Recipient(s) received the message on their device
- They haven't opened the chat yet or haven't scrolled to your message

### ✓✓ Double Blue Check
**Meaning:** Message has been read by at least one recipient
- Recipient(s) have opened the chat
- Your message is visible on their screen

## Group Chats

In group chats:
- **Gray double check (✓✓)** appears when ANY member has received the message
- **Blue double check (✓✓)** appears when ALL members have read the message

## Privacy & Settings

Currently, read receipts are always enabled. Future updates may include:
- Option to disable sending read receipts
- Option to hide your read status from others
- Detailed "Read by" list showing who read the message and when

## Technical Details

### For Developers

**Database Fields:**
- `deliveredTo: String[]` - Array of user IDs who received the message
- `readBy: String[]` - Array of user IDs who read the message

**Socket Events:**
```typescript
// Mark message as delivered
socket.emit('message:delivered', {
  conversationId: string,
  messageId: string
});

// Mark message as read
socket.emit('message:read', {
  conversationId: string,
  messageId: string
});

// Listen for status updates
socket.on('message:status-update', (data) => {
  // data.messageId
  // data.deliveredTo - updated array
  // data.readBy - updated array
  // data.status - 'delivered' or 'read'
});
```

**Flutter Methods:**
```dart
// Mark as delivered
SocketService.instance.markMessageDelivered(
  conversationId: chatId,
  messageId: messageId,
);

// Mark as read
SocketService.instance.markMessageRead(
  conversationId: chatId,
  messageId: messageId,
);

// Listen for updates
SocketService.instance.messageStatusUpdates.listen((data) {
  // Handle status update
});
```

## Automatic Behavior

The app automatically handles message status:

1. **Delivery:** Messages are marked as delivered when:
   - Recipient is online when message is sent
   - Recipient comes online and receives pending messages
   - Recipient opens the app and syncs messages

2. **Read:** Messages are marked as read when:
   - Recipient opens the chat
   - Message becomes visible on screen (scrolled into view)
   - Chat is in focus/foreground

## Known Behaviors

- ✅ Your own messages are never marked as delivered/read by yourself
- ✅ System messages don't show status indicators
- ✅ Status updates happen in real-time without page refresh
- ✅ Works in both direct (1:1) and group chats
- ✅ Offline messages get proper status when recipient comes online

## Troubleshooting

**Status not updating?**
- Check internet connection
- Ensure both users are connected to the backend
- Try closing and reopening the chat

**Always showing single check?**
- Recipient might be offline
- Check if recipient's app is running
- Verify socket connection is active

**Blue checks not appearing?**
- Recipient needs to actually open the chat
- Message must be visible on screen (scrolled into view)
- In group chats, ALL members must read it for blue checks
