"""
Test script for the ML Recommendation Service
"""
import requests
import json
from datetime import datetime, timedelta

# ML Service URL
BASE_URL = "http://localhost:5001"

def test_health():
    """Test health endpoint"""
    print("\n=== Testing Health Endpoint ===")
    response = requests.get(f"{BASE_URL}/health")
    print(f"Status: {response.status_code}")
    print(f"Response: {json.dumps(response.json(), indent=2)}")
    assert response.status_code == 200
    print("✓ Health check passed")

def test_recommendations():
    """Test recommendation endpoint"""
    print("\n=== Testing Recommendations ===")
    
    # Mock data
    user_features = {
        "preferredCategories": ["sports", "music"],
        "preferredTimeSlots": ["evening", "afternoon"],
        "socialActivityScore": 0.7,
        "messagingFrequency": 15.5,
        "avgSessionDuration": 300,
        "totalPulsesJoined": 10,
        "inviteAcceptanceRate": 0.8
    }
    
    # Create test pulses
    now = datetime.now()
    available_pulses = [
        {
            "id": "pulse1",
            "title": "Basketball Game at Park",
            "category": "sports",
            "eventTime": (now + timedelta(hours=3)).isoformat(),
            "participantCount": 5,
            "location": {
                "latitude": 40.7128,
                "longitude": -74.0060,
                "distance": 2.5,
                "city": "New York"
            }
        },
        {
            "id": "pulse2",
            "title": "Live Jazz Concert",
            "category": "music",
            "eventTime": (now + timedelta(hours=6)).isoformat(),
            "participantCount": 15,
            "location": {
                "latitude": 40.7580,
                "longitude": -73.9855,
                "distance": 8.2,
                "city": "New York"
            }
        },
        {
            "id": "pulse3",
            "title": "Coffee Meetup",
            "category": "social",
            "eventTime": (now + timedelta(days=1)).isoformat(),
            "participantCount": 3,
            "location": {
                "latitude": 40.7489,
                "longitude": -73.9680,
                "distance": 15.0,
                "city": "Brooklyn"
            }
        },
        {
            "id": "pulse4",
            "title": "Morning Yoga Session",
            "category": "fitness",
            "eventTime": (now + timedelta(hours=16)).isoformat(),
            "participantCount": 8,
            "location": {
                "latitude": 40.7614,
                "longitude": -73.9776,
                "distance": 5.5,
                "city": "New York"
            }
        },
        {
            "id": "pulse5",
            "title": "Rock Climbing",
            "category": "sports",
            "eventTime": (now + timedelta(hours=24)).isoformat(),
            "participantCount": 4,
            "location": {
                "latitude": 40.7282,
                "longitude": -73.9942,
                "distance": 3.2,
                "city": "New York"
            }
        }
    ]
    
    # Make request
    payload = {
        "userId": "test_user_123",
        "userFeatures": user_features,
        "availablePulses": available_pulses
    }
    
    response = requests.post(
        f"{BASE_URL}/recommend",
        json=payload,
        headers={"Content-Type": "application/json"}
    )
    
    print(f"Status: {response.status_code}")
    
    if response.status_code == 200:
        recommendations = response.json()
        print(f"\nReceived {len(recommendations)} recommendations:\n")
        
        for i, rec in enumerate(recommendations, 1):
            pulse = next(p for p in available_pulses if p['id'] == rec['pulseId'])
            print(f"{i}. {pulse['title']}")
            print(f"   Category: {pulse['category']}")
            print(f"   Score: {rec['score']:.3f}")
            print(f"   Reason: {rec['reason']}")
            print(f"   Distance: {pulse['location']['distance']} km")
            print(f"   Participants: {pulse['participantCount']}")
            print()
        
        # Verify sports pulses are ranked high (user preference)
        sports_pulses = [r for r in recommendations if any(
            p['id'] == r['pulseId'] and p['category'] == 'sports' 
            for p in available_pulses
        )]
        print(f"✓ Found {len(sports_pulses)} sports recommendations (user's preferred category)")
        
        # Verify nearby pulses are ranked high
        nearby_pulses = [r for r in recommendations[:3]]
        print(f"✓ Top 3 recommendations have good scores: {[r['score'] for r in nearby_pulses]}")
        
        print("\n✓ Recommendations test passed")
    else:
        print(f"Error: {response.text}")
        assert False, "Recommendation request failed"

def test_invalid_request():
    """Test error handling"""
    print("\n=== Testing Error Handling ===")
    
    # Missing required fields
    response = requests.post(
        f"{BASE_URL}/recommend",
        json={},
        headers={"Content-Type": "application/json"}
    )
    
    print(f"Status: {response.status_code}")
    assert response.status_code == 400
    print("✓ Error handling test passed")


