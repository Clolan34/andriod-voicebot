import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../application.dart';
import '../data/store.dart';
import '../domain/study_rules.dart';
import 'common.dart';

class FocusPage extends StatefulWidget {
  const FocusPage({super.key});
  @override
  State<FocusPage> createState() => _FocusPageState();
}

class _FocusPageState extends State<FocusPage> with WidgetsBindingObserver {
  FocusClock? clock;
  Timer? ticker;
  int study = 25;
  int rest = 5;
  bool isBreak = false;
  bool sound = false;
  bool vibration = false;
  bool writing = false;
  String? error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  @override
  void dispose() {
    ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> load() async {
    try {
      final s = AppScope.of(context).store;
      study = int.tryParse(await s.setting('studyMinutes', '25')) ?? 25;
      rest = int.tryParse(await s.setting('breakMinutes', '5')) ?? 5;
      sound = await s.setting('sound') == 'yes';
      vibration = await s.setting('vibration') == 'yes';
      final raw = await s.setting('focusClock');
      if (raw.isNotEmpty) {
        final saved = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        clock = FocusClock.fromJson(saved);
        isBreak = saved['isBreak'] == true;
      }
      clock ??= FocusClock(id: uuid.v4(), durationSeconds: study * 60);
      if (!mounted) return;
      setState(() {});
      ticker = Timer.periodic(const Duration(seconds: 1), (_) => tick());
      await tick();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) tick();
  }

  Future<void> persist() async {
    final s = AppScope.of(context).store;
    await s.set(
      'focusClock',
      jsonEncode({...clock!.toJson(), 'isBreak': isBreak}),
    );
  }

  Future<void> tick() async {
    if (!mounted || clock == null || writing) return;
    final c = clock!;
    if (!c.recorded && c.remaining(DateTime.now()) == 0) {
      writing = true;
      try {
        if (isBreak) {
          c.recorded = true;
          await persist();
        } else {
          await AppScope.of(context).store.recordFocus(c, DateTime.now());
        }
        if (sound) await SystemSound.play(SystemSoundType.alert);
        if (vibration) await HapticFeedback.mediumImpact();
      } catch (_) {
        if (mounted) {
          message(context, 'Could not save timer completion. It will retry.');
        }
      } finally {
        writing = false;
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> reset(bool nextBreak) async {
    if (clock != null &&
        !clock!.recorded &&
        clock!.remaining(DateTime.now()) < clock!.durationSeconds) {
      if (!await confirm(
        context,
        'Reset timer?',
        'This unfinished session will not count as completed study time.',
        action: 'Reset',
      )) {
        return;
      }
    }
    isBreak = nextBreak;
    clock = FocusClock(
      id: uuid.v4(),
      durationSeconds: (isBreak ? rest : study) * 60,
    );
    await persist();
    if (mounted) setState(() {});
  }

  Future<void> configure() async {
    final a = TextEditingController(text: '$study');
    final b = TextEditingController(text: '$rest');
    final valid = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Timer lengths'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: a,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Study minutes (1–180)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: b,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Break minutes (1–60)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final x = int.tryParse(a.text);
              final y = int.tryParse(b.text);
              if (x != null &&
                  y != null &&
                  x >= 1 &&
                  x <= 180 &&
                  y >= 1 &&
                  y <= 60) {
                Navigator.pop(c, true);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (valid != true) return;
    study = int.parse(a.text);
    rest = int.parse(b.text);
    final s = AppScope.of(context).store;
    await s.set('studyMinutes', '$study');
    await s.set('breakMinutes', '$rest');
    if (mounted) setState(() {});
    message(
      context,
      'New lengths apply when you reset or start the next session.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = clock;
    final left = c?.remaining(DateTime.now()) ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Focus timer')),
      body: error != null
          ? EmptyState('Could not restore timer', error!)
          : c == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  isBreak
                      ? 'Take a breather.'
                      : 'One thing. Your full attention.',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 36,
                      horizontal: 16,
                    ),
                    child: Column(
                      children: [
                        Text(
                          isBreak ? 'BREAK' : 'STUDY',
                          style: const TextStyle(
                            color: teal,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '${left ~/ 60}:${(left % 60).toString().padLeft(2, '0')}',
                            style: Theme.of(context).textTheme.displayLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          c.recorded
                              ? isBreak
                                    ? 'Break complete'
                                    : 'Complete • study time saved'
                              : c.deadline == null
                              ? 'Ready when you are'
                              : 'Stay with it. You’re doing the work.',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: c.recorded || writing
                      ? null
                      : () => guard(context, () async {
                          if (c.deadline == null) {
                            c.start(DateTime.now());
                          } else {
                            c.pause(DateTime.now());
                          }
                          await persist();
                          if (mounted) setState(() {});
                        }),
                  icon: Icon(
                    c.deadline == null ? Icons.play_arrow : Icons.pause,
                  ),
                  label: Text(c.deadline == null ? 'Start / resume' : 'Pause'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: writing
                      ? null
                      : () => guard(context, () => reset(isBreak)),
                  child: const Text('Reset'),
                ),
                TextButton(
                  onPressed: writing
                      ? null
                      : () => guard(context, () => reset(!isBreak)),
                  child: Text(isBreak ? 'Switch to study' : 'Switch to break'),
                ),
                TextButton.icon(
                  onPressed: () => guard(context, configure),
                  icon: const Icon(Icons.tune),
                  label: Text('Configure • $study min study / $rest min break'),
                ),
                SwitchListTile(
                  title: const Text('Completion sound'),
                  value: sound,
                  onChanged: (v) => guard(context, () async {
                    await AppScope.of(
                      context,
                    ).store.set('sound', v ? 'yes' : 'no');
                    setState(() => sound = v);
                  }),
                ),
                SwitchListTile(
                  title: const Text('Completion haptic feedback'),
                  value: vibration,
                  onChanged: (v) => guard(context, () async {
                    await AppScope.of(
                      context,
                    ).store.set('vibration', v ? 'yes' : 'no');
                    setState(() => vibration = v);
                  }),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Time uses a saved deadline, so backgrounding the app does not pause it. Completed study time is recorded once when StudyForge next checks the timer. Breaks are not counted. Sound and haptics are delivered while the app is active.',
                ),
              ],
            ),
    );
  }
}
