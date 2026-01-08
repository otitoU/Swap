#!/usr/bin/env python3
"""Script to reindex all profiles from Firestore to Azure AI Search."""

import sys
from pathlib import Path

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from app.firebase_db import get_firebase_service
from app.embeddings import get_embedding_service
from app.azure_search import get_azure_search_service


def skills_to_text(skills):
    """Convert skills array or string to text for embeddings."""
    if not skills:
        return None
    if isinstance(skills, str):
        return skills
    if isinstance(skills, list):
        # Convert array of objects like [{name, category, level}, ...] to text
        parts = []
        for s in skills:
            if isinstance(s, dict):
                name = s.get('name', '')
                level = s.get('level', '')
                if name:
                    parts.append(f"{name} ({level})" if level else name)
            elif isinstance(s, str):
                parts.append(s)
        return ', '.join(parts) if parts else None
    return None


def reindex_all_profiles():
    """Reindex all profiles from Firestore to Azure AI Search."""
    firebase_service = get_firebase_service()
    embedding_service = get_embedding_service()
    azure_search_service = get_azure_search_service()

    profiles = firebase_service.list_profiles(limit=10000)
    print(f"Found {len(profiles)} profiles to reindex")

    if not profiles:
        print("No profiles found in Firestore")
        return

    for i, profile in enumerate(profiles, 1):
        uid = profile.get('uid')
        print(f"[{i}/{len(profiles)}] Indexing {uid}...")

        try:
            # Handle both camelCase (frontend) and snake_case (backend) field names
            skills_to_offer = skills_to_text(
                profile.get('skills_to_offer') or profile.get('skillsToOffer')
            )
            services_needed = skills_to_text(
                profile.get('services_needed') or profile.get('servicesNeeded')
            )
            
            if not skills_to_offer or not services_needed:
                print(f"  ⊘ Skipped {uid} (no skills defined)")
                continue
            
            # Generate embeddings
            offer_vec = embedding_service.encode(skills_to_offer)
            need_vec = embedding_service.encode(services_needed)
            
            # Prepare payload (handle both camelCase and snake_case)
            payload = {
                "uid": uid,
                "email": profile.get('email'),
                "display_name": profile.get('display_name') or profile.get('displayName') or profile.get('fullName'),
                "photo_url": profile.get('photo_url') or profile.get('photoUrl'),
                "full_name": profile.get('full_name') or profile.get('fullName'),
                "username": profile.get('username'),
                "bio": profile.get('bio'),
                "city": profile.get('city'),
                "timezone": profile.get('timezone'),
                "skills_to_offer": skills_to_offer,
                "services_needed": services_needed,
                "dm_open": profile.get('dm_open', profile.get('dmOpen', True)),
                "show_city": profile.get('show_city', profile.get('showCity', True)),
            }
            
            # Upsert to Azure AI Search
            azure_search_service.upsert_profile(
                username=uid,
                offer_vec=offer_vec,
                need_vec=need_vec,
                payload=payload,
            )
            print(f"  ✓ Indexed {uid}")
            
        except Exception as e:
            print(f"  ✗ Error indexing {uid}: {e}")
            continue
    
    print("\n✓ Reindexing complete!")


if __name__ == "__main__":
    reindex_all_profiles()

