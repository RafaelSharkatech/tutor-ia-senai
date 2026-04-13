import 'models/chat_models.dart';

/// Abstraction over the storage used to persist chat sessions/messages.
///
/// Stage 2 will provide a Firestore implementation, but this interface allows
/// alternative backends (local cache, mock repos for tests) if needed later.
abstract class ChatRepository {
  /// Loads the current list of chats for the authenticated user.
  Future<List<ChatSession>> fetchChats({required String userId});

  /// Realtime stream used by the drawer to stay in sync with remote changes.
  Stream<List<ChatSession>> watchChats({required String userId});

  /// Creates a new chat session and returns the hydrated model.
  Future<ChatSession> createChat({
    required String userId,
    ChatDraft? draft,
  });

  /// Deletes a chat and all respective messages.
  Future<void> deleteChat({required String userId, required String chatId});

  /// Archives or restores a chat without deleting its history.
  Future<void> archiveChat({
    required String userId,
    required String chatId,
    required bool archived,
  });

  /// Saves/updates the friendly chat title (auto-generated or custom).
  Future<void> renameChat({
    required String userId,
    required String chatId,
    required String title,
  });

  /// Adds a message to the selected chat and updates derived metadata.
  Future<ChatMessage> appendMessage({
    required String userId,
    required String chatId,
    required ChatMessage message,
  });

  /// Real-time stream for the conversation body.
  Stream<List<ChatMessage>> watchMessages({
    required String userId,
    required String chatId,
    int? limit,
  });

  /// Fetches a context window (latest N messages) to send to the worker/LLM.
  Future<List<ChatMessage>> loadContext({
    required String userId,
    required String chatId,
    int limit,
  });
}
