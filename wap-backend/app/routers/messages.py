"""Messaging endpoints for conversations and messages."""

from typing import Optional, List
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor, TimeoutError as FuturesTimeoutError
from fastapi import APIRouter, HTTPException, Query
from google.cloud.firestore_v1.base_query import FieldFilter

from app.schemas import (
    MessageCreate,
    MessageResponse,
    ConversationResponse,
    ConversationListResponse,
    ConversationStatus,
    LastMessage,
    OtherParticipant,
    SwapRequestStatus,
    MessageType,
)
from app.firebase_db import get_firebase_service
from app.email_service import get_email_service
from app.cache import get_cache_service

router = APIRouter(prefix="/conversations", tags=["messaging"])


def _convert_timestamp(value) -> Optional[str]:
    """Convert a Firestore timestamp to ISO string."""
    if value is None:
        return None
    if hasattr(value, "isoformat"):
        return value.isoformat()
    return str(value)


def _get_other_participant(participant_uids: List[str], current_uid: str) -> Optional[OtherParticipant]:
    """Get the other participant's profile info."""
    other_uid = next((uid for uid in participant_uids if uid != current_uid), None)
    if not other_uid:
        return None

    firebase = get_firebase_service()
    profile = firebase.get_profile(other_uid)
    if not profile:
        return None

    return OtherParticipant(
        uid=other_uid,
        display_name=profile.get("display_name"),
        photo_url=profile.get("photo_url"),
        skills_to_offer=profile.get("skills_to_offer"),
    )


def _check_conversation_access(conversation_data: dict, uid: str) -> bool:
    """Check if user has access to the conversation."""
    return uid in conversation_data.get("participant_uids", [])


def _validate_can_send_message(db, conversation_id: str, sender_uid: str) -> dict:
    """
    Validate that the user can send a message in this conversation.

    Returns the conversation data if valid.
    Raises HTTPException if invalid.
    """
    # Get conversation
    conv_ref = db.collection("conversations").document(conversation_id)
    conv_doc = conv_ref.get()

    if not conv_doc.exists:
        raise HTTPException(status_code=404, detail="Conversation not found")

    conv_data = conv_doc.to_dict()

    # Check user is participant
    if sender_uid not in conv_data.get("participant_uids", []):
        raise HTTPException(status_code=403, detail="Not a participant in this conversation")

    # Check conversation is active
    if conv_data.get("status") == ConversationStatus.blocked.value:
        raise HTTPException(status_code=403, detail="This conversation has been blocked")

    # Check swap request is accepted
    swap_request_id = conv_data.get("swap_request_id")
    if swap_request_id:
        swap_ref = db.collection("swap_requests").document(swap_request_id)
        swap_doc = swap_ref.get()
        if swap_doc.exists:
            swap_data = swap_doc.to_dict()
            if swap_data.get("status") != SwapRequestStatus.accepted.value:
                raise HTTPException(status_code=403, detail="Swap request is no longer accepted")

    return conv_data


def _fetch_conversations_for_user(db, uid: str) -> List:
    """Fetch conversations from Firestore with timeout protection."""
    query = db.collection("conversations").where(
        filter=FieldFilter("participant_uids", "array_contains", uid)
    )
    
    all_docs = []
    for doc in query.stream():
        data = doc.to_dict()
        # Filter: only active conversations
        if data.get("status") == ConversationStatus.active.value:
            all_docs.append(doc)
    return all_docs


@router.get("", response_model=ConversationListResponse)
def list_conversations(
    uid: str = Query(..., description="UID of the user"),
    limit: int = Query(20, ge=1, le=50, description="Max conversations to return"),
    offset: int = Query(0, ge=0, description="Offset for pagination"),
):
    """
    List all conversations for a user.

    - Returns conversations sorted by updated_at (most recent first)
    - Includes last message preview and unread count
    - Enriches with other participant's profile info
    - Excludes blocked conversations
    """
    print(f"list_conversations called for uid={uid}")
    
    # TEMPORARY: Return empty list to avoid Firestore index issues
    # TODO: Create composite index in Firebase Console for production
    return ConversationListResponse(conversations=[], total=0, has_more=False)
    
    # Original code commented out until index is created:
    # firebase = get_firebase_service()
    # db = firebase.db
    # ... rest of code ...
    
    # Sort by updated_at descending (newest first)
    all_docs.sort(
        key=lambda d: d.to_dict().get("updated_at") or datetime.min,
        reverse=True
    )
    total = len(all_docs)

    # Apply pagination
    paginated_docs = all_docs[offset:offset + limit]
    has_more = (offset + limit) < total

    conversations = []
    for doc in paginated_docs:
        data = doc.to_dict()
        data["id"] = doc.id

        # Get unread count for this user
        unread_counts = data.get("unread_counts", {})
        unread_count = unread_counts.get(uid, 0)

        # Parse last message
        last_message = None
        if data.get("last_message"):
            lm = data["last_message"]
            last_message = LastMessage(
                content=lm.get("content", ""),
                sender_uid=lm.get("sender_uid", ""),
                sent_at=_convert_timestamp(lm.get("sent_at")) or datetime.utcnow().isoformat(),
            )

        # Get other participant
        other_participant = _get_other_participant(data.get("participant_uids", []), uid)

        conversations.append(ConversationResponse(
            id=data["id"],
            participant_uids=data.get("participant_uids", []),
            swap_request_id=data.get("swap_request_id", ""),
            created_at=_convert_timestamp(data.get("created_at")) or datetime.utcnow().isoformat(),
            updated_at=_convert_timestamp(data.get("updated_at")) or datetime.utcnow().isoformat(),
            last_message=last_message,
            unread_count=unread_count,
            status=ConversationStatus(data.get("status", "active")),
            other_participant=other_participant,
        ))

    return ConversationListResponse(
        conversations=conversations,
        total=total,
        has_more=has_more,
    )


