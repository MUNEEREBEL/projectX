import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/database/database_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/glass_card.dart';
import '../../core/utils/indian_doc_validator.dart';
import '../../models/document_field.dart';
import '../../models/document_model.dart';

class DocumentDetailScreen extends StatefulWidget {
  final DocumentModel document;

  const DocumentDetailScreen({super.key, required this.document});

  @override
  State<DocumentDetailScreen> createState() => _DocumentDetailScreenState();
}

class _DocumentDetailScreenState extends State<DocumentDetailScreen> {
  List<DocumentField> _fields = [];
  bool _isLoading = true;
  String? _copiedFieldId;
  bool _maskAadhaar = true;

  @override
  void initState() {
    super.initState();
    _loadFields();
  }

  Future<void> _loadFields() async {
    final fields = await DatabaseService.instance.getFieldsForDocument(widget.document.id);
    if (mounted) {
      setState(() {
        _fields = fields;
        _isLoading = false;
      });
    }
  }

  void _copyValue(String id, String value) {
    Clipboard.setData(ClipboardData(text: value));
    HapticFeedback.lightImpact();
    setState(() => _copiedFieldId = id);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copiedFieldId = null);
    });
  }

  void _shareDocumentFile() async {
    final file = File(widget.document.filePath);
    if (await file.exists()) {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(widget.document.filePath)],
          text: 'Document: ${widget.document.title}',
        ),
      );
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Original file not found: ${widget.document.fileName}')),
        );
      }
    }
  }

  String _formatDate(DateTime date) {
    return DateFormat('dd MMM yyyy').format(date);
  }

  void _openFullScreenImage(BuildContext context, File file, String title) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black.withValues(alpha: 0.95),
        insetPadding: const EdgeInsets.all(10),
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 6.0,
                child: Image.file(file),
              ),
            ),
            Positioned(
              top: 10,
              left: 14,
              right: 50,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
            Positioned(
              top: 6,
              right: 6,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 24),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentPreview(DocumentModel doc) {
    final ext = doc.fileType.toLowerCase();
    final isImage = ['jpg', 'jpeg', 'png', 'webp', 'bmp'].contains(ext) ||
        doc.filePath.toLowerCase().endsWith('.jpg') ||
        doc.filePath.toLowerCase().endsWith('.jpeg') ||
        doc.filePath.toLowerCase().endsWith('.png') ||
        doc.filePath.toLowerCase().endsWith('.webp');
    final file = File(doc.filePath);
    final fileExists = file.existsSync();

    return GlassCard(
      padding: const EdgeInsets.all(14),
      borderRadius: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.preview_outlined, size: 16, color: AppTheme.accentColor),
              const SizedBox(width: 8),
              const Text(
                'DOCUMENT VIEWER',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.textMuted, letterSpacing: 0.8),
              ),
              const Spacer(),
              if (fileExists)
                Text(
                  '${(file.lengthSync() / 1024).toStringAsFixed(1)} KB',
                  style: const TextStyle(fontSize: 10, color: AppTheme.textMuted, fontFamily: 'monospace'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (!fileExists)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.dangerColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.dangerColor.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.broken_image_outlined, color: AppTheme.dangerColor, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Original file not found at path.\n${doc.filePath}',
                      style: const TextStyle(fontSize: 11, color: AppTheme.dangerColor),
                    ),
                  ),
                ],
              ),
            )
          else if (isImage) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                height: 240,
                width: double.infinity,
                color: Colors.black.withValues(alpha: 0.03),
                child: Stack(
                  children: [
                    Center(
                      child: InteractiveViewer(
                        minScale: 0.8,
                        maxScale: 4.0,
                        child: Image.file(
                          file,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Center(
                            child: Icon(Icons.broken_image, color: AppTheme.textMuted, size: 40),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Material(
                        color: Colors.white.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => _openFullScreenImage(context, file, doc.title),
                          child: const Padding(
                            padding: EdgeInsets.all(6.0),
                            child: Icon(Icons.fullscreen, size: 20, color: AppTheme.primaryColor),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Center(
              child: Text(
                'Pinch to zoom preview • Tap full screen for high-res view',
                style: TextStyle(fontSize: 10, color: AppTheme.textMuted),
              ),
            ),
          ] else ...[
            // PDF or other document
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.picture_as_pdf, color: AppTheme.accentColor, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          doc.fileName,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppTheme.textPrimary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'PDF Document (${doc.fileType.toUpperCase()})',
                          style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed: _shareDocumentFile,
                    icon: const Icon(Icons.open_in_new, size: 14),
                    label: const Text('Open', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final doc = widget.document;
    final isAadhaar = doc.docType.toUpperCase() == 'AADHAAR';

    return GlassBackgroundWrapper(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(doc.title),
          actions: [
            IconButton(
              tooltip: 'Share / Upload Original File',
              icon: const Icon(Icons.share_outlined, color: AppTheme.accentColor),
              onPressed: _shareDocumentFile,
            ),
            IconButton(
              tooltip: 'Delete Document',
              icon: const Icon(Icons.delete_outline, color: AppTheme.dangerColor),
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: Theme.of(context).cardColor,
                    title: const Text('Delete Document?', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
                    content: Text(
                      'Remove "${doc.title}" from your vault? The local original file will not be deleted.',
                      style: const TextStyle(color: AppTheme.textSecondary),
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: AppTheme.dangerColor),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Delete', style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                );

                if (confirm == true) {
                  await DatabaseService.instance.deleteDocument(doc.id);
                  if (context.mounted) Navigator.pop(context);
                }
              },
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accentColor))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // 1. Executive Frosted Document Overview Card
                  GlassCard(
                    padding: const EdgeInsets.all(20),
                    borderRadius: 20,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AppTheme.glassBorder),
                              ),
                              child: Text(
                                doc.category.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.accentColor,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (doc.isVerified)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppTheme.successColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: AppTheme.successColor.withValues(alpha: 0.3)),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.verified, size: 12, color: AppTheme.successColor),
                                    SizedBox(width: 4),
                                    Text(
                                      'VERIFIED',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.successColor,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryColor.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                doc.fileType.toUpperCase(),
                                style: const TextStyle(color: AppTheme.accentColor, fontSize: 10, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          doc.title,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppTheme.textPrimary, letterSpacing: -0.4),
                        ),
                        if (doc.idNumber != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              SelectableText(
                                isAadhaar && _maskAadhaar
                                    ? IndianDocValidator.maskAadhaar(doc.idNumber!)
                                    : doc.idNumber!,
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: AppTheme.textPrimary,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'monospace',
                                  letterSpacing: 0.5,
                                ),
                              ),
                              if (isAadhaar) ...[
                                const SizedBox(width: 8),
                                InkWell(
                                  onTap: () => setState(() => _maskAadhaar = !_maskAadhaar),
                                  child: Padding(
                                    padding: const EdgeInsets.all(4.0),
                                    child: Icon(
                                      _maskAadhaar ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                      size: 16,
                                      color: AppTheme.accentColor,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(Icons.file_present_outlined, size: 14, color: AppTheme.textMuted),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                doc.fileName,
                                style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // In-App Document Preview (Image viewer with pinch-to-zoom or PDF card)
                  _buildDocumentPreview(doc),

                  const SizedBox(height: 12),

                  // 2. Frosted Expiry & Lifetime Validity Banner
                  GlassCard(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    borderRadius: 16,
                    borderColor: doc.expiryDate != null
                        ? (doc.isExpired ? AppTheme.dangerColor.withValues(alpha: 0.4) : AppTheme.glassBorder)
                        : AppTheme.successColor.withValues(alpha: 0.3),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: doc.expiryDate != null
                                ? (doc.isExpired ? AppTheme.dangerColor.withValues(alpha: 0.15) : AppTheme.warningColor.withValues(alpha: 0.15))
                                : AppTheme.successColor.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            doc.expiryDate != null
                                ? (doc.isExpired ? Icons.warning_amber_rounded : Icons.event_available)
                                : Icons.all_inclusive,
                            color: doc.expiryDate != null
                                ? (doc.isExpired ? AppTheme.dangerColor : AppTheme.warningColor)
                                : AppTheme.successColor,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                doc.expiryDate != null
                                    ? (doc.isExpired ? 'DOCUMENT EXPIRED' : 'VALID UNTIL')
                                    : 'DOCUMENT VALIDITY',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 10,
                                  color: doc.expiryDate != null
                                      ? (doc.isExpired ? AppTheme.dangerColor : AppTheme.textMuted)
                                      : AppTheme.textMuted,
                                  letterSpacing: 0.6,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                doc.expiryDate != null
                                    ? (doc.isExpired
                                        ? '${_formatDate(doc.expiryDate!)} (Expired ${doc.daysUntilExpiry!.abs()} days ago)'
                                        : '${_formatDate(doc.expiryDate!)} (${doc.daysUntilExpiry} days remaining)')
                                    : 'Lifetime Validity (No Expiry)',
                                style: TextStyle(
                                  color: doc.expiryDate != null
                                      ? (doc.isExpired ? AppTheme.dangerColor : AppTheme.textPrimary)
                                      : AppTheme.successColor,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 22),

                  // 3. Extracted Fields List
                  Row(
                    children: [
                      const Text(
                        'VERIFIED FIELDS',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textMuted, letterSpacing: 0.8),
                      ),
                      const Spacer(),
                      InkWell(
                        onTap: _shareDocumentFile,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.3)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.upload_file, size: 12, color: AppTheme.accentColor),
                              SizedBox(width: 4),
                              Text('Send File to Upload', style: TextStyle(fontSize: 11, color: AppTheme.accentColor, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  if (_fields.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text('No structured fields extracted.', style: TextStyle(color: AppTheme.textMuted)),
                    )
                  else
                    ..._fields.map((field) {
                      final isCopied = _copiedFieldId == field.id;
                      return GlassCard(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        borderRadius: 14,
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    field.fieldName.toUpperCase(),
                                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.textMuted, letterSpacing: 0.5),
                                  ),
                                  const SizedBox(height: 3),
                                  SelectableText(
                                    field.fieldValue,
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                isCopied ? Icons.check : Icons.copy_rounded,
                                size: 18,
                                color: isCopied ? AppTheme.successColor : AppTheme.accentColor,
                              ),
                              tooltip: 'Copy value',
                              onPressed: () => _copyValue(field.id, field.fieldValue),
                            ),
                          ],
                        ),
                      );
                    }),

                  if (doc.rawText != null && doc.rawText!.trim().isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Center(
                      child: TextButton.icon(
                        icon: const Icon(Icons.code, size: 16, color: AppTheme.accentColor),
                        label: const Text('View Raw AI Vision JSON', style: TextStyle(color: AppTheme.accentColor, fontSize: 12, fontWeight: FontWeight.w600)),
                        onPressed: () {
                          showModalBottomSheet(
                            context: context,
                            backgroundColor: Theme.of(context).cardColor,
                            isScrollControlled: true,
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                            ),
                            builder: (ctx) {
                              return DraggableScrollableSheet(
                                initialChildSize: 0.6,
                                minChildSize: 0.3,
                                maxChildSize: 0.9,
                                expand: false,
                                builder: (_, scrollController) {
                                  return Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            const Icon(Icons.data_object, color: AppTheme.accentColor, size: 18),
                                            const SizedBox(width: 8),
                                            const Text('Raw Stored AI Response (SQLite)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.textPrimary)),
                                            const Spacer(),
                                            IconButton(
                                              icon: const Icon(Icons.copy, size: 18, color: AppTheme.accentColor),
                                              tooltip: 'Copy JSON',
                                              onPressed: () => _copyValue('raw_json', doc.rawText!),
                                            ),
                                          ],
                                        ),
                                        Divider(color: AppTheme.glassBorder),
                                        Expanded(
                                          child: SingleChildScrollView(
                                            controller: scrollController,
                                            child: SelectableText(
                                              doc.rawText!,
                                              style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: AppTheme.textSecondary, height: 1.4),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
