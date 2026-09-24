import 'package:flutter/material.dart';

import 'app.dart';
import 'state/theme_store.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 先恢复外观偏好，避免启动瞬间先闪浅色主题
  await ThemeStore.instance.load();
  runApp(const BeancountTransApp());
}
