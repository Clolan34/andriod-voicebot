import 'dart:convert';

class Course {
  final String id;
  final String name;
  final String code;
  final int color;
  final String topics;
  const Course({
    required this.id,
    required this.name,
    this.code = '',
    this.color = 0xff00897b,
    this.topics = '',
  });
  Map<String, Object?> toRow() => {
    'id': id,
    'name': name,
    'code': code,
    'color': color,
    'topics': topics,
  };
  factory Course.fromRow(Map<String, Object?> r) => Course(
    id: r['id'] as String,
    name: r['name'] as String,
    code: r['code'] as String,
    color: r['color'] as int,
    topics: r['topics'] as String,
  );
}

/// Shared envelope keeps searching and course relationships consistent. Feature
/// metadata is deliberately small and stored in [data] as versioned JSON.
class Entry {
  final String id;
  final String kind;
  final String courseId;
  final String topic;
  final String title;
  final String body;
  final Map<String, dynamic> data;
  const Entry({
    required this.id,
    required this.kind,
    required this.courseId,
    this.topic = '',
    required this.title,
    this.body = '',
    this.data = const {},
  });
  Map<String, Object?> toRow() => {
    'id': id,
    'kind': kind,
    'course_id': courseId,
    'topic': topic,
    'title': title,
    'body': body,
    'data': jsonEncode(data),
  };
  factory Entry.fromRow(Map<String, Object?> r) => Entry(
    id: r['id'] as String,
    kind: r['kind'] as String,
    courseId: r['course_id'] as String,
    topic: r['topic'] as String,
    title: r['title'] as String,
    body: r['body'] as String,
    data: Map<String, dynamic>.from(jsonDecode(r['data'] as String) as Map),
  );
  Entry withData(Map<String, dynamic> changes) => Entry(
    id: id,
    kind: kind,
    courseId: courseId,
    topic: topic,
    title: title,
    body: body,
    data: {...data, ...changes},
  );
}
