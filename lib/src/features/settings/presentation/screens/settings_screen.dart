import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:six7_chat/src/features/contacts/domain/providers/contacts_provider.dart';
import 'package:six7_chat/src/features/messaging/domain/providers/korium_node_provider.dart';
import 'package:six7_chat/src/features/profile/domain/providers/profile_provider.dart';
import 'package:six7_chat/src/korium/korium_bridge.dart' show DhtPeer;

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
          _buildNodeStatusSection(context, nodeState),

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
          backgroundColor: theme.colorScheme.error.withValues(alpha: 0.2),
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
            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.2),
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
                // TODO: Retry connection
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
  Map<String, String?> _resolvedContacts = {}; // identity -> address or null
  List<DhtPeer> _dhtPeers = []; // Peers from DHT routing table
  List<String> _ownAddresses = []; // All routable addresses for this node
  String? _error;
  bool _hasAutoLoaded = false; // Track if we've auto-loaded after bootstrap

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
    final contactsAsync = ref.read(contactsProvider);
    
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
      _resolvedContacts = {};
      _dhtPeers = [];
      _ownAddresses = [];
    });

    await nodeAsync.when(
      loading: () async {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _error = 'Node not ready';
        });
      },
      error: (e, _) async {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _error = 'Node error: $e';
        });
      },
      data: (node) async {
        final contacts = contactsAsync.value ?? [];
        final resolved = <String, String?>{};
        
        // Get own routable addresses
        List<String> ownAddrs = [];
        try {
          ownAddrs = await node.routableAddresses();
        } catch (e) {
          debugPrint('Failed to get own addresses: $e');
        }
        
        // Resolve contacts
        for (final contact in contacts) {
          try {
            final addrs = await node.resolvePeer(peerId: contact.identity);
            resolved[contact.identity] = addrs.isNotEmpty ? addrs.first : null;
          } catch (e) {
            resolved[contact.identity] = null;
          }
        }
        
        // Get DHT peers
        List<DhtPeer> peers = [];
        try {
          peers = await node.getDhtPeers();
        } catch (e) {
          debugPrint('Failed to get DHT peers: $e');
        }
        
        if (mounted) {
          setState(() {
            _ownAddresses = ownAddrs;
            _resolvedContacts = resolved;
            _dhtPeers = peers;
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
          // === OWN CONTACT CARD ===
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header with bootstrap status
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: theme.colorScheme.primary,
                        child: const Icon(Icons.person, size: 24, color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'This Device (You)',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Icon(
                                  isBootstrapped ? Icons.check_circle : Icons.pending,
                                  size: 16,
                                  color: isBootstrapped ? Colors.green : Colors.orange,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  isBootstrapped ? 'Connected to DHT' : 'Connecting...',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isBootstrapped ? Colors.green[700] : Colors.orange,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Green checkmark for bootstrap success
                      if (isBootstrapped)
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check,
                            color: Colors.green,
                            size: 24,
                          ),
                        ),
                    ],
                  ),
                  
                  if (bootstrapError != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
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
                  ],
                  
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  
                  // Identity
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.fingerprint, size: 16, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Identity',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 2),
                            SelectableText(
                              identity.isNotEmpty ? identity : 'Not connected',
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 9,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 12),
                  
                  // Addresses section
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.dns, size: 16, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Addresses (${_ownAddresses.isEmpty ? 1 : _ownAddresses.length})',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.grey,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            // Local bind address
                            _AddressRow(
                              icon: Icons.lan,
                              label: 'Local',
                              address: localAddr,
                              color: Colors.grey,
                            ),
                            // Routable addresses from DHT
                            if (_ownAddresses.isNotEmpty)
                              ..._ownAddresses.map((addr) => _AddressRow(
                                icon: Icons.public,
                                label: 'Routable',
                                address: addr,
                                color: Colors.green,
                              ))
                            else if (isBootstrapped)
                              const _AddressRow(
                                icon: Icons.public,
                                label: 'Routable',
                                address: 'Discovering...',
                                color: Colors.orange,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // === CONTACTS CARD ===
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.people, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Contacts',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Text(
                        '${_resolvedContacts.values.where((v) => v != null).length}/${_resolvedContacts.length} online',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_error != null)
                    Container(
                      padding: const EdgeInsets.all(8),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red, size: 16),
                          const SizedBox(width: 8),
                          Expanded(child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12))),
                        ],
                      ),
                    ),
                  _buildContactsList(context, theme),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // === DHT PEERS CARD ===
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.cloud, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'DHT Peers (${_dhtPeers.length})',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_dhtPeers.isEmpty)
                    Text(
                      isBootstrapped 
                          ? 'No DHT peers discovered yet. Tap refresh to scan.'
                          : 'Waiting for bootstrap...',
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                    )
                  else
                    ..._dhtPeers.map((peer) => _DhtPeerRow(
                      peer: peer,
                      truncateId: _truncateId,
                    )),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactsList(BuildContext context, ThemeData theme) {
    final contactsAsync = ref.watch(contactsProvider);
    
    return contactsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Text('Error: $e', style: const TextStyle(color: Colors.red)),
      data: (contacts) {
        if (contacts.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No contacts yet. Scan a QR code to add contacts.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          );
        }
        return Column(
          children: contacts.map((contact) {
            final resolvedAddr = _resolvedContacts[contact.identity];
            final hasResolved = _resolvedContacts.containsKey(contact.identity);
            
            return _ContactRow(
              contact: contact,
              resolvedAddr: resolvedAddr,
              hasResolved: hasResolved,
              truncateId: _truncateId,
            );
          }).toList(),
        );
      },
    );
  }

  String _truncateId(String id) {
    if (id.length <= 16) return id;
    return '${id.substring(0, 8)}...${id.substring(id.length - 8)}';
  }
}

