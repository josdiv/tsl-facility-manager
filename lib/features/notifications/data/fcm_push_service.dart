import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../../core/firebase/firebase_env.dart';
import '../../profile/domain/user_profile.dart';
import '../domain/notifications.dart';

/// Firebase Cloud Messaging, set up the way SpotLat does it. Pushes are sent
/// by Cloud Functions through the company push API; this side registers the
/// device and shows what arrives.
class FcmPushService implements PushService {
  FcmPushService({FirebaseMessaging? messaging, FirebaseFirestore? firestore})
    : _messaging = messaging ?? FirebaseMessaging.instance,
      _db = firestore ?? appFirestore();

  final FirebaseMessaging _messaging;
  final FirebaseFirestore _db;
  final _local = FlutterLocalNotificationsPlugin();
  final _taps = StreamController<void>.broadcast();

  StreamSubscription<String>? _tokenRefresh;
  String? _uid;
  String? _token;
  var _initialized = false;

  static const _channel = AndroidNotificationChannel(
    'tsl.default',
    'TSL alerts',
    description: 'Work order updates and messages',
    importance: Importance.high,
  );

  @override
  Stream<void> get onTapped => _taps.stream;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // Pushes that arrive while the app is open aren't shown by the system,
    // so the local notifications plugin shows them.
    await _local.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (_) => _taps.add(null),
    );
    await _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_channel);
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    FirebaseMessaging.onMessage.listen(_showForeground);
    FirebaseMessaging.onMessageOpenedApp.listen((_) => _taps.add(null));
    // Opened from a push while the app was closed.
    if (await _messaging.getInitialMessage() != null) _taps.add(null);
  }

  @override
  Future<void> bind(UserProfile user) async {
    if (_uid == user.uid) return;
    _uid = user.uid;
    final settings = await _messaging.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.denied) return;
    try {
      final token = await _messaging.getToken();
      if (token != null) await _save(token);
    } on Object catch (e) {
      debugPrint('Push token unavailable: $e');
    }
    await _tokenRefresh?.cancel();
    _tokenRefresh = _messaging.onTokenRefresh.listen(_save);
  }

  @override
  Future<void> unbind() async {
    await _tokenRefresh?.cancel();
    _tokenRefresh = null;
    final uid = _uid;
    final token = _token;
    _uid = null;
    _token = null;
    if (uid == null || token == null) return;
    // Best effort: this device should stop getting this person's pushes.
    try {
      await _db.doc('users/$uid/fcmTokens/$token').delete();
    } on Object catch (e) {
      debugPrint('Push token not removed: $e');
    }
  }

  Future<void> _save(String token) async {
    final uid = _uid;
    if (uid == null) return;
    _token = token;
    try {
      await _db.doc('users/$uid/fcmTokens/$token').set({
        'platform': Platform.isIOS ? 'ios' : 'android',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } on Object catch (e) {
      debugPrint('Push token not saved: $e');
    }
  }

  Future<void> _showForeground(RemoteMessage message) async {
    // The company push API sends "title\nbody" as one message, so split it.
    final raw =
        message.notification?.body ??
        message.data['message'] as String? ??
        message.data['body'] as String? ??
        '';
    final lines = raw.split('\n');
    final title =
        message.notification?.title ??
        message.data['title'] as String? ??
        (lines.length > 1 ? lines.first : 'TSL Facility Manager');
    final body = lines.length > 1 && message.notification?.title == null
        ? lines.skip(1).join('\n')
        : raw;
    if (title.isEmpty && body.isEmpty) return;
    await _local.show(
      id: (message.messageId ?? '$title$body').hashCode,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }
}
