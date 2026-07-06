import 'package:flutter/material.dart';
import 'providers.dart';
import 'services/storage_service.dart';
import 'screens/home_screen.dart';

const String serverUrl = 'ws://localhost:8000';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final storageService = StorageService();
  runApp(FrenchTutorApp(storageService: storageService));
}

class FrenchTutorApp extends StatelessWidget {
  final StorageService storageService;

  const FrenchTutorApp({super.key, required this.storageService});

  @override
  Widget build(BuildContext context) {
    return AppProviders(
      storageService: storageService,
      child: MaterialApp(
        title: 'French Tutor',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFF0F0F1A),
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF6C5CE7),
            secondary: Color(0xFF8B7CF6),
            surface: Color(0xFF1A1A2E),
          ),
        ),
        home: const HomeScreen(serverUrl: serverUrl),
      ),
    );
  }
}
