import 'package:flutter/material.dart';
import 'AppColors.dart';
import 'Moderation.dart' show kSupportEmail;
import 'SettingsWidgets.dart';

/// Settings → Help & About → Community Guidelines. Read-only: people
/// agree to these with the Terms at sign-up. Keep this in step with
/// CONTENT_POLICY in index.js (what the AI checker removes and limits).
class CommunityGuidelinesScreen extends StatelessWidget {
  const CommunityGuidelinesScreen({Key? key}) : super(key: key);

  static Future<void> open(BuildContext context) => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const CommunityGuidelinesScreen()),
  );

  static const _rules = <_Rule>[
    _Rule(
      icon: Icons.no_adult_content_outlined,
      title: 'Keep it appropriate',
      about: 'Kaidose is for teens and adults, so no sexual content of any kind.',
      ok: [
        'Swimwear, gym and sports clothes',
        'Art, memes, sports hits and injuries',
        'Violence in movies, shows and games',
      ],
      notOk: [
        'Nudity or sexual content',
        'Anything sexual involving someone under 18 (reported right away)',
        'Graphic violence or gore',
      ],
    ),
    _Rule(
      icon: Icons.favorite_border_rounded,
      title: 'Be kind',
      about: 'Joke around all you want, just don\'t aim it at who someone is.',
      ok: [
        'Cursing, crude jokes, dark humor and edgy memes',
        'Roasting your friends when it\'s all in fun',
      ],
      notOk: [
        'Slurs or hate toward race, religion, sexuality, gender identity or disability',
        'Bullying or harassing someone',
        'Real threats against a real person',
        'Posting someone\'s private info, like where they live',
      ],
    ),
    _Rule(
      icon: Icons.health_and_safety_outlined,
      title: 'Stay safe',
      about: 'Nothing that could get someone hurt.',
      ok: [
        'Video games of every kind, shooters included',
        'Replica, prop, toy, cosplay, airsoft and collectible weapons',
        'Knives for cooking or crafts',
        'Drinking, and smoking or vaping shown in a post',
        'Talking about marijuana',
      ],
      notOk: [
        'Encouraging suicide, self-harm or eating disorders',
        'Buying or selling real weapons, drugs, marijuana, tobacco, vapes or alcohol',
        'Showing marijuana or other drugs, or how to use them',
        'How to make weapons or explosives',
        'Threatening someone with a weapon',
      ],
    ),
    _Rule(
      icon: Icons.verified_user_outlined,
      title: 'Be yourself',
      about: 'Real people sharing their days.',
      ok: ['Nicknames and inside jokes'],
      notOk: [
        'Pretending to be someone else',
        'Spam, fake giveaways or scams',
      ],
    ),
    _Rule(
      icon: Icons.copyright_rounded,
      title: 'Post what\'s yours',
      about: 'Only share things you have the right to share.',
      ok: ['Your own photos, videos and writing', 'Memes and reposts with credit'],
      notOk: [
        'Passing off someone else\'s work as yours',
        'Private photos or videos of someone without their OK',
      ],
    ),
  ];

  static const _limited = [
    'Sexually suggestive posts',
    'Real fights or serious injuries',
    'Very crude or gross-out stuff',
    'Real guns shown casually, like a range day or hunting',
    'Promoting tobacco or vapes, like hyping a brand',
  ];

  static const _steps = <(IconData, String, String)>[
    (Icons.shield_outlined, 'Posts are checked',
    'Clips, Daily posts and comments are checked automatically, and anyone can report something.'),
    (Icons.visibility_off_outlined, 'Breaking a rule gets it removed',
    'It\'s hidden from everyone, and you get a notice saying which rule and why.'),
    (Icons.rate_review_outlined, 'You can ask for a review',
    'A person from Kaidose looks at it. If we got it wrong, it comes back and doesn\'t count against you.'),
    (Icons.report_gmailerrorred_rounded, 'Repeat removals are reviewed',
    '3 removals in 30 days and our team reviews your account, which can lead to it being restricted or suspended.'),
  ];

  @override
  Widget build(BuildContext context) {
    return SettingsPage(
      title: 'Community Guidelines',
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(4, 10, 4, 0),
          child: Text(
            'Kaidose is for real people sharing their days. These are the '
                'rules for everything you post: clips, Daily posts, covers, '
                'comments and chats.',
            style: TextStyle(
                fontSize: 14.5, height: 1.4, color: kc.adapt(const Color(0xFF555A61))),
          ),
        ),
        for (final r in _rules) _RuleCard(rule: r),

        SettingsGroup(
          title: 'Allowed, but not recommended',
          footer: 'These stay up on your profile and in your Dailies, but '
              'Kaidose won\'t recommend them or use them as a Daily cover. '
              'They don\'t count against you.',
          children: [
            for (final l in _limited) _Line(text: l, mark: _Mark.limited),
          ],
        ),

        SettingsGroup(
          title: 'What happens when something breaks a rule',
          footer: 'Anything sexual involving someone under 18 can\'t be '
              'reviewed this way and is reported to the authorities.',
          children: [
            for (final s in _steps)
              Padding(
                padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(s.$1, size: 22, color: kc.adapt(const Color(0xFF55595F))),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.$2,
                              style: TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w500,
                                  color: SettingsStyle.ink)),
                          const SizedBox(height: 3),
                          Text(s.$3,
                              style: TextStyle(
                                  fontSize: 13,
                                  height: 1.35,
                                  color: SettingsStyle.subtle)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),

        Padding(
          padding: EdgeInsets.fromLTRB(6, 22, 6, 0),
          child: Text(
            'See something that breaks these? Report it from the ⋯ menu. '
                'Questions: $kSupportEmail',
            style: TextStyle(
                fontSize: 12.5, height: 1.35, color: SettingsStyle.subtle),
          ),
        ),
      ],
    );
  }
}

class _Rule {
  final IconData icon;
  final String title;
  final String about;
  final List<String> ok;
  final List<String> notOk;
  const _Rule({
    required this.icon,
    required this.title,
    required this.about,
    required this.ok,
    required this.notOk,
  });
}

/// One rule: a heading row, then what's fine and what isn't.
class _RuleCard extends StatelessWidget {
  final _Rule rule;
  const _RuleCard({required this.rule});

  @override
  Widget build(BuildContext context) {
    return SettingsGroup(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(rule.icon, size: 22, color: kc.adapt(const Color(0xFF55595F))),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(rule.title,
                        style: TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w700,
                            color: SettingsStyle.ink)),
                    const SizedBox(height: 3),
                    Text(rule.about,
                        style: TextStyle(
                            fontSize: 13.5,
                            height: 1.35,
                            color: SettingsStyle.subtle)),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Column(
            children: [
              for (final t in rule.ok) _Line(text: t, mark: _Mark.ok),
              for (final t in rule.notOk) _Line(text: t, mark: _Mark.notOk),
            ],
          ),
        ),
      ],
    );
  }
}

enum _Mark { ok, notOk, limited }

class _Line extends StatelessWidget {
  final String text;
  final _Mark mark;
  const _Line({required this.text, required this.mark});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (mark) {
      _Mark.ok => (Icons.check_circle_rounded, const Color(0xFF2FA36B)),
      _Mark.notOk => (Icons.cancel_rounded, SettingsStyle.danger),
      _Mark.limited => (Icons.remove_circle_rounded, const Color(0xFFE0A100)),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 7, 14, 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 14.5, height: 1.3, color: SettingsStyle.ink)),
          ),
        ],
      ),
    );
  }
}