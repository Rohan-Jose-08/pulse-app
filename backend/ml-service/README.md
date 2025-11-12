# Pulse ML Recommendation Service

This is the machine learning service for generating personalized pulse recommendations.

## Features

- **Hybrid Recommendation System**: Combines content-based, collaborative, and contextual filtering
- **Real-time Scoring**: Fast recommendation generation (< 100ms for 100 pulses)
- **Explainable Recommendations**: Provides human-readable reasons
- **Scalable Architecture**: Stateless design for easy horizontal scaling

## Quick Start

### 1. Install Dependencies

```bash
cd backend/ml-service
pip install -r requirements.txt
```

### 2. Run the Service

```bash
python app.py
```

The service will start on `http://localhost:5001`

### 3. Test the Service

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
  "userFeatures": {
    "preferredCategories": ["sports", "music"],
    "preferredTimeSlots": ["evening"],
    "socialActivityScore": 0.7
  },
  "availablePulses": [
    {
      "id": "pulse1",
      "title": "Basketball Game",
      "category": "sports",
      "eventTime": "2025-01-15T18:00:00Z",
      "participantCount": 5,
      "location": {
        "distance": 2.5,
        "city": "New York"
      }
    }
  ]
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

## Recommendation Algorithm

The system uses a weighted scoring approach:

- **Content-Based (30%)**: Category and interest matching
- **Temporal (20%)**: Time of day preferences, event timing
- **Location (20%)**: Distance from user
- **Social (15%)**: Social activity patterns
- **Popularity (10%)**: Number of participants
- **Recency (5%)**: Newly created pulses

## Configuration

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
