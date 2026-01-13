from flask import Flask, request, jsonify
from flask_cors import CORS
import numpy as np
from datetime import datetime, timedelta
from typing import List, Dict, Any, Optional, Tuple
import logging
import os
from dotenv import load_dotenv
from sqlalchemy import create_engine, text
from sqlalchemy.pool import NullPool
import json
from collections import defaultdict
import hashlib
import pickle
from functools import lru_cache
import threading
import time

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
            import uuid
            interaction_id = 'c' + uuid.uuid4().hex[:24]
            
            with self.engine.connect() as conn:
                conn.execute(
                    text("""
                        INSERT INTO "PulseInteraction" 
                        ("id", "userId", "pulseId", "interactionType", "duration", "source", "timestamp")
                        VALUES (:id, :user_id, :pulse_id, :interaction_type, :duration, :source, NOW())
                    """),
                    {
                        "id": interaction_id,
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
                    # Generate a unique ID (cuid-like)
                    import uuid
                    rec_id = 'c' + uuid.uuid4().hex[:24]
                    
                    conn.execute(
                        text("""
                            INSERT INTO "PulseRecommendation" 
                            ("id", "userId", "pulseId", "score", "reason", "generatedAt")
                            VALUES (:id, :user_id, :pulse_id, :score, :reason, NOW())
                        """),
                        {
                            "id": rec_id,
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


# ============================================================================
# ADVANCED ML MODELS
# ============================================================================

class TFIDFVectorizer:
    """Simple TF-IDF implementation for text similarity"""
    
    def __init__(self):
        self.vocabulary = {}
        self.idf_values = {}
        self.fitted = False
    
    def fit(self, documents: List[str]):
        """Build vocabulary and IDF values from documents"""
        doc_count = len(documents)
        term_doc_count = defaultdict(int)
        
        # Build vocabulary
        for doc in documents:
            terms = set(self._tokenize(doc))
            for term in terms:
                term_doc_count[term] += 1
        
        # Calculate IDF
        for idx, (term, count) in enumerate(term_doc_count.items()):
            self.vocabulary[term] = idx
            self.idf_values[term] = np.log((doc_count + 1) / (count + 1)) + 1
        
        self.fitted = True
    
    def transform(self, text: str) -> np.ndarray:
        """Transform text into TF-IDF vector"""
        if not self.fitted:
            return np.array([])
        
        vector = np.zeros(len(self.vocabulary))
        terms = self._tokenize(text)
        term_counts = defaultdict(int)
        
        for term in terms:
            term_counts[term] += 1
        
        for term, count in term_counts.items():
            if term in self.vocabulary:
                tf = count / len(terms) if terms else 0
                idf = self.idf_values.get(term, 1)
                vector[self.vocabulary[term]] = tf * idf
        
        # Normalize
        norm = np.linalg.norm(vector)
        if norm > 0:
            vector = vector / norm
        
        return vector
    
    def _tokenize(self, text: str) -> List[str]:
        """Simple tokenization"""
        if not text:
            return []
        return text.lower().split()


class CollaborativeFilter:
    """
    Collaborative filtering using user-item interaction matrix
    Uses cosine similarity between users based on their pulse interactions
    """
    
    def __init__(self):
        self.user_item_matrix = None
        self.user_mapping = {}
        self.item_mapping = {}
        self.reverse_user_mapping = {}
        self.reverse_item_mapping = {}
        self.user_similarity_matrix = None
        self.last_update = None
    
    def fit(self, interactions: List[Dict[str, Any]]):
        """Build user-item matrix from interactions"""
        if not interactions:
            return
        
        # Build mappings
        users = list(set(i['userId'] for i in interactions))
        items = list(set(i['pulseId'] for i in interactions))
        
        self.user_mapping = {u: idx for idx, u in enumerate(users)}
        self.item_mapping = {i: idx for idx, i in enumerate(items)}
        self.reverse_user_mapping = {idx: u for u, idx in self.user_mapping.items()}
        self.reverse_item_mapping = {idx: i for i, idx in self.item_mapping.items()}
        
        # Build matrix
        n_users = len(users)
        n_items = len(items)
        self.user_item_matrix = np.zeros((n_users, n_items))
        
        # Weight different interaction types
        interaction_weights = {
            'join': 5.0,
            'message': 3.0,
            'invite': 2.0,
            'recommendation_click': 1.5,
            'view': 1.0,
            'share': 2.5,
        }
        
        for interaction in interactions:
            user_idx = self.user_mapping.get(interaction['userId'])
            item_idx = self.item_mapping.get(interaction['pulseId'])
            if user_idx is not None and item_idx is not None:
                weight = interaction_weights.get(interaction['interactionType'], 1.0)
                self.user_item_matrix[user_idx, item_idx] += weight
        
        # Calculate user similarity matrix
        self._compute_user_similarity()
        self.last_update = datetime.now()
    
    def _compute_user_similarity(self):
        """Compute cosine similarity between all users"""
        if self.user_item_matrix is None or self.user_item_matrix.shape[0] == 0:
            return
        
        # Normalize rows
        norms = np.linalg.norm(self.user_item_matrix, axis=1, keepdims=True)
        norms[norms == 0] = 1
        normalized = self.user_item_matrix / norms
        
        # Compute similarity matrix
        self.user_similarity_matrix = np.dot(normalized, normalized.T)
    
    def get_similar_users(self, user_id: str, top_k: int = 10) -> List[Tuple[str, float]]:
        """Get top-k similar users"""
        if user_id not in self.user_mapping or self.user_similarity_matrix is None:
            return []
        
        user_idx = self.user_mapping[user_id]
        similarities = self.user_similarity_matrix[user_idx]
        
        # Get top similar users (excluding self)
        similar_indices = np.argsort(similarities)[::-1][1:top_k+1]
        
        result = []
        for idx in similar_indices:
            if similarities[idx] > 0:
                result.append((self.reverse_user_mapping[idx], float(similarities[idx])))
        
        return result
    
    def predict_score(self, user_id: str, pulse_id: str) -> float:
        """Predict user's interest in a pulse based on similar users"""
        if user_id not in self.user_mapping or self.user_similarity_matrix is None:
            return 0.5  # Default score
        
        if pulse_id not in self.item_mapping:
            return 0.5
        
        user_idx = self.user_mapping[user_id]
        item_idx = self.item_mapping[pulse_id]
        
        # Weighted average of similar users' ratings
        similarities = self.user_similarity_matrix[user_idx]
        item_scores = self.user_item_matrix[:, item_idx]
        
        # Exclude self
        mask = np.arange(len(similarities)) != user_idx
        sim_scores = similarities[mask] * item_scores[mask]
        
        if np.sum(similarities[mask]) > 0:
            score = np.sum(sim_scores) / (np.sum(np.abs(similarities[mask])) + 1e-8)
            # Normalize to 0-1 range
            return min(1.0, max(0.0, score / 5.0))
        
        return 0.5


class NeuralScorer:
    """
    Simple neural network for pulse scoring using numpy
    Features: user features + pulse features -> score prediction
    """
    
    def __init__(self, input_dim: int = 20, hidden_dim: int = 32):
        self.input_dim = input_dim
        self.hidden_dim = hidden_dim
        
        # Initialize weights with Xavier initialization
        scale1 = np.sqrt(2.0 / input_dim)
        scale2 = np.sqrt(2.0 / hidden_dim)
        
        self.W1 = np.random.randn(input_dim, hidden_dim) * scale1
        self.b1 = np.zeros(hidden_dim)
        self.W2 = np.random.randn(hidden_dim, hidden_dim // 2) * scale2
        self.b2 = np.zeros(hidden_dim // 2)
        self.W3 = np.random.randn(hidden_dim // 2, 1) * np.sqrt(2.0 / (hidden_dim // 2))
        self.b3 = np.zeros(1)
        
        self.is_trained = False
    
    def _relu(self, x: np.ndarray) -> np.ndarray:
        return np.maximum(0, x)
    
    def _sigmoid(self, x: np.ndarray) -> np.ndarray:
        return 1 / (1 + np.exp(-np.clip(x, -500, 500)))
    
    def predict(self, features: np.ndarray) -> float:
        """Forward pass to predict score"""
        h1 = self._relu(np.dot(features, self.W1) + self.b1)
        h2 = self._relu(np.dot(h1, self.W2) + self.b2)
        output = self._sigmoid(np.dot(h2, self.W3) + self.b3)
        return float(output[0])
    
    def extract_features(self, user_features: Dict, pulse: Dict) -> np.ndarray:
        """Extract feature vector from user and pulse data"""
        features = np.zeros(self.input_dim)
        
        # User features (indices 0-9)
        features[0] = user_features.get('socialActivityScore', 0.5)
        features[1] = user_features.get('messagingFrequency', 0) / 10.0
        features[2] = user_features.get('inviteAcceptanceRate', 0.5)
        features[3] = user_features.get('totalPulsesJoined', 0) / 100.0
        features[4] = user_features.get('totalPulsesCreated', 0) / 50.0
        features[5] = len(user_features.get('preferredCategories', [])) / 5.0
        features[6] = len(user_features.get('preferredTimeSlots', [])) / 4.0
        features[7] = user_features.get('avgSessionDuration', 60) / 300.0
        features[8] = user_features.get('avgDistanceKm', 10) / 50.0
        
        # Category match
        pulse_category = pulse.get('category', '').lower()
        preferred = [c.lower() for c in user_features.get('preferredCategories', [])]
        features[9] = 1.0 if pulse_category in preferred else 0.0
        
        # Pulse features (indices 10-19)
        features[10] = pulse.get('participantCount', 0) / 20.0
        features[11] = 1.0 if pulse.get('maxParticipants') else 0.0
        
        # Distance feature
        location = pulse.get('location', {})
        distance = location.get('distance', 50)
        features[12] = max(0, 1 - distance / 50.0)
        
        # Time features
        event_time_str = pulse.get('eventTime')
        if event_time_str:
            try:
                event_time = datetime.fromisoformat(str(event_time_str).replace('Z', '+00:00'))
                now = datetime.now(event_time.tzinfo) if event_time.tzinfo else datetime.now()
                hours_until = (event_time - now).total_seconds() / 3600
                
                # Time urgency (0 to 1, higher for events starting soon)
                features[13] = max(0, 1 - hours_until / 48.0)
                
                # Time slot match
                hour = event_time.hour
                if 6 <= hour < 12:
                    time_slot = 'morning'
                elif 12 <= hour < 17:
                    time_slot = 'afternoon'
                elif 17 <= hour < 21:
                    time_slot = 'evening'
                else:
                    time_slot = 'night'
                
                preferred_slots = user_features.get('preferredTimeSlots', [])
                features[14] = 1.0 if time_slot in preferred_slots else 0.0
            except:
                pass
        
        # Weekday/weekend
        try:
            if event_time_str:
                event_time = datetime.fromisoformat(str(event_time_str).replace('Z', '+00:00'))
                features[15] = 1.0 if event_time.weekday() >= 5 else 0.0
        except:
            pass
        
        return features
    
    def train_batch(self, features_batch: List[np.ndarray], labels: List[float], 
                   learning_rate: float = 0.01):
        """Simple batch training with gradient descent"""
        if not features_batch:
            return
        
        for features, label in zip(features_batch, labels):
            # Forward pass
            h1 = self._relu(np.dot(features, self.W1) + self.b1)
            h2 = self._relu(np.dot(h1, self.W2) + self.b2)
            output = self._sigmoid(np.dot(h2, self.W3) + self.b3)
            
            # Compute gradients (simplified backprop)
            error = output - label
            
            # Output layer gradients
            d3 = error * output * (1 - output)
            dW3 = np.outer(h2, d3)
            db3 = d3
            
            # Hidden layer 2 gradients
            d2 = np.dot(d3, self.W3.T) * (h2 > 0)
            dW2 = np.outer(h1, d2)
            db2 = d2
            
            # Hidden layer 1 gradients
            d1 = np.dot(d2, self.W2.T) * (h1 > 0)
            dW1 = np.outer(features, d1)
            db1 = d1
            
            # Update weights
            self.W3 -= learning_rate * dW3
            self.b3 -= learning_rate * db3
            self.W2 -= learning_rate * dW2
            self.b2 -= learning_rate * db2
            self.W1 -= learning_rate * dW1
            self.b1 -= learning_rate * db1
        
        self.is_trained = True


class ModelEnsemble:
    """
    Ensemble model combining multiple scoring approaches
    Weights can be adjusted via A/B testing
    """
    
    def __init__(self):
        self.weights = {
            'content': 0.30,
            'collaborative': 0.25,
            'neural': 0.20,
            'temporal': 0.15,
            'social': 0.10,
        }
    
    def combine_scores(self, scores: Dict[str, float]) -> float:
        """Combine multiple scores using weighted average"""
        total_weight = 0
        weighted_sum = 0
        
        for key, weight in self.weights.items():
            if key in scores and scores[key] is not None:
                weighted_sum += scores[key] * weight
                total_weight += weight
        
        if total_weight > 0:
            return weighted_sum / total_weight
        return 0.5
    
    def set_weights(self, weights: Dict[str, float]):
        """Update ensemble weights (for A/B testing)"""
        self.weights.update(weights)


class ABTestManager:
    """
    A/B Testing manager for recommendation experiments
    """
    
    def __init__(self):
        self.experiments = {}
        self.user_assignments = {}
    
    def create_experiment(self, name: str, variants: List[Dict[str, Any]]):
        """Create new A/B test experiment"""
        self.experiments[name] = {
            'name': name,
            'variants': variants,
            'created_at': datetime.now().isoformat(),
            'is_active': True
        }
    
    def get_variant(self, user_id: str, experiment_name: str) -> Optional[Dict[str, Any]]:
        """Get experiment variant for user (consistent assignment)"""
        if experiment_name not in self.experiments:
            return None
        
        experiment = self.experiments[experiment_name]
        if not experiment['is_active']:
            return None
        
        key = f"{user_id}:{experiment_name}"
        if key not in self.user_assignments:
            # Hash user ID for consistent assignment
            hash_val = int(hashlib.md5(key.encode()).hexdigest(), 16)
            variant_idx = hash_val % len(experiment['variants'])
            self.user_assignments[key] = variant_idx
        
        return experiment['variants'][self.user_assignments[key]]


# Initialize ML components
collaborative_filter = CollaborativeFilter()
neural_scorer = NeuralScorer()
model_ensemble = ModelEnsemble()
ab_test_manager = ABTestManager()
text_vectorizer = TFIDFVectorizer()

# Background model update flag
model_update_lock = threading.Lock()
last_model_update = None


def update_models_async():
    """Background task to update ML models periodically"""
    global last_model_update
    
    while True:
        try:
            with model_update_lock:
                if db_service and db_service.engine:
                    logger.info("Starting background model update...")
                    
                    # Get all interactions from last 30 days
                    interactions = get_all_interactions(days=30)
                    if interactions:
                        # Update collaborative filter
                        collaborative_filter.fit(interactions)
                        logger.info(f"Collaborative filter updated with {len(interactions)} interactions")
                    
                    last_model_update = datetime.now()
                    logger.info("Background model update completed")
        except Exception as e:
            logger.error(f"Error in background model update: {e}")
        
        # Update every 30 minutes
        time.sleep(1800)


def get_all_interactions(days: int = 30) -> List[Dict[str, Any]]:
    """Fetch all interactions from database for model training"""
    if not db_service or not db_service.engine:
        return []
    
    try:
        with db_service.engine.connect() as conn:
            result = conn.execute(
                text("""
                    SELECT "userId", "pulseId", "interactionType", "timestamp"
                    FROM "PulseInteraction"
                    WHERE "timestamp" > NOW() - INTERVAL ':days days'
                    ORDER BY "timestamp" DESC
                    LIMIT 100000
                """.replace(':days', str(days)))
            )
            
            interactions = []
            for row in result:
                interactions.append({
                    'userId': row[0],
                    'pulseId': row[1],
                    'interactionType': row[2],
                    'timestamp': row[3].isoformat() if row[3] else None
                })
            
            return interactions
    except Exception as e:
        logger.error(f"Error fetching all interactions: {e}")
        return []


# Start background model update thread
model_update_thread = threading.Thread(target=update_models_async, daemon=True)
# Comment out for now - enable in production
# model_update_thread.start()


class PulseRecommender:
    """
    ML-powered pulse recommendation system
    Uses a hybrid approach combining:
    - Content-based filtering (category, location, time preferences)
    - Collaborative filtering (similar user preferences)
    - Neural network scoring
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
        self.use_advanced_ml = True
    
    def calculate_pulse_score(
        self,
        pulse: Dict[str, Any],
        user_features: Dict[str, Any],
        user_id: str = None,
        use_ensemble: bool = True
    ) -> float:
        """
        Calculate composite recommendation score for a pulse
        Returns score between 0.0 and 1.0
        
        Uses ensemble of:
        - Content-based filtering
        - Collaborative filtering
        - Neural network
        - Temporal & location features
        """
        scores = {}
        
        # Content-based score
        scores['content'] = self._content_based_score(pulse, user_features)
        
        # Temporal score
        scores['temporal'] = self._temporal_score(pulse, user_features)
        
        # Location score
        location_score = self._location_score(pulse, user_features)
        
        # Social score
        scores['social'] = self._social_score(pulse, user_features)
        
        # Popularity score (included in content)
        popularity_score = self._popularity_score(pulse)
        recency_score = self._recency_score(pulse)
        
        # Adjust content score with popularity and recency
        scores['content'] = (scores['content'] * 0.7 + popularity_score * 0.2 + recency_score * 0.1)
        
        # Advanced ML scores (if enabled and user_id available)
        if self.use_advanced_ml and user_id:
            # Collaborative filtering score
            cf_score = collaborative_filter.predict_score(user_id, pulse.get('id', ''))
            if cf_score != 0.5:  # Non-default score means we have data
                scores['collaborative'] = cf_score
            
            # Neural network score
            try:
                features = neural_scorer.extract_features(user_features, pulse)
                scores['neural'] = neural_scorer.predict(features)
            except Exception as e:
                logger.debug(f"Neural scoring error: {e}")
        
        # Use ensemble or fallback to weighted average
        if use_ensemble and len(scores) >= 3:
            # Include location in ensemble scores
            scores['location'] = location_score
            final_score = model_ensemble.combine_scores(scores)
        else:
            # Fallback: simple weighted average
            final_score = 0.5  # Base score
            final_score += 0.30 * scores.get('content', 0.5)
            final_score += 0.20 * scores.get('temporal', 0.5)
            final_score += 0.25 * location_score
            final_score += 0.15 * scores.get('social', 0.5)
            final_score += 0.10 * scores.get('collaborative', 0.5)
        
        return min(1.0, max(0.0, final_score))
    
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
    """Health check endpoint with detailed status"""
    db_status = 'connected' if (db_service and db_service.engine) else 'disconnected'
    
    return jsonify({
        'status': 'healthy',
        'service': 'pulse-ml-recommender',
        'version': '2.0.0',
        'features': [
            'content_based_filtering',
            'collaborative_filtering', 
            'neural_network_scoring',
            'ensemble_model',
            'ab_testing',
            'batch_recommendations',
            'recommendation_explanations'
        ],
        'database': db_status,
        'models': {
            'collaborative_filter': {
                'users': len(collaborative_filter.user_mapping),
                'items': len(collaborative_filter.item_mapping)
            },
            'neural_scorer': {
                'trained': neural_scorer.is_trained
            }
        }
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
        
        # Check for A/B test variant
        variant = ab_test_manager.get_variant(user_id, 'recommendation_weights')
        if variant:
            model_ensemble.set_weights(variant.get('weights', {}))
            logger.info(f"Using A/B test variant for user {user_id}")
        
        # Score each pulse using advanced ML ensemble
        recommendations = []
        for pulse in available_pulses:
            score = recommender.calculate_pulse_score(
                pulse, 
                user_features, 
                user_id=user_id,
                use_ensemble=True
            )
            reason = recommender.generate_reason(pulse, user_features, score)
            
            recommendations.append({
                'pulseId': pulse['id'],
                'score': round(score, 3),
                'reason': reason,
                'category': pulse.get('category'),
                'distance': pulse.get('location', {}).get('distance')
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
    Train/update the recommendation models
    
    Request body:
    {
        "model": "all" | "collaborative" | "neural",  // Which model to train
        "days": 30,  // Number of days of data to use
        "force": false  // Force retrain even if recently trained
    }
    """
    try:
        data = request.json or {}
        model_type = data.get('model', 'all')
        days = data.get('days', 30)
        force = data.get('force', False)
        
        if not db_service:
            return jsonify({'error': 'Database not available'}), 503
        
        results = {
            'status': 'success',
            'models_trained': [],
            'interaction_count': 0
        }
        
        # Get interactions for training
        interactions = get_all_interactions(days=days)
        results['interaction_count'] = len(interactions)
        
        if not interactions:
            return jsonify({
                'status': 'no_data',
                'message': 'No interaction data available for training'
            })
        
        # Train collaborative filter
        if model_type in ['all', 'collaborative']:
            try:
                with model_update_lock:
                    collaborative_filter.fit(interactions)
                results['models_trained'].append('collaborative_filter')
                logger.info(f"Trained collaborative filter with {len(interactions)} interactions")
            except Exception as e:
                logger.error(f"Error training collaborative filter: {e}")
                results['errors'] = results.get('errors', []) + [f"Collaborative filter: {str(e)}"]
        
        # Train neural network (requires labeled data from positive interactions)
        if model_type in ['all', 'neural']:
            try:
                # Create training data from interactions
                positive_interactions = [i for i in interactions if i['interactionType'] in ['join', 'message', 'invite']]
                negative_interactions = [i for i in interactions if i['interactionType'] == 'view'][:len(positive_interactions)]
                
                if len(positive_interactions) >= 10:
                    features_batch = []
                    labels = []
                    
                    # This is a simplified training - in production you'd have more sophisticated data
                    for interaction in positive_interactions[:100]:
                        user_features = db_service.get_user_features(interaction['userId']) or {}
                        pulse_features = {'id': interaction['pulseId'], 'category': 'unknown'}
                        features = neural_scorer.extract_features(user_features, pulse_features)
                        features_batch.append(features)
                        labels.append(1.0)
                    
                    for interaction in negative_interactions[:100]:
                        user_features = db_service.get_user_features(interaction['userId']) or {}
                        pulse_features = {'id': interaction['pulseId'], 'category': 'unknown'}
                        features = neural_scorer.extract_features(user_features, pulse_features)
                        features_batch.append(features)
                        labels.append(0.2)  # Low score for view-only
                    
                    # Train for a few epochs
                    for epoch in range(5):
                        neural_scorer.train_batch(features_batch, labels, learning_rate=0.01)
                    
                    results['models_trained'].append('neural_scorer')
                    logger.info(f"Trained neural scorer with {len(features_batch)} samples")
                else:
                    results['warnings'] = results.get('warnings', []) + ['Not enough positive interactions for neural training']
            except Exception as e:
                logger.error(f"Error training neural scorer: {e}")
                results['errors'] = results.get('errors', []) + [f"Neural scorer: {str(e)}"]
        
        return jsonify(results)
    
    except Exception as e:
        logger.error(f"Error in train endpoint: {e}")
        return jsonify({'error': 'Internal server error'}), 500


@app.route('/similar-users/<user_id>', methods=['GET'])
def get_similar_users(user_id: str):
    """
    Get users similar to the given user based on collaborative filtering
    
    Query params:
    - limit: Maximum number of similar users (default: 10)
    """
    try:
        limit = request.args.get('limit', 10, type=int)
        
        similar = collaborative_filter.get_similar_users(user_id, top_k=limit)
        
        return jsonify({
            'userId': user_id,
            'similarUsers': [
                {'userId': uid, 'similarity': round(sim, 3)}
                for uid, sim in similar
            ]
        })
    
    except Exception as e:
        logger.error(f"Error getting similar users: {e}")
        return jsonify({'error': 'Internal server error'}), 500


@app.route('/ab-test', methods=['POST'])
def create_ab_test():
    """
    Create or update an A/B test experiment
    
    Request body:
    {
        "name": "recommendation_weights",
        "variants": [
            {"name": "control", "weights": {"content": 0.3, "collaborative": 0.25, "neural": 0.2}},
            {"name": "neural_heavy", "weights": {"content": 0.2, "collaborative": 0.2, "neural": 0.4}}
        ]
    }
    """
    try:
        data = request.json
        name = data.get('name')
        variants = data.get('variants')
        
        if not name or not variants:
            return jsonify({'error': 'name and variants are required'}), 400
        
        ab_test_manager.create_experiment(name, variants)
        
        return jsonify({
            'status': 'success',
            'experiment': name,
            'variantCount': len(variants)
        })
    
    except Exception as e:
        logger.error(f"Error creating A/B test: {e}")
        return jsonify({'error': 'Internal server error'}), 500


@app.route('/ab-test/<experiment_name>/variant/<user_id>', methods=['GET'])
def get_ab_variant(experiment_name: str, user_id: str):
    """Get the A/B test variant assigned to a user"""
    try:
        variant = ab_test_manager.get_variant(user_id, experiment_name)
        
        if variant:
            return jsonify({
                'experiment': experiment_name,
                'userId': user_id,
                'variant': variant
            })
        else:
            return jsonify({'error': 'Experiment not found or not active'}), 404
    
    except Exception as e:
        logger.error(f"Error getting A/B variant: {e}")
        return jsonify({'error': 'Internal server error'}), 500


@app.route('/model-stats', methods=['GET'])
def get_model_stats():
    """Get statistics about the ML models"""
    try:
        stats = {
            'collaborative_filter': {
                'user_count': len(collaborative_filter.user_mapping),
                'item_count': len(collaborative_filter.item_mapping),
                'last_update': collaborative_filter.last_update.isoformat() if collaborative_filter.last_update else None
            },
            'neural_scorer': {
                'is_trained': neural_scorer.is_trained,
                'input_dim': neural_scorer.input_dim,
                'hidden_dim': neural_scorer.hidden_dim
            },
            'ensemble': {
                'weights': model_ensemble.weights
            },
            'ab_tests': {
                'active_experiments': list(ab_test_manager.experiments.keys())
            }
        }
        
        return jsonify(stats)
    
    except Exception as e:
        logger.error(f"Error getting model stats: {e}")
        return jsonify({'error': 'Internal server error'}), 500


@app.route('/batch-recommend', methods=['POST'])
def batch_recommend():
    """
    Generate recommendations for multiple users in batch
    Useful for pre-computing recommendations
    
    Request body:
    {
        "userIds": ["user1", "user2", "user3"],
        "maxResults": 10
    }
    """
    try:
        data = request.json
        user_ids = data.get('userIds', [])
        max_results = data.get('maxResults', 10)
        
        if not user_ids:
            return jsonify({'error': 'userIds are required'}), 400
        
        if not db_service:
            return jsonify({'error': 'Database not available'}), 503
        
        # Get all active pulses once
        available_pulses = db_service.get_active_pulses()
        
        results = {}
        for user_id in user_ids[:50]:  # Limit to 50 users per batch
            try:
                user_features = db_service.get_user_features(user_id) or {
                    'preferredCategories': [],
                    'preferredTimeSlots': [],
                    'socialActivityScore': 0.5
                }
                
                recommendations = []
                for pulse in available_pulses:
                    score = recommender.calculate_pulse_score(
                        pulse, user_features, user_id=user_id
                    )
                    recommendations.append({
                        'pulseId': pulse['id'],
                        'score': round(score, 3)
                    })
                
                recommendations.sort(key=lambda x: x['score'], reverse=True)
                results[user_id] = recommendations[:max_results]
            except Exception as e:
                logger.error(f"Error recommending for user {user_id}: {e}")
                results[user_id] = {'error': str(e)}
        
        return jsonify({
            'status': 'success',
            'userCount': len(results),
            'recommendations': results
        })
    
    except Exception as e:
        logger.error(f"Error in batch recommend: {e}")
        return jsonify({'error': 'Internal server error'}), 500


@app.route('/explain/<user_id>/<pulse_id>', methods=['GET'])
def explain_recommendation(user_id: str, pulse_id: str):
    """
    Get detailed explanation of why a pulse was recommended to a user
    """
    try:
        # Get user features
        user_features = {}
        if db_service:
            user_features = db_service.get_user_features(user_id) or {}
        
        if not user_features:
            user_features = {
                'preferredCategories': [],
                'preferredTimeSlots': [],
                'socialActivityScore': 0.5
            }
        
        # Mock pulse data (in production, fetch from DB)
        pulse = {'id': pulse_id, 'category': 'unknown'}
        if db_service:
            pulses = db_service.get_active_pulses()
            for p in pulses:
                if p['id'] == pulse_id:
                    pulse = p
                    break
        
        # Calculate individual scores
        explanation = {
            'userId': user_id,
            'pulseId': pulse_id,
            'scores': {
                'content': round(recommender._content_based_score(pulse, user_features), 3),
                'temporal': round(recommender._temporal_score(pulse, user_features), 3),
                'location': round(recommender._location_score(pulse, user_features), 3),
                'social': round(recommender._social_score(pulse, user_features), 3),
                'popularity': round(recommender._popularity_score(pulse), 3),
                'recency': round(recommender._recency_score(pulse), 3),
            },
            'collaborative_score': round(collaborative_filter.predict_score(user_id, pulse_id), 3),
            'final_score': round(recommender.calculate_pulse_score(pulse, user_features, user_id=user_id), 3),
            'ensemble_weights': model_ensemble.weights,
            'user_features': user_features,
            'pulse_features': {
                'category': pulse.get('category'),
                'participantCount': pulse.get('participantCount'),
                'eventTime': pulse.get('eventTime'),
                'location': pulse.get('location', {}).get('city')
            },
            'reason': recommender.generate_reason(pulse, user_features, 0.7)
        }
        
        return jsonify(explanation)
    
    except Exception as e:
        logger.error(f"Error explaining recommendation: {e}")
        return jsonify({'error': 'Internal server error'}), 500
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
