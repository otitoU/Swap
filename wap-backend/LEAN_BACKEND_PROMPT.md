# Lean Backend Build Instructions

## Overview
This document provides a complete prompt for building a simplified, production-ready backend for the skill-swap platform. Use this with any AI coding assistant to create a lean version that removes complexity while maintaining core functionality.

---

## Understanding Semantic Search vs Keyword Search

### What is Semantic Search?

**Semantic search** understands the **meaning** of queries, not just exact word matches. It uses machine learning (BERT embeddings) to find conceptually similar content.

### Comparison

| Feature | Keyword Search | Semantic Search |
|---------|---------------|-----------------|
| **Query Type** | Exact words only | Natural language |
| **Example Query** | "guitar" | "teach me guitar and music" |
| **Matching** | Exact text match | Meaning/concept match |
| **Synonyms** | ❌ Misses "guitar lessons" | ✅ Finds "guitar", "music lessons" |
| **Related Terms** | ❌ Misses "music theory" | ✅ Finds related concepts |
| **Implementation** | Simple string search | ML embeddings + vector DB |
| **Dependencies** | None | transformers, Qdrant |
| **Speed** | Very fast | Slower (but cached) |

### Natural Query Examples

#### Example 1: Conversational
```json
{
  "query": "I need someone to teach me guitar and music theory"
}
```
**Finds:**
- "Guitar lessons, jazz, music theory"
- "Classical guitar instruction"
- "Music production, playing instruments"

#### Example 2: Short phrase
```json
{
  "query": "Python web development"
}
```
**Finds:**
- "FastAPI, Django, backend development"
- "Python programming, REST APIs"
- "Full-stack development with Python"

#### Example 3: Question format
```json
{
  "query": "Who can help me learn graphic design?"
}
```
**Finds:**
- "Adobe Photoshop, Illustrator, UI design"
- "Digital art, logo design"
- "Visual design, branding"

### Why Semantic Search is Powerful

1. **Synonyms work**: "programming" finds "coding", "development", "software engineering"
2. **Related concepts**: "fitness" finds "yoga", "gym training", "nutrition"
3. **Different phrasing**: "teach me X" = "learn X" = "X lessons" = "X instruction"
4. **Context understanding**: "Italian food" understands "pasta", "pizza", "cuisine"
5. **Typo tolerance**: Minor spelling errors still work
6. **Multi-language**: Can work across similar languages

---

## AI Agent Prompt: Build Lean Skill-Swap Backend

### Context
Build a **minimal viable backend** for a skill-exchange platform where users can create profiles with skills they offer and services they need, then find matches using **simple keyword-based search** (no ML/vector databases).

---

### Core Requirements

#### 1. Technology Stack
- **Framework**: FastAPI (Python 3.11+)
- **Database**: Firebase Firestore (serverless, no local setup)
- **Matching**: Keyword-based search (no ML, no vector DB)
- **Deployment**: Single Docker container

#### 2. Profile Schema

```python
{
  "uid": "firebase_user_123",           # Required - Unique ID
  "email": "alice@example.com",         # Required
  "display_name": "Alice Smith",        # Optional
  "photo_url": "https://...",           # Optional
  "bio": "Software engineer...",        # Optional
  "city": "New York",                   # Optional
  "skills_to_offer": "Python, FastAPI", # Required - What they teach
  "services_needed": "Guitar, music",   # Required - What they want
  "created_at": "2024-01-15T...",       # Auto-generated
  "updated_at": "2024-01-15T..."        # Auto-generated
}
```

---

### 3. Required Endpoints

#### A. Health Check
```
GET /healthz
Response: {"ok": true}
```

#### B. Profile Management

**Create/Update Profile**
```
POST /profiles/upsert
Body: ProfileCreate (see schema above)
Response: ProfileResponse with timestamps
```

**Get Profile by UID**
```
GET /profiles/{uid}
Response: ProfileResponse or 404
```

**Update Profile (Partial)**
```
PATCH /profiles/{uid}
Body: Partial profile fields
Response: Updated ProfileResponse
```

