import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Help settings screen for help center, contact, and privacy policy.
class HelpSettingsScreen extends StatelessWidget {
  const HelpSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Help'),
      ),
      body: ListView(
        children: [
          // Help section
          _buildSectionHeader(context, 'Help center'),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('FAQs'),
            subtitle: const Text('Frequently asked questions'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showFaqs(context),
          ),
          ListTile(
            leading: const Icon(Icons.search),
            title: const Text('Search for help'),
            subtitle: const Text('Find answers to your questions'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showSearch(context),
          ),

          const Divider(),

          // Contact section
          _buildSectionHeader(context, 'Contact us'),
          ListTile(
            leading: const Icon(Icons.email_outlined),
            title: const Text('Contact support'),
            subtitle: const Text('Get help from our support team'),
            onTap: () => _contactSupport(context),
          ),
          ListTile(
            leading: const Icon(Icons.bug_report_outlined),
            title: const Text('Report a bug'),
            subtitle: const Text('Help us improve Six7'),
            onTap: () => _reportBug(context),
          ),
          ListTile(
            leading: const Icon(Icons.lightbulb_outline),
            title: const Text('Suggest a feature'),
            subtitle: const Text('Tell us what you\'d like to see'),
            onTap: () => _suggestFeature(context),
          ),

          const Divider(),

          // Legal section
          _buildSectionHeader(context, 'Legal'),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy policy'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _openUrl(context, 'https://six7.app/privacy'),
          ),
          ListTile(
            leading: const Icon(Icons.article_outlined),
            title: const Text('Terms of service'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _openUrl(context, 'https://six7.app/terms'),
          ),
          ListTile(
            leading: const Icon(Icons.gavel_outlined),
            title: const Text('Open source licenses'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showLicenses(context),
          ),

          const Divider(),

          // About section
          _buildSectionHeader(context, 'About'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About Six7'),
            subtitle: const Text('Learn more about our mission'),
            onTap: () => _showAbout(context),
          ),
          ListTile(
            leading: const Icon(Icons.code),
            title: const Text('Open source'),
            subtitle: const Text('View the source code on GitHub'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _openUrl(context, 'https://github.com/six7chat/six7'),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
    );
  }

  void _showFaqs(BuildContext context) {
    final faqs = [
      (
        'What is Six7?',
        'Six7 is a secure, ephemeral messaging app that uses peer-to-peer '
            'communication. Your messages are end-to-end encrypted and never '
            'stored on central servers.',
      ),
      (
        'How does Six7 protect my privacy?',
        'Six7 uses strong encryption for all messages. Communications happen '
            'directly between devices without passing through servers. Your '
            'identity is cryptographic and self-sovereign.',
      ),
      (
        'Can I recover my account?',
        'Since Six7 uses self-sovereign identity, you should back up your '
            'identity keys. Without them, account recovery is not possible.',
      ),
      (
        'How do I add contacts?',
        'You can add contacts by scanning their QR code or by manually '
            'entering their Six7 identity address.',
      ),
      (
        'Are group chats encrypted?',
        'Yes, group chats use the same strong encryption as direct messages. '
            'Only group members can read messages.',
      ),
    ];

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('FAQs')),
          body: ListView.builder(
            itemCount: faqs.length,
            itemBuilder: (context, index) {
              final (question, answer) = faqs[index];
              return ExpansionTile(
                title: Text(question),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(answer),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  void _showSearch(BuildContext context) {
    showSearch(
      context: context,
      delegate: _HelpSearchDelegate(),
    );
  }

  void _contactSupport(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Contact Support',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            const Text(
              'Our support team is available to help you with any issues.',
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.email),
              title: const Text('Email'),
              subtitle: const Text('support@six7.app'),
              onTap: () {
                Navigator.pop(context);
                _openUrl(context, 'mailto:support@six7.app');
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _reportBug(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Report a Bug'),
        // ignore: prefer_const_constructors - Contains TextField (StatefulWidget)
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Please describe the issue you encountered. Include steps to '
              'reproduce if possible.',
            ),
            const SizedBox(height: 16),
            // ignore: prefer_const_constructors - TextField is StatefulWidget
            TextField(
              maxLines: 4,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Describe the bug...',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Thank you for your report!'),
                ),
              );
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  void _suggestFeature(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Suggest a Feature'),
        // ignore: prefer_const_constructors - Contains TextField (StatefulWidget)
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'We\'d love to hear your ideas! What feature would you like to '
              'see in Six7?',
            ),
            const SizedBox(height: 16),
            // ignore: prefer_const_constructors - TextField is StatefulWidget
            TextField(
              maxLines: 4,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Describe your feature idea...',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Thank you for your suggestion!'),
                ),
              );
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  Future<void> _openUrl(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open $url')),
        );
      }
    }
  }

  void _showLicenses(BuildContext context) {
    showLicensePage(
      context: context,
      applicationName: 'Six7',
      applicationVersion: '1.0.0',
      applicationIcon: const Padding(
        padding: EdgeInsets.all(8),
        child: FlutterLogo(size: 64),
      ),
    );
  }

  void _showAbout(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('About Six7'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Six7 is a secure, ephemeral messaging application built with '
              'privacy as the core principle.',
            ),
            SizedBox(height: 16),
            Text(
              'Our Mission',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 8),
            Text(
              'To provide truly private communication that respects user '
              'sovereignty. No central servers, no data harvesting, no '
              'compromises.',
            ),
            SizedBox(height: 16),
            Text(
              'Key Features',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 8),
            Text('• End-to-end encryption'),
            Text('• Peer-to-peer communication'),
            Text('• Self-sovereign identity'),
            Text('• No central servers'),
            Text('• Open source'),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _HelpSearchDelegate extends SearchDelegate<String> {
  final List<(String, String)> helpTopics = [
    ('Getting started', 'Learn how to set up and use Six7'),
    ('Adding contacts', 'How to add and manage your contacts'),
    ('Sending messages', 'Send text, photos, and files'),
    ('Groups', 'Create and manage group conversations'),
    ('Privacy settings', 'Configure your privacy preferences'),
    ('Security', 'Keep your account secure'),
    ('Notifications', 'Customize your notification settings'),
    ('Troubleshooting', 'Fix common issues'),
  ];

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      IconButton(
        icon: const Icon(Icons.clear),
        onPressed: () => query = '',
      ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, ''),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return _buildSearchResults();
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return _buildSearchResults();
  }

  Widget _buildSearchResults() {
    final filtered = helpTopics.where((topic) {
      final (title, description) = topic;
      final queryLower = query.toLowerCase();
      return title.toLowerCase().contains(queryLower) ||
          description.toLowerCase().contains(queryLower);
    }).toList();

    if (filtered.isEmpty) {
      return const Center(
        child: Text('No results found'),
      );
    }

    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final (title, description) = filtered[index];
        return ListTile(
          leading: const Icon(Icons.article),
          title: Text(title),
          subtitle: Text(description),
          onTap: () => close(context, title),
        );
      },
    );
  }
}
