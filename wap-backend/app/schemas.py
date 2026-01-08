"""Pydantic schemas for user profiles and messaging."""

from datetime import datetime
from enum import Enum
from typing import Optional, List, Literal
from pydantic import BaseModel, Field, EmailStr


class ProfileBase(BaseModel):
    """Base profile fields - matches Flutter AppUser model."""
    
    # Firebase Auth fields
    uid: str = Field(..., description="Firebase Auth UID")
    email: EmailStr = Field(..., description="User email")
    display_name: Optional[str] = Field(None, description="Display name")
    photo_url: Optional[str] = Field(None, description="Profile photo URL")
    
    # User profile fields
    full_name: Optional[str] = Field(None, description="Full name")
    username: Optional[str] = Field(None, description="Username")
    bio: Optional[str] = Field(None, description="User bio")
    city: Optional[str] = Field(None, description="City")
    timezone: Optional[str] = Field(None, description="Timezone")
    
    # Skill-swap fields
    skills_to_offer: Optional[str] = Field(None, description="Skills user can teach")
    services_needed: Optional[str] = Field(None, description="Services/skills user wants to learn")
    
    # Settings/preferences
    dm_open: Optional[bool] = Field(True, description="Direct messages open")
    email_updates: Optional[bool] = Field(True, description="Email updates enabled")
    show_city: Optional[bool] = Field(True, description="Show city publicly")


class ProfileCreate(ProfileBase):
    """Schema for creating a new profile."""
    
    created_at: Optional[datetime] = Field(default_factory=datetime.utcnow)


class ProfileUpdate(BaseModel):
    """Schema for updating an existing profile (all fields optional)."""
    
    email: Optional[EmailStr] = None
    display_name: Optional[str] = None
    photo_url: Optional[str] = None
    full_name: Optional[str] = None
    username: Optional[str] = None
    bio: Optional[str] = None
    city: Optional[str] = None
    timezone: Optional[str] = None
    skills_to_offer: Optional[str] = None
    services_needed: Optional[str] = None
    dm_open: Optional[bool] = None
    email_updates: Optional[bool] = None
    show_city: Optional[bool] = None


class ProfileResponse(ProfileBase):
    """Schema for profile responses."""
    
    created_at: datetime
    updated_at: Optional[datetime] = None
    
    class Config:
        from_attributes = True
        json_schema_extra = {
            "example": {
                "uid": "firebase_user_123",
                "email": "alice@example.com",
                "display_name": "Alice Smith",
                "photo_url": "https://example.com/photo.jpg",
                "full_name": "Alice Marie Smith",
                "username": "alice_codes",
                "bio": "Software engineer passionate about music",
                "city": "New York",
                "timezone": "America/New_York",
                "skills_to_offer": "Python programming, web development, FastAPI",
                "services_needed": "Guitar lessons, music theory",
                "dm_open": True,
                "email_updates": True,
                "show_city": True,
                "created_at": "2025-01-15T10:30:00Z",
                "updated_at": "2025-01-20T15:45:00Z"
            }
        }


class ProfileSearchResult(BaseModel):
    """Schema for search results."""
    
    uid: str
    email: str
    display_name: Optional[str]
    photo_url: Optional[str]
    full_name: Optional[str]
    username: Optional[str]
    bio: Optional[str]
    city: Optional[str]
    timezone: Optional[str]
    skills_to_offer: Optional[str]
    services_needed: Optional[str]
    dm_open: Optional[bool]
    show_city: Optional[bool]
    score: float = Field(..., description="Similarity score (0-1)")


class ReciprocalMatchResult(ProfileSearchResult):
    """Schema for reciprocal match results."""

    reciprocal_score: float = Field(..., description="Harmonic mean of both match directions")
    offer_match_score: float = Field(..., description="How well they offer what you need")
    need_match_score: float = Field(..., description="How well you offer what they need")


# =============================================================================
# Swap Request Schemas
# =============================================================================

class SwapRequestStatus(str, Enum):
    """Status of a swap request."""
    pending = "pending"
    accepted = "accepted"
    declined = "declined"
    cancelled = "cancelled"
    # Completion states
    pending_completion = "pending_completion"  # One party marked complete
    disputed = "disputed"                       # Dispute raised
    completed = "completed"                     # Finalized


class SkillLevel(str, Enum):
    """Skill level for points calculation."""
    beginner = "beginner"
    intermediate = "intermediate"
    advanced = "advanced"


class SwapRequestCreate(BaseModel):
    """Schema for creating a swap request."""

    recipient_uid: str = Field(..., description="UID of person to swap with")
    requester_offer: str = Field(..., description="What you're offering in the swap")
    requester_need: str = Field(..., description="What you need from them")
    message: Optional[str] = Field(None, max_length=500, description="Optional intro message")


