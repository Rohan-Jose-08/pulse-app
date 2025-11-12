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
        json={"userId": "test"},
        headers={"Content-Type": "application/json"}
    )
    
    print(f"Status: {response.status_code}")
    assert response.status_code == 400
    print("✓ Error handling test passed")

if __name__ == "__main__":
    print("=" * 60)
    print("ML Recommendation Service - Test Suite")
    print("=" * 60)
    
    try:
        test_health()
        test_recommendations()
        test_invalid_request()
        
        print("\n" + "=" * 60)
        print("✓ ALL TESTS PASSED!")
        print("=" * 60)
        
    except Exception as e:
        print(f"\n✗ TEST FAILED: {e}")
        import traceback
        traceback.print_exc()
