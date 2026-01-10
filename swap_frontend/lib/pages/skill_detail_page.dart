import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'home_page.dart';
import 'user_profile_page.dart' show showSwapRequestDialog;
import '../models/swap_request.dart';
import '../services/swap_request_service.dart';

class SkillDetailPage extends StatefulWidget {
  final String title;
  final String description;
  final String category;
  final String difficulty;
  final int durationHours;
  final String mode;
  final double rating;
  final List<String> tags;
  final List<String> deliverables;
  final bool verified;
  final String creatorUid;
  final String creatorName;
  final String? creatorPhotoUrl;
  final String? servicesNeeded;

  const SkillDetailPage({
    super.key,
    required this.title,
    required this.description,
    required this.category,
    required this.difficulty,
    required this.durationHours,
    required this.mode,
    required this.rating,
    required this.tags,
    required this.deliverables,
    required this.verified,
    required this.creatorUid,
    required this.creatorName,
    this.creatorPhotoUrl,
    this.servicesNeeded,
  });

  @override
  State<SkillDetailPage> createState() => _SkillDetailPageState();
}

class _SkillDetailPageState extends State<SkillDetailPage> {
  int _selectedSegment = 0; // 0 = Skill, 1 = Profile
  Map<String, dynamic>? _profileData;
  bool _loadingProfile = true;
  List<Map<String, dynamic>> _userSkills = [];

  // Swap history
  List<SwapRequest>? _swapHistory;
  bool _loadingSwapHistory = true;

  // Creator's services needed (fetched from profile if not provided)
  String? _creatorServicesNeeded;

  @override
  void initState() {
    super.initState();
    _creatorServicesNeeded = widget.servicesNeeded;
    _loadProfileData();
    _loadSwapHistory();
  }

