# ML-Powered Pulse Recommendations - Implementation Guide

## Overview

This document describes the complete ML recommendation system for Pulse, enabling personalized pulse suggestions based on user behavior, preferences, and contextual signals.

## Architecture

```
┌─────────────────┐
│  Flutter App    │
│  (Dart)         │
└────────┬────────┘
         │ HTTP/REST
         ↓
┌─────────────────┐      ┌──────────────────┐
│  Node.js API    │─────→│  ML Service      │
│  (TypeScript)   │←─────│  (Python/Flask)  │
└────────┬────────┘      └──────────────────┘
         │
         ↓
┌─────────────────┐
│  PostgreSQL     │
│  (Prisma)       │
└─────────────────┘
```

## Project Structure

```
backend/
├── ml-service/              # Python ML Service
│   ├── app.py              # Flask application
│   ├── requirements.txt    # Python dependencies
│   ├── Dockerfile          # Docker configuration
│   ├── test_service.py     # Test suite
│   └── README.md           # ML service docs
├── src/
│   ├── services/
│   │   └── recommendation.ts  # Node.js recommendation service
│   └── routes/
│       └── pulses.ts       # API endpoints with ML integration
└── prisma/
    └── schema.prisma       # Database schema with ML tables
```

## Database Schema

### New Tables Added

#### `PulseInteraction`
Tracks all user interactions with pulses for ML training.

```prisma
model PulseInteraction {
  id              String   @id @default(cuid())
  userId          String
  pulseId         String
  interactionType String   // 'view', 'join', 'message', 'invite', 'share', 'recommendation_view', 'recommendation_click'
  duration        Int?     // Duration in seconds
  timestamp       DateTime @default(now())
  source          String?  // 'feed', 'map', 'recommendation', 'search', 'notification'
  deviceType      String?  // 'ios', 'android', 'web'
}
```

#### `PulseRecommendation`
Stores precomputed recommendations for fast retrieval (15-minute cache).

```prisma
model PulseRecommendation {
  id           String   @id @default(cuid())
  userId       String
  pulseId      String
  score        Float    // 0.0 - 1.0
  reason       String?  // Human-readable reason
  generatedAt  DateTime @default(now())
  viewed       Boolean  @default(false)
  clicked      Boolean  @default(false)
}
```

#### `UserEmbedding`
Stores user vector embeddings for similarity-based recommendations (future enhancement).

```prisma
model UserEmbedding {
  userId     String   @id
  embedding  Float[]  // Vector representation
  updatedAt  DateTime @default(now())
}
```

#### `UserFeatureCache`
Caches computed user features (1-hour cache).

```prisma
model UserFeatureCache {
  userId                  String   @id
  avgSessionDuration      Float?
  preferredCategories     String[]
  preferredTimeSlots      String[]
  socialActivityScore     Float?
  messagingFrequency      Float?
  inviteAcceptanceRate    Float?
  lastPulseJoinedAt       DateTime?
  totalPulsesJoined       Int
  totalPulsesCreated      Int
  avgDistanceKm           Float?
  updatedAt               DateTime
}
```

## Backend Implementation (Node.js)

### Service: `recommendation.ts`

**Location:** `backend/src/services/recommendation.ts`

#### Key Functions:

1. **`getPersonalizedRecommendations(userId, lat, lng)`**
   - Returns top 20 personalized pulse recommendations
   - Uses 15-minute cache
   - Falls back to rule-based recommendations if ML service fails

2. **`generateUserFeatures(userId)`**
   - Computes user feature vector from interaction history
   - Caches for 1 hour
   - Includes: categories, time slots, social score, messaging frequency, etc.

3. **`trackPulseInteraction(userId, pulseId, type, duration, source)`**
   - Records user interactions for ML training
   - Invalidates feature cache on significant interactions (join, etc.)

4. **`getFallbackRecommendations(userId, pulses, features)`**
   - Rule-based scoring when ML service unavailable
   - Scores based on: followed users, categories, distance, popularity

### API Endpoints

**Location:** `backend/src/routes/pulses.ts`

#### `GET /api/pulses/personalized`

**Query Parameters:**
- `latitude` (optional): User's latitude
- `longitude` (optional): User's longitude

**Response:**
```json
{
  "recommendations": [
    {
      "id": "pulse123",
      "title": "Basketball Game",
      "category": "sports",
      "recommendationScore": 0.87,
      "recommendationReason": "Matches your interests • Nearby • Starting soon",
      "location": { ... },
      "author": { ... },
      "participants": [...],
      "participantCount": 5
    }
  ],
  "count": 20
}
```

#### `POST /api/pulses/track-interaction`

**Body:**
```json
{
  "pulseId": "pulse123",
  "interactionType": "view",
  "duration": 45,
  "source": "feed"
}
```

**Interaction Types:**
- `view`: User viewed pulse details
- `join`: User joined pulse
- `message`: User sent message in pulse chat
- `invite`: User invited others
- `share`: User shared pulse
- `recommendation_view`: User saw recommendation
- `recommendation_click`: User clicked recommendation

## ML Service (Python/Flask)

**Location:** `backend/ml-service/app.py`

### Recommendation Algorithm

The ML service uses a **hybrid scoring approach**:

#### Scoring Components:

1. **Content-Based (30%)**
   - Category matching with user preferences
   - Interest alignment
   - Ranked by preference order

2. **Temporal (20%)**
   - Time until event starts
   - Time of day preferences (morning/afternoon/evening/night)
   - Urgency weighting

