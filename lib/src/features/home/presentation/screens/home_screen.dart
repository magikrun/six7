import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:six7_chat/src/features/contacts/domain/models/contact.dart';
import 'package:six7_chat/src/features/groups/domain/providers/groups_provider.dart';
import 'package:six7_chat/src/features/home/presentation/widgets/chat_list_tile.dart';
import 'package:six7_chat/src/features/home/domain/providers/chat_list_provider.dart';
import 'package:six7_chat/src/features/vibes/domain/models/vibe.dart';
import 'package:six7_chat/src/features/vibes/domain/models/vibe_profile.dart';
import 'package:six7_chat/src/features/vibes/domain/providers/discovery_provider.dart';
import 'package:six7_chat/src/features/vibes/domain/providers/vibes_provider.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Subscribe to all group topics when node is ready
    // This provider handles subscription automatically
    ref.watch(groupTopicSubscriptionProvider);
    
    // Listen for incoming group invites and auto-join
    ref.watch(groupInviteListenerProvider);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Six7'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () => _showQrScanner(context),
            tooltip: 'Scan QR Code',
          ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => context.push('/search'),
            tooltip: 'Search',
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
            tooltip: 'Settings',
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _BeatsTab(),
          _TeasTab(),
          _VibesTab(),
        ],
      ),
      bottomNavigationBar: Material(
        color: Theme.of(context).colorScheme.primary,
        child: SafeArea(
          top: false,
          child: TabBar(
            controller: _tabController,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: const [
              Tab(text: 'Beats'),
              Tab(text: 'Teas'),
              Tab(text: 'Vibes'),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/contacts'),
        tooltip: 'Start a chat',
        child: const Icon(Icons.chat_bubble),
      ),
    );
  }

  void _showQrScanner(BuildContext context) {
    context.push('/qr-scanner');
  }
}

/// Beats tab - 1:1 direct chats
class _BeatsTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatListAsync = ref.watch(chatListProvider);

    return chatListAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text('Error: $error'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => ref.invalidate(chatListProvider),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (chats) {
        if (chats.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.chat_bubble_outline,
                  size: 80,
                  color: Theme.of(context).colorScheme.primary.withValues(
                        alpha: 0.5,
                      ),
                ),
                const SizedBox(height: 16),
                Text(
                  'No beats yet',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Start a 1:1 chat with someone',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey,
                      ),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          itemCount: chats.length,
          separatorBuilder: (context, index) => const Divider(
            indent: 88,
            height: 1,
          ),
          itemBuilder: (context, index) {
            final chat = chats[index];
            return ChatListTile(
              chat: chat,
              onTap: () => context.push(
                '/chat/${chat.peerId}?name=${Uri.encodeComponent(chat.peerName)}',
              ),
              onDelete: () {
                ref.read(chatListProvider.notifier).deleteChat(chat.peerId);
              },
              onTogglePin: () {
                ref.read(chatListProvider.notifier).togglePin(chat.peerId);
              },
            );
          },
        );
      },
    );
  }
}

/// Teas tab - Group chats
class _TeasTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(groupsProvider);
    final theme = Theme.of(context);

    return groupsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text('Error: $error'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => ref.invalidate(groupsProvider),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (groups) {
        if (groups.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.groups_outlined,
                  size: 80,
                  color: theme.colorScheme.primary.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 16),
                Text(
                  'No teas yet',
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Create a group to spill the tea with your crew',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.grey,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => context.push('/new-group'),
                  icon: const Icon(Icons.group_add),
                  label: const Text('Spill the tea'),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          itemCount: groups.length,
          separatorBuilder: (context, index) => const Divider(
            indent: 88,
            height: 1,
          ),
          itemBuilder: (context, index) {
            final group = groups[index];
            return ListTile(
              leading: CircleAvatar(
                radius: 28,
                backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.2),
                child: Text(
                  _getGroupInitials(group.name),
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              title: Text(
                group.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                '${group.memberIds.length} members',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[600],
                ),
              ),
              onTap: () => context.push('/group-chat/${group.id}'),
            );
          },
        );
      },
    );
  }

  String _getGroupInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts[0].isNotEmpty ? parts[0][0].toUpperCase() : '?';
    }
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
}

/// Vibes tab - Swipe to match
class _VibesTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Matches now automatically create chat messages,
    // so users see matches in the Beats tab instead
    return _UnifiedSwipeView();
  }
}

/// Represents a swipeable item (either Contact or VibeProfile)
sealed class SwipeItem {
  String get identity;
  String get displayName;
  String? get bio;
  String? get avatarUrl;
  bool get isDiscovered;
}

class ContactSwipeItem implements SwipeItem {
  final Contact contact;
  ContactSwipeItem(this.contact);

