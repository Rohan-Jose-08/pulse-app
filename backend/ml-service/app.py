from flask import Flask, request, jsonify
from flask_cors import CORS
import numpy as np
from datetime import datetime, timedelta
from typing import List, Dict, Any, Optional
import logging
import os
from dotenv import load_dotenv
from sqlalchemy import create_engine, text
from sqlalchemy.pool import NullPool
import json

# Load environment variables
load_dotenv()

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Database connection
DATABASE_URL = os.getenv('DATABASE_URL')
if not DATABASE_URL:
    logger.warning('DATABASE_URL not set, running without database connectivity')
    engine = None
else:
    # Handle Prisma Accelerate URLs by extracting direct connection
    if 'prisma+postgres://' in DATABASE_URL:
        logger.warning('Prisma Accelerate URL detected, please provide direct DATABASE_URL for ML service')
        engine = None
    else:
        # Ensure the URL uses postgresql:// (not postgres://)
        db_url = DATABASE_URL.replace('postgres://', 'postgresql://')
        engine = create_engine(db_url, poolclass=NullPool)

app = Flask(__name__)
CORS(app)  # Enable CORS for all routes


class DatabaseService:
    """Service for fetching data from PostgreSQL database"""
    
    def __init__(self, engine):
        self.engine = engine
    
    def get_user_features(self, user_id: str) -> Optional[Dict[str, Any]]:
        """Fetch cached user features from database"""
        if not self.engine:
            return None
        
        try:
            with self.engine.connect() as conn:
                result = conn.execute(
                    text("""
                        SELECT 
                            "userId",
                            "avgSessionDuration",
                            "preferredCategories",
                            "preferredTimeSlots",
                            "socialActivityScore",
                            "messagingFrequency",
                            "inviteAcceptanceRate",
                            "totalPulsesJoined",
                            "totalPulsesCreated",
                            "avgDistanceKm"
                        FROM "UserFeatureCache"
                        WHERE "userId" = :user_id
                    """),
                    {"user_id": user_id}
                )
                row = result.fetchone()
                
                if row:
                    return {
                        'avgSessionDuration': float(row[1]) if row[1] else None,
                        'preferredCategories': row[2] if row[2] else [],
                        'preferredTimeSlots': row[3] if row[3] else [],
                        'socialActivityScore': float(row[4]) if row[4] else 0.5,
                        'messagingFrequency': float(row[5]) if row[5] else None,
                        'inviteAcceptanceRate': float(row[6]) if row[6] else None,
                        'totalPulsesJoined': int(row[7]) if row[7] else 0,
                        'totalPulsesCreated': int(row[8]) if row[8] else 0,
                        'avgDistanceKm': float(row[9]) if row[9] else None,
                    }
                return None
        except Exception as e:
            logger.error(f"Error fetching user features: {e}")
            return None
    
    def get_active_pulses(self, user_lat: Optional[float] = None, user_lon: Optional[float] = None, 
                         max_distance_km: float = 50.0) -> List[Dict[str, Any]]:
        """Fetch active pulses from database with optional location filtering"""
        if not self.engine:
            return []
        
        try:
            with self.engine.connect() as conn:
                # Get active pulses with location data
                query = text("""
                    SELECT 
                        p.id,
                        p.title,
                        p.description,
                        p.category,
                        p."eventTime",
                        p."createdAt",
                        p."currentParticipants",
                        p."maxParticipants",
                        p."authorId",
                        l.latitude,
                        l.longitude,
                        l.city,
                        l.name as location_name
                    FROM "Pulse" p
                    LEFT JOIN "Location" l ON p."locationId" = l.id
                    WHERE p."activeUntil" IS NULL OR p."activeUntil" > NOW()
                    AND p."eventTime" > NOW()
                    ORDER BY p."createdAt" DESC
                    LIMIT 100
                """)
                
                result = conn.execute(query)
                pulses = []
                
                for row in result:
                    pulse_data = {
                        'id': row[0],
                        'title': row[1],
                        'description': row[2],
                        'category': row[3] or 'social',
                        'eventTime': row[4].isoformat() if row[4] else None,
                        'createdAt': row[5].isoformat() if row[5] else None,
                        'participantCount': int(row[6]) if row[6] else 0,
                        'maxParticipants': int(row[7]) if row[7] else None,
                        'authorId': row[8],
                        'location': {}
                    }
                    
                    # Add location data if available
                    if row[9] is not None and row[10] is not None:
                        pulse_lat = float(row[9])
                        pulse_lon = float(row[10])
                        
                        pulse_data['location'] = {
                            'latitude': pulse_lat,
                            'longitude': pulse_lon,
                            'city': row[11],
                            'name': row[12]
                        }
                        
                        # Calculate distance if user location provided
                        if user_lat is not None and user_lon is not None:
                            distance = self._haversine_distance(
                                user_lat, user_lon, pulse_lat, pulse_lon
                            )
                            pulse_data['location']['distance'] = distance
                            
                            # Skip if too far
                            if distance > max_distance_km:
                                continue
                    
                    pulses.append(pulse_data)
                
                return pulses
        except Exception as e:
            logger.error(f"Error fetching active pulses: {e}")
            return []
    
    def get_user_interactions(self, user_id: str, limit: int = 100) -> List[Dict[str, Any]]:
        """Fetch recent user interactions for analysis"""
        if not self.engine:
            return []
        
        try:
            with self.engine.connect() as conn:
                result = conn.execute(
                    text("""
                        SELECT 
                            "pulseId",
                            "interactionType",
                            "duration",
                            "timestamp",
                            "source"
                        FROM "PulseInteraction"
                        WHERE "userId" = :user_id
                        ORDER BY "timestamp" DESC
                        LIMIT :limit
                    """),
                    {"user_id": user_id, "limit": limit}
                )
                
                interactions = []
                for row in result:
                    interactions.append({
                        'pulseId': row[0],
                        'interactionType': row[1],
                        'duration': int(row[2]) if row[2] else None,
                        'timestamp': row[3].isoformat() if row[3] else None,
                        'source': row[4]
                    })
                
                return interactions
        except Exception as e:
            logger.error(f"Error fetching user interactions: {e}")
            return []
    
    def save_interaction(self, user_id: str, pulse_id: str, interaction_type: str,
                        duration: Optional[int] = None, source: Optional[str] = None) -> bool:
        """Save a user interaction to the database"""
        if not self.engine:
            return False
        
        try:
            with self.engine.connect() as conn:
                conn.execute(
                    text("""
                        INSERT INTO "PulseInteraction" 
                        ("userId", "pulseId", "interactionType", "duration", "source", "timestamp")
                        VALUES (:user_id, :pulse_id, :interaction_type, :duration, :source, NOW())
                    """),
                    {
                        "user_id": user_id,
                        "pulse_id": pulse_id,
                        "interaction_type": interaction_type,
                        "duration": duration,
                        "source": source
                    }
                )
                conn.commit()
                return True
        except Exception as e:
            logger.error(f"Error saving interaction: {e}")
            return False
    
    def save_recommendations(self, recommendations: List[Dict[str, Any]]) -> bool:
        """Save generated recommendations to cache"""
        if not self.engine:
            return False
        
        try:
            with self.engine.connect() as conn:
                for rec in recommendations:
                    conn.execute(
                        text("""
                            INSERT INTO "PulseRecommendation" 
                            ("userId", "pulseId", "score", "reason", "generatedAt")
                            VALUES (:user_id, :pulse_id, :score, :reason, NOW())
                        """),
                        {
                            "user_id": rec['userId'],
                            "pulse_id": rec['pulseId'],
                            "score": rec['score'],
                            "reason": rec.get('reason')
                        }
                    )
                conn.commit()
                return True
        except Exception as e:
            logger.error(f"Error saving recommendations: {e}")
            return False
    
    @staticmethod
    def _haversine_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
        """Calculate distance between two points in kilometers"""
        R = 6371  # Earth's radius in kilometers
        
        lat1_rad = np.radians(lat1)
        lat2_rad = np.radians(lat2)
        delta_lat = np.radians(lat2 - lat1)
        delta_lon = np.radians(lon2 - lon1)
        
        a = np.sin(delta_lat/2)**2 + np.cos(lat1_rad) * np.cos(lat2_rad) * np.sin(delta_lon/2)**2
        c = 2 * np.arctan2(np.sqrt(a), np.sqrt(1-a))
        
        return R * c


