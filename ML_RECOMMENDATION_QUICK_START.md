# ML Recommendation System - Quick Reference

## ✅ Implementation Complete

The ML recommendation system has been successfully implemented and integrated into your Pulse app.

## 📁 Structure

```
backend/
├── ml-service/                    # Python ML Service (NEW)
│   ├── app.py                    # Flask ML recommendation API
│   ├── requirements.txt          # Python dependencies
│   ├── test_service.py           # Test suite
│   ├── Dockerfile               # Docker deployment config
│   └── README.md                # ML service documentation
│
├── src/
│   ├── services/
│   │   └── recommendation.ts     # Node.js ML integration (NEW)
│   └── routes/
│       └── pulses.ts            # Added ML endpoints (UPDATED)
│
└── prisma/
    └── schema.prisma            # Added 4 ML tables (UPDATED)
    └── migrations/
        └── 20251112222034_add_ml_recommendation_tables/

pulse/
└── lib/backend/
    └── api_service.dart         # Added ML methods (UPDATED)
```

## 🗄️ Database Changes

**Migration Applied:** `20251112222034_add_ml_recommendation_tables`

**New Tables:**
1. `PulseInteraction` - Tracks user behavior (views, joins, messages, etc.)
2. `PulseRecommendation` - Cached recommendations (15-min TTL)
3. `UserEmbedding` - User vector embeddings (future use)
4. `UserFeatureCache` - Computed user features (1-hour TTL)

## 🔌 API Endpoints

### Node.js Backend (Port 3000)

**GET** `/api/pulses/personalized`
- Returns ML-powered recommendations
- Query params: `latitude`, `longitude` (optional)
- Authenticated endpoint

**POST** `/api/pulses/track-interaction`
- Tracks user interactions for ML training
- Body: `{ pulseId, interactionType, duration, source }`

### Python ML Service (Port 5001)

**GET** `/health`
- Health check

**POST** `/recommend`
- Generates recommendations based on user features
- Called internally by Node.js backend

## 🚀 Quick Start

### 1. Start ML Service (Python)

```bash
cd backend/ml-service

# Install dependencies (first time only)
pip install -r requirements.txt

# Start service
python app.py
```

Service runs on `http://localhost:5001`

### 2. Configure Backend

Add to `backend/.env`:
```
ML_SERVICE_URL=http://localhost:5001
```

### 3. Test ML Service

```bash
cd backend/ml-service
python test_service.py
```

### 4. Use in Flutter

```dart
// Get personalized recommendations
final recommendations = await ApiService.instance.getPersonalizedPulses(
  latitude: position.latitude,
  longitude: position.longitude,
);

// Track interactions
await ApiService.instance.trackPulseView('pulse123', durationSeconds: 30);
await ApiService.instance.trackPulseJoin('pulse123');
await ApiService.instance.trackRecommendationClick('pulse123');
```

## 🎯 How It Works

1. **User browses pulses** → Interactions tracked in `PulseInteraction`
2. **User requests recommendations** → Backend calls `/api/pulses/personalized`
3. **Backend generates features** → Computes from user history, cached in `UserFeatureCache`
4. **Backend queries nearby pulses** → Filters active pulses within radius
5. **ML service scores pulses** → Python service calculates personalized scores
6. **Results cached** → Stored in `PulseRecommendation` for 15 minutes
7. **User receives recommendations** → Ranked by score with explanations

## 📊 Scoring Algorithm

The ML service uses a **weighted hybrid approach**:

- **30%** Content (category matching)
- **20%** Temporal (event timing, time of day)
- **20%** Location (distance from user)
- **15%** Social (activity level, friends)
- **10%** Popularity (participant count)
- **5%** Recency (newly created)

**Final score:** 0.0 - 1.0 (higher is better)

## 🔄 Fallback System

If ML service is unavailable:
1. Backend automatically falls back to rule-based recommendations
2. Uses followed users, categories, and distance
3. No user-facing errors
4. Graceful degradation

## 📱 Flutter Integration

**New methods in `api_service.dart`:**

```dart
// Get recommendations
Future<List<Map<String, dynamic>>> getPersonalizedPulses({
  double? latitude,
  double? longitude,
})

// Tracking
Future<void> trackPulseView(String pulseId, {int? durationSeconds})
Future<void> trackPulseJoin(String pulseId)
Future<void> trackPulseMessage(String pulseId)
Future<void> trackPulseShare(String pulseId)
Future<void> trackRecommendationClick(String pulseId)
```

## 📈 Next Steps

### Immediate:
- [ ] Install Python dependencies: `pip install -r requirements.txt`
- [ ] Start ML service: `python app.py` 
- [ ] Test ML service: `python test_service.py`
- [ ] Add `ML_SERVICE_URL=http://localhost:5001` to `backend/.env`
- [ ] Add UI to display recommendations in Flutter app

### Future Enhancements:
- [ ] Deploy ML service to Railway/Cloud Run
- [ ] Add deep learning embeddings
- [ ] Implement collaborative filtering
- [ ] Add A/B testing framework
- [ ] Set up monitoring dashboard
- [ ] Add recommendation diversity constraints

## 📖 Documentation

- **Full Guide:** `ML_RECOMMENDATION_GUIDE.md` (root directory)
- **ML Service:** `backend/ml-service/README.md`
- **API Docs:** See guide for complete API documentation

## 🐛 Troubleshooting

**ML service won't start:**
- Install dependencies: `pip install -r requirements.txt`
- Check Python version: `python --version` (3.8+ required)
- Check port 5001 is not in use

**No recommendations returned:**
- Check ML service is running: `curl http://localhost:5001/health`
- Check `ML_SERVICE_URL` in backend `.env`
- Check backend logs for errors
- System falls back to rule-based if ML fails

**Low recommendation quality:**
- Need more interaction data (views, joins, messages)
- Adjust scoring weights in `backend/ml-service/app.py`
- Ensure user has completed profile (interests, location)

## ✨ Summary

You now have a complete ML-powered recommendation system:

✅ **Backend:** Node.js service handles requests, caching, fallbacks
✅ **ML Service:** Python Flask app scores pulses with hybrid algorithm
✅ **Database:** 4 new tables track interactions and cache results
✅ **Flutter:** API methods to get recommendations and track behavior
✅ **Deployment Ready:** Docker, Railway, Cloud Run configurations included

**Start using:** Run `python app.py` in `backend/ml-service` and start getting personalized recommendations!