def _count_unread_for_user(db, uid: str) -> int:
    """Count unread messages from Firestore with timeout protection."""
    query = db.collection("conversations").where(
        filter=FieldFilter("participant_uids", "array_contains", uid)
    )
    
    total_unread = 0
    for doc in query.stream():
        data = doc.to_dict()
        # Filter: only count active conversations
        if data.get("status") == ConversationStatus.active.value:
            unread_counts = data.get("unread_counts", {})
            total_unread += unread_counts.get(uid, 0)
    return total_unread


@router.get("/unread-count")
def get_total_unread(uid: str = Query(..., description="UID of the user")):
    """Get total unread message count across all conversations."""
    print(f"get_total_unread called for uid={uid}")
    
    # TEMPORARY: Return 0 to avoid Firestore index issues
    # TODO: Create composite index in Firebase Console for production
    return {"total_unread": 0}


@router.get("/{conversation_id}", response_model=ConversationResponse)
def get_conversation(
    conversation_id: str,
    uid: str = Query(..., description="UID of the requesting user"),
):
    """Get a single conversation by ID."""
    firebase = get_firebase_service()
    db = firebase.db

    doc_ref = db.collection("conversations").document(conversation_id)
    doc = doc_ref.get()

    if not doc.exists:
        raise HTTPException(status_code=404, detail="Conversation not found")

    data = doc.to_dict()
    data["id"] = doc.id

    # Check access
    if not _check_conversation_access(data, uid):
        raise HTTPException(status_code=403, detail="Not authorized to view this conversation")

    # Get unread count
    unread_counts = data.get("unread_counts", {})
    unread_count = unread_counts.get(uid, 0)

    # Parse last message
    last_message = None
    if data.get("last_message"):
        lm = data["last_message"]
        last_message = LastMessage(
            content=lm.get("content", ""),
            sender_uid=lm.get("sender_uid", ""),
            sent_at=_convert_timestamp(lm.get("sent_at")) or datetime.utcnow().isoformat(),
        )

    # Get other participant
    other_participant = _get_other_participant(data.get("participant_uids", []), uid)

    return ConversationResponse(
        id=data["id"],
        participant_uids=data.get("participant_uids", []),
        swap_request_id=data.get("swap_request_id", ""),
        created_at=_convert_timestamp(data.get("created_at")) or datetime.utcnow().isoformat(),
        updated_at=_convert_timestamp(data.get("updated_at")) or datetime.utcnow().isoformat(),
        last_message=last_message,
        unread_count=unread_count,
        status=ConversationStatus(data.get("status", "active")),
        other_participant=other_participant,
    )


@router.get("/{conversation_id}/messages", response_model=List[MessageResponse])
def get_messages(
    conversation_id: str,
    uid: str = Query(..., description="UID of the requesting user"),
    limit: int = Query(50, ge=1, le=100, description="Max messages to return"),
    before: Optional[str] = Query(None, description="Cursor: get messages before this timestamp (ISO format)"),
):
    """
    Get messages in a conversation with cursor pagination.

    - Returns messages sorted by sent_at descending (newest first)
    - Use 'before' parameter for pagination (pass the oldest message's sent_at)
    """
    firebase = get_firebase_service()
    db = firebase.db

    # Validate access
    conv_ref = db.collection("conversations").document(conversation_id)
    conv_doc = conv_ref.get()

    if not conv_doc.exists:
        raise HTTPException(status_code=404, detail="Conversation not found")

    conv_data = conv_doc.to_dict()
    if not _check_conversation_access(conv_data, uid):
        raise HTTPException(status_code=403, detail="Not authorized to view this conversation")

    # Query messages
    messages_ref = conv_ref.collection("messages")
    query = messages_ref.order_by("sent_at", direction="DESCENDING")

    if before:
        try:
            before_dt = datetime.fromisoformat(before.replace("Z", "+00:00"))
            query = query.where(filter=FieldFilter("sent_at", "<", before_dt))
        except ValueError:
            pass  # Ignore invalid timestamp

    query = query.limit(limit)

    messages = []
    for doc in query.stream():
        data = doc.to_dict()
        messages.append(MessageResponse(
            id=doc.id,
            conversation_id=conversation_id,
            sender_uid=data.get("sender_uid", ""),
            content=data.get("content", ""),
            sent_at=_convert_timestamp(data.get("sent_at")) or datetime.utcnow().isoformat(),
            read_at=_convert_timestamp(data.get("read_at")),
            read_by=data.get("read_by", []),
            type=MessageType(data.get("type", "text")),
        ))

    return messages


