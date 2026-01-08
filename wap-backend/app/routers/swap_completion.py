"""Swap completion management endpoints."""

from typing import Optional
from datetime import datetime, timedelta
from fastapi import APIRouter, HTTPException, Query

from app.schemas import (
    SwapCompletionCreate,
    SwapCompletionVerify,
    SwapCompletionStatus,
    SwapRequestStatus,
    SwapRequestResponse,
    ParticipantCompletion,
    SkillLevel,
)
from app.firebase_db import get_firebase_service
from app.email_service import get_email_service

router = APIRouter(prefix="/swaps", tags=["swap-completion"])

# Auto-completion window in hours
AUTO_COMPLETE_HOURS = 48


def _convert_timestamps(data: dict) -> dict:
    """Convert Firestore timestamps to datetime objects or ISO strings."""
    timestamp_fields = ["created_at", "updated_at", "responded_at", "auto_complete_at", "completed_at", "marked_at"]
    for field in timestamp_fields:
        if field in data and data[field]:
            if hasattr(data[field], "isoformat"):
                data[field] = data[field].isoformat() if isinstance(data[field], datetime) else data[field]
            elif hasattr(data[field], "__str__"):
                data[field] = str(data[field])
    return data


def _get_completion_status(swap_data: dict) -> SwapCompletionStatus:
    """Build completion status from swap request data."""
    completion = swap_data.get("completion", {})

    requester_data = completion.get("requester", {})
    recipient_data = completion.get("recipient", {})

    requester_completion = ParticipantCompletion(
        marked_complete=requester_data.get("marked_complete", False),
        marked_at=requester_data.get("marked_at"),
        hours_claimed=requester_data.get("hours_claimed"),
        skill_level=requester_data.get("skill_level"),
        notes=requester_data.get("notes"),
    ) if requester_data else None

    recipient_completion = ParticipantCompletion(
        marked_complete=recipient_data.get("marked_complete", False),
        marked_at=recipient_data.get("marked_at"),
        hours_claimed=recipient_data.get("hours_claimed"),
        skill_level=recipient_data.get("skill_level"),
        notes=recipient_data.get("notes"),
    ) if recipient_data else None

    return SwapCompletionStatus(
        swap_request_id=swap_data.get("id"),
        status=SwapRequestStatus(swap_data.get("status", "pending")),
        requester_completion=requester_completion,
        recipient_completion=recipient_completion,
        auto_complete_at=completion.get("auto_complete_at"),
        completed_at=completion.get("completed_at"),
        final_hours=completion.get("final_hours"),
    )