3. **Location (20%)**
   - Distance from user (Haversine)
   - Proximity scoring: < 1km (1.0), < 3km (0.9), < 10km (0.7), etc.

4. **Social (15%)**
   - Social activity score
   - Participant count
   - Adaptive to user's social engagement level

5. **Popularity (10%)**
   - Number of current participants
   - Event momentum

6. **Recency (5%)**
   - Bonus for newly created pulses

### Endpoints

#### `POST /recommend`

**Request:**
```json
{
  "userId": "user123",
  "userFeatures": {
    "preferredCategories": ["sports", "music"],
    "preferredTimeSlots": ["evening", "afternoon"],
    "socialActivityScore": 0.7,
    "messagingFrequency": 15.5
  },
  "availablePulses": [...]
}
```

**Response:**
```json
[
  {
    "pulseId": "pulse1",
    "score": 0.87,
    "reason": "Matches your interests • Nearby • Starting soon"
  }
]
```

## Flutter Integration

**Location:** `pulse/lib/backend/api_service.dart`

### New Methods:

#### `getPersonalizedPulses({latitude, longitude})`
Fetches ML-powered recommendations from backend.

```dart
final recommendations = await ApiService.instance.getPersonalizedPulses(
  latitude: 40.7128,
  longitude: -74.0060,
);
```

#### Tracking Methods:

```dart
// Track various interactions
await ApiService.instance.trackPulseView('pulse123', durationSeconds: 45);
await ApiService.instance.trackPulseJoin('pulse123');
await ApiService.instance.trackPulseMessage('pulse123');
await ApiService.instance.trackPulseShare('pulse123');
await ApiService.instance.trackRecommendationClick('pulse123');
```

## Deployment

### 1. Backend (Node.js)

Already running - no additional deployment needed.

### 2. ML Service (Python)

#### Local Development:
```bash
cd backend/ml-service
pip install -r requirements.txt
python app.py
```

The service will start on `http://localhost:5001`

#### Production Options:

**Option A: Docker**
```bash
cd backend/ml-service
docker build -t pulse-ml-service .
docker run -p 5001:5001 pulse-ml-service
```

**Option B: Railway (Recommended)**
1. Create new project on Railway.app
2. Connect GitHub repo
3. Set root directory to `backend/ml-service`
4. Railway auto-detects Python and deploys
5. Note the deployed URL (e.g., `https://pulse-ml-xxxxx.railway.app`)

**Option C: Google Cloud Run**
```bash
cd backend/ml-service
gcloud run deploy pulse-ml-service \
  --source . \
  --platform managed \
  --region us-central1 \
  --allow-unauthenticated
```

### 3. Configure ML Service URL

Set environment variable in your Node.js backend:

```bash
# backend/.env
ML_SERVICE_URL=http://localhost:5001  # Development
# ML_SERVICE_URL=https://pulse-ml-xxxxx.railway.app  # Production
```

## Testing

### 1. Test ML Service

```bash
cd backend/ml-service

# Health check
curl http://localhost:5001/health

# Run test suite
python test_service.py
```

### 2. Test Backend API

```bash
# Get personalized recommendations (requires auth token)
curl -X GET "http://localhost:3000/api/pulses/personalized?latitude=40.7128&longitude=-74.0060" \
  -H "Authorization: Bearer YOUR_FIREBASE_TOKEN"

# Track interaction
curl -X POST http://localhost:3000/api/pulses/track-interaction \
  -H "Authorization: Bearer YOUR_FIREBASE_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "pulseId": "pulse123",
    "interactionType": "view",
    "duration": 30,
    "source": "feed"
  }'
```

### 3. Test Flutter Integration

Add debug logging in your Flutter app:

```dart
final recommendations = await ApiService.instance.getPersonalizedPulses(
  latitude: position.latitude,
  longitude: position.longitude,
);
print('Received ${recommendations.length} recommendations');
for (final rec in recommendations) {
  print('${rec['title']}: ${rec['recommendationReason']}');
}
```

## Monitoring & Analytics

### Key Metrics to Track:

1. **Recommendation Performance**
   - Click-through rate (CTR): `clicks / views`
   - Conversion rate: `joins / clicks`
   - Average score of clicked recommendations

2. **User Engagement**
   - Time spent viewing recommendations
   - Recommendations viewed per session
   - Percentage of users who interact with recommendations

3. **System Performance**
   - ML service response time (target: < 100ms)
   - Cache hit rate (target: > 70%)
   - Feature computation time

## Summary

The ML recommendation system is now fully implemented with:

✅ Database schema (4 new tables)
✅ Backend service (`recommendation.ts`)
✅ API endpoints (`/personalized`, `/track-interaction`)
✅ ML service (Python/Flask in `backend/ml-service`)
✅ Flutter integration (API methods)
✅ Caching (15-min recommendations, 1-hour features)
✅ Fallback logic (rule-based when ML unavailable)
✅ Tracking system (views, clicks, interactions)
✅ Explainable recommendations (human-readable reasons)

## Next Steps

1. **Install Python dependencies**: `cd backend/ml-service && pip install -r requirements.txt`
2. **Start ML service**: `python app.py` (runs on port 5001)
3. **Test ML service**: `python test_service.py`
4. **Update backend .env**: Set `ML_SERVICE_URL=http://localhost:5001`
5. **Add UI components** in Flutter to display recommendations
6. **Deploy ML service** to production when ready

🎉 Your pulse recommendation system is ready to use!