class SwapRequestAction(BaseModel):
    """Schema for responding to a swap request."""

    action: Literal["accept", "decline"] = Field(..., description="Accept or decline the request")


class SwapParticipant(BaseModel):
    """Minimal profile info for swap request participants."""

    uid: str
    display_name: Optional[str] = None
    photo_url: Optional[str] = None
    email: Optional[str] = None
    skills_to_offer: Optional[str] = None
    services_needed: Optional[str] = None


class SwapRequestResponse(BaseModel):
    """Schema for swap request responses."""

    id: str
    requester_uid: str
    recipient_uid: str
    status: SwapRequestStatus
    requester_offer: str
    requester_need: str
    message: Optional[str] = None
    created_at: datetime
    updated_at: datetime
    responded_at: Optional[datetime] = None
    conversation_id: Optional[str] = None
    requester_profile: Optional[SwapParticipant] = None
    recipient_profile: Optional[SwapParticipant] = None


# =============================================================================
# Messaging Schemas
# =============================================================================

class MessageType(str, Enum):
    """Type of message."""
    text = "text"
    system = "system"


class ConversationStatus(str, Enum):
    """Status of a conversation."""
    active = "active"
    blocked = "blocked"
    archived = "archived"


class MessageCreate(BaseModel):
    """Schema for sending a message."""

    content: str = Field(..., min_length=1, max_length=5000, description="Message content")


class MessageResponse(BaseModel):
    """Schema for message responses."""

    id: str
    conversation_id: str
    sender_uid: str
    content: str
    sent_at: datetime
    read_at: Optional[datetime] = None
    read_by: List[str] = Field(default_factory=list)
    type: MessageType = MessageType.text


class LastMessage(BaseModel):
    """Embedded last message preview for conversation list."""

    content: str
    sender_uid: str
    sent_at: datetime


class OtherParticipant(BaseModel):
    """Other participant info for conversation display."""

    uid: str
    display_name: Optional[str] = None
    photo_url: Optional[str] = None
    skills_to_offer: Optional[str] = None


class ConversationResponse(BaseModel):
    """Schema for conversation responses."""

    id: str
    participant_uids: List[str]
    swap_request_id: str
    created_at: datetime
    updated_at: datetime
    last_message: Optional[LastMessage] = None
    unread_count: int = 0
    status: ConversationStatus = ConversationStatus.active
    other_participant: Optional[OtherParticipant] = None


class ConversationListResponse(BaseModel):
    """Paginated conversation list response."""

    conversations: List[ConversationResponse]
    total: int
    has_more: bool


# =============================================================================
# Moderation Schemas
# =============================================================================

class BlockCreate(BaseModel):
    """Schema for blocking a user."""

    blocked_uid: str = Field(..., description="UID of user to block")
    reason: Optional[str] = Field(None, max_length=500, description="Optional reason for blocking")


class BlockResponse(BaseModel):
    """Schema for block responses."""

    id: str
    blocker_uid: str
    blocked_uid: str
    created_at: datetime
    reason: Optional[str] = None


class ReportReason(str, Enum):
    """Reason for reporting a user."""
    spam = "spam"
    harassment = "harassment"
    inappropriate_content = "inappropriate_content"
    scam = "scam"
    other = "other"


class ReportCreate(BaseModel):
    """Schema for reporting a user or message."""

    reported_uid: str = Field(..., description="UID of user being reported")
    conversation_id: Optional[str] = Field(None, description="Related conversation ID")
    message_id: Optional[str] = Field(None, description="Related message ID")
    reason: ReportReason = Field(..., description="Reason for report")
    details: str = Field(..., min_length=10, max_length=2000, description="Details of the report")


class ReportResponse(BaseModel):
    """Schema for report confirmation."""

    id: str
    status: str = "pending"
    message: str = "Report submitted. We'll review it within 24-48 hours."


# =============================================================================
# Swap Completion Schemas
# =============================================================================

class SwapCompletionCreate(BaseModel):
    """Schema for marking a swap as complete."""

    hours_exchanged: float = Field(..., ge=0.5, le=100, description="Hours spent in exchange")
    skill_level: SkillLevel = Field(..., description="Level of skill exchanged")
    notes: Optional[str] = Field(None, max_length=500, description="Optional completion notes")


class SwapCompletionVerify(BaseModel):
    """Schema for verifying or disputing a completion."""

    action: Literal["verify", "dispute"] = Field(..., description="Verify or dispute the completion")
    dispute_reason: Optional[str] = Field(None, max_length=500, description="Reason for dispute (required if disputing)")