/// Helper widget for displaying an address row.
class _AddressRow extends StatelessWidget {
  const _AddressRow({
    required this.icon,
    required this.label,
    required this.address,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String address;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 9,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              address,
              style: TextStyle(
                fontSize: 10,
                fontFamily: 'monospace',
                color: color == Colors.grey ? Colors.grey : color,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Helper widget for displaying a contact row.
class _ContactRow extends ConsumerWidget {
  const _ContactRow({
    required this.contact,
    required this.resolvedAddr,
    required this.hasResolved,
    required this.truncateId,
  });

  final dynamic contact; // Contact type
  final String? resolvedAddr;
  final bool hasResolved;
  final String Function(String) truncateId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.2),
            child: Text(
              contact.displayName.substring(0, 1).toUpperCase(),
              style: const TextStyle(fontSize: 14),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  contact.displayName,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                Text(
                  truncateId(contact.identity),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    color: Colors.grey,
                  ),
                ),
                if (hasResolved)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      children: [
                        Icon(
                          resolvedAddr != null ? Icons.check_circle : Icons.cancel,
                          size: 12,
                          color: resolvedAddr != null ? Colors.green : Colors.orange,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            resolvedAddr ?? 'Not found in DHT',
                            style: TextStyle(
                              fontSize: 10,
                              color: resolvedAddr != null ? Colors.green[700] : Colors.orange,
                              fontFamily: resolvedAddr != null ? 'monospace' : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          _ContactStatusIndicator(peerId: contact.identity),
        ],
      ),
    );
  }
}

/// Helper widget for displaying a DHT peer row.
class _DhtPeerRow extends StatelessWidget {
  const _DhtPeerRow({
    required this.peer,
    required this.truncateId,
  });

  final DhtPeer peer;
  final String Function(String) truncateId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: theme.colorScheme.secondary.withValues(alpha: 0.2),
            child: const Icon(Icons.dns, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  truncateId(peer.identity),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                  ),
                ),
                if (peer.addresses.isNotEmpty)
                  ...peer.addresses.take(2).map((addr) => Row(
                    children: [
                      const Icon(Icons.public, size: 10, color: Colors.grey),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          addr,
                          style: const TextStyle(
                            fontSize: 9,
                            color: Colors.grey,
                            fontFamily: 'monospace',
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  )),
                if (peer.addresses.length > 2)
                  Text(
                    '+${peer.addresses.length - 2} more addresses',
                    style: const TextStyle(fontSize: 9, color: Colors.grey),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Widget showing online/offline status for a peer.
class _ContactStatusIndicator extends ConsumerWidget {
  const _ContactStatusIndicator({required this.peerId});

  final String peerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(peerOnlineStatusProvider(peerId));

    return statusAsync.when(
      loading: () => const SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(strokeWidth: 1),
      ),
      error: (_, _) => const Icon(Icons.help_outline, size: 16, color: Colors.grey),
      data: (isOnline) => Icon(
        Icons.circle,
        size: 12,
        color: isOnline ? Colors.green : Colors.grey,
      ),
    );
  }
}
