import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../application.dart';
import 'common.dart';
import 'ai.dart';
import '../data/ai_model.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final name = TextEditingController();
  bool loaded = false;
  bool busy = false;
  bool reminders = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (loaded) return;
    loaded = true;
    name.text = AppScope.of(context).name;
    AppScope.of(context).store.setting('reminders').then((v) {
      if (mounted) setState(() => reminders = v == 'yes');
    });
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    await guard(context, action);
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (busy) const LinearProgressIndicator(),
          const Section('Make it yours'),
          TextField(
            controller: name,
            maxLength: 60,
            decoration: const InputDecoration(
              labelText: 'Your name (optional)',
            ),
          ),
          FilledButton(
            onPressed: busy
                ? null
                : () => run(() async {
                    await app.store.set('name', name.text.trim());
                    await app.refreshPreferences();
                    message(context, 'Profile saved on this device.');
                  }),
            child: const Text('Save name'),
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<ThemeMode>(
            isExpanded: true,
            initialValue: app.theme,
            decoration: const InputDecoration(labelText: 'Appearance'),
            items: const [
              DropdownMenuItem(
                value: ThemeMode.system,
                child: Text('Use device theme'),
              ),
              DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
              DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
            ],
            onChanged: busy
                ? null
                : (value) => run(() async {
                    await app.store.set('theme', value!.name);
                    await app.refreshPreferences();
                  }),
          ),
          const Section('AI study tools'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.psychology_outlined),
            title: const Text('Free offline AI'),
            subtitle: const Text('Tutor, summarizer and model storage'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const StudyAiPage()),
            ),
          ),
          const Section('Reminders'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Session & deadline reminders'),
            subtitle: const Text(
              'An approximate reminder 10 minutes before. Android may delay delivery to save battery.',
            ),
            value: reminders,
            onChanged: busy
                ? null
                : (value) => run(() async {
                    if (value) {
                      final granted = await app.reminders.enable();
                      if (!granted) {
                        await app.store.set('reminders', 'no');
                        setState(() => reminders = false);
                        message(
                          context,
                          'Notifications are unavailable or denied. Planning still works. To enable them, open Android Settings → Apps → StudyForge → Notifications.',
                        );
                        return;
                      }
                    }
                    await app.store.set('reminders', value ? 'yes' : 'no');
                    setState(() => reminders = value);
                    await app.reminders.rebuild(app.store);
                  }),
          ),
          const Text(
            'Dates are saved as instants and displayed in your device’s current time zone. Reminders are rebuilt when you edit plans or reopen the app, including after a time-zone change. No exact-alarm permission is requested.',
          ),
          const Section('Backup & restore'),
          const Text(
            'Backups contain your records and imported PDFs. Store them somewhere safe. Uninstalling StudyForge removes local data unless you exported a backup.',
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: busy
                ? null
                : () => run(() async {
                    final bytes = await app.backups.export();
                    await app.files.exportBytes(
                      bytes,
                      'StudyForge-${DateTime.now().millisecondsSinceEpoch}.zip',
                    );
                  }),
            icon: const Icon(Icons.ios_share),
            label: const Text('Export backup ZIP'),
          ),
          OutlinedButton.icon(
            onPressed: busy
                ? null
                : () => run(() async {
                    final picked = await FilePicker.platform.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: ['zip'],
                      withData: false,
                    );
                    if (picked == null) return;
                    if (picked.files.single.size > 50 * 1024 * 1024) {
                      throw const FormatException(
                        'Choose a backup smaller than 50 MB.',
                      );
                    }
                    if (!await confirm(
                      context,
                      'Replace all current data?',
                      'Restore REPLACES your courses, notes, files, plans and progress with this backup. It does not merge. Export your current data first if needed. A failed validation leaves current data intact.',
                      action: 'Replace & restore',
                    )) {
                      return;
                    }
                    final selected = picked.files.single;
                    final bytes =
                        selected.bytes ??
                        await File(selected.path!).readAsBytes();
                    await app.backups.restore(bytes);
                    await app.refreshPreferences();
                    await app.changed();
                    name.text = app.name;
                    reminders = await app.store.setting('reminders') == 'yes';
                    message(
                      context,
                      'Backup restored. Running timers were reset.',
                    );
                  }),
            icon: const Icon(Icons.restore),
            label: const Text('Restore backup (replace)'),
          ),
          const Section('Demonstration content'),
          const Text(
            'Original questions and cards for programming, maths and study skills. Not official university material. Loading samples adds no personal scores or completed sessions.',
          ),
          OutlinedButton(
            onPressed: busy
                ? null
                : () => run(() async {
                    await app.store.loadSamples();
                    message(
                      context,
                      'Demo courses are available in Courses and Practice. Samples are loaded only once.',
                    );
                  }),
            child: const Text('Load demo courses, questions & cards'),
          ),
          const Section('Privacy & connectivity'),
          const Text(
            'No StudyForge sign-in, subscriptions, advertising or analytics. Your study records stay on this device. Online topic search contacts Wikipedia; learning-resource links open in your browser. Saved reference notes can be read offline. AI runs on this phone after a one-time model download from Hugging Face. No paid API. PDFs and AI questions are never uploaded.',
          ),
          const Section('Data controls'),
          OutlinedButton.icon(
            onPressed: busy
                ? null
                : () => run(() async {
                    if (!await confirm(
                      context,
                      'Delete all StudyForge data?',
                      'This permanently removes every local course, record, PDF, setting and result. Exported backups outside the app are not deleted.',
                      action: 'Delete everything',
                    )) {
                      return;
                    }
                    await app.store.clear();
                    await (await AiModelFile.open()).remove();
                    await app.reminders.plugin.cancelAll();
                    await app.changed();
                    await app.refreshPreferences();
                    if (context.mounted) Navigator.pop(context);
                  }),
            icon: const Icon(Icons.delete_forever_outlined),
            label: const Text('Delete all data'),
          ),
          TextButton(
            onPressed: () => showLicensePage(context: context),
            child: const Text('Open-source licenses'),
          ),
          const SizedBox(height: 24),
          const Text(
            'StudyForge 1.1 • Testing build\nMade for focused, affordable study.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
