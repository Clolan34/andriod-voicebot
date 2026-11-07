import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../application.dart';
import '../data/models.dart';
import '../domain/study_rules.dart';
import 'common.dart';
import 'documents.dart';
import 'editors.dart';
import 'online.dart';

class PracticePage extends StatefulWidget {
  final String initialKind;
  const PracticePage({this.initialKind = 'question', super.key});
  @override
  State<PracticePage> createState() => _PracticePageState();
}

class _PracticePageState extends State<PracticePage> {
  late String kind = widget.initialKind;
  String? course;
  String? topic;
  bool incorrect = false;
  Future<(List<Entry>, List<Course>)> load() async {
    final s = AppScope.of(context).store;
    var entries = await s.entries(kind: kind, courseId: course);
    if (incorrect && kind == 'question') {
      final rows = await s.db.rawQuery(
        'SELECT question_id FROM answers WHERE rowid IN (SELECT MAX(rowid) FROM answers GROUP BY question_id) AND correct = 0',
      );
      final ids = rows.map((r) => r['question_id']).toSet();
      entries = entries.where((e) => ids.contains(e.id)).toList();
    }
    return (entries, await s.courses());
  }

  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<(List<Entry>, List<Course>)>(
    future: load(),
    builder: (context, s) {
      if (s.hasError) {
        return Center(child: Text('Could not load practice: ${s.error}'));
      }
      if (!s.hasData) return const Center(child: CircularProgressIndicator());
      final topics =
          s.data!.$1
              .map((e) => e.topic)
              .where((v) => v.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
      final list = s.data!.$1
          .where((e) => topic == null || e.topic == topic)
          .toList();
      final courses = s.data!.$2;
      final validCourse = courses.any((c) => c.id == course) ? course : null;
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'question', label: Text('Quizzes')),
              ButtonSegment(value: 'card', label: Text('Cards')),
              ButtonSegment(value: 'paper', label: Text('Papers')),
            ],
            selected: {kind},
            onSelectionChanged: (v) => setState(() {
              kind = v.first;
              topic = null;
              incorrect = false;
            }),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            key: ValueKey('course-$validCourse'),
            initialValue: validCourse,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Course'),
            items: [
              const DropdownMenuItem<String>(
                value: null,
                child: Text('All courses'),
              ),
              ...courses.map(
                (c) => DropdownMenuItem(
                  value: c.id,
                  child: Text(c.name, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
            onChanged: (v) => setState(() {
              course = v;
              topic = null;
            }),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('topic-$topic-${topics.join()}'),
            initialValue: topics.contains(topic) ? topic : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Topic'),
            items: [
              const DropdownMenuItem<String>(
                value: null,
                child: Text('All topics'),
              ),
              ...topics.map(
                (t) => DropdownMenuItem(
                  value: t,
                  child: Text(t, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
            onChanged: (v) => setState(() => topic = v),
          ),
          const SizedBox(height: 16),
          if (kind == 'question') ...[
            FilterChip(
              label: const Text('Previously incorrect'),
              selected: incorrect,
              onSelected: (v) => setState(() {
                incorrect = v;
                topic = null;
              }),
            ),
            FilledButton.icon(
              onPressed: list.isEmpty ? null : () => startQuiz(list, false),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Untimed practice'),
            ),
            OutlinedButton.icon(
              onPressed: list.isEmpty ? null : () => startQuiz(list, true),
              icon: const Icon(Icons.timer_outlined),
              label: const Text('Timed quiz'),
            ),
            TextButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const HistoryPage()),
              ),
              icon: const Icon(Icons.history),
              label: const Text('Attempt history'),
            ),
          ],
          if (kind == 'card') ...[
            FilledButton.icon(
              onPressed: list.any(_due)
                  ? () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            CardReviewPage(cards: list.where(_due).toList()),
                      ),
                    )
                  : null,
              icon: const Icon(Icons.style_outlined),
              label: Text('Review ${list.where(_due).length} due cards'),
            ),
            const SizedBox(height: 8),
            const Text(
              'Reveal the answer, then rate recall honestly. Again repeats in 10 minutes; Hard, Good and Easy grow the interval.',
            ),
          ],
          if (kind == 'paper')
            const Text(
              'Import papers you have permission to use. Link a marking guide and save your own answers. There is no automatic marking.',
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => editEntry(context, kind, courseId: validCourse),
            icon: const Icon(Icons.add),
            label: Text(
              kind == 'question'
                  ? 'Create question'
                  : kind == 'card'
                  ? 'Create flashcard'
                  : 'Import past paper',
            ),
          ),
          if (list.isEmpty)
            EmptyState(
              'No ${kind == 'question'
                  ? 'questions'
                  : kind == 'card'
                  ? 'cards'
                  : 'papers'} found',
              'Add your own material, change the filter, or load demo questions and cards from Settings.',
            ),
          for (final e in list)
            EntryTile(
              e,
              subtitle:
                  '${courseName(courses, e.courseId)}${e.topic.isEmpty ? '' : ' • ${e.topic}'}'
                  '${e.data['sample'] == true ? '\nDemonstration • not official questions' : ''}'
                  '${kind == 'card' ? '\nNext review: ${stamp(e.data['due'] as String)}' : ''}'
                  '${kind == 'paper' ? '\n${e.data['year']} • Semester ${e.data['semester']}' : ''}',
              trailing: const Icon(Icons.chevron_right),
              onTap: () => kind == 'paper'
                  ? Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => DocumentPage(entryId: e.id),
                      ),
                    )
                  : manage(e),
            ),
          const Section('Learn online'),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const OnlinePage()),
            ),
            icon: const Icon(Icons.public),
            label: const Text('Search topics & free resources'),
          ),
        ],
      );
    },
  );
  bool _due(Entry e) =>
      !DateTime.parse(e.data['due'] as String).isAfter(DateTime.now());
  Future<void> startQuiz(List<Entry> list, bool timed) async {
    var seconds = 0;
    if (timed) {
      final c = TextEditingController(text: '${list.length}');
      final minutes = await showDialog<int>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Quiz time limit'),
          content: TextField(
            controller: c,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Minutes (1–180)'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final n = int.tryParse(c.text);
                if (n != null && n >= 1 && n <= 180) Navigator.pop(dialog, n);
              },
              child: const Text('Begin'),
            ),
          ],
        ),
      );
      if (minutes == null) return;
      seconds = minutes * 60;
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => QuizPage(questions: list, seconds: seconds),
      ),
    );
  }

  Future<void> manage(Entry e) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(e.title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              if (e.kind == 'question')
                for (var i = 0; i < 4; i++)
                  Text(
                    '${i == e.data['correct'] ? '✓' : '•'} ${(e.data['options'] as List)[i]}',
                  ),
              const SizedBox(height: 8),
              Text(e.body),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () {
                  Navigator.pop(sheet);
                  editEntry(context, e.kind, entry: e);
                },
                child: const Text('Edit'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(sheet);
                  if (!await confirm(
                    context,
                    'Delete ${e.kind}?',
                    'This removes the item and its card review records, if any. Saved quiz answer snapshots remain in attempt history.',
                  )) {
                    return;
                  }
                  await guard(context, () async {
                    await AppScope.of(context).store.delete(e.id);
                  });
                },
                child: const Text('Delete'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class QuizPage extends StatefulWidget {
  final List<Entry> questions;
  final int seconds;
  const QuizPage({required this.questions, this.seconds = 0, super.key});
  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  late final List<int?> answers = List.filled(widget.questions.length, null);
  DateTime? deadline;
  Timer? timer;
  bool submitted = false;
  bool allowLeave = false;
  bool saving = false;
  String? failure;
  int left = 0;
  @override
  void initState() {
    super.initState();
    if (widget.seconds > 0) {
      deadline = DateTime.now().add(Duration(seconds: widget.seconds));
      left = widget.seconds;
      timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || submitted) return;
        setState(
          () => left = deadline!
              .difference(DateTime.now())
              .inSeconds
              .clamp(0, widget.seconds),
        );
        if (left == 0 && !saving) submit();
      });
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> submit() async {
    if (saving || submitted) return;
    setState(() {
      saving = true;
      failure = null;
    });
    try {
      await AppScope.of(context).store.recordQuiz(widget.questions, answers);
      timer?.cancel();
      if (mounted) {
        setState(() {
          submitted = true;
          saving = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          failure =
              'Result could not be saved. Free some storage and tap Submit to retry.';
        });
      }
      timer?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    final score = QuizScore.calculate(
      widget.questions.map((q) => q.data['correct'] as int).toList(),
      answers,
    );
    return PopScope(
      canPop: submitted || allowLeave,
      onPopInvokedWithResult: (popped, result) async {
        if (popped) return;
        if (await confirm(
              context,
              'Leave quiz?',
              'This unfinished attempt will not be recorded.',
              action: 'Leave',
            ) &&
            context.mounted) {
          setState(() => allowLeave = true);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.pop(context);
          });
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(submitted ? 'Quiz results' : 'Practice quiz'),
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (deadline != null && !submitted)
              Text(
                'Time left ${left ~/ 60}:${(left % 60).toString().padLeft(2, '0')}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            if (submitted)
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    '${score.percent}% • ${score.correct} / ${score.total} correct\nSaved to your history.',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
              ),
            if (failure != null)
              Text(failure!, style: const TextStyle(color: amber)),
            for (var i = 0; i < widget.questions.length; i++) question(i),
            if (!submitted)
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        if (answers.any((a) => a == null) &&
                            !await confirm(
                              context,
                              'Submit with unanswered questions?',
                              'Unanswered questions count as incorrect.',
                              action: 'Submit',
                            )) {
                          return;
                        }
                        await submit();
                      },
                child: Text(saving ? 'Saving…' : 'Submit quiz'),
              ),
            if (submitted)
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Back to practice'),
              ),
          ],
        ),
      ),
    );
  }

  Widget question(int i) {
    final q = widget.questions[i];
    final options = q.data['options'] as List;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${i + 1}. ${q.title}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (q.data['sample'] == true)
              const Text(
                'Demonstration question • not official material',
                style: TextStyle(fontSize: 12),
              ),
            const SizedBox(height: 12),
            for (var j = 0; j < 4; j++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.all(14),
                    backgroundColor: submitted && j == q.data['correct']
                        ? Theme.of(context).colorScheme.primaryContainer
                        : answers[i] == j
                        ? Theme.of(context).colorScheme.secondaryContainer
                        : null,
                  ),
                  onPressed:
                      submitted || saving || (deadline != null && left == 0)
                      ? null
                      : () => setState(() => answers[i] = j),
                  child: Row(
                    children: [
                      Icon(
                        answers[i] == j
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '${options[j]}',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                      if (submitted && j == q.data['correct'])
                        const Icon(Icons.check_circle, color: teal),
                    ],
                  ),
                ),
              ),
            if (submitted) ...[
              const SizedBox(height: 12),
              Text(
                answers[i] == q.data['correct']
                    ? 'Correct'
                    : 'Incorrect${answers[i] == null ? ' • unanswered' : ''}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                'Correct answer: ${options[q.data['correct'] as int]}\n${q.body}',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class CardReviewPage extends StatefulWidget {
  final List<Entry> cards;
  const CardReviewPage({required this.cards, super.key});
  @override
  State<CardReviewPage> createState() => _CardReviewPageState();
}

class _CardReviewPageState extends State<CardReviewPage> {
  int index = 0;
  bool revealed = false;
  bool busy = false;
  String? next;
  @override
  Widget build(BuildContext context) {
    final complete = index >= widget.cards.length;
    final card = complete ? null : widget.cards[index];
    return Scaffold(
      appBar: AppBar(title: const Text('Flashcard review')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (complete)
            EmptyState(
              'Review complete',
              'You reviewed $index cards. $next',
              action: 'Back to practice',
              onAction: () => Navigator.pop(context),
            )
          else ...[
            Text(
              'Card ${index + 1} of ${widget.cards.length} • ${card!.topic}',
            ),
            const SizedBox(height: 24),
            Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => setState(() => revealed = true),
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    children: [
                      Text(
                        card.title,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        revealed ? card.body : 'Tap to reveal answer',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (!revealed)
              FilledButton(
                onPressed: () => setState(() => revealed = true),
                child: const Text('Reveal answer'),
              ),
            if (revealed) ...[
              const Section('How well did you remember?'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ['Again', 'Hard', 'Good', 'Easy']
                    .map(
                      (grade) => FilledButton.tonal(
                        onPressed: busy
                            ? null
                            : () async {
                                setState(() => busy = true);
                                await guard(context, () async {
                                  final now = DateTime.now();
                                  final schedule = ReviewSchedule.next(
                                    now,
                                    (card.data['interval'] as int?) ?? 0,
                                    (card.data['reviews'] as int?) ?? 0,
                                    grade,
                                  );
                                  await AppScope.of(
                                    context,
                                  ).store.review(card, grade, now: now);
                                  if (mounted) {
                                    setState(() {
                                      next =
                                          'Last card next due: ${stamp(schedule.due.toIso8601String())}';
                                      index++;
                                      revealed = false;
                                    });
                                  }
                                });
                                if (mounted) setState(() => busy = false);
                              },
                        child: Text(grade),
                      ),
                    )
                    .toList(),
              ),
            ],
            if (next != null)
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Text(next!),
              ),
          ],
        ],
      ),
    );
  }
}

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Quiz attempt history')),
    body: FutureBuilder<List<Map<String, Object?>>>(
      future: AppScope.of(
        context,
      ).store.db.query('attempts', orderBy: 'at DESC'),
      builder: (context, s) {
        if (s.hasError) return Center(child: Text('${s.error}'));
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        if (s.data!.isEmpty) {
          return const EmptyState(
            'No attempts yet',
            'Finish a quiz to save its score and answer explanations.',
          );
        }
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            for (final a in s.data!)
              Card(
                child: ListTile(
                  title: Text('${a['correct']} / ${a['total']} correct'),
                  subtitle: Text(stamp(a['at'] as String)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => AttemptPage(id: a['id'] as String),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}

class AttemptPage extends StatelessWidget {
  final String id;
  const AttemptPage({required this.id, super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Saved answers')),
    body: FutureBuilder<List<Map<String, Object?>>>(
      future: AppScope.of(context).store.db.query(
        'answers',
        where: 'attempt_id = ?',
        whereArgs: [id],
        orderBy: 'rowid',
      ),
      builder: (context, s) {
        if (s.hasError) return Center(child: Text('${s.error}'));
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            for (final a in s.data!)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a['title'] as String,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Your answer: ${a['chosen'] == null ? 'Unanswered' : (jsonDecode(a['options'] as String) as List)[a['chosen'] as int]}',
                      ),
                      Text(
                        'Correct answer: ${(jsonDecode(a['options'] as String) as List)[a['expected'] as int]}',
                      ),
                      Text(a['explanation'] as String),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}
