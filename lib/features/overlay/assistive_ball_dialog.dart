import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/database/database_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/glass_card.dart';
import '../../models/document_model.dart';
import '../../models/person.dart';

class AssistiveBallDialog extends StatefulWidget {
  const AssistiveBallDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.65),
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
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(doc.filePath)],
          text: 'Document: ${doc.title}',
        ),
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
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 440, maxHeight: 620),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF0F1422).withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Dialog Header
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppTheme.primaryColor, AppTheme.accentColor],
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.accentColor.withValues(alpha: 0.35),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.bolt, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Assistive Form Copilot',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textPrimary, letterSpacing: -0.3),
                          ),
                          Text(
                            '1-Tap Form Filling & Document Upload',
                            style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20, color: AppTheme.textMuted),
                      onPressed: () => Navigator.pop(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Family Member Selector
                if (_persons.isNotEmpty)
                  SizedBox(
                    height: 34,
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
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                        const SizedBox(width: 8),
                        ..._persons.map((p) {
                          final isSelected = _selectedPersonId == p.id;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(p.name),
                              selected: isSelected,
                              onSelected: (_) {
                                setState(() => _selectedPersonId = isSelected ? null : p.id);
                                _loadData();
                              },
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),

                const SizedBox(height: 14),

                // Search Bar
                GlassCard(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  borderRadius: 12,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (_) => _loadData(),
                    style: const TextStyle(fontSize: 13, color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Search field (e.g. pan, dl, ifsc, address)...',
                      hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                      prefixIcon: const Icon(Icons.search, size: 18, color: AppTheme.accentColor),
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
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
                ),

                const SizedBox(height: 14),

                // File Upload Section (When Chrome or a form asks to upload files)
                const Text(
                  'FAST FILE UPLOAD',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.textMuted, letterSpacing: 0.8),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 38,
                  child: _documents.isEmpty
                      ? const Text('No documents in vault', style: TextStyle(color: AppTheme.textMuted, fontSize: 11))
                      : ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _documents.length,
                          itemBuilder: (context, index) {
                            final doc = _documents[index];
                            return Container(
                              margin: const EdgeInsets.only(right: 8),
                              child: InkWell(
                                onTap: () => _shareDocumentFile(doc),
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: AppTheme.glassBorderHighlight),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        doc.fileType == 'pdf' ? Icons.picture_as_pdf : Icons.image,
                                        size: 14,
                                        color: AppTheme.accentColor,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        doc.title,
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),

                const Divider(color: AppTheme.darkBorder, height: 24),

                // Field List
                const Text(
                  'VERIFIED FORM VALUES (TAP TO COPY)',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.textMuted, letterSpacing: 0.8),
                ),
                const SizedBox(height: 8),

                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accentColor))
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

                                return InkWell(
                                  onTap: () => _copyToClipboard(id, fieldValue),
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: isCopied
                                          ? AppTheme.successColor.withValues(alpha: 0.15)
                                          : Colors.white.withValues(alpha: 0.05),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: isCopied
                                            ? AppTheme.successColor.withValues(alpha: 0.5)
                                            : AppTheme.glassBorder,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Text(
                                                    fieldName.toUpperCase(),
                                                    style: const TextStyle(
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.w700,
                                                      color: AppTheme.textMuted,
                                                      letterSpacing: 0.5,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                    decoration: BoxDecoration(
                                                      color: Colors.white.withValues(alpha: 0.08),
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: Text(
                                                      personName,
                                                      style: const TextStyle(fontSize: 9, color: AppTheme.accentColor, fontWeight: FontWeight.w600),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                fieldValue,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                  color: AppTheme.textPrimary,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: isCopied
                                                ? AppTheme.successColor.withValues(alpha: 0.2)
                                                : Colors.white.withValues(alpha: 0.06),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            isCopied ? Icons.check : Icons.copy_rounded,
                                            size: 14,
                                            color: isCopied ? AppTheme.successColor : AppTheme.accentColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
