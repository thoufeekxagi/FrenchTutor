import 'package:flutter/material.dart';
import 'services/storage_service.dart';

class AppProviders extends InheritedWidget {
  final StorageService storageService;

  const AppProviders({
    super.key,
    required this.storageService,
    required super.child,
  });

  static StorageService storageOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<AppProviders>()!
        .storageService;
  }

  @override
  bool updateShouldNotify(AppProviders oldWidget) {
    return storageService != oldWidget.storageService;
  }
}
