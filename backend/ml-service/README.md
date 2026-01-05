# Pulse ML Recommendation Service

This is the machine learning service for generating personalized pulse recommendations.

## Features

- **Hybrid Recommendation System**: Combines content-based, collaborative, and contextual filtering
- **Real-time Scoring**: Fast recommendation generation (< 100ms for 100 pulses)
- **Explainable Recommendations**: Provides human-readable reasons
- **Scalable Architecture**: Stateless design for easy horizontal scaling
- **Database Integration**: Direct PostgreSQL access for fetching user data and pulses
- **Interaction Tracking**: Records user interactions for continuous model improvement

## Quick Start

### 1. Install Dependencies

```bash
cd backend/ml-service
pip install -r requirements.txt
```

### 2. Configure Environment

Create a `.env` file in the `ml-service` directory:

```env
# Database connection (use direct PostgreSQL URL, not Prisma Accelerate)
DATABASE_URL=postgresql://user:password@host:port/database

# Optional: Flask configuration
FLASK_ENV=development
FLASK_DEBUG=1
```

**Important**: The ML service requires a direct PostgreSQL connection URL, not a Prisma Accelerate URL. 
If your `backend/.env` uses Prisma Accelerate, you'll need to add a separate direct connection for the ML service.

### 3. Run the Service

```bash
python app.py
```

The service will start on `http://localhost:5001`

### 4. Test the Service

```bash
curl http://localhost:5001/health
```

## API Endpoints

### `GET /health`
Health check endpoint

**Response:**
```json
{
  "status": "healthy",
  "service": "pulse-ml-recommender",
  "version": "1.0.0"
}
```

### `POST /recommend`
Generate personalized recommendations

**Request:**
```json
{
  "userId": "user123",
  "userLocation": {
    "latitude": 40.7128,
    "longitude": -74.0060
  },
  "maxResults": 20
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

**Note**: If `userFeatures` or `availablePulses` are not provided, they will be fetched from the database automatically.

### `POST /interactions`
Track user interaction with a pulse

**Request:**
```json
{
  "userId": "user123",
  "pulseId": "pulse456",
  "interactionType": "view",
  "duration": 30,
  "source": "feed"
}
```

**Interaction Types:**
- `view` - User viewed the pulse
- `join` - User joined the pulse
- `message` - User sent a message in pulse chat
- `invite` - User invited someone to the pulse
- `share` - User shared the pulse
- `recommendation_view` - User viewed a recommended pulse
- `recommendation_click` - User clicked on a recommended pulse

**Response:**
```json
{
  "status": "success"
}
```

### `GET /user-features/<user_id>`
Get cached user features

**Response:**
```json
{
  "userId": "user123",
  "features": {
    "preferredCategories": ["sports", "music"],
    "preferredTimeSlots": ["evening"],
    "socialActivityScore": 0.75,
    "totalPulsesJoined": 15,
    "totalPulsesCreated": 3
  }
}
```

### `POST /compute-features`
Compute and cache user features from interaction history

**Request:**
```json
{
  "userId": "user123"
}
```

**Response:**
```json
{
  "status": "success",
  "userId": "user123",
  "features": {
    "socialActivityScore": 0.75,
    "messagingFrequency": 0.25,
    "preferredTimeSlots": ["evening", "afternoon"],
    "totalInteractions": 50
  }
}
```

## Recommendation Algorithm

The system uses a weighted scoring approach:

- **Content-Based (30%)**: Category and interest matching
- **Temporal (20%)**: Time of day preferences, event timing
- **Location (20%)**: Distance from user
- **Social (15%)**: Social activity patterns
- **Popularity (10%)**: Number of participants
- **Recency (5%)**: Newly created pulses

## Database Schema

The ML service uses the following tables:

- `User` - User profiles with location and preferences
- `Pulse` - Active pulses with event details
- `Location` - Structured location data
- `PulseInteraction` - User interactions for training
- `PulseRecommendation` - Cached recommendations
- `UserFeatureCache` - Precomputed user features

## Integration with Node.js Backend

The Node.js backend communicates with the ML service via HTTP:

```typescript
// In backend/src/services/recommendation.ts
const response = await axios.post(
  'http://localhost:5001/recommend',
  { userId, userLocation }
);
```

The backend provides these endpoints:

- `GET /api/recommendations` - Get personalized recommendations
- `POST /api/recommendations/track` - Track interactions
- `GET /api/recommendations/features` - Get user features
- `POST /api/recommendations/compute-features` - Compute features
- `GET /api/recommendations/stats` - Get recommendation statistics

## Deployment

### Docker

Build the Docker image:

```bash
docker build -t pulse-ml-service .
```

Run the container:

```bash
docker run -p 5001:5001 \
  -e DATABASE_URL=postgresql://user:password@host:port/database \
  pulse-ml-service
