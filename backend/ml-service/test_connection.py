"""Quick test to verify database connection for ML service"""
from dotenv import load_dotenv
import os
from sqlalchemy import create_engine, text
import sys

# Load environment variables
load_dotenv()
DATABASE_URL = os.getenv('DATABASE_URL')

print("=" * 60)
print("ML SERVICE DATABASE CONNECTION TEST")
print("=" * 60)
print()

if not DATABASE_URL:
    print("❌ DATABASE_URL not found in .env file")
    sys.exit(1)

# Show connection info (hide password)
if '@' in DATABASE_URL:
    masked = DATABASE_URL.split('@')[0].split(':')[0] + ":***@" + DATABASE_URL.split('@')[1]
else:
    masked = DATABASE_URL[:20] + "..."
print(f"📡 Connecting to: {masked}")
print()

try:
    # Ensure the URL uses postgresql:// (not postgres://)
    db_url = DATABASE_URL.replace('postgres://', 'postgresql://')
    
    # Create engine
    engine = create_engine(db_url, pool_pre_ping=True)
    
    # Test connection
    print("⏳ Testing connection...")
    with engine.connect() as conn:
        # Simple query
        result = conn.execute(text("SELECT 1 as test"))
        row = result.fetchone()
        
        if row and row[0] == 1:
            print("✅ Database connection successful!")
            print()
            
            # Query users
            try:
                result = conn.execute(text('SELECT COUNT(*) FROM "User"'))
                count = result.fetchone()[0]
                print(f"  📊 Users in database: {count}")
            except Exception as e:
                print(f"  ⚠️  User table: {e}")
            
            # Query pulses
            try:
                result = conn.execute(text('SELECT COUNT(*) FROM "Pulse"'))
                count = result.fetchone()[0]
                print(f"  📊 Pulses in database: {count}")
            except Exception as e:
                print(f"  ⚠️  Pulse table: {e}")
            
            # Check ML tables
            try:
                result = conn.execute(text('SELECT COUNT(*) FROM "PulseInteraction"'))
                count = result.fetchone()[0]
                print(f"  📊 Pulse interactions: {count}")
            except Exception as e:
                print(f"  ⚠️  PulseInteraction table: {e}")
            
            try:
                result = conn.execute(text('SELECT COUNT(*) FROM "PulseRecommendation"'))
                count = result.fetchone()[0]
                print(f"  📊 Cached recommendations: {count}")
            except Exception as e:
                print(f"  ⚠️  PulseRecommendation table: {e}")
            
            print()
            print("🎉 ML Service is ready to connect to your database!")
            print()
            print("✅ Next step: Start the ML service with: python app.py")
        else:
            print("❌ Connection test failed")
            
except Exception as e:
    print(f"❌ Connection failed: {e}")
    print()
    print("Common solutions:")
    print("  1. Check your DATABASE_URL in .env file")
    print("  2. Ensure your database is running")
    print("  3. Verify firewall/network settings")
    print("  4. Check if SSL is required (?sslmode=require)")
