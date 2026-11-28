import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/database/database_service.dart';
import '../../core/services/qa_assistant_service.dart';
import '../../models/document_field.dart';
import '../../models/document_model.dart';

class AssistiveBallDialog extends StatefulWidget {
  const AssistiveBallDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (context) => const AssistiveBallDialog(),
    );
  }

  @override
  State<AssistiveBallDialog> createState() => _AssistiveBallDialogState();
}

class _AssistiveBallDialogState extends State<AssistiveBallDialog> {
  int _activeTab = 0; // 0 = Vault Explorer, 1 = Copilot Chat

  final TextEditingController _vaultSearchController = TextEditingController();
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isChatLoading = false;

  final List<Map<String, dynamic>> _chatMessages = [
    {
      'text': 'Ask X anything about your cards, account numbers, or documents.',
      'isUser': false,
    },
  ];

  List<DocumentModel> _documents = [];
  Map<String, List<DocumentField>> _docFields = {};
  final Set<String> _expandedDocIds = {};
  bool _isLoadingData = true;

  @override
  void initState() {
    super.initState();
    _loadVaultData();
  }

  @override
  void dispose() {
    _vaultSearchController.dispose();
    _chatController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadVaultData() async {
    final db = DatabaseService.instance;
    await db.cleanupDuplicates();
    final docs = await db.getAllDocuments();
    final Map<String, List<DocumentField>> fieldsMap = {};

    for (final doc in docs) {
      final fields = await db.getFieldsForDocument(doc.id);
      fieldsMap[doc.id] = fields;
    }

    if (mounted) {
      setState(() {
        _documents = docs;
        _docFields = fieldsMap;
        // Expand first document by default
        if (docs.isNotEmpty) {
          _expandedDocIds.add(docs.first.id);
        }
        _isLoadingData = false;
      });
    }
  }

  void _copy(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied $label: "$text"'),
        duration: const Duration(seconds: 1),
        backgroundColor: const Color(0xFF0F172A),
      ),
    );
  }

  void _sendChatMessage() async {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;

    _chatController.clear();
    setState(() {
      _chatMessages.add({'text': text, 'isUser': true});
      _isChatLoading = true;
    });

    try {
      final response = await QAAssistantService.askQuestion(text);
      if (mounted) {
        setState(() {
          _chatMessages.add({
            'text': response.answer,
            'isUser': false,
            'copyable': response.copyableValues.isNotEmpty ? response.copyableValues.first : null,
            'copyLabel': 'Value',
          });
          _isChatLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _chatMessages.add({
            'text': 'Unable to retrieve answer: $e',
            'isUser': false,
          });
          _isChatLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.78,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.15),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            // Top Header: Title, Segment Tabs, Close
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 14, 10),
              child: _buildHeader(),
            ),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),

            // Body: Real Vault Explorer vs Copilot Chat
            Expanded(
              child: _activeTab == 0 ? _buildRealVaultView() : _buildChatView(),
            ),

            if (_activeTab == 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
                child: _buildBottomInputBar(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Title
        Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Text(
              'PROJECT ',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
                letterSpacing: 0.5,
              ),
            ),
            Text(
              'X',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Color(0xFF00B4D8),
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),

        // Tabs Toggle (Vault Explorer vs Copilot Chat)
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              _buildTabButton(title: 'Vault', index: 0),
              _buildTabButton(title: 'Copilot', index: 1),
            ],
          ),
        ),

        // Close Button
        InkWell(
          onTap: () => Navigator.pop(context),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(6),
            child: const Icon(Icons.close_rounded, size: 20, color: Color(0xFF64748B)),
          ),
        ),
      ],
    );
  }

  Widget _buildTabButton({required String title, required int index}) {
    final isSelected = _activeTab == index;
    return InkWell(
      onTap: () => setState(() => _activeTab = index),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: isSelected
              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4)]
              : null,
        ),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF64748B),
          ),
        ),
      ),
    );
  }

  // Real Vault View: Full list of documents with all extracted fields
  Widget _buildRealVaultView() {
    if (_isLoadingData) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    if (_documents.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.folder_open_rounded, size: 40, color: Color(0xFF94A3B8)),
            SizedBox(height: 8),
            Text('No documents indexed in vault yet', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0F172A))),
            SizedBox(height: 2),
            Text('Sync your folder from the main app to see cards here.', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
          ],
        ),
      );
    }

    final query = _vaultSearchController.text.trim().toLowerCase();
    final filtered = _documents.where((d) {
      if (query.isEmpty) return true;
      final matchTitle = d.title.toLowerCase().contains(query);
      final matchId = d.idNumber != null && d.idNumber!.toLowerCase().contains(query);
      final fields = _docFields[d.id] ?? [];
      final matchFields = fields.any((f) => f.fieldName.toLowerCase().contains(query) || f.fieldValue.toLowerCase().contains(query));
      return matchTitle || matchId || matchFields;
    }).toList();

    return Column(
      children: [
        // Search bar for real-time vault filtering
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                const Icon(Icons.search_rounded, size: 18, color: Color(0xFF94A3B8)),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _vaultSearchController,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(fontSize: 12.5, color: Color(0xFF0F172A)),
                    decoration: const InputDecoration(
                      hintText: 'Search cards, names, numbers, IFSC...',
                      hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
                if (_vaultSearchController.text.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _vaultSearchController.clear();
                      setState(() {});
                    },
                    child: const Icon(Icons.clear, size: 16, color: Color(0xFF94A3B8)),
                  ),
              ],
            ),
          ),
        ),

        // Attention Banner (Expiring or Expired documents)
        Builder(
          builder: (context) {
            final attentionDocs = _documents.where((d) => d.isExpired || (d.daysUntilExpiry ?? 999) <= 45).toList();
            if (attentionDocs.isEmpty) return const SizedBox.shrink();
            return Container(
              margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFDC2626)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${attentionDocs.length} Document${attentionDocs.length > 1 ? 's' : ''} Need Attention (Expired / Expiring)',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFB91C1C)),
                    ),
                  ),
                ],
              ),
            );
          },
        ),

        // Scrollable list of document cards
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            physics: const BouncingScrollPhysics(),
            itemCount: filtered.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final doc = filtered[index];
              final fields = _docFields[doc.id] ?? [];
              final isExpanded = _expandedDocIds.contains(doc.id) || query.isNotEmpty;

              // Find real holder name
              String? holderName;
              for (final f in fields) {
                if (f.fieldName.toLowerCase() == 'full name' &&
                    f.fieldValue.trim().isNotEmpty &&
                    f.fieldValue.toLowerCase() != 'unknown' &&
                    f.fieldValue.toLowerCase() != 'primary user' &&
                    f.fieldValue.toLowerCase() != 'primary cardholder') {
                  holderName = f.fieldValue.trim();
                  break;
                }
              }

              // Status badge
              String? statusBadge;
              Color statusBg = const Color(0xFFDCFCE7);
              Color statusFg = const Color(0xFF16A34A);
              if (doc.expiryDate != null) {
                final days = doc.expiryDate!.difference(DateTime.now()).inDays;
                if (days < 0) {
                  statusBadge = 'EXPIRED';
                  statusBg = const Color(0xFFFEE2E2);
                  statusFg = const Color(0xFFDC2626);
                } else if (days <= 45) {
                  statusBadge = 'Exp ${days}d';
                  statusBg = const Color(0xFFFEF3C7);
                  statusFg = const Color(0xFFD97706);
                }
              }

              return Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: statusBadge == 'EXPIRED' ? const Color(0xFFFECACA) : const Color(0xFFE2E8F0),
                    width: statusBadge == 'EXPIRED' ? 1.4 : 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0F172A).withValues(alpha: 0.02),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Card Header: Tap to expand
                    InkWell(
                      onTap: () {
                        setState(() {
                          if (_expandedDocIds.contains(doc.id)) {
                            _expandedDocIds.remove(doc.id);
                          } else {
                            _expandedDocIds.add(doc.id);
                          }
                        });
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.description_outlined, size: 20, color: Color(0xFF2563EB)),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          doc.title,
                                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (statusBadge != null) ...[
                                        const SizedBox(width: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                          decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(4)),
                                          child: Text(statusBadge, style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w700, color: statusFg)),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      if (holderName != null) ...[
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                          decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(4)),
                                          child: Text(holderName, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: Color(0xFF2563EB)), maxLines: 1, overflow: TextOverflow.ellipsis),
                                        ),
                                        const SizedBox(width: 4),
                                      ],
                                      Expanded(
                                        child: Text(
                                          doc.idNumber != null && doc.idNumber!.isNotEmpty
                                              ? doc.idNumber!
                                              : 'Category: ${doc.category}',
                                          style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            if (doc.idNumber != null && doc.idNumber!.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.copy_rounded, size: 16, color: Color(0xFF00B4D8)),
                                tooltip: 'Copy ID',
                                onPressed: () => _copy(doc.idNumber!, doc.title),
                              ),
                            Icon(
                              isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                              size: 20,
                              color: const Color(0xFF94A3B8),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Expanded Section: All Extracted Fields with 1-Tap Copy
                    if (isExpanded) ...[
                      const Divider(height: 1, color: Color(0xFFF1F5F9)),
                      Container(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                        decoration: const BoxDecoration(
                          color: Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.vertical(bottom: Radius.circular(14)),
                        ),
                        child: fields.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.all(8.0),
                                child: Text('No extracted fields available', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                              )
                            : Column(
                                children: fields.map((field) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 4),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          flex: 4,
                                          child: Text(
                                            field.fieldName,
                                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          flex: 5,
                                          child: Text(
                                            field.fieldValue,
                                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        InkWell(
                                          onTap: () => _copy(field.fieldValue, field.fieldName),
                                          borderRadius: BorderRadius.circular(6),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: const Color(0xFFE2E8F0)),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: const [
                                                Icon(Icons.copy_rounded, size: 11, color: Color(0xFF00B4D8)),
                                                SizedBox(width: 3),
                                                Text('Copy', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // Copilot Chat View
  Widget _buildChatView() {
    return ListView.builder(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      itemCount: _chatMessages.length,
      itemBuilder: (context, index) {
        final msg = _chatMessages[index];
        final isUser = msg['isUser'] as bool;
        final text = msg['text'] as String;
        final copyable = msg['copyable'] as String?;

        if (isUser) {
          return Align(
            alignment: Alignment.centerRight,
            child: Container(
              margin: const EdgeInsets.only(bottom: 10, left: 40),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                text,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: Colors.white),
              ),
            ),
          );
        }

        return Align(
          alignment: Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 10, right: 30),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF1E293B), height: 1.35),
                ),
                if (copyable != null) ...[
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () => _copy(copyable, 'Value'),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.copy_rounded, size: 12, color: Color(0xFF00B4D8)),
                          SizedBox(width: 4),
                          Text('Copy Value', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomInputBar() {
    return Container(
      height: 44,
      padding: const EdgeInsets.only(left: 16, right: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.1),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _chatController,
              onSubmitted: (_) => _sendChatMessage(),
              style: const TextStyle(fontSize: 12.5, color: Color(0xFF0F172A)),
              decoration: const InputDecoration(
                hintText: 'Ask Copilot...',
                hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          if (_isChatLoading)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0F172A)),
            )
          else
            InkWell(
              onTap: _sendChatMessage,
              borderRadius: BorderRadius.circular(14),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(
                  Icons.near_me_outlined,
                  size: 18,
                  color: Color(0xFF64748B),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
