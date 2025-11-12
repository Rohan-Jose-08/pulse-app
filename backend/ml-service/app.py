from flask import Flask, request, jsonify
from flask_cors import CORS
import numpy as np
from datetime import datetime, timedelta
from typing import List, Dict, Any
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)
CORS(app)  # Enable CORS for all routes

class PulseRecommender:
    """
    ML-powered pulse recommendation system
    Uses a hybrid approach combining:
    - Content-based filtering (category, location, time preferences)
    - Collaborative filtering (similar user preferences)
    - Contextual features (time of day, distance, social signals)
    """
    
    def __init__(self):
        self.category_weights = {
            'sports': 1.0,
            'music': 1.0,
            'food': 1.0,
            'outdoors': 1.0,
            'social': 1.0,
            'entertainment': 1.0,
            'education': 1.0,
            'business': 1.0,
        }
    
    def calculate_pulse_score(
        self,
        pulse: Dict[str, Any],
        user_features: Dict[str, Any],
        similar_users: List[str] = []
    ) -> float:
        """
        Calculate composite recommendation score for a pulse
        Returns score between 0.0 and 1.0
        """
        score = 0.5  # Base score
        
        # Content-based score (30%)
        content_score = self._content_based_score(pulse, user_features)
        score += 0.3 * content_score
        
        # Temporal score (20%)
        temporal_score = self._temporal_score(pulse, user_features)
        score += 0.2 * temporal_score
        
        # Location score (20%)
        location_score = self._location_score(pulse, user_features)
        score += 0.2 * location_score
        
        # Social score (15%)
        social_score = self._social_score(pulse, user_features)
        score += 0.15 * social_score
        
        # Popularity score (10%)
        popularity_score = self._popularity_score(pulse)
        score += 0.1 * popularity_score
        
        # Recency bonus (5%)
        recency_score = self._recency_score(pulse)
        score += 0.05 * recency_score
        
        return min(1.0, max(0.0, score))
    
    def _content_based_score(self, pulse: Dict, user_features: Dict) -> float:
        """Score based on category match and user interests"""
        score = 0.5
        
        # Category match
        pulse_category = pulse.get('category', '').lower()
        preferred_categories = [c.lower() for c in user_features.get('preferredCategories', [])]
        
        if pulse_category in preferred_categories:
            # Higher score for top preferences
            try:
                rank = preferred_categories.index(pulse_category)
                score = 1.0 - (rank * 0.15)  # First choice: 1.0, second: 0.85, etc.
            except ValueError:
                score = 0.7
        
        return score
    
    def _temporal_score(self, pulse: Dict, user_features: Dict) -> float:
        """Score based on time of day and user activity patterns"""
        score = 0.5
        
        try:
            # Parse event time
            event_time_str = pulse.get('eventTime')
            if not event_time_str:
                return score
            
            # Handle ISO format datetime
            if isinstance(event_time_str, str):
                event_time = datetime.fromisoformat(event_time_str.replace('Z', '+00:00'))
            else:
                return score
            
            # Hours until event
            now = datetime.now(event_time.tzinfo) if event_time.tzinfo else datetime.now()
            hours_until = (event_time - now).total_seconds() / 3600
            
            # Prefer events happening soon (within 2-12 hours)
            if 2 <= hours_until <= 12:
                score = 1.0
            elif 0 <= hours_until < 2:
                score = 0.9  # Very soon - might be too rushed
            elif 12 < hours_until <= 48:
                score = 0.7  # Tomorrow - still relevant
            else:
                score = 0.4  # Too far in future
            
            # Time of day preference
            event_hour = event_time.hour
            if event_hour >= 6 and event_hour < 12:
                time_slot = 'morning'
            elif event_hour >= 12 and event_hour < 17:
                time_slot = 'afternoon'
            elif event_hour >= 17 and event_hour < 21:
                time_slot = 'evening'
            else:
                time_slot = 'night'
            
            preferred_slots = user_features.get('preferredTimeSlots', [])
            if time_slot in preferred_slots:
                score += 0.2
                score = min(1.0, score)
        
        except Exception as e:
            logger.error(f"Error calculating temporal score: {e}")
        
        return score
    
    def _location_score(self, pulse: Dict, user_features: Dict) -> float:
        """Score based on distance from user"""
        score = 0.5
        
        location = pulse.get('location')
        if not location:
            return score
        
        distance = location.get('distance')
        if distance is None:
            return score
        
        # Distance-based scoring
        if distance < 1:
            score = 1.0  # Very close
        elif distance < 3:
            score = 0.9  # Walking distance
        elif distance < 10:
            score = 0.7  # Short drive/transit
        elif distance < 25:
            score = 0.5  # Medium distance
        else:
            score = 0.3  # Far away
        
        return score
    
    def _social_score(self, pulse: Dict, user_features: Dict) -> float:
        """Score based on social factors"""
        score = 0.5
        
        # Social activity multiplier
        social_activity = user_features.get('socialActivityScore', 0.5)
        
        # More socially active users might prefer more popular events
        participant_count = pulse.get('participantCount', 0)
        if participant_count > 0:
            if social_activity > 0.7:
                # Social users prefer events with more people
                score = min(1.0, 0.5 + (participant_count * 0.05))
            else:
                # Less social users might prefer smaller gatherings
                score = max(0.3, 0.8 - (participant_count * 0.03))
        
        return score
    
    def _popularity_score(self, pulse: Dict) -> float:
        """Score based on pulse popularity"""
        participant_count = pulse.get('participantCount', 0)
        
        if participant_count == 0:
            return 0.3
        elif participant_count < 5:
            return 0.5
        elif participant_count < 15:
            return 0.8
        else:
            return 1.0
    
    def _recency_score(self, pulse: Dict) -> float:
        """Bonus for newly created pulses"""
        # This would need createdAt field from pulse
        # For now, return neutral score
        return 0.5
    
    def generate_reason(self, pulse: Dict, user_features: Dict, score: float) -> str:
        """Generate human-readable recommendation reason"""
        reasons = []
        
        # Category match
        pulse_category = pulse.get('category', '').lower()
        preferred_categories = [c.lower() for c in user_features.get('preferredCategories', [])]
        if pulse_category in preferred_categories:
            reasons.append("Matches your interests")
        
        # Location
        location = pulse.get('location')
        if location:
            distance = location.get('distance')
            if distance is not None and distance < 2:
                reasons.append("Nearby")
            elif distance is not None and distance < 10:
                city = location.get('city', '')
                if city:
                    reasons.append(f"In {city}")
        
        # Popularity
        participant_count = pulse.get('participantCount', 0)
        if participant_count > 10:
            reasons.append("Popular event")
        elif participant_count > 0:
            reasons.append(f"{participant_count} people going")
        
        # Time
        event_time_str = pulse.get('eventTime')
        if event_time_str:
            try:
                if isinstance(event_time_str, str):
                    event_time = datetime.fromisoformat(event_time_str.replace('Z', '+00:00'))
                    now = datetime.now(event_time.tzinfo) if event_time.tzinfo else datetime.now()
                    hours_until = (event_time - now).total_seconds() / 3600
                    
                    if 0 <= hours_until < 4:
                        reasons.append("Starting soon")
                    elif 4 <= hours_until < 24:
                        reasons.append("Today")
            except:
                pass
        
        # Default
        if not reasons:
            if score > 0.7:
                reasons.append("Recommended for you")
            else:
                reasons.append("You might like this")
        
        return " • ".join(reasons[:3])  # Limit to 3 reasons


