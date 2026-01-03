import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:six7_chat/src/features/messaging/domain/providers/korium_node_provider.dart';
import 'package:six7_chat/src/features/profile/domain/providers/profile_provider.dart';
import 'package:six7_chat/src/korium/korium_bridge.dart' show Telemetry;

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nodeState = ref.watch(koriumNodeStateProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          // Profile section
          _buildProfileSection(context, ref, nodeState),

          const Divider(),

          // Node status section
          _buildNodeStatusSection(context, ref, nodeState),

          const Divider(),

          // Settings sections
          ListTile(
            leading: const Icon(Icons.key),
            title: const Text('Account'),
            subtitle: const Text('Privacy, security, change number'),
            onTap: () => context.push('/settings/account'),
          ),
          ListTile(
            leading: const Icon(Icons.chat),
            title: const Text('Chats'),
            subtitle: const Text('Theme, wallpapers, chat history'),
            onTap: () => context.push('/settings/chats'),
          ),
          ListTile(
            leading: const Icon(Icons.notifications),
            title: const Text('Notifications'),
            subtitle: const Text('Vibe & tea notifications'),
            onTap: () => context.push('/settings/notifications'),
          ),
          ListTile(
            leading: const Icon(Icons.data_usage),
            title: const Text('Storage and data'),
            subtitle: const Text('Network usage, auto-download'),
            onTap: () => context.push('/settings/storage'),
          ),
          ListTile(
            leading: const Icon(Icons.language),
            title: const Text('App language'),
            subtitle: const Text("Device's language"),
            onTap: () => context.push('/settings/language'),
          ),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('Help'),
            subtitle: const Text('Help center, contact us, privacy policy'),
            onTap: () => context.push('/settings/help'),
          ),

          const Divider(),

          // About section
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About Six7'),
            subtitle: const Text('Version 1.0.1'),
            onTap: () => _showAboutDialog(context),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileSection(
    BuildContext context,
    WidgetRef ref,
    KoriumNodeState nodeState,
  ) {
    final theme = Theme.of(context);
    final profileAsync = ref.watch(userProfileProvider);
    
    String identity = 'Not connected';
    String? localAddr;
    if (nodeState is KoriumNodeConnected) {
      identity = nodeState.identity;
      localAddr = nodeState.localAddr;
    }

    return profileAsync.when(
      loading: () => const ListTile(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        leading: CircleAvatar(
          radius: 36,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        title: Text('Loading profile...'),
      ),
      error: (error, _) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        leading: CircleAvatar(
          radius: 36,
          // ignore: deprecated_member_use
          backgroundColor: theme.colorScheme.error.withOpacity(0.2),
          child: Icon(Icons.error, size: 36, color: theme.colorScheme.error),
        ),
        title: const Text('Error loading profile'),
        subtitle: Text(error.toString()),
      ),
      data: (profile) {
        final hasAvatar = profile.avatarPath != null;
        final displayName = profile.displayName;
        final status = profile.status ?? '';

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          leading: CircleAvatar(
            radius: 36,
            // ignore: deprecated_member_use
            backgroundColor: theme.colorScheme.primary.withOpacity(0.2),
            backgroundImage: hasAvatar
                ? FileImage(File(profile.avatarPath!))
                : null,
            child: hasAvatar
                ? null
                : Text(
                    displayName.isNotEmpty
                        ? displayName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
          title: Text(
            displayName.isEmpty ? 'Set your name' : displayName,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text(
                status.isEmpty ? 'Set your status' : status,
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => _showQrCode(context, identity, localAddr),
                child: Text(
                  _truncateId(identity),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: Colors.grey,
                  ),
                ),
              ),
            ],
          ),
          trailing: IconButton(
            icon: const Icon(Icons.qr_code),
            onPressed: () => context.push('/qr-display'),
            tooltip: 'Show QR Code',
          ),
          onTap: () => context.push('/profile'),
        );
      },
    );
  }

  Widget _buildNodeStatusSection(
      BuildContext context,
      WidgetRef ref,
      KoriumNodeState nodeState,
  ) {
    IconData icon;
    Color color;
    String title;
    String subtitle;

    switch (nodeState) {
      case KoriumNodeDisconnected():
        icon = Icons.cloud_off;
        color = Colors.grey;
        title = 'Disconnected';
        subtitle = 'Tap to connect';
      case KoriumNodeConnecting():
        icon = Icons.cloud_sync;
        color = Colors.orange;
        title = 'Connecting...';
        subtitle = 'Please wait';
      case KoriumNodeConnected(:final localAddr):
        icon = Icons.cloud_done;
        color = Colors.green;
        title = 'Connected';
        subtitle = 'Listening on $localAddr';
      case KoriumNodeError(:final message):
        icon = Icons.error;
        color = Colors.red;
        title = 'Connection Error';
        subtitle = message;
    }

    return ListTile(
      leading: Icon(icon, color: color, size: 32),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (nodeState is KoriumNodeConnected)
            IconButton(
              icon: const Icon(Icons.hub),
              onPressed: () => _showDhtInfo(context),
              tooltip: 'DHT Info',
            ),
          if (nodeState is KoriumNodeError)
            TextButton(
              onPressed: () {
                // Invalidate the provider to trigger a reconnection attempt
                ref.invalidate(koriumNodeProvider);
              },
              child: const Text('Retry'),
            ),
        ],
      ),
    );
  }

  void _showDhtInfo(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const DhtInfoScreen()),
    );
  }

  void _showQrCode(BuildContext context, String identity, String? localAddr) {
    // Always include address so scanning peers can bootstrap directly
    // Format: six7://IP:PORT/IDENTITY (with address) or six7://IDENTITY (fallback)
    final qrData = localAddr != null && localAddr.isNotEmpty
        ? 'six7://$localAddr/$identity'
        : 'six7://$identity';
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Your Six7 Identity'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 200,
              height: 200,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: QrImageView(
                data: qrData,
                version: QrVersions.auto,
                size: 184,
                backgroundColor: Colors.white,
                errorCorrectionLevel: QrErrorCorrectLevel.M,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _truncateId(identity),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: identity));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied to clipboard')),
                );
              }
            },
            child: const Text('Copy'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              context.push('/qr-display');
            },
            child: const Text('Full Screen'),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'Six7',
      applicationVersion: '1.0.0',
      applicationIcon: const FlutterLogo(size: 64),
      children: [
        const Text(
          'A secure, ephemeral messaging app.\n\n'
          'Features:\n'
          '• End-to-end encrypted messaging\n'
          '• Peer-to-peer communication\n'
          '• No central server\n'
          '• Self-sovereign identity',
        ),
      ],
    );
  }

  String _truncateId(String id) {
    if (id.length <= 16) return id;
    return '${id.substring(0, 8)}...${id.substring(id.length - 8)}';
  }
}