# Initialize database service
db_service = DatabaseService(engine) if engine else None


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
    
    def compute_features_from_interactions(self, interactions: List[Dict[str, Any]]) -> Dict[str, Any]:
        """
        Compute user features from interaction history
        
        Args:
            interactions: List of user interactions with pulses
        
        Returns:
            Dictionary of computed features
        """
        if not interactions:
            return {}
        
        # Analyze interaction types
        join_count = sum(1 for i in interactions if i['interactionType'] == 'join')
        view_count = sum(1 for i in interactions if i['interactionType'] == 'view')
        message_count = sum(1 for i in interactions if i['interactionType'] == 'message')
        
        # Calculate social activity score (0.0 - 1.0)
        total_interactions = len(interactions)
        social_score = min(1.0, (join_count * 0.5 + message_count * 0.3) / max(1, total_interactions))
        
        # Calculate messaging frequency
        messaging_frequency = message_count / max(1, total_interactions)
        
        # Analyze time patterns
        time_slots = {'morning': 0, 'afternoon': 0, 'evening': 0, 'night': 0}
        for interaction in interactions:
            try:
                timestamp = datetime.fromisoformat(interaction['timestamp'].replace('Z', '+00:00'))
                hour = timestamp.hour
                
                if 6 <= hour < 12:
                    time_slots['morning'] += 1
                elif 12 <= hour < 17:
                    time_slots['afternoon'] += 1
                elif 17 <= hour < 21:
                    time_slots['evening'] += 1
                else:
                    time_slots['night'] += 1
            except:
                pass
        
        # Get preferred time slots (top 2)
        sorted_slots = sorted(time_slots.items(), key=lambda x: x[1], reverse=True)
        preferred_time_slots = [slot for slot, count in sorted_slots[:2] if count > 0]
        
        # Calculate average session duration
        durations = [i['duration'] for i in interactions if i.get('duration')]
        avg_duration = sum(durations) / len(durations) if durations else None
        
        return {
            'socialActivityScore': round(social_score, 3),
            'messagingFrequency': round(messaging_frequency, 3),
            'preferredTimeSlots': preferred_time_slots,
            'avgSessionDuration': round(avg_duration, 1) if avg_duration else None,
            'totalInteractions': total_interactions,
            'joinCount': join_count,
            'viewCount': view_count,
            'messageCount': message_count
        }


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
        "userLocation": {  // Optional
            "latitude": 40.7128,
            "longitude": -74.0060
        },
        "userFeatures": {  // Optional, will be fetched from DB if not provided
            "preferredCategories": ["sports", "music"],
            "preferredTimeSlots": ["evening", "afternoon"],
            "socialActivityScore": 0.7
        },
        "availablePulses": [],  // Optional, will be fetched from DB if not provided
        "maxResults": 20  // Optional, default 20
    }
    
    Response:
    [
        {
            "pulseId": "pulse1",
            "score": 0.87,
            "reason": "Matches your interests • Nearby • Starting soon"
        }
    ]
    """
    try:
        data = request.json
        user_id = data.get('userId')
        
        if not user_id:
            return jsonify({'error': 'userId is required'}), 400
        
        # Get user location
        user_location = data.get('userLocation')
        user_lat = user_location.get('latitude') if user_location else None
        user_lon = user_location.get('longitude') if user_location else None
        
        # Get or fetch user features
        user_features = data.get('userFeatures')
        if not user_features and db_service:
            logger.info(f"Fetching user features from database for user {user_id}")
            user_features = db_service.get_user_features(user_id)
        
        if not user_features:
            logger.warning(f"No user features found for user {user_id}, using defaults")
            user_features = {
                'preferredCategories': [],
                'preferredTimeSlots': [],
                'socialActivityScore': 0.5
            }
        
        # Get or fetch available pulses
        available_pulses = data.get('availablePulses', [])
        if not available_pulses and db_service:
            logger.info(f"Fetching active pulses from database")
            available_pulses = db_service.get_active_pulses(user_lat, user_lon)
        
        if not available_pulses:
            logger.warning("No pulses available for recommendations")
            return jsonify([])
        
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
        
        # Limit results
        max_results = data.get('maxResults', 20)
        recommendations = recommendations[:max_results]
        
        # Save recommendations to cache if database available
        if db_service and recommendations:
            recs_to_save = [
                {
                    'userId': user_id,
                    'pulseId': rec['pulseId'],
                    'score': rec['score'],
                    'reason': rec['reason']
                }
                for rec in recommendations
            ]
            db_service.save_recommendations(recs_to_save)
        
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


@app.route('/interactions', methods=['POST'])
def track_interaction():
    """
    Track user interaction with a pulse
    
    Request body:
    {
        "userId": "user123",
        "pulseId": "pulse456",
        "interactionType": "view",  // view, join, message, invite, share, recommendation_click
        "duration": 30,  // Optional, in seconds
        "source": "feed"  // Optional: feed, map, recommendation, search, notification
    }
    """
    try:
        data = request.json
        user_id = data.get('userId')
        pulse_id = data.get('pulseId')
        interaction_type = data.get('interactionType')
        
        if not all([user_id, pulse_id, interaction_type]):
            return jsonify({'error': 'userId, pulseId, and interactionType are required'}), 400
        
        duration = data.get('duration')
        source = data.get('source')
        
        # Save interaction
        if db_service:
            success = db_service.save_interaction(user_id, pulse_id, interaction_type, duration, source)
            if success:
                logger.info(f"Tracked {interaction_type} interaction for user {user_id} on pulse {pulse_id}")
                return jsonify({'status': 'success'})
            else:
                return jsonify({'error': 'Failed to save interaction'}), 500
        else:
            logger.warning("Database not connected, cannot save interaction")
            return jsonify({'error': 'Database not available'}), 503
    
    except Exception as e:
        logger.error(f"Error tracking interaction: {e}")
        return jsonify({'error': 'Internal server error'}), 500


@app.route('/user-features/<user_id>', methods=['GET'])
def get_user_features(user_id: str):
    """
    Get cached user features for a specific user
    
    Response:
    {
        "userId": "user123",
        "features": {
            "preferredCategories": ["sports", "music"],
            "preferredTimeSlots": ["evening"],
            "socialActivityScore": 0.75,
            ...
        }
    }
    """
    try:
        if not db_service:
            return jsonify({'error': 'Database not available'}), 503
        
        features = db_service.get_user_features(user_id)
        
        if features:
            return jsonify({
                'userId': user_id,
                'features': features
            })
        else:
            return jsonify({'error': 'User features not found'}), 404
    
    except Exception as e:
        logger.error(f"Error fetching user features: {e}")
        return jsonify({'error': 'Internal server error'}), 500


@app.route('/compute-features', methods=['POST'])
def compute_user_features():
    """
    Compute and cache user features from interaction history
    
    Request body:
    {
        "userId": "user123"
    }
    
    This endpoint analyzes user's interaction history and computes:
    - Preferred categories (based on interaction frequency)
    - Preferred time slots (based on interaction times)
    - Social activity score (based on messaging and invitation patterns)
    - Other behavioral metrics
    """
    try:
        data = request.json
        user_id = data.get('userId')
        
        if not user_id:
            return jsonify({'error': 'userId is required'}), 400
        
        if not db_service:
            return jsonify({'error': 'Database not available'}), 503
        
        # Get user interactions
        interactions = db_service.get_user_interactions(user_id, limit=500)
        
        if not interactions:
            logger.info(f"No interactions found for user {user_id}")
            return jsonify({'status': 'no_data', 'message': 'No interactions found'})
        
        # Compute features from interactions
        features = recommender.compute_features_from_interactions(interactions)
        
        # TODO: Save computed features to UserFeatureCache table
        # This would require an additional database method
        
        logger.info(f"Computed features for user {user_id}: {features}")
        
        return jsonify({
            'status': 'success',
            'userId': user_id,
            'features': features
        })
    
    except Exception as e:
        logger.error(f"Error computing user features: {e}")
        return jsonify({'error': 'Internal server error'}), 500


if __name__ == '__main__':
    port = 5001
    logger.info(f"Starting Pulse ML Recommendation Service on port {port}")
    app.run(host='0.0.0.0', port=port, debug=True)
