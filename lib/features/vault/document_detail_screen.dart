import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/database/database_service.dart';
import '../../core/theme/app_theme.dart';
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

  @override
  Widget build(BuildContext context) {
    final doc = widget.document;

    return Scaffold(
      appBar: AppBar(
        title: Text(doc.title),
        actions: [
          IconButton(
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
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 1. Verification & Document Header Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.darkCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.darkSurface),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.verified, size: 14, color: AppTheme.primaryColor),
                                const SizedBox(width: 4),
                                Text(
                                  doc.isVerified ? 'VERIFIED DATA' : 'UNVERIFIED',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.primaryColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          Text(
                            doc.fileType.toUpperCase(),
                            style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        doc.title,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      if (doc.idNumber != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'ID: ${doc.idNumber}',
                          style: const TextStyle(fontSize: 14, color: AppTheme.primaryColor, fontWeight: FontWeight.w600),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        'File: ${doc.filePath}',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // 2. Expiry / Renewal Card (if applicable)
                if (doc.expiryDate != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: (doc.isExpired ? AppTheme.dangerColor : AppTheme.warningColor).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: doc.isExpired ? AppTheme.dangerColor : AppTheme.warningColor,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          doc.isExpired ? Icons.warning_amber : Icons.alarm_on,
                          color: doc.isExpired ? AppTheme.dangerColor : AppTheme.warningColor,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                doc.isExpired ? 'DOCUMENT EXPIRED' : 'RENEWAL RADAR ACTIVE',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: doc.isExpired ? AppTheme.dangerColor : AppTheme.warningColor,
                                ),
                              ),
                              Text(
                                doc.isExpired
                                    ? 'Expired on ${_formatDate(doc.expiryDate!)}'
                                    : 'Expires on ${_formatDate(doc.expiryDate!)} (${doc.daysUntilExpiry} days remaining)',
                                style: const TextStyle(color: Colors.white, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                // 3. Extracted Fields with 1-Tap Copy
                const Text(
                  'Extracted Fields (1-Tap Copy)',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.grey),
                ),
                const SizedBox(height: 8),

                if (_fields.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text('No structured fields extracted.', style: TextStyle(color: Colors.grey)),
                  )
                else
                  ..._fields.map((field) {
                    final isCopied = _copiedFieldId == field.id;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppTheme.darkCard,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isCopied ? AppTheme.primaryColor : AppTheme.darkSurface,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  field.fieldName,
                                  style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 2),
                                SelectableText(
                                  field.fieldValue,
                                  style: const TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              isCopied ? Icons.check : Icons.copy,
                              color: isCopied ? AppTheme.primaryColor : Colors.grey,
                              size: 18,
                            ),
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