class ParticipantCompletion(BaseModel):
    """Tracks completion state for one participant."""

    marked_complete: bool = False
    marked_at: Optional[datetime] = None
    hours_claimed: Optional[float] = None
    skill_level: Optional[SkillLevel] = None
    notes: Optional[str] = None


class SwapCompletionStatus(BaseModel):
    """Current completion status for a swap."""

    swap_request_id: str
    status: SwapRequestStatus
    requester_completion: Optional[ParticipantCompletion] = None
    recipient_completion: Optional[ParticipantCompletion] = None
    auto_complete_at: Optional[datetime] = None  # When auto-completion will trigger
    completed_at: Optional[datetime] = None
    final_hours: Optional[float] = None  # Agreed hours after verification


# =============================================================================
# Reviews Schemas
# =============================================================================

class ReviewCreate(BaseModel):
    """Schema for submitting a review after swap completion."""

    swap_request_id: str = Field(..., description="ID of the completed swap")
    rating: int = Field(..., ge=1, le=5, description="Star rating (1-5)")
    review_text: Optional[str] = Field(None, max_length=1000, description="Optional review text")


class ReviewResponse(BaseModel):
    """Schema for review responses."""

    id: str
    swap_request_id: str
    reviewer_uid: str
    reviewed_uid: str
    rating: int
    review_text: Optional[str] = None
    skill_exchanged: Optional[str] = None
    hours_exchanged: Optional[float] = None
    created_at: datetime

    # Enriched reviewer info
    reviewer_name: Optional[str] = None
    reviewer_photo: Optional[str] = None


class ReviewListResponse(BaseModel):
    """Paginated list of reviews."""

    reviews: List[ReviewResponse]
    total: int
    average_rating: float


# =============================================================================
# Points & Credits Schemas
# =============================================================================

class PointsTransactionType(str, Enum):
    """Type of points transaction."""
    earned = "earned"
    spent = "spent"


class PointsTransactionReason(str, Enum):
    """Reason for points transaction."""
    swap_completed = "swap_completed"
    priority_boost = "priority_boost"
    request_without_reciprocity = "request_without_reciprocity"
    bonus = "bonus"  # For promotions, etc.


class PointsTransaction(BaseModel):
    """Schema for a points transaction record."""

    id: str
    uid: str
    type: PointsTransactionType
    amount: int
    balance_after: int
    reason: PointsTransactionReason
    related_swap_id: Optional[str] = None
    related_skill: Optional[str] = None
    created_at: datetime


class PointsBalanceResponse(BaseModel):
    """Schema for points balance response."""

    uid: str
    swap_points: int
    lifetime_points_earned: int
    recent_transactions: List[PointsTransaction] = []


class PointsSpendRequest(BaseModel):
    """Schema for spending points."""

    amount: int = Field(..., ge=1, description="Points to spend")
    reason: Literal["priority_boost", "request_without_reciprocity"] = Field(..., description="What to spend on")
    duration_hours: Optional[int] = Field(24, ge=1, le=168, description="Duration for boost (if applicable)")


class PointsSpendResponse(BaseModel):
    """Schema for spend confirmation."""

    success: bool
    new_balance: int
    transaction_id: str
    message: str


# =============================================================================
# Portfolio Schemas
# =============================================================================

class VerifiedSkill(BaseModel):
    """A skill verified through completed swaps."""

    skill_name: str
    times_exchanged: int
    total_hours: float
    average_rating: float
    last_used: Optional[datetime] = None


class CompletedSwapSummary(BaseModel):
    """Summary of a completed swap for portfolio."""

    swap_request_id: str
    partner_uid: str
    partner_name: Optional[str] = None
    partner_photo: Optional[str] = None
    skill_taught: Optional[str] = None
    skill_learned: Optional[str] = None
    hours_exchanged: float
    rating_given: Optional[int] = None
    rating_received: Optional[int] = None
    completed_at: datetime


class PortfolioResponse(BaseModel):
    """Comprehensive skill portfolio response."""

    uid: str
    display_name: Optional[str] = None
    photo_url: Optional[str] = None

    # Stats
    swap_credits: int = 0
    swap_points: int = 0
    total_swaps_completed: int = 0
    total_hours_traded: float = 0.0
    average_rating: float = 0.0
    review_count: int = 0

    # Verified skills (from completed swaps)
    verified_skills_taught: List[VerifiedSkill] = []
    verified_skills_learned: List[VerifiedSkill] = []

    # Recent activity
    recent_swaps: List[CompletedSwapSummary] = []
    recent_reviews: List[ReviewResponse] = []

    # Member since
    member_since: Optional[datetime] = None

