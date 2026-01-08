/// Models for swap points and transactions.

enum PointsTransactionType { earned, spent }

enum PointsTransactionReason {
  swapCompleted,
  priorityBoost,
  requestWithoutReciprocity,
}

/// A single points transaction.
class PointsTransaction {
  final String id;
  final String uid;
  final PointsTransactionType type;
  final int amount;
  final int balanceAfter;
  final PointsTransactionReason reason;
  final String? relatedSwapId;
  final String? relatedSkill;
  final DateTime createdAt;

  PointsTransaction({
    required this.id,
    required this.uid,
    required this.type,
    required this.amount,
    required this.balanceAfter,
    required this.reason,
    this.relatedSwapId,
    this.relatedSkill,
    required this.createdAt,
  });

  factory PointsTransaction.fromJson(Map<String, dynamic> json) =>
      PointsTransaction(
        id: json['id'] as String? ?? '',
        uid: json['uid'] as String? ?? '',
        type: _parseType(json['type'] as String?),
        amount: json['amount'] as int? ?? 0,
        balanceAfter: json['balance_after'] as int? ?? 0,
        reason: _parseReason(json['reason'] as String?),
        relatedSwapId: json['related_swap_id'] as String?,
        relatedSkill: json['related_skill'] as String?,
        createdAt: json['created_at'] != null
            ? DateTime.parse(json['created_at'] as String)
            : DateTime.now(),
      );

  static PointsTransactionType _parseType(String? type) {
    switch (type) {
      case 'spent':
        return PointsTransactionType.spent;
      default:
        return PointsTransactionType.earned;
    }
  }

  static PointsTransactionReason _parseReason(String? reason) {
    switch (reason) {
      case 'priority_boost':
        return PointsTransactionReason.priorityBoost;
      case 'request_without_reciprocity':
        return PointsTransactionReason.requestWithoutReciprocity;
      default:
        return PointsTransactionReason.swapCompleted;
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'uid': uid,
        'type': type.name,
        'amount': amount,
        'balance_after': balanceAfter,
        'reason': reason.name,
        'related_swap_id': relatedSwapId,
        'related_skill': relatedSkill,
        'created_at': createdAt.toIso8601String(),
      };

  /// Whether this is an earned transaction.
  bool get isEarned => type == PointsTransactionType.earned;

  /// Whether this is a spent transaction.
  bool get isSpent => type == PointsTransactionType.spent;
}

/// User's points balance response.
class PointsBalanceResponse {
  final String uid;
  final int swapPoints;
  final int lifetimePointsEarned;
  final List<PointsTransaction> recentTransactions;

  PointsBalanceResponse({
    required this.uid,
    required this.swapPoints,
    required this.lifetimePointsEarned,
    required this.recentTransactions,
  });

  factory PointsBalanceResponse.fromJson(Map<String, dynamic> json) =>
      PointsBalanceResponse(
        uid: json['uid'] as String? ?? '',
        swapPoints: json['swap_points'] as int? ?? 0,
        lifetimePointsEarned: json['lifetime_points_earned'] as int? ?? 0,
        recentTransactions: (json['recent_transactions'] as List<dynamic>?)
                ?.map(
                    (e) => PointsTransaction.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );
}

/// Active priority boost.
class ActiveBoost {
  final String id;
  final String type;
  final DateTime startedAt;
  final DateTime endsAt;
  final double remainingHours;

  ActiveBoost({
    required this.id,
    required this.type,
    required this.startedAt,
    required this.endsAt,
    required this.remainingHours,
  });

  factory ActiveBoost.fromJson(Map<String, dynamic> json) => ActiveBoost(
        id: json['id'] as String? ?? '',
        type: json['type'] as String? ?? 'priority',
        startedAt: json['started_at'] != null
            ? DateTime.parse(json['started_at'] as String)
            : DateTime.now(),
        endsAt: json['ends_at'] != null
            ? DateTime.parse(json['ends_at'] as String)
            : DateTime.now(),
        remainingHours: (json['remaining_hours'] as num?)?.toDouble() ?? 0.0,
      );
}
