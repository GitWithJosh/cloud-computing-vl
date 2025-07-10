#!/usr/bin/env python3
"""
🤖 Python ML Pipeline für Food Calorie Analysis
==========================================

Dieses Script demonstriert eine vollständige ML-Pipeline mit:
- Python scikit-learn Machine Learning
- Feature Engineering
- ML Model Training (Random Forest)
- Model Evaluation & Performance Metrics
- Batch Prediction

AUFGABE 4: Big Data Processing mit Python ML
"""

import pandas as pd
import numpy as np
import json
import time
import logging
import subprocess
import os
from datetime import datetime
from sklearn.ensemble import RandomForestRegressor
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import LabelEncoder
from sklearn.metrics import mean_squared_error, r2_score

# Logging Setup
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s | %(levelname)s | %(message)s',
    datefmt='%H:%M:%S'
)
logger = logging.getLogger(__name__)

def generate_sample_food_data():
    """Erstellt realistischen Food Dataset für ML Training"""
    
    # Erweiterte, realistische Food-Daten 
    foods = [
        # Protein-reiche Lebensmittel
        {'food_item': 'Chicken Breast', 'category': 'protein', 'base_calories_per_100g': 165},
        {'food_item': 'Salmon', 'category': 'protein', 'base_calories_per_100g': 208}, 
        {'food_item': 'Greek Yogurt', 'category': 'dairy', 'base_calories_per_100g': 59},
        {'food_item': 'Eggs', 'category': 'protein', 'base_calories_per_100g': 155},
        {'food_item': 'Tofu', 'category': 'protein', 'base_calories_per_100g': 76},
        
        # Kohlenhydrate
        {'food_item': 'Brown Rice', 'category': 'grain', 'base_calories_per_100g': 111},
        {'food_item': 'Quinoa', 'category': 'grain', 'base_calories_per_100g': 120},
        {'food_item': 'Sweet Potato', 'category': 'vegetable', 'base_calories_per_100g': 86},
        {'food_item': 'Oats', 'category': 'grain', 'base_calories_per_100g': 389},
        {'food_item': 'Banana', 'category': 'fruit', 'base_calories_per_100g': 89},
        
        # Gemüse (niedrige Kalorien)
        {'food_item': 'Broccoli', 'category': 'vegetable', 'base_calories_per_100g': 34},
        {'food_item': 'Spinach', 'category': 'vegetable', 'base_calories_per_100g': 23},
        {'food_item': 'Carrots', 'category': 'vegetable', 'base_calories_per_100g': 41},
        {'food_item': 'Bell Peppers', 'category': 'vegetable', 'base_calories_per_100g': 31},
        
        # Fette/Nüsse (sehr kalorienreich)
        {'food_item': 'Almonds', 'category': 'nuts', 'base_calories_per_100g': 579},
        {'food_item': 'Avocado', 'category': 'fruit', 'base_calories_per_100g': 160},
        {'food_item': 'Olive Oil', 'category': 'fat', 'base_calories_per_100g': 884}
    ]
    
    # Generiere realistische Portionsgrößen und Kalorien
    np.random.seed(42)  # Reproduzierbare Ergebnisse
    
    data = []
    for _ in range(500):  # 500 Trainingssamples
        food = np.random.choice(foods)
        
        # Realistische Portionsgrößen basierend auf Food-Typ
        if food['category'] == 'fat':
            weight = np.random.normal(15, 5)  # Öl: 10-20g typisch
        elif food['category'] == 'nuts':
            weight = np.random.normal(30, 10)  # Nüsse: 20-50g
        elif food['category'] == 'fruit':
            weight = np.random.normal(150, 40)  # Früchte: 100-200g
        elif food['category'] == 'vegetable':
            weight = np.random.normal(100, 30)  # Gemüse: 70-150g
        elif food['category'] == 'grain':
            weight = np.random.normal(75, 20)  # Getreide (gekocht): 50-100g
        else:  # protein/dairy
            weight = np.random.normal(120, 30)  # Protein: 90-150g
            
        weight = max(10, weight)  # Mindestens 10g
        
        # Kalorien berechnen mit kleinen realistischen Variationen
        base_calories = food['base_calories_per_100g']
        calorie_factor = weight / 100
        
        # Kleine Zufallsvariation für Realismus (±5%)
        variation = np.random.normal(1.0, 0.05)
        actual_calories = base_calories * calorie_factor * variation
        
        data.append({
            'food_item': food['food_item'],
            'category': food['category'],
            'weight_grams': round(weight, 1),
            'calories': round(actual_calories, 1)
        })
    
    df = pd.DataFrame(data)
    logger.info(f"📊 Generated {len(df)} food samples across {df['category'].nunique()} categories")
    
    return df

