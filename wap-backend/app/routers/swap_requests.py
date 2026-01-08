"""Swap request management endpoints."""

from typing import Optional, List
from datetime import datetime
from fastapi import APIRouter, HTTPException, Query
from google.cloud.firestore_v1.base_query import FieldFilter

from app.schemas import (
    SwapRequestCreate,
    SwapRequestResponse,
    SwapRequestAction,
    SwapRequestStatus,
    SwapParticipant,
    ConversationStatus,
    SwapType,
    PointsTransactionReason,
)
from app.firebase_db import get_firebase_service
from app.email_service import get_email_service

# Constants for indirect swap pricing
POINTS_PER_HOUR_INDIRECT = 10  # Points cost per hour for indirect swaps

router = APIRouter(prefix="/swap-requests", tags=["swap-requests"])


def _get_participant_profile(uid: str) -> Optional[SwapParticipant]:
    """Get minimal profile info for a swap participant."""
    firebase = get_firebase_service()
    profile = firebase.get_profile(uid)
    if not profile:
        return None
    return SwapParticipant(
        uid=profile.get("uid", uid),
        display_name=profile.get("display_name"),
        photo_url=profile.get("photo_url"),
        email=profile.get("email"),
        skills_to_offer=profile.get("skills_to_offer"),
        services_needed=profile.get("services_needed"),
    )


def _update_response_rate(db, uid: str):
    """
    Update a user's response rate based on their swap request history.
    Response rate = (accepted + declined) / total received * 100
    """
    # Count all requests received by this user
    all_requests = list(db.collection("swap_requests").where(
        filter=FieldFilter("recipient_uid", "==", uid)
    ).stream())
    
    total_received = len(all_requests)
    
    if total_received == 0:
        return
    
    # Count requests that have been responded to (accepted or declined)
    responded_count = sum(
        1 for req in all_requests 
        if req.to_dict().get("status") in [
            SwapRequestStatus.accepted.value, 
            SwapRequestStatus.declined.value,
            SwapRequestStatus.completed.value
        ]
    )
    
    response_rate = round((responded_count / total_received) * 100, 1)
    
    profile_ref = db.collection("profiles").document(uid)
    profile_ref.update({
        "responseRate": response_rate,
        "total_requests_received": total_received,
        "total_requests_responded": responded_count,
        "updated_at": datetime.utcnow(),
    })


def _check_not_blocked(uid1: str, uid2: str) -> bool:
    """Check if either user has blocked the other."""
    firebase = get_firebase_service()
    db = firebase.db

    # Check both directions
    blocks1 = list(db.collection("blocks").where(
        filter=FieldFilter("blocker_uid", "==", uid1)
    ).where(
        filter=FieldFilter("blocked_uid", "==", uid2)
    ).limit(1).stream())

    if blocks1:
        return False

    blocks2 = list(db.collection("blocks").where(
        filter=FieldFilter("blocker_uid", "==", uid2)
    ).where(
        filter=FieldFilter("blocked_uid", "==", uid1)
    ).limit(1).stream())

    return len(blocks2) == 0


def _convert_timestamps(data: dict) -> dict:
    """Convert Firestore timestamps to ISO strings."""
    for field in ["created_at", "updated_at", "responded_at"]:
        if field in data and data[field]:
            if hasattr(data[field], "isoformat"):
                data[field] = data[field].isoformat()
            elif hasattr(data[field], "__str__"):
                data[field] = str(data[field])
    return data


def _enrich_swap_request(request_data: dict) -> SwapRequestResponse:
    """Enrich swap request with participant profiles and formatted completion data."""
    request_data = _convert_timestamps(request_data)

    requester_profile = _get_participant_profile(request_data["requester_uid"])
    recipient_profile = _get_participant_profile(request_data["recipient_uid"])

    # Format completion data for frontend consumption
    completion_data = None
    if "completion" in request_data and request_data["completion"]:
        raw_completion = request_data["completion"]
        completion_data = {
            "requester": raw_completion.get("requester"),
            "recipient": raw_completion.get("recipient"),
            "auto_complete_at": raw_completion.get("auto_complete_at"),
            "completed_at": raw_completion.get("completed_at"),
            "final_hours": raw_completion.get("final_hours"),
            "requester_points_earned": raw_completion.get("requester_points_earned"),
            "requester_credits_earned": raw_completion.get("requester_credits_earned"),
            "recipient_points_earned": raw_completion.get("recipient_points_earned"),
            "recipient_credits_earned": raw_completion.get("recipient_credits_earned"),
        }
        # Remove completion from request_data to avoid duplicate
        del request_data["completion"]

    return SwapRequestResponse(
        **request_data,
        requester_profile=requester_profile,
        recipient_profile=recipient_profile,
        completion=completion_data,
    )


