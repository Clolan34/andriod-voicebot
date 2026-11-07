import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../application.dart';
import '../data/online.dart';
import '../data/models.dart';
import '../data/store.dart';
import 'common.dart';

class OnlinePage extends StatefulWidget {
  const OnlinePage({super.key});
  @override
  State<OnlinePage> createState() => _OnlinePageState();
}

class _OnlinePageState extends State<OnlinePage> {
  final query = TextEditingController();
  final library = OnlineLibrary();
  List<ReferenceSummary>? results;
  bool busy = false;
  String? error;
  @override
  void dispose() {
    query.dispose();
    library.close();
    super.dispose();
  }

  Future<void> search() async {
    if (query.text.trim().isEmpty || busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final found = await library.search(query.text);
      if (mounted) setState(() => results = found);
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Could not reach online search. Check your data or Wi-Fi and try again. Your saved study materials are still available offline.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> open(String url) async {
    await guard(context, () async {
      if (!await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      )) {
        throw Exception('No browser is available to open this link.');
      }
    });
  }

  Future<void> save(ReferenceSummary summary) async {
    await guard(context, () async {
      final app = AppScope.of(context);
      final courses = await app.store.courses();
      if (courses.isEmpty) {
        message(context, 'Create a course first, then save this reference.');
        return;
      }
      final id = await showDialog<String>(
        context: context,
        builder: (dialog) => SimpleDialog(
          title: const Text('Save as a note in…'),
          children: [
            for (final c in courses)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(dialog, c.id),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(c.name),
                ),
              ),
          ],
        ),
      );
      if (id == null) return;
      await app.store.save(
        Entry(
          id: uuid.v4(),
          kind: 'note',
          courseId: id,
          topic: query.text.trim(),
          title: summary.title,
          body:
              '${summary.text}\n\nSource: Wikipedia contributors, “${summary.title}”.\n${summary.url}\n'
              'Text under CC BY-SA 4.0: https://creativecommons.org/licenses/by-sa/4.0/\n'
              'Saved ${DateTime.now().toUtc().toIso8601String()}. Reference summary; verify against your course materials.',
          data: {'source': summary.url},
        ),
      );
      message(context, 'Reference saved as an offline course note.');
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Learn online')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Another way to understand it.',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Search public reference summaries or explore free learning sites. No StudyForge account required. Internet access and normal data charges apply.',
        ),
        const SizedBox(height: 18),
        TextField(
          controller: query,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => search(),
          decoration: const InputDecoration(
            labelText: 'Search a topic',
            hintText: 'e.g. linear algebra',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: busy ? null : search,
          icon: const Icon(Icons.travel_explore),
          label: Text(busy ? 'Searching…' : 'Search Wikipedia'),
        ),
        if (busy)
          const Padding(
            padding: EdgeInsets.all(12),
            child: LinearProgressIndicator(),
          ),
        if (error != null)
          EmptyState(
            'Online search unavailable',
            error!,
            action: 'Try again',
            onAction: search,
          ),
        if (results != null && results!.isEmpty && error == null)
          const EmptyState(
            'No results found',
            'Try a shorter or different topic name.',
          ),
        for (final r in results ?? <ReferenceSummary>[])
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(r.title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  SelectableText(
                    r.text.isEmpty
                        ? 'Open the source to read this article.'
                        : r.text,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Wikipedia • reference material, not an official course source',
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: () => open(r.url),
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('Read source'),
                      ),
                      TextButton.icon(
                        onPressed: r.text.isEmpty ? null : () => save(r),
                        icon: const Icon(Icons.bookmark_add_outlined),
                        label: const Text('Save offline note'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        const Section('Free learning resources'),
        resource(
          'Khan Academy',
          'Maths, science and introductory programming',
          'https://www.khanacademy.org/',
        ),
        resource(
          'OpenStax',
          'Free peer-reviewed university textbooks',
          'https://openstax.org/subjects',
        ),
        resource(
          'MIT OpenCourseWare',
          'Open lecture notes, courses and exercises',
          'https://ocw.mit.edu/',
        ),
        resource(
          'freeCodeCamp',
          'Programming lessons and practice',
          'https://www.freecodecamp.org/learn/',
        ),
        const SizedBox(height: 12),
        const Text(
          'Resource links open in your browser. Third-party sites have their own policies and may offer optional accounts. StudyForge sends only your search text to Wikipedia; it does not upload your notes, files or progress.',
        ),
      ],
    ),
  );
  Widget resource(String name, String detail, String url) => Card(
    child: ListTile(
      leading: const Icon(Icons.language, color: teal),
      title: Text(name),
      subtitle: Text(detail),
      trailing: const Icon(Icons.open_in_new),
      onTap: () => open(url),
    ),
  );
}
