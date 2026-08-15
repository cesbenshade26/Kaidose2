import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'Home.dart';

// ─── Data ────────────────────────────────────────────────────────────────────

const List<Map<String, dynamic>> _interestOptions = [
  {'label': 'Sports',      'emoji': '🏆'},
  {'label': 'Music',       'emoji': '🎵'},
  {'label': 'Gaming',      'emoji': '🎮'},
  {'label': 'Fitness',     'emoji': '💪'},
  {'label': 'Food',        'emoji': '🍕'},
  {'label': 'Travel',      'emoji': '✈️'},
  {'label': 'Art',         'emoji': '🎨'},
  {'label': 'Fashion',     'emoji': '👗'},
  {'label': 'Nature',      'emoji': '🌿'},
  {'label': 'Tech',        'emoji': '💻'},
  {'label': 'Movies / TV', 'emoji': '🎬'},
  {'label': 'Books',       'emoji': '📚'},
];

const List<Map<String, dynamic>> _vibeOptions = [
  {'label': 'Chill',         'emoji': '😌'},
  {'label': 'Competitive',   'emoji': '🔥'},
  {'label': 'Creative',      'emoji': '✨'},
  {'label': 'Adventurous',   'emoji': '🧗'},
  {'label': 'Funny',         'emoji': '😂'},
  {'label': 'Motivated',     'emoji': '🚀'},
  {'label': 'Social',        'emoji': '🤝'},
  {'label': 'Introspective', 'emoji': '🌙'},
];

// ─── Entry point ─────────────────────────────────────────────────────────────

class InterestOnboarding extends StatelessWidget {
  const InterestOnboarding({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(child: _OnboardingFlow()),
    );
  }
}

// ─── Flow controller ──────────────────────────────────────────────────────────

class _OnboardingFlow extends StatefulWidget {
  const _OnboardingFlow();

  @override
  State<_OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<_OnboardingFlow>
    with SingleTickerProviderStateMixin {

  static const int _totalPages = 4;
  int _page = 0;

  // Answers
  final Set<String> _interests = {};
  final Set<String> _vibes = {};
  final TextEditingController _wordCtrl = TextEditingController();

  // Slide animation
  late final AnimationController _animCtrl;
  late Animation<Offset> _slideIn;
  late Animation<Offset> _slideOut;
  bool _transitioning = false;
  Widget? _outgoingPage;

  // Chat subtitle
  String _subtitle = '';
  double _subtitleOpacity = 0;

  // Follow suggestions
  List<Map<String, dynamic>> _users = [];
  final Set<String> _followed = {};
  bool _loadingUsers = true;
  bool _saving = false;

  static const List<String> _subtitles = [
    '',
    'Sweet. Now, what\'s your vibe?',
    'Love it. One more thing —',
    'Almost there — a few people you might like.',
  ];

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _setupAnimations(forward: true);
    _loadUsers();
    _wordCtrl.addListener(() => setState(() {}));
  }

