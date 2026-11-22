import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/database/database_service.dart';
import '../../core/theme/app_theme.dart';
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
      await Share.shareXFiles(
        [XFile(widget.document.filePath)],
        text: 'Document: ${widget.document.title}',
      );
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Original file not found: ${widget.document.fileName}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final doc = widget.document;
    final isAadhaar = doc.docType.toUpperCase() == 'AADHAAR';

    return Scaffold(
      appBar: AppBar(
        title: Text(doc.title),
        actions: [
          // Quick File Share / Upload
          IconButton(
            tooltip: 'Share / Upload Original File',
            icon: const Icon(Icons.share_outlined),
            onPressed: _shareDocumentFile,
          ),
          IconButton(
            tooltip: 'Delete Document',
            icon: const Icon(Icons.delete_outline, color: AppTheme.dangerColor),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: AppTheme.darkCard,
                  title: const Text('Delete Document?'),
                  content: Text('Remove "${doc.title}" from your vault? The local original file will not be deleted.'),
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
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryColor))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 1. Executive Document Overview Card
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppTheme.darkCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.darkBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppTheme.darkBorder,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              doc.category.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textSecondary,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (doc.isVerified)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppTheme.successColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.check, size: 12, color: AppTheme.successColor),
                                  SizedBox(width: 4),
                                  Text(
                                    'VERIFIED',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.successColor,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const Spacer(),
                          Text(
                            doc.fileType.toUpperCase(),
                            style: const TextStyle(color: AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        doc.title,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                      ),
                      if (doc.idNumber != null) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            SelectableText(
                              isAadhaar && _maskAadhaar
                                  ? IndianDocValidator.maskAadhaar(doc.idNumber!)
                                  : doc.idNumber!,
                              style: const TextStyle(
                                fontSize: 15,
                                color: AppTheme.textPrimary,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'monospace',
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
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                      const SizedBox(height: 10),
                      Text(
                        'File: ${doc.filePath}',
                        style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // 2. Expiry Status Badge (Handled properly for both Expiry & No Expiry)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.darkCard,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: doc.expiryDate != null
                          ? (doc.isExpired ? AppTheme.dangerColor.withValues(alpha: 0.5) : AppTheme.darkBorder)
                          : AppTheme.darkBorder,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        doc.expiryDate != null
                            ? (doc.isExpired ? Icons.warning_amber : Icons.event_available)
                            : Icons.all_inclusive,
                        color: doc.expiryDate != null
                            ? (doc.isExpired ? AppTheme.dangerColor : AppTheme.warningColor)
                            : AppTheme.textSecondary,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              doc.expiryDate != null
                                  ? (doc.isExpired ? 'DOCUMENT EXPIRED' : 'VALID UNTIL')
                                  : 'DOCUMENT VALIDITY',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 10,
                                color: doc.expiryDate != null
                                    ? (doc.isExpired ? AppTheme.dangerColor : AppTheme.textMuted)
                                    : AppTheme.textMuted,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              doc.expiryDate != null
                                  ? '${_formatDate(doc.expiryDate!)} (${doc.daysUntilExpiry} days remaining)'
                                  : 'No Expiry Date (Lifetime Validity)',
                              style: TextStyle(
                                color: doc.expiryDate != null
                                    ? (doc.isExpired ? AppTheme.dangerColor : AppTheme.textPrimary)
                                    : AppTheme.textSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // 3. Extracted Fields List
                Row(
                  children: [
                    const Text(
                      'VERIFIED FIELDS',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.textMuted, letterSpacing: 0.6),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _shareDocumentFile,
                      icon: const Icon(Icons.upload_file, size: 14),
                      label: const Text('Send File to Upload', style: TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                if (_fields.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text('No structured fields extracted.', style: TextStyle(color: AppTheme.textMuted)),
                  )
                else
                  ..._fields.map((field) {
                    final isCopied = _copiedFieldId == field.id;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppTheme.darkCard,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isCopied ? AppTheme.primaryColor : AppTheme.darkBorder,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  field.fieldName.toUpperCase(),
                                  style: const TextStyle(fontSize: 10, color: AppTheme.textMuted, fontWeight: FontWeight.w600, letterSpacing: 0.4),
                                ),
                                const SizedBox(height: 3),
                                SelectableText(
                                  field.fieldValue,
                                  style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              isCopied ? Icons.check : Icons.copy,
                              color: isCopied ? AppTheme.successColor : AppTheme.textSecondary,
                              size: 16,
                            ),
                            tooltip: 'Copy value',
                            onPressed: () => _copyValue(field.id, field.fieldValue),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }
}
