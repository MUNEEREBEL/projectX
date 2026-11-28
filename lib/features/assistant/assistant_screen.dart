import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/document_model.dart';
import '../../core/services/qa_assistant_service.dart';
import '../vault/document_detail_screen.dart';

class ChatMessage {
  final String text;
  final bool isUser;
  final List<String> copyableValues;
  final List<DocumentModel> referenceDocuments;

  ChatMessage({
    required this.text,
    required this.isUser,
    this.copyableValues = const [],
    this.referenceDocuments = const [],
  });
}

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final List<ChatMessage> _messages = [
    ChatMessage(
      text: 'Project X Assistant ready. Ask any question about your documents, policy numbers, or expiry dates.',
      isUser: false,
    ),
  ];

  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;
  bool _offlineMode = false;

  final List<String> _suggestions = [
    'What is my PAN?',
    'When does car insurance expire?',
    'What is my father\'s Aadhaar?',
    'Show full permanent address',
  ];

  void _sendMessage([String? presetText]) async {
    final text = presetText ?? _controller.text.trim();
    if (text.isEmpty) return;

    if (presetText == null) _controller.clear();

    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true));
      _isLoading = true;
    });

    _scrollToBottom();

    try {
      final response = await QAAssistantService.askQuestion(text, forceOffline: _offlineMode);
      if (mounted) {
        setState(() {
          _messages.add(ChatMessage(
            text: response.answer,
            isUser: false,
            copyableValues: response.copyableValues,
            referenceDocuments: response.referenceDocuments,
          ));
          _isLoading = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.add(ChatMessage(
            text: 'Unable to retrieve answer: $e',
            isUser: false,
          ));
          _isLoading = false;
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
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0.0, 0.35, 0.7, 1.0],
            colors: [
              Color(0xFFEFF6FF), // soft airy blue top
              Color(0xFFF8FAFC), // clean white slate
              Color(0xFFFDF2F8), // gentle blush accent
              Color(0xFFEBF4FF), // soft glow bottom
            ],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // 1. TOP HEADER: "Project X Assistant" & "Online"
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Project X Assistant',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                        letterSpacing: -0.4,
                      ),
                    ),
                    // Interactive Mode Pill: Cloud AI vs Fast Offline Search
                    InkWell(
                      onTap: () {
                        setState(() => _offlineMode = !_offlineMode);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(_offlineMode
                                ? 'Offline Fast Mode active (instant sub-100ms local answers)'
                                : 'Online AI active (Gemini Vision intelligence)'),
                            duration: const Duration(seconds: 1),
                            backgroundColor: const Color(0xFF0F172A),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _offlineMode ? const Color(0xFFEFF6FF) : const Color(0xFFDCFCE7),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _offlineMode ? const Color(0xFF93C5FD) : const Color(0xFF86EFAC),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: _offlineMode ? const Color(0xFF3B82F6) : const Color(0xFF10B981),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              _offlineMode ? 'Offline Fast' : 'Online AI',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: _offlineMode ? const Color(0xFF1D4ED8) : const Color(0xFF16A34A),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 2. SUGGESTION CHIPS
              SizedBox(
                height: 36,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: _suggestions.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final suggestion = _suggestions[index];
                    return InkWell(
                      onTap: () => _sendMessage(suggestion),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Text(
                          suggestion,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF475569),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),

              // 3. CHAT MESSAGES LIST
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final message = _messages[index];
                    return _buildMessageBubble(message);
                  },
                ),
              ),

              if (_isLoading)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: Row(
                    children: const [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0F172A)),
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Searching verified vault documents...',
                        style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B), fontStyle: FontStyle.italic),
                      ),
                    ],
                  ),
                ),

              // 4. FLOATING INPUT BAR
              Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  6,
                  16,
                  MediaQuery.of(context).viewInsets.bottom > 0 ? 8 : 78,
                ),
                child: _buildInputBar(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    if (message.isUser) {
      // User message: Dark navy container right-aligned
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12, left: 50),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.12),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            message.text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
        ),
      );
    }

    // AI Assistant message: Frosted white container left-aligned
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14, right: 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                message.text,
                style: const TextStyle(
                  color: Color(0xFF1E293B),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  height: 1.45,
                ),
              ),
            ),

            // Copyable extracted values (1-tap autofill buttons)
            if (message.copyableValues.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: message.copyableValues.map((val) {
                  return InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: val));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Copied: "$val"'),
                          duration: const Duration(seconds: 1),
                          backgroundColor: const Color(0xFF0F172A),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.copy_rounded, size: 12, color: Color(0xFF2563EB)),
                          const SizedBox(width: 4),
                          Text(
                            val,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF2563EB),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],

            // Attached Reference Document Card
            if (message.referenceDocuments.isNotEmpty) ...[
              const SizedBox(height: 6),
              ...message.referenceDocuments.map((doc) => _buildReferenceCard(doc)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildReferenceCard(DocumentModel doc) {
    return Container(
      width: 240,
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.description_outlined, size: 19, color: Color(0xFF2563EB)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  doc.title,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DocumentDetailScreen(document: doc),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: const Text(
                      'View Document →',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF2563EB)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 4. FLOATING INPUT BAR
  Widget _buildInputBar() {
    return Container(
      height: 50,
      padding: const EdgeInsets.only(left: 14, right: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(
            Icons.auto_awesome_rounded,
            size: 19,
            color: Color(0xFF00B4D8),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _controller,
              onSubmitted: (_) => _sendMessage(),
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF0F172A),
                fontWeight: FontWeight.w500,
              ),
              decoration: const InputDecoration(
                hintText: 'Ask anything about your documents, PAN, Aadhaar...',
                hintStyle: TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w400,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            onTap: () => _sendMessage(),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: Color(0xFF0F172A),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Icon(
                  Icons.arrow_upward_rounded,
                  size: 18,
                  color: Color(0xFF00F2FE),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
