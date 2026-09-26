import 'dart:io';

import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Android 待办角标通知渠道（ID 固定，便于覆盖与撤销同一条通知）。
const String kTodoBadgeChannelId = 'todo_badge';
const String kTodoBadgeChannelName = '待办角标';
const String kTodoBadgeChannelDescription = '仅用于在应用图标上显示待办数量角标，不发出声音与横幅';

/// 汇总通知的固定 ID。
const int kTodoBadgeNotificationId = 90210;

/// 通知重要性：low —— 可靠性优先（部分启动器会抑制 min 重要性的角标）。
/// 若希望状态栏完全不出现图标，可改为 [Importance.min]，但需接受角标可能不显示。
const Importance kTodoBadgeImportance = Importance.low;

/// 系统图标气泡服务：Android 走「通知驱动角标」，iOS 走 badge 授权后直接写角标。
///
/// Android 8+ 官方只承认「通知驱动」的角标，因此必须存在一条活跃通知，
/// 其 [AndroidNotificationDetails.number] 即角标数字；撤销通知即清除角标。
///
/// 角标失败一律静默降级（仅 [debugPrint]），绝不影响登录与待办列表等主流程；
/// 非移动平台（含 `flutter test` 的宿主机环境）为空实现。
class BadgeService {
  BadgeService._();

  static final BadgeService instance = BadgeService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _notificationPermissionRequested = false;
  bool _badgePermissionRequested = false;

  /// 仅移动端可用。
  bool get _supported => Platform.isAndroid || Platform.isIOS;

  /// 同步系统角标；[count] <= 0 时清除角标。
  Future<void> setCount(int count) async {
    if (!_supported) return;
    try {
      await _ensureInitialized();
      final value = count < 0 ? 0 : count;
      if (value == 0) {
        await _clear();
      } else {
        await _show(value);
      }
    } catch (error) {
      debugPrint('同步系统角标失败：$error');
    }
  }

  /// 清除角标（退出登录 / 登录态失效时调用）。
  Future<void> clear() => setCount(0);

  Future<void> _ensureInitialized() async {
    if (_initialized) return;

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_notification'),
        // 授权时机交给 setCount —— 有真实待办时才弹窗，此处不主动请求
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );

    if (Platform.isAndroid) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              kTodoBadgeChannelId,
              kTodoBadgeChannelName,
              description: kTodoBadgeChannelDescription,
              importance: kTodoBadgeImportance,
              playSound: false,
              enableVibration: false,
              showBadge: true,
            ),
          );
    }

    _initialized = true;
  }

  Future<void> _show(int count) async {
    if (Platform.isAndroid) {
      if (!_notificationPermissionRequested) {
        _notificationPermissionRequested = true;
        // Android 13 以下返回 null（无需授权），结果不影响后续逻辑
        await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission();
      }

      await _plugin.show(
        id: kTodoBadgeNotificationId,
        title: '$count 项待办',
        body: '点击查看解析审核与到期对账',
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            kTodoBadgeChannelId,
            kTodoBadgeChannelName,
            channelDescription: kTodoBadgeChannelDescription,
            importance: kTodoBadgeImportance,
            priority: Priority.low,
            showWhen: false,
            playSound: false,
            enableVibration: false,
            silent: true,
            ongoing: false,
            autoCancel: false,
            onlyAlertOnce: true,
            number: count,
          ),
        ),
      );
      return;
    }

    if (!_badgePermissionRequested) {
      _badgePermissionRequested = true;
      // 只申请角标权限，不申请横幅与声音
      await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: false, badge: true, sound: false);
    }

    await AppBadgePlus.updateBadge(count);
  }

  Future<void> _clear() async {
    if (Platform.isAndroid) {
      await _plugin.cancel(id: kTodoBadgeNotificationId);
      return;
    }
    await AppBadgePlus.updateBadge(0);
  }
}
