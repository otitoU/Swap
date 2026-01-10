import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'landing_page.dart';
import 'dart:async'; // for TimeoutException
import '../services/search_service.dart';
// import 'post_skill_page.dart'; // no longer used directly here
import '../services/auth_service.dart';
import '../widgets/app_sidebar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_profile_page.dart';
import 'skill_detail_page.dart';
// Removed debug-only imports (seed/upsert/test helpers)

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  // ---- Theme (same palette family you’ve been using)
  static const Color bg = Color(0xFF000000);
  static const Color sidebar = Color(0xFF0A0A0C);
  static const Color surface = Color(0xFF0F0F11);
  static const Color surfaceAlt = Color(0xFF111113);
  static const Color card = Color(0xFF0F0F11);
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textMuted = Color(0xFFA1A1AA);
  static const Color textSecondary = Color(0xFF71717A);
  static const Color line = Color(0xFF27272A);
  static const Color accent = Color(0xFF7C3AED); // purple
  static const Color accentAlt = Color(0xFF9F67FF);
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _searchService = SearchService();
  bool _loadingSearch = false;
  List<SearchResult> _searchResults = [];
  String _currentQuery = '';

  Future<void> _handleSearch(String query) async {
    final q = query.trim();
    // if empty, clear results and return to default display
    if (q.isEmpty) {
      if (mounted)
        setState(() {
          _searchResults = [];
          _currentQuery = '';
        });
      return;
    }
    setState(() {
      _loadingSearch = true;
      _searchResults = [];
    });
    try {
      // Attempt search with reasonable timeout
      final res = await _searchService.search(
        q,
        mode: 'offers',
        limit: 10,
        timeout: const Duration(seconds: 10),
      );
      if (mounted)
        setState(() {
          _searchResults = res;
          _currentQuery = q;
        });
    } catch (e) {
      // Silently handle errors - just log them
      debugPrint('Search error for "$q": $e');
      if (mounted) {
        setState(() {
          _searchResults = [];
          _currentQuery = q;
        });
      }
    } finally {
      if (mounted) setState(() => _loadingSearch = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Local aliases for theme tokens (defined on the widget class)
    final bg = HomePage.bg;
    final surface = HomePage.surface;
    // Removed unused variable surfaceAlt; use HomePage.surfaceAlt directly where needed.
    final card = HomePage.card;
    final textPrimary = HomePage.textPrimary;
    final textMuted = HomePage.textMuted;
    final line = HomePage.line;
    final accent = HomePage.accent;
    final accentAlt = HomePage.accentAlt;

    final theme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.dark,
        surface: surface,
        background: bg,
        primary: accent,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        foregroundColor: textPrimary,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderSide: BorderSide(color: line),
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: line),
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: accent),
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
        hintStyle: TextStyle(color: textMuted),
        labelStyle: TextStyle(color: textMuted),
      ),
      chipTheme: ChipThemeData(
        side: BorderSide(color: line),
        backgroundColor: surface,
        selectedColor: const Color(0xFF1A1333),
        checkmarkColor: accentAlt,
        labelStyle: TextStyle(color: textPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      dividerColor: line,
      cardTheme: CardThemeData(
        color: card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: line),
        ),
        margin: const EdgeInsets.all(0), // optional, matches tight layout
      ),
    );

    return Theme(
      data: theme,
      child: Scaffold(
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AppSidebar(active: 'Home'),
            Expanded(
              child: Column(
                children: [
                  _TopBar(onSearch: _handleSearch),
                  if (_loadingSearch)
                    const LinearProgressIndicator(minHeight: 3),
                  Expanded(
                    child: _DiscoverPane(
                      searchResults: _searchResults,
                      onSearch: _handleSearch,
                      currentQuery: _currentQuery,
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

/* =============================== (Removed Sidebar) =============================== */
// Sidebar widget removed; navigation handled by AppSidebar in its own file.

// Removed _NavItem (unused after Sidebar removal)

/* ============================= DISCOVER PANE ============================= */

class _DiscoverPane extends StatefulWidget {
  _DiscoverPane({
    Key? key,
    this.searchResults,
    this.onSearch,
    this.currentQuery,
  }) : super(key: key);

  final List<SearchResult>? searchResults;
  final ValueChanged<String>? onSearch;
  final String? currentQuery;

  @override
  State<_DiscoverPane> createState() => _DiscoverPaneState();
}

class _DiscoverPaneState extends State<_DiscoverPane> {
  late final TextEditingController _searchCtrl;
  List<_Skill> skills = [];
  bool _loadingSkills = true;

  final List<String> categories = const [
    'All Skills',
    'Design',
    'Coding',
    'Writing',
    'Language',
    'Tutoring',
    'Music',
  ];
  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController();
    _loadSkillsFromFirestore();
  }

  Future<void> _loadSkillsFromFirestore() async {
    try {
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      debugPrint('⭐ Loading skills for user: $currentUid');

      final snapshot = await FirebaseFirestore.instance
          .collection('skills')
          .get();

      debugPrint('⭐ Found ${snapshot.docs.length} skill documents');

      // Collect creator UIDs that need profile fetch (no servicesNeeded in skill)
      final creatorUidsNeedingProfile = <String>{};
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final uid = data['creatorUid'] as String?;
        final hasServicesNeeded = data['creatorServicesNeeded'] != null &&
            (data['creatorServicesNeeded'] as String).isNotEmpty;
        if (uid != null && uid.isNotEmpty && !hasServicesNeeded) {
          creatorUidsNeedingProfile.add(uid);
        }
      }

      // Batch fetch profiles to get servicesNeeded
      final profilesMap = <String, Map<String, dynamic>>{};
      if (creatorUidsNeedingProfile.isNotEmpty) {
        try {
          final uidList = creatorUidsNeedingProfile.toList();
          for (var i = 0; i < uidList.length; i += 10) {
            final batch = uidList.sublist(
              i,
              i + 10 > uidList.length ? uidList.length : i + 10,
            );
            final profilesSnapshot = await FirebaseFirestore.instance
                .collection('profiles')
                .where(FieldPath.documentId, whereIn: batch)
                .get();
            for (final doc in profilesSnapshot.docs) {
              profilesMap[doc.id] = doc.data();
            }
          }
          debugPrint('⭐ Fetched ${profilesMap.length} profiles for servicesNeeded');
        } catch (e) {
          debugPrint('⭐ Error fetching profiles: $e');
        }
      }

      final loadedSkills = snapshot.docs.map((doc) {
        final data = doc.data();
        final creatorUid = data['creatorUid'] ?? '';

        // Get servicesNeeded - first from skill, then from profile
        String? servicesNeeded = data['creatorServicesNeeded'] as String?;
        if ((servicesNeeded == null || servicesNeeded.isEmpty) &&
            profilesMap.containsKey(creatorUid)) {
          final profile = profilesMap[creatorUid]!;
          final rawNeeds = profile['servicesNeeded'] ?? profile['services_needed'];
          if (rawNeeds is String) {
            servicesNeeded = rawNeeds;
          } else if (rawNeeds is List) {
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

        return _Skill(
          title: data['title'] ?? '',
          category: data['category'] ?? 'other',
          description: data['description'] ?? '',
          difficulty: data['difficulty'] ?? 'Beginner',
          durationHours: data['estimatedHours'] ?? 1,
          mode: data['deliveryFormat'] ?? 'Remote',
          rating: (data['rating'] ?? 4.5).toDouble(),
          tags: List<String>.from(data['tags'] ?? []),
          deliverables: List<String>.from(data['deliverables'] ?? []),
          verified: data['verified'] ?? false,
          isNew: data['isNew'] ?? false,
          creatorUid: creatorUid,
          creatorName: data['creatorName'] ?? 'Anonymous',
          creatorPhotoUrl: data['creatorPhotoUrl'] as String?,
          servicesNeeded: servicesNeeded,
        );
      }).toList();

      // Filter out current user's own skills - marketplace should show others' skills
      final filteredSkills = loadedSkills.where((skill) => skill.creatorUid != currentUid).toList();
      debugPrint('⭐ Total skills loaded: ${loadedSkills.length}, showing ${filteredSkills.length} (excluding own)');

      if (mounted) {
        setState(() {
          skills = filteredSkills;
          _loadingSkills = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading skills: $e');
      if (mounted) {
        setState(() => _loadingSkills = false);
      }
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searchResults = widget.searchResults;

    // If a search was performed, show backend results instead of the
    // default curated skill grid.
    if (searchResults != null && searchResults.isNotEmpty) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Search results' +
                          (widget.currentQuery?.isNotEmpty == true
                              ? ' for "${widget.currentQuery}"'
                              : ''),
                      style: TextStyle(
                        color: HomePage.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      _searchCtrl.clear();
                      widget.onSearch?.call('');
                    },
                    icon: const Icon(
                      Icons.close,
                      size: 18,
                      color: Colors.white,
                    ),
                    label: const Text('Close'),
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final maxW = constraints.maxWidth;
                    final crossAxisCount = maxW >= 1200
                        ? 3
                        : (maxW >= 780 ? 2 : 1);
                    return GridView.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: 18,
                        mainAxisSpacing: 18,
                        mainAxisExtent: 240,
                      ),
                      itemCount: searchResults.length,
                      itemBuilder: (context, i) {
                        final r = searchResults[i];
                        return InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => UserProfilePage(
                                  uid: r.uid,
                                  initialName: r.displayName.isNotEmpty
                                      ? r.displayName
                                      : r.email,
                                ),
                              ),
                            );
                          },
                          borderRadius: BorderRadius.circular(14),
                          child: Card(
                            color: HomePage.surface,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(color: HomePage.line),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      // Profile picture
                                      CircleAvatar(
                                        radius: 20,
                                        backgroundColor: HomePage.surfaceAlt,
                                        backgroundImage: r.photoUrl != null && r.photoUrl!.isNotEmpty
                                            ? NetworkImage(r.photoUrl!)
                                            : null,
                                        child: r.photoUrl == null || r.photoUrl!.isEmpty
                                            ? Text(
                                                (r.displayName.isNotEmpty ? r.displayName : r.email)
                                                    .characters.first.toUpperCase(),
                                                style: const TextStyle(
                                                  color: HomePage.textMuted,
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              )
                                            : null,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              r.displayName.isNotEmpty
                                                  ? r.displayName
                                                  : r.email,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: HomePage.textPrimary,
                                                fontWeight: FontWeight.w800,
                                                fontSize: 15,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 6,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: HomePage.surfaceAlt,
                                                borderRadius: BorderRadius.circular(999),
                                                border: Border.all(color: HomePage.line),
                                              ),
                                              child: const Text(
                                                'profile',
                                                style: TextStyle(
                                                  color: HomePage.textMuted,
                                                  fontSize: 10,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  const SizedBox(height: 6),
                                  Expanded(
                                    child: Text(
                                      r.bio,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: HomePage.textMuted),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          r.skillsToOffer,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: HomePage.textMuted,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.star,
                                            color: Colors.amber,
                                            size: 18,
                                          ),
                                          Text(
                                            r.score.toStringAsFixed(2),
                                            style: TextStyle(
                                              color: HomePage.textPrimary,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
              ).copyWith(top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 6),
                  const Text(
                    'Find Services to Swap',
                    style: TextStyle(
                      color: HomePage.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 28,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Find amazing services and skills to learn and swap from our community',
                    style: TextStyle(color: HomePage.textMuted, fontSize: 13),
                  ),
                  const SizedBox(height: 18),

                  // Search + Filters row (secondary)
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          onSubmitted: (v) => widget.onSearch?.call(v),
                          onChanged: (v) {
                            setState(() {});
                            if (v.trim().isEmpty) widget.onSearch?.call('');
                          },
                          decoration: InputDecoration(
                            prefixIcon: Icon(
                              Icons.search,
                              color: HomePage.textMuted,
                            ),
                            hintText: 'Search skills...',
                            suffixIcon: _searchCtrl.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      widget.onSearch?.call('');
                                    },
                                  )
                                : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: () {},
                        icon: const Icon(
                          Icons.tune_rounded,
                          color: HomePage.textMuted,
                        ),
                        label: const Text('Filters'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: HomePage.line),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          backgroundColor: HomePage.surface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Category chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (int i = 0; i < categories.length; i++) ...[
                          _CategoryChip(label: categories[i], selected: i == 0),
                          const SizedBox(width: 10),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),

          // Grid of skill cards
          SliverPadding(
            padding: const EdgeInsets.symmetric(
              horizontal: 24,
            ).copyWith(bottom: 24),
            sliver: _loadingSkills
                ? const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  )
                : skills.isEmpty
                ? const SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.search_off,
                            size: 64,
                            color: HomePage.textMuted,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'No skills posted yet',
                            style: TextStyle(
                              color: HomePage.textMuted,
                              fontSize: 18,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Be the first to share your skills!',
                            style: TextStyle(
                              color: HomePage.textMuted,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : SliverLayoutBuilder(
                    builder: (context, constraints) {
                      final maxW = constraints.crossAxisExtent;
                      // nice responsive column count
                      final crossAxisCount = maxW >= 1200
                          ? 3
                          : (maxW >= 780 ? 2 : 1);

                      return SliverGrid.builder(
                        itemCount: skills.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          mainAxisSpacing: 14,
                          crossAxisSpacing: 14,
                          mainAxisExtent: 190,
                        ),
                        itemBuilder: (context, i) =>
                            _SkillCard(skill: skills[i]),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/* ============================== WIDGET PIECES ============================= */

class _CategoryChip extends StatefulWidget {
  const _CategoryChip({required this.label, this.selected = false});
  final String label;
  final bool selected;

  @override
  State<_CategoryChip> createState() => _CategoryChipState();
}

class _CategoryChipState extends State<_CategoryChip> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: widget.selected
              ? HomePage.accent.withOpacity(0.15)
              : _hovering
                  ? HomePage.surfaceAlt
                  : HomePage.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: widget.selected
                ? HomePage.accent.withOpacity(0.3)
                : _hovering
                    ? HomePage.line
                    : HomePage.line.withOpacity(0.5),
          ),
        ),
        child: Text(
          widget.label,
          style: TextStyle(
            color: widget.selected ? HomePage.accentAlt : HomePage.textPrimary,
            fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _SkillCard extends StatelessWidget {
  const _SkillCard({required this.skill});
  final _Skill skill;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SkillDetailPage(
              title: skill.title,
              description: skill.description,
              category: skill.category,
              difficulty: skill.difficulty,
              durationHours: skill.durationHours,
              mode: skill.mode,
              rating: skill.rating,
              tags: skill.tags,
              deliverables: skill.deliverables,
              verified: skill.verified,
              creatorUid: skill.creatorUid,
              creatorName: skill.creatorName,
              creatorPhotoUrl: skill.creatorPhotoUrl,
              servicesNeeded: skill.servicesNeeded,
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: HomePage.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: HomePage.line.withOpacity(0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: category + rating
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: HomePage.bg,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    skill.category,
                    style: const TextStyle(color: HomePage.textMuted, fontSize: 11, fontWeight: FontWeight.w500),
                  ),
                ),
                if (skill.isNew) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF34C759).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('NEW', style: TextStyle(color: Color(0xFF34C759), fontSize: 9, fontWeight: FontWeight.w700)),
                  ),
                ],
                const Spacer(),
                const Icon(Icons.star_rounded, size: 14, color: Color(0xFFFFD60A)),
                const SizedBox(width: 3),
                Text(skill.rating.toStringAsFixed(1), style: const TextStyle(color: HomePage.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 10),

            // Title
            Text(
              skill.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: HomePage.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 15,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 6),

            // Description
            Text(
              skill.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: HomePage.textMuted, fontSize: 12, height: 1.4),
            ),
            const Spacer(),

            // Bottom row: creator + swap button
            Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: const Color(0xFF2C2C2E),
                  backgroundImage: skill.creatorPhotoUrl != null && skill.creatorPhotoUrl!.isNotEmpty
                      ? NetworkImage(skill.creatorPhotoUrl!)
                      : null,
                  child: skill.creatorPhotoUrl == null || skill.creatorPhotoUrl!.isEmpty
                      ? Text(
                          skill.creatorName.isNotEmpty ? skill.creatorName[0].toUpperCase() : 'U',
                          style: const TextStyle(color: HomePage.textMuted, fontSize: 10, fontWeight: FontWeight.w600),
                        )
                      : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    skill.creatorName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: HomePage.textMuted, fontSize: 12),
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    if (skill.creatorUid.isNotEmpty) {
                      showSwapRequestDialog(
                        context,
                        recipientUid: skill.creatorUid,
                        recipientName: skill.creatorName,
                        preSelectedSkill: skill.title,
                      );
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: HomePage.accent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('Swap', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, {this.icon, this.color});
  final String text;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? const Color(0xFF6B7280); // gray badge by default
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.withOpacity(.15),
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

/* ================================ MODELS ================================= */

class _Skill {
  final String title;
  final String category; // small label (music/writing/coding/etc)
  final String description;
  final String difficulty; // Beginner / Intermediate / Advanced
  final int durationHours;
  final String mode; // Remote / In-person / Both
  final double rating;
  final List<String> tags;
  final List<String> deliverables; // What they'll deliver
  final bool verified;
  final bool isNew;
  final String creatorUid; // Link to profile
  final String creatorName;
  final String? creatorPhotoUrl; // Creator's profile picture
  final String? servicesNeeded; // What the creator is looking for

  _Skill({
    required this.title,
    required this.category,
    required this.description,
    this.difficulty = 'Beginner',
    required this.durationHours,
    required this.mode,
    required this.rating,
    required this.tags,
    this.deliverables = const [],
    this.verified = false,
    this.isNew = false,
    this.creatorUid = '',
    this.creatorName = '',
    this.creatorPhotoUrl,
    this.servicesNeeded,
  });
}

class _TopBar extends StatelessWidget implements PreferredSizeWidget {
  const _TopBar({this.onSearch});

  final ValueChanged<String>? onSearch;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: preferredSize.height,
      color: HomePage.bg,
      padding: const EdgeInsets.fromLTRB(24, 10, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 44,
              child: TextField(
                onSubmitted: (v) => onSearch?.call(v),
                decoration: InputDecoration(
                  hintText: 'Search skills...',
                  prefixIcon: const Icon(
                    Icons.search,
                    color: HomePage.textMuted,
                  ),
                  filled: true,
                  fillColor: HomePage.surface,
                  contentPadding: EdgeInsets.zero,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999),
                    borderSide: BorderSide(color: HomePage.line),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999),
                    borderSide: BorderSide(color: HomePage.line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999),
                    borderSide: BorderSide(color: HomePage.accent),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                tooltip: 'Notifications',
                icon: const Icon(Icons.notifications_none_rounded),
                onPressed: () {},
              ),
              Positioned(
                right: 10,
                top: 10,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFF22C55E),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await AuthService.instance.signOut();
              if (!context.mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LandingPage()),
                (route) => false,
              );
            },
          ),
        ],
      ),
    );
  }
}
