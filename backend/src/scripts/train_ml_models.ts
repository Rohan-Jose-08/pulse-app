/**
 * Script to train ML models periodically
 * Run this as a scheduled task or cron job
 */
import axios from 'axios';

const ML_SERVICE_URL = process.env.ML_SERVICE_URL || 'http://localhost:5001';

async function trainModels() {
  console.log(`[${new Date().toISOString()}] Starting ML model training...`);
  
  try {
    const response = await axios.post(
      `${ML_SERVICE_URL}/train`,
      {
        model: 'all',
        days: 30,
        force: true
      },
      { timeout: 300000 } // 5 minute timeout
    );
    
    console.log('Training completed successfully:');
    console.log(JSON.stringify(response.data, null, 2));
    
    return response.data;
  } catch (error: any) {
    console.error('Training failed:', error.message);
    throw error;
  }
}

// Run if called directly
if (require.main === module) {
  trainModels()
    .then(() => {
      console.log('✓ Training job completed');
      process.exit(0);
    })
    .catch((error) => {
      console.error('✗ Training job failed:', error);
      process.exit(1);
    });
}

export { trainModels };
