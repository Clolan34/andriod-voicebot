import 'package:flutter/material.dart';
import '../application.dart';
import '../data/models.dart';
import '../domain/study_rules.dart';
import 'common.dart';
import 'editors.dart';

class PlannerPage extends StatefulWidget {
  const PlannerPage({super.key});
  @override
  State<PlannerPage> createState() => _PlannerPageState();
}

class _PlannerPageState extends State<PlannerPage> {
  bool week = false;
  DateTime monday = mondayOf(DateTime.now());
  Future<(List<Entry>, List<Course>)> load() async {
    final s = AppScope.of(context).store;
    return (await s.entries(), await s.courses());
  }

  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<(List<Entry>, List<Course>)>(
    future: load(),
    builder: (context, s) {
      if (s.hasError) {
        return Center(child: Text('Could not load planner: ${s.error}'));
      }
      if (!s.hasData) return const Center(child: CircularProgressIndicator());
      final all =
          s.data!.$1
              .where((e) => ['session', 'assignment'].contains(e.kind))
              .toList()
            ..sort((a, b) => _at(a).compareTo(_at(b)));
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Give your next study session a place.'),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () => editEntry(context, 'session'),
                icon: const Icon(Icons.add),
                label: const Text('Study session'),
              ),
              OutlinedButton.icon(
                onPressed: () => editEntry(context, 'assignment'),
                icon: const Icon(Icons.add_task),
                label: const Text('Assignment'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Agenda')),
              ButtonSegment(value: true, label: Text('Week')),
            ],
            selected: {week},
            onSelectionChanged: (s) => setState(() => week = s.first),
          ),
          if (all.isEmpty)
            const EmptyState(
              'Your planner is ready',
              'Add a session or assignment. Reminders are optional and can be enabled in Settings.',
            ),
          if (week) ...[
            Row(
              children: [
                IconButton(
                  tooltip: 'Previous week',
                  onPressed: () =>
                      setState(() => monday = calendarOffset(monday, -7)),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    'Week of ${dateLabel(monday)}',
                    textAlign: TextAlign.center,
                  ),
                ),
                IconButton(
                  tooltip: 'Next week',
                  onPressed: () =>
                      setState(() => monday = calendarOffset(monday, 7)),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            for (var i = 0; i < 7; i++) ...[
              Section(dateLabel(calendarOffset(monday, i))),
              if (!all.any((e) => sameDay(_at(e), calendarOffset(monday, i))))
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('No sessions or deadlines'),
                ),
              for (final e in all.where(
                (e) => sameDay(_at(e), calendarOffset(monday, i)),
              ))
                tile(e, s.data!.$2),
            ],
          ] else ...[
            const Section('Sessions & deadlines'),
            for (final e in all) tile(e, s.data!.$2),
          ],
        ],
      );
    },
  );
  DateTime _at(Entry e) => DateTime.parse(
    e.data[e.kind == 'session' ? 'start' : 'due'] as String,
  ).toLocal();
  Widget tile(Entry e, List<Course> courses) {
    final done = e.data['done'] == true;
    final overdue =
        e.kind == 'assignment' && !done && _at(e).isBefore(DateTime.now());
    final detail =
        '${courseName(courses, e.courseId)} • ${stamp(_at(e).toIso8601String())}\n'
        '${done
            ? 'Completed'
            : overdue
            ? 'OVERDUE'
            : e.kind == 'session'
            ? '${e.data['minutes']} min'
            : '${e.data['priority']} priority'}';
    return EntryTile(
      e,
      subtitle: detail,
      onTap: () => showActions(e),
      trailing: Icon(
        done
            ? Icons.check_circle
            : overdue
            ? Icons.warning_amber
            : Icons.chevron_right,
        color: done
            ? teal
            : overdue
            ? amber
            : null,
      ),
    );
  }

  Future<void> showActions(Entry e) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                e.title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit details'),
              onTap: () {
                Navigator.pop(sheet);
                editEntry(context, e.kind, entry: e);
              },
            ),
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: Text(
                e.data['done'] == true ? 'Mark incomplete' : 'Mark completed',
              ),
              onTap: () async {
                Navigator.pop(sheet);
                int? actual;
                if (e.kind == 'session' && e.data['done'] != true) {
                  final minutes = TextEditingController(
                    text: '${e.data['minutes']}',
                  );
                  actual = await showDialog<int>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text('Record study time'),
                      content: TextField(
                        controller: minutes,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Minutes actually studied (1–1440)',
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(c),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () {
                            final n = int.tryParse(minutes.text);
                            if (n != null && n > 0 && n <= 1440) {
                              Navigator.pop(c, n);
                            }
                          },
                          child: const Text('Record'),
                        ),
                      ],
                    ),
                  );
                  if (actual == null) return;
                }
                await guard(context, () async {
                  final app = AppScope.of(context);
                  await app.store.save(
                    e.withData({
                      'done': e.data['done'] != true,
                      'completedMinutes': actual ?? 0,
                    }),
                  );
                  await app.changed();
                });
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete'),
              onTap: () async {
                Navigator.pop(sheet);
                if (!await confirm(
                  context,
                  'Delete ${e.kind}?',
                  'This removes the plan and its recorded completion time. Its reminder will be cancelled.',
                )) {
                  return;
                }
                await guard(context, () async {
                  final app = AppScope.of(context);
                  await app.store.delete(e.id);
                  await app.changed();
                });
              },
            ),
          ],
        ),
      ),
    );
  }
}
