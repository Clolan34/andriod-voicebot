import 'package:flutter/material.dart';
import 'application.dart';
import 'data/files.dart';
import 'data/reminders.dart';
import 'data/store.dart';
import 'ui/common.dart';
import 'ui/home.dart';
import 'ui/courses.dart';
import 'ui/planner.dart';
import 'ui/practice.dart';
import 'ui/progress.dart';
import 'ui/settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final store = await StudyStore.open();
    final files = await DocumentFiles.open();
    final reminders = ReminderService();
    await reminders.init();
    final app = StudyAppState(store, files, reminders);
    await app.refreshPreferences();
    await app.changed();
    runApp(StudyForge(app: app));
  } catch (error) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'StudyForge could not open its local storage. '
                'Please check available space and restart the app. Your data has not been reset.\n$error',
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class StudyForge extends StatelessWidget {
  final StudyAppState app;
  const StudyForge({required this.app, super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: app,
    builder: (context, _) => AppScope(
      app: app,
      child: MaterialApp(
        title: 'StudyForge',
        debugShowCheckedModeBanner: false,
        theme: appTheme(Brightness.light),
        darkTheme: appTheme(Brightness.dark),
        themeMode: app.theme,
        home: app.onboarded ? const Shell() : const Welcome(),
      ),
    ),
  );
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  int index = 0;
  String practiceKind = 'question';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      AppScope.of(context).reconcileTimer().catchError((_) {});
      AppScope.of(
        context,
      ).reminders.rebuild(AppScope.of(context).store).catchError((_) {});
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    const names = ['Home', 'Courses', 'Planner', 'Practice', 'Progress'];
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.local_fire_department_rounded, color: teal),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                index == 0 ? 'StudyForge' : names[index],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
            ),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: switch (index) {
          0 => HomePage(
            onNavigate: (i) => setState(() {
              practiceKind = 'question';
              index = i;
            }),
            onReviewCards: () => setState(() {
              practiceKind = 'card';
              index = 3;
            }),
          ),
          1 => const CoursesPage(),
          2 => const PlannerPage(),
          3 => PracticePage(initialKind: practiceKind),
          _ => const ProgressPage(),
        },
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (i) => setState(() => index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_stories_outlined),
            label: 'Courses',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            label: 'Planner',
          ),
          NavigationDestination(
            icon: Icon(Icons.psychology_outlined),
            label: 'Practice',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            label: 'Progress',
          ),
        ],
      ),
    );
  }
}

class Welcome extends StatefulWidget {
  const Welcome({super.key});
  @override
  State<Welcome> createState() => _WelcomeState();
}

class _WelcomeState extends State<Welcome> {
  final name = TextEditingController();
  bool busy = false;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> finish(bool samples) async {
    setState(() => busy = true);
    await guard(context, () async {
      final app = AppScope.of(context);
      if (samples) await app.store.loadSamples();
      await app.store.set('name', name.text.trim());
      await app.store.set('onboarded', 'yes');
      await app.refreshPreferences();
    });
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.local_fire_department_rounded,
                  color: teal,
                  size: 64,
                ),
                const SizedBox(height: 24),
                Text(
                  'Build your next breakthrough.',
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Your courses, revision and focus time. One calm place to make progress, even without data.',
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: name,
                  maxLength: 60,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'What should we call you? (optional)',
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: busy ? null : () => finish(false),
                  child: const Text('Start with my own courses'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: busy ? null : () => finish(true),
                  child: const Text('Explore demonstration content'),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Samples are original demonstration material, not official university questions.',
                    textAlign: TextAlign.center,
                  ),
                ),
                TextButton(
                  onPressed: busy ? null : () => finish(false),
                  child: const Text('Skip introduction'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
