import 'package:flutter/material.dart';

import '../../core/engagement_alerts.dart';
import '../../core/progress.dart';
import '../../core/rewards.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../data/app_database.dart';

const _achievementIcons = {
  'first_game': Icons.flag_rounded,
  'ten_games': Icons.emoji_events_rounded,
  'fifty_games': Icons.military_tech_rounded,
  'streak3': Icons.local_fire_department_rounded,
  'streak7': Icons.whatshot_rounded,
  'all_games': Icons.apps_rounded,
  'sharp': Icons.stars_rounded,
};

/// My Progress: star level and XP, games played, best streak, achievements and
/// the week at a glance. It counts playing, never ability or health.
class ProgressScreen extends StatelessWidget {
  const ProgressScreen({
    super.key,
    required this.db,
    required this.patientId,
    required this.lang,
  });
  final AppDatabase db;
  final String patientId, lang;

  String t(String k) => tr(lang, k);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t('tileProgress'))),
      body: SafeArea(
        child: FutureBuilder<List<SessionRecord>>(
          future: db.sessionRecords(patientId),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return _content(context, snap.data!);
          },
        ),
      ),
    );
  }

  Widget _content(BuildContext context, List<SessionRecord> sessions) {
    final rewards = computeRewards(sessions);
    final times = sessions.map((s) => s.endedAt).toList();
    final today = DateTime.now();
    final week = sessionsLast7Days(times, today);
    final maxCount = week.fold<int>(1, (m, c) => c > m ? c : m);
    final rank = t('rank_${rewards.level.clamp(1, 5)}');

    Widget stat(IconData icon, Color fg, Color bg, String value, String label) =>
        Expanded(
          child: AppCard(
            child: Column(
              children: [
                IconBadge(icon: icon, fg: fg, bg: bg, size: 44, circle: true),
                const SizedBox(height: 8),
                Text(value,
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w700)),
                Text(label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: Palette.muted)),
              ],
            ),
          ),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        // Level card
        AppCard(
          color: const Color(0xFFFFF4D6),
          child: Row(
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                      colors: [Color(0xFFFFD86B), Color(0xFFF5A524)]),
                ),
                child: Center(
                  child: Stack(alignment: Alignment.center, children: [
                    const Icon(Icons.star_rounded,
                        size: 54, color: Colors.white),
                    Text('${rewards.level}',
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFB36B00))),
                  ]),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(trf(lang, 'levelWord', a: rewards.level),
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w700)),
                    Text(rank,
                        style: const TextStyle(
                            fontSize: 15, color: Palette.muted)),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: rewards.levelProgress,
                        minHeight: 10,
                        backgroundColor: Colors.white,
                        color: Palette.sky,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                        trf(lang, 'xpLabel',
                            a: rewards.xp, b: rewards.nextLevelXp),
                        style: const TextStyle(
                            fontSize: 13, color: Palette.muted)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(children: [
          stat(Icons.sports_esports_rounded, Palette.blue, Palette.tileBlue,
              '${sessions.length}', t('gamesPlayed')),
          const SizedBox(width: 14),
          stat(Icons.local_fire_department_rounded, Palette.orange,
              Palette.tileOrange, trf(lang, bestStreak(times) == 1 ? 'dayUnit' : 'daysUnit',
                  a: bestStreak(times)),
              t('bestStreak')),
        ]),
        const SizedBox(height: 14),

        // Achievements
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(t('achievements'),
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 8),
                Text('${rewards.unlockedCount} / ${rewards.achievements.length}',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Palette.orange)),
              ]),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final a in rewards.achievements)
                    SizedBox(
                      width: 84,
                      child: Column(children: [
                        IconBadge(
                          icon: _achievementIcons[a.id] ?? Icons.star_rounded,
                          fg: a.unlocked ? Palette.orange : Palette.muted,
                          bg: a.unlocked ? Palette.tileOrange : const Color(0xFFEFEFEF),
                          size: 52,
                          circle: true,
                        ),
                        const SizedBox(height: 4),
                        Text(t('ach_${a.id}'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 11.5,
                                color: a.unlocked ? Palette.ink : Palette.muted)),
                      ]),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Weekly progress
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t('weeklyProgress'),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              SizedBox(
                height: 130,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < 7; i++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Container(
                                height: 8 + 80.0 * week[i] / maxCount,
                                decoration: BoxDecoration(
                                  color: week[i] == 0
                                      ? const Color(0xFFE5E7EB)
                                      : (i.isEven ? Palette.brand : Palette.sky),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                  'MTWTFSS'[today
                                          .subtract(Duration(days: 6 - i))
                                          .weekday -
                                      1],
                                  style: const TextStyle(
                                      fontSize: 12, color: Palette.muted)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(t('progressNote2'),
            style: const TextStyle(fontSize: 13, color: Palette.muted)),
      ],
    );
  }
}