  void _setupAnimations({required bool forward}) {
    _slideIn = Tween<Offset>(
      begin: Offset(forward ? 1.2 : -1.2, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));

    _slideOut = Tween<Offset>(
      begin: Offset.zero,
      end: Offset(forward ? -1.2 : 1.2, 0),
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeInCubic));
  }

  Future<void> _loadUsers() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .limit(30)
          .get();
      final list = snap.docs
          .where((d) => d.id != uid)
          .map((d) => <String, dynamic>{'uid': d.id, ...d.data()})
          .toList();
      if (mounted) setState(() { _users = list; _loadingUsers = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingUsers = false);
    }
  }

  bool get _canProceed {
    switch (_page) {
      case 0: return _interests.isNotEmpty;
      case 1: return _vibes.isNotEmpty;
      case 2: return _wordCtrl.text.trim().isNotEmpty;
      default: return true;
    }
  }

  Future<void> _advance({bool skip = false}) async {
    if (_transitioning) return;
    if (_page == _totalPages - 1 || skip && _page == _totalPages - 1) {
      await _finish();
      return;
    }

    final nextPage = skip ? _page + 1 : _page + 1;

    setState(() {
      _transitioning = true;
      _outgoingPage = _buildPage(_page);
      _subtitle = _subtitles[nextPage];
      _subtitleOpacity = 0;
    });

    _setupAnimations(forward: true);
    _animCtrl.reset();

    // Fade subtitle in while slide happens
    _animCtrl.forward();
    // Subtitle fade
    for (double t = 0; t <= 1; t += 0.1) {
      await Future.delayed(const Duration(milliseconds: 20));
      if (mounted) setState(() => _subtitleOpacity = t.clamp(0.0, 1.0));
    }
    await _animCtrl.forward();

    if (mounted) {
      setState(() {
        _page = nextPage;
        _transitioning = false;
        _outgoingPage = null;
      });
      // Hold subtitle briefly then fade out
      await Future.delayed(const Duration(milliseconds: 800));
      for (double t = 1; t >= 0; t -= 0.1) {
        await Future.delayed(const Duration(milliseconds: 30));
        if (mounted) setState(() => _subtitleOpacity = t.clamp(0.0, 1.0));
      }
      if (mounted) setState(() => _subtitle = '');
    }
  }

  Future<void> _goBack() async {
    if (_transitioning || _page == 0) return;

    setState(() {
      _transitioning = true;
      _outgoingPage = _buildPage(_page);
      _subtitle = '';
      _subtitleOpacity = 0;
    });

    _setupAnimations(forward: false);
    _animCtrl.reset();
    await _animCtrl.forward();

    if (mounted) {
      setState(() {
        _page = _page - 1;
        _transitioning = false;
        _outgoingPage = null;
      });
    }
  }

  Future<void> _finish() async {
    setState(() => _saving = true);
    await _save();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const HomeScreen(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  Future<void> _save() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'interests': _interests.toList(),
        'vibes': _vibes.toList(),
        'oneWord': _wordCtrl.text.trim(),
        'onboardingComplete': true,
        'onboardedAt': FieldValue.serverTimestamp(),
      });
      if (_followed.isNotEmpty) {
        final batch = FirebaseFirestore.instance.batch();
        for (final fid in _followed) {
          batch.set(
            FirebaseFirestore.instance.collection('users').doc(uid).collection('following').doc(fid),
            {'followedAt': FieldValue.serverTimestamp()},
          );
          batch.set(
            FirebaseFirestore.instance.collection('users').doc(fid).collection('followers').doc(uid),
            {'followedAt': FieldValue.serverTimestamp()},
          );
        }
        await batch.commit();
      }
    } catch (e) {
      print('InterestOnboarding: save error: $e');
    }
  }

  // ─── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Top bar: back + progress dots
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 16, 0),
          child: Row(
            children: [
              AnimatedOpacity(
                opacity: _page > 0 ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: IconButton(
                  icon: Icon(Icons.arrow_back_ios,
                      size: 18, color: Colors.grey[400]),
                  onPressed: _page > 0 ? _goBack : null,
                ),
              ),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_totalPages, (i) {
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: i == _page ? 22 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == _page ? Colors.cyan : Colors.grey[300],
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(width: 48), // balance the back button
            ],
          ),
        ),

        // Chat subtitle
        AnimatedOpacity(
          opacity: _subtitleOpacity,
          duration: const Duration(milliseconds: 100),
          child: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
            child: Text(
              _subtitle,
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey[500],
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ),

        // Slide area
        Expanded(
          child: ClipRect(
            child: Stack(
              children: [
                // Outgoing
                if (_transitioning && _outgoingPage != null)
                  SlideTransition(
                    position: _slideOut,
                    child: _outgoingPage!,
                  ),
                // Incoming
                SlideTransition(
                  position: _transitioning
                      ? _slideIn
                      : AlwaysStoppedAnimation(Offset.zero),
                  child: _buildPage(_page),
                ),
              ],
            ),
          ),
        ),

        // Bottom CTA
        _buildBottom(),
      ],
    );
  }

  Widget _buildPage(int index) {
    switch (index) {
      case 0: return _InterestsPage(
        selected: _interests,
        onToggle: (label) => setState(() {
          _interests.contains(label)
              ? _interests.remove(label)
              : _interests.add(label);
        }),
      );
      case 1: return _VibePage(
        selected: _vibes,
        onToggle: (label) => setState(() {
          if (_vibes.contains(label)) {
            _vibes.remove(label);
          } else if (_vibes.length < 3) {
            _vibes.add(label);
          }
        }),
      );
      case 2: return _OneWordPage(controller: _wordCtrl);
      case 3: return _FollowPage(
        users: _users,
        followed: _followed,
        loading: _loadingUsers,
        onToggle: (uid) => setState(() {
          _followed.contains(uid)
              ? _followed.remove(uid)
              : _followed.add(uid);
        }),
      );
      default: return const SizedBox();
    }
  }

  Widget _buildBottom() {
    final isLast = _page == _totalPages - 1;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            height: 54,
            child: AnimatedOpacity(
              opacity: _canProceed ? 1.0 : 0.35,
              duration: const Duration(milliseconds: 200),
              child: ElevatedButton(
                onPressed: (_canProceed && !_saving && !_transitioning)
                    ? () => _advance()
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyan,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.cyan,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                child: _saving
                    ? const SizedBox(
                  width: 22, height: 22,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2.5),
                )
                    : Text(
                  isLast ? 'Let\'s go 🎉' : 'Next',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: !_saving ? () => _advance(skip: true) : null,
            child: Text(
              'Skip',
              style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[400],
                  fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _wordCtrl.dispose();
    super.dispose();
  }
}

// ─── Page widgets ─────────────────────────────────────────────────────────────

class _InterestsPage extends StatelessWidget {
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  const _InterestsPage({required this.selected, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('What are you into?',
              style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87)),
          const SizedBox(height: 6),
          Text('Pick as many as you like.',
              style: TextStyle(fontSize: 15, color: Colors.grey[500])),
          const SizedBox(height: 24),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _interestOptions.map((opt) {
              final label = opt['label'] as String;
              final sel = selected.contains(label);
              return GestureDetector(
                onTap: () => onToggle(label),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 11),
                  decoration: BoxDecoration(
                    color: sel ? Colors.cyan : Colors.grey[100],
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                        color: sel ? Colors.cyan : Colors.grey[300]!,
                        width: 1.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(opt['emoji'] as String,
                          style: const TextStyle(fontSize: 17)),
                      const SizedBox(width: 7),
                      Text(label,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: sel ? Colors.white : Colors.black87)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _VibePage extends StatelessWidget {
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  const _VibePage({required this.selected, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('What\'s your vibe?',
              style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87)),
          const SizedBox(height: 6),
          Text('Pick up to 3.',
              style: TextStyle(fontSize: 15, color: Colors.grey[500])),
          const SizedBox(height: 24),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 2.5,
            children: _vibeOptions.map((opt) {
              final label = opt['label'] as String;
              final sel = selected.contains(label);
              final maxed = selected.length >= 3 && !sel;
              return GestureDetector(
                onTap: maxed ? null : () => onToggle(label),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  decoration: BoxDecoration(
                    color: sel
                        ? Colors.cyan
                        : maxed
                        ? Colors.grey[50]
                        : Colors.grey[100],
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: sel ? Colors.cyan : Colors.grey[300]!,
                        width: 1.5),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(opt['emoji'] as String,
                          style: const TextStyle(fontSize: 20)),
                      const SizedBox(width: 8),
                      Text(label,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: sel
                                  ? Colors.white
                                  : maxed
                                  ? Colors.grey[400]
                                  : Colors.black87)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _OneWordPage extends StatelessWidget {
  final TextEditingController controller;

  const _OneWordPage({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'If you had one word\nto describe yourself,\nwhat would it be?',
            style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
                height: 1.35),
          ),
          const SizedBox(height: 36),
          TextField(
            controller: controller,
            maxLength: 20,
            textCapitalization: TextCapitalization.words,
            autofocus: false,
            style: const TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.bold,
                color: Colors.cyan),
            decoration: InputDecoration(
              counterText: '',
              hintText: 'Type here...',
              hintStyle: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[300]),
              enabledBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey, width: 1.5)),
              focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.cyan, width: 2.5)),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'One word. No pressure — just how you\'d introduce yourself.',
            style: TextStyle(fontSize: 13, color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }
}

class _FollowPage extends StatelessWidget {
  final List<Map<String, dynamic>> users;
  final Set<String> followed;
  final bool loading;
  final ValueChanged<String> onToggle;

  const _FollowPage({
    required this.users,
    required this.followed,
    required this.loading,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('People you might like',
                  style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87)),
              const SizedBox(height: 6),
              Text('Follow a few to get started.',
                  style: TextStyle(fontSize: 15, color: Colors.grey[500])),
              const SizedBox(height: 16),
            ],
          ),
        ),
        Expanded(
          child: loading
              ? const Center(
              child: CircularProgressIndicator(color: Colors.cyan))
              : users.isEmpty
              ? Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'You\'re one of the first ones here 👋\nCome back soon for suggestions!',
                style: TextStyle(
                    color: Colors.grey[500], fontSize: 15),
                textAlign: TextAlign.center,
              ),
            ),
          )
              : ListView.builder(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            itemCount: users.length,
            itemBuilder: (context, i) {
              final user = users[i];
              final uid = user['uid'] as String;
              final username =
                  (user['username'] as String?) ?? 'Unknown';
              final isFollowed = followed.contains(uid);
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: Colors.grey[200]!, width: 1),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.cyan.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          username.isNotEmpty
                              ? username[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.cyan[700]),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(username,
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600)),
                    ),
                    GestureDetector(
                      onTap: () => onToggle(uid),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 8),
                        decoration: BoxDecoration(
                          color: isFollowed
                              ? Colors.grey[100]
                              : Colors.cyan,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: isFollowed
                                  ? Colors.grey[300]!
                                  : Colors.cyan),
                        ),
                        child: Text(
                          isFollowed ? 'Following' : 'Follow',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isFollowed
                                  ? Colors.grey[600]
                                  : Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}