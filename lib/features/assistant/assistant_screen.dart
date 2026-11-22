import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/services/qa_assistant_service.dart';
import '../../core/theme/app_theme.dart';

class ChatMessage {
  final String text;
  final bool isUser;
  final List<String> copyableValues;

  ChatMessage({
    required this.text,
    required this.isUser,
    this.copyableValues = const [],
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
      text: 'PrivDoc Intelligence Assistant ready. You can ask for policy numbers, expiry dates, registered addresses, or cardholder details.',
      isUser: false,
    ),
  ];
  final TextEditingController _controller = TextEditingController();
  bool _isLoading = false;

  final List<String> _suggestions = [
    'When does my car insurance expire?',
    'What is my PAN number?',
    'Show full permanent address with pin code',
    'Which documents are expiring soon?',
  ];

  void _sendMessage([String? presetText]) async {
    final text = presetText ?? _controller.text.trim();
    if (text.isEmpty) return;

    if (presetText == null) _controller.clear();

    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true));
      _isLoading = true;
    });

    try {
      final response = await QAAssistantService.askQuestion(text);
      if (mounted) {
        setState(() {
          _messages.add(ChatMessage(
            text: response.answer,
            isUser: false,
            copyableValues: response.copyableValues,
          ));
          _isLoading = false;
        });
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
      }
    }
  }

  void _copyToClipboard(String value) {
    Clipboard.setData(ClipboardData(text: value));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied "$value" to clipboard'),
        duration: const Duration(seconds: 1),
        backgroundColor: AppTheme.darkCard,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Document Intelligence Q&A'),
      ),
      body: Column(
        children: [
          // Messages View
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    mainAxisAlignment:
                        msg.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!msg.isUser) ...[
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: AppTheme.darkCard,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppTheme.darkBorder),
                          ),
                          child: const Icon(Icons.bolt, color: AppTheme.primaryColor, size: 16),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: msg.isUser ? AppTheme.primaryColor : AppTheme.darkCard,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: msg.isUser ? AppTheme.primaryColor : AppTheme.darkBorder,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SelectableText(
                                msg.text,
                                style: TextStyle(
                                  color: msg.isUser ? Colors.white : AppTheme.textPrimary,
                                  fontSize: 13,
                                  height: 1.45,
                                  fontWeight: msg.isUser ? FontWeight.w500 : FontWeight.normal,
                                ),
                              ),
                              if (msg.copyableValues.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                const Text(
                                  'Tap to copy field:',
                                  style: TextStyle(fontSize: 10, color: AppTheme.textMuted, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: msg.copyableValues.map((val) {
                                    return ActionChip(
                                      avatar: const Icon(Icons.copy, size: 12, color: AppTheme.primaryColor),
                                      label: Text(
                                        val,
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, fontFamily: 'monospace'),
                                      ),
                                      onPressed: () => _copyToClipboard(val),
                                      backgroundColor: AppTheme.darkBg,
                                      side: const BorderSide(color: AppTheme.darkBorder),
                                    );
                                  }).toList(),
                                ),
                              ],
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

          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryColor),
                  ),
                  SizedBox(width: 8),
                  Text('Retrieving grounded answer...', style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                ],
              ),
            ),

          // Suggestion Chips
          SizedBox(
            height: 34,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _suggestions.length,
              itemBuilder: (context, index) {
                final suggestion = _suggestions[index];
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ActionChip(
                    label: Text(suggestion, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                    onPressed: _isLoading ? null : () => _sendMessage(suggestion),
                    backgroundColor: AppTheme.darkCard,
                    side: const BorderSide(color: AppTheme.darkBorder),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 8),

          // Input Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(
              color: AppTheme.darkCard,
              border: Border(top: BorderSide(color: AppTheme.darkBorder)),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      onSubmitted: (_) => _sendMessage(),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Ask about any document or field...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: AppTheme.darkBorder),
                        ),
                        filled: true,
                        fillColor: AppTheme.darkBg,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.arrow_upward, color: AppTheme.primaryColor),
                    onPressed: _isLoading ? null : () => _sendMessage(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
