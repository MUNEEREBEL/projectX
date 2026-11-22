import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/database/database_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/document_model.dart';
import '../../models/person.dart';

class AssistiveBallDialog extends StatefulWidget {
  const AssistiveBallDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (context) => const AssistiveBallDialog(),
    );
  }

  @override
  State<AssistiveBallDialog> createState() => _AssistiveBallDialogState();
}

class _AssistiveBallDialogState extends State<AssistiveBallDialog> {
  final TextEditingController _searchController = TextEditingController();
  List<Person> _persons = [];
  List<DocumentModel> _documents = [];
  List<Map<String, dynamic>> _searchResults = [];
  String? _selectedPersonId;
  String? _copiedFieldId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final db = DatabaseService.instance;
    final persons = await db.getAllPersons();
    final docs = await db.getAllDocuments();
    final results = await db.searchFields(_searchController.text.trim(), personId: _selectedPersonId);

    if (mounted) {
      setState(() {
        _persons = persons;
        _documents = docs;
        _searchResults = results;
        _isLoading = false;
      });
    }
  }

  void _copyToClipboard(String id, String value) {
    Clipboard.setData(ClipboardData(text: value));
    HapticFeedback.lightImpact();
    setState(() => _copiedFieldId = id);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copiedFieldId = null);
    });
  }

  void _shareDocumentFile(DocumentModel doc) async {
    final file = File(doc.filePath);
    if (await file.exists()) {
      await Share.shareXFiles(
        [XFile(doc.filePath)],
        text: 'Document: ${doc.title}',
      );
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Original file not found: ${doc.fileName}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.darkCard,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppTheme.darkBorder, width: 1.2),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 600),
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Dialog Header
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.bolt, color: AppTheme.primaryColor, size: 18),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Assistive Form Copilot',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                      ),
                      Text(
                        '1-Tap Copy & Quick File Upload',
                        style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18, color: AppTheme.textSecondary),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // Family Member Selector
            if (_persons.isNotEmpty)
              SizedBox(
                height: 32,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    ChoiceChip(
                      label: const Text('All'),
                      selected: _selectedPersonId == null,
                      onSelected: (_) {
                        setState(() => _selectedPersonId = null);
                        _loadData();
                      },
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    const SizedBox(width: 6),
                    ..._persons.map((p) {
                      final isSelected = _selectedPersonId == p.id;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(p.name),
                          selected: isSelected,
                          onSelected: (_) {
                            setState(() => _selectedPersonId = isSelected ? null : p.id);
                            _loadData();
                          },
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                      );
                    }),
                  ],
                ),
              ),

            const SizedBox(height: 12),

            // Search Bar
            TextField(
              controller: _searchController,
              onChanged: (_) => _loadData(),
              style: const TextStyle(fontSize: 13, color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search field (e.g. pan, dl, ifsc, address)...',
                prefixIcon: const Icon(Icons.search, size: 18, color: AppTheme.textMuted),
                contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16, color: AppTheme.textMuted),
                        onPressed: () {
                          _searchController.clear();
                          _loadData();
                        },
                      )
                    : null,
              ),
            ),

            const SizedBox(height: 12),

            // File Upload Section (When Chrome or a form asks to upload files)
            const Text(
              'FAST FILE UPLOAD',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.textMuted, letterSpacing: 0.5),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 36,
              child: _documents.isEmpty
                  ? const Text('No documents in vault', style: TextStyle(color: AppTheme.textMuted, fontSize: 11))
                  : ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _documents.length,
                      itemBuilder: (context, index) {
                        final doc = _documents[index];
                        return Container(
                          margin: const EdgeInsets.only(right: 8),
                          child: ActionChip(
                            avatar: Icon(
                              doc.fileType == 'pdf' ? Icons.picture_as_pdf : Icons.image,
                              size: 14,
                              color: AppTheme.primaryColor,
                            ),
                            label: Text(
                              doc.title,
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                            ),
                            tooltip: 'Share/Pass file to upload dialog',
                            onPressed: () => _shareDocumentFile(doc),
                            backgroundColor: AppTheme.darkBg,
                            side: const BorderSide(color: AppTheme.darkBorder),
                          ),
                        );
                      },
                    ),
            ),

            const Divider(color: AppTheme.darkBorder, height: 20),

            // Field List
            const Text(
              'VERIFIED FORM VALUES',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.textMuted, letterSpacing: 0.5),
            ),
            const SizedBox(height: 6),

            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryColor))
                  : _searchResults.isEmpty
                      ? Center(
                          child: Text(
                            _documents.isEmpty
                                ? 'No documents in vault yet. Sync your folder first.'
                                : 'No matching fields found.',
                            style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                          ),
                        )
                      : ListView.separated(
                          itemCount: _searchResults.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 6),
                          itemBuilder: (context, index) {
                            final item = _searchResults[index];
                            final id = item['id'] as String;
                            final fieldName = item['field_name'] as String;
                            final fieldValue = item['field_value'] as String;
                            final personName = item['person_name'] as String;
                            final isCopied = _copiedFieldId == id;

                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: AppTheme.darkBg,
                                borderRadius: BorderRadius.circular(8),
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
                                          '$fieldName ($personName)',
                                          style: const TextStyle(fontSize: 10, color: AppTheme.textMuted, fontWeight: FontWeight.w500),
                                        ),
                                        const SizedBox(height: 2),
                                        SelectableText(
                                          fieldValue,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: AppTheme.textPrimary,
                                            fontFamily: 'monospace',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  InkWell(
                                    onTap: () => _copyToClipboard(id, fieldValue),
                                    borderRadius: BorderRadius.circular(6),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: isCopied
                                            ? AppTheme.successColor.withValues(alpha: 0.2)
                                            : AppTheme.darkCard,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: isCopied ? AppTheme.successColor : AppTheme.darkBorder,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            isCopied ? Icons.check : Icons.copy,
                                            size: 13,
                                            color: isCopied ? AppTheme.successColor : AppTheme.textSecondary,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            isCopied ? 'Copied' : 'Copy',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: isCopied ? AppTheme.successColor : AppTheme.textPrimary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