@router.post("/{request_id}/complete", response_model=SwapCompletionStatus)
def mark_swap_complete(
    request_id: str,
    completion: SwapCompletionCreate,
    uid: str = Query(..., description="UID of the user marking complete"),
):
    """
    Mark a swap as complete from your side.

    - First party to mark: Sets status to pending_completion, starts 48hr timer
    - Second party to mark: Finalizes completion, triggers points/credits award

    Only participants in an 'accepted' or 'pending_completion' swap can mark complete.
    """
    firebase = get_firebase_service()
    email_service = get_email_service()
    db = firebase.db

    # Get the swap request
    doc_ref = db.collection("swap_requests").document(request_id)
    doc = doc_ref.get()

    if not doc.exists:
        raise HTTPException(status_code=404, detail="Swap request not found")

    swap_data = doc.to_dict()
    swap_data["id"] = doc.id

    requester_uid = swap_data.get("requester_uid")
    recipient_uid = swap_data.get("recipient_uid")
    current_status = swap_data.get("status")

    # Verify user is a participant
    if uid not in [requester_uid, recipient_uid]:
        raise HTTPException(status_code=403, detail="Only swap participants can mark completion")

    # Verify swap is in valid state for completion
    if current_status not in ["accepted", "pending_completion"]:
        raise HTTPException(
            status_code=400,
            detail=f"Cannot mark completion for swap in '{current_status}' status. Must be 'accepted' or 'pending_completion'."
        )

    # Determine which party is marking complete
    is_requester = uid == requester_uid
    party_key = "requester" if is_requester else "recipient"
    other_party_key = "recipient" if is_requester else "requester"
    other_party_uid = recipient_uid if is_requester else requester_uid

    # Get or initialize completion data
    existing_completion = swap_data.get("completion", {})

    # Check if this user already marked complete
    if existing_completion.get(party_key, {}).get("marked_complete"):
        raise HTTPException(status_code=400, detail="You have already marked this swap as complete")

    now = datetime.utcnow()

    # Update this party's completion
    party_completion = {
        "marked_complete": True,
        "marked_at": now,
        "hours_claimed": completion.hours_exchanged,
        "skill_level": completion.skill_level.value,
        "notes": completion.notes,
    }

    # Check if other party has already marked complete
    other_party_completed = existing_completion.get(other_party_key, {}).get("marked_complete", False)

    if other_party_completed:
        # Both parties have now marked complete - finalize!
        other_hours = existing_completion.get(other_party_key, {}).get("hours_claimed", completion.hours_exchanged)
        final_hours = (completion.hours_exchanged + other_hours) / 2  # Average of both claims

        update_data = {
            "status": "completed",
            f"completion.{party_key}": party_completion,
            "completion.completed_at": now,
            "completion.final_hours": final_hours,
            "updated_at": now,
        }
        new_status = SwapRequestStatus.completed

        # TODO: Trigger points/credits award here
        # This will be implemented in Phase 3 & 4

    else:
        # First party to mark complete - start timer
        auto_complete_at = now + timedelta(hours=AUTO_COMPLETE_HOURS)

        update_data = {
            "status": "pending_completion",
            f"completion.{party_key}": party_completion,
            "completion.auto_complete_at": auto_complete_at,
            "updated_at": now,
        }
        new_status = SwapRequestStatus.pending_completion

        # Send notification to other party
        other_profile = firebase.get_profile(other_party_uid)
        user_profile = firebase.get_profile(uid)

        if other_profile and other_profile.get("email_updates", True):
            email_service.send_completion_pending(
                to_email=other_profile.get("email"),
                user_name=other_profile.get("display_name", "there"),
                partner_name=user_profile.get("display_name", "Your swap partner"),
                hours_claimed=completion.hours_exchanged,
                deadline=auto_complete_at,
            )

    # Perform update
    doc_ref.update(update_data)

    # Get updated data
    updated_doc = doc_ref.get()
    updated_data = updated_doc.to_dict()
    updated_data["id"] = updated_doc.id

    return _get_completion_status(updated_data)


@router.post("/{request_id}/verify", response_model=SwapCompletionStatus)
def verify_completion(
    request_id: str,
    verification: SwapCompletionVerify,
    uid: str = Query(..., description="UID of the user verifying"),
):
    """
    Verify or dispute a pending completion.

    - verify: Confirm the swap is complete (finalizes immediately)
    - dispute: Raise a dispute (sets status to 'disputed', notifies admin)

    Only the party who hasn't marked complete yet can verify/dispute.
    """
    firebase = get_firebase_service()
    email_service = get_email_service()
    db = firebase.db

    # Get the swap request
    doc_ref = db.collection("swap_requests").document(request_id)
    doc = doc_ref.get()

    if not doc.exists:
        raise HTTPException(status_code=404, detail="Swap request not found")

    swap_data = doc.to_dict()
    swap_data["id"] = doc.id

    requester_uid = swap_data.get("requester_uid")
    recipient_uid = swap_data.get("recipient_uid")
    current_status = swap_data.get("status")

    # Verify user is a participant
    if uid not in [requester_uid, recipient_uid]:
        raise HTTPException(status_code=403, detail="Only swap participants can verify completion")

    # Verify swap is pending completion
    if current_status != "pending_completion":
        raise HTTPException(
            status_code=400,
            detail=f"Cannot verify/dispute swap in '{current_status}' status. Must be 'pending_completion'."
        )

    # Determine which party is verifying
    is_requester = uid == requester_uid
    party_key = "requester" if is_requester else "recipient"
    other_party_key = "recipient" if is_requester else "requester"

    completion = swap_data.get("completion", {})

    # The verifying party should NOT have marked complete yet
    # (they're responding to the other party's completion mark)
    if completion.get(party_key, {}).get("marked_complete"):
        raise HTTPException(
            status_code=400,
            detail="You have already marked this swap complete. Use the completion status endpoint to check status."
        )

    # Ensure other party has marked complete
    if not completion.get(other_party_key, {}).get("marked_complete"):
        raise HTTPException(status_code=400, detail="No pending completion to verify")

    now = datetime.utcnow()

    if verification.action == "verify":
        # Finalize the swap
        other_hours = completion.get(other_party_key, {}).get("hours_claimed", 1.0)

        # When verifying, accept the other party's hours claim
        update_data = {
            "status": "completed",
            f"completion.{party_key}.marked_complete": True,
            f"completion.{party_key}.marked_at": now,
            "completion.completed_at": now,
            "completion.final_hours": other_hours,
            "completion.auto_complete_at": None,  # Clear the timer
            "updated_at": now,
        }

        # TODO: Trigger points/credits award here

    else:  # dispute
        if not verification.dispute_reason:
            raise HTTPException(status_code=400, detail="Dispute reason is required")

        update_data = {
            "status": "disputed",
            f"completion.{party_key}.dispute_reason": verification.dispute_reason,
            f"completion.{party_key}.disputed_at": now,
            "completion.auto_complete_at": None,  # Clear the timer
            "updated_at": now,
        }

        # Create a moderation case for the dispute
        db.collection("disputes").add({
            "swap_request_id": request_id,
            "disputer_uid": uid,
            "reason": verification.dispute_reason,
            "status": "pending",
            "created_at": now,
        })

        # Notify the other party
        other_uid = recipient_uid if is_requester else requester_uid
        other_profile = firebase.get_profile(other_uid)

        if other_profile and other_profile.get("email_updates", True):
            email_service.send_completion_disputed(
                to_email=other_profile.get("email"),
                user_name=other_profile.get("display_name", "there"),
                dispute_reason=verification.dispute_reason,
            )

    # Perform update
    doc_ref.update(update_data)

    # Get updated data
    updated_doc = doc_ref.get()
    updated_data = updated_doc.to_dict()
    updated_data["id"] = updated_doc.id

    return _get_completion_status(updated_data)


