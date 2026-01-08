import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart' as storage;

import '../widgets/app_sidebar.dart';
import '../services/portfolio_service.dart';
import '../services/review_service.dart';
import '../models/portfolio.dart';
import '../models/review.dart';
import 'home_page.dart';
import 'post_skill_page.dart';
import 'onboarding.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  static const double _gutter = 12;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const _AuthGuard();

    return Scaffold(
      backgroundColor: HomePage.bg,
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AppSidebar(active: 'Profile'),
            Expanded(
              child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('profiles')
                    .doc(uid)
                    .snapshots(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (!snap.hasData || !snap.data!.exists) {
                    return _EmptyProfileCard(
                      onSetup: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ProfileSetupFlow(),
                          ),
                        );
                      },
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
                  final joinedAt = _parseJoinedAt(data['joinedAt']);

                  // Stats (from portfolio data or fallbacks)
                  final swapsCompleted = (data['completed_swap_count'] ??
                      data['swapsCompleted'] ??
                      0) as int;
                  final hoursTraded = (data['total_hours_traded'] ??
                          data['hoursTraded'] ??
                          0)
                      .toDouble();
                  final avgRating = (data['average_rating'] ??
                          data['avgRating'] ??
                          0)
                      .toDouble();
                  final responseRate = ((data['responseRate'] ?? 0).toDouble())
                      .clamp(0, 100);
                  final swapCredits = (data['swap_credits'] ?? 0) as int;
                  final swapPoints = (data['swap_points'] ?? 0) as int;

                  // Skills stored as arrays on the user doc
                  final skillsToOffer =
                      (data['skillsToOffer'] as List<dynamic>?)
                          ?.cast<Map<String, dynamic>>() ??
                      const [];
                  final servicesNeeded =
                      (data['servicesNeeded'] as List<dynamic>?)
                          ?.cast<Map<String, dynamic>>() ??
                      const [];
                  final skillsCount = skillsToOffer.length;
                  final reviewsCount = (data['reviewsCount'] ?? 0) as int;

                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1000),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _HeaderBanner(
                              name: name.isEmpty ? 'Your Name' : name,
                              username: username,
                              city: city,
                              timezone: timezone,
                              photoUrl: photoUrl,
                              joinedLabel: joinedAt == null
                                  ? 'Joined recently'
                                  : 'Joined ${_formatMonthYear(joinedAt)}',
                              verified: verified,
                              topRated: topRated,
                              onEdit: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const ProfileSetupFlow(),
                                  ),
                                );
                              },
                              onSettings: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Settings coming soon'),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 12),

                            // Four compact stat tiles (dark)
                            Row(
                              children: [
                                Expanded(
                                  child: _StatCard(
                                    icon: Icons.swap_horiz_rounded,
                                    label: 'Swaps Completed',
                                    value: swapsCompleted.toString(),
                                  ),
                                ),
                                const SizedBox(width: _gutter),
                                Expanded(
                                  child: _StatCard(
                                    icon: Icons.access_time,
                                    label: 'Hours Traded',
                                    value: '${hoursTraded.toStringAsFixed(1)}h',
                                  ),
                                ),
                                const SizedBox(width: _gutter),
                                Expanded(
                                  child: _StatCard(
                                    icon: Icons.star_rate_rounded,
                                    label: 'Average Rating',
                                    value: avgRating.toStringAsFixed(1),
                                  ),
                                ),
                                const SizedBox(width: _gutter),
                                Expanded(
                                  child: _StatCard(
                                    icon: Icons.monetization_on_outlined,
                                    label: 'Swap Credits',
                                    value: swapCredits.toString(),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: _gutter),
                            // Second row of stats
                            Row(
                              children: [
                                Expanded(
                                  child: _StatCard(
                                    icon: Icons.toll_rounded,
                                    label: 'Swap Points',
                                    value: swapPoints.toString(),
                                  ),
                                ),
                                const SizedBox(width: _gutter),
                                Expanded(
                                  child: _StatCard(
                                    icon: Icons.trending_up_rounded,
                                    label: 'Response Rate',
                                    value:
                                        '${responseRate.toStringAsFixed(0)}%',
                                  ),
                                ),
                                const SizedBox(width: _gutter),
                                const Expanded(child: SizedBox()),
                                const SizedBox(width: _gutter),
                                const Expanded(child: SizedBox()),
                              ],
                            ),

                            const SizedBox(height: 16),

                            // Tabs: My Skills / Reviews / Activity
                            _SegmentedTabs(
                              skillsLabel: 'My Skills ($skillsCount)',
                              reviewsLabel: 'Reviews ($reviewsCount)',
                              activityLabel: 'Activity',
                              skillsBuilder: () => _SkillsSection(
                                skillsToOffer: skillsToOffer,
                                servicesNeeded: servicesNeeded,
                                uid: uid,
                                onPostFirst: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const PostSkillPage(),
                                    ),
                                  );
                                },
                              ),
                              reviewsBuilder: () => _ReviewsSection(uid: uid),
                              activityBuilder: () => _ActivitySection(uid: uid),
                            ),

                            if (bio.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              _AboutCard(bio: bio),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ------------------------------ Pieces ------------------------------ */

class _HeaderBanner extends StatelessWidget {
  const _HeaderBanner({
    required this.name,
    required this.username,
    required this.city,
    required this.timezone,
    required this.photoUrl,
    required this.joinedLabel,
    required this.verified,
    required this.topRated,
    required this.onEdit,
    required this.onSettings,
  });

  final String name;
  final String username;
  final String city;
  final String timezone;
  final String? photoUrl;
  final String joinedLabel;
  final bool verified;
  final bool topRated;
  final VoidCallback onEdit;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: HomePage.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 4,
      child: Column(
        children: [
          // Gradient banner
          Container(
            height: 128,
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              gradient: LinearGradient(
                colors: [Color(0xFF7C3AED), Color(0xFF4F46E5)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // content
                Padding(
                  padding: const EdgeInsets.only(top: 44),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(width: 92), // under avatar
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 10,
                              runSpacing: 6,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(
                                    color: HomePage.textPrimary,
                                    fontSize: 26,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                if (verified)
                                  _pill(
                                    icon: Icons.verified,
                                    label: 'Verified',
                                    fg: const Color(0xFF22C55E),
                                  ),
                                if (topRated)
                                  _pill(
                                    icon: Icons.emoji_events_outlined,
                                    label: 'Top Rated',
                                    fg: const Color(0xFFF59E0B),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 16,
                              runSpacing: 6,
                              children: [
                                if (city.isNotEmpty)
                                  _subInfo(
                                    icon: Icons.location_on_outlined,
                                    text: city,
                                  ),
                                if (joinedLabel.isNotEmpty)
                                  _subInfo(
                                    icon: Icons.calendar_month_outlined,
                                    text: joinedLabel,
                                  ),
                                _subInfo(
                                  icon: Icons.access_time,
                                  text: 'Responds in ~2h',
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Wrap(
                        spacing: 10,
                        children: [
                          _DarkChipButton(
                            icon: Icons.edit_outlined,
                            label: 'Edit Profile',
                            onPressed: onEdit,
                          ),
                          _DarkChipButton(
                            icon: Icons.settings_outlined,
                            label: 'Settings',
                            onPressed: onSettings,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // floating avatar with gradient ring + soft drop shadow
                Positioned(
                  left: 0,
                  top: -42,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [Color(0xFF9F67FF), Color(0xFF7C3AED)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black38,
                          blurRadius: 12,
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                    child: FutureBuilder<String?>(
                      future: _resolvePhotoUrl(photoUrl),
                      builder: (context, snap) {
                        final url = snap.data;
                        return CircleAvatar(
                          radius: 42,
                          backgroundColor: HomePage.surfaceAlt,
                          foregroundImage: (url != null && url.isNotEmpty)
                              ? NetworkImage(url)
                              : null,
                          child: (url == null || url.isEmpty)
                              ? Text(
                                  name.isNotEmpty
                                      ? name.characters.first.toUpperCase()
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
    return raw; // already an https URL
  }

  static Widget _pill({
    required IconData icon,
    required String label,
    required Color fg,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: HomePage.surfaceAlt,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: HomePage.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(color: fg, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  static Widget _subInfo({required IconData icon, required String text}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: const Color(0xFF94A3B8)),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(color: HomePage.textMuted, fontSize: 15),
        ),
      ],
    );
  }
}

/// Dark pill action like in the screenshot, matching theme
class _DarkChipButton extends StatelessWidget {
  const _DarkChipButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: HomePage.surfaceAlt,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: HomePage.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: HomePage.textPrimary),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: HomePage.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      child: Card(
        color: HomePage.surface,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: HomePage.line),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: HomePage.surfaceAlt,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: HomePage.line),
                ),
                child: Icon(icon, color: HomePage.accentAlt),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      color: HomePage.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: const TextStyle(color: HomePage.textMuted),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SegmentedTabs extends StatefulWidget {
  const _SegmentedTabs({
    required this.skillsBuilder,
    required this.reviewsBuilder,
    required this.activityBuilder,
    required this.skillsLabel,
    required this.reviewsLabel,
    required this.activityLabel,
  });
  final Widget Function() skillsBuilder;
  final Widget Function() reviewsBuilder;
  final Widget Function() activityBuilder;
  final String skillsLabel;
  final String reviewsLabel;
  final String activityLabel;

  @override
  State<_SegmentedTabs> createState() => _SegmentedTabsState();
}

class _SegmentedTabsState extends State<_SegmentedTabs> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // dark pill bar
        Container(
          height: 52,
          decoration: BoxDecoration(
            color: HomePage.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: HomePage.line),
          ),
          child: Row(
            children: [
              _tab(widget.skillsLabel, 0),
              _tab(widget.reviewsLabel, 1),
              _tab(widget.activityLabel, 2),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: switch (_index) {
            0 => widget.skillsBuilder(),
            1 => widget.reviewsBuilder(),
            _ => widget.activityBuilder(),
          },
        ),
      ],
    );
  }

  Expanded _tab(String label, int i) {
    final active = _index == i;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _index = i),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? HomePage.surfaceAlt : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: active ? HomePage.accentAlt : HomePage.line,
                width: active ? 2 : 1,
              ),
              boxShadow: active
                  ? const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Text(
              label,
              style: TextStyle(
                color: active ? HomePage.textPrimary : HomePage.textMuted,
                fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SkillsSection extends StatefulWidget {
  const _SkillsSection({
    required this.skillsToOffer,
    required this.servicesNeeded,
    required this.onPostFirst,
    required this.uid,
  });

  final List<Map<String, dynamic>> skillsToOffer;
  final List<Map<String, dynamic>> servicesNeeded;
  final VoidCallback onPostFirst;
  final String uid;

  @override
  State<_SkillsSection> createState() => _SkillsSectionState();
}

class _SkillsSectionState extends State<_SkillsSection> {
  List<Map<String, dynamic>> _postedSkills = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPostedSkills();
  }

  Future<void> _loadPostedSkills() async {
    debugPrint('Loading posted skills for uid: ${widget.uid}');
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('skills')
          .where('creatorUid', isEqualTo: widget.uid)
          .get();

      debugPrint('Found ${snapshot.docs.length} skills for uid: ${widget.uid}');

      if (mounted) {
        setState(() {
          _postedSkills = snapshot.docs.map((doc) => doc.data()).toList();
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading posted skills: $e');
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasProfileSkills = widget.skillsToOffer.isNotEmpty;
    final hasPostedSkills = _postedSkills.isNotEmpty;

    if (!hasProfileSkills && !hasPostedSkills && !_loading) {
      return _EmptySkills(onPostFirst: widget.onPostFirst);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Posted Skills (from skills collection)
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else if (_postedSkills.isNotEmpty) ...[
          _SectionCard(
            title: 'Posted Skills (${_postedSkills.length})',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _postedSkills.map((skill) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: HomePage.surfaceAlt,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: HomePage.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        skill['title'] ?? 'Untitled',
                        style: const TextStyle(
                          color: HomePage.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        skill['description'] ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: HomePage.textMuted,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        children: [
                          _smallChip(skill['category'] ?? 'other'),
                          _smallChip(skill['difficulty'] ?? ''),
                          _smallChip('${skill['estimatedHours'] ?? 1}h'),
                        ],
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Profile Skills (from onboarding)
        if (widget.skillsToOffer.isNotEmpty) ...[
          _SectionCard(
            title: 'Skills I Offer',
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: widget.skillsToOffer
                  .map(
                    (e) =>
                        _chip('${e['name']} • ${e['category']} • ${e['level']}'),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Services Needed
        _SectionCard(
          title: 'Services I Need',
          child: widget.servicesNeeded.isEmpty
              ? const Text(
                  'Nothing added yet.',
                  style: TextStyle(color: HomePage.textMuted),
                )
              : Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: widget.servicesNeeded
                      .map(
                        (e) => _chip(
                          '${e['name']} • ${e['category']} • ${e['level']}',
                        ),
                      )
                      .toList(),
                ),
        ),
      ],
    );
  }

  static Widget _chip(String text) {
    return Container(
      decoration: BoxDecoration(
        color: HomePage.surfaceAlt,
        border: Border.all(color: HomePage.line),
        borderRadius: BorderRadius.circular(999),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(text, style: const TextStyle(color: HomePage.textPrimary)),
    );
  }

  static Widget _smallChip(String text) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: HomePage.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: HomePage.line),
      ),
      child: Text(
        text,
        style: const TextStyle(color: HomePage.textMuted, fontSize: 11),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: HomePage.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: HomePage.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: HomePage.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _AboutCard extends StatelessWidget {
  const _AboutCard({required this.bio});
  final String bio;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'About',
      child: Text(bio, style: const TextStyle(color: HomePage.textPrimary)),
    );
  }
}

/* ---------------------------- Placeholders ---------------------------- */

class _EmptyProfileCard extends StatelessWidget {
  const _EmptyProfileCard({required this.onSetup});
  final VoidCallback onSetup;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Card(
        color: HomePage.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: HomePage.line),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.person_outline,
                size: 40,
                color: HomePage.textMuted,
              ),
              const SizedBox(height: 10),
              const Text(
                'Let’s set up your profile',
                style: TextStyle(
                  color: HomePage.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'We’ll use your details to personalize your page.',
                style: TextStyle(color: HomePage.textMuted),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 42,
                child: FilledButton(
                  onPressed: onSetup,
                  style: FilledButton.styleFrom(
                    backgroundColor: HomePage.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Complete Profile'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptySkills extends StatelessWidget {
  const _EmptySkills({required this.onPostFirst});
  final VoidCallback onPostFirst;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: HomePage.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: HomePage.line),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 26, 18, 28),
        child: Column(
          children: [
            CircleAvatar(
              radius: 42,
              backgroundColor: HomePage.surfaceAlt,
              child: Icon(
                Icons.person_outline,
                color: HomePage.textMuted,
                size: 40,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'No skills posted yet',
              style: TextStyle(
                color: HomePage.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Share your expertise with the community',
              style: TextStyle(color: HomePage.textMuted),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 44,
              child: FilledButton(
                onPressed: onPostFirst,
                style: FilledButton.styleFrom(
                  backgroundColor: HomePage.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Post Your First Skill'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewsSection extends StatefulWidget {
  const _ReviewsSection({required this.uid});
  final String uid;

  @override
  State<_ReviewsSection> createState() => _ReviewsSectionState();
}

class _ReviewsSectionState extends State<_ReviewsSection> {
  final _reviewService = ReviewService();
  List<Review>? _reviews;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadReviews();
  }

  Future<void> _loadReviews() async {
    try {
      final response = await _reviewService.getUserReviews(widget.uid, limit: 10);
      if (mounted) {
        setState(() {
          _reviews = response.reviews;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_error != null) {
      return _SectionCard(
        title: 'Reviews',
        child: Text(
          'Unable to load reviews.',
          style: const TextStyle(color: HomePage.textMuted),
        ),
      );
    }

    if (_reviews == null || _reviews!.isEmpty) {
      return _SectionCard(
        title: 'Reviews',
        child: const Text(
          'No reviews yet.',
          style: TextStyle(color: HomePage.textMuted),
        ),
      );
    }

    return Column(
      children: _reviews!.map((review) => _ReviewCard(review: review)).toList(),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review});
  final Review review;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: HomePage.surface,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: HomePage.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: HomePage.surfaceAlt,
                  backgroundImage: review.reviewerPhoto != null
                      ? NetworkImage(review.reviewerPhoto!)
                      : null,
                  child: review.reviewerPhoto == null
                      ? Text(
                          (review.reviewerName ?? 'U')[0].toUpperCase(),
                          style: const TextStyle(
                            color: HomePage.textPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        review.reviewerName ?? 'Anonymous',
                        style: const TextStyle(
                          color: HomePage.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (review.skillExchanged != null)
                        Text(
                          review.skillExchanged!,
                          style: const TextStyle(
                            color: HomePage.textMuted,
                            fontSize: 13,
                          ),
                        ),
                    ],
                  ),
                ),
                Row(
                  children: List.generate(
                    5,
                    (i) => Icon(
                      i < review.rating ? Icons.star : Icons.star_border,
                      size: 18,
                      color: const Color(0xFFF59E0B),
                    ),
                  ),
                ),
              ],
            ),
            if (review.reviewText != null && review.reviewText!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                review.reviewText!,
                style: const TextStyle(color: HomePage.textPrimary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActivitySection extends StatefulWidget {
  const _ActivitySection({required this.uid});
  final String uid;

  @override
  State<_ActivitySection> createState() => _ActivitySectionState();
}

class _ActivitySectionState extends State<_ActivitySection> {
  final _portfolioService = PortfolioService();
  List<CompletedSwapSummary>? _swaps;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadActivity();
  }

  Future<void> _loadActivity() async {
    try {
      final portfolio = await _portfolioService.getPortfolio(
        widget.uid,
        includeSwaps: true,
        includeReviews: false,
        swapLimit: 10,
      );
      if (mounted) {
        setState(() {
          _swaps = portfolio.recentSwaps;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_error != null) {
      return _SectionCard(
        title: 'Recent Activity',
        child: Text(
          'Unable to load activity.',
          style: const TextStyle(color: HomePage.textMuted),
        ),
      );
    }

    if (_swaps == null || _swaps!.isEmpty) {
      return _SectionCard(
        title: 'Recent Activity',
        child: const Text(
          'No recent activity.',
          style: TextStyle(color: HomePage.textMuted),
        ),
      );
    }

    return Column(
      children: _swaps!.map((swap) => _ActivityCard(swap: swap)).toList(),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.swap});
  final CompletedSwapSummary swap;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: HomePage.surface,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: HomePage.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: HomePage.surfaceAlt,
                  backgroundImage: swap.partnerPhoto != null
                      ? NetworkImage(swap.partnerPhoto!)
                      : null,
                  child: swap.partnerPhoto == null
                      ? Text(
                          (swap.partnerName ?? 'U')[0].toUpperCase(),
                          style: const TextStyle(
                            color: HomePage.textPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Swap with ${swap.partnerName ?? "Unknown"}',
                        style: const TextStyle(
                          color: HomePage.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${swap.hoursExchanged.toStringAsFixed(1)} hours exchanged',
                        style: const TextStyle(
                          color: HomePage.textMuted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF22C55E).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Completed',
                    style: TextStyle(
                      color: Color(0xFF22C55E),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (swap.skillTaught != null) ...[
                  Expanded(
                    child: _skillPill(
                      'Taught: ${swap.skillTaught!}',
                      const Color(0xFF7C3AED),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                if (swap.skillLearned != null)
                  Expanded(
                    child: _skillPill(
                      'Learned: ${swap.skillLearned!}',
                      const Color(0xFF0EA5E9),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _skillPill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _AuthGuard extends StatelessWidget {
  const _AuthGuard();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Please sign in to view your profile.',
        style: TextStyle(color: HomePage.textPrimary),
      ),
    );
  }
}

/* ----------------------------- Utilities ----------------------------- */

DateTime? _parseJoinedAt(dynamic v) {
  try {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is String) return DateTime.tryParse(v);
    return null;
  } catch (_) {
    return null;
  }
}

String _formatMonthYear(DateTime d) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[d.month - 1]} ${d.year}';
}
