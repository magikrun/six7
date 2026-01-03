import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:six7_chat/src/features/home/presentation/widgets/chat_list_tile.dart';
import 'package:six7_chat/src/features/home/domain/providers/chat_list_provider.dart';

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
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Six7'),
        actions: [
          IconButton(
            icon: const Icon(Icons.hub),
            onPressed: () => context.push('/dht-info'),
            tooltip: 'Network Info',
          ),
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
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'VIBES'),
            Tab(text: 'TEA'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _VibesTab(),
          _TeaTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/contacts'),
        tooltip: 'Start a vibe',
        child: const Icon(Icons.chat_bubble),
      ),
    );
  }

  void _showQrScanner(BuildContext context) {
    context.push('/qr-scanner');
  }
}

class _VibesTab extends ConsumerWidget {
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
                  'No vibes yet',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Check your vibes — tap to start one',
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
            );
          },
        );
      },
    );
  }
}

class _TeaTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.groups_outlined,
            size: 80,
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'The Tea is boiling',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Group vibes coming soon — spill the tea with your crew',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
