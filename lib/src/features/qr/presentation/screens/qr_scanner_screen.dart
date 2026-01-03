import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:six7_chat/src/features/contacts/domain/providers/contacts_provider.dart';
import 'package:six7_chat/src/features/messaging/domain/providers/korium_node_provider.dart';

/// QR Scanner screen for scanning peer identities.
///
/// Supports two QR code formats:
/// 1. Raw identity: 64 hex characters (e.g., "abc123...")
/// 2. six7:// URI: six7://identity?name=DisplayName
class QrScannerScreen extends ConsumerStatefulWidget {
  const QrScannerScreen({super.key});

  @override
  ConsumerState<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends ConsumerState<QrScannerScreen>
    with WidgetsBindingObserver {
  late final MobileScannerController _controller;

  /// Tracks if we've already processed a code to prevent duplicate handling.
  bool _isProcessing = false;

  /// Pattern for validating 64-character hex identity.
  static final _identityPattern = RegExp(r'^[0-9a-fA-F]{64}$');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Handle app lifecycle for camera resource management.
    // SECURITY: Ensure camera is released when app is backgrounded.
    if (!_controller.value.isInitialized) return;

    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(_controller.start());
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        unawaited(_controller.stop());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final myIdentity = ref.watch(koriumNodeStateProvider);
    String? currentIdentity;
    if (myIdentity is KoriumNodeConnected) {
      currentIdentity = myIdentity.identity;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan QR Code'),
        actions: [
          IconButton(
            icon: ValueListenableBuilder(
              valueListenable: _controller,
              builder: (context, state, child) {
                return Icon(
                  state.torchState == TorchState.on
                      ? Icons.flash_on
                      : Icons.flash_off,
                );
              },
            ),
            onPressed: () => _controller.toggleTorch(),
            tooltip: 'Toggle flash',
          ),
          IconButton(
            icon: const Icon(Icons.flip_camera_ios),
            onPressed: () => _controller.switchCamera(),
            tooltip: 'Switch camera',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: Stack(
              children: [
                MobileScanner(
                  controller: _controller,
                  onDetect: _onDetect,
                  errorBuilder: (context, error) {
                    return _buildErrorWidget(context, error);
                  },
                ),
                // Scanning overlay
                _buildScanOverlay(theme),
              ],
            ),
          ),
          // Instructions
          Expanded(
            flex: 1,
            child: Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Point your camera at a Six7 QR code',
                    style: theme.textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'The QR code should contain a peer identity',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.grey,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (currentIdentity != null) ...[
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: () => _showMyQrCode(context, currentIdentity!),
                      icon: const Icon(Icons.qr_code),
                      label: const Text('Show my QR code'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanOverlay(ThemeData theme) {
    return CustomPaint(
      painter: _ScanOverlayPainter(
        borderColor: theme.colorScheme.primary,
        backgroundColor: Colors.black.withValues(alpha: 0.5),
      ),
      child: const SizedBox.expand(),
    );
  }

  Widget _buildErrorWidget(BuildContext context, MobileScannerException error) {
    String message;
    IconData icon;

    switch (error.errorCode) {
      case MobileScannerErrorCode.permissionDenied:
        icon = Icons.no_photography;
        message = 'Camera permission denied.\n'
            'Please grant camera access in Settings.';
      case MobileScannerErrorCode.unsupported:
        icon = Icons.camera_alt;
        message = 'Camera not supported on this device.';
      default:
        icon = Icons.error_outline;
        message = 'Camera error: ${error.errorDetails?.message ?? 'Unknown'}';
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            if (error.errorCode == MobileScannerErrorCode.permissionDenied)
              ElevatedButton(
                onPressed: () => openAppSettings(),
                child: const Text('Open Settings'),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    // Prevent duplicate processing
    if (_isProcessing) return;

    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final rawValue = barcodes.first.rawValue;
    if (rawValue == null || rawValue.isEmpty) return;

    _isProcessing = true;

    try {
      final result = _parseQrCode(rawValue);
      if (result != null) {
        // Haptic feedback on successful scan
        await HapticFeedback.mediumImpact();
        
        // Stop scanning while we process
        await _controller.stop();

        if (mounted) {
          await _handleScannedIdentity(
            result.identity, 
            result.displayName,
            result.addrs,
          );
        }
      } else {
        // Invalid QR code format
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Invalid QR code format'),
              backgroundColor: Colors.red,
            ),
          );
        }
        // Resume scanning after a delay
        await Future<void>.delayed(const Duration(seconds: 2));
        _isProcessing = false;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      _isProcessing = false;
      await _controller.start();
    }
  }

  /// Parses a QR code value into an identity, optional display name, and optional address.
  ///
  /// Supported formats:
  /// - Raw hex identity: "abc123..." (64 chars)
  /// - six7:// URI: "six7://IDENTITY?addrs=IP1:PORT1,IP2:PORT2" (new multi-address)
  /// - six7:// URI: "six7://IP:PORT/IDENTITY" (legacy single address)
  ({String identity, String? displayName, List<String>? addrs})? _parseQrCode(String value) {
    final trimmed = value.trim();

    // Try six7:// URI format first
    if (trimmed.startsWith('six7://')) {
      return _parseSix7Uri(trimmed);
    }

    // Try raw identity format
    if (_identityPattern.hasMatch(trimmed)) {
      return (identity: trimmed.toLowerCase(), displayName: null, addrs: null);
    }

    return null;
  }

  ({String identity, String? displayName, List<String>? addrs})? _parseSix7Uri(String uriString) {
    try {
      final uri = Uri.parse(uriString);
      
      // NEW FORMAT: six7://IDENTITY?addrs=IP1:PORT1,IP2:PORT2
      // This format supports multiple addresses for LAN + external connectivity
      final addrsParam = uri.queryParameters['addrs'];
      if (addrsParam != null && addrsParam.isNotEmpty) {
        // Identity is the host part
        final identity = uri.host;
        if (!_identityPattern.hasMatch(identity)) {
          return null;
        }
        final addrs = addrsParam.split(',').where((a) => a.isNotEmpty).toList();
        final displayName = uri.queryParameters['name'];
        return (identity: identity.toLowerCase(), displayName: displayName, addrs: addrs);
      }
      
      // OLD FORMAT: six7://IP:PORT/IDENTITY
      // uri.host = IP, uri.port = PORT, uri.path = /IDENTITY
      final host = uri.host;
      final port = uri.port;
      final path = uri.path.replaceAll('/', '');
      
      // Check if we have the old format (IP:PORT/IDENTITY)
      if (host.isNotEmpty && port > 0 && path.isNotEmpty) {
        if (!_identityPattern.hasMatch(path)) {
          return null;
        }
        final addr = '$host:$port';
        final displayName = uri.queryParameters['name'];
        return (identity: path.toLowerCase(), displayName: displayName, addrs: [addr]);
      }
      
      // Fallback: Legacy format where host IS the identity (no port)
      // six7://IDENTITY or six7://IDENTITY?name=...
      String? identity = host.isNotEmpty ? host : null;
      if (identity == null || identity.isEmpty) {
        identity = path.isNotEmpty ? path : null;
      }

      if (identity == null || !_identityPattern.hasMatch(identity)) {
        return null;
      }

      final displayName = uri.queryParameters['name'];
      // No address in legacy format
      return (identity: identity.toLowerCase(), displayName: displayName, addrs: null);
    } catch (_) {
      return null;
    }
  }

  Future<void> _handleScannedIdentity(
    String identity,
    String? suggestedName,
    List<String>? peerAddrs,
  ) async {
    // Check if this is our own identity
    final nodeState = ref.read(koriumNodeStateProvider);
    if (nodeState is KoriumNodeConnected && 
        nodeState.identity.toLowerCase() == identity.toLowerCase()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("That's your own QR code!"),
            backgroundColor: Colors.orange,
          ),
        );
        await _controller.start();
        _isProcessing = false;
      }
      return;
    }

    // Bootstrap with ALL addresses at once - korium 0.3.2+ tries each address
    // and automatically fetches the peer's full signed Contact from DHT.
    if (peerAddrs != null && peerAddrs.isNotEmpty) {
      try {
        debugPrint('Bootstrapping to peer with ${peerAddrs.length} addresses: $peerAddrs');
        // Use notifier to ensure bootstrap state is properly tracked
        await ref.read(koriumNodeProvider.notifier).bootstrap(identity, peerAddrs);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Connected to peer (${peerAddrs.length} addresses)'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 1),
            ),
          );
        }
      } catch (e) {
        debugPrint('Bootstrap failed: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not connect: $e'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    }

    // Check if contact already exists
    final contacts = ref.read(contactsProvider).value ?? [];
    final existing = contacts.where(
      (c) => c.identity.toLowerCase() == identity.toLowerCase(),
    ).firstOrNull;

    if (existing != null) {
      // Contact exists - send contact request anyway to re-establish connection
      // This helps when peer was offline or changed addresses
      try {
        final nodeAsync = ref.read(koriumNodeProvider);
        await nodeAsync.whenData((node) async {
          final myName = node.identity.substring(0, 8);
          await ref.read(contactsProvider.notifier).sendContactRequest(
            identity: identity,
            myDisplayName: myName,
          );
          debugPrint('[QR] Sent contact request to existing contact');
        });
      } catch (e) {
        debugPrint('[QR] Failed to send contact request to existing: $e');
      }
      
      if (mounted) {
        final shouldOpenChat = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Contact Exists'),
            content: Text(
              '${existing.displayName} is already in your contacts.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Open Chat'),
              ),
            ],
          ),
        );

        if (shouldOpenChat == true && mounted) {
          context.go(
            '/chat/${existing.identity}?name=${Uri.encodeComponent(existing.displayName)}&autofocus=true',
          );
        } else {
          await _controller.start();
          _isProcessing = false;
        }
      }
      return;
    }

    // Show dialog to add contact
    if (mounted) {
      final result = await showDialog<({String name, bool startChat})>(
        context: context,
        barrierDismissible: false,
        builder: (context) => _AddScannedContactDialog(
          identity: identity,
          suggestedName: suggestedName,
        ),
      );

      if (result != null && mounted) {
        try {
          // Add contact locally
          await ref.read(contactsProvider.notifier).addContact(
            identity: identity,
            displayName: result.name,
          );
          
          // Send contact request to notify the peer
          final nodeAsync = ref.read(koriumNodeProvider);
          final myName = await nodeAsync.when(
            loading: () async => 'Unknown',
            error: (e, s) async => 'Unknown',
            data: (node) async {
              // Try to get our display name, fall back to truncated identity
              return node.identity.substring(0, 8);
            },
          );
          
          try {
            await ref.read(contactsProvider.notifier).sendContactRequest(
              identity: identity,
              myDisplayName: myName,
            );
          } catch (e) {
            // Contact request failed, but contact was added locally
            // ignore: avoid_print
            print('[QR] Contact request send failed: $e');
          }

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Added ${result.name} to contacts')),
            );

            if (result.startChat) {
              context.go(
                '/chat/$identity?name=${Uri.encodeComponent(result.name)}&autofocus=true',
              );
            } else {
              context.pop();
            }
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to add contact: $e'),
                backgroundColor: Colors.red,
              ),
            );
            await _controller.start();
            _isProcessing = false;
          }
        }
      } else {
        // User cancelled
        await _controller.start();
        _isProcessing = false;
      }
    }
  }

  void _showMyQrCode(BuildContext context, String identity) {
    context.push('/qr-display');
  }
}

