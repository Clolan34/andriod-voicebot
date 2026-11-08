import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import '../application.dart';
import '../data/models.dart';
import 'common.dart';
import 'editors.dart';
import 'ai.dart';

class DocumentPage extends StatelessWidget {
  final String entryId;
  const DocumentPage({required this.entryId, super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AppScope.of(context),
    builder: (context, _) => FutureBuilder<List<Entry>>(
      future: AppScope.of(context).store.entries(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(appBar: AppBar(), body: Text('${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        final e = snapshot.data!.where((e) => e.id == entryId).firstOrNull;
        if (e == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyState(
              'Document removed',
              'Return to your course.',
            ),
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(e.title),
            actions: [
              IconButton(
                tooltip: 'Edit',
                onPressed: () => editEntry(context, e.kind, entry: e),
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  if (!await confirm(
                    context,
                    'Delete ${e.title}?',
                    'This removes this record, its attached PDF and marking guide, if any.',
                  )) {
                    return;
                  }
                  await guard(context, () async {
                    final app = AppScope.of(context);
                    await app.store.delete(e.id);
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
              Text(e.topic, style: Theme.of(context).textTheme.titleMedium),
              if (e.kind == 'paper')
                Text('${e.data['year']} • Semester ${e.data['semester']}'),
              const SizedBox(height: 16),
              if (e.data['file'] != null)
                FilledButton.icon(
                  onPressed: () =>
                      openPdf(context, e.title, e.data['file'] as String),
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('Read PDF offline'),
                ),
              if (e.data['guide'] != null)
                OutlinedButton.icon(
                  onPressed: () => openPdf(
                    context,
                    'Marking guide',
                    e.data['guide'] as String,
                  ),
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('Open linked marking guide'),
                ),
              if (e.kind == 'paper') ...[
                const Section('Practice timer'),
                const PaperTimer(),
                const Section('Your answers & self-assessment'),
                const Text(
                  'Use Edit to save your written answers and reflections. StudyForge does not automatically mark papers.',
                ),
              ],
              const SizedBox(height: 20),
              SelectableText(e.body.isEmpty ? 'No written notes yet.' : e.body),
              if (e.body.trim().isNotEmpty) ...[
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => Navigator.push(context,
                    MaterialPageRoute<void>(builder: (_) => StudyAiPage(
                      initialText: e.body, courseId: e.courseId))),
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: const Text('Summarize written text with AI'),
                ),
              ],
            ],
          ),
        );
      },
    ),
  );
}

void openPdf(BuildContext context, String title, String name) => Navigator.push(
  context,
  MaterialPageRoute<void>(
    builder: (_) => PdfPage(title: title, name: name),
  ),
);

class PdfPage extends StatefulWidget {
  final String title;
  final String name;
  const PdfPage({required this.title, required this.name, super.key});
  @override
  State<PdfPage> createState() => _PdfPageState();
}

class _PdfPageState extends State<PdfPage> {
  PdfControllerPinch? controller;
  String? error;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (controller != null || error != null) return;
    try {
      controller = PdfControllerPinch(
        document: PdfDocument.openFile(
          AppScope.of(context).files.file(widget.name).path,
        ),
      );
    } catch (e) {
      error = '$e';
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: error != null
        ? EmptyState(
            'Cannot open this PDF',
            'It may be damaged or unsupported. Import a new copy. $error',
          )
        : PdfViewPinch(
            controller: controller!,
            builders: PdfViewPinchBuilders<DefaultBuilderOptions>(
              options: const DefaultBuilderOptions(),
              errorBuilder: (_, e) => const EmptyState(
                'Cannot read this PDF',
                'The file may be damaged, encrypted or unsupported. Try importing a different copy.',
              ),
            ),
          ),
  );
}

class PaperTimer extends StatefulWidget {
  const PaperTimer({super.key});
  @override
  State<PaperTimer> createState() => _PaperTimerState();
}

class _PaperTimerState extends State<PaperTimer> {
  DateTime? deadline;
  int left = 60 * 60;
  Timer? ticker;
  @override
  void initState() {
    super.initState();
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (deadline != null && mounted) {
        setState(() {
          left = deadline!.difference(DateTime.now()).inSeconds.clamp(0, 86400);
        });
      }
    });
  }

  @override
  void dispose() {
    ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text(
            '${left ~/ 60}:${(left % 60).toString().padLeft(2, '0')}',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: () => setState(() {
                  if (deadline == null) {
                    deadline = DateTime.now().add(Duration(seconds: left));
                  } else {
                    deadline = null;
                  }
                }),
                child: Text(deadline == null ? 'Start / resume' : 'Pause'),
              ),
              TextButton(
                onPressed: () => setState(() {
                  deadline = null;
                  left = 3600;
                }),
                child: const Text('Reset 60 min'),
              ),
            ],
          ),
          const Text(
            'Timer continues while reading a PDF. This practice timer is not recorded as study time.',
          ),
        ],
      ),
    ),
  );
}