def _reserve_points(db, uid: str, amount: int, swap_id: str) -> bool:
    """Reserve points for an indirect swap. Returns True if successful."""
    profile_ref = db.collection("profiles").document(uid)
    profile_doc = profile_ref.get()
    
    if not profile_doc.exists:
        return False
    
    profile = profile_doc.to_dict()
    current_balance = profile.get("swap_points", 0)
    
    if current_balance < amount:
        return False
    
    # Deduct points and record transaction
    new_balance = current_balance - amount
    now = datetime.utcnow()
    
    # Create reservation transaction
    db.collection("points_transactions").add({
        "uid": uid,
        "type": "spent",
        "amount": amount,
        "balance_after": new_balance,
        "reason": PointsTransactionReason.indirect_swap_reserved.value,
        "related_swap_id": swap_id,
        "created_at": now,
    })
    
    # Update profile balance
    profile_ref.update({
        "swap_points": new_balance,
        "updated_at": now,
    })
    
    return True


def _refund_reserved_points(db, uid: str, amount: int, swap_id: str):
    """Refund reserved points when a swap is declined or cancelled."""
    profile_ref = db.collection("profiles").document(uid)
    profile_doc = profile_ref.get()
    
    if not profile_doc.exists:
        return
    
    profile = profile_doc.to_dict()
    current_balance = profile.get("swap_points", 0)
    new_balance = current_balance + amount
    now = datetime.utcnow()
    
    # Create refund transaction
    db.collection("points_transactions").add({
        "uid": uid,
        "type": "earned",
        "amount": amount,
        "balance_after": new_balance,
        "reason": PointsTransactionReason.indirect_swap_refund.value,
        "related_swap_id": swap_id,
        "created_at": now,
    })
    
    # Update profile balance
    profile_ref.update({
        "swap_points": new_balance,
        "updated_at": now,
    })


@router.post("", response_model=SwapRequestResponse)
def create_swap_request(
    request: SwapRequestCreate,
    requester_uid: str = Query(..., description="UID of the requester"),
):
    """
    Create a new swap request.

    Supports two swap types:
    - direct: Both users exchange skills (requester_offer required)
    - indirect: Requester pays points for the service (points_offered required)

    - Creates a pending swap request
    - For indirect swaps: reserves points from requester's balance
    - Sends email notification to recipient if email_updates enabled
    - Returns the created request with participant profiles
    """
    firebase = get_firebase_service()
    email_service = get_email_service()
    db = firebase.db

    # Validate: can't send request to yourself
    if requester_uid == request.recipient_uid:
        raise HTTPException(status_code=400, detail="Cannot send swap request to yourself")

    # Validate swap type requirements
    is_indirect = request.swap_type == SwapType.indirect
    
    if is_indirect:
        if not request.points_offered or request.points_offered < 1:
            raise HTTPException(
                status_code=400, 
                detail="Points offered is required for indirect swaps"
            )
    else:
        # Direct swap requires requester_offer
        if not request.requester_offer:
            raise HTTPException(
                status_code=400, 
                detail="Skill offer is required for direct swaps"
            )

    # Check if blocked
    if not _check_not_blocked(requester_uid, request.recipient_uid):
        raise HTTPException(status_code=403, detail="Cannot send request to this user")

    # Check if recipient exists
    recipient_profile = firebase.get_profile(request.recipient_uid)
    if not recipient_profile:
        raise HTTPException(status_code=404, detail="Recipient not found")

    # For indirect swaps, check if requester has enough points
    points_reserved = None
    if is_indirect:
        requester_profile_data = firebase.get_profile(requester_uid)
        if not requester_profile_data:
            raise HTTPException(status_code=404, detail="Requester profile not found")
        
        current_points = requester_profile_data.get("swap_points", 0)
        if current_points < request.points_offered:
            raise HTTPException(
                status_code=400, 
                detail=f"Insufficient points. You have {current_points}, need {request.points_offered}"
            )
        points_reserved = request.points_offered

    # Check for existing pending request between these users
    existing = list(db.collection("swap_requests").where(
        filter=FieldFilter("requester_uid", "==", requester_uid)
    ).where(
        filter=FieldFilter("recipient_uid", "==", request.recipient_uid)
    ).where(
        filter=FieldFilter("status", "==", SwapRequestStatus.pending.value)
    ).limit(1).stream())

    if existing:
        raise HTTPException(status_code=400, detail="You already have a pending request to this user")

    # Create the swap request
    now = datetime.utcnow()
    request_doc = {
        "requester_uid": requester_uid,
        "recipient_uid": request.recipient_uid,
        "status": SwapRequestStatus.pending.value,
        "swap_type": request.swap_type.value,
        "requester_offer": request.requester_offer,
        "requester_need": request.requester_need,
        "points_offered": request.points_offered if is_indirect else None,
        "points_reserved": None,  # Will be set after successful reservation
        "message": request.message,
        "created_at": now,
        "updated_at": now,
        "responded_at": None,
        "conversation_id": None,
    }

    doc_ref = db.collection("swap_requests").document()
    doc_ref.set(request_doc)
    request_doc["id"] = doc_ref.id

    # For indirect swaps, reserve points now that we have the swap ID
    if is_indirect and points_reserved:
        if not _reserve_points(db, requester_uid, points_reserved, doc_ref.id):
            # Rollback: delete the swap request
            doc_ref.delete()
            raise HTTPException(
                status_code=400, 
                detail="Failed to reserve points. Please try again."
            )
        # Update the request with reserved points
        doc_ref.update({"points_reserved": points_reserved})
        request_doc["points_reserved"] = points_reserved

    # Send email notification to recipient
    requester_profile = firebase.get_profile(requester_uid)
    if recipient_profile.get("email_updates", True) and recipient_profile.get("email"):
        swap_type_text = "points-based" if is_indirect else "skill exchange"
        email_service.send_swap_request_notification(
            to_email=recipient_profile["email"],
            recipient_name=recipient_profile.get("display_name", "there"),
            requester_name=requester_profile.get("display_name", "Someone") if requester_profile else "Someone",
            requester_offers=request.requester_offer if not is_indirect else f"{points_reserved} points",
            requester_needs=request.requester_need,
            message=request.message,
            request_id=doc_ref.id,
        )

    return _enrich_swap_request(request_doc)


