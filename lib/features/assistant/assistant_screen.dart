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
      text: 'Hello! I am your PrivDoc Assistant. Ask me anything about your stored documents, expiry dates, or policy numbers.',
      isUser: false,
    ),
  ];
  final TextEditingController _controller = TextEditingController();
  bool _isLoading = false;

  final List<String> _suggestions = [
    'When does my car insurance expire?',
    'What is my PAN number?',
    'Show my permanent address with pin code',
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
            text: 'Error answering question: $e',
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
        content: Text('Copied "$value" to clipboard!'),
        duration: const Duration(seconds: 1),
        backgroundColor: AppTheme.successColor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Vault Assistant'),
      ),
      body: Column(
        children: [
          // Message List
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(
                    mainAxisAlignment:
                        msg.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!msg.isUser) ...[
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.bolt, color: AppTheme.primaryColor, size: 18),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: msg.isUser ? AppTheme.primaryColor : AppTheme.darkCard,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: msg.isUser ? AppTheme.primaryColor : AppTheme.darkSurface,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SelectableText(
                                msg.text,
                                style: TextStyle(
                                  color: msg.isUser ? Colors.black : Colors.white,
                                  fontSize: 14,
                                  height: 1.4,
                                  fontWeight: msg.isUser ? FontWeight.w600 : FontWeight.normal,
                                ),
                              ),
                              if (msg.copyableValues.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                const Text(
                                  'Tap to copy:',
                                  style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: msg.copyableValues.map((val) {
                                    return ActionChip(
                                      avatar: const Icon(Icons.copy, size: 14, color: AppTheme.primaryColor),
                                      label: Text(
                                        val,
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                      ),
                                      onPressed: () => _copyToClipboard(val),
                                      backgroundColor: AppTheme.darkBg,
                                      side: const BorderSide(color: AppTheme.primaryColor),
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
              padding: EdgeInsets.all(8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryColor),
                  ),
                  SizedBox(width: 8),
                  Text('Searching verified documents...', style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),

          // Suggestion Chips
          SizedBox(
            height: 38,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _suggestions.length,
              itemBuilder: (context, index) {
                final suggestion = _suggestions[index];
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ActionChip(
                    label: Text(suggestion, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    onPressed: _isLoading ? null : () => _sendMessage(suggestion),
                    backgroundColor: AppTheme.darkCard,
                    side: const BorderSide(color: AppTheme.darkSurface),
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
              border: Border(top: BorderSide(color: AppTheme.darkSurface)),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      onSubmitted: (_) => _sendMessage(),
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Ask about any document or detail...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: AppTheme.darkBg,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.send, color: AppTheme.primaryColor),
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
