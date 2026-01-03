import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:six7_chat/src/features/messaging/domain/models/chat_message.dart';
import 'package:six7_chat/src/features/messaging/domain/providers/korium_node_provider.dart';
import 'package:six7_chat/src/features/reporting/domain/models/abuse_report.dart';
import 'package:six7_chat/src/features/reporting/domain/services/abuse_report_service.dart';

/// Dialog for generating and sharing an abuse report.
class ReportMessageDialog extends ConsumerStatefulWidget {
  const ReportMessageDialog({
    super.key,
    required this.message,
    required this.senderDisplayName,
    this.groupId,
    this.groupName,
  });

  final ChatMessage message;
  final String senderDisplayName;
  final String? groupId;
  final String? groupName;

  /// Shows the report dialog.
  static Future<void> show(
    BuildContext context, {
    required ChatMessage message,
    required String senderDisplayName,
    String? groupId,
    String? groupName,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (context) => ReportMessageDialog(
        message: message,
        senderDisplayName: senderDisplayName,
        groupId: groupId,
        groupName: groupName,
      ),
    );
  }

  @override
  ConsumerState<ReportMessageDialog> createState() =>
      _ReportMessageDialogState();
}

class _ReportMessageDialogState extends ConsumerState<ReportMessageDialog> {
  final _statementController = TextEditingController();
  AbuseReport? _report;
  String? _error;
  bool _isGenerating = false;

  @override
  void dispose() {
    _statementController.dispose();
    super.dispose();
  }

  Future<void> _generateReport() async {
    setState(() {
      _isGenerating = true;
      _error = null;
    });

    try {
      final node = ref.read(koriumNodeProvider).value;
      if (node == null) {
        throw const ReportException('Not connected to network');
      }

      final reportService = ref.read(abuseReportServiceProvider);
      final report = reportService.generateReport(
        message: widget.message,
        senderDisplayName: widget.senderDisplayName,
        reporterIdentity: node.identity,
        groupId: widget.groupId,
        groupName: widget.groupName,
        statement: _statementController.text.isNotEmpty
            ? _statementController.text
            : null,
      );

      setState(() {
        _report = report;
        _isGenerating = false;
      });
    } on ReportException catch (e) {
      setState(() {
        _error = e.message;
        _isGenerating = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to generate report: $e';
        _isGenerating = false;
      });
    }
  }

  Future<void> _sendViaEmail() async {
    if (_report == null) return;

    final reportService = ref.read(abuseReportServiceProvider);
    await reportService.sendViaEmail(_report!);

    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Report ready to send'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _shareReport() async {
    if (_report == null) return;

    final reportService = ref.read(abuseReportServiceProvider);
    await reportService.shareReport(_report!);

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _copyToClipboard() async {
    if (_report == null) return;

    final reportService = ref.read(abuseReportServiceProvider);
    final json = reportService.exportToString(_report!);
    await Clipboard.setData(ClipboardData(text: json));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Report copied to clipboard'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Show report ready screen
    if (_report != null) {
      return _buildReportReadyDialog(theme);
    }

    // Show report generation screen
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.flag_outlined, color: theme.colorScheme.error),
          const SizedBox(width: 8),
          const Text('Report Message'),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info card
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'From: ${widget.senderDisplayName}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.message.text,
                    style: theme.textTheme.bodyMedium,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'This will generate a cryptographic proof that this message '
              'was sent by ${widget.senderDisplayName}. The proof can be '
              'verified by anyone.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            // Optional statement
            TextField(
              controller: _statementController,
              decoration: const InputDecoration(
                labelText: 'Add context (optional)',
                hintText: 'Describe why you are reporting this message...',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              maxLength: 500,
            ),
            // Error message
            if (_error != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: theme.colorScheme.onErrorContainer,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: theme.colorScheme.onErrorContainer,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isGenerating ? null : _generateReport,
          child: _isGenerating
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Generate Report'),
        ),
      ],
    );
  }

  Widget _buildReportReadyDialog(ThemeData theme) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.check_circle, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          const Text('Report Ready'),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Success message
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.verified,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Cryptographic proof generated successfully',
                      style: TextStyle(
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Report summary
            Text(
              'Report Summary',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            _buildSummaryRow('Sender', widget.senderDisplayName),
            _buildSummaryRow(
              'Time',
              _formatDateTime(widget.message.timestamp),
            ),
            if (widget.groupName != null)
              _buildSummaryRow('Group', widget.groupName!),
            const SizedBox(height: 16),
            Text(
              'The report contains proof that cannot be fabricated. '
              'Send it via email or share it to report the abuse.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _copyToClipboard,
          child: const Text('Copy'),
        ),
        OutlinedButton.icon(
          onPressed: _shareReport,
          icon: const Icon(Icons.share, size: 18),
          label: const Text('Share'),
        ),
        FilledButton.icon(
          onPressed: _sendViaEmail,
          icon: const Icon(Icons.email, size: 18),
          label: const Text('Email'),
        ),
      ],
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }
}
