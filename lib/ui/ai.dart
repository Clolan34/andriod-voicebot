import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../application.dart';
import '../data/ai_model.dart';
import '../data/local_ai.dart';
import '../data/models.dart';
import '../data/store.dart';
import '../domain/ai_prompts.dart';
import 'common.dart';

class StudyAiPage extends StatefulWidget {
  final String initialText;
  final String? courseId;
  final LocalStudyAi? ai;
  final AiModelFile? model;
  const StudyAiPage({
    this.initialText = '',
    this.courseId,
    this.ai,
    this.model,
    super.key,
  });
  @override
  State<StudyAiPage> createState() => _StudyAiPageState();
}

class _StudyAiPageState extends State<StudyAiPage> with WidgetsBindingObserver {
  late final TextEditingController input;
  late LocalStudyAi ai;
  AiModelFile? model;
  StudyAiMode mode = StudyAiMode.tutor;
  final history = <StudyAiTurn>[];
  String notes = '';
  String noteName = '';
  String result = '';
  String? error;
  bool ready = false;
  bool checking = true;
  bool busy = false;
  bool generating = false;
  bool stopped = false;
  int received = 0;
  String? selectedCourse;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    input = TextEditingController(text: widget.initialText);
    ai = widget.ai ?? LocalStudyAi(PhoneAiEngine());
    selectedCourse = widget.courseId;
    if (widget.initialText.isNotEmpty) mode = StudyAiMode.summary;
    unawaited(checkModel());
  }

  Future<void> checkModel() async {
    try {
      final found = widget.model ?? await AiModelFile.open();
      model = found;
      final exists = await found.exists();
      if (exists) await found.verify();
      if (mounted) setState(() => ready = exists);
    } catch (_) {
      if (mounted) {
        model ??= widget.model;
        setState(
          () => error =
              'Could not verify the model. Download or import it again.',
        );
      }
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && generating) unawaited(stop());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    input.dispose();
    model?.cancel();
    unawaited(ai.close().catchError((_) {}));
    super.dispose();
  }

  Future<void> setup(bool download) async {
    if (busy || model == null) return;
    if (download &&
        !await confirm(
          context,
          'Download the free model?',
          'SmolLM2 is about 386 MB. Use Wi-Fi and allow at least 800 MB free for setup. '
              'There are no API fees; normal mobile-data charges may apply. Keep this screen open.',
        )) {
      return;
    }
    if (!mounted) return;
    setState(() {
      busy = true;
      received = 0;
      error = null;
    });
    try {
      void progress(int bytes) {
        if (mounted && bytes ~/ (1024 * 1024) != received ~/ (1024 * 1024)) {
          setState(() => received = bytes);
        }
      }

      if (download) {
        await model!.download(progress);
      } else {
        final picked = await FilePicker.platform.pickFiles(
          type: FileType.any,
          withData: false,
        );
        if (!mounted) return;
        final path = picked?.files.single.path;
        if (path == null) return;
        await model!.importFile(path, progress);
      }
      if (mounted) setState(() => ready = true);
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Model setup did not finish. Check storage and your connection, then retry. '
              'For import, use smollm2-360m-instruct-q8_0.gguf from the model source below.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> generate() async {
    if (busy || !ready || input.text.trim().isEmpty) return;
    FocusScope.of(context).unfocus();
    final question = input.text.trim();
    setState(() {
      busy = true;
      generating = true;
      stopped = false;
      error = null;
      result = '';
    });
    try {
      final answer = await ai.answer(
        modelPath: model!.file.path,
        mode: mode,
        input: question,
        notes: notes,
        history: history,
      );
      if (!mounted) return;
      setState(() {
        result = answer;
        stopped = ai.stopped;
        if (mode == StudyAiMode.tutor && !stopped) {
          history.add(StudyAiTurn(question, answer));
          if (history.length > 2) history.removeAt(0);
        }
      });
    } on FormatException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => error = ai.stopped
              ? 'Generation stopped. You can try again.'
              : 'The phone could not generate an answer. Close other apps and try a shorter passage. '
                    'If it keeps failing, this phone may not support the local model.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          generating = false;
        });
      }
    }
  }

  Future<void> stop() async {
    try {
      await ai.stop();
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Could not stop immediately. Please wait.');
      }
    }
  }

  Future<void> chooseNote() async {
    await guard(context, () async {
      final entries = (await AppScope.of(context).store.entries(
        kind: 'note',
      )).where((e) => e.body.trim().isNotEmpty).toList();
      if (!mounted) return;
      if (entries.isEmpty) {
        message(
          context,
          'Add a written course note first. PDF text is not extracted automatically.',
        );
        return;
      }
      final picked = await showDialog<Entry>(
        context: context,
        builder: (dialog) => SimpleDialog(
          title: const Text('Choose a written note'),
          children: [
            for (final e in entries)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(dialog, e),
                child: Text(e.title),
              ),
          ],
        ),
      );
      if (picked == null || !mounted) return;
      if (picked.body.length > 6000) {
        message(
          context,
          'This note is long. Copy a section of up to 6,000 characters and paste it instead.',
        );
        return;
      }
      setState(() {
        history.clear();
        result = '';
        error = null;
        selectedCourse = picked.courseId;
        if (mode == StudyAiMode.summary) {
          input.text = picked.body;
        } else {
          notes = picked.body;
          noteName = picked.title;
        }
      });
    });
  }

  Future<void> save() async {
    await guard(context, () async {
      final app = AppScope.of(context);
      final courses = await app.store.courses();
      if (!mounted) return;
      if (courses.isEmpty) {
        message(context, 'Create a course first to save this answer.');
        return;
      }
      final id = await showDialog<String>(
        context: context,
        builder: (dialog) => SimpleDialog(
          title: const Text('Save AI note in…'),
          children: [
            for (final c in courses)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(dialog, c.id),
                child: Text('${c.id == selectedCourse ? '• ' : ''}${c.name}'),
              ),
          ],
        ),
      );
      if (id == null || !mounted) return;
      await app.store.save(
        Entry(
          id: uuid.v4(),
          kind: 'note',
          courseId: id,
          title: mode == StudyAiMode.summary
              ? 'AI study summary'
              : 'AI tutor explanation',
          body:
              '$result\n\nGenerated locally with SmolLM2. Verify against your course materials. '
              '${stopped ? 'Generation was stopped; this answer is incomplete.' : ''}',
        ),
      );
      if (mounted) message(context, 'Saved as an offline course note.');
    });
  }

  Future<void> removeModel() async {
    if (!await confirm(
      context,
      'Remove the AI model?',
      'This frees about 386 MB. Saved notes stay available. Download the model again to use AI.',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => busy = true);
    try {
      await ai.close();
      ai = LocalStudyAi(PhoneAiEngine());
      await model!.remove();
      if (mounted) {
        setState(() {
          ready = false;
          history.clear();
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Could not remove the model. Try again.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('AI study helper')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Learn at your own pace.',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'Free on-device tutor and summarizer. No paid API, account or subscription. '
          'Your questions and notes stay on this phone. A small English-language model can make mistakes; '
          'check its answers against your course materials.',
        ),
        const SizedBox(height: 16),
        if (checking) const LinearProgressIndicator(),
        if (!checking && !ready)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Set up offline AI',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Download SmolLM2 once (about 386 MB), or import the same GGUF file. '
                    'Allow at least 800 MB free for setup. A 64-bit Android phone with 3 GB RAM or more '
                    'is recommended. Speed and compatibility vary by phone.',
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: busy || model == null ? null : () => setup(true),
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Download free model'),
                  ),
                  OutlinedButton(
                    onPressed: busy || model == null
                        ? null
                        : () => setup(false),
                    child: const Text('Import downloaded model'),
                  ),
                ],
              ),
            ),
          ),
        if (ready) ...[
          const Text('✓ Model ready • runs offline'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Tutor'),
                selected: mode == StudyAiMode.tutor,
                onSelected: busy
                    ? null
                    : (_) => setState(() {
                        mode = StudyAiMode.tutor;
                        result = '';
                        history.clear();
                        error = null;
                        input.clear();
                        notes = '';
                        noteName = '';
                      }),
              ),
              ChoiceChip(
                label: const Text('Summarizer'),
                selected: mode == StudyAiMode.summary,
                onSelected: busy
                    ? null
                    : (_) => setState(() {
                        mode = StudyAiMode.summary;
                        result = '';
                        history.clear();
                        error = null;
                        input.clear();
                        notes = '';
                        noteName = '';
                      }),
              ),
            ],
          ),
          TextButton.icon(
            onPressed: busy ? null : chooseNote,
            icon: const Icon(Icons.library_books_outlined),
            label: Text(
              mode == StudyAiMode.summary
                  ? 'Use a saved note'
                  : 'Attach a saved note',
            ),
          ),
          if (notes.isNotEmpty)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Reference: $noteName'),
              trailing: IconButton(
                tooltip: 'Remove reference note',
                onPressed: busy
                    ? null
                    : () => setState(() {
                        notes = '';
                        noteName = '';
                        history.clear();
                      }),
                icon: const Icon(Icons.close),
              ),
            ),
          TextField(
            controller: input,
            enabled: !busy,
            minLines: 3,
            maxLines: 10,
            maxLength: 6000,
            decoration: InputDecoration(
              labelText: mode == StudyAiMode.summary
                  ? 'Paste study text to summarize'
                  : 'Ask your tutor a question',
              hintText: mode == StudyAiMode.summary
                  ? 'Use a short passage. Split long notes into sections.'
                  : 'e.g. Explain supply and demand with an example',
            ),
          ),
          const Text(
            'Written text only. PDF contents are not read automatically.',
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: busy ? null : generate,
            icon: const Icon(Icons.psychology_outlined),
            label: Text(
              mode == StudyAiMode.summary
                  ? 'Summarize on this phone'
                  : 'Ask tutor',
            ),
          ),
          if (history.isNotEmpty)
            TextButton(
              onPressed: busy
                  ? null
                  : () => setState(() {
                      history.clear();
                      result = '';
                      input.clear();
                    }),
              child: const Text('Clear conversation'),
            ),
          if (history.isNotEmpty)
            const Text(
              'The tutor remembers up to two recent exchanges while this screen is open.',
            ),
        ],
        if (busy) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
          Text(
            generating
                ? 'Thinking on this phone… Keep the app open. This may take a while.'
                : 'Setting up model… ${(received / (1024 * 1024)).toStringAsFixed(0)} MB received. Verifying before use.',
          ),
          TextButton(
            onPressed: generating ? stop : model?.cancel,
            child: Text(generating ? 'Stop generation' : 'Cancel setup'),
          ),
        ],
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (result.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    stopped
                        ? 'Incomplete answer (stopped)'
                        : 'AI study response',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  SelectableText(result),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: busy ? null : save,
                        icon: const Icon(Icons.note_add_outlined),
                        label: const Text('Save as course note'),
                      ),
                      TextButton.icon(
                        onPressed: busy
                            ? null
                            : () async {
                                await Clipboard.setData(
                                  ClipboardData(text: result),
                                );
                                if (context.mounted) {
                                  message(context, 'Response copied.');
                                }
                              },
                        icon: const Icon(Icons.copy),
                        label: const Text('Copy'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: busy
              ? null
              : () => guard(context, () async {
                  if (!await launchUrl(
                    Uri.parse(AiModelFile.modelPage),
                    mode: LaunchMode.externalApplication,
                  )) {
                    throw StateError('Could not open the model source.');
                  }
                }),
          child: const Text('Model source & Apache 2.0 license'),
        ),
        if (ready)
          TextButton(
            onPressed: busy ? null : removeModel,
            child: const Text('Remove model to free space'),
          ),
        const Text(
          'The model is not included in backups. Conversations are cleared when this screen closes; '
          'only answers you save become course notes. Model downloads use the internet; AI generation does not.',
        ),
      ],
    ),
  );
}
