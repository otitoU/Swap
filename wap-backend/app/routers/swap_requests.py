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
)
from app.firebase_db import get_firebase_service
from app.email_service import get_email_service

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
    """Enrich swap request with participant profiles."""
    request_data = _convert_timestamps(request_data)

    requester_profile = _get_participant_profile(request_data["requester_uid"])
    recipient_profile = _get_participant_profile(request_data["recipient_uid"])

    return SwapRequestResponse(
        **request_data,
        requester_profile=requester_profile,
        recipient_profile=recipient_profile,
    )


@router.post("", response_model=SwapRequestResponse)
def create_swap_request(
    request: SwapRequestCreate,
    requester_uid: str = Query(..., description="UID of the requester"),
):
    """
    Create a new swap request.

    - Creates a pending swap request
    - Sends email notification to recipient if email_updates enabled
    - Returns the created request with participant profiles
    """
    firebase = get_firebase_service()
    email_service = get_email_service()
    db = firebase.db

    # Validate: can't send request to yourself
    if requester_uid == request.recipient_uid:
        raise HTTPException(status_code=400, detail="Cannot send swap request to yourself")

    # Check if blocked
    if not _check_not_blocked(requester_uid, request.recipient_uid):
        raise HTTPException(status_code=403, detail="Cannot send request to this user")

    # Check if recipient exists
    recipient_profile = firebase.get_profile(request.recipient_uid)
    if not recipient_profile:
        raise HTTPException(status_code=404, detail="Recipient not found")

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
        "requester_offer": request.requester_offer,
        "requester_need": request.requester_need,
        "message": request.message,
        "created_at": now,
        "updated_at": now,
        "responded_at": None,
        "conversation_id": None,
    }

    doc_ref = db.collection("swap_requests").document()
    doc_ref.set(request_doc)
    request_doc["id"] = doc_ref.id

    # Send email notification to recipient
    requester_profile = firebase.get_profile(requester_uid)
    if recipient_profile.get("email_updates", True) and recipient_profile.get("email"):
        email_service.send_swap_request_notification(
            to_email=recipient_profile["email"],
            recipient_name=recipient_profile.get("display_name", "there"),
            requester_name=requester_profile.get("display_name", "Someone") if requester_profile else "Someone",
            requester_offers=request.requester_offer,
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

    # Order by created_at descending
    query = query.order_by("created_at", direction="DESCENDING")

    docs = query.stream()
    requests = []
    for doc in docs:
        data = doc.to_dict()
        data["id"] = doc.id
        requests.append(_enrich_swap_request(data))

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

    query = query.order_by("created_at", direction="DESCENDING")

    docs = query.stream()
    requests = []
    for doc in docs:
        data = doc.to_dict()
        data["id"] = doc.id
        requests.append(_enrich_swap_request(data))

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

    if action.action == "accept":
        # Create a conversation
        participant_uids = sorted([request_data["requester_uid"], request_data["recipient_uid"]])

        conversation_doc = {
            "participant_uids": participant_uids,
            "swap_request_id": request_id,
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
            "content": "Swap accepted! You can now start chatting.",
            "sent_at": now,
            "read_at": None,
            "read_by": [],
            "type": "system",
        }
        conv_ref.collection("messages").add(system_message)

        new_status = SwapRequestStatus.accepted.value
    else:
        new_status = SwapRequestStatus.declined.value

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

    return _enrich_swap_request(request_data)


@router.delete("/{request_id}")
def cancel_request(
    request_id: str,
    uid: str = Query(..., description="UID of the user cancelling"),
):
    """
    Cancel a pending swap request.

    Only the requester can cancel their own pending request.
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