def feature_engineering(df):
    """Feature Engineering für ML Model"""
    
    # Label Encoding für kategorische Features
    le_food = LabelEncoder()
    le_category = LabelEncoder()
    
    df['food_encoded'] = le_food.fit_transform(df['food_item'])
    df['category_encoded'] = le_category.fit_transform(df['category'])
    
    # Engineering: Zusätzliche numerische Features
    df['weight_normalized'] = df['weight_grams'] / 100  # Normalisierung
    df['weight_squared'] = df['weight_grams'] ** 2     # Quadratisches Feature
    df['log_weight'] = np.log1p(df['weight_grams'])    # Log-Transform
    
    # Feature Matrix X und Target y
    feature_columns = ['food_encoded', 'category_encoded', 'weight_grams', 
                      'weight_normalized', 'weight_squared', 'log_weight']
    X = df[feature_columns]
    y = df['calories']
    
    logger.info(f"🔧 Feature engineering completed: {X.shape[1]} features, {len(y)} samples")
    
    return X, y, le_food, le_category

def train_ml_model(X, y):
    """Training des Random Forest ML Models"""
    
    # Train/Test Split
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42
    )
    
    # Random Forest Model (robust für verschiedene Datentypen)
    model = RandomForestRegressor(
        n_estimators=100,
        random_state=42,
        max_depth=10,
        min_samples_split=5
    )
    
    # Training
    logger.info("🤖 Training Random Forest model...")
    model.fit(X_train, y_train)
    
    # Evaluation
    y_pred = model.predict(X_test)
    
    # Metriken
    rmse = np.sqrt(mean_squared_error(y_test, y_pred))
    r2 = r2_score(y_test, y_pred)
    
    logger.info(f"   ✅ Model trained successfully!")
    logger.info(f"   📊 RMSE: {rmse:.2f} kcal")
    logger.info(f"   📊 R² Score: {r2:.4f}")
    
    metrics = {
        'rmse': round(rmse, 2),
        'r2_score': round(r2, 4),
        'train_samples': len(X_train),
        'test_samples': len(X_test)
    }
    
    return model, metrics

def run_batch_predictions(model, le_food, le_category):
    """Batch Predictions für neue Food Items"""
    
    # Test-Daten für Predictions
    test_foods = [
        {'food_item': 'Chicken Breast', 'category': 'protein', 'weight_grams': 150},
        {'food_item': 'Brown Rice', 'category': 'grain', 'weight_grams': 80},
        {'food_item': 'Broccoli', 'category': 'vegetable', 'weight_grams': 100},
        {'food_item': 'Almonds', 'category': 'nuts', 'weight_grams': 25},
        {'food_item': 'Banana', 'category': 'fruit', 'weight_grams': 120}
    ]
    
    predictions = []
    
    logger.info("🔮 Running batch predictions:")
    
    for food_data in test_foods:
        try:
            # Feature Encoding (muss konsistent mit Training sein)
            food_encoded = le_food.transform([food_data['food_item']])[0]
            category_encoded = le_category.transform([food_data['category']])[0]
            weight = food_data['weight_grams']
            
            # Feature Vector erstellen (gleiche Reihenfolge wie Training)
            features = np.array([[
                food_encoded,
                category_encoded,
                weight,          # weight_grams
                weight / 100,    # weight_normalized
                weight ** 2,     # weight_squared
                np.log1p(weight) # log_weight
            ]])
            
            # Vorhersage (suppress warnings by using DataFrame)
            feature_names = ['food_encoded', 'category_encoded', 'weight_grams', 
                           'weight_normalized', 'weight_squared', 'log_weight']
            features_df = pd.DataFrame(features, columns=feature_names)
            predicted_calories = model.predict(features_df)[0]
            
            result = {
                **food_data,
                'predicted_calories': round(predicted_calories, 1),
                'prediction_timestamp': datetime.now().isoformat()
            }
            predictions.append(result)
            
            logger.info(f"   🍽️  {food_data['food_item']} ({weight}g) → {predicted_calories:.1f} kcal")
            
        except ValueError as e:
            logger.warning(f"   ❌ Could not predict for {food_data['food_item']}: {e}")
    
    return predictions

