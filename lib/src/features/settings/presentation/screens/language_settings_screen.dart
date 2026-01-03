import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:six7_chat/src/features/settings/domain/providers/settings_provider.dart';

/// Language settings screen for selecting app language.
class LanguageSettingsScreen extends ConsumerWidget {
  const LanguageSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedLanguage = ref.watch(languageSettingsProvider);
    final notifier = ref.read(languageSettingsProvider.notifier);
    const languages = LanguageSettingsNotifier.supportedLanguages;

    return Scaffold(
      appBar: AppBar(
        title: const Text('App language'),
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Select your preferred language for the app interface.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const Divider(height: 1),
          ...languages.entries.map((entry) {
            final code = entry.key;
            final name = entry.value;
            final isSelected = code == selectedLanguage;

            return ListTile(
              leading: Icon(
                isSelected ? Icons.check_circle : Icons.circle_outlined,
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey,
              ),
              title: Text(name),
              subtitle: code != 'system'
                  ? Text(
                      _getNativeName(code),
                      style: const TextStyle(fontSize: 12),
                    )
                  : null,
              onTap: () async {
                await notifier.setLanguage(code);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Language set to $name'),
                    ),
                  );
                }
              },
            );
          }),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Note: Changing the language may require restarting the app.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  String _getNativeName(String code) {
    return switch (code) {
      'en' => 'English',
      'de' => 'German',
      'fr' => 'French',
      'es' => 'Spanish',
      'it' => 'Italian',
      'pt' => 'Portuguese',
      'zh' => 'Chinese',
      'ja' => 'Japanese',
      'ko' => 'Korean',
      _ => '',
    };
  }
}