```

### Production Considerations

1. **Database Connection Pooling**: The service uses `NullPool` to avoid connection issues. For production, consider using a connection pool.

2. **Caching**: Recommendations are cached in the database. Consider adding Redis for faster cache access.

3. **Monitoring**: Add health checks and metrics endpoints for monitoring in production.

4. **Scaling**: The service is stateless and can be horizontally scaled behind a load balancer.

5. **Security**: Use environment variables for sensitive data. Don't commit `.env` files.

## Development

### Running Tests

```bash
python test_service.py
```

### Adding New Features

The recommendation algorithm is in the `PulseRecommender` class. Key methods:

- `calculate_pulse_score()` - Main scoring function
- `_content_based_score()` - Category matching
- `_temporal_score()` - Time-based scoring
- `_location_score()` - Distance-based scoring
- `_social_score()` - Social activity scoring

### Feature Engineering

User features are computed in `compute_features_from_interactions()`. Add new features by:

1. Querying interaction history
2. Computing metrics
3. Updating the feature dictionary
4. Adding to `UserFeatureCache` schema

## Troubleshooting

### Database Connection Issues

If you see "DATABASE_URL not set" warnings:

1. Check your `.env` file exists in `ml-service/`
2. Verify the DATABASE_URL format is correct
3. Ensure you're using a direct PostgreSQL URL, not Prisma Accelerate

### ML Service Not Responding

If the Node.js backend can't connect:

1. Verify the ML service is running: `curl http://localhost:5001/health`
2. Check `ML_SERVICE_URL` in backend's `.env`
3. Ensure no firewall is blocking port 5001

### No Recommendations Generated

If recommendations are empty:

1. Check if there are active pulses in the database
2. Verify user features are computed: `GET /user-features/<userId>`
3. Check logs for errors in pulse fetching

## Future Enhancements

- **Deep Learning Models**: Add neural network models for better personalization
- **Collaborative Filtering**: Implement user-user and item-item similarity
- **A/B Testing**: Framework for testing different recommendation strategies
- **Real-time Updates**: WebSocket integration for live recommendation updates
- **Explainability**: Enhanced reasoning for why pulses are recommended

### Environment Variables

- `FLASK_ENV`: Set to `production` for production deployment
- `PORT`: Service port (default: 5001)

## Production Deployment

### Option 1: Docker

```bash
# Build image
docker build -t pulse-ml-service .

# Run container
docker run -p 5001:5001 pulse-ml-service
```

### Option 2: Cloud Platforms

- **Google Cloud Run**: Serverless, auto-scaling
- **AWS Lambda + API Gateway**: Event-driven
- **Railway**: Simple deployment with auto-scaling

## Future Enhancements

1. **Deep Learning Models**: Add neural network-based embeddings
2. **Collaborative Filtering**: User-user similarity matching
3. **A/B Testing**: Test different recommendation strategies
4. **Batch Training**: Periodic model retraining on historical data
5. **Real-time Updates**: Streaming data processing
6. **Diversity Constraints**: Avoid filter bubbles

## Monitoring

Add these metrics to track recommendation quality:

- Click-through rate (CTR)
- Conversion rate (recommendations → joins)
- User engagement time
- Recommendation diversity
- Model inference latency

## License

MIT
