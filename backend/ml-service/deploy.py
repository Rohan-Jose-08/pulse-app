#!/usr/bin/env python3
"""
Production deployment script for ML Recommendation Service
Runs the service with production-ready settings
"""
import os
import sys
import logging
from pathlib import Path

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('ml-service.log'),
        logging.StreamHandler(sys.stdout)
    ]
)

logger = logging.getLogger(__name__)

def check_environment():
    """Check if all required environment variables are set"""
    required_vars = ['DATABASE_URL']
    missing = []
    
    for var in required_vars:
        if not os.getenv(var):
            missing.append(var)
    
    if missing:
        logger.error(f"Missing required environment variables: {', '.join(missing)}")
        logger.error("Please set them in .env file or environment")
        return False
    
    return True

def check_dependencies():
    """Check if all required packages are installed"""
    try:
        import flask
        import numpy
        import sqlalchemy
        import flask_cors
        logger.info("✓ All dependencies installed")
        return True
    except ImportError as e:
        logger.error(f"Missing dependency: {e}")
        logger.error("Run: pip install -r requirements.txt")
        return False

def start_production_server():
    """Start the production server with Gunicorn"""
    try:
        import gunicorn.app.base
        
        class StandaloneApplication(gunicorn.app.base.BaseApplication):
            def __init__(self, app, options=None):
                self.options = options or {}
                self.application = app
                super().__init__()
            
            def load_config(self):
                for key, value in self.options.items():
                    if key in self.cfg.settings and value is not None:
                        self.cfg.set(key.lower(), value)
            
            def load(self):
                return self.application
        
        # Import the Flask app
        from app import app
        
        # Gunicorn options
        options = {
            'bind': '0.0.0.0:5001',
            'workers': 4,
            'worker_class': 'sync',
            'timeout': 120,
            'keepalive': 5,
            'accesslog': 'access.log',
            'errorlog': 'error.log',
            'loglevel': 'info',
            'reload': False,
        }
        
        logger.info("Starting production server with Gunicorn...")
        logger.info(f"Workers: {options['workers']}")
        logger.info(f"Bind: {options['bind']}")
        
        StandaloneApplication(app, options).run()
        
    except ImportError:
        logger.warning("Gunicorn not installed, falling back to Flask development server")
        logger.warning("For production, install gunicorn: pip install gunicorn")
        start_development_server()

def start_development_server():
    """Start the development server (fallback)"""
    from app import app
    logger.info("Starting development server...")
    logger.warning("⚠️  DO NOT USE THIS IN PRODUCTION!")
    app.run(host='0.0.0.0', port=5001, debug=False)

if __name__ == '__main__':
    logger.info("=" * 60)
    logger.info("Pulse ML Recommendation Service - Production Deploy")
    logger.info("=" * 60)
    
    # Pre-flight checks
    logger.info("Running pre-flight checks...")
    
    if not check_environment():
        sys.exit(1)
    
    if not check_dependencies():
        sys.exit(1)
    
    logger.info("✓ All checks passed")
    logger.info("")
    
    # Start server
    mode = os.getenv('DEPLOY_MODE', 'production')
    
    if mode == 'production':
        start_production_server()
    else:
        start_development_server()