/// Dialog for adding a scanned contact.
class _AddScannedContactDialog extends StatefulWidget {
  const _AddScannedContactDialog({
    required this.identity,
    this.suggestedName,
  });

  final String identity;
  final String? suggestedName;

  @override
  State<_AddScannedContactDialog> createState() =>
      _AddScannedContactDialogState();
}

class _AddScannedContactDialogState extends State<_AddScannedContactDialog> {
  late final TextEditingController _nameController;
  bool _startChat = true;
  String? _nameError;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.suggestedName ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Contact'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Identity:',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _truncateId(widget.identity),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: 'Display Name',
              hintText: 'Enter a name for this contact',
              border: const OutlineInputBorder(),
              errorText: _nameError,
            ),
            textCapitalization: TextCapitalization.words,
            autofocus: widget.suggestedName == null,
            onChanged: (_) {
              // Clear error when user starts typing
              if (_nameError != null) {
                setState(() => _nameError = null);
              }
            },
          ),
          const SizedBox(height: 16),
          CheckboxListTile(
            value: _startChat,
            onChanged: (value) => setState(() => _startChat = value ?? true),
            title: const Text('Start chat immediately'),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
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
            final name = _nameController.text.trim();
            if (name.isEmpty) {
              setState(() => _nameError = 'Please enter a display name');
              return;
            }
            Navigator.pop(context, (name: name, startChat: _startChat));
          },
          child: const Text('Add'),
        ),
      ],
    );
  }

  String _truncateId(String id) {
    if (id.length <= 16) return id;
    return '${id.substring(0, 8)}...${id.substring(id.length - 8)}';
  }
}