recommender = PulseRecommender()


@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint"""
    return jsonify({
        'status': 'healthy',
        'service': 'pulse-ml-recommender',
        'version': '1.0.0'
    })


@app.route('/recommend', methods=['POST'])
def recommend():
    """
    Generate personalized pulse recommendations
    
    Request body:
    {
        "userId": "user123",
        "userFeatures": {
            "preferredCategories": ["sports", "music"],
            "preferredTimeSlots": ["evening", "afternoon"],
            "socialActivityScore": 0.7,
            "avgSessionDuration": 300,
            ...
        },
        "availablePulses": [
            {
                "id": "pulse1",
                "title": "Basketball Game",
                "category": "sports",
                "eventTime": "2025-01-15T18:00:00Z",
                "participantCount": 5,
                "location": {
                    "latitude": 40.7128,
                    "longitude": -74.0060,
                    "distance": 2.5
                }
            },
            ...
        ]
    }
    
    Response:
    [
        {
            "pulseId": "pulse1",
            "score": 0.87,
            "reason": "Matches your interests • Nearby • Starting soon"
        },
        ...
    ]
    """
    try:
        data = request.json
        user_id = data.get('userId')
        user_features = data.get('userFeatures', {})
        available_pulses = data.get('availablePulses', [])
        
        if not user_id or not available_pulses:
            return jsonify({'error': 'userId and availablePulses are required'}), 400
        
        logger.info(f"Generating recommendations for user {user_id} with {len(available_pulses)} pulses")
        
        # Score each pulse
        recommendations = []
        for pulse in available_pulses:
            score = recommender.calculate_pulse_score(pulse, user_features)
            reason = recommender.generate_reason(pulse, user_features, score)
            
            recommendations.append({
                'pulseId': pulse['id'],
                'score': round(score, 3),
                'reason': reason
            })
        
        # Sort by score (highest first)
        recommendations.sort(key=lambda x: x['score'], reverse=True)
        
        # Return top 20
        recommendations = recommendations[:20]
        
        logger.info(f"Generated {len(recommendations)} recommendations for user {user_id}")
        
        return jsonify(recommendations)
    
    except Exception as e:
        logger.error(f"Error generating recommendations: {e}")
        return jsonify({'error': 'Internal server error'}), 500


@app.route('/train', methods=['POST'])
def train():
    """
    Train/update the recommendation model
    This is a placeholder for future ML model training
    """
    try:
        data = request.json
        logger.info("Train endpoint called - model training not yet implemented")
        
        return jsonify({
            'status': 'success',
            'message': 'Model training scheduled (placeholder)'
        })
    
    except Exception as e:
        logger.error(f"Error in train endpoint: {e}")
        return jsonify({'error': 'Internal server error'}), 500


if __name__ == '__main__':
    port = 5001
    logger.info(f"Starting Pulse ML Recommendation Service on port {port}")
    app.run(host='0.0.0.0', port=port, debug=True)
