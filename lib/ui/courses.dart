import 'package:flutter/material.dart';
import '../application.dart';
import '../data/models.dart';
import '../data/store.dart';
import 'common.dart';
import 'editors.dart';
import 'documents.dart';

class CoursesPage extends StatelessWidget {
  const CoursesPage({super.key});
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return FutureBuilder<List<Course>>(
      future: app.store.courses(),
      builder: (context, s) {
        if (s.hasError) {
          return Center(child: Text('Could not load courses: ${s.error}'));
        }
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('A little structure. A lot more clarity.'),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => editCourse(context),
              icon: const Icon(Icons.add),
              label: const Text('Add course'),
            ),
            if (s.data!.isEmpty)
              const EmptyState(
                'Make room for your first course',
                'Add its name, course code and topics. Your notes and practice stay organised here.',
              ),
            for (final c in s.data!)
              Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: CircleAvatar(
                    backgroundColor: Color(c.color),
                    child: const Icon(Icons.auto_stories, color: Colors.white),
                  ),
                  title: Text(
                    c.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    [c.code, c.topics].where((v) => v.isNotEmpty).join(' • '),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => CoursePage(courseId: c.id),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

Future<void> editCourse(BuildContext context, {Course? course}) async {
  final name = TextEditingController(text: course?.name ?? '');
  final code = TextEditingController(text: course?.code ?? '');
  final topics = TextEditingController(text: course?.topics ?? '');
  var color = course?.color ?? 0xff007e78;
  var saving = false;
  final form = GlobalKey<FormState>();
  await showDialog<void>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (dialog, set) => AlertDialog(
        title: Text(course == null ? 'Add course' : 'Edit course'),
        content: SizedBox(
          width: 380,
          child: Form(
            key: form,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Course name'),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Enter a course name'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: code,
                    decoration: const InputDecoration(
                      labelText: 'Course code (optional)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: topics,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Topics (separate with commas)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [0xff007e78, 0xff243e69, 0xff845700, 0xff6b4184]
                        .map(
                          (v) => IconButton(
                            tooltip: 'Course colour ${v.toRadixString(16)}',
                            onPressed: () => set(() => color = v),
                            icon: Icon(
                              color == v ? Icons.check_circle : Icons.circle,
                              color: Color(v),
                              size: 32,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: saving ? null : () => Navigator.pop(dialog),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: saving
                ? null
                : () async {
                    if (!form.currentState!.validate()) return;
                    set(() => saving = true);
                    await guard(context, () async {
                      await AppScope.of(context).store.saveCourse(
                        Course(
                          id: course?.id ?? uuid.v4(),
                          name: name.text.trim(),
                          code: code.text.trim(),
                          topics: topics.text.trim(),
                          color: color,
                        ),
                      );
                      if (dialog.mounted) Navigator.pop(dialog);
                    });
                    if (dialog.mounted) set(() => saving = false);
                  },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  // Dialog route animations may still reference fields immediately after pop.
  await Future<void>.delayed(const Duration(milliseconds: 250));
  name.dispose();
  code.dispose();
  topics.dispose();
}

class CoursePage extends StatefulWidget {
  final String courseId;
  const CoursePage({required this.courseId, super.key});
  @override
  State<CoursePage> createState() => _CoursePageState();
}

class _CoursePageState extends State<CoursePage> {
  String search = '';
  bool favorites = false;
  Future<(Course?, List<Entry>)> load() async {
    final store = AppScope.of(context).store;
    final courses = await store.courses();
    final found = courses.where((c) => c.id == widget.courseId).firstOrNull;
    final entries = await store.entries(
      kind: 'note',
      courseId: widget.courseId,
      search: search,
    );
    return (
      found,
      favorites
          ? entries.where((n) => n.data['favorite'] == true).toList()
          : entries,
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AppScope.of(context),
    builder: (context, _) => FutureBuilder<(Course?, List<Entry>)>(
      future: load(),
      builder: (context, s) {
        if (s.hasError) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(child: Text('Could not load course: ${s.error}')),
          );
        }
        if (!s.hasData) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        final c = s.data!.$1;
        if (c == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyState(
              'Course removed',
              'This course no longer exists.',
            ),
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(c.name),
            actions: [
              IconButton(
                tooltip: 'Edit course',
                onPressed: () => editCourse(context, course: c),
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                tooltip: 'Delete course',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  if (!await confirm(
                    context,
                    'Delete ${c.name}?',
                    'This deletes its notes, PDFs, sessions, assignments, questions, cards, papers and course-level progress. Export a backup first if needed.',
                  )) {
                    return;
                  }
                  await guard(context, () async {
                    final app = AppScope.of(context);
                    await app.store.deleteCourse(c.id);
                    await app.changed();
                    if (context.mounted) Navigator.pop(context);
                  });
                },
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (c.code.isNotEmpty || c.topics.isNotEmpty)
                Text('${c.code}\n${c.topics}'),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => editEntry(context, 'note', courseId: c.id),
                icon: const Icon(Icons.add),
                label: const Text('Add note or PDF'),
              ),
              const SizedBox(height: 16),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Search note title or content',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (v) => setState(() => search = v),
              ),
              FilterChip(
                label: const Text('Favourites only'),
                selected: favorites,
                onSelected: (v) => setState(() => favorites = v),
              ),
              if (s.data!.$2.isEmpty)
                const EmptyState(
                  'No notes here yet',
                  'Add your own text or import a PDF using the button above.',
                ),
              for (final e in s.data!.$2)
                EntryTile(
                  e,
                  subtitle: e.topic.isEmpty ? 'General notes' : e.topic,
                  trailing: IconButton(
                    tooltip: 'Toggle favourite',
                    icon: Icon(
                      e.data['favorite'] == true
                          ? Icons.star
                          : Icons.star_border,
                    ),
                    onPressed: () => guard(
                      context,
                      () => AppScope.of(context).store.save(
                        e.withData({'favorite': e.data['favorite'] != true}),
                      ),
                    ),
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => DocumentPage(entryId: e.id),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
}