**Delete Profile**
```
DELETE /profiles/{uid}
Response: {"message": "Profile deleted", "uid": "..."}
```

#### C. Matching Endpoint

**Simple Keyword Search**
```
POST /match
Body: {
  "query": "Python programming",
  "limit": 10
}
Response: List of matching profiles with scores
```

---

### 4. Matching Logic (Simple Keyword-Based)

**Algorithm:**
1. Split query into lowercase keywords
2. Fetch all profiles from Firestore
3. For each profile, count how many keywords appear in their `skills_to_offer`
4. Return profiles sorted by keyword overlap count
5. Minimum 1 keyword match required

**Implementation:**
```python
def keyword_match(query: str, limit: int = 10):
    # Normalize and split query
    keywords = set(query.lower().split())
    
    # Fetch all profiles
    profiles = db.collection('profiles').stream()
    
    matches = []
    for doc in profiles:
        data = doc.to_dict()
        skills = data.get('skills_to_offer', '').lower()
        
        # Count keyword overlaps
        overlap = sum(1 for kw in keywords if kw in skills)
        
        if overlap > 0:
            matches.append({
                **data,
                'score': overlap,
                'matched_keywords': [kw for kw in keywords if kw in skills]
            })
    
    # Sort by score (most matches first)
    matches.sort(key=lambda x: x['score'], reverse=True)
    return matches[:limit]
```

---

### 5. Project Structure

```
lean-backend/
├── app/
│   ├── __init__.py
│   ├── main.py              # FastAPI app + all endpoints
│   ├── config.py            # Settings (Firebase credentials path)
│   ├── firebase_db.py       # Firebase CRUD operations
│   ├── schemas.py           # Pydantic models
│   └── matching.py          # Keyword matching logic
├── firebase-credentials.json # Firebase service account key
├── requirements.txt
├── Dockerfile
├── .env.example
└── README.md
```

---

### 6. Dependencies (requirements.txt)

```txt
fastapi==0.109.0
uvicorn[standard]==0.27.0
firebase-admin==6.4.0
pydantic[email]==2.5.3
python-dotenv==1.0.0
```

**Total: 5 packages (vs 14 in full version)**

---

### 7. Firebase Setup Code

```python
# app/firebase_db.py
import firebase_admin
from firebase_admin import credentials, firestore
from typing import Optional, Dict, Any
from datetime import datetime

class FirebaseService:
    def __init__(self, credentials_path: str):
        cred = credentials.Certificate(credentials_path)
        firebase_admin.initialize_app(cred)
        self.db = firestore.client()
    
    def upsert_profile(self, uid: str, data: Dict[str, Any]) -> Dict[str, Any]:
        """Create or update a profile."""
        now = datetime.utcnow()
        
        # Check if exists
        doc_ref = self.db.collection('profiles').document(uid)
        existing = doc_ref.get()
        
        if existing.exists:
            data['updated_at'] = now
            doc_ref.update(data)
        else:
            data['created_at'] = now
            data['updated_at'] = now
            doc_ref.set(data)
        
        return {**data, 'uid': uid}
    
    def get_profile(self, uid: str) -> Optional[Dict[str, Any]]:
        """Get profile by UID."""
        doc = self.db.collection('profiles').document(uid).get()
        if doc.exists:
            return {**doc.to_dict(), 'uid': doc.id}
        return None
    
    def update_profile(self, uid: str, data: Dict[str, Any]) -> Dict[str, Any]:
        """Partial update."""
        data['updated_at'] = datetime.utcnow()
        doc_ref = self.db.collection('profiles').document(uid)
        doc_ref.update(data)
        return self.get_profile(uid)
    
    def delete_profile(self, uid: str):
        """Delete profile."""
        self.db.collection('profiles').document(uid).delete()
    
    def get_all_profiles(self):
        """Get all profiles (for matching)."""
        return self.db.collection('profiles').stream()
```

---

### 8. FastAPI Main App

