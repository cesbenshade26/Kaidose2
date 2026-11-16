import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'Home.dart';
import 'AccessContacts.dart';
import 'GroupAvatar.dart';
import 'friend_request_service.dart';

// ─── Data ────────────────────────────────────────────────────────────────────

/// Same 16 topics as the tags on a Daily (kDailyTags in ManageDaily.dart), so
/// what someone picks here lines up with what Dailies are tagged with.
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
  {'label': 'Health',      'emoji': '🧘'},
  {'label': 'Finance',     'emoji': '💰'},
  {'label': 'Science',     'emoji': '🔬'},
  {'label': 'Comedy',      'emoji': '😂'},
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

  // Interests, one word, people you might know.
  static const int _totalPages = 3;
  int _page = 0;

  // Answers
  final Set<String> _interests = {};
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

  // People you might know
  final FriendRequestService _friends = FriendRequestService();
  _ContactsState _contactsState = _ContactsState.notAsked;
  List<_Person> _fromContacts = [];
  List<_Person> _popular = [];
  bool _loadingPopular = true;
  final Set<String> _requested = {};
  final Set<String> _sending = {};
  String? _myUsername;
  bool _saving = false;

  static const List<String> _subtitles = [
    '',
    'Sweet. One more thing —',
    'Almost there — find your people.',
  ];

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _setupAnimations(forward: true);
    _loadMe();
    _loadPopular();
    _checkContacts();
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

  Future<void> _loadMe() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc =
      await FirebaseFirestore.instance.collection('users').doc(uid).get();
      _myUsername = doc.data()?['username'] as String?;
    } catch (_) {}
  }

  /// Popular accounts: verified ones first, then the people whose clips get
  /// the most likes. Shown after contacts (or alone, without contacts).
  Future<void> _loadPopular() async {
    final me = FirebaseAuth.instance.currentUser?.uid;
    final out = <String, _Person>{};
    try {
      final db = FirebaseFirestore.instance;
      final results = await Future.wait([
        db.collection('users').where('verified', isEqualTo: true).limit(10).get(),
        db.collection('clips').orderBy('likeCount', descending: true).limit(80).get(),
      ]);
      for (final d in results[0].docs) {
        final name = d.data()['username'] as String?;
        if (d.id == me || name == null || name.isEmpty) continue;
        out[d.id] = _Person(d.id, name, 'Verified', verified: true);
      }
      // Total likes per creator across their most-liked clips.
      final likes = <String, int>{};
      final names = <String, String>{};
      for (final d in results[1].docs) {
        final data = d.data();
        final uid = data['creatorUid'] as String?;
        final name = data['creatorUsername'] as String?;
        if (uid == null || uid == me || name == null || name.isEmpty) continue;
        likes[uid] = (likes[uid] ?? 0) + ((data['likeCount'] as num?)?.toInt() ?? 0);
        names[uid] = name;
      }
      final ranked = likes.keys.toList()
        ..sort((a, b) => likes[b]!.compareTo(likes[a]!));
      for (final uid in ranked.take(20)) {
        if (out.containsKey(uid)) continue;
        final n = likes[uid]!;
        out[uid] = _Person(uid, names[uid]!,
            n > 0 ? 'Popular on Kaidose · ${_count(n)} likes' : 'Popular on Kaidose');
      }
    } catch (e) {
      print('InterestOnboarding: popular load error: $e');
    }
    if (mounted) {
      setState(() {
        _popular = out.values.toList();
        _loadingPopular = false;
      });
    }
  }

  static String _count(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  /// If contacts access was given before (e.g. reinstall), match right away.
  Future<void> _checkContacts() async {
    if (await AccessContacts.hasPermission()) await _matchContacts();
  }

  Future<void> _allowContacts() async {
    setState(() => _contactsState = _ContactsState.loading);
    final ok = await AccessContacts.requestAccess();
    if (!mounted) return;
    if (!ok) {
      setState(() => _contactsState = _ContactsState.denied);
      return;
    }
    await _matchContacts();
  }

  Future<void> _matchContacts() async {
    if (mounted) setState(() => _contactsState = _ContactsState.loading);
    final contacts = await AccessContacts.loadContacts();
    final matches = await AccessContacts.findOnKaidose(contacts);
    if (!mounted) return;
    setState(() {
      _fromContacts = matches
          .map((m) => _Person(
        m.uid,
        m.username,
        (m.contactName != null &&
            m.contactName!.toLowerCase() != m.username.toLowerCase())
            ? '${m.contactName} in your contacts'
            : 'In your contacts',
      ))
          .toList();
      _contactsState = _ContactsState.done;
    });
  }

  /// Sends a real friend request right away (same as Search's Add).
  Future<void> _add(_Person p) async {
    if (_requested.contains(p.uid) || _sending.contains(p.uid)) return;
    setState(() => _sending.add(p.uid));
    final result = await _friends.sendFriendRequest(
      toUserId: p.uid,
      toUsername: p.username,
      fromUsername: _myUsername ?? 'Someone',
    );
    if (!mounted) return;
    setState(() {
      _sending.remove(p.uid);
      // "Already sent" / "already friends" also count as done here.
      final err = '${result['error'] ?? ''}'.toLowerCase();
      if (result['success'] == true ||
          err.contains('already') ||
          err.contains('sent you')) {
        _requested.add(p.uid);
      }
    });
    if (result['success'] != true && !_requested.contains(p.uid) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't send that request. Try again.")),
      );
    }
  }

  bool get _canProceed {
    switch (_page) {
      case 0: return _interests.isNotEmpty;
      case 1: return _wordCtrl.text.trim().isNotEmpty;
      default: return true;
    }
  }

  Future<void> _advance({bool skip = false}) async {
    if (_transitioning) return;
    if (_page == _totalPages - 1) {
      await _finish();
      return;
    }

    final nextPage = _page + 1;

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
      // The one word is never shown; a Cloud Function turns it into a few
      // starting topics for the feed (onUserOneWord).
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'interests': _interests.toList(),
        'oneWord': _wordCtrl.text.trim(),
        'onboardingComplete': true,
        'onboardedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
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
      case 1: return _OneWordPage(controller: _wordCtrl);
      case 2: return _PeoplePage(
        contactsState: _contactsState,
        fromContacts: _fromContacts,
        popular: _popular,
        loadingPopular: _loadingPopular,
        requested: _requested,
        sending: _sending,
        onAllowContacts: _allowContacts,
        onAdd: _add,
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
                      borderRadius: BorderRadius.circular(14)),
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
            onTap: (!_saving && !_transitioning)
                ? () => _advance(skip: true)
                : null,
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

class _OneWordPage extends StatelessWidget {
  final TextEditingController controller;

  const _OneWordPage({required this.controller});

  @override
  Widget build(BuildContext context) {
    // Scrollable: when the keyboard opens there isn't room for the big
    // question + field, and a fixed Column overflowed (the striped error).
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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

enum _ContactsState { notAsked, loading, denied, done }

class _Person {
  final String uid;
  final String username;
  final String subtitle;
  final bool verified;
  const _Person(this.uid, this.username, this.subtitle, {this.verified = false});
}

/// "People you might know": first an ask for contacts, then friends found
/// in contacts, then popular accounts. "Add" sends a real friend request.
class _PeoplePage extends StatelessWidget {
  final _ContactsState contactsState;
  final List<_Person> fromContacts;
  final List<_Person> popular;
  final bool loadingPopular;
  final Set<String> requested;
  final Set<String> sending;
  final VoidCallback onAllowContacts;
  final ValueChanged<_Person> onAdd;

  const _PeoplePage({
    required this.contactsState,
    required this.fromContacts,
    required this.popular,
    required this.loadingPopular,
    required this.requested,
    required this.sending,
    required this.onAllowContacts,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final contactIds = fromContacts.map((p) => p.uid).toSet();
    final popularShown =
    popular.where((p) => !contactIds.contains(p.uid)).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      children: [
        const Text('People you might know',
            style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.black87)),
        const SizedBox(height: 6),
        Text('Add a few friends to get started.',
            style: TextStyle(fontSize: 15, color: Colors.grey[500])),
        const SizedBox(height: 20),

        // Contacts
        if (contactsState == _ContactsState.notAsked) _contactsCard(),
        if (contactsState == _ContactsState.loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(
                child: CircularProgressIndicator(color: Colors.cyan)),
          ),
        if (contactsState == _ContactsState.denied)
          _note('Contacts are off. You can turn them on later in your '
              'phone\'s Settings to find friends.'),
        if (contactsState == _ContactsState.done) ...[
          if (fromContacts.isEmpty)
            _note('None of your contacts are on Kaidose yet. '
                'Invite a few once you\'re in!')
          else ...[
            _sectionLabel('From your contacts'),
            ...fromContacts.map(_row),
            const SizedBox(height: 12),
          ],
        ],

        // Popular
        if (loadingPopular)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(
                child: CircularProgressIndicator(color: Colors.cyan)),
          )
        else if (popularShown.isNotEmpty) ...[
          _sectionLabel('Popular on Kaidose'),
          ...popularShown.map(_row),
        ] else if (fromContacts.isEmpty &&
            contactsState != _ContactsState.notAsked)
          _note('You\'re one of the first ones here 👋 '
              'Come back soon for suggestions!'),
      ],
    );
  }

  Widget _contactsCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.cyan.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.contacts_outlined,
                color: Colors.cyan, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Find friends from your contacts',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('Only used to find people you know on Kaidose.',
                    style: TextStyle(fontSize: 12.5, color: Colors.grey[600])),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onAllowContacts,
            style: TextButton.styleFrom(
              backgroundColor: Colors.cyan,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
            ),
            child: const Text('Allow',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(text,
        style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Colors.grey[600],
            letterSpacing: 0.3)),
  );

  Widget _note(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Text(text,
        style: TextStyle(fontSize: 14, color: Colors.grey[500], height: 1.35)),
  );

  Widget _row(_Person p) {
    final done = requested.contains(p.uid);
    final busy = sending.contains(p.uid);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          MemberAvatar(userId: p.uid, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(p.username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 15.5, fontWeight: FontWeight.w600)),
                    ),
                    if (p.verified) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.verified, size: 15, color: Colors.cyan),
                    ],
                  ],
                ),
                const SizedBox(height: 1),
                Text(p.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: Colors.grey[500])),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: (done || busy) ? null : () => onAdd(p),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 92,
              padding: const EdgeInsets.symmetric(vertical: 8),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: done ? Colors.grey[100] : Colors.cyan,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: done ? Colors.grey[300]! : Colors.cyan),
              ),
              child: busy
                  ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
                  : Text(
                done ? 'Requested' : 'Add',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: done ? Colors.grey[600] : Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}