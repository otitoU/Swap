"""Moderation endpoints for blocking and reporting users."""

from typing import List
from datetime import datetime
from fastapi import APIRouter, HTTPException, Query
from google.cloud.firestore_v1.base_query import FieldFilter

from app.schemas import (
    BlockCreate,
    BlockResponse,
    ReportCreate,
    ReportResponse,
    ConversationStatus,
)
from app.firebase_db import get_firebase_service

router = APIRouter(prefix="/moderation", tags=["moderation"])


def _convert_timestamp(value) -> str:
    """Convert a Firestore timestamp to ISO string."""
    if value is None:
        return datetime.utcnow().isoformat()
    if hasattr(value, "isoformat"):
        return value.isoformat()
    return str(value)


@router.post("/block", response_model=BlockResponse)
def block_user(
    block: BlockCreate,
    uid: str = Query(..., description="UID of the user doing the blocking"),
):
    """
    Block another user.

    Effects:
    1. Creates block record
    2. Updates any shared conversation status to 'blocked'
    3. Prevents future swap requests between users
    4. Prevents messaging
    """
    firebase = get_firebase_service()
    db = firebase.db

    # Validate: can't block yourself
    if uid == block.blocked_uid:
        raise HTTPException(status_code=400, detail="Cannot block yourself")

    # Check if already blocked
    existing = list(db.collection("blocks").where(
        filter=FieldFilter("blocker_uid", "==", uid)
    ).where(
        filter=FieldFilter("blocked_uid", "==", block.blocked_uid)
    ).limit(1).stream())

    if existing:
        raise HTTPException(status_code=400, detail="User is already blocked")

    now = datetime.utcnow()

    # Create block record
    block_doc = {
        "blocker_uid": uid,
        "blocked_uid": block.blocked_uid,
        "created_at": now,
        "reason": block.reason,
    }

    doc_ref = db.collection("blocks").document()
    doc_ref.set(block_doc)

    # Update any shared conversations to blocked status
    conversations = db.collection("conversations").where(
        filter=FieldFilter("participant_uids", "array_contains", uid)
    ).stream()

    for conv_doc in conversations:
        conv_data = conv_doc.to_dict()
        if block.blocked_uid in conv_data.get("participant_uids", []):
            conv_doc.reference.update({
                "status": ConversationStatus.blocked.value,
                "updated_at": now,
            })

    return BlockResponse(
        id=doc_ref.id,
        blocker_uid=uid,
        blocked_uid=block.blocked_uid,
        created_at=now.isoformat(),
        reason=block.reason,
    )


@router.delete("/block/{blocked_uid}")
def unblock_user(
    blocked_uid: str,
    uid: str = Query(..., description="UID of the user doing the unblocking"),
):
    """
    Unblock a previously blocked user.

    Effects:
    1. Removes block record
    2. Restores conversation status to 'active'
    """
    firebase = get_firebase_service()
    db = firebase.db

    # Find the block record
    blocks = list(db.collection("blocks").where(
        filter=FieldFilter("blocker_uid", "==", uid)
    ).where(
        filter=FieldFilter("blocked_uid", "==", blocked_uid)
    ).limit(1).stream())

    if not blocks:
        raise HTTPException(status_code=404, detail="Block not found")

    # Delete the block
    blocks[0].reference.delete()

    now = datetime.utcnow()

    # Check if the other user also has a block
    reverse_block = list(db.collection("blocks").where(
        filter=FieldFilter("blocker_uid", "==", blocked_uid)
    ).where(
        filter=FieldFilter("blocked_uid", "==", uid)
    ).limit(1).stream())

    # Only restore conversation if neither user is blocking the other
    if not reverse_block:
        conversations = db.collection("conversations").where(
            filter=FieldFilter("participant_uids", "array_contains", uid)
        ).stream()

        for conv_doc in conversations:
            conv_data = conv_doc.to_dict()
            if blocked_uid in conv_data.get("participant_uids", []):
                if conv_data.get("status") == ConversationStatus.blocked.value:
                    conv_doc.reference.update({
                        "status": ConversationStatus.active.value,
                        "updated_at": now,
                    })

    return {"message": "User unblocked", "blocked_uid": blocked_uid}


@router.get("/blocked", response_model=List[BlockResponse])
def list_blocked_users(
    uid: str = Query(..., description="UID of the user"),
):
    """List all users blocked by this user."""
    firebase = get_firebase_service()
    db = firebase.db

    blocks = db.collection("blocks").where(
        filter=FieldFilter("blocker_uid", "==", uid)
    ).order_by("created_at", direction="DESCENDING").stream()

    result = []
    for doc in blocks:
        data = doc.to_dict()
        result.append(BlockResponse(
            id=doc.id,
            blocker_uid=data.get("blocker_uid"),
            blocked_uid=data.get("blocked_uid"),
            created_at=_convert_timestamp(data.get("created_at")),
            reason=data.get("reason"),
        ))

    return result


@router.post("/report", response_model=ReportResponse)
def report_user(
    report: ReportCreate,
    uid: str = Query(..., description="UID of the reporter"),
):
    """
    Report a user for policy violation.

    - Creates report for admin review
    - Optionally includes message context
    """
    firebase = get_firebase_service()
    db = firebase.db

    # Validate: can't report yourself
    if uid == report.reported_uid:
        raise HTTPException(status_code=400, detail="Cannot report yourself")

    now = datetime.utcnow()

    # Create report
    report_doc = {
        "reporter_uid": uid,
        "reported_uid": report.reported_uid,
        "conversation_id": report.conversation_id,
        "message_id": report.message_id,
        "reason": report.reason.value,
        "details": report.details,
        "status": "pending",
        "created_at": now,
        "reviewed_at": None,
        "reviewed_by": None,
        "resolution_notes": None,
    }

    doc_ref = db.collection("reports").document()
    doc_ref.set(report_doc)

    return ReportResponse(
        id=doc_ref.id,
        status="pending",
        message="Report submitted. We'll review it within 24-48 hours.",
    )


@router.get("/reports")
def list_my_reports(
    uid: str = Query(..., description="UID of the user"),
):
    """List reports submitted by this user."""
    firebase = get_firebase_service()
    db = firebase.db

    reports = db.collection("reports").where(
        filter=FieldFilter("reporter_uid", "==", uid)
    ).order_by("created_at", direction="DESCENDING").stream()

    result = []
    for doc in reports:
        data = doc.to_dict()
        result.append({
            "id": doc.id,
            "reported_uid": data.get("reported_uid"),
            "reason": data.get("reason"),
            "status": data.get("status"),
            "created_at": _convert_timestamp(data.get("created_at")),
        })

    return result
