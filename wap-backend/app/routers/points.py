"""Points management endpoints for the swap economy."""

from typing import Optional, List
from datetime import datetime, timedelta
from fastapi import APIRouter, HTTPException, Query
from google.cloud.firestore_v1.base_query import FieldFilter

from app.schemas import (
    PointsBalanceResponse,
    PointsTransaction,
    PointsTransactionType,
    PointsTransactionReason,
    PointsSpendRequest,
    PointsSpendResponse,
    SkillLevel,
)
from app.firebase_db import get_firebase_service

router = APIRouter(prefix="/points", tags=["points"])

# Points costs for spending
PRIORITY_BOOST_COST_PER_HOUR = 5  # 5 points per hour of boost
REQUEST_WITHOUT_RECIPROCITY_COST = 50  # Flat cost to request without offering


def _convert_timestamp(value) -> Optional[str]:
    """Convert Firestore timestamp to ISO string."""
    if value is None:
        return None
    if hasattr(value, "isoformat"):
        return value.isoformat()
    return str(value)


def calculate_points(
    hours: float,
    skill_level: str,
    trust_score: float,
    demand_multiplier: float = 1.0,
) -> int:
    """
    Calculate points earned from a completed swap.

    Weighted formula:
    - Time: 50% (base: 10 points per hour)
    - Skill Level: 25% (beginner=0.5x, intermediate=1x, advanced=1.5x)
    - Trust: 15% (0.5 + trust_score where trust_score is 0-0.5 based on completed swaps)
    - Demand: 10% (demand_multiplier from skill_demand_index, typically 0.5-2.0)

    Args:
        hours: Hours exchanged in the swap
        skill_level: beginner, intermediate, or advanced
        trust_score: User's trust score (0-0.5 based on completed swaps)
        demand_multiplier: How in-demand the skill is (default 1.0)

    Returns:
        Points to award (minimum 1)
    """
    SKILL_MULTIPLIERS = {
        "beginner": 0.5,
        "intermediate": 1.0,
        "advanced": 1.5,
    }

    base_points = hours * 10  # 10 points per hour base

    time_component = base_points * 0.50
    skill_component = base_points * 0.25 * SKILL_MULTIPLIERS.get(skill_level, 1.0)
    trust_component = base_points * 0.15 * (0.5 + trust_score)
    demand_component = base_points * 0.10 * demand_multiplier

    total = time_component + skill_component + trust_component + demand_component

    return max(1, round(total))  # Minimum 1 point


def get_user_trust_score(db, uid: str) -> float:
    """
    Calculate user's trust score based on completed swaps and reviews.

    Trust score ranges from 0 to 0.5:
    - 0 completed swaps: 0
    - 1-5 completed swaps: 0.1-0.25
    - 5-20 completed swaps: 0.25-0.4
    - 20+ completed swaps: 0.4-0.5

    Also factors in average rating.
    """
    profile_ref = db.collection("profiles").document(uid)
    profile_doc = profile_ref.get()

    if not profile_doc.exists:
        return 0.0

    profile = profile_doc.to_dict()
    completed_swaps = profile.get("completed_swap_count", 0)
    avg_rating = profile.get("average_rating", 3.0)

    # Base trust from completed swaps (0 to 0.35)
    if completed_swaps == 0:
        swap_trust = 0.0
    elif completed_swaps <= 5:
        swap_trust = 0.1 + (completed_swaps / 5) * 0.15
    elif completed_swaps <= 20:
        swap_trust = 0.25 + ((completed_swaps - 5) / 15) * 0.10
    else:
        swap_trust = 0.35

    # Rating bonus (0 to 0.15)
    rating_bonus = ((avg_rating - 1) / 4) * 0.15  # 1 star = 0, 5 stars = 0.15

    return min(0.5, swap_trust + rating_bonus)


def get_skill_demand_multiplier(db, skill: Optional[str]) -> float:
    """
    Get demand multiplier for a skill from the skill_demand_index.

    Returns 1.0 if skill not found or index doesn't exist.
    """
    if not skill:
        return 1.0

    # Try to find in skill_demand_index
    # For now, return default since we haven't populated this collection
    # TODO: Implement skill demand index calculation job
    return 1.0


