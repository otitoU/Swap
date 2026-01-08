import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart' as storage;

import 'home_page.dart';

/// Page to view another user's profile (read-only)
class UserProfilePage extends StatelessWidget {
  final String uid;
  final String? initialName;
  final String? initialPhotoUrl;

  const UserProfilePage({
    super.key,
    required this.uid,
    this.initialName,
    this.initialPhotoUrl,
  });

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final isOwnProfile = currentUid == uid;

    return Scaffold(
      backgroundColor: HomePage.bg,
      appBar: AppBar(
        backgroundColor: HomePage.bg,
        foregroundColor: HomePage.textPrimary,
        elevation: 0,
        title: Text(initialName ?? 'Profile'),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('profiles')
            .doc(uid)
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snap.hasData || !snap.data!.exists) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.person_off, size: 64, color: HomePage.textMuted),
                  const SizedBox(height: 16),
                  Text(
                    'Profile not found',
                    style: TextStyle(color: HomePage.textMuted, fontSize: 18),
                  ),
                ],
              ),
            );
          }

          final data = snap.data!.data()!;
          final name = (data['fullName'] ?? data['displayName'] ?? '')
              .toString()
              .trim();
          final username = (data['username'] ?? '').toString().trim();
          final city = (data['city'] ?? '').toString().trim();
          final bio = (data['bio'] ?? '').toString().trim();
          final photoUrl = data['photoUrl'] as String?;
          final timezone = (data['timezone'] ?? '').toString().trim();

          final verified = (data['verified'] ?? false) == true;
          final topRated = (data['topRated'] ?? false) == true;

          // Stats
          final swapsCompleted = (data['completed_swap_count'] ??
              data['swapsCompleted'] ??
              0) as int;
          final avgRating =
              (data['average_rating'] ?? data['avgRating'] ?? 0).toDouble();

          // Skills
          final skillsToOffer =
              (data['skillsToOffer'] as List<dynamic>?)
                  ?.cast<Map<String, dynamic>>() ??
              const [];
          final servicesNeeded =
              (data['servicesNeeded'] as List<dynamic>?)
                  ?.cast<Map<String, dynamic>>() ??
              const [];

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Profile header card
                    Card(
                      color: HomePage.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          // Banner
                          Container(
                            height: 100,
                            decoration: const BoxDecoration(
                              borderRadius: BorderRadius.vertical(
                                top: Radius.circular(16),
                              ),
                              gradient: LinearGradient(
                                colors: [Color(0xFF7C3AED), Color(0xFF4F46E5)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 50),
                                  child: Column(
                                    children: [
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          const SizedBox(width: 100),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Wrap(
                                                  spacing: 8,
                                                  crossAxisAlignment:
                                                      WrapCrossAlignment.center,
                                                  children: [
                                                    Text(
                                                      name.isEmpty
                                                          ? 'User'
                                                          : name,
                                                      style: const TextStyle(
                                                        color:
                                                            HomePage.textPrimary,
                                                        fontSize: 24,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                      ),
                                                    ),
                                                    if (verified)
                                                      _badge(
                                                        Icons.verified,
                                                        'Verified',
                                                        const Color(0xFF22C55E),
                                                      ),
                                                    if (topRated)
                                                      _badge(
                                                        Icons
                                                            .emoji_events_outlined,
                                                        'Top Rated',
                                                        const Color(0xFFF59E0B),
                                                      ),
                                                  ],
                                                ),
                                                if (username.isNotEmpty)
                                                  Text(
                                                    '@$username',
                                                    style: TextStyle(
                                                      color: HomePage.textMuted,
                                                    ),
                                                  ),
                                                const SizedBox(height: 4),
                                                Wrap(
                                                  spacing: 16,
                                                  children: [
                                                    if (city.isNotEmpty)
                                                      _infoRow(
                                                        Icons
                                                            .location_on_outlined,
                                                        city,
                                                      ),
                                                    if (timezone.isNotEmpty)
                                                      _infoRow(
                                                        Icons.access_time,
                                                        timezone,
                                                      ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 16),
                                      // Action buttons
                                      if (!isOwnProfile)
                                        Row(
                                          children: [
                                            Expanded(
                                              child: FilledButton.icon(
                                                onPressed: () {
                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(
                                                    const SnackBar(
                                                      content: Text(
                                                        'Send a swap request to start messaging!',
                                                      ),
                                                    ),
                                                  );
                                                },
                                                icon: const Icon(
                                                    Icons.message_outlined),
                                                label: const Text('Message'),
                                                style: FilledButton.styleFrom(
                                                  backgroundColor:
                                                      HomePage.accent,
                                                  foregroundColor: Colors.white,
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                    vertical: 14,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: OutlinedButton.icon(
                                                onPressed: () {
                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(
                                                    const SnackBar(
                                                      content: Text(
                                                        'Swap request coming soon!',
                                                      ),
                                                    ),
                                                  );
                                                },
                                                icon: const Icon(
                                                    Icons.swap_horiz),
                                                label:
                                                    const Text('Request Swap'),
                                                style: OutlinedButton.styleFrom(
                                                  foregroundColor:
                                                      HomePage.textPrimary,
                                                  side: BorderSide(
                                                    color: HomePage.line,
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                    vertical: 14,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                    ],
                                  ),
                                ),
                                // Avatar
                                Positioned(
                                  left: 0,
                                  top: -40,
                                  child: Container(
                                    padding: const EdgeInsets.all(3),
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: LinearGradient(
                                        colors: [
                                          Color(0xFF9F67FF),
                                          Color(0xFF7C3AED),
                                        ],
                                      ),
                                    ),
                                    child: FutureBuilder<String?>(
                                      future: _resolvePhotoUrl(photoUrl),
                                      builder: (context, snap) {
                                        final url = snap.data;
                                        return CircleAvatar(
                                          radius: 44,
                                          backgroundColor: HomePage.surfaceAlt,
                                          foregroundImage:
                                              (url != null && url.isNotEmpty)
                                                  ? NetworkImage(url)
                                                  : null,
                                          child: (url == null || url.isEmpty)
                                              ? Text(
                                                  name.isNotEmpty
                                                      ? name[0].toUpperCase()
                                                      : 'U',
                                                  style: const TextStyle(
                                                    color: HomePage.textPrimary,
                                                    fontSize: 30,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                )
                                              : null,
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Stats row
                    Row(
                      children: [
                        Expanded(
                          child: _statCard(
                            Icons.swap_horiz,
                            'Swaps',
                            swapsCompleted.toString(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _statCard(
                            Icons.star,
                            'Rating',
                            avgRating > 0 ? avgRating.toStringAsFixed(1) : 'N/A',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _statCard(
                            Icons.lightbulb_outline,
                            'Skills',
                            skillsToOffer.length.toString(),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Bio
                    if (bio.isNotEmpty)
                      _sectionCard(
                        'About',
                        Text(
                          bio,
                          style: const TextStyle(color: HomePage.textPrimary),
                        ),
                      ),

                    if (bio.isNotEmpty) const SizedBox(height: 16),

                    // Skills to offer
                    if (skillsToOffer.isNotEmpty)
                      _sectionCard(
                        'Skills to Offer',
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: skillsToOffer
                              .map(
                                (e) => _skillChip(
                                  '${e['name']} • ${e['level']}',
                                ),
                              )
                              .toList(),
                        ),
                      ),

                    if (skillsToOffer.isNotEmpty) const SizedBox(height: 16),

                    // Services needed
                    if (servicesNeeded.isNotEmpty)
                      _sectionCard(
                        'Looking For',
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: servicesNeeded
                              .map(
                                (e) => _skillChip(
                                  '${e['name']} • ${e['level']}',
                                ),
                              )
                              .toList(),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  static Future<String?> _resolvePhotoUrl(String? raw) async {
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('gs://')) {
      try {
        return await storage.FirebaseStorage.instance
            .refFromURL(raw)
            .getDownloadURL();
      } catch (_) {
        return null;
      }
    }
    return raw;
  }

  Widget _badge(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: HomePage.surfaceAlt,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: HomePage.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: HomePage.textMuted),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(color: HomePage.textMuted, fontSize: 14)),
      ],
    );
  }

  Widget _statCard(IconData icon, String label, String value) {
    return Card(
      color: HomePage.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: HomePage.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: HomePage.accentAlt, size: 24),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                color: HomePage.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(label, style: TextStyle(color: HomePage.textMuted)),
          ],
        ),
      ),
    );
  }

  Widget _sectionCard(String title, Widget child) {
    return Card(
      color: HomePage.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: HomePage.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: HomePage.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _skillChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: HomePage.surfaceAlt,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: HomePage.line),
      ),
      child: Text(
        text,
        style: const TextStyle(color: HomePage.textPrimary, fontSize: 13),
      ),
    );
  }
}
