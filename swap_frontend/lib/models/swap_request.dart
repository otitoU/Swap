/// Models for swap requests.

enum SwapRequestStatus {
  pending,
  accepted,
  declined,
  cancelled,
  pendingCompletion,
  disputed,
  completed,
}

enum SkillLevel { beginner, intermediate, advanced }

/// Type of swap exchange.
enum SwapType {
  direct,   // Both users exchange skills
  indirect, // Requester pays points, provider teaches
}

extension SwapTypeExtension on SwapType {
  String get displayName {
    switch (this) {
      case SwapType.direct:
        return 'Skill Exchange';
      case SwapType.indirect:
        return 'Points Based';
    }
  }
  
  String get description {
    switch (this) {
      case SwapType.direct:
        return 'Exchange skills with each other';
      case SwapType.indirect:
        return 'Pay with points for this service';
    }
  }
}

/// Completion data for one participant.
class ParticipantCompletion {
  final bool markedComplete;
  final DateTime? markedAt;
  final double? hoursClaimed;
  final SkillLevel? skillLevel;
  final String? notes;

  ParticipantCompletion({
    this.markedComplete = false,
    this.markedAt,
    this.hoursClaimed,
    this.skillLevel,
    this.notes,
  });

  factory ParticipantCompletion.fromJson(Map<String, dynamic> json) =>
      ParticipantCompletion(
        markedComplete: json['marked_complete'] as bool? ?? false,
        markedAt: json['marked_at'] != null
            ? DateTime.parse(json['marked_at'] as String)
            : null,
        hoursClaimed: (json['hours_claimed'] as num?)?.toDouble(),
        skillLevel: _parseSkillLevel(json['skill_level'] as String?),
        notes: json['notes'] as String?,
      );

  static SkillLevel? _parseSkillLevel(String? level) {
    switch (level) {
      case 'beginner':
        return SkillLevel.beginner;
      case 'intermediate':
        return SkillLevel.intermediate;
      case 'advanced':
        return SkillLevel.advanced;
      default:
        return null;
    }
  }
}

/// Full completion status for a swap.
class SwapCompletionData {
  final ParticipantCompletion requester;
  final ParticipantCompletion recipient;
  final DateTime? autoCompleteAt;
  final DateTime? completedAt;
  final double? finalHours;
  // Earnings on completion
  final int? requesterPointsEarned;
  final int? requesterCreditsEarned;
  final int? recipientPointsEarned;
  final int? recipientCreditsEarned;

  SwapCompletionData({
    required this.requester,
    required this.recipient,
    this.autoCompleteAt,
    this.completedAt,
    this.finalHours,
    this.requesterPointsEarned,
    this.requesterCreditsEarned,
    this.recipientPointsEarned,
    this.recipientCreditsEarned,
  });

  factory SwapCompletionData.fromJson(Map<String, dynamic> json) =>
      SwapCompletionData(
        requester: json['requester'] != null
            ? ParticipantCompletion.fromJson(
                json['requester'] as Map<String, dynamic>)
            : ParticipantCompletion(),
        recipient: json['recipient'] != null
            ? ParticipantCompletion.fromJson(
                json['recipient'] as Map<String, dynamic>)
            : ParticipantCompletion(),
        autoCompleteAt: json['auto_complete_at'] != null
            ? DateTime.parse(json['auto_complete_at'] as String)
            : null,
        completedAt: json['completed_at'] != null
            ? DateTime.parse(json['completed_at'] as String)
            : null,
        finalHours: (json['final_hours'] as num?)?.toDouble(),
        requesterPointsEarned: json['requester_points_earned'] as int?,
        requesterCreditsEarned: json['requester_credits_earned'] as int?,
        recipientPointsEarned: json['recipient_points_earned'] as int?,
        recipientCreditsEarned: json['recipient_credits_earned'] as int?,
      );
}

/// Minimal profile info for swap request participants.
class SwapParticipant {
  final String uid;
  final String? displayName;
  final String? photoUrl;
  final String? email;
  final String? skillsToOffer;
  final String? servicesNeeded;

  SwapParticipant({
    required this.uid,
    this.displayName,
    this.photoUrl,
    this.email,
    this.skillsToOffer,
    this.servicesNeeded,
  });

  factory SwapParticipant.fromJson(Map<String, dynamic> json) =>
      SwapParticipant(
        uid: json['uid'] as String? ?? '',
        displayName: json['display_name'] as String?,
        photoUrl: json['photo_url'] as String?,
        email: json['email'] as String?,
        skillsToOffer: json['skills_to_offer'] as String?,
        servicesNeeded: json['services_needed'] as String?,
      );
}

