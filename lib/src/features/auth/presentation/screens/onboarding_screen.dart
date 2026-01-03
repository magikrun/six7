import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:six7_chat/src/features/messaging/domain/providers/korium_node_provider.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                },
                children: [
                  _buildPage(
                    context,
                    icon: Icons.security,
                    title: 'Secure Messaging',
                    description:
                        'All messages are end-to-end encrypted using Ed25519 cryptography. '
                        'Only you and the recipient can read your messages.',
                  ),
                  _buildPage(
                    context,
                    icon: Icons.hub,
                    title: 'Decentralized',
                    description:
                        'No central servers. Your messages travel directly between peers '
                        'using secure mesh networking.',
                  ),
                  _buildPage(
                    context,
                    icon: Icons.fingerprint,
                    title: 'Self-Sovereign Identity',
                    description:
                        'Your identity is your cryptographic key. No phone number or email required. '
                        'You own your identity.',
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  // Page indicators
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(3, (index) {
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: _currentPage == index ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _currentPage == index
                              ? theme.colorScheme.primary
                              : theme.colorScheme.primary.withValues(
                                  alpha: 0.3,
                                ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 32),
                  // Action buttons
                  if (_currentPage == 2) ...[
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => _setupNode(context),
                        child: const Text('Get Started'),
                      ),
                    ),
                  ] else ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: () => context.go('/'),
                          child: const Text('Skip'),
                        ),
                        FilledButton(
                          onPressed: () {
                            _pageController.nextPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            );
                          },
                          child: const Text('Next'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPage(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
  }) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 80,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 48),
          Text(
            title,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            description,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Future<void> _setupNode(BuildContext context) async {
    // Show loading dialog
    unawaited(showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Setting up your Six7 identity...'),
          ],
        ),
      ),
    ),);

    try {
      // Initialize the Korium node
      await ref.read(koriumNodeProvider.future);

      if (context.mounted) {
        Navigator.pop(context); // Close loading dialog
        context.go('/');
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to initialize: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