@router.get("/{request_id}/completion-status", response_model=SwapCompletionStatus)
def get_completion_status(
    request_id: str,
    uid: str = Query(..., description="UID of the requesting user"),
):
    """
    Get the current completion status of a swap.

    Returns completion state for both parties, auto-complete deadline, etc.
    """
    firebase = get_firebase_service()
    db = firebase.db

    # Get the swap request
    doc_ref = db.collection("swap_requests").document(request_id)
    doc = doc_ref.get()

    if not doc.exists:
        raise HTTPException(status_code=404, detail="Swap request not found")

    swap_data = doc.to_dict()
    swap_data["id"] = doc.id

    requester_uid = swap_data.get("requester_uid")
    recipient_uid = swap_data.get("recipient_uid")

    # Verify user is a participant
    if uid not in [requester_uid, recipient_uid]:
        raise HTTPException(status_code=403, detail="Only swap participants can view completion status")

    return _get_completion_status(swap_data)


@router.get("/completed", response_model=list)
def get_completed_swaps(
    uid: str = Query(..., description="UID of the user"),
    limit: int = Query(20, ge=1, le=100),
):
    """
    Get all completed swaps for a user.

    Returns swaps where the user was either requester or recipient
    and status is 'completed'.
    """
    firebase = get_firebase_service()
    db = firebase.db

    # Query swaps where user is requester
    requester_swaps = db.collection("swap_requests").where(
        "requester_uid", "==", uid
    ).where(
        "status", "==", "completed"
    ).order_by("updated_at", direction="DESCENDING").limit(limit).stream()

    # Query swaps where user is recipient
    recipient_swaps = db.collection("swap_requests").where(
        "recipient_uid", "==", uid
    ).where(
        "status", "==", "completed"
    ).order_by("updated_at", direction="DESCENDING").limit(limit).stream()

    # Combine and sort
    all_swaps = []

    for doc in requester_swaps:
        data = doc.to_dict()
        data["id"] = doc.id
        data = _convert_timestamps(data)
        all_swaps.append(data)

    for doc in recipient_swaps:
        data = doc.to_dict()
        data["id"] = doc.id
        data = _convert_timestamps(data)
        all_swaps.append(data)

    # Sort by updated_at descending and limit
    all_swaps.sort(key=lambda x: x.get("updated_at", ""), reverse=True)

    return all_swaps[:limit]