  @override
  String get identity => contact.identity;
  @override
  String get displayName => contact.displayName;
  @override
  String? get bio => contact.status;
  @override
  String? get avatarUrl => contact.avatarUrl;
  @override
  bool get isDiscovered => false;
}

class DiscoveredSwipeItem implements SwipeItem {
  final VibeProfile profile;
  DiscoveredSwipeItem(this.profile);

  @override
  String get identity => profile.identity;
  @override
  String get displayName => profile.name;
  @override
  String? get bio => profile.bio;
  @override
  String? get avatarUrl => null; // VibeProfile doesn't have avatars
  @override
  bool get isDiscovered => true;
}

/// Unified swipe view - shows contacts first, then discovered profiles
class _UnifiedSwipeView extends ConsumerStatefulWidget {
  @override
  ConsumerState<_UnifiedSwipeView> createState() => _UnifiedSwipeViewState();
}

class _UnifiedSwipeViewState extends ConsumerState<_UnifiedSwipeView> {
  double _dragX = 0;
  double _dragY = 0;
  bool _isDragging = false;

  void _resetDrag() {
    setState(() {
      _dragX = 0;
      _dragY = 0;
      _isDragging = false;
    });
  }

  Future<void> _onSwipeRight(SwipeItem item) async {
    switch (item) {
      case ContactSwipeItem(:final contact):
        await ref.read(vibesProvider.notifier).sendVibe(contact);
      case DiscoveredSwipeItem(:final profile):
        await ref.read(vibesProvider.notifier).sendVibeToDiscovered(profile);
    }
    if (mounted) {
      _resetDrag();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sent vibe to ${item.displayName}'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _onSwipeLeft(SwipeItem item) async {
    switch (item) {
      case ContactSwipeItem(:final contact):
        await ref.read(vibesProvider.notifier).skipContact(contact.identity);
      case DiscoveredSwipeItem(:final profile):
        await ref.read(vibesProvider.notifier).skipDiscovered(profile.identity);
    }
    if (mounted) {
      _resetDrag();
    }
  }

  @override
  Widget build(BuildContext context) {
    final availableContacts = ref.watch(availableToVibeProvider);
    final discoveredProfiles = ref.watch(discoverableProfilesProvider);
    final receivedVibes = ref.watch(receivedVibesProvider);
    final discoveryEnabled = ref.watch(discoveryEnabledProvider);
    final theme = Theme.of(context);

    // Show received vibes first (they vibed us)
    if (receivedVibes.isNotEmpty) {
      return _ReceivedVibesPrompt(
        receivedVibes: receivedVibes,
        onVibeBack: (vibe) async {
          // Find the contact or create temporary one
          final contacts = ref.read(availableToVibeProvider);
          final contact = contacts.firstWhere(
            (c) => c.identity == vibe.contactId,
            orElse: () => Contact(
              identity: vibe.contactId,
              displayName: vibe.contactName,
              addedAt: DateTime.now(),
            ),
          );
          await ref.read(vibesProvider.notifier).sendVibe(contact);
        },
        onSkip: (vibe) async {
          await ref.read(vibesProvider.notifier).skipContact(vibe.contactId);
        },
      );
    }

    // Build unified list: contacts first, then discovered profiles (if enabled)
    final List<SwipeItem> swipeItems = [
      ...availableContacts.map((c) => ContactSwipeItem(c)),
      if (discoveryEnabled)
        ...discoveredProfiles.map((p) => DiscoveredSwipeItem(p)),
    ];

    if (swipeItems.isEmpty) {
      return _EmptySwipeState(discoveryEnabled: discoveryEnabled);
    }

    final currentItem = swipeItems.first;
    final screenWidth = MediaQuery.of(context).size.width;
    final swipeProgress = (_dragX / (screenWidth * 0.4)).clamp(-1.0, 1.0);
    final rotation = swipeProgress * 0.2;

    return Column(
      children: [
        Expanded(
          child: Center(
            child: GestureDetector(
              onPanStart: (_) {
                setState(() => _isDragging = true);
              },
              onPanUpdate: (details) {
                setState(() {
                  _dragX += details.delta.dx;
                  _dragY += details.delta.dy;
                });
              },
              onPanEnd: (details) {
                if (_dragX.abs() > screenWidth * 0.3) {
                  if (_dragX > 0) {
                    _onSwipeRight(currentItem);
                  } else {
                    _onSwipeLeft(currentItem);
                  }
                } else {
                  _resetDrag();
                }
              },
              child: Transform.translate(
                offset: Offset(_dragX, _dragY),
                child: Transform.rotate(
                  angle: rotation,
                  child: Stack(
                    children: [
                      _SwipeCard(item: currentItem),
                      // Like/Nope overlay
                      if (_isDragging && _dragX.abs() > 20)
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _dragX > 0 ? Colors.green : Colors.red,
                                width: 4,
                              ),
                            ),
                            child: Center(
                              child: Transform.rotate(
                                angle: -0.3,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: _dragX > 0 ? Colors.green : Colors.red,
                                      width: 3,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    _dragX > 0 ? 'VIBE' : 'SKIP',
                                    style: TextStyle(
                                      color: _dragX > 0 ? Colors.green : Colors.red,
                                      fontSize: 32,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        // Action buttons
        Padding(
          padding: const EdgeInsets.only(bottom: 32),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Skip button
              Material(
                elevation: 4,
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: () => _onSwipeLeft(currentItem),
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.colorScheme.surface,
                    ),
                    child: const Icon(
                      Icons.close,
                      color: Colors.red,
                      size: 32,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 40),
              // Vibe button
              Material(
                elevation: 4,
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: () => _onSwipeRight(currentItem),
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          theme.colorScheme.primary,
                          theme.colorScheme.secondary,
                        ],
                      ),
                    ),
                    child: const Icon(
                      Icons.favorite,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Remaining count
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(
            '${swipeItems.length} ${swipeItems.length == 1 ? "person" : "people"} to swipe',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// Unified swipe card for both contacts and discovered profiles
class _SwipeCard extends StatelessWidget {
  final SwipeItem item;

  const _SwipeCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initials = _getInitials(item.displayName);
    final isDiscovered = item.isDiscovered;

    return Container(
      width: 320,
      height: 420,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background gradient - different for discovered vs contacts
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDiscovered
                      ? [
                          theme.colorScheme.tertiaryContainer,
                          theme.colorScheme.secondaryContainer,
                        ]
                      : [
                          theme.colorScheme.primaryContainer,
                          theme.colorScheme.secondaryContainer,
                        ],
                ),
              ),
            ),
            // Content
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Avatar - show image if available, otherwise initials
                CircleAvatar(
                  radius: 70,
                  backgroundColor: isDiscovered
                      ? theme.colorScheme.tertiary
                      : theme.colorScheme.primary,
                  backgroundImage: item.avatarUrl != null
                      ? FileImage(File(item.avatarUrl!))
                      : null,
                  child: item.avatarUrl == null
                      ? Text(
                          initials,
                          style: const TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        )
                      : null,
                ),
                const SizedBox(height: 20),
                // Name
                Text(
                  item.displayName,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                  textAlign: TextAlign.center,
                ),
                // Bio/Status
                if (item.bio != null && item.bio!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      item.bio!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer
                            .withValues(alpha: 0.7),
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                // Source badge
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isDiscovered ? Icons.location_on : Icons.person,
                      size: 16,
                      color: isDiscovered
                          ? theme.colorScheme.tertiary
                          : theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isDiscovered ? 'Nearby' : 'Contact',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: isDiscovered
                            ? theme.colorScheme.tertiary
                            : theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts[0].isNotEmpty ? parts[0][0].toUpperCase() : '?';
    }
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
}

/// Empty state when no people to swipe
class _EmptySwipeState extends ConsumerWidget {
  final bool discoveryEnabled;

  const _EmptySwipeState({required this.discoveryEnabled});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.favorite_border,
              size: 80,
              color: theme.colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 24),
            Text(
              'No one to swipe',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              discoveryEnabled
                  ? 'Add more contacts or wait for\nnearby people to appear'
                  : 'Add contacts or enable discovery\nto meet new people nearby',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: () => context.push('/contacts'),
                  icon: const Icon(Icons.person_add),
                  label: const Text('Add Contacts'),
                ),
                if (!discoveryEnabled) ...[
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: () => context.push('/settings/account'),
                    icon: const Icon(Icons.explore),
                    label: const Text('Discovery'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}



/// Prompt shown when someone has vibed us
class _ReceivedVibesPrompt extends StatelessWidget {
  final List<Vibe> receivedVibes;
  final void Function(Vibe) onVibeBack;
  final void Function(Vibe) onSkip;

  const _ReceivedVibesPrompt({
    required this.receivedVibes,
    required this.onVibeBack,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vibe = receivedVibes.first;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Pulsing heart animation effect
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primaryContainer,
              ),
              child: Icon(
                Icons.favorite,
                size: 48,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Someone vibed you!',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${vibe.contactName} sent you a vibe',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'Vibe back to match!',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Skip
                OutlinedButton.icon(
                  onPressed: () => onSkip(vibe),
                  icon: const Icon(Icons.close),
                  label: const Text('Skip'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey,
                    side: const BorderSide(color: Colors.grey),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Vibe back
                FilledButton.icon(
                  onPressed: () => onVibeBack(vibe),
                  icon: const Icon(Icons.favorite),
                  label: const Text('Vibe Back'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                ),
              ],
            ),
            if (receivedVibes.length > 1) ...[
              const SizedBox(height: 16),
              Text(
                '+${receivedVibes.length - 1} more waiting',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