def upload_to_minio_data_lake():
    """Upload ML Pipeline Results zu MinIO Data Lake mit MinIO Client (mc)"""
    try:
        logger.info('📤 Attempting to save results to MinIO Data Lake...')
        
        # Verwende den Timestamp aus der Umgebungsvariable oder generiere einen neuen
        timestamp = os.environ.get('ML_JOB_TIMESTAMP', datetime.now().strftime("%Y%m%d-%H%M%S"))
        if 'ML_JOB_TIMESTAMP' in os.environ:
            logger.info(f'🔄 Using timestamp from job: {timestamp}')
        else:
            logger.info(f'🔄 No job timestamp found, generating new one: {timestamp}')
            
        json_filename = f'ml_pipeline_results_{timestamp}.json'
        csv_filename = f'training_data_{timestamp}.csv'
        logger.info(f'📂 Using timestamped filenames: {json_filename} and {csv_filename}')
        
        # Datei-Größen protokollieren
        json_size = os.path.getsize('/tmp/ml_pipeline_results.json')
        csv_size = os.path.getsize('/tmp/training_data.csv')
        logger.info(f'📋 Files prepared for upload: JSON={json_size} bytes, CSV={csv_size} bytes')
        
        # MinIO Client (mc) Script erstellen - die effektivste Methode
        logger.info('� Creating MinIO upload script using MinIO Client (mc)...')
        mc_script = f'''#!/bin/bash
echo "Setting up MinIO Client (mc)..."
mc_found=$(which mc 2>/dev/null)

if [ -z "$mc_found" ]; then
    echo "MinIO Client not found, downloading..."
    wget -q https://dl.min.io/client/mc/release/linux-amd64/mc -O /tmp/mc
    chmod +x /tmp/mc
    MC_BIN="/tmp/mc"
else
    echo "MinIO Client found at: $mc_found"
    MC_BIN="mc"
fi

echo "Configuring MinIO client..."
$MC_BIN alias set myminio http://minio:9000 minioadmin minioadmin123 >/dev/null 2>&1

echo "Ensuring buckets exist..."
$MC_BIN mb myminio/processed-data --ignore-existing >/dev/null 2>&1
$MC_BIN mb myminio/raw-data --ignore-existing >/dev/null 2>&1

echo "Uploading ML pipeline results..."
$MC_BIN cp /tmp/ml_pipeline_results.json myminio/processed-data/{json_filename}
JSON_STATUS=$?

echo "Uploading training data..."
$MC_BIN cp /tmp/training_data.csv myminio/raw-data/{csv_filename}
CSV_STATUS=$?

if [ $JSON_STATUS -eq 0 ] && [ $CSV_STATUS -eq 0 ]; then
    echo "✅ SUCCESS: All files uploaded successfully to MinIO"
    echo "Files are available at:"
    echo " - processed-data/{json_filename}"
    echo " - raw-data/{csv_filename}"
    exit 0
else
    echo "⚠️ WARNING: Some uploads may have failed"
    echo "JSON upload status: $JSON_STATUS"
    echo "CSV upload status: $CSV_STATUS"
    exit 1
fi
'''
        
        # Script speichern und ausführen
        with open('/tmp/minio_upload.sh', 'w') as f:
            f.write(mc_script)
        
        logger.info('🚀 Running MinIO upload script...')
        subprocess.run(['chmod', '+x', '/tmp/minio_upload.sh'], check=True)
        result = subprocess.run(['/tmp/minio_upload.sh'], 
                             capture_output=True, text=True, timeout=180) # Erhöhe Timeout für langsamere Netzwerke
        
        if result.returncode == 0:
            logger.info('✅ MinIO upload successful!')
            logger.info(f'📂 Files uploaded to MinIO Data Lake:')
            logger.info(f'   - processed-data/{json_filename}')
            logger.info(f'   - raw-data/{csv_filename}')
            
            for line in result.stdout.splitlines():
                if line.strip():
                    logger.info(f'   {line}')
            
            # Cleanup temp script
            try:
                os.remove('/tmp/minio_upload.sh')
                logger.debug('🧹 Removed temporary upload script')
            except Exception:
                pass
                
            return True
        else:
            logger.warning(f'⚠️ MinIO upload had issues:')
            logger.warning(f'   Exit code: {result.returncode}')
            
            # Log detailed error information
            logger.warning(f'   STDERR:')
            for line in result.stderr.splitlines():
                if line.strip():
                    logger.warning(f'   {line}')
                    
            logger.warning(f'   STDOUT:')
            for line in result.stdout.splitlines():
                if line.strip():
                    logger.warning(f'   {line}')
            
            # Try to cleanup temp script even on failure
            try:
                os.remove('/tmp/minio_upload.sh')
            except Exception:
                pass
                
            raise Exception(f'MinIO upload script failed. Check if minio service is reachable at http://minio:9000')
        
        # Store results in a known location for manual inspection (Fallback)
        logger.info('📝 Creating job summary with upload details...')
        try:
            # Create a summary file with all important information
            summary = {
                'status': 'ML Pipeline completed successfully',
                'timestamp': datetime.now().isoformat(),
                'local_files': [
                    '/tmp/ml_pipeline_results.json',
                    '/tmp/training_data.csv'
                ],
                'minio_files': {
                    'processed_data': f'processed-data/{json_filename}',
                    'raw_data': f'raw-data/{csv_filename}'
                },
                'minio_access': {
                    'console_url': 'http://MASTER_IP:30901',
                    'credentials': 'minioadmin/minioadmin123',
                    'instructions': 'Navigate to the buckets "processed-data" and "raw-data" to see uploaded files'
                }
            }
            
            with open('/tmp/ml_pipeline_summary.json', 'w') as f:
                json.dump(summary, f, indent=2)
            
            logger.info('✅ Pipeline summary saved to /tmp/ml_pipeline_summary.json')
            logger.info('� Results available both in MinIO Data Lake and locally')
            
        except Exception as summary_e:
            logger.warning(f'⚠️ Could not create summary: {summary_e}')
        
    except Exception as e:
        logger.error(f'❌ MinIO upload failed: {e}')
        logger.info('📝 Results still saved locally for manual access:')
        logger.info('   - /tmp/ml_pipeline_results.json')
        logger.info('   - /tmp/training_data.csv')
        logger.info('� Tip: Check MinIO console manually at http://MASTER_IP:30901 (minioadmin/minioadmin123)')