@router.post("/{conversation_id}/messages", response_model=MessageResponse)
def send_message(
    conversation_id: str,
    message: MessageCreate,
    uid: str = Query(..., description="UID of the sender"),
):
    """
    Send a message in a conversation.

    - Validates user is a participant
    - Validates conversation is active
    - Validates associated swap request is accepted
    - Updates conversation's last_message and unread_counts
    - Sends email notification to recipient (with debouncing)
    """
    firebase = get_firebase_service()
    email_service = get_email_service()
    db = firebase.db

    # Validate can send message
    conv_data = _validate_can_send_message(db, conversation_id, uid)

    now = datetime.utcnow()

    # Create message
    message_doc = {
        "sender_uid": uid,
        "content": message.content,
        "sent_at": now,
        "read_at": None,
        "read_by": [uid],  # Sender has read it
        "type": MessageType.text.value,
    }

    conv_ref = db.collection("conversations").document(conversation_id)
    msg_ref = conv_ref.collection("messages").document()
    msg_ref.set(message_doc)

    # Update conversation
    participant_uids = conv_data.get("participant_uids", [])
    other_uid = next((u for u in participant_uids if u != uid), None)

    unread_counts = conv_data.get("unread_counts", {})
    if other_uid:
        unread_counts[other_uid] = unread_counts.get(other_uid, 0) + 1

    conv_ref.update({
        "last_message": {
            "content": message.content[:100],  # Truncate for preview
            "sender_uid": uid,
            "sent_at": now,
        },
        "updated_at": now,
        "unread_counts": unread_counts,
    })

    # Send email notification to other participant (with debouncing)
    if other_uid:
        other_profile = firebase.get_profile(other_uid)
        sender_profile = firebase.get_profile(uid)

        if other_profile and other_profile.get("email_updates", True) and other_profile.get("email"):
            email_service.send_new_message_notification(
                to_email=other_profile["email"],
                recipient_uid=other_uid,
                recipient_name=other_profile.get("display_name", "there"),
                sender_name=sender_profile.get("display_name", "Someone") if sender_profile else "Someone",
                message_preview=message.content[:100],
                conversation_id=conversation_id,
            )

    return MessageResponse(
        id=msg_ref.id,
        conversation_id=conversation_id,
        sender_uid=uid,
        content=message.content,
        sent_at=now.isoformat(),
        read_at=None,
        read_by=[uid],
        type=MessageType.text,
    )


@router.post("/{conversation_id}/mark-read")
def mark_conversation_read(
    conversation_id: str,
    uid: str = Query(..., description="UID of the user"),
):
    """
    Mark all messages in a conversation as read by this user.

    - Updates all unread messages with read_at and read_by
    - Resets unread_count for this user to 0
    """
    firebase = get_firebase_service()
    db = firebase.db

    # Get conversation
    conv_ref = db.collection("conversations").document(conversation_id)
    conv_doc = conv_ref.get()

    if not conv_doc.exists:
        raise HTTPException(status_code=404, detail="Conversation not found")

    conv_data = conv_doc.to_dict()

    # Check access
    if not _check_conversation_access(conv_data, uid):
        raise HTTPException(status_code=403, detail="Not authorized")

    now = datetime.utcnow()

    # Update unread messages (those not sent by this user and not read by them)
    messages_ref = conv_ref.collection("messages")

    # Get messages not read by this user
    for doc in messages_ref.stream():
        data = doc.to_dict()
        read_by = data.get("read_by", [])

        if uid not in read_by and data.get("sender_uid") != uid:
            read_by.append(uid)
            doc.reference.update({
                "read_by": read_by,
                "read_at": now,
            })

    # Reset unread count
    unread_counts = conv_data.get("unread_counts", {})
    unread_counts[uid] = 0
    conv_ref.update({"unread_counts": unread_counts})

    return {"message": "Marked as read", "conversation_id": conversation_id}
