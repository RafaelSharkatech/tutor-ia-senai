import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../session/app_session_controller.dart';
import 'chat_repository.dart';
import 'models/chat_models.dart';

class FirestoreChatRepository implements ChatRepository {
  FirestoreChatRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  static const int _deleteBatchSize = 100;

  CollectionReference<Map<String, dynamic>> _userChats(String userId) =>
      _firestore.collection('users').doc(userId).collection('chats');

  DocumentReference<Map<String, dynamic>> _chatDoc(
    String userId,
    String chatId,
  ) => _userChats(userId).doc(chatId);

  CollectionReference<Map<String, dynamic>> _chatMessages(
    String userId,
    String chatId,
  ) => _chatDoc(userId, chatId).collection('messages');

  @override
  Future<List<ChatSession>> fetchChats({required String userId}) async {
    final snapshot = await _userChats(
      userId,
    ).orderBy('updatedAt', descending: true).get();
    return snapshot.docs.map(_sessionFromDoc).toList();
  }

  @override
  Stream<List<ChatSession>> watchChats({required String userId}) {
    return _userChats(userId)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(_sessionFromDoc).toList());
  }

  @override
  Future<ChatSession> createChat({
    required String userId,
    ChatDraft? draft,
  }) async {
    final now = DateTime.now();
    final docRef = _userChats(userId).doc();
    final session = ChatSession(
      id: docRef.id,
      title: draft?.title?.trim().isNotEmpty == true
          ? draft!.title!.trim()
          : _defaultTitle(now),
      createdAt: now,
      updatedAt: now,
      messageCount: 0,
      archived: false,
    );
    await docRef.set(_encodeSession(session));
    if (draft?.initialMessage != null) {
      await appendMessage(
        userId: userId,
        chatId: session.id,
        message: draft!.initialMessage!,
      );
    }
    return session;
  }

  @override
  Future<void> deleteChat({
    required String userId,
    required String chatId,
  }) async {
    final chatRef = _chatDoc(userId, chatId);
    // Delete messages in batches to avoid timeouts
    while (true) {
      final batch = _firestore.batch();
      final chunk = await chatRef
          .collection('messages')
          .limit(_deleteBatchSize)
          .get();
      if (chunk.docs.isEmpty) {
        break;
      }
      for (final doc in chunk.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
    await chatRef.delete();
  }

  @override
  Future<void> archiveChat({
    required String userId,
    required String chatId,
    required bool archived,
  }) {
    return _chatDoc(userId, chatId).update({
      'archived': archived,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> renameChat({
    required String userId,
    required String chatId,
    required String title,
  }) {
    return _chatDoc(userId, chatId).update({
      'title': title.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<ChatMessage> appendMessage({
    required String userId,
    required String chatId,
    required ChatMessage message,
  }) async {
    final messages = _chatMessages(userId, chatId);
    final docRef = message.id.isEmpty
        ? messages.doc()
        : messages.doc(message.id);
    final storedMessage = message.id.isEmpty
        ? message.copyWith(id: docRef.id)
        : message;
    final data = _encodeMessage(storedMessage);

    await _firestore.runTransaction((txn) async {
      txn.set(docRef, data);
      txn.update(_chatDoc(userId, chatId), {
        'updatedAt': FieldValue.serverTimestamp(),
        'lastMessageSnippet': storedMessage.text.substring(
          0,
          storedMessage.text.length.clamp(0, 120),
        ),
        'messageCount': FieldValue.increment(1),
      });
    });
    return storedMessage;
  }

  @override
  Stream<List<ChatMessage>> watchMessages({
    required String userId,
    required String chatId,
    int? limit,
  }) {
    Query<Map<String, dynamic>> query = _chatMessages(
      userId,
      chatId,
    ).orderBy('createdAt');
    if (limit != null) {
      query = query.limit(limit);
    }
    return query.snapshots().map(
      (snapshot) => snapshot.docs.map(_messageFromDoc).toList(),
    );
  }

  @override
  Future<List<ChatMessage>> loadContext({
    required String userId,
    required String chatId,
    int limit = 20,
  }) async {
    final query = await _chatMessages(
      userId,
      chatId,
    ).orderBy('createdAt', descending: true).limit(limit).get();
    final messages = query.docs.map(_messageFromDoc).toList();
    return messages.reversed.toList(growable: false);
  }

  ChatSession _sessionFromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return ChatSession.fromMap(id: doc.id, data: data);
  }

  ChatMessage _messageFromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return ChatMessage.fromMap(id: doc.id, data: data);
  }

  Map<String, dynamic> _encodeSession(ChatSession session) {
    return {
      'title': session.title,
      'createdAt': Timestamp.fromDate(session.createdAt),
      'updatedAt': Timestamp.fromDate(session.updatedAt),
      'messageCount': session.messageCount,
      'archived': session.archived,
      if (session.lastMessageSnippet != null)
        'lastMessageSnippet': session.lastMessageSnippet,
    };
  }

  Map<String, dynamic> _encodeMessage(ChatMessage message) {
    return {
      'role': message.role.name,
      'text': message.text,
      'createdAt': Timestamp.fromDate(message.createdAt),
      if (message.metadata != null) 'metadata': message.metadata,
    };
  }

  String _defaultTitle(DateTime now) {
    String two(int value) => value.toString().padLeft(2, '0');
    return 'Chat ${two(now.day)}/${two(now.month)} ${two(now.hour)}:${two(now.minute)}';
  }
}

ChatRepository createDefaultChatRepository(AppSessionController session) {
  return FirestoreChatRepository();
}
