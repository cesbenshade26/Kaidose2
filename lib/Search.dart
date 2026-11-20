import 'package:flutter/material.dart';
import 'AppColors.dart';
import 'FriendsSearch.dart';
import 'DailySearch.dart';
import 'ClipSearch.dart';
import 'FeedService.dart';

// Search Screen
class SearchScreen extends StatefulWidget {
  /// True when this is the Search tab in the bottom bar (no back arrow, no
  /// auto-focused keyboard, and results must not pop the screen when opened).
  final bool isTab;

  const SearchScreen({Key? key, this.isTab = false}) : super(key: key);

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  static const _tabs = ['All', 'People', 'Dailies', 'Clips'];
  static const int _all = 0, _people = 1, _dailies = 2, _clips = 3;

  /// Tab row (44) + sliding line (2) + divider (1).
  static const double _tabsHeight = 47;

  /// Recent searches live for the app session.
  static final List<String> _recent = [];

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focus = FocusNode();
  int _selectedTabIndex = _all;
  List<String> _topics = [];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    _loadTopics();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _loadTopics() async {
    try {
      final topics = await FeedService.getTopTopics(limit: 8);
      if (mounted) setState(() => _topics = topics);
    } catch (_) {}
  }

  String get _query => _searchController.text.trim();

  void _remember(String q) {
    q = q.trim();
    if (q.isEmpty) return;
    _recent.removeWhere((r) => r.toLowerCase() == q.toLowerCase());
    _recent.insert(0, q);
    if (_recent.length > 8) _recent.removeLast();
  }

  void _useSuggestion(String text) {
    _searchController.text = text;
    _searchController.selection =
        TextSelection.fromPosition(TextPosition(offset: text.length));
    _remember(text);
    _focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    // The whole page scrolls: the search box and tabs slide away as you
    // scroll down through results and slide back as soon as you scroll up
    // a little (floating + snap), so the search box is never far away.
    return Scaffold(
      backgroundColor: kc.background,
      body: NestedScrollView(
        floatHeaderSlivers: true,
        headerSliverBuilder: (context, innerScrolled) => [
          SliverAppBar(
            floating: true,
            snap: true,
            backgroundColor: kc.background,
            surfaceTintColor: Colors.transparent,
            scrolledUnderElevation: 0,
            elevation: 0,
            automaticallyImplyLeading: false,
            centerTitle: false,
            titleSpacing: 0,
            toolbarHeight: 64,
            title: _buildSearchBar(),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(_tabsHeight),
              child: _buildTabs(),
            ),
          ),
        ],
        body: SafeArea(top: false, child: _getTabContent()),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: kc.grey(100),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          if (!widget.isTab)
            IconButton(
              icon: Icon(Icons.arrow_back, color: kc.text, size: 22),
              onPressed: () => Navigator.pop(context),
            )
          else
            const SizedBox(width: 10),
          Icon(Icons.search, color: kc.grey(500), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _focus,
              autofocus: !widget.isTab,
              textInputAction: TextInputAction.search,
              onSubmitted: _remember,
              decoration: InputDecoration(
                hintText: 'Search people, Dailies, topics',
                hintStyle: TextStyle(color: kc.grey(500), fontSize: 16),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
              style: TextStyle(fontSize: 16, color: kc.text),
            ),
          ),
          if (_searchController.text.isNotEmpty)
            IconButton(
              icon: Icon(Icons.close, color: kc.grey(500), size: 20),
              onPressed: _searchController.clear,
            ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    final width = MediaQuery.of(context).size.width / _tabs.length;
    return SizedBox(
      height: _tabsHeight,
      child: Column(
        children: [
          Row(
            children: [
              for (var i = 0; i < _tabs.length; i++)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _selectedTabIndex = i),
                    child: SizedBox(
                      height: 44,
                      child: Center(
                        child: Text(
                          _tabs[i],
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: _selectedTabIndex == i
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color:
                            _selectedTabIndex == i ? kc.text : kc.grey(500),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(
            height: 2,
            child: Stack(
              children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  left: width * _selectedTabIndex + width * 0.2,
                  width: width * 0.6,
                  child: Container(height: 2, color: Colors.black),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: kc.grey(200)),
        ],
      ),
    );
  }

  Widget _getTabContent() {
    switch (_selectedTabIndex) {
      case _people:
        return FriendsSearchWidget(searchQuery: _query);
      case _dailies:
        return DailySearchWidget(
          searchQuery: _query,
          closeSearchOnOpen: !widget.isTab,
        );
      case _clips:
        return ClipSearchWidget(
          searchQuery: _query,
          onTopicTap: _useSuggestion,
        );
      default:
        return _buildAll();
    }
  }

  // ─── All ────────────────────────────────────────────────────────────────────

  Widget _buildAll() {
    final typed = _query.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        if (!typed) ..._buildIdleExtras(),

        _sectionHeader(typed ? 'People' : 'People you may know',
            onTap: () => setState(() => _selectedTabIndex = _people)),
        FriendsSearchWidget(
          key: ValueKey('all-people-$_query'),
          searchQuery: _query,
          embedded: true,
          limit: 3,
          onSeeAll: () => setState(() => _selectedTabIndex = _people),
        ),
        const SizedBox(height: 20),

        _sectionHeader(typed ? 'Dailies' : 'Suggested Dailies',
            onTap: () => setState(() => _selectedTabIndex = _dailies)),
        DailySearchWidget(
          key: ValueKey('all-dailies-$_query'),
          searchQuery: _query,
          closeSearchOnOpen: !widget.isTab,
          embedded: true,
          limit: 4,
          onSeeAll: () => setState(() => _selectedTabIndex = _dailies),
        ),
        const SizedBox(height: 20),

        _sectionHeader(typed ? 'Clips' : 'Clips for you',
            onTap: () => setState(() => _selectedTabIndex = _clips)),
        ClipSearchWidget(
          key: ValueKey('all-clips-$_query'),
          searchQuery: _query,
          embedded: true,
        ),
      ],
    );
  }

  /// Recent searches and topic chips shown before the user types.
  List<Widget> _buildIdleExtras() {
    return [
      if (_recent.isNotEmpty) ...[
        _sectionHeader('Recent'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final r in _recent)
              ActionChip(
                avatar: Icon(Icons.history, size: 16, color: kc.grey(600)),
                label: Text(r),
                backgroundColor: kc.grey(100),
                side: BorderSide.none,
                onPressed: () => _useSuggestion(r),
              ),
          ],
        ),
        const SizedBox(height: 20),
      ],
      if (_topics.isNotEmpty) ...[
        _sectionHeader('Topics for you'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in _topics)
              ActionChip(
                label: Text(t),
                labelStyle: TextStyle(
                    color: kc.text, fontWeight: FontWeight.w500),
                backgroundColor: kc.adapt(const Color(0xFFF1F3F5)),
                side: BorderSide.none,
                onPressed: () => _useSuggestion(t),
              ),
          ],
        ),
        const SizedBox(height: 20),
      ],
    ];
  }

  Widget _sectionHeader(String text, {VoidCallback? onTap}) => Padding(
    padding: const EdgeInsets.only(bottom: 10, left: 2),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: kc.grey(800)),
          ),
        ),
        if (onTap != null)
          GestureDetector(
            onTap: onTap,
            child: Icon(Icons.chevron_right, color: kc.grey(500)),
          ),
      ],
    ),
  );
}