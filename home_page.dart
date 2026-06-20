import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math';
import 'login_page.dart';
import 'main.dart' show themeNotifier;

// ─────────────────────────────────────────────
//  THEME CONSTANTS  (matches LoginPage palette)
// ─────────────────────────────────────────────
const kBg = Color(0xFF0F1117);
const kCard = Color(0xFF1E2130);
const kBorder = Color(0xFF2E3250);
const kSurface = Color(0xFF13151F);
const kPrimary = Color(0xFF6C63FF);
const kAccent = Color(0xFF3ECFCF);
const kGreen = Color(0xFF22C55E);
const kRed = Color(0xFFE53E3E);
const kAmber = Color(0xFFFFAB4E);
const kTextPrimary = Colors.white;
const kTextSecondary = Color(0xFF8B8FA8);
const kTextMuted = Color(0xFF4A4F6A);

// ─────────────────────────────────────────────
//  HOME PAGE  (shell with bottom nav)
// ─────────────────────────────────────────────
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;

  // ── Shared live data ──
  int score = 0;
  int good = 0;
  int bad = 0;
  int sitting = 0;
  String suggestion = "Fetching AI suggestion…";
  List<double> weeklyScores = [];
  List<double> monthlyScores = List.generate(
    30,
    (i) => 60 + Random().nextDouble() * 35,
  );

  // ── Heatmap data: { "2026-06-09": { "10": 85, "11": 72 } } ──
  Map<String, Map<int, int>> heatmapData = {};

  // ── Weekly Firebase data ──
  Map<String, int> weeklyFirebase = {};

  // ── Accumulated stats from daily node ──
  int weeklyGood = 0;
  int weeklyBad = 0;
  int weeklySitting = 0;
  int monthlyGood = 0;
  int monthlyBad = 0;
  int monthlySitting = 0;

  @override
  void initState() {
    super.initState();
    _setActiveUser(); // ✅ Python script কে সঠিক UID দাও
    _listenFirebase();
    _listenHeatmap();
    _listenWeekly();
    _listenDaily();
  }

  // ✅ App খুললেই active_user update — Python script সবসময় সঠিক UID পাবে
  void _setActiveUser() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    FirebaseDatabase.instance.ref('active_user').set(user.uid);
  }

  void _listenFirebase() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    FirebaseDatabase.instance.ref("users/${user.uid}/analytics").onValue.listen(
      (event) {
        final data = event.snapshot.value as Map?;
        if (data == null) return;

        setState(() {
          score = data["posture_score"] ?? 0;
          good = data["good_posture"] ?? 0;
          bad = data["bad_posture"] ?? 0;
          sitting = data["sitting_time"] ?? 0;
          suggestion = data["last_suggestion"] ?? "No suggestion";

          final w = (data["posture_score"] ?? 0).toDouble();
          if (weeklyScores.length >= 7) {
            weeklyScores = [...weeklyScores.skip(1), w];
          } else {
            weeklyScores = [...weeklyScores, w];
          }
        });
      },
    );
  }

  void _listenHeatmap() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    FirebaseDatabase.instance.ref("users/${user.uid}/heatmap").onValue.listen((
      event,
    ) {
      final raw = event.snapshot.value as Map?;
      if (raw == null) return;

      final Map<String, Map<int, int>> parsed = {};
      raw.forEach((date, hours) {
        if (hours is Map) {
          final Map<int, int> hourMap = {};
          hours.forEach((h, val) {
            if (val is Map && val["score"] != null) {
              hourMap[int.tryParse(h.toString()) ?? 0] = (val["score"] as num)
                  .toInt();
            }
          });
          parsed[date.toString()] = hourMap;
        }
      });

      setState(() => heatmapData = parsed);
    });
  }

  void _listenWeekly() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    FirebaseDatabase.instance.ref("users/${user.uid}/weekly").onValue.listen((
      event,
    ) {
      final raw = event.snapshot.value as Map?;
      if (raw == null) return;

      final Map<String, int> parsed = {};
      raw.forEach((day, val) {
        if (val is Map && val["score"] != null) {
          parsed[day.toString()] = (val["score"] as num).toInt();
        }
      });

      const order = [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ];
      final scores = order
          .where((d) => parsed.containsKey(d))
          .map((d) => parsed[d]!.toDouble())
          .toList();

      setState(() {
        weeklyFirebase = parsed;
        if (scores.isNotEmpty) weeklyScores = scores;
      });
    });
  }

  void _listenDaily() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    FirebaseDatabase.instance.ref("users/${user.uid}/daily").onValue.listen((
      event,
    ) {
      final raw = event.snapshot.value as Map?;
      if (raw == null) return;

      final now = DateTime.now();

      // Last 7 days keys
      final last7 = List.generate(7, (i) {
        final d = now.subtract(Duration(days: i));
        return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      }).toSet();

      // Last 30 days keys
      final last30 = List.generate(30, (i) {
        final d = now.subtract(Duration(days: i));
        return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      }).toSet();

      int wGood = 0, wBad = 0, wSit = 0;
      int mGood = 0, mBad = 0, mSit = 0;

      raw.forEach((date, val) {
        if (val is Map) {
          final g = (val["good_posture"] as num?)?.toInt() ?? 0;
          final b = (val["bad_posture"] as num?)?.toInt() ?? 0;
          final s = (val["sitting_time"] as num?)?.toInt() ?? 0;

          if (last7.contains(date.toString())) {
            wGood += g;
            wBad += b;
            wSit += s;
          }
          if (last30.contains(date.toString())) {
            mGood += g;
            mBad += b;
            mSit += s;
          }
        }
      });

      setState(() {
        weeklyGood = wGood;
        weeklyBad = wBad;
        weeklySitting = wSit;
        monthlyGood = mGood;
        monthlyBad = mBad;
        monthlySitting = mSit;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _DashboardPage(
        score: score,
        good: good,
        bad: bad,
        sitting: sitting,
        suggestion: suggestion,
        weeklyScores: weeklyScores,
      ),
      _StatsPage(
        good: good,
        bad: bad,
        sitting: sitting,
        weekly: weeklyScores,
        monthly: monthlyScores,
        weeklyGood: weeklyGood,
        weeklyBad: weeklyBad,
        weeklySitting: weeklySitting,
        monthlyGood: monthlyGood,
        monthlyBad: monthlyBad,
        monthlySitting: monthlySitting,
      ),
      _HeatmapPage(heatmapData: heatmapData),
      _TipsPage(score: score),
      _ProfilePage(score: score),
    ];

    return Scaffold(
      backgroundColor: kBg,
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: _BottomNav(
        currentIndex: _tab,
        onTap: (i) => setState(() => _tab = i),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  BOTTOM NAV  (Facebook-style)
// ─────────────────────────────────────────────
class _BottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  _BottomNav({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.home_rounded, Icons.home_outlined, 'Home'),
      (Icons.bar_chart_rounded, Icons.bar_chart_outlined, 'Stats'),
      (Icons.grid_view_rounded, Icons.grid_view_outlined, 'Heatmap'),
      (Icons.lightbulb_rounded, Icons.lightbulb_outline, 'Tips'),
      (Icons.person_rounded, Icons.person_outline_rounded, 'Profile'),
    ];

    return Container(
      height: 64,
      decoration: const BoxDecoration(
        color: kCard,
        border: Border(top: BorderSide(color: kBorder, width: 0.8)),
      ),
      child: Row(
        children: List.generate(items.length, (i) {
          final active = currentIndex == i;
          return Expanded(
            child: InkWell(
              onTap: () => onTap(i),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    active ? items[i].$1 : items[i].$2,
                    color: active ? kPrimary : kTextMuted,
                    size: 26,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    items[i].$3,
                    style: TextStyle(
                      color: active ? kPrimary : kTextMuted,
                      fontSize: 10,
                      fontWeight: active ? FontWeight.w700 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  PAGE 1 — DASHBOARD
// ─────────────────────────────────────────────
class _DashboardPage extends StatelessWidget {
  final int score, good, bad, sitting;
  final String suggestion;
  final List<double> weeklyScores;

  const _DashboardPage({
    required this.score,
    required this.good,
    required this.bad,
    required this.sitting,
    required this.suggestion,
    required this.weeklyScores,
  });

  static String _formatTime(int seconds) {
    if (seconds < 60) return '${seconds}s';
    if (seconds < 3600) {
      final m = seconds ~/ 60;
      final s = seconds % 60;
      return s > 0 ? '${m}m ${s}s' : '${m}m';
    }
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    return m > 0 ? '${h}h ${m}m' : '${h}h';
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email ?? '';
    final name = email.contains('@') ? email.split('@')[0] : 'User';

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top bar ──
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Good day, $name 👋',
                      style: const TextStyle(
                        color: kTextSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Posture Dashboard',
                      style: TextStyle(
                        color: kTextPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [kPrimary, kAccent]),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.accessibility_new_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // ── Score hero card ──
            _ScoreCard(score: score),

            const SizedBox(height: 20),

            // ── Stats row ──
            Row(
              children: [
                Expanded(
                  child: _StatTile(
                    label: 'Good',
                    value: _formatTime(good),
                    icon: Icons.thumb_up_alt_rounded,
                    color: kGreen,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatTile(
                    label: 'Bad',
                    value: _formatTime(bad),
                    icon: Icons.thumb_down_alt_rounded,
                    color: kRed,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatTile(
                    label: 'Sitting',
                    value: _formatTime(sitting),
                    icon: Icons.chair_rounded,
                    color: kAccent,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // ── AI Suggestion ──
            _AiSuggestionCard(suggestion: suggestion),

            const SizedBox(height: 24),

            // ── Weekly graph ──
            _SectionHeader(title: 'Weekly Trend', subtitle: 'Last 7 days'),
            const SizedBox(height: 12),
            _LineChartCard(
              scores: weeklyScores,
              color: kPrimary,
              labels: ['M', 'T', 'W', 'T', 'F', 'S', 'S'],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  PAGE 2 — STATS
// ─────────────────────────────────────────────
class _StatsPage extends StatefulWidget {
  final int good, bad, sitting;
  final int weeklyGood, weeklyBad, weeklySitting;
  final int monthlyGood, monthlyBad, monthlySitting;
  final List<double> weekly, monthly;
  const _StatsPage({
    required this.good,
    required this.bad,
    required this.sitting,
    required this.weekly,
    required this.monthly,
    required this.weeklyGood,
    required this.weeklyBad,
    required this.weeklySitting,
    required this.monthlyGood,
    required this.monthlyBad,
    required this.monthlySitting,
  });

  @override
  State<_StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<_StatsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tc;

  @override
  void initState() {
    super.initState();
    _tc = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // daily scores — use last 2 points of weekly or just current score twice
    final dailyScores = widget.weekly.isNotEmpty
        ? [widget.weekly.last, widget.weekly.last]
        : <double>[];

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Stats',
                  style: TextStyle(
                    color: kTextPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Track your posture over time',
                  style: TextStyle(color: kTextSecondary, fontSize: 13),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // tab bar
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            height: 40,
            decoration: BoxDecoration(
              color: kSurface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: kBorder),
            ),
            child: TabBar(
              controller: _tc,
              indicator: BoxDecoration(
                gradient: const LinearGradient(colors: [kPrimary, kAccent]),
                borderRadius: BorderRadius.circular(8),
              ),
              labelColor: Colors.white,
              unselectedLabelColor: kTextMuted,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
              dividerColor: Colors.transparent,
              tabs: const [
                Tab(text: 'Daily'),
                Tab(text: 'Weekly'),
                Tab(text: 'Monthly'),
              ],
            ),
          ),

          const SizedBox(height: 16),

          Expanded(
            child: TabBarView(
              controller: _tc,
              children: [
                // daily — today's current session
                _StatTabContent(
                  good: widget.good,
                  bad: widget.bad,
                  sitting: widget.sitting,
                  scores: dailyScores,
                  chartColor: kGreen,
                  labels: ['AM', 'PM'],
                  period: 'Today',
                ),
                // weekly — last 7 days accumulated
                _StatTabContent(
                  good: widget.weeklyGood > 0 ? widget.weeklyGood : widget.good,
                  bad: widget.weeklyBad > 0 ? widget.weeklyBad : widget.bad,
                  sitting: widget.weeklyGood > 0
                      ? widget.weeklySitting
                      : widget.sitting,
                  scores: widget.weekly,
                  chartColor: kPrimary,
                  labels: ['M', 'T', 'W', 'T', 'F', 'S', 'S'],
                  period: 'This Week',
                ),
                // monthly — last 30 days accumulated
                _StatTabContent(
                  good: widget.monthlyGood > 0
                      ? widget.monthlyGood
                      : widget.good,
                  bad: widget.monthlyBad > 0 ? widget.monthlyBad : widget.bad,
                  sitting: widget.monthlyGood > 0
                      ? widget.monthlySitting
                      : widget.sitting,
                  scores: widget.monthly,
                  chartColor: kAccent,
                  labels: List.generate(30, (i) => (i + 1).toString()),
                  period: 'This Month',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTabContent extends StatelessWidget {
  final int good, bad, sitting;
  final List<double> scores;
  final Color chartColor;
  final List<String> labels;
  final String period;

  const _StatTabContent({
    required this.good,
    required this.bad,
    required this.sitting,
    required this.scores,
    required this.chartColor,
    required this.labels,
    required this.period,
  });

  static String _formatTime(int seconds) {
    if (seconds < 60) return '${seconds}s';
    if (seconds < 3600) {
      final m = seconds ~/ 60;
      final s = seconds % 60;
      return s > 0 ? '${m}m ${s}s' : '${m}m';
    }
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (m == 0 && s == 0) return '${h}h';
    if (s == 0) return '${h}h ${m}m';
    return '${h}h ${m}m ${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final avg = scores.isEmpty
        ? 0
        : (scores.reduce((a, b) => a + b) / scores.length).round();
    final best = scores.isEmpty ? 0 : scores.reduce(max).round();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        children: [
          // summary row
          Row(
            children: [
              Expanded(
                child: _BigStatCard(
                  label: 'Avg Score',
                  value: '$avg%',
                  color: chartColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _BigStatCard(
                  label: 'Best Score',
                  value: '$best%',
                  color: kAmber,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _BigStatCard(
                  label: 'Good Posture',
                  value: _formatTime(good),
                  color: kGreen,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _BigStatCard(
                  label: 'Bad Posture',
                  value: _formatTime(bad),
                  color: kRed,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _BigStatCard(
                  label: 'Sitting Time',
                  value: _formatTime(sitting),
                  color: kAccent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _BigStatCard(
                  label: 'Total Sessions',
                  value: scores.isEmpty ? '—' : '${scores.length}',
                  color: kTextSecondary,
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // bar chart – good vs bad
          _SectionHeader(title: '$period — Good vs Bad', subtitle: ''),
          const SizedBox(height: 12),
          _GoodBadBarCard(good: good, bad: bad),

          const SizedBox(height: 20),

          // line chart
          _SectionHeader(title: 'Score Trend', subtitle: period),
          const SizedBox(height: 12),
          _LineChartCard(scores: scores, color: chartColor, labels: labels),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  PAGE 3 — HEATMAP
// ─────────────────────────────────────────────
class _HeatmapPage extends StatelessWidget {
  final Map<String, Map<int, int>> heatmapData;
  const _HeatmapPage({required this.heatmapData});

  Color _cellColor(int? score) {
    if (score == null) return kSurface;
    if (score >= 85) return kGreen;
    if (score >= 65) return kAccent;
    if (score >= 45) return kAmber;
    return kRed;
  }

  // Get last 7 dates
  List<String> get _last7Days {
    final now = DateTime.now();
    return List.generate(7, (i) {
      final d = now.subtract(Duration(days: 6 - i));
      return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    });
  }

  String _shortDate(String date) {
    final parts = date.split('-');
    if (parts.length < 3) return date;
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
    final m = int.tryParse(parts[1]) ?? 1;
    return '${months[m - 1]} ${parts[2]}';
  }

  @override
  Widget build(BuildContext context) {
    final days = _last7Days;
    final hours = List.generate(24, (i) => i);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Posture Heatmap',
              style: TextStyle(
                color: kTextPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Hourly posture score — last 7 days',
              style: TextStyle(color: kTextSecondary, fontSize: 13),
            ),

            const SizedBox(height: 20),

            // Legend
            Row(
              children: [
                _LegendDot(color: kGreen, label: '≥85 Great'),
                const SizedBox(width: 12),
                _LegendDot(color: kAccent, label: '≥65 Good'),
                const SizedBox(width: 12),
                _LegendDot(color: kAmber, label: '≥45 Fair'),
                const SizedBox(width: 12),
                _LegendDot(color: kRed, label: 'Poor'),
              ],
            ),

            const SizedBox(height: 20),

            // Heatmap grid
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: kCard,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: kBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Hour labels top
                  Padding(
                    padding: const EdgeInsets.only(left: 52),
                    child: Row(
                      children: [0, 3, 6, 9, 12, 15, 18, 21].map((h) {
                        return Expanded(
                          flex: h == 21 ? 3 : 3,
                          child: Text(
                            '${h}h',
                            style: const TextStyle(
                              color: kTextMuted,
                              fontSize: 9,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Rows per day
                  ...days.map((date) {
                    final hourMap = heatmapData[date] ?? {};
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          // Date label
                          SizedBox(
                            width: 52,
                            child: Text(
                              _shortDate(date),
                              style: const TextStyle(
                                color: kTextSecondary,
                                fontSize: 9,
                              ),
                            ),
                          ),
                          // Hour cells
                          ...hours.map((h) {
                            final s = hourMap[h];
                            return Expanded(
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 400),
                                height: 22,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: s != null
                                      ? _cellColor(s).withOpacity(0.85)
                                      : kSurface,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Daily summary cards
            const Text(
              'Daily Summary',
              style: TextStyle(
                color: kTextPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),

            ...days.reversed.map((date) {
              final hourMap = heatmapData[date] ?? {};
              if (hourMap.isEmpty) return const SizedBox.shrink();
              final scores = hourMap.values.toList();
              final avg = scores.isEmpty
                  ? 0
                  : (scores.reduce((a, b) => a + b) / scores.length).round();
              final best = scores.isEmpty ? 0 : scores.reduce(max);
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: kCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: kBorder),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: _cellColor(avg).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.calendar_today_rounded,
                          color: _cellColor(avg),
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _shortDate(date),
                              style: const TextStyle(
                                color: kTextPrimary,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              '${hourMap.length} active hours',
                              style: const TextStyle(
                                color: kTextSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'Avg $avg%',
                            style: TextStyle(
                              color: _cellColor(avg),
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            'Best $best%',
                            style: const TextStyle(
                              color: kTextSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(color: kTextSecondary, fontSize: 10),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
//  PAGE 4 — TIPS
// ─────────────────────────────────────────────
// ─────────────────────────────────────────────
class _TipsPage extends StatelessWidget {
  final int score;
  const _TipsPage({required this.score});

  static const _tips = [
    (
      Icons.monitor_rounded,
      'Screen at eye level',
      'Keep your monitor top at eye height to avoid neck flexion. Every 1 cm of forward head is 4–5 kg extra load on the cervical spine.',
      kAccent,
    ),
    (
      Icons.chair_alt_rounded,
      'Hips back, feet flat',
      'Sit deep into the chair, knees at 90°, feet flat on the floor. Let the backrest support your lumbar, not the edge of the seat.',
      kPrimary,
    ),
    (
      Icons.timer_rounded,
      '20-20-20 rule',
      'Every 20 minutes, look at something 20 feet away for 20 seconds AND stand up to relieve spinal compression.',
      kAmber,
    ),
    (
      Icons.fitness_center_rounded,
      'Shoulder blade squeeze',
      'Pull your shoulder blades back and down for 10 seconds, 10 reps. Counters the forward-rolled shoulders from keyboard use.',
      kGreen,
    ),
    (
      Icons.self_improvement_rounded,
      'Core engagement',
      'A light core brace (30% effort) throughout the day stabilises the lumbar. Think: "tall spine" not "sucked-in stomach".',
      Color(0xFFFF6B9D),
    ),
    (
      Icons.local_drink_rounded,
      'Stay hydrated',
      'Spinal discs are 80% water. Dehydration reduces disc height and shock absorption. Aim for 2–3 L per day.',
      kAccent,
    ),
    (
      Icons.phone_android_rounded,
      'Phone at eye level',
      '"Text neck" adds up to 27 kg of force on the spine. Raise your phone, not bow your head.',
      kRed,
    ),
    (
      Icons.directions_walk_rounded,
      'Walk every hour',
      'A 5-minute walk each hour cuts lower-back compression by ~50% compared to sitting the full hour.',
      kGreen,
    ),
  ];

  String get _scoreLabel {
    if (score >= 85) return 'Excellent';
    if (score >= 70) return 'Good';
    if (score >= 50) return 'Fair';
    return 'Needs Work';
  }

  Color get _scoreColor {
    if (score >= 85) return kGreen;
    if (score >= 70) return kAccent;
    if (score >= 50) return kAmber;
    return kRed;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Posture Tips',
                    style: TextStyle(
                      color: kTextPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Based on your score: ',
                    style: const TextStyle(color: kTextSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 12),

                  // score banner
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: _scoreColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _scoreColor.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.insights_rounded,
                          color: _scoreColor,
                          size: 28,
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Your posture is $_scoreLabel',
                              style: TextStyle(
                                color: _scoreColor,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            Text(
                              'Score: $score%',
                              style: const TextStyle(
                                color: kTextSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _TipCard(
                    icon: _tips[i].$1,
                    title: _tips[i].$2,
                    body: _tips[i].$3,
                    color: _tips[i].$4,
                  ),
                ),
                childCount: _tips.length,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  PAGE 5 — PROFILE
// ─────────────────────────────────────────────
class _ProfilePage extends StatelessWidget {
  final int score;
  const _ProfilePage({required this.score});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email ?? 'Unknown';
    final name = email.contains('@') ? email.split('@')[0] : 'User';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'U';

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          children: [
            // avatar
            Center(
              child: Column(
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [kPrimary, kAccent],
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: kPrimary.withOpacity(0.35),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        initial,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    name,
                    style: const TextStyle(
                      color: kTextPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    email,
                    style: const TextStyle(color: kTextSecondary, fontSize: 13),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // score card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    kPrimary.withOpacity(0.15),
                    kAccent.withOpacity(0.1),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: kBorder),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _ProfileStat(label: 'Today', value: '$score%'),
                  _vDivider(),
                  _ProfileStat(label: 'Weekly Avg', value: '81%'),
                  _vDivider(),
                  _ProfileStat(label: 'Streak', value: '7d 🔥'),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // info tiles
            _InfoTile(icon: Icons.email_outlined, label: 'Email', value: email),
            const SizedBox(height: 10),
            _InfoTile(
              icon: Icons.fingerprint_rounded,
              label: 'User ID',
              value: user?.uid.substring(0, 12) ?? '—',
            ),
            const SizedBox(height: 10),
            _InfoTile(
              icon: Icons.calendar_today_rounded,
              label: 'Member since',
              value: user?.metadata.creationTime != null
                  ? '${user!.metadata.creationTime!.day}/${user.metadata.creationTime!.month}/${user.metadata.creationTime!.year}'
                  : '—',
            ),

            const SizedBox(height: 32),

            // theme toggle
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: kCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: kBorder),
              ),
              child: Row(
                children: [
                  Icon(
                    themeNotifier.isDark
                        ? Icons.dark_mode_rounded
                        : Icons.light_mode_rounded,
                    color: kPrimary,
                    size: 20,
                  ),
                  const SizedBox(width: 14),
                  Text(
                    themeNotifier.isDark ? 'Dark Mode' : 'Light Mode',
                    style: const TextStyle(color: kTextSecondary, fontSize: 13),
                  ),
                  const Spacer(),
                  Switch(
                    value: themeNotifier.isDark,
                    onChanged: (_) => themeNotifier.toggle(),
                    activeColor: kPrimary,
                    activeTrackColor: kPrimary.withOpacity(0.3),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // logout
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                onPressed: () async {
                  await FirebaseAuth.instance.signOut();
                  if (context.mounted) {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginPage()),
                    );
                  }
                },
                icon: const Icon(Icons.logout_rounded, color: kRed, size: 18),
                label: const Text(
                  'Logout',
                  style: TextStyle(color: kRed, fontWeight: FontWeight.w700),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: kRed, width: 1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _vDivider() => Container(width: 1, height: 36, color: kBorder);
}

// ─────────────────────────────────────────────
//  SHARED SMALL WIDGETS
// ─────────────────────────────────────────────

class _ScoreCard extends StatelessWidget {
  final int score;
  const _ScoreCard({required this.score});

  Color get _color {
    if (score >= 85) return kGreen;
    if (score >= 65) return kAccent;
    if (score >= 45) return kAmber;
    return kRed;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [kPrimary.withOpacity(0.25), kAccent.withOpacity(0.15)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: kBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Today\'s Score',
                  style: TextStyle(
                    color: kTextSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$score',
                      style: TextStyle(
                        color: _color,
                        fontSize: 52,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text(
                        '%',
                        style: TextStyle(
                          color: kTextSecondary,
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                _ScoreBar(score: score, color: _color),
              ],
            ),
          ),
          const SizedBox(width: 20),
          _RadialScore(score: score, color: _color),
        ],
      ),
    );
  }
}

class _ScoreBar extends StatelessWidget {
  final int score;
  final Color color;
  const _ScoreBar({required this.score, required this.color});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, c) {
        return Stack(
          children: [
            Container(
              height: 6,
              width: c.maxWidth,
              decoration: BoxDecoration(
                color: kSurface,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              height: 6,
              width: c.maxWidth * (score / 100),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [color.withOpacity(0.6), color],
                ),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RadialScore extends StatelessWidget {
  final int score;
  final Color color;
  const _RadialScore({required this.score, required this.color});

  String get _label {
    if (score >= 85) return 'Great';
    if (score >= 65) return 'Good';
    if (score >= 45) return 'Fair';
    return 'Poor';
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80,
      height: 80,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 80,
            height: 80,
            child: CircularProgressIndicator(
              value: score / 100,
              strokeWidth: 7,
              backgroundColor: kSurface,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          Text(
            _label,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(color: kTextSecondary, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _AiSuggestionCard extends StatelessWidget {
  final String suggestion;
  const _AiSuggestionCard({required this.suggestion});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kPrimary.withOpacity(0.3)),
        gradient: LinearGradient(
          colors: [kPrimary.withOpacity(0.08), kAccent.withOpacity(0.04)],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [kPrimary, kAccent]),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.psychology_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AI Suggestion',
                  style: TextStyle(
                    color: kPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  suggestion,
                  style: const TextStyle(
                    color: kTextPrimary,
                    fontSize: 13.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title, subtitle;
  const _SectionHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            color: kTextPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Spacer(),
        if (subtitle.isNotEmpty)
          Text(
            subtitle,
            style: const TextStyle(color: kTextSecondary, fontSize: 12),
          ),
      ],
    );
  }
}

class _LineChartCard extends StatelessWidget {
  final List<double> scores;
  final Color color;
  final List<String> labels;
  const _LineChartCard({
    required this.scores,
    required this.color,
    required this.labels,
  });

  @override
  Widget build(BuildContext context) {
    if (scores.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 200,
      padding: const EdgeInsets.fromLTRB(12, 16, 16, 8),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kBorder),
      ),
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: 100,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 25,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: kBorder, strokeWidth: 0.8),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: 25,
                getTitlesWidget: (v, _) => Text(
                  '${v.round()}',
                  style: const TextStyle(color: kTextMuted, fontSize: 10),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 1,
                getTitlesWidget: (v, _) {
                  final i = v.toInt();
                  if (i < 0 || i >= labels.length) return const SizedBox();
                  return Text(
                    labels[i],
                    style: const TextStyle(color: kTextMuted, fontSize: 10),
                  );
                },
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              isCurved: true,
              curveSmoothness: 0.35,
              color: color,
              barWidth: 2.5,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                  radius: 3,
                  color: color,
                  strokeWidth: 1.5,
                  strokeColor: kBg,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [color.withOpacity(0.25), color.withOpacity(0.0)],
                ),
              ),
              spots: List.generate(
                scores.length,
                (i) => FlSpot(i.toDouble(), scores[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GoodBadBarCard extends StatelessWidget {
  final int good, bad;
  const _GoodBadBarCard({required this.good, required this.bad});

  static String _formatTime(int seconds) {
    if (seconds < 60) return '${seconds}s';
    if (seconds < 3600) {
      final m = seconds ~/ 60;
      final s = seconds % 60;
      return s > 0 ? '${m}m ${s}s' : '${m}m';
    }
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    return m > 0 ? '${h}h ${m}m' : '${h}h';
  }

  @override
  Widget build(BuildContext context) {
    final total = (good + bad).toDouble();
    if (total == 0) {
      return Container(
        height: 90,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kBorder),
        ),
        child: const Center(
          child: Text('No data yet', style: TextStyle(color: kTextSecondary)),
        ),
      );
    }
    final goodRatio = good / total;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: kGreen,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Good  ${_formatTime(good)}',
                    style: const TextStyle(color: kTextSecondary, fontSize: 12),
                  ),
                ],
              ),
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: kRed,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Bad  ${_formatTime(bad)}',
                    style: const TextStyle(color: kTextSecondary, fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Row(
              children: [
                Expanded(
                  flex: (goodRatio * 100).round(),
                  child: Container(height: 14, color: kGreen),
                ),
                Expanded(
                  flex: 100 - (goodRatio * 100).round(),
                  child: Container(height: 14, color: kRed),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BigStatCard extends StatelessWidget {
  final String label, value;
  final Color color;
  const _BigStatCard({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: kTextSecondary, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _TipCard extends StatefulWidget {
  final IconData icon;
  final String title, body;
  final Color color;
  const _TipCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.color,
  });

  @override
  State<_TipCard> createState() => _TipCardState();
}

class _TipCardState extends State<_TipCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _expanded ? widget.color.withOpacity(0.4) : kBorder,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: widget.color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(widget.icon, color: widget.color, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    style: const TextStyle(
                      color: kTextPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  if (_expanded) ...[
                    const SizedBox(height: 6),
                    Text(
                      widget.body,
                      style: const TextStyle(
                        color: kTextSecondary,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 3),
                    Text(
                      widget.body,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: kTextMuted, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
              color: kTextMuted,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorder),
      ),
      child: Row(
        children: [
          Icon(icon, color: kPrimary, size: 20),
          const SizedBox(width: 14),
          Text(
            label,
            style: const TextStyle(color: kTextSecondary, fontSize: 13),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              color: kTextPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileStat extends StatelessWidget {
  final String label, value;
  const _ProfileStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: kTextPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: const TextStyle(color: kTextSecondary, fontSize: 11),
        ),
      ],
    );
  }
}
