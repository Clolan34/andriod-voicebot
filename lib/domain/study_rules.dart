/// Pure application rules, independent of widgets and storage.
class ReviewSchedule {
  final DateTime due;
  final int intervalDays;
  final int reviews;
  const ReviewSchedule(this.due, this.intervalDays, this.reviews);

  /// Again: 10 minutes; Hard: >=1 day, 1.2x; Good: >=1 day, 2x;
  /// Easy: >=4 days, 3x. Intervals are capped at 365 days.
  static ReviewSchedule next(DateTime now, int days, int count, String grade) {
    if (!['Again', 'Hard', 'Good', 'Easy'].contains(grade)) {
      throw ArgumentError.value(grade, 'grade');
    }
    if (grade == 'Again') {
      return ReviewSchedule(now.add(const Duration(minutes: 10)), 0, count + 1);
    }
    final factor = {'Hard': 1.2, 'Good': 2.0, 'Easy': 3.0}[grade]!;
    final minimum = grade == 'Easy' ? 4 : 1;
    final interval = (days * factor).round().clamp(minimum, 365);
    return ReviewSchedule(
      now.add(Duration(days: interval)),
      interval,
      count + 1,
    );
  }
}

class TopicPerformance {
  final int correct;
  final int total;
  const TopicPerformance(this.correct, this.total);
  double get accuracy => total == 0 ? 0 : correct / total;
  String get label => total < 5
      ? 'Not enough data'
      : accuracy < .6
      ? 'Needs revision'
      : 'On track';
}

class QuizScore {
  final int correct;
  final int total;
  const QuizScore(this.correct, this.total);
  int get percent => total == 0 ? 0 : (100 * correct / total).round();
  static QuizScore calculate(List<int> expected, List<int?> given) {
    if (expected.length != given.length || expected.isEmpty) {
      throw ArgumentError('A quiz needs matching, nonempty answer lists.');
    }
    var score = 0;
    for (var i = 0; i < expected.length; i++) {
      if (expected[i] == given[i]) score++;
    }
    return QuizScore(score, expected.length);
  }
}

/// Absolute deadlines count background time; paused remaining time is frozen.
class FocusClock {
  final String id;
  final int durationSeconds;
  int remainingSeconds;
  DateTime? deadline;
  bool recorded;
  FocusClock({
    required this.id,
    required this.durationSeconds,
    int? remainingSeconds,
    this.deadline,
    this.recorded = false,
  }) : remainingSeconds = remainingSeconds ?? durationSeconds;
  int remaining(DateTime now) => deadline == null
      ? remainingSeconds
      : ((deadline!.difference(now).inMilliseconds / 1000).ceil()).clamp(
          0,
          durationSeconds,
        );
  void start(DateTime now) {
    if (deadline == null && remainingSeconds > 0) {
      deadline = now.add(Duration(seconds: remainingSeconds));
    }
  }

  void pause(DateTime now) {
    remainingSeconds = remaining(now);
    deadline = null;
  }

  bool claimCompletion(DateTime now) {
    if (recorded || remaining(now) > 0) return false;
    recorded = true;
    return true;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'duration': durationSeconds,
    'remaining': remainingSeconds,
    'deadline': deadline?.toUtc().toIso8601String(),
    'recorded': recorded,
  };
  factory FocusClock.fromJson(Map<String, dynamic> j) => FocusClock(
    id: j['id'] as String,
    durationSeconds: j['duration'] as int,
    remainingSeconds: j['remaining'] as int,
    deadline: j['deadline'] == null
        ? null
        : DateTime.parse(j['deadline'] as String),
    recorded: j['recorded'] as bool,
  );
}

DateTime mondayOf(DateTime day) {
  final local = DateTime(day.year, day.month, day.day);
  return DateTime(local.year, local.month, local.day - local.weekday + 1);
}

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

DateTime calendarOffset(DateTime day, int days) =>
    DateTime(day.year, day.month, day.day + days);