```python
# app/main.py
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from typing import List

from app.schemas import ProfileCreate, ProfileUpdate, ProfileResponse
from app.firebase_db import FirebaseService
from app.matching import keyword_match
from app.config import settings

# Initialize Firebase
firebase_service = FirebaseService(settings.firebase_credentials_path)

app = FastAPI(
    title="Skill Swap API - Lean Version",
    description="Simple skill exchange platform with keyword matching",
    version="1.0.0",
)

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/healthz")
def health_check():
    return {"ok": True}

@app.post("/profiles/upsert", response_model=ProfileResponse)
def upsert_profile(profile: ProfileCreate):
    profile_dict = profile.model_dump()
    uid = profile_dict.pop('uid')
    result = firebase_service.upsert_profile(uid, profile_dict)
    return ProfileResponse(**result)

@app.get("/profiles/{uid}", response_model=ProfileResponse)
def get_profile(uid: str):
    profile = firebase_service.get_profile(uid)
    if not profile:
        raise HTTPException(status_code=404, detail="Profile not found")
    return ProfileResponse(**profile)

@app.patch("/profiles/{uid}", response_model=ProfileResponse)
def update_profile(uid: str, update: ProfileUpdate):
    existing = firebase_service.get_profile(uid)
    if not existing:
        raise HTTPException(status_code=404, detail="Profile not found")
    
    update_dict = update.model_dump(exclude_unset=True)
    result = firebase_service.update_profile(uid, update_dict)
    return ProfileResponse(**result)

@app.delete("/profiles/{uid}")
def delete_profile(uid: str):
    existing = firebase_service.get_profile(uid)
    if not existing:
        raise HTTPException(status_code=404, detail="Profile not found")
    
    firebase_service.delete_profile(uid)
    return {"message": "Profile deleted successfully", "uid": uid}

@app.post("/match")
def match_profiles(request: dict):
    query = request.get('query', '')
    limit = request.get('limit', 10)
    
    if not query:
        raise HTTPException(status_code=422, detail="Query is required")
    
    matches = keyword_match(
        query=query,
        limit=limit,
        firebase_service=firebase_service
    )
    return matches
```

---

### 9. Dockerfile

```dockerfile
FROM python:3.11-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy app
COPY app/ ./app/
COPY firebase-credentials.json .

# Expose port
EXPOSE 8000

# Run
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

---

### 10. What to Skip (For Lean Version)

| Feature | Full Version | Lean Version |
|---------|-------------|--------------|
| Vector DB (Qdrant) | ✅ | ❌ Skip |
| ML Embeddings (BERT) | ✅ | ❌ Skip |
| Semantic Search | ✅ | ❌ Use keywords |
| Reciprocal Matching | ✅ | ❌ Simple match only |
| Multiple Routers | ✅ | ❌ Single main.py |
| Docker Compose | ✅ | ❌ Single Dockerfile |
| Caching | ✅ | ❌ Skip |
| Rate Limiting | ✅ | ❌ Skip |

**Result:** ~200 lines of code (vs 1000+)

---

### 11. Testing Commands

```bash
# Build and run
docker build -t lean-backend .
docker run -p 8000:8000 lean-backend

# Health check
curl http://localhost:8000/healthz

# Create profile
curl -X POST http://localhost:8000/profiles/upsert \
  -H "Content-Type: application/json" \
  -d '{
    "uid": "user123",
    "email": "alice@test.com",
    "display_name": "Alice",
    "skills_to_offer": "Python programming, FastAPI, web development",
    "services_needed": "Guitar lessons, music theory"
  }'

# Find matches
curl -X POST http://localhost:8000/match \
  -H "Content-Type: application/json" \
  -d '{
    "query": "Python programming",
    "limit": 5
  }'

# Get profile
curl http://localhost:8000/profiles/user123

# Update profile
curl -X PATCH http://localhost:8000/profiles/user123 \
  -H "Content-Type: application/json" \
  -d '{"bio": "Updated bio text"}'

