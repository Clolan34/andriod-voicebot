import 'package:flutter/material.dart';
import '../application.dart';
import '../data/models.dart';
import '../domain/study_rules.dart';
import 'common.dart';
import 'editors.dart';
import 'focus.dart';
import 'online.dart';

class HomePage extends StatelessWidget {
  final ValueChanged<int> onNavigate;
  final VoidCallback onReviewCards;
  const HomePage({
    required this.onNavigate,
    required this.onReviewCards,
    super.key,
  });
  Future<(List<Entry>, List<Map<String, Object?>>)> load(
    BuildContext context,
  ) async {
    final s = AppScope.of(context).store;
    return (
      await s.entries(),
      await s.db.query('attempts', orderBy: 'at DESC', limit: 3),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<(List<Entry>, List<Map<String, Object?>>)>(
    future: load(context),
    builder: (context, s) {
      if (s.hasError) {
        return Center(child: Text('Could not load dashboard: ${s.error}'));
      }
      if (!s.hasData) return const Center(child: CircularProgressIndicator());
      final app = AppScope.of(context);
      final now = DateTime.now();
      final entries = s.data!.$1;
      final sessions =
          entries
              .where(
                (e) =>
                    e.kind == 'session' &&
                    sameDay(
                      DateTime.parse(e.data['start'] as String).toLocal(),
                      now,
                    ),
              )
              .toList()
            ..sort(
              (a, b) => (a.data['start'] as String).compareTo(
                b.data['start'] as String,
              ),
            );
      final assignments =
          entries
              .where((e) => e.kind == 'assignment' && e.data['done'] != true)
              .toList()
            ..sort(
              (a, b) =>
                  (a.data['due'] as String).compareTo(b.data['due'] as String),
            );
      final due = entries
          .where(
            (e) =>
                e.kind == 'card' &&
                !DateTime.parse(e.data['due'] as String).isAfter(now),
          )
          .length;
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(
            'Hello${app.name.isEmpty ? '' : ', ${app.name}'}',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text('Small steps today. Stronger understanding tomorrow.'),
          Card(
            color: navy,
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'MAKE SPACE TO FOCUS',
                    style: TextStyle(
                      color: Color(0xff8fe4d5),
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'One session at a time.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 25,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const FocusPage(),
                      ),
                    ),
                    icon: const Icon(Icons.timer_outlined),
                    label: const Text('Open focus timer'),
                  ),
                ],
              ),
            ),
          ),
          const Section('Quick start'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                avatar: const Icon(Icons.note_add_outlined),
                label: const Text('Add note'),
                onPressed: () => editEntry(context, 'note'),
              ),
              ActionChip(
                avatar: const Icon(Icons.quiz_outlined),
                label: const Text('Start quiz'),
                onPressed: () => onNavigate(3),
              ),
              ActionChip(
                avatar: const Icon(Icons.style_outlined),
                label: const Text('Review cards'),
                onPressed: onReviewCards,
              ),
              ActionChip(
                avatar: const Icon(Icons.event_outlined),
                label: const Text('Plan session'),
                onPressed: () => editEntry(context, 'session'),
              ),
            ],
          ),
          const Section('Today’s sessions'),
          if (sessions.isEmpty)
            EmptyState(
              'A fresh page for today',
              'Plan a small study session to get started.',
              action: 'Plan a session',
              onAction: () => editEntry(context, 'session'),
            ),
          for (final e in sessions)
            EntryTile(
              e,
              subtitle:
                  '${stamp(e.data['start'] as String)} • ${e.data['minutes']} min${e.data['done'] == true ? ' • Complete' : ''}',
              onTap: () => onNavigate(2),
            ),
          const Section('Assignment deadlines'),
          if (assignments.isEmpty)
            EmptyState(
              'No pending deadlines',
              'Add your next assignment when you receive it.',
              action: 'Add assignment',
              onAction: () => editEntry(context, 'assignment'),
            ),
          for (final e in assignments.take(4))
            EntryTile(
              e,
              subtitle:
                  '${stamp(e.data['due'] as String)}${DateTime.parse(e.data['due'] as String).isBefore(now) ? ' • OVERDUE' : ''}',
              onTap: () => onNavigate(2),
            ),
          const Section('Revision ready'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.style_outlined, color: teal),
              title: Text('$due flashcards due'),
              subtitle: const Text(
                'A few minutes of recall makes a difference.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: onReviewCards,
            ),
          ),
          const Section('Recent quiz results'),
          if (s.data!.$2.isEmpty)
            EmptyState(
              'Your progress starts with practice',
              'Create questions or load the original demo bank in Settings.',
              action: 'Open practice',
              onAction: () => onNavigate(3),
            ),
          for (final a in s.data!.$2)
            Card(
              child: ListTile(
                leading: const Icon(Icons.insights_outlined),
                title: Text('${a['correct']} / ${a['total']} correct'),
                subtitle: Text(stamp(a['at'] as String)),
                onTap: () => onNavigate(4),
              ),
            ),
          const Section('Explore online'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.public, color: teal),
              title: const Text('Find another explanation'),
              subtitle: const Text(
                'Topic search and free learning resources. No account needed.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const OnlinePage()),
              ),
            ),
          ),
        ],
      );
    },
  );
}
