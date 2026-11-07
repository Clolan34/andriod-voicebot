import 'package:flutter/material.dart';
import '../application.dart';
import '../data/models.dart';
import '../data/store.dart';
import 'common.dart';

Future<void> editEntry(
  BuildContext context,
  String kind, {
  Entry? entry,
  String? courseId,
}) async {
  await Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => EntryEditor(kind: kind, entry: entry, courseId: courseId),
    ),
  );
}

class EntryEditor extends StatefulWidget {
  final String kind;
  final Entry? entry;
  final String? courseId;
  const EntryEditor({required this.kind, this.entry, this.courseId, super.key});
  @override
  State<EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends State<EntryEditor> {
  final form = GlobalKey<FormState>();
  late final TextEditingController title;
  late final TextEditingController body;
  late final TextEditingController topic;
  late final TextEditingController duration;
  late final TextEditingController year;
  late final List<TextEditingController> options;
  List<Course>? courses;
  String? course;
  String? file;
  String? guide;
  String priority = 'Normal';
  String semester = '1';
  int correct = 0;
  DateTime date = DateTime.now().add(const Duration(hours: 1));
  bool busy = false;
  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    final d = e?.data ?? {};
    title = TextEditingController(text: e?.title ?? '');
    body = TextEditingController(text: e?.body ?? '');
    topic = TextEditingController(text: e?.topic ?? '');
    duration = TextEditingController(text: '${d['minutes'] ?? 30}');
    year = TextEditingController(text: '${d['year'] ?? DateTime.now().year}');
    options = List.generate(
      4,
      (i) => TextEditingController(
        text: d['options'] == null ? '' : (d['options'] as List)[i] as String,
      ),
    );
    correct = (d['correct'] as int?) ?? 0;
    course = e?.courseId ?? widget.courseId;
    file = d['file'] as String?;
    guide = d['guide'] as String?;
    priority = (d['priority'] as String?) ?? 'Normal';
    semester = (d['semester'] as String?) ?? '1';
    final raw = d['start'] ?? d['due'];
    if (raw is String) date = DateTime.parse(raw).toLocal();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await guard(context, () async {
        final list = await AppScope.of(context).store.courses();
        if (mounted) {
          setState(() {
            courses = list;
            course ??= list.firstOrNull?.id;
          });
        }
      });
    });
  }

  @override
  void dispose() {
    for (final c in [title, body, topic, duration, year, ...options]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> chooseDate() async {
    final chosen = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (chosen == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(date),
    );
    if (time == null || !mounted) return;
    setState(
      () => date = DateTime(
        chosen.year,
        chosen.month,
        chosen.day,
        time.hour,
        time.minute,
      ),
    );
  }

  Future<void> pickPdf(bool marking) async {
    setState(() => busy = true);
    await guard(context, () async {
      final name = await AppScope.of(context).files.importPdf();
      if (name != null && mounted) {
        setState(() {
          if (marking) {
            guide = name;
          } else {
            file = name;
          }
        });
      }
    });
    if (mounted) setState(() => busy = false);
  }

  Future<void> save() async {
    if (!(form.currentState?.validate() ?? false)) return;
    if (course == null) {
      message(context, 'Create a course first.');
      return;
    }
    if (widget.kind == 'paper' && file == null) {
      message(context, 'Import the paper PDF first.');
      return;
    }
    setState(() => busy = true);
    await guard(context, () async {
      final d = <String, dynamic>{...?widget.entry?.data};
      d.remove('file');
      d.remove('guide');
      if (file != null) d['file'] = file;
      if (guide != null) d['guide'] = guide;
      switch (widget.kind) {
        case 'question':
          d.addAll({
            'options': options.map((c) => c.text.trim()).toList(),
            'correct': correct,
          });
        case 'session':
          d.addAll({
            'start': date.toUtc().toIso8601String(),
            'minutes': int.parse(duration.text),
          });
        case 'assignment':
          d.addAll({
            'due': date.toUtc().toIso8601String(),
            'priority': priority,
          });
        case 'card':
          d.putIfAbsent('due', () => DateTime.now().toUtc().toIso8601String());
          d.putIfAbsent('interval', () => 0);
          d.putIfAbsent('reviews', () => 0);
        case 'paper':
          d.addAll({'year': int.parse(year.text), 'semester': semester});
      }
      final app = AppScope.of(context);
      await app.store.save(
        Entry(
          id: widget.entry?.id ?? uuid.v4(),
          kind: widget.kind,
          courseId: course!,
          title: title.text.trim(),
          topic: topic.text.trim(),
          body: body.text.trim(),
          data: d,
        ),
      );
      await app.changed();
      if (mounted) Navigator.pop(context);
    });
    if (mounted) setState(() => busy = false);
  }

  Widget text(
    TextEditingController c,
    String label, {
    int lines = 1,
    bool required = true,
    bool number = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      controller: c,
      minLines: lines,
      maxLines: lines == 1 ? 1 : lines + 5,
      keyboardType: number ? TextInputType.number : TextInputType.multiline,
      decoration: InputDecoration(labelText: label),
      validator: (v) {
        if (required && (v == null || v.trim().isEmpty)) {
          return 'This field is required';
        }
        if (number &&
            (int.tryParse(v ?? '') == null ||
                int.parse(v!) < 1 ||
                int.parse(v) > 10000)) {
          return 'Enter a number from 1 to 10000';
        }
        return null;
      },
    ),
  );
  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.entry == null ? 'New' : 'Edit'} $kind'),
      ),
      body: courses == null
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: form,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (courses!.isEmpty)
                    const EmptyState(
                      'A course comes first',
                      'Return to Courses and add a course before creating study materials.',
                    ),
                  DropdownButtonFormField<String>(
                    initialValue: course,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Course'),
                    items: courses!
                        .map(
                          (c) => DropdownMenuItem(
                            value: c.id,
                            child: Text(
                              c.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: busy ? null : (v) => setState(() => course = v),
                  ),
                  const SizedBox(height: 14),
                  text(topic, 'Topic (optional)', required: false),
                  text(
                    title,
                    kind == 'card' || kind == 'question'
                        ? 'Question / front'
                        : 'Title',
                  ),
                  text(
                    body,
                    switch (kind) {
                      'card' => 'Answer / back',
                      'question' => 'Explanation',
                      'paper' => 'Your answers and self-assessment',
                      _ => 'Notes',
                    },
                    lines: kind == 'note' || kind == 'paper' ? 6 : 3,
                    required:
                        kind == 'card' ||
                        kind == 'question' ||
                        (kind == 'note' && file == null),
                  ),
                  if (kind == 'question') ...[
                    for (var i = 0; i < 4; i++)
                      text(options[i], 'Option ${i + 1}'),
                    DropdownButtonFormField<int>(
                      initialValue: correct,
                      decoration: const InputDecoration(
                        labelText: 'Correct option',
                      ),
                      items: List.generate(
                        4,
                        (i) => DropdownMenuItem(
                          value: i,
                          child: Text('Option ${i + 1}'),
                        ),
                      ),
                      onChanged: (v) => setState(() => correct = v!),
                    ),
                  ],
                  if (kind == 'session' || kind == 'assignment') ...[
                    OutlinedButton.icon(
                      onPressed: busy ? null : chooseDate,
                      icon: const Icon(Icons.event),
                      label: Text(stamp(date.toIso8601String())),
                    ),
                    const SizedBox(height: 12),
                    if (kind == 'session')
                      text(duration, 'Duration in minutes', number: true),
                    if (kind == 'assignment')
                      DropdownButtonFormField<String>(
                        initialValue: priority,
                        decoration: const InputDecoration(
                          labelText: 'Priority',
                        ),
                        items: ['Low', 'Normal', 'High']
                            .map(
                              (s) => DropdownMenuItem(value: s, child: Text(s)),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => priority = v!),
                      ),
                  ],
                  if (kind == 'paper') ...[
                    text(year, 'Year', number: true),
                    DropdownButtonFormField<String>(
                      initialValue: semester,
                      decoration: const InputDecoration(labelText: 'Semester'),
                      items: ['1', '2', 'Summer', 'Other']
                          .map(
                            (s) => DropdownMenuItem(value: s, child: Text(s)),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => semester = v!),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (kind == 'note' || kind == 'paper') ...[
                    OutlinedButton.icon(
                      onPressed: busy ? null : () => pickPdf(false),
                      icon: const Icon(Icons.upload_file),
                      label: Text(
                        file == null
                            ? 'Import PDF (up to 30 MB)'
                            : 'Replace attached PDF',
                      ),
                    ),
                    if (file != null)
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => setState(() => file = null),
                        child: const Text('Remove PDF attachment'),
                      ),
                    if (kind == 'paper')
                      OutlinedButton.icon(
                        onPressed: busy ? null : () => pickPdf(true),
                        icon: const Icon(Icons.fact_check_outlined),
                        label: Text(
                          guide == null
                              ? 'Link a marking guide PDF'
                              : 'Replace marking guide',
                        ),
                      ),
                    if (kind == 'paper' && guide != null)
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => setState(() => guide = null),
                        child: const Text('Remove marking guide'),
                      ),
                    if (kind == 'paper')
                      const Text(
                        'Import only papers you have permission to use. Answers and self-assessments are yours; PDFs are not automatically marked.',
                      ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: busy || courses!.isEmpty ? null : save,
                    icon: const Icon(Icons.check),
                    label: Text(busy ? 'Saving…' : 'Save'),
                  ),
                ],
              ),
            ),
    );
  }
}
