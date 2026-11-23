import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/database/database_service.dart';
import '../../core/services/qa_assistant_service.dart';
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
  int _activeTab = 0; // 0 = Chat System, 1 = Vault Files

  final TextEditingController _chatController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isChatLoading = false;

  final List<Map<String, dynamic>> _chatMessages = [
    {
      'text': 'What is my father\'s PAN number?',
      'isUser': true,
    },
    {
      'text': 'Your father\'s PAN is ABCDE1234F.',
      'isUser': false,
      'copyable': 'ABCDE1234F',
      'copyLabel': 'Copy PAN',
    },
  ];

  // Quick Copy extracted fields from Vault
  String? _userPan;
  String? _userAadhaar;
  String? _userIfsc;
  String? _userAddress;

  List<DocumentModel> _documents = [];
  bool _isLoadingData = true;

  @override
  void initState() {
    super.initState();
    _loadVaultData();
  }

  Future<void> _loadVaultData() async {
    final db = DatabaseService.instance;
    final docs = await db.getAllDocuments();

    String? pan;
    String? aadhaar;
    String? ifsc;
    String? address;

    for (final doc in docs) {
      final fields = await db.getFieldsForDocument(doc.id);
      for (final f in fields) {
        final name = f.fieldName.toLowerCase();
        if (pan == null && (name.contains('pan') || doc.docType == 'PAN')) {
          pan = f.fieldValue;
        } else if (aadhaar == null && (name.contains('aadhaar') || doc.docType == 'AADHAAR')) {
          aadhaar = f.fieldValue;
        } else if (ifsc == null && name.contains('ifsc')) {
          ifsc = f.fieldValue;
        } else if (address == null && (name.contains('address') || name.contains('permanent'))) {
          address = f.fieldValue;
        }
      }
    }

    if (mounted) {
      setState(() {
        _documents = docs;
        _userPan = pan ?? 'ABCDE1234F';
        _userAadhaar = aadhaar ?? '9876 5432 4821';
        _userIfsc = ifsc ?? 'SBIN0001234';
        _userAddress = address ?? 'Green Oak Avenue, Bangalore';
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

    _scrollToBottom();

    try {
      final response = await QAAssistantService.askQuestion(text);
      if (mounted) {
        String? copyVal;
        String? copyLabel;

        if (response.copyableValues.isNotEmpty) {
          copyVal = response.copyableValues.first;
          copyLabel = 'Copy Value';
        }

        setState(() {
          _chatMessages.add({
            'text': response.answer,
            'isUser': false,
            'copyable': copyVal,
            'copyLabel': copyLabel,
          });
          _isChatLoading = false;
        });
        _scrollToBottom();
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
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.12),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. TOP HEADER: "Project X" + Pulse Waveform + Tab Toggles + Close
                _buildHeader(),
                const SizedBox(height: 12),

                // 2. QUICK-COPY PILLS ROW (PAN, Aadhaar, Bank IFSC, Address)
                _buildQuickCopyPills(),
                const SizedBox(height: 12),

                // 3. BODY (Chat System OR Vault Files View)
                Expanded(
                  child: _activeTab == 0 ? _buildChatSystem() : _buildVaultFilesView(),
                ),

                // 4. BOTTOM INPUT BAR (Only visible in Chat mode)
                if (_activeTab == 0) ...[
                  const SizedBox(height: 10),
                  _buildBottomInputBar(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 1. TOP HEADER
  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Left: Folded X Logo + "Project X" + Waveform Pulse
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSmallProjectXLogo(),
            const SizedBox(width: 6),
            const Text(
              'Project X',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.graphic_eq_rounded,
                size: 15,
                color: Color(0xFF00B4D8),
              ),
            ),
          ],
        ),

        // Middle: Tabs Toggle (Chat vs Vault)
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              _buildTabButton(title: 'Chat', index: 0),
              _buildTabButton(title: 'Vault', index: 1),
            ],
          ),
        ),

        // Close Button
        InkWell(
          onTap: () => Navigator.pop(context),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(4),
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF64748B),
          ),
        ),
      ),
    );
  }

  Widget _buildSmallProjectXLogo() {
    return SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(
        painter: _ProjectXSmallPainter(),
      ),
    );
  }

  // 2. QUICK-COPY PILLS ROW
  Widget _buildQuickCopyPills() {
    // Masked strings
    final panDisplay = _userPan != null && _userPan!.length >= 4
        ? 'PAN: ${_userPan!.substring(0, 2)}***${_userPan!.substring(_userPan!.length - 3)}'
        : 'PAN: AB***12P';

    final aadhaarDisplay = _userAadhaar != null && _userAadhaar!.length >= 4
        ? 'Aadhaar: •••• ${_userAadhaar!.replaceAll(' ', '').substring(_userAadhaar!.replaceAll(' ', '').length - 4)}'
        : 'Aadhaar: •••• 4821';

    final ifscDisplay = _userIfsc != null ? 'Bank IFSC: $_userIfsc' : 'Bank IFSC: SBIN0001234';

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildCopyPill(
                label: panDisplay,
                copyValue: _userPan ?? 'ABCDE1234F',
                itemLabel: 'PAN',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildCopyPill(
                label: aadhaarDisplay,
                copyValue: _userAadhaar ?? '9876 5432 4821',
                itemLabel: 'Aadhaar',
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: _buildCopyPill(
                label: ifscDisplay,
                copyValue: _userIfsc ?? 'SBIN0001234',
                itemLabel: 'IFSC',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: _buildCopyPill(
                label: 'Address',
                copyValue: _userAddress ?? 'Green Oak Avenue, Bangalore',
                itemLabel: 'Address',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCopyPill({required String label, required String copyValue, required String itemLabel}) {
    return InkWell(
      onTap: () => _copy(copyValue, itemLabel),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9).withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF334155),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.copy_rounded,
              size: 13,
              color: Color(0xFF64748B),
            ),
          ],
        ),
      ),
    );
  }

  // 3A. CHAT SYSTEM (Inside X)
  Widget _buildChatSystem() {
    return ListView.builder(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      itemCount: _chatMessages.length,
      itemBuilder: (context, index) {
        final msg = _chatMessages[index];
        final isUser = msg['isUser'] as bool;
        final text = msg['text'] as String;
        final copyable = msg['copyable'] as String?;
        final copyLabel = msg['copyLabel'] as String?;

        if (isUser) {
          return Align(
            alignment: Alignment.centerRight,
            child: Container(
              margin: const EdgeInsets.only(bottom: 10, left: 40),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.03),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF0F172A),
                ),
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
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.03),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF0F172A),
                    height: 1.35,
                  ),
                ),
                if (copyable != null) ...[
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () => _copy(copyable, copyLabel ?? 'Value'),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            copyLabel ?? 'Copy',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.copy_rounded, size: 12, color: Color(0xFF0F172A)),
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

  // 3B. VAULT FILES VIEW (Inside X)
  Widget _buildVaultFilesView() {
    if (_isLoadingData) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    if (_documents.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.folder_open_rounded, size: 36, color: Color(0xFF94A3B8)),
            SizedBox(height: 6),
            Text('No files indexed yet', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
          ],
        ),
      );
    }

    return ListView.separated(
      physics: const BouncingScrollPhysics(),
      itemCount: _documents.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final doc = _documents[index];
        final idDisplay = doc.idNumber != null ? 'ID: ${doc.idNumber}' : 'Verified Document';

        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.description_outlined, size: 18, color: Color(0xFF475569)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doc.title,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      idDisplay,
                      style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
              if (doc.idNumber != null)
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 15, color: Color(0xFF64748B)),
                  onPressed: () => _copy(doc.idNumber!, doc.title),
                ),
              IconButton(
                icon: const Icon(Icons.share_outlined, size: 15, color: Color(0xFF64748B)),
                onPressed: () async {
                  final file = File(doc.filePath);
                  if (await file.exists()) {
                    await SharePlus.instance.share(
                      ShareParams(files: [XFile(doc.filePath)], text: doc.title),
                    );
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // 4. BOTTOM INPUT BAR
  Widget _buildBottomInputBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _chatController,
              onSubmitted: (_) => _sendChatMessage(),
              style: const TextStyle(fontSize: 12.5, color: Color(0xFF0F172A)),
              decoration: const InputDecoration(
                hintText: 'Ask X...',
                hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 8),
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
            IconButton(
              icon: const Icon(Icons.send_rounded, size: 16, color: Color(0xFF0F172A)),
              onPressed: _sendChatMessage,
            ),
        ],
      ),
    );
  }
}

class _ProjectXSmallPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final paintDark = Paint()
      ..color = const Color(0xFF1E293B)
      ..style = PaintingStyle.fill;

    final pathDark = Path()
      ..moveTo(w * 0.1, 0)
      ..lineTo(w * 0.38, 0)
      ..lineTo(w * 0.9, h)
      ..lineTo(w * 0.62, h)
      ..close();

    canvas.drawPath(pathDark, paintDark);

    final rect = Rect.fromLTWH(0, 0, w, h);
    final paintBlue = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
      ).createShader(rect)
      ..style = PaintingStyle.fill;

    final pathBlue = Path()
      ..moveTo(w * 0.62, 0)
      ..lineTo(w * 0.9, 0)
      ..lineTo(w * 0.38, h)
      ..lineTo(w * 0.1, h)
      ..close();

    canvas.drawPath(pathBlue, paintBlue);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
