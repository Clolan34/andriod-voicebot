import 'package:flutter/material.dart';
import '../application.dart';
import '../data/models.dart';
import '../domain/study_rules.dart';
import 'common.dart';
import 'practice.dart';

class ProgressPage extends StatelessWidget {
  const ProgressPage({super.key});
  Future<Map<String, dynamic>> load(BuildContext context) async {
    final store = AppScope.of(context).store;
    final entries = await store.entries(kind: 'session');
    final complete = entries.where((e) => e.data['done'] == true).toList();
    final focus = await store.db.rawQuery(
      'SELECT COUNT(*) AS n, COALESCE(SUM(minutes), 0) AS minutes FROM focus',
    );
    final reviews = await store.db.rawQuery(
      'SELECT COUNT(*) AS n FROM reviews',
    );
    final quiz = await store.db.rawQuery(
      'SELECT COUNT(*) AS n, COALESCE(SUM(correct), 0) AS correct, COALESCE(SUM(total), 0) AS total FROM attempts',
    );
    final topics = await store.db.rawQuery(
      'SELECT course_id, topic, COUNT(*) AS total, SUM(correct) AS correct FROM answers GROUP BY course_id, topic ORDER BY course_id, topic',
    );
    final byCourse = await store.db.rawQuery(
      'SELECT course_id, COUNT(*) AS total, SUM(correct) AS correct FROM answers GROUP BY course_id',
    );
    return {
      'complete': complete,
      'focus': focus.first,
      'reviews': reviews.first['n'],
      'quiz': quiz.first,
      'topics': topics,
      'byCourse': byCourse,
      'courses': await store.courses(),
    };
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: load(context),
    builder: (context, s) {
      if (s.hasError) {
        return Center(child: Text('Could not load progress: ${s.error}'));
      }
      if (!s.hasData) return const Center(child: CircularProgressIndicator());
      final d = s.data!;
      final complete = d['complete'] as List<Entry>;
      final focus = d['focus'] as Map;
      final quiz = d['quiz'] as Map;
      final courses = d['courses'] as List<Course>;
      final minutes =
          complete.fold<int>(
            0,
            (sum, e) => sum + ((e.data['completedMinutes'] as int?) ?? 0),
          ) +
          (focus['minutes'] as int);
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Your effort, made visible.',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Every number comes from your saved activity. Samples never add personal results.',
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              metric(context, '${complete.length}', 'Completed study plans'),
              metric(context, '${focus['n']}', 'Completed focus sessions'),
              metric(context, '$minutes', 'Recorded study minutes'),
              metric(context, '${d['reviews']}', 'Flashcard reviews'),
              metric(context, '${quiz['n']}', 'Quiz attempts'),
              metric(
                context,
                quiz['total'] == 0
                    ? '—'
                    : '${((quiz['correct'] as int) * 100 / (quiz['total'] as int)).round()}%',
                'Overall quiz accuracy',
              ),
            ],
          ),
          const Section('Performance by course'),
          if ((d['byCourse'] as List).isEmpty)
            const EmptyState(
              'No quiz activity yet',
              'Finish a quiz to see course and topic performance.',
            ),
          for (final row in d['byCourse'] as List)
            performance(
              context,
              courseName(courses, row['course_id'] as String),
              TopicPerformance(row['correct'] as int, row['total'] as int),
            ),
          const Section('Topics to revisit'),
          const Text(
            'At least 5 answered questions are needed per topic. Accuracy below 60% is labelled “Needs revision”. Unanswered quiz questions count as incorrect.',
          ),
          for (final row in d['topics'] as List)
            performance(
              context,
              '${courseName(courses, row['course_id'] as String)} • ${(row['topic'] as String).isEmpty ? 'General' : row['topic']}',
              TopicPerformance(row['correct'] as int, row['total'] as int),
            ),
          const Section('Study & recall by course'),
          for (final course in courses)
            FutureBuilder<List<Map<String, Object?>>>(
              future: AppScope.of(context).store.db.rawQuery(
                'SELECT COUNT(*) AS n FROM reviews WHERE course_id = ?',
                [course.id],
              ),
              builder: (context, count) => Card(
                child: ListTile(
                  title: Text(course.name),
                  subtitle: Text(
                    '${complete.where((e) => e.courseId == course.id).fold<int>(0, (sum, e) => sum + ((e.data['completedMinutes'] as int?) ?? 0))} recorded plan minutes • ${count.data?.first['n'] ?? 0} card reviews',
                  ),
                ),
              ),
            ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const HistoryPage()),
            ),
            icon: const Icon(Icons.history),
            label: const Text('Open quiz history'),
          ),
          const SizedBox(height: 12),
          const Text(
            'Focus time is recorded globally. Course statistics use completed plans, saved quiz answers and flashcard reviews assigned to each course.',
          ),
        ],
      );
    },
  );
  Widget metric(BuildContext context, String value, String label) => SizedBox(
    width: (MediaQuery.sizeOf(context).width - 52) / 2,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 6),
            Text(label),
          ],
        ),
      ),
    ),
  );
  Widget performance(BuildContext context, String name, TopicPerformance p) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: p.accuracy,
                minHeight: 7,
                borderRadius: BorderRadius.circular(6),
              ),
              const SizedBox(height: 8),
              Text(
                '${p.correct} / ${p.total} correct • ${p.label}',
                style: TextStyle(
                  color: p.total >= 5 && p.accuracy < .6 ? amber : null,
                ),
              ),
            ],
          ),
        ),
      );
}
