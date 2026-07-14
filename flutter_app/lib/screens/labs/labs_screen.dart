import 'package:flutter/material.dart';
import '../../config/theme.dart';
import 'vocab_lab_screen.dart';
import 'grammar_lab_screen.dart';
import 'connectors_lab_screen.dart';
import 'listening_lab_screen.dart';
import 'writing_lab_screen.dart';

class LabsScreen extends StatelessWidget {
  const LabsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Passeport.parchment,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              Text('Labs', style: Passeport.display(24)),
              const SizedBox(height: 4),
              Text('Practice by skill', style: Passeport.body(14).copyWith(color: Passeport.slateDim)),
              const SizedBox(height: 24),
              Expanded(
                child: ListView(
                  children: [
                    _LabTile(
                      icon: Icons.abc,
                      title: 'Vocabulary',
                      subtitle: 'Flashcards & SRS',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const VocabLabScreen()),
                      ),
                    ),
                    _LabTile(
                      icon: Icons.menu_book_rounded,
                      title: 'Grammar',
                      subtitle: 'Lessons & drills',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const GrammarLabScreen()),
                      ),
                    ),
                    _LabTile(
                      icon: Icons.link_rounded,
                      title: 'Connectors',
                      subtitle: 'Logic words',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ConnectorsLabScreen()),
                      ),
                    ),
                    _LabTile(
                      icon: Icons.headphones_rounded,
                      title: 'Listening',
                      subtitle: 'Comprehension',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ListeningLabScreen()),
                      ),
                    ),
                    _LabTile(
                      icon: Icons.edit_rounded,
                      title: 'Writing',
                      subtitle: 'Essays & grading',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const WritingLabScreen()),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LabTile extends StatelessWidget {
  const _LabTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Passeport.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Passeport.hairline, width: 1),
      ),
      child: ListTile(
        leading: Icon(icon, color: Passeport.brass, size: 28),
        title: Text(title, style: Passeport.body(15, weight: FontWeight.w500)),
        subtitle: Text(subtitle, style: Passeport.body(12).copyWith(color: Passeport.slateDim)),
        trailing: Icon(Icons.chevron_right, color: Passeport.slate, size: 20),
        onTap: onTap,
      ),
    );
  }
}