/// A swap request between two users.
class SwapRequest {
  final String id;
  final String requesterUid;
  final String recipientUid;
  final SwapRequestStatus status;
  final SwapType swapType;
  final String? requesterOffer;
  final String requesterNeed;
  final int? pointsOffered;
  final int? pointsReserved;
  final String? message;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? respondedAt;
  final String? conversationId;
  final SwapParticipant? requesterProfile;
  final SwapParticipant? recipientProfile;
  final SwapCompletionData? completion;

  SwapRequest({
    required this.id,
    required this.requesterUid,
    required this.recipientUid,
    required this.status,
    this.swapType = SwapType.direct,
    this.requesterOffer,
    required this.requesterNeed,
    this.pointsOffered,
    this.pointsReserved,
    this.message,
    required this.createdAt,
    required this.updatedAt,
    this.respondedAt,
    this.conversationId,
    this.requesterProfile,
    this.recipientProfile,
    this.completion,
  });

  factory SwapRequest.fromJson(Map<String, dynamic> json) => SwapRequest(
        id: json['id'] as String? ?? '',
        requesterUid: json['requester_uid'] as String? ?? '',
        recipientUid: json['recipient_uid'] as String? ?? '',
        status: _parseStatus(json['status'] as String?),
        swapType: _parseSwapType(json['swap_type'] as String?),
        requesterOffer: json['requester_offer'] as String?,
        requesterNeed: json['requester_need'] as String? ?? '',
        pointsOffered: json['points_offered'] as int?,
        pointsReserved: json['points_reserved'] as int?,
        message: json['message'] as String?,
        createdAt: json['created_at'] != null
            ? DateTime.parse(json['created_at'] as String)
            : DateTime.now(),
        updatedAt: json['updated_at'] != null
            ? DateTime.parse(json['updated_at'] as String)
            : DateTime.now(),
        respondedAt: json['responded_at'] != null
            ? DateTime.parse(json['responded_at'] as String)
            : null,
        conversationId: json['conversation_id'] as String?,
        requesterProfile: json['requester_profile'] != null
            ? SwapParticipant.fromJson(
                json['requester_profile'] as Map<String, dynamic>)
            : null,
        recipientProfile: json['recipient_profile'] != null
            ? SwapParticipant.fromJson(
                json['recipient_profile'] as Map<String, dynamic>)
            : null,
        completion: json['completion'] != null
            ? SwapCompletionData.fromJson(
                json['completion'] as Map<String, dynamic>)
            : null,
      );

  static SwapRequestStatus _parseStatus(String? status) {
    switch (status) {
      case 'accepted':
        return SwapRequestStatus.accepted;
      case 'declined':
        return SwapRequestStatus.declined;
      case 'cancelled':
        return SwapRequestStatus.cancelled;
      case 'pending_completion':
        return SwapRequestStatus.pendingCompletion;
      case 'disputed':
        return SwapRequestStatus.disputed;
      case 'completed':
        return SwapRequestStatus.completed;
      default:
        return SwapRequestStatus.pending;
    }
  }

  static SwapType _parseSwapType(String? type) {
    switch (type) {
      case 'indirect':
        return SwapType.indirect;
      default:
        return SwapType.direct;
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'requester_uid': requesterUid,
        'recipient_uid': recipientUid,
        'status': status.name,
        'swap_type': swapType.name,
        'requester_offer': requesterOffer,
        'requester_need': requesterNeed,
        'points_offered': pointsOffered,
        'points_reserved': pointsReserved,
        'message': message,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'responded_at': respondedAt?.toIso8601String(),
        'conversation_id': conversationId,
      };

  /// Whether this is a direct skill exchange.
  bool get isDirect => swapType == SwapType.direct;

  /// Whether this is an indirect (points-based) swap.
  bool get isIndirect => swapType == SwapType.indirect;

  /// Whether this request is pending and awaiting a response.
  bool get isPending => status == SwapRequestStatus.pending;

  /// Whether this request was accepted.
  bool get isAccepted => status == SwapRequestStatus.accepted;

  /// Whether this request was declined.
  bool get isDeclined => status == SwapRequestStatus.declined;

  /// Whether this request was cancelled.
  bool get isCancelled => status == SwapRequestStatus.cancelled;

  /// Whether this request is awaiting completion verification.
  bool get isPendingCompletion => status == SwapRequestStatus.pendingCompletion;

  /// Whether this request is disputed.
  bool get isDisputed => status == SwapRequestStatus.disputed;

  /// Whether this request is fully completed.
  bool get isCompleted => status == SwapRequestStatus.completed;

  /// Whether the swap is in an active state (accepted but not completed).
  bool get isActive => isAccepted || isPendingCompletion;

  /// Whether the swap can be marked complete.
  bool get canMarkComplete => isAccepted;
}