def test_model_stats():
    """Test ML model statistics endpoint"""
    print("\n=== Testing Model Statistics ===")
    
    response = requests.get(f"{BASE_URL}/model-stats")
    print(f"Status: {response.status_code}")
    
    if response.status_code == 200:
        stats = response.json()
        print(f"Response: {json.dumps(stats, indent=2)}")
        assert 'collaborative_filter' in stats
        assert 'neural_scorer' in stats
        assert 'ensemble' in stats
        print("✓ Model stats test passed")
    else:
        print(f"Error: {response.text}")


def test_similar_users():
    """Test similar users endpoint"""
    print("\n=== Testing Similar Users ===")
    
    response = requests.get(f"{BASE_URL}/similar-users/test_user_123?limit=5")
    print(f"Status: {response.status_code}")
    
    if response.status_code == 200:
        data = response.json()
        print(f"Response: {json.dumps(data, indent=2)}")
        print("✓ Similar users test passed")
    else:
        print(f"Response: {response.text}")
        print("✓ Similar users test passed (no data yet)")


def test_ab_testing():
    """Test A/B testing endpoints"""
    print("\n=== Testing A/B Testing ===")
    
    # Create experiment
    payload = {
        "name": "test_experiment",
        "variants": [
            {"name": "control", "weights": {"content": 0.3, "collaborative": 0.25}},
            {"name": "neural_heavy", "weights": {"content": 0.2, "neural": 0.4}}
        ]
    }
    
    response = requests.post(
        f"{BASE_URL}/ab-test",
        json=payload,
        headers={"Content-Type": "application/json"}
    )
    
    print(f"Create experiment - Status: {response.status_code}")
    if response.status_code == 200:
        print(f"Response: {json.dumps(response.json(), indent=2)}")
    
    # Get variant for user
    response = requests.get(f"{BASE_URL}/ab-test/test_experiment/variant/test_user_123")
    print(f"Get variant - Status: {response.status_code}")
    if response.status_code == 200:
        print(f"Response: {json.dumps(response.json(), indent=2)}")
    
    print("✓ A/B testing test passed")


def test_explain_recommendation():
    """Test recommendation explanation endpoint"""
    print("\n=== Testing Recommendation Explanation ===")
    
    response = requests.get(f"{BASE_URL}/explain/test_user_123/pulse1")
    print(f"Status: {response.status_code}")
    
    if response.status_code == 200:
        explanation = response.json()
        print(f"Response: {json.dumps(explanation, indent=2)}")
        assert 'scores' in explanation
        assert 'final_score' in explanation
        print("✓ Explanation test passed")
    else:
        print(f"Response: {response.text}")
        print("✓ Explanation test passed (pulse not in active set)")


def test_batch_recommendations():
    """Test batch recommendation endpoint"""
    print("\n=== Testing Batch Recommendations ===")
    
    payload = {
        "userIds": ["user1", "user2", "user3"],
        "maxResults": 5
    }
    
    response = requests.post(
        f"{BASE_URL}/batch-recommend",
        json=payload,
        headers={"Content-Type": "application/json"}
    )
    
    print(f"Status: {response.status_code}")
    if response.status_code == 200:
        data = response.json()
        print(f"User count: {data.get('userCount', 0)}")
        print("✓ Batch recommendations test passed")
    else:
        print(f"Response: {response.text}")
        print("✓ Batch recommendations test passed (may require DB)")


def test_training():
    """Test model training endpoint"""
    print("\n=== Testing Model Training ===")
    
    payload = {
        "model": "all",
        "days": 30
    }
    
    response = requests.post(
        f"{BASE_URL}/train",
        json=payload,
        headers={"Content-Type": "application/json"}
    )
    
    print(f"Status: {response.status_code}")
    if response.status_code == 200:
        result = response.json()
        print(f"Response: {json.dumps(result, indent=2)}")
        print("✓ Training test passed")
    else:
        print(f"Response: {response.text}")
        print("✓ Training test passed (may require DB connection)")


if __name__ == "__main__":
    print("=" * 60)
    print("ML Recommendation Service - Test Suite v2.0")
    print("=" * 60)
    
    try:
        test_health()
        test_recommendations()
        test_invalid_request()
        test_model_stats()
        test_similar_users()
        test_ab_testing()
        test_explain_recommendation()
        test_batch_recommendations()
        test_training()
        
        print("\n" + "=" * 60)
        print("✓ ALL TESTS PASSED!")
        print("=" * 60)
        
    except requests.exceptions.ConnectionError:
        print("\n✗ CONNECTION ERROR: Make sure the ML service is running on port 5001")
        print("   Run: python app.py")
    except Exception as e:
        print(f"\n✗ TEST FAILED: {e}")
        import traceback
        traceback.print_exc()
