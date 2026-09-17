import 'package:flutter/widgets.dart';

/// 全局路由观察者：供页面在自身重新回到栈顶时刷新数据。
final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();