def main():
    """Hauptfunktion der ML Pipeline"""
    logger.info("🚀 Starting Food Calorie ML Pipeline")
    logger.info("=" * 50)
    
    start_time = time.time()
    
    try:
        # 1. Data Generation
        logger.info("📈 Step 1: Generating training data...")
        df = generate_sample_food_data()
        logger.info(f"   ✅ Generated {len(df)} food samples")
        
        # 2. Feature Engineering
        logger.info("🔧 Step 2: Feature engineering...")
        X, y, le_food, le_category = feature_engineering(df)
        
        # 3. Model Training
        logger.info("🤖 Step 3: Training ML model...")
        model, metrics = train_ml_model(X, y)
        
        # 4. Batch Predictions
        logger.info("🔮 Step 4: Running batch predictions...")
        predictions = run_batch_predictions(model, le_food, le_category)
        
        # 5. Pipeline Summary
        total_time = time.time() - start_time
        
        logger.info("🎉 ML Pipeline completed successfully!")
        logger.info("=" * 50)
        logger.info(f"📊 Pipeline Summary:")
        logger.info(f"   ├─ Total Runtime: {total_time:.2f} seconds")
        logger.info(f"   ├─ Training Samples: {len(df)}")
        logger.info(f"   ├─ Model Accuracy (R²): {metrics['r2_score']:.4f}")
        logger.info(f"   ├─ Model Error (RMSE): {metrics['rmse']:.2f} kcal")
        logger.info(f"   └─ Predictions Made: {len(predictions)}")
        
        # Export Results (für Integration mit MinIO/Data Lake)
        # Verwende den gleichen Timestamp wie für die Dateinamen oder generiere einen neuen
        job_timestamp = os.environ.get('ML_JOB_TIMESTAMP', datetime.now().strftime("%Y%m%d-%H%M%S"))
        results = {
            'pipeline_run': {
                'job_id': f'ml-pipeline-{job_timestamp}',
                'timestamp': datetime.now().isoformat(),
                'runtime_seconds': total_time,
                'training_samples': len(df),
                'model_metrics': metrics,
                'predictions': predictions
            }
        }
        
        # Lokale Dateien erstellen
        logger.info("💾 Exporting results to local files...")
        with open('/tmp/ml_pipeline_results.json', 'w') as f:
            json.dump(results, f, indent=2)
        
        # Training data als CSV speichern
        df.to_csv('/tmp/training_data.csv', index=False)
        
        logger.info("✅ Results exported to: /tmp/ml_pipeline_results.json")
        logger.info("📊 Training data saved to /tmp/training_data.csv")
        
        # MinIO Upload mit robustem mc Tool
        upload_to_minio_data_lake()
        
        logger.info("🎯 ML Pipeline ready for production deployment!")
        
    except Exception as e:
        logger.error(f"❌ Pipeline failed: {e}")
        raise

if __name__ == "__main__":
    main()