@router.get("/incoming", response_model=List[SwapRequestResponse])
def get_incoming_requests(
    uid: str = Query(..., description="UID of the user"),
    status: Optional[SwapRequestStatus] = Query(None, description="Filter by status"),
):
    """Get swap requests sent TO the user (they are the recipient)."""
    firebase = get_firebase_service()
    db = firebase.db

    query = db.collection("swap_requests").where(
        filter=FieldFilter("recipient_uid", "==", uid)
    )

    if status:
        query = query.where(filter=FieldFilter("status", "==", status.value))

    # Fetch all matching documents
    docs = query.stream()
    requests = []
    for doc in docs:
        data = doc.to_dict()
        data["id"] = doc.id
        requests.append(_enrich_swap_request(data))

    # Sort by created_at descending in Python (avoids requiring composite index)
    requests.sort(key=lambda x: x.created_at, reverse=True)

    return requests


@router.get("/outgoing", response_model=List[SwapRequestResponse])
def get_outgoing_requests(
    uid: str = Query(..., description="UID of the user"),
    status: Optional[SwapRequestStatus] = Query(None, description="Filter by status"),
):
    """Get swap requests sent BY the user (they are the requester)."""
    firebase = get_firebase_service()
    db = firebase.db

    query = db.collection("swap_requests").where(
        filter=FieldFilter("requester_uid", "==", uid)
    )

    if status:
        query = query.where(filter=FieldFilter("status", "==", status.value))

    # Fetch all matching documents
    docs = query.stream()
    requests = []
    for doc in docs:
        data = doc.to_dict()
        data["id"] = doc.id
        requests.append(_enrich_swap_request(data))

    # Sort by created_at descending in Python (avoids requiring composite index)
    requests.sort(key=lambda x: x.created_at, reverse=True)

    return requests