def award_points_for_swap(
    db,
    uid: str,
    swap_id: str,
    hours: float,
    skill_level: str,
    skill: Optional[str] = None,
) -> int:
    """
    Award points to a user for completing a swap.

    Creates a points_transactions record and updates profile balance.

    Returns:
        Points awarded
    """
    trust_score = get_user_trust_score(db, uid)
    demand_mult = get_skill_demand_multiplier(db, skill)

    points = calculate_points(hours, skill_level, trust_score, demand_mult)

    # Get current balance
    profile_ref = db.collection("profiles").document(uid)
    profile_doc = profile_ref.get()

    current_balance = 0
    lifetime_earned = 0

    if profile_doc.exists:
        profile = profile_doc.to_dict()
        current_balance = profile.get("swap_points", 0)
        lifetime_earned = profile.get("lifetime_points_earned", 0)

    new_balance = current_balance + points

    # Create transaction record
    now = datetime.utcnow()
    transaction_data = {
        "uid": uid,
        "type": "earned",
        "amount": points,
        "balance_after": new_balance,
        "reason": "swap_completed",
        "related_swap_id": swap_id,
        "related_skill": skill,
        "created_at": now,
    }

    db.collection("points_transactions").add(transaction_data)

    # Update profile balance
    profile_ref.update({
        "swap_points": new_balance,
        "lifetime_points_earned": lifetime_earned + points,
        "updated_at": now,
    })

    return points


@router.get("/balance/{uid}", response_model=PointsBalanceResponse)
def get_points_balance(
    uid: str,
    include_transactions: bool = Query(True, description="Include recent transactions"),
    transaction_limit: int = Query(10, ge=1, le=50),
):
    """
    Get a user's current points balance and recent transactions.
    """
    firebase = get_firebase_service()
    db = firebase.db

    # Get profile for balance
    profile_ref = db.collection("profiles").document(uid)
    profile_doc = profile_ref.get()

    if not profile_doc.exists:
        raise HTTPException(status_code=404, detail="User not found")

    profile = profile_doc.to_dict()
    swap_points = profile.get("swap_points", 0)
    lifetime_earned = profile.get("lifetime_points_earned", 0)

    recent_transactions = []

    if include_transactions:
        # Get recent transactions
        transactions_query = db.collection("points_transactions").where(
            filter=FieldFilter("uid", "==", uid)
        ).order_by("created_at", direction="DESCENDING").limit(transaction_limit)

        for doc in transactions_query.stream():
            data = doc.to_dict()
            recent_transactions.append(PointsTransaction(
                id=doc.id,
                uid=data.get("uid"),
                type=PointsTransactionType(data.get("type")),
                amount=data.get("amount"),
                balance_after=data.get("balance_after"),
                reason=PointsTransactionReason(data.get("reason")),
                related_swap_id=data.get("related_swap_id"),
                related_skill=data.get("related_skill"),
                created_at=_convert_timestamp(data.get("created_at")) or datetime.utcnow().isoformat(),
            ))

    return PointsBalanceResponse(
        uid=uid,
        swap_points=swap_points,
        lifetime_points_earned=lifetime_earned,
        recent_transactions=recent_transactions,
    )


@router.get("/transactions/{uid}")
def get_points_history(
    uid: str,
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
    type_filter: Optional[str] = Query(None, description="Filter by transaction type: earned or spent"),
):
    """
    Get full points transaction history for a user.
    """
    firebase = get_firebase_service()
    db = firebase.db

    # Build query
    query = db.collection("points_transactions").where(
        filter=FieldFilter("uid", "==", uid)
    )

    if type_filter:
        query = query.where(filter=FieldFilter("type", "==", type_filter))

    query = query.order_by("created_at", direction="DESCENDING")

    # Get all for count (pagination)
    all_docs = list(query.stream())
    total = len(all_docs)

    # Apply pagination
    paginated_docs = all_docs[offset:offset + limit]

    transactions = []
    for doc in paginated_docs:
        data = doc.to_dict()
        transactions.append({
            "id": doc.id,
            "uid": data.get("uid"),
            "type": data.get("type"),
            "amount": data.get("amount"),
            "balance_after": data.get("balance_after"),
            "reason": data.get("reason"),
            "related_swap_id": data.get("related_swap_id"),
            "related_skill": data.get("related_skill"),
            "created_at": _convert_timestamp(data.get("created_at")),
        })

    return {
        "transactions": transactions,
        "total": total,
        "limit": limit,
        "offset": offset,
        "has_more": offset + limit < total,
    }


