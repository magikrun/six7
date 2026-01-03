import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:six7_chat/src/features/messaging/domain/providers/korium_node_provider.dart';

/// Screen that displays the user's QR code for sharing their identity.
///
/// The QR code contains a six7:// URI format with multiple addresses:
/// six7://IDENTITY?addrs=IP1:PORT1,IP2:PORT2
/// 
/// Addresses include both:
/// - External (STUN-discovered) for peers on different networks
/// - LAN addresses for peers on the same local network
class QrDisplayScreen extends ConsumerStatefulWidget {
  const QrDisplayScreen({super.key});

  @override
  ConsumerState<QrDisplayScreen> createState() => _QrDisplayScreenState();
}

class _QrDisplayScreenState extends ConsumerState<QrDisplayScreen> {
  List<String>? _addresses;
  bool _loadingAddresses = true;

  @override
  void initState() {
    super.initState();
    // Load addresses immediately
    _loadAddresses();
  }

  Future<void> _loadAddresses() async {
    try {
      final node = await ref.read(koriumNodeProvider.future);
      
      // Get routable addresses from korium
      List<String> addresses = [];
      try {
        addresses = await node.routableAddresses();
        debugPrint('QR: Routable addresses: $addresses');
      } catch (e) {
        debugPrint('QR: routableAddresses failed: $e');
      }
      
      // Filter invalid addresses (0.0.0.0 only - always invalid)
      // Keep 10.0.2.x for emulator testing; korium provides real IPs on real devices
      final validAddrs = addresses.where((addr) {
        if (addr.startsWith('0.0.0.0')) return false;
        return true;
      }).toList();
      
      debugPrint('QR: Final valid addresses: $validAddrs');
      
      if (mounted) {
        setState(() {
          _addresses = validAddrs;
          _loadingAddresses = false;
        });
      }
    } catch (e) {
      debugPrint('QR: Error loading addresses: $e');
      if (mounted) {
        setState(() {
          _loadingAddresses = false;
        });
      }
    }
  }
  
  Future<void> _refreshAddresses() async {
    if (!mounted) return;
    setState(() {
      _loadingAddresses = true;
    });
    await _loadAddresses();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nodeState = ref.watch(koriumNodeStateProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My QR Code'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: _buildQrContent(context, nodeState, theme),
                ),
              ),
              const SizedBox(height: 24),
              _buildInstructions(context, theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQrContent(
    BuildContext context,
    KoriumNodeState nodeState,
    ThemeData theme,
  ) {
    switch (nodeState) {
      case KoriumNodeDisconnected():
      case KoriumNodeConnecting():
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Connecting...',
              style: theme.textTheme.titleMedium,
            ),
          ],
        );

      case KoriumNodeError(:final message):
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'Connection Error',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        );

      case KoriumNodeConnected(:final identity, localAddr: _):
        // If still loading addresses, show spinner
        if (_loadingAddresses) {
          return const CircularProgressIndicator();
        }
        
        // Addresses are already filtered during loading
        final validAddrs = _addresses ?? [];
        
        // Create the QR data in six7:// URI format with all addresses
        // Format: six7://IDENTITY?addrs=IP1:PORT1,IP2:PORT2
        // This allows peers on same LAN or different networks to connect
        final String qrData;
        if (validAddrs.isNotEmpty) {
          final addrsParam = Uri.encodeQueryComponent(validAddrs.join(','));
          qrData = 'six7://$identity?addrs=$addrsParam';
        } else {
          // Fallback to identity-only format (DHT lookup required)
          qrData = 'six7://$identity';
        }
        
        // Debug: log what addresses we found
        debugPrint('QR Display: all addresses: $_addresses');
        debugPrint('QR Display: valid addresses: $validAddrs');
        debugPrint('QR Display: qrData: $qrData');

        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // QR Code Card
            Card(
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // QR Code
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: QrImageView(
                        data: qrData,
                        version: QrVersions.auto,
                        size: 220,
                        backgroundColor: Colors.white,
                        errorCorrectionLevel: QrErrorCorrectLevel.M,
                        eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: Colors.black,
                        ),
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: Colors.black,
                        ),
                        embeddedImage: null, // Could add app logo here
                        embeddedImageStyle: null,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Identity text
                    Text(
                      'Your Six7 Identity',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SelectableText(
                        _formatIdentity(identity),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    // Show ALL reachable addresses prominently
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Color.fromRGBO(
                          theme.colorScheme.primaryContainer.r.toInt(),
                          theme.colorScheme.primaryContainer.g.toInt(),
                          theme.colorScheme.primaryContainer.b.toInt(),
                          0.3,
                        ),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Color.fromRGBO(
                            theme.colorScheme.primary.r.toInt(),
                            theme.colorScheme.primary.g.toInt(),
                            theme.colorScheme.primary.b.toInt(),
                            0.3,
                          ),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'All Addresses (${validAddrs.length})',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              GestureDetector(
                                onTap: _refreshAddresses,
                                child: Icon(
                                  Icons.refresh,
                                  size: 18,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (validAddrs.isNotEmpty)
                            ...validAddrs.map((addr) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                children: [
                                  Icon(
                                    addr.contains('192.168.') || addr.contains('10.') || addr.contains('172.')
                                        ? Icons.wifi  // LAN
                                        : Icons.public,  // External
                                    size: 14,
                                    color: theme.colorScheme.primary,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: SelectableText(
                                      addr,
                                      style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 12,
                                        color: theme.colorScheme.onSurface,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ))
                          else
                            Row(
                              children: [
                                Icon(
                                  Icons.warning_amber,
                                  size: 14,
                                  color: Colors.orange.shade700,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'No routable address found - tap refresh',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.orange.shade700,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _copyToClipboard(context, identity),
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy ID'),
                ),
                const SizedBox(width: 16),
                FilledButton.icon(
                  onPressed: () => _shareIdentity(context, qrData),
                  icon: const Icon(Icons.share),
                  label: const Text('Share'),
                ),
              ],
            ),
          ],
        );
    }
  }

  Widget _buildInstructions(BuildContext context, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Let others scan this QR code to add you as a contact. '
              'Your identity never leaves your device.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  String _formatIdentity(String identity) {
    // Format as 4-character groups for readability
    // SECURITY: Display full identity for verification
    final buffer = StringBuffer();
    for (var i = 0; i < identity.length; i += 8) {
      if (i > 0) buffer.write(' ');
      final end = (i + 8 > identity.length) ? identity.length : i + 8;
      buffer.write(identity.substring(i, end));
      if (i + 8 < identity.length && (i + 8) % 32 == 0) {
        buffer.write('\n');
      }
    }
    return buffer.toString();
  }

  Future<void> _copyToClipboard(BuildContext context, String identity) async {
    await Clipboard.setData(ClipboardData(text: identity));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Identity copied to clipboard')),
      );
    }
  }

  Future<void> _shareIdentity(BuildContext context, String qrData) async {
    // Use native share sheet
    final result = await Share.share(
      qrData,
      subject: 'Add me on Six7',
    );

    // Show feedback based on share result
    if (context.mounted) {
      if (result.status == ShareResultStatus.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Shared successfully')),
        );
      } else if (result.status == ShareResultStatus.dismissed) {
        // User cancelled - no message needed
      }
    }
  }
}