/// Custom painter for the scan overlay with cutout.
class _ScanOverlayPainter extends CustomPainter {
  _ScanOverlayPainter({
    required this.borderColor,
    required this.backgroundColor,
  });

  final Color borderColor;
  final Color backgroundColor;

  @override
  void paint(Canvas canvas, Size size) {
    final backgroundPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    // Calculate cutout size (80% of the smaller dimension)
    final cutoutSize = size.shortestSide * 0.7;
    final left = (size.width - cutoutSize) / 2;
    final top = (size.height - cutoutSize) / 2;
    final cutoutRect = Rect.fromLTWH(left, top, cutoutSize, cutoutSize);

    // Draw background with cutout
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(cutoutRect, const Radius.circular(16)))
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, backgroundPaint);

    // Draw border around cutout
    canvas.drawRRect(
      RRect.fromRectAndRadius(cutoutRect, const Radius.circular(16)),
      borderPaint,
    );

    // Draw corner accents
    const cornerLength = 30.0;
    final cornerPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;

    // Top-left corner
    canvas.drawLine(
      Offset(left, top + cornerLength),
      Offset(left, top),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(left, top),
      Offset(left + cornerLength, top),
      cornerPaint,
    );

    // Top-right corner
    canvas.drawLine(
      Offset(left + cutoutSize - cornerLength, top),
      Offset(left + cutoutSize, top),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(left + cutoutSize, top),
      Offset(left + cutoutSize, top + cornerLength),
      cornerPaint,
    );

    // Bottom-left corner
    canvas.drawLine(
      Offset(left, top + cutoutSize - cornerLength),
      Offset(left, top + cutoutSize),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(left, top + cutoutSize),
      Offset(left + cornerLength, top + cutoutSize),
      cornerPaint,
    );

    // Bottom-right corner
    canvas.drawLine(
      Offset(left + cutoutSize - cornerLength, top + cutoutSize),
      Offset(left + cutoutSize, top + cutoutSize),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(left + cutoutSize, top + cutoutSize - cornerLength),
      Offset(left + cutoutSize, top + cutoutSize),
      cornerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ScanOverlayPainter oldDelegate) {
    return borderColor != oldDelegate.borderColor ||
        backgroundColor != oldDelegate.backgroundColor;
  }
}

/// Opens platform settings. Called when camera permission is denied.
Future<void> openAppSettings() async {
  await ph.openAppSettings();
}