@router.post("/{request_id}/respond", response_model=SwapRequestResponse)
def respond_to_request(
    request_id: str,
    action: SwapRequestAction,
    uid: str = Query(..., description="UID of the responding user"),
):
    """
    Accept or decline a swap request.

    - Only the recipient can respond
    - If accepted: creates a conversation and updates the request
    - If declined and indirect swap: refunds reserved points to requester
    - Sends email notification to the requester about the decision
    """
    firebase = get_firebase_service()
    email_service = get_email_service()
    db = firebase.db

    # Get the request
    doc_ref = db.collection("swap_requests").document(request_id)
    doc = doc_ref.get()

    if not doc.exists:
        raise HTTPException(status_code=404, detail="Swap request not found")

    request_data = doc.to_dict()
    request_data["id"] = doc.id

    # Validate: only recipient can respond
    if request_data["recipient_uid"] != uid:
        raise HTTPException(status_code=403, detail="Only the recipient can respond to this request")

    # Validate: can only respond to pending requests
    if request_data["status"] != SwapRequestStatus.pending.value:
        raise HTTPException(status_code=400, detail="This request has already been responded to")

    now = datetime.utcnow()
    conversation_id = None
    is_indirect = request_data.get("swap_type") == SwapType.indirect.value

    if action.action == "accept":
        # Create a conversation
        participant_uids = sorted([request_data["requester_uid"], request_data["recipient_uid"]])

        # Create appropriate system message based on swap type
        if is_indirect:
            points_amount = request_data.get("points_reserved", 0)
            system_content = f"Swap accepted! This is a points-based swap ({points_amount} points). You can now start chatting and coordinate your skill exchange."
        else:
            system_content = "Swap accepted! You can now start chatting and coordinate your skill exchange."

        conversation_doc = {
            "participant_uids": participant_uids,
            "swap_request_id": request_id,
            "swap_type": request_data.get("swap_type", SwapType.direct.value),
            "created_at": now,
            "updated_at": now,
            "last_message": None,
            "unread_counts": {
                request_data["requester_uid"]: 0,
                request_data["recipient_uid"]: 0,
            },
            "status": ConversationStatus.active.value,
        }

        conv_ref = db.collection("conversations").document()
        conv_ref.set(conversation_doc)
        conversation_id = conv_ref.id

        # Add a system message
        system_message = {
            "sender_uid": "system",
            "content": system_content,
            "sent_at": now,
            "read_at": None,
            "read_by": [],
            "type": "system",
        }
        conv_ref.collection("messages").add(system_message)

        new_status = SwapRequestStatus.accepted.value
    else:
        # Declined - refund points for indirect swaps
        new_status = SwapRequestStatus.declined.value
        
        if is_indirect:
            points_reserved = request_data.get("points_reserved", 0)
            if points_reserved > 0:
                _refund_reserved_points(
                    db, 
                    request_data["requester_uid"], 
                    points_reserved, 
                    request_id
                )

    # Update the request
    update_data = {
        "status": new_status,
        "updated_at": now,
        "responded_at": now,
        "conversation_id": conversation_id,
    }
    doc_ref.update(update_data)
    request_data.update(update_data)

    # Send email notification to requester
    requester_profile = firebase.get_profile(request_data["requester_uid"])
    recipient_profile = firebase.get_profile(uid)

    if requester_profile and requester_profile.get("email_updates", True) and requester_profile.get("email"):
        email_service.send_swap_response_notification(
            to_email=requester_profile["email"],
            requester_name=requester_profile.get("display_name", "there"),
            recipient_name=recipient_profile.get("display_name", "Someone") if recipient_profile else "Someone",
            accepted=(action.action == "accept"),
            conversation_id=conversation_id,
        )

    # Update recipient's response rate
    _update_response_rate(db, uid)

    return _enrich_swap_request(request_data)


@router.delete("/{request_id}")
def cancel_request(
    request_id: str,
    uid: str = Query(..., description="UID of the user cancelling"),
):
    """
    Cancel a pending swap request.

    Only the requester can cancel their own pending request.
    For indirect swaps, refunds the reserved points.
    """
    firebase = get_firebase_service()
    db = firebase.db

    # Get the request
    doc_ref = db.collection("swap_requests").document(request_id)
    doc = doc_ref.get()

    if not doc.exists:
        raise HTTPException(status_code=404, detail="Swap request not found")

    request_data = doc.to_dict()

    # Validate: only requester can cancel
    if request_data["requester_uid"] != uid:
        raise HTTPException(status_code=403, detail="Only the requester can cancel this request")

    # Validate: can only cancel pending requests
    if request_data["status"] != SwapRequestStatus.pending.value:
        raise HTTPException(status_code=400, detail="Can only cancel pending requests")

    # Refund points for indirect swaps
    is_indirect = request_data.get("swap_type") == SwapType.indirect.value
    if is_indirect:
        points_reserved = request_data.get("points_reserved", 0)
        if points_reserved > 0:
            _refund_reserved_points(db, uid, points_reserved, request_id)

    # Update status to cancelled
    now = datetime.utcnow()
    doc_ref.update({
        "status": SwapRequestStatus.cancelled.value,
        "updated_at": now,
    })

    return {"message": "Swap request cancelled", "id": request_id}


@router.get("/{request_id}", response_model=SwapRequestResponse)
def get_swap_request(
    request_id: str,
    uid: str = Query(..., description="UID of the requesting user"),
):
    """Get a specific swap request by ID."""
    firebase = get_firebase_service()
    db = firebase.db

    doc_ref = db.collection("swap_requests").document(request_id)
    doc = doc_ref.get()

    if not doc.exists:
        raise HTTPException(status_code=404, detail="Swap request not found")

    request_data = doc.to_dict()
    request_data["id"] = doc.id

    # Validate: only participants can view
    if uid not in [request_data["requester_uid"], request_data["recipient_uid"]]:
        raise HTTPException(status_code=403, detail="Not authorized to view this request")

    return _enrich_swap_request(request_data)