# Delete profile
curl -X DELETE http://localhost:8000/profiles/user123
```

---

### 12. Success Criteria

✅ Can create/update/delete profiles via REST API  
✅ Can retrieve profile by UID  
✅ Can find matches using keyword search  
✅ Returns JSON responses with proper HTTP status codes  
✅ Works with single `docker run` command  
✅ Includes error handling (404, 422, 500)  
✅ Interactive API docs at `/docs`  
✅ Health check endpoint works  
✅ CORS enabled for frontend integration  
✅ Total codebase under 500 lines  
✅ No external services except Firebase  
✅ Deployable in under 5 minutes  

---

### 13. README.md Template

```markdown
# Lean Skill-Swap Backend

Simple skill exchange platform with keyword-based matching.

## Quick Start

### 1. Setup Firebase
1. Go to [Firebase Console](https://console.firebase.com)
2. Create project → Enable Firestore
3. Download service account JSON → Save as `firebase-credentials.json`

### 2. Run with Docker
```bash
docker build -t lean-backend .
docker run -p 8000:8000 lean-backend
```

### 3. Test
```bash
curl http://localhost:8000/healthz
```

## API Docs
- Swagger UI: http://localhost:8000/docs
- ReDoc: http://localhost:8000/redoc

## Endpoints
- `POST /profiles/upsert` - Create/update profile
- `GET /profiles/{uid}` - Get profile
- `PATCH /profiles/{uid}` - Update profile
- `DELETE /profiles/{uid}` - Delete profile
- `POST /match` - Find matches

## Tech Stack
- Python 3.11 + FastAPI
- Firebase Firestore
- Keyword-based matching (no ML)
```

---

### 14. Deployment Options

#### Option A: Docker (Any Platform)
```bash
docker build -t lean-backend .
docker run -p 8000:8000 \
  -v $(pwd)/firebase-credentials.json:/app/firebase-credentials.json \
  lean-backend
```

#### Option B: Fly.io
```bash
fly launch
fly deploy
```

#### Option C: Railway
```bash
# Connect GitHub repo, Railway auto-deploys
```

#### Option D: Local Development
```bash
pip install -r requirements.txt
uvicorn app.main:app --reload
```

---

### 15. Upgrade Path (Future Enhancement)

When ready to add semantic search:

1. **Add dependencies:**
   ```
   sentence-transformers==2.2.2
   qdrant-client==1.7.0
   ```

2. **Add Qdrant service:**
   ```bash
   docker run -p 6333:6333 qdrant/qdrant
   ```

3. **Replace keyword matching with embeddings:**
   ```python
   from sentence_transformers import SentenceTransformer
   model = SentenceTransformer('all-MiniLM-L6-v2')
   
   query_vec = model.encode(query)
   results = qdrant.search(query_vec, limit=10)
   ```

---

## Deliverables Checklist

- [ ] Complete FastAPI application in `app/` directory
- [ ] `requirements.txt` with minimal dependencies
- [ ] `Dockerfile` for containerization
- [ ] `README.md` with setup instructions
- [ ] `.env.example` file
- [ ] Example API requests in README
- [ ] Error handling for 404, 422, 500
- [ ] CORS middleware configured
- [ ] Pydantic models with validation
- [ ] Firebase integration working
- [ ] Keyword matching implemented
- [ ] Health check endpoint
- [ ] Interactive docs at `/docs`
- [ ] Total code under 500 lines

---

## Priority

**Focus on: Simplicity, Speed, Maintainability**

The backend should be:
- ✅ Understandable in 10 minutes
- ✅ Deployable in 5 minutes
- ✅ Maintainable by junior developers
- ✅ Scalable to 1000+ users
- ✅ Production-ready for MVP

---

## Notes

- No authentication (assume frontend handles auth with Firebase)
- No caching (can add Redis later if needed)
- No rate limiting (can add later)
- Keyword matching is "good enough" for MVP
- Can upgrade to semantic search later without rewriting everything

---

**End of Prompt**