  Future<void> _loadSwapHistory() async {
    try {
      final swapService = SwapRequestService();
      final swaps = await swapService.getCompletedSwaps(widget.creatorUid, limit: 5);
      if (mounted) {
        setState(() {
          _swapHistory = swaps;
          _loadingSwapHistory = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading swap history: $e');
      if (mounted) {
        setState(() => _loadingSwapHistory = false);
      }
    }
  }

  Future<void> _loadProfileData() async {
    try {
      // Load user profile from 'profiles' collection
      final profileDoc = await FirebaseFirestore.instance
          .collection('profiles')
          .doc(widget.creatorUid)
          .get();

      // Load user's other skills
      final skillsSnapshot = await FirebaseFirestore.instance
          .collection('skills')
          .where('creatorUid', isEqualTo: widget.creatorUid)
          .get();

      if (mounted) {
        final profileData = profileDoc.data();

        // Extract services needed from profile if not already set
        String? servicesNeeded = _creatorServicesNeeded;
        if ((servicesNeeded == null || servicesNeeded.isEmpty) && profileData != null) {
          // Try to get from profile - could be List or String
          final rawNeeds = profileData['servicesNeeded'] ?? profileData['services_needed'];
          if (rawNeeds is String) {
            servicesNeeded = rawNeeds;
          } else if (rawNeeds is List) {
            // Convert list of skill maps to readable string
            servicesNeeded = rawNeeds.map((need) {
              if (need is Map) {
                final name = need['name'] ?? need['title'] ?? '';
                final level = need['level'] ?? '';
                return level.toString().isNotEmpty ? '$name ($level)' : name;
              }
              return need.toString();
            }).join(', ');
          }
        }

        setState(() {
          _profileData = profileData;
          _creatorServicesNeeded = servicesNeeded;
          _userSkills = skillsSnapshot.docs
              .map((doc) => doc.data())
              .where((skill) => skill['title'] != widget.title) // Exclude current skill
              .toList();
          _loadingProfile = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
      if (mounted) {
        setState(() => _loadingProfile = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HomePage.bg,
      appBar: AppBar(
        backgroundColor: HomePage.bg,
        foregroundColor: HomePage.textPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
      ),
      body: Column(
        children: [
          // Segmented Picker
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Container(
              decoration: BoxDecoration(
                color: HomePage.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: HomePage.line),
              ),
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  Expanded(
                    child: _SegmentButton(
                      label: 'Skill Details',
                      icon: Icons.article_outlined,
                      isSelected: _selectedSegment == 0,
                      onTap: () => setState(() => _selectedSegment = 0),
                    ),
                  ),
                  Expanded(
                    child: _SegmentButton(
                      label: 'Profile',
                      icon: Icons.person_outline,
                      isSelected: _selectedSegment == 1,
                      onTap: () => setState(() => _selectedSegment = 1),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: _selectedSegment == 0
                      ? _buildSkillDetails()
                      : _buildProfileView(),
                ),
              ),
            ),
          ),

          // Bottom Request Button
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: HomePage.surface,
              border: Border(top: BorderSide(color: HomePage.line)),
            ),
            child: SafeArea(
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: () {
                    showSwapRequestDialog(
                      context,
                      recipientUid: widget.creatorUid,
                      recipientName: widget.creatorName,
                      preSelectedSkill: widget.title,
                    );
                  },
                  icon: const Icon(Icons.swap_horiz, size: 22),
                  label: const Text(
                    'Request Swap',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: HomePage.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkillDetails() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with category and badges
        Row(
          children: [
            _Pill(widget.category),
            const SizedBox(width: 8),
            _Pill(widget.difficulty, color: HomePage.accent),
            if (widget.verified) ...[
              const SizedBox(width: 8),
              const _Pill('Verified', icon: Icons.verified, color: HomePage.success),
            ],
          ],
        ),
        const SizedBox(height: 16),

        // Title
        Text(
          widget.title,
          style: const TextStyle(
            color: HomePage.textPrimary,
            fontSize: 26,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 20),

        // Quick info row
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: HomePage.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: HomePage.line),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _InfoItem(
                icon: Icons.access_time,
                label: 'Duration',
                value: '${widget.durationHours}h',
              ),
              _InfoItem(
                icon: Icons.public,
                label: 'Format',
                value: widget.mode,
              ),
              _InfoItem(
                icon: Icons.star,
                label: 'Rating',
                value: widget.rating.toStringAsFixed(1),
                iconColor: Colors.amber,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Description section
        _SectionTitle('About This Skill'),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: HomePage.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: HomePage.line),
          ),
          child: Text(
            widget.description,
            style: const TextStyle(
              color: HomePage.textPrimary,
              fontSize: 15,
              height: 1.6,
            ),
          ),
        ),
        const SizedBox(height: 24),

        // What they're looking for
        if (_creatorServicesNeeded != null && _creatorServicesNeeded!.isNotEmpty) ...[
          _SectionTitle('What They\'re Looking For'),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: HomePage.accent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: HomePage.accent.withOpacity(0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.search,
                  color: HomePage.accentAlt,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _creatorServicesNeeded!,
                    style: const TextStyle(
                      color: HomePage.textPrimary,
                      fontSize: 15,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'If you can offer any of these skills, you might be a great match!',
            style: TextStyle(
              color: HomePage.textMuted,
              fontSize: 13,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 24),
        ]
        else if (_loadingProfile) ...[
          _SectionTitle('What They\'re Looking For'),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: HomePage.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: HomePage.line),
            ),
            child: const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],

        // Deliverables
        if (widget.deliverables.isNotEmpty) ...[
          _SectionTitle('What You\'ll Get'),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: HomePage.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: HomePage.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: widget.deliverables
                  .map((d) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.check_circle,
                              color: HomePage.success,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                d,
                                style: const TextStyle(
                                  color: HomePage.textPrimary,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 24),
        ],

        // Tags
        if (widget.tags.isNotEmpty) ...[
          _SectionTitle('Tags'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.tags
                .map((t) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: HomePage.surface,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: HomePage.line),
                      ),
                      child: Text(
                        t,
                        style: const TextStyle(
                          color: HomePage.textMuted,
                          fontSize: 13,
                        ),
                      ),
                    ))
                .toList(),
          ),
        ],
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildProfileView() {
    if (_loadingProfile) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(48),
          child: CircularProgressIndicator(),
        ),
      );
    }

    // Extract profile fields (matching user_profile_page.dart)
    final name = (_profileData?['fullName'] ?? _profileData?['displayName'] ?? widget.creatorName).toString().trim();
    final username = (_profileData?['username'] ?? '').toString().trim();
    final city = (_profileData?['city'] ?? '').toString().trim();
    final bio = (_profileData?['bio'] ?? '').toString().trim();
    final photoUrl = _profileData?['photoUrl'] ?? widget.creatorPhotoUrl;
    final timezone = (_profileData?['timezone'] ?? '').toString().trim();
    final verified = (_profileData?['verified'] ?? false) == true;
    final topRated = (_profileData?['topRated'] ?? false) == true;

    // Stats
    final swapsCompleted = (_profileData?['completed_swap_count'] ?? _profileData?['swapsCompleted'] ?? 0) as int;
    final swapCredits = (_profileData?['swap_credits'] ?? 0) as int;

    // Skills (as List of Maps)
    final skillsToOffer = (_profileData?['skillsToOffer'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    final servicesNeeded = (_profileData?['servicesNeeded'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Profile header card with banner
        Card(
          color: HomePage.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              // Gradient banner
              Container(
                height: 80,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF7C3AED), Color(0xFF4F46E5)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
              // Profile content
              Transform.translate(
                offset: const Offset(0, -40),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      // Avatar
                      CircleAvatar(
                        radius: 48,
                        backgroundColor: HomePage.bg,
                        child: CircleAvatar(
                          radius: 44,
                          backgroundColor: HomePage.surfaceAlt,
                          backgroundImage: photoUrl != null && photoUrl.toString().isNotEmpty
                              ? NetworkImage(photoUrl.toString())
                              : null,
                          child: photoUrl == null || photoUrl.toString().isEmpty
                              ? Text(
                                  name.isNotEmpty ? name[0].toUpperCase() : 'U',
                                  style: const TextStyle(
                                    color: HomePage.textMuted,
                                    fontSize: 32,
                                    fontWeight: FontWeight.w600,
                                  ),
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Name and badges
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              name.isEmpty ? 'User' : name,
                              style: const TextStyle(
                                color: HomePage.textPrimary,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (verified) ...[
                            const SizedBox(width: 8),
                            const Icon(Icons.verified, color: HomePage.success, size: 20),
                          ],
                          if (topRated) ...[
                            const SizedBox(width: 6),
                            const Icon(Icons.emoji_events, color: Color(0xFFF59E0B), size: 20),
                          ],
                        ],
                      ),
                      if (username.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          '@$username',
                          style: const TextStyle(color: HomePage.textMuted),
                        ),
                      ],
                      const SizedBox(height: 8),
                      // Location and timezone
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 16,
                        children: [
                          if (city.isNotEmpty)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.location_on_outlined, size: 16, color: HomePage.textMuted),
                                const SizedBox(width: 4),
                                Text(city, style: const TextStyle(color: HomePage.textMuted, fontSize: 13)),
                              ],
                            ),
                          if (timezone.isNotEmpty)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.access_time, size: 16, color: HomePage.textMuted),
                                const SizedBox(width: 4),
                                Text(timezone, style: const TextStyle(color: HomePage.textMuted, fontSize: 13)),
                              ],
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Stats row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _StatItem(value: '$swapsCompleted', label: 'Swaps'),
                          Container(
                            width: 1,
                            height: 30,
                            color: HomePage.line,
                            margin: const EdgeInsets.symmetric(horizontal: 20),
                          ),
                          _StatItem(value: '$swapCredits', label: 'Credits'),
                          Container(
                            width: 1,
                            height: 30,
                            color: HomePage.line,
                            margin: const EdgeInsets.symmetric(horizontal: 20),
                          ),
                          _StatItem(value: widget.rating.toStringAsFixed(1), label: 'Rating', icon: Icons.star, iconColor: Colors.amber),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Bio
        if (bio.isNotEmpty) ...[
          _SectionTitle('About'),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: HomePage.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: HomePage.line),
            ),
            child: Text(
              bio,
              style: const TextStyle(
                color: HomePage.textPrimary,
                fontSize: 15,
                height: 1.6,
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],

        // Skills they offer
        if (skillsToOffer.isNotEmpty) ...[
          _SectionTitle('Skills They Offer'),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: HomePage.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: HomePage.line),
            ),
            child: Column(
              children: skillsToOffer.map((skill) {
                final skillName = skill['name'] ?? skill['title'] ?? '';
                final skillLevel = skill['level'] ?? '';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, color: HomePage.success, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          skillName,
                          style: const TextStyle(color: HomePage.textPrimary, fontSize: 14),
                        ),
                      ),
                      if (skillLevel.toString().isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: HomePage.accent.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            skillLevel.toString(),
                            style: TextStyle(color: HomePage.accentAlt, fontSize: 11),
                          ),
                        ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 24),
        ],

        // What they need
        if (servicesNeeded.isNotEmpty) ...[
          _SectionTitle('What They\'re Looking For'),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: HomePage.accent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: HomePage.accent.withOpacity(0.3)),
            ),
            child: Column(
              children: servicesNeeded.map((need) {
                final needName = need['name'] ?? need['title'] ?? need.toString();
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(Icons.search, color: HomePage.accentAlt, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          needName.toString(),
                          style: const TextStyle(color: HomePage.textPrimary, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 24),
        ],

        // Other skills by this user
        if (_userSkills.isNotEmpty) ...[
          _SectionTitle('Other Skills by ${widget.creatorName}'),
          const SizedBox(height: 12),
          ...(_userSkills.map((skill) => _OtherSkillCard(
                title: skill['title'] ?? '',
                category: skill['category'] ?? '',
                description: skill['description'] ?? '',
                onTap: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SkillDetailPage(
                        title: skill['title'] ?? '',
                        description: skill['description'] ?? '',
                        category: skill['category'] ?? '',
                        difficulty: skill['difficulty'] ?? 'Beginner',
                        durationHours: skill['estimatedHours'] ?? 1,
                        mode: skill['deliveryFormat'] ?? 'Remote',
                        rating: (skill['rating'] ?? 4.5).toDouble(),
                        tags: List<String>.from(skill['tags'] ?? []),
                        deliverables: List<String>.from(skill['deliverables'] ?? []),
                        verified: skill['verified'] ?? false,
                        creatorUid: widget.creatorUid,
                        creatorName: widget.creatorName,
                        creatorPhotoUrl: widget.creatorPhotoUrl,
                        servicesNeeded: widget.servicesNeeded,
                      ),
                    ),
                  );
                },
              ))),
          const SizedBox(height: 24),
        ],

        // Swap History
        _SectionTitle('Swap History'),
        const SizedBox(height: 12),
        _buildSwapHistorySection(),

        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildSwapHistorySection() {
    if (_loadingSwapHistory) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: HomePage.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: HomePage.line),
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_swapHistory == null || _swapHistory!.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: HomePage.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: HomePage.line),
        ),
        child: Row(
          children: [
            Icon(Icons.history, color: HomePage.textMuted, size: 20),
            const SizedBox(width: 12),
            Text(
              'No completed swaps yet',
              style: TextStyle(color: HomePage.textMuted),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: HomePage.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: HomePage.line),
      ),
      child: Column(
        children: _swapHistory!.map((swap) {
          // Determine partner info
          final isRequester = swap.requesterUid == widget.creatorUid;
          final partnerName = isRequester
              ? swap.recipientProfile?.displayName
              : swap.requesterProfile?.displayName;
          final partnerPhoto = isRequester
              ? swap.recipientProfile?.photoUrl
              : swap.requesterProfile?.photoUrl;

          // Skills exchanged from this person's perspective
          final skillOffered = isRequester ? swap.requesterOffer : swap.requesterNeed;
          final skillReceived = isRequester ? swap.requesterNeed : swap.requesterOffer;

          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: swap == _swapHistory!.last ? Colors.transparent : HomePage.line,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: HomePage.surfaceAlt,
                      backgroundImage: partnerPhoto != null && partnerPhoto.isNotEmpty
                          ? NetworkImage(partnerPhoto)
                          : null,
                      child: partnerPhoto == null || partnerPhoto.isEmpty
                          ? Text(
                              (partnerName ?? 'U')[0].toUpperCase(),
                              style: const TextStyle(
                                color: HomePage.textPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
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
                            'Swap with ${partnerName ?? "Unknown"}',
                            style: const TextStyle(
                              color: HomePage.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          if (swap.completion?.finalHours != null)
                            Text(
                              '${swap.completion!.finalHours!.toStringAsFixed(1)} hours exchanged',
                              style: TextStyle(color: HomePage.textMuted, fontSize: 12),
                            ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: HomePage.success.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Completed',
                        style: TextStyle(
                          color: HomePage.success,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                if (skillOffered != null || skillReceived != null) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (skillOffered != null && skillOffered.isNotEmpty)
                        _swapSkillPill('Offered: $skillOffered', HomePage.accent),
                      if (skillReceived != null && skillReceived.isNotEmpty)
                        _swapSkillPill('Received: $skillReceived', const Color(0xFF0EA5E9)),
                    ],
                  ),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _swapSkillPill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  String _formatSkills(dynamic skills) {
    if (skills is String) return skills;
    if (skills is List) {
      return skills.map((s) {
        if (s is Map) {
          return s['name'] ?? s['title'] ?? s.toString();
        }
        return s.toString();
      }).join(', ');
    }
    return skills.toString();
  }
}

class _SegmentButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _SegmentButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? HomePage.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? Colors.white : HomePage.textMuted,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : HomePage.textMuted,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OtherSkillCard extends StatelessWidget {
  final String title;
  final String category;
  final String description;
  final VoidCallback onTap;

  const _OtherSkillCard({
    required this.title,
    required this.category,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: HomePage.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: HomePage.line),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _Pill(category),
                      const Spacer(),
                      const Icon(Icons.arrow_forward_ios, size: 14, color: HomePage.textMuted),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    style: const TextStyle(
                      color: HomePage.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: HomePage.textMuted,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: HomePage.textPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String value;
  final String label;
  final IconData? icon;
  final Color? iconColor;

  const _StatItem({
    required this.value,
    required this.label,
    this.icon,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: iconColor ?? HomePage.accentAlt),
              const SizedBox(width: 4),
            ],
            Text(
              value,
              style: const TextStyle(
                color: HomePage.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: HomePage.textMuted,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _InfoItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? iconColor;

  const _InfoItem({
    required this.icon,
    required this.label,
    required this.value,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: iconColor ?? HomePage.accentAlt, size: 24),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(color: HomePage.textMuted, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: HomePage.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final IconData? icon;
  final Color? color;

  const _Pill(this.text, {this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? const Color(0xFF6B7280);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: c.withOpacity(0.15),
        border: Border.all(color: HomePage.line),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: c),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            style: TextStyle(
              color: c,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
