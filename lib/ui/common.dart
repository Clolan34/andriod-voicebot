import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data/models.dart';

const navy = Color(0xff11243a);
const teal = Color(0xff007e78);
const amber = Color(0xffab6b05);
String stamp(String? date) => date == null
    ? 'Not set'
    : DateFormat('EEE, d MMM • HH:mm').format(DateTime.parse(date).toLocal());
String dateLabel(DateTime date) => DateFormat('EEE, d MMM').format(date);

ThemeData appTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: teal,
    brightness: brightness,
    primary: brightness == Brightness.light ? teal : const Color(0xff67d7cb),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: brightness == Brightness.light
        ? const Color(0xfff3f6f8)
        : null,
    appBarTheme: AppBarTheme(
      backgroundColor: brightness == Brightness.light
          ? const Color(0xfff3f6f8)
          : scheme.surface,
      foregroundColor: brightness == Brightness.light ? navy : scheme.onSurface,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    textTheme: ThemeData(
      brightness: brightness,
    ).textTheme.apply(fontFamily: 'Roboto'),
  );
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  final String? action;
  final VoidCallback? onAction;
  const EmptyState(
    this.title,
    this.detail, {
    this.icon = Icons.auto_stories_outlined,
    this.action,
    this.onAction,
    super.key,
  });
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(icon, size: 36, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(detail, textAlign: TextAlign.center),
          if (onAction != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: FilledButton(onPressed: onAction, child: Text(action!)),
            ),
        ],
      ),
    ),
  );
}

class Section extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const Section(this.title, {this.trailing, super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    ),
  );
}

Future<bool> confirm(
  BuildContext context,
  String title,
  String detail, {
  String action = 'Delete',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        scrollable: true,
        title: Text(title),
        content: Text(detail),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

void message(BuildContext context, String text) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

Future<void> guard(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
  } catch (error) {
    message(
      context,
      'Could not finish this action. ${error.toString().replaceFirst('Exception: ', '')}',
    );
  }
}

String courseName(List<Course> courses, String id) {
  for (final c in courses) {
    if (c.id == id) return c.name;
  }
  return 'Deleted course';
}

class EntryTile extends StatelessWidget {
  final Entry entry;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;
  const EntryTile(
    this.entry, {
    required this.subtitle,
    required this.onTap,
    this.trailing,
    super.key,
  });
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        child: Icon(switch (entry.kind) {
          'note' =>
            entry.data['file'] != null
                ? Icons.picture_as_pdf_outlined
                : Icons.notes_outlined,
          'card' => Icons.style_outlined,
          'question' => Icons.quiz_outlined,
          'session' => Icons.event_outlined,
          'assignment' => Icons.task_alt,
          _ => Icons.description_outlined,
        }),
      ),
      title: Text(entry.title),
      subtitle: Text(subtitle),
      trailing: trailing,
      onTap: onTap,
    ),
  );
}
