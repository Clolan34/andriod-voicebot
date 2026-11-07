import 'package:flutter_test/flutter_test.dart';
import 'package:studyforge/domain/study_rules.dart';

void main() {
  final now = DateTime.utc(2026, 1, 31, 23, 59);
  test(
    'Quiz scoring includes unanswered questions and rejects mismatched inputs',
    () {
      final score = QuizScore.calculate([0, 2, 1], [0, null, 1]);
      expect(score.correct, 2);
      expect(score.percent, 67);
      expect(() => QuizScore.calculate([0], []), throwsArgumentError);
      expect(() => QuizScore.calculate([], []), throwsArgumentError);
    },
  );
  test('Scheduling has documented intervals, lapses and cap', () {
    expect(
      ReviewSchedule.next(now, 20, 7, 'Again').due,
      now.add(const Duration(minutes: 10)),
    );
    expect(ReviewSchedule.next(now, 20, 7, 'Again').intervalDays, 0);
    expect(ReviewSchedule.next(now, 0, 0, 'Hard').intervalDays, 1);
    expect(ReviewSchedule.next(now, 3, 1, 'Good').intervalDays, 6);
    expect(ReviewSchedule.next(now, 0, 0, 'Easy').intervalDays, 4);
    expect(ReviewSchedule.next(now, 300, 7, 'Easy').intervalDays, 365);
    expect(ReviewSchedule.next(now, 3, 1, 'Good').reviews, 2);
    expect(() => ReviewSchedule.next(now, 3, 1, 'bad'), throwsArgumentError);
  });
  test(
    'Topic accuracy needs five answers and uses a strict 60 percent threshold',
    () {
      expect(const TopicPerformance(0, 0).label, 'Not enough data');
      expect(const TopicPerformance(0, 4).label, 'Not enough data');
      expect(const TopicPerformance(2, 5).label, 'Needs revision');
      expect(const TopicPerformance(3, 5).label, 'On track');
    },
  );
  test('Planner week crosses year boundary and uses calendar dates', () {
    expect(mondayOf(DateTime(2027, 1, 1, 23)), DateTime(2026, 12, 28));
    expect(sameDay(DateTime(2026, 1, 1, 0), DateTime(2026, 1, 1, 23)), isTrue);
    expect(sameDay(DateTime(2026, 1, 1, 23), DateTime(2026, 1, 2, 0)), isFalse);
    final instant = DateTime.parse('2026-11-07T23:30:00+02:00');
    expect(instant.toUtc(), DateTime.utc(2026, 11, 7, 21, 30));
  });
  test(
    'Timer counts background time, freezes on pause, resumes and persists',
    () {
      final c = FocusClock(id: 'one', durationSeconds: 1500);
      c.start(now);
      expect(c.remaining(now.add(const Duration(minutes: 5))), 1200);
      c.pause(now.add(const Duration(minutes: 5)));
      expect(c.remaining(now.add(const Duration(hours: 2))), 1200);
      final restored = FocusClock.fromJson(c.toJson());
      expect(restored.deadline, isNull);
      restored.start(now.add(const Duration(hours: 2)));
      final finish = now.add(const Duration(hours: 2, minutes: 20));
      expect(restored.remaining(finish), 0);
      expect(restored.claimCompletion(finish), isTrue);
      expect(restored.claimCompletion(finish), isFalse);
      expect(
        FocusClock.fromJson(restored.toJson()).claimCompletion(finish),
        isFalse,
      );
    },
  );
  test('Timer rounds partial seconds up and never becomes negative', () {
    final c = FocusClock(id: 'x', durationSeconds: 60)..start(now);
    expect(FocusClock.fromJson(c.toJson()).deadline!.isUtc, isTrue);
    expect(c.remaining(now.add(const Duration(milliseconds: 500))), 60);
    expect(c.remaining(now.add(const Duration(days: 1))), 0);
    c.start(now.add(const Duration(seconds: 5)));
    expect(c.deadline, now.add(const Duration(seconds: 60)));
  });
}
