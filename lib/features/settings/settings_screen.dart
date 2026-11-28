import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/config/app_config.dart';
import '../overlay/assistive_ball_widget.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _ownerNameController = TextEditingController();

  String _ownerName = 'Primary Owner';
  String _ownerDob = '';
  bool _assistiveBallEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final key = await AppConfig.getApiKey();
    final prefs = await SharedPreferences.getInstance();
    final savedName = prefs.getString('vault_owner_name');
    final savedDob = prefs.getString('vault_owner_dob');
    final ballEnabled = prefs.getBool('assistive_ball_enabled') ?? true;

    if (mounted) {
      setState(() {
        if (key != null) _apiKeyController.text = key;
        if (savedName != null && savedName.isNotEmpty) {
          _ownerName = savedName;
          _ownerNameController.text = savedName;
        }
        if (savedDob != null && savedDob.isNotEmpty) {
          _ownerDob = savedDob;
        } else {
          _ownerDob = 'Not specified';
        }
        _assistiveBallEnabled = ballEnabled;
      });
    }
  }

  void _openApiKeyDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Gemini Vision API Key', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter your Google Gemini API Key (AIzaSy...) or ultra-low latency Groq API Key (gsk_...) to power real-time vision document extraction.',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _apiKeyController,
                obscureText: true,
                style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  hintText: 'AIzaSy... or gsk_...',
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                await AppConfig.setApiKey(_apiKeyController.text.trim());
                if (mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('API Key updated successfully!'), backgroundColor: Color(0xFF10B981)),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                foregroundColor: Colors.white,
              ),
              child: const Text('Save Key'),
            ),
          ],
        );
      },
    );
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
          child: Column(
            children: [
              // 1. TOP HEADER: "< Settings & Security"
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: Color(0xFF0F172A)),
                      onPressed: () {},
                    ),
                    const Expanded(
                      child: Text(
                        'Settings & Security',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                    const SizedBox(width: 40), // Balance back button
                  ],
                ),
              ),

              // Scrollable Body
              Expanded(
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 76),
                  children: [
                    // 2. PRIMARY OWNER PROFILE CARD
                    _buildOwnerProfileCard(),
                    const SizedBox(height: 18),

                    // 3. PRIVACY & LOCAL STORAGE DIAGNOSTIC CARD
                    _buildSectionHeader('Privacy & Local Storage Diagnostic Card'),
                    const SizedBox(height: 8),
                    _buildPrivacyDiagnosticCard(),
                    const SizedBox(height: 18),

                    // 4. ASSISTIVE BALL X OVERLAY (System-Wide Floating Smart Ball)
                    _buildSectionHeader('Assistive Ball X Overlay'),
                    const SizedBox(height: 8),
                    _buildAssistiveBallCard(),
                    const SizedBox(height: 18),

                    // 5. API CONFIGURATION TILE
                    _buildSectionHeader('API Configuration Tile'),
                    const SizedBox(height: 8),
                    _buildApiConfigCard(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w700,
        color: Color(0xFF1E293B),
        letterSpacing: -0.2,
      ),
    );
  }

  // 2. PRIMARY OWNER PROFILE CARD
  Widget _buildOwnerProfileCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          Row(
            children: [
              // Avatar Circle
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFE2E8F0),
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const ClipOval(
                  child: Icon(Icons.person, size: 40, color: Color(0xFF475569)),
                ),
              ),
              const SizedBox(width: 16),

              // Name & DOB
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Name',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _ownerName,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Date of Birth',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _ownerDob,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Primary Owner Pill
          Positioned(
            top: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Text(
                'Primary Owner',
                style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 3. PRIVACY DIAGNOSTIC CARD
  Widget _buildPrivacyDiagnosticCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.shield_outlined, color: Color(0xFF3B82F6), size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  '100% Local Device Storage',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                ),
                SizedBox(height: 2),
                Text(
                  'Zero Cloud Retention • Offline Encryption Active',
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 5. ASSISTIVE BALL X OVERLAY CARD
  Widget _buildAssistiveBallCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.smart_toy_outlined, color: Color(0xFF00B4D8), size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Enable Assistive Ball X',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                ),
                SizedBox(height: 2),
                Text(
                  'Floating smart ball docked on screen edge for fast copying & chat',
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
          Switch(
            value: _assistiveBallEnabled,
            activeThumbColor: Colors.white,
            activeTrackColor: const Color(0xFF00B4D8),
            inactiveThumbColor: Colors.white,
            inactiveTrackColor: const Color(0xFFCBD5E1),
            onChanged: (val) async {
              setState(() => _assistiveBallEnabled = val);
              await AssistiveBallWidget.setEnabled(val);
            },
          ),
        ],
      ),
    );
  }

  // 6. API CONFIGURATION TILE
  Widget _buildApiConfigCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Manage/configure custom',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                ),
                Text(
                  'Gemini API Key',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20, color: Color(0xFF0F172A)),
            onPressed: _openApiKeyDialog,
          ),
        ],
      ),
    );
  }
}
