#!/bin/bash

# Firebase Data Export Script
# Exports all data from Firebase to local JSON files

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}Firebase Data Export${NC}"
echo ""

# Check if Firebase CLI is installed
if ! command -v firebase &> /dev/null; then
    echo -e "${YELLOW}Firebase CLI not found. Installing...${NC}"
    npm install -g firebase-tools
fi

# Create export directory
EXPORT_DIR="firebase-export"
mkdir -p $EXPORT_DIR/storage

echo -e "${YELLOW}[1/3] Logging in to Firebase...${NC}"
firebase login

echo -e "${YELLOW}[2/3] Exporting Firestore data...${NC}"
echo "This will export all profiles from Firestore..."

# Create export script
cat > export-firestore.py << 'EOF'
import firebase_admin
from firebase_admin import credentials, firestore
import json
import os
from datetime import datetime

# Initialize Firebase
cred_path = os.environ.get('FIREBASE_CREDENTIALS_PATH', '../wap-backend/firebase-credentials.json')
cred = credentials.Certificate(cred_path)
firebase_admin.initialize_app(cred)

db = firestore.client()

# Export profiles
print("Exporting profiles...")
profiles_ref = db.collection('profiles')
profiles = profiles_ref.stream()

profiles_data = []
for profile in profiles:
    data = profile.to_dict()
    data['_id'] = profile.id  # Preserve document ID

    # Convert timestamps to ISO format
    if 'created_at' in data and data['created_at']:
        data['created_at'] = data['created_at'].isoformat() if hasattr(data['created_at'], 'isoformat') else str(data['created_at'])
    if 'updated_at' in data and data['updated_at']:
        data['updated_at'] = data['updated_at'].isoformat() if hasattr(data['updated_at'], 'isoformat') else str(data['updated_at'])

    profiles_data.append(data)

# Save to JSON
output_file = 'firebase-export/profiles.json'
with open(output_file, 'w') as f:
    json.dump(profiles_data, f, indent=2)

print(f"✓ Exported {len(profiles_data)} profiles to {output_file}")

# Export metadata
metadata = {
    'export_date': datetime.now().isoformat(),
    'total_profiles': len(profiles_data),
    'source': 'Firebase Firestore',
    'collection': 'profiles'
}

with open('firebase-export/metadata.json', 'w') as f:
    json.dump(metadata, f, indent=2)

print("✓ Export complete!")
EOF

# Run export
python3 export-firestore.py

echo -e "${GREEN}✓ Firestore data exported${NC}"
echo ""

echo -e "${YELLOW}[3/3] Exporting Firebase Storage files...${NC}"

# Create storage export script
cat > export-storage.py << 'EOF'
import firebase_admin
from firebase_admin import credentials, storage
import os

# Initialize if not already done
if not firebase_admin._apps:
    cred_path = os.environ.get('FIREBASE_CREDENTIALS_PATH', '../wap-backend/firebase-credentials.json')
    cred = credentials.Certificate(cred_path)
    firebase_admin.initialize_app(cred, {
        'storageBucket': 'swap-besmart.appspot.com'  # Update with your bucket name
    })

bucket = storage.bucket()

# List all blobs
blobs = bucket.list_blobs()

print("Downloading storage files...")
count = 0
for blob in blobs:
    local_path = f"firebase-export/storage/{blob.name}"
    os.makedirs(os.path.dirname(local_path), exist_ok=True)

    blob.download_to_filename(local_path)
    print(f"  Downloaded: {blob.name}")
    count += 1

print(f"✓ Downloaded {count} files")
EOF

# Run storage export (may fail if no files)
python3 export-storage.py || echo "No storage files found or error occurred"

echo -e "${GREEN}✓ Storage files exported${NC}"
echo ""

# Summary
echo -e "${GREEN}Export Complete!${NC}"
echo ""
echo "Files exported to: $EXPORT_DIR/"
ls -lh $EXPORT_DIR/

# Count profiles
PROFILE_COUNT=$(python3 -c "import json; print(len(json.load(open('$EXPORT_DIR/profiles.json'))))")
echo ""
echo "Total profiles exported: $PROFILE_COUNT"
echo ""
echo "Next step: Import to Cosmos DB"
echo "  python import-to-cosmos.py --input $EXPORT_DIR/profiles.json"