@router.post("/spend", response_model=PointsSpendResponse)
def spend_points(
    request: PointsSpendRequest,
    uid: str = Query(..., description="UID of the user spending points"),
):
    """
    Spend points on platform features.

    Available options:
    - priority_boost: Boost visibility in search results (5 points/hour, max 168 hours)
    - request_without_reciprocity: Request help without offering a skill (50 points)
    """
    firebase = get_firebase_service()
    db = firebase.db

    # Get current balance
    profile_ref = db.collection("profiles").document(uid)
    profile_doc = profile_ref.get()

    if not profile_doc.exists:
        raise HTTPException(status_code=404, detail="User not found")

    profile = profile_doc.to_dict()
    current_balance = profile.get("swap_points", 0)

    # Calculate cost
    if request.reason == "priority_boost":
        cost = PRIORITY_BOOST_COST_PER_HOUR * (request.duration_hours or 24)
    else:  # request_without_reciprocity
        cost = REQUEST_WITHOUT_RECIPROCITY_COST

    # Check balance
    if current_balance < cost:
        raise HTTPException(
            status_code=400,
            detail=f"Insufficient points. Need {cost}, have {current_balance}."
        )

    now = datetime.utcnow()
    new_balance = current_balance - cost

    # Create transaction record
    transaction_data = {
        "uid": uid,
        "type": "spent",
        "amount": cost,
        "balance_after": new_balance,
        "reason": request.reason,
        "created_at": now,
    }

    doc_ref = db.collection("points_transactions").add(transaction_data)

    # Update profile balance
    profile_ref.update({
        "swap_points": new_balance,
        "updated_at": now,
    })

    # If priority boost, create active boost record
    if request.reason == "priority_boost":
        boost_end = now + timedelta(hours=request.duration_hours or 24)
        db.collection("active_boosts").add({
            "uid": uid,
            "type": "priority",
            "started_at": now,
            "ends_at": boost_end,
            "points_spent": cost,
        })
        message = f"Priority boost activated for {request.duration_hours} hours!"
    else:
        message = "You can now request help without offering a skill in return."

    return PointsSpendResponse(
        success=True,
        new_balance=new_balance,
        transaction_id=doc_ref[1].id,
        message=message,
    )


@router.get("/active-boosts/{uid}")
def get_active_boosts(uid: str):
    """
    Get active priority boosts for a user.
    """
    firebase = get_firebase_service()
    db = firebase.db

    now = datetime.utcnow()

    # Query active boosts (ends_at > now)
    boosts_query = db.collection("active_boosts").where(
        filter=FieldFilter("uid", "==", uid)
    ).stream()

    active_boosts = []
    for doc in boosts_query:
        data = doc.to_dict()
        ends_at = data.get("ends_at")

        # Check if still active
        if ends_at:
            if hasattr(ends_at, "timestamp"):
                ends_at_dt = datetime.fromtimestamp(ends_at.timestamp())
            else:
                ends_at_dt = ends_at

            if ends_at_dt > now:
                active_boosts.append({
                    "id": doc.id,
                    "type": data.get("type"),
                    "started_at": _convert_timestamp(data.get("started_at")),
                    "ends_at": _convert_timestamp(ends_at),
                    "remaining_hours": round((ends_at_dt - now).total_seconds() / 3600, 1),
                })

    return {
        "uid": uid,
        "active_boosts": active_boosts,
        "has_active_boost": len(active_boosts) > 0,
    }
