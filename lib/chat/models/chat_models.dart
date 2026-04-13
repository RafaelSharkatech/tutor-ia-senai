import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;

/// Chat data models used to persist sessions and messages regardless of
/// the underlying storage (Firestore, local cache, etc.).
class ChatMessage {
  final String id;
  final ChatRole role;
  final String text;
  final DateTime createdAt;
  final Map<String, dynamic>? metadata;

  const ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.createdAt,
    this.metadata,
  });

  ChatMessage copyWith({
    String? id,
    ChatRole? role,
    String? text,
    DateTime? createdAt,
    Map<String, dynamic>? metadata,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      text: text ?? this.text,
      createdAt: createdAt ?? this.createdAt,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'role': role.name,
      'text': text,
      'createdAt': createdAt.toIso8601String(),
      if (metadata != null) 'metadata': metadata,
    };
  }

  factory ChatMessage.fromMap({
    required String id,
    required Map<String, dynamic> data,
  }) {
    final timestamp = data['createdAt'];
    return ChatMessage(
      id: id,
      role: ChatRoleX.fromName(data['role'] as String?),
      text: (data['text'] as String?) ?? '',
      createdAt: _decodeDateTime(timestamp),
      metadata: (data['metadata'] is Map<String, dynamic>)
          ? data['metadata'] as Map<String, dynamic>
          : (data['metadata'] is Map)
          ? (data['metadata'] as Map).cast<String, dynamic>()
          : null,
    );
  }
}

class ChatSession {
  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? lastMessageSnippet;
  final int messageCount;
  final bool archived;

  const ChatSession({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.lastMessageSnippet,
    this.messageCount = 0,
    this.archived = false,
  });

  ChatSession copyWith({
    String? id,
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? lastMessageSnippet,
    int? messageCount,
    bool? archived,
  }) {
    return ChatSession(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastMessageSnippet: lastMessageSnippet ?? this.lastMessageSnippet,
      messageCount: messageCount ?? this.messageCount,
      archived: archived ?? this.archived,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'messageCount': messageCount,
      'archived': archived,
      if (lastMessageSnippet != null) 'lastMessageSnippet': lastMessageSnippet,
    };
  }

  factory ChatSession.fromMap({
    required String id,
    required Map<String, dynamic> data,
  }) {
    return ChatSession(
      id: id,
      title: (data['title'] as String?) ?? 'Chat sem titulo',
      createdAt: _decodeDateTime(data['createdAt']),
      updatedAt: _decodeDateTime(data['updatedAt']),
      lastMessageSnippet: data['lastMessageSnippet'] as String?,
      messageCount: (data['messageCount'] as num?)?.toInt() ?? 0,
      archived: data['archived'] as bool? ?? false,
    );
  }
}

DateTime _decodeDateTime(dynamic value) {
  if (value is DateTime) {
    return value;
  }
  if (value is Timestamp) {
    return value.toDate();
  }
  if (value is num) {
    // Support epoch milliseconds
    return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  }
  if (value is String) {
    return DateTime.tryParse(value) ?? DateTime.now();
  }
  return DateTime.now();
}

/// Convenient extension for parsing enum values coming from persistence.
extension ChatRoleX on ChatRole {
  static ChatRole fromName(String? value) {
    switch (value) {
      case 'assistant':
        return ChatRole.assistant;
      case 'system':
        return ChatRole.system;
      case 'user':
      default:
        return ChatRole.user;
    }
  }
}

enum ChatRole { system, user, assistant }

/// Basic DTO used when creating a chat before the first message arrives.
class ChatDraft {
  final String? title;
  final ChatMessage? initialMessage;

  const ChatDraft({this.title, this.initialMessage});
}
