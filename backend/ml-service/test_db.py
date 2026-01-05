from dotenv import load_dotenv
import os
from sqlalchemy import create_engine, text

# Load environment variables
load_dotenv()
DATABASE_URL = os.getenv('DATABASE_URL')

if not DATABASE_URL:
    print("❌ DATABASE_URL not set in .env file")
    print("Please create a .env file with your database connection string")
    print("Example: DATABASE_URL=postgresql://user:password@host:port/database")
    exit(1)

# Hide password in output
safe_url = DATABASE_URL.split('@')[1] if '@' in DATABASE_URL else 'database'
print(f"Testing connection to: {safe_url}")
print()

try:
    # Ensure the URL uses postgresql:// (not postgres://)
    db_url = DATABASE_URL.replace('postgres://', 'postgresql://')
    
    # Create engine
    engine = create_engine(db_url)
    
    # Test connection
    with engine.connect() as conn:
        # Simple query
        result = conn.execute(text("SELECT 1 as test"))
        row = result.fetchone()
        
        if row and row[0] == 1:
            print("✓ Database connection successful!")
            print()
            
            # Try to query a Pulse table
            try:
                result = conn.execute(text("SELECT COUNT(*) FROM \"User\""))
                count = result.fetchone()[0]
                print(f"✓ Found {count} users in database")
                
                result = conn.execute(text("SELECT COUNT(*) FROM \"Pulse\""))
                count = result.fetchone()[0]
                print(f"✓ Found {count} pulses in database")
                
                print()
                print("🎉 ML Service can successfully connect to your database!")
            except Exception as e:
                print(f"⚠️  Connection works, but couldn't query tables: {e}")
                print("This might mean your database schema isn't set up yet.")
                print("Run 'npx prisma db push' from the backend directory.")
        else:
            print("❌ Connection test query failed")
            
except Exception as e:
    print(f"❌ Connection failed: {e}")
    print()
    print("Common issues:")
    print("- Check your username and password are correct")
    print("- Verify the host and port are accessible")
    print("- Ensure your IP is whitelisted (for cloud databases)")
    print("- Try adding ?sslmode=require to your connection string")