/// Screen showing DHT (Distributed Hash Table) network information.
class DhtInfoScreen extends ConsumerStatefulWidget {
  const DhtInfoScreen({super.key});

  @override
  ConsumerState<DhtInfoScreen> createState() => _DhtInfoScreenState();
}

class _DhtInfoScreenState extends ConsumerState<DhtInfoScreen> {
  bool _isLoading = false;
  List<String> _routableAddresses = [];
  List<String> _subscriptions = [];
  Telemetry? _telemetry;
  bool _hasAutoLoaded = false; // Track if we've auto-loaded after bootstrap
  
  // Expanded section states
  bool _thisDeviceExpanded = true;
  bool _subscriptionsExpanded = false;
  bool _telemetryExpanded = false;

  @override
  void initState() {
    super.initState();
  }

  /// Auto-load data when node becomes bootstrapped
  void _autoLoadIfBootstrapped(KoriumNodeState nodeState) {
    if (!_hasAutoLoaded && 
        !_isLoading && 
        nodeState is KoriumNodeConnected && 
        nodeState.isBootstrapped) {
      _hasAutoLoaded = true;
      // Schedule for next frame to avoid setState during build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _loadNetworkData();
        }
      });
    }
  }

  Future<void> _loadNetworkData() async {
    final nodeAsync = ref.read(koriumNodeProvider);
    
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _routableAddresses = [];
      _subscriptions = [];
      _telemetry = null;
    });

    await nodeAsync.when(
      loading: () async {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
        });
      },
      error: (e, _) async {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
        });
        debugPrint('Node error: $e');
      },
      data: (node) async {
        // Get routable addresses with timeout
        List<String> addresses = [];
        try {
          addresses = await node.routableAddresses()
              .timeout(const Duration(seconds: 5));
        } catch (e) {
          debugPrint('Failed to get routable addresses: $e');
          addresses = ['Discovery timed out'];
        }
        
        // Get subscriptions
        List<String> subs = [];
        try {
          subs = await node.getSubscriptions();
        } catch (e) {
          debugPrint('Failed to get subscriptions: $e');
        }
        
        // Get telemetry
        Telemetry? telem;
        try {
          telem = await node.getTelemetry();
        } catch (e) {
          debugPrint('Failed to get telemetry: $e');
        }
        
        if (mounted) {
          setState(() {
            _routableAddresses = addresses;
            _subscriptions = subs;
            _telemetry = telem;
            _isLoading = false;
          });
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final nodeState = ref.watch(koriumNodeStateProvider);
    final theme = Theme.of(context);

    // Auto-load when bootstrap completes
    _autoLoadIfBootstrapped(nodeState);

    String identity = '';
    String localAddr = '';
    bool isBootstrapped = false;
    String? bootstrapError;
    if (nodeState is KoriumNodeConnected) {
      identity = nodeState.identity;
      localAddr = nodeState.localAddr;
      isBootstrapped = nodeState.isBootstrapped;
      bootstrapError = nodeState.bootstrapError;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Network Info'),
        actions: [
          IconButton(
            icon: _isLoading 
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadNetworkData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // === 1. THIS DEVICE ===
          _buildExpandableSection(
            title: 'This Device',
            icon: Icons.phone_android,
            isExpanded: _thisDeviceExpanded,
            onToggle: () => setState(() => _thisDeviceExpanded = !_thisDeviceExpanded),
            statusWidget: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isBootstrapped ? Colors.green : Colors.orange,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  isBootstrapped ? 'Online' : 'Connecting',
                  style: TextStyle(
                    fontSize: 12,
                    color: isBootstrapped ? Colors.green[700] : Colors.orange,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            child: _buildThisDeviceContent(theme, identity, localAddr, isBootstrapped, bootstrapError),
          ),

          const SizedBox(height: 12),

          // === 2. SUBSCRIPTIONS ===
          _buildExpandableSection(
            title: 'Subscriptions',
            icon: Icons.rss_feed,
            isExpanded: _subscriptionsExpanded,
            onToggle: () => setState(() => _subscriptionsExpanded = !_subscriptionsExpanded),
            statusWidget: Text(
              '${_subscriptions.length} topic${_subscriptions.length == 1 ? '' : 's'}',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            child: _buildSubscriptionsContent(theme, isBootstrapped),
          ),

          const SizedBox(height: 12),

          // === 3. TELEMETRY ===
          _buildExpandableSection(
            title: 'Telemetry',
            icon: Icons.analytics,
            isExpanded: _telemetryExpanded,
            onToggle: () => setState(() => _telemetryExpanded = !_telemetryExpanded),
            statusWidget: _telemetry != null
                ? Text(
                    '${_telemetry!.storedKeys} keys',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  )
                : const SizedBox.shrink(),
            child: _buildTelemetryContent(theme, isBootstrapped),
          ),
        ],
      ),
    );
  }

  /// Builds an expandable section card.
  Widget _buildExpandableSection({
    required String title,
    required IconData icon,
    required bool isExpanded,
    required VoidCallback onToggle,
    required Widget statusWidget,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(icon, color: theme.colorScheme.primary, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  statusWidget,
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.expand_more, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: child,
            ),
            crossFadeState: isExpanded 
                ? CrossFadeState.showSecond 
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }

  /// Content for This Device section.
  Widget _buildThisDeviceContent(
    ThemeData theme, 
    String identity, 
    String localAddr, 
    bool isBootstrapped, 
    String? bootstrapError,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 1),
        const SizedBox(height: 12),
        
        if (bootstrapError != null) ...[
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              // ignore: deprecated_member_use
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    bootstrapError,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        
        // Identity
        _InfoRow(
          icon: Icons.fingerprint,
          label: 'Identity',
          value: identity.isNotEmpty ? identity : 'Not connected',
          isMonospace: true,
          isCopyable: true,
        ),
        
        const SizedBox(height: 8),
        
        // Local Address
        _InfoRow(
          icon: Icons.lan,
          label: 'Local Address',
          value: localAddr,
          isMonospace: true,
        ),
        
        const SizedBox(height: 8),
        
        // Routable Addresses
        _InfoRow(
          icon: Icons.public,
          label: 'Routable Addresses',
          value: _routableAddresses.isEmpty 
              ? 'Discovering...' 
              : _routableAddresses.join('\n'),
          isMonospace: true,
        ),
      ],
    );
  }

  /// Content for Subscriptions section - shows PubSub topics.
  Widget _buildSubscriptionsContent(ThemeData theme, bool isBootstrapped) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 1),
        const SizedBox(height: 12),
        
        if (_subscriptions.isEmpty)
          Text(
            isBootstrapped 
                ? 'No active subscriptions'
                : 'Waiting for bootstrap...',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          )
        else
          ..._subscriptions.map((topic) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(Icons.tag, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    topic,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          )),
      ],
    );
  }

  /// Content for Telemetry section - shows DHT stats.
  Widget _buildTelemetryContent(ThemeData theme, bool isBootstrapped) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 1),
        const SizedBox(height: 12),
        
        if (_telemetry == null)
          Text(
            isBootstrapped 
                ? 'Telemetry unavailable'
                : 'Waiting for bootstrap...',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          )
        else ...[
          _InfoRow(
            icon: Icons.key,
            label: 'Stored Keys',
            value: '${_telemetry!.storedKeys}',
          ),
          const SizedBox(height: 8),
          _InfoRow(
            icon: Icons.content_copy,
            label: 'Replication Factor',
            value: '${_telemetry!.replicationFactor}',
          ),
          const SizedBox(height: 8),
          _InfoRow(
            icon: Icons.sync,
            label: 'Concurrency',
            value: '${_telemetry!.concurrency}',
          ),
        ],
      ],
    );
  }

  String _truncateId(String id) {
    if (id.length <= 16) return id;
    return '${id.substring(0, 8)}...${id.substring(id.length - 8)}';
  }
}

/// Helper widget for displaying an info row with label and value.
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.isMonospace = false,
    this.isCopyable = false,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool isMonospace;
  final bool isCopyable;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              if (isCopyable)
                SelectableText(
                  value,
                  style: TextStyle(
                    fontFamily: isMonospace ? 'monospace' : null,
                    fontSize: isMonospace ? 10 : 13,
                    color: valueColor,
                  ),
                )
              else
                Text(
                  value,
                  style: TextStyle(
                    fontFamily: isMonospace ? 'monospace' : null,
                    fontSize: isMonospace ? 10 : 13,
                    color: valueColor,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}


