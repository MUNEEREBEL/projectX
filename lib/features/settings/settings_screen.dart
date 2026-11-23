import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../core/config/app_config.dart';
import '../../core/database/database_service.dart';
import '../../models/person.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _ownerNameController = TextEditingController();

  String _ownerName = 'Muneer Ahmed';
  String _ownerDob = '15/08/1968';
  List<Person> _persons = [];

  bool _alert60 = true;
  bool _alert30 = true;
  bool _alert7 = true;
  bool _alert1 = true;

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
    final persons = await DatabaseService.instance.getAllPersons();

    if (mounted) {
      setState(() {
        if (key != null) _apiKeyController.text = key;
        if (savedName != null && savedName.isNotEmpty) {
          _ownerName = savedName;
          _ownerNameController.text = savedName;
        }
        if (savedDob != null && savedDob.isNotEmpty) {
          _ownerDob = savedDob;
        }
        _persons = persons;
      });
    }
  }

  void _openAddMemberModal() {
    final nameCtrl = TextEditingController();
    String relationship = 'Father';

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text('Add Family Member', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Full Name', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
                  const SizedBox(height: 6),
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      hintText: 'e.g. Absar Ahmed',
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text('Relationship', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: relationship,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                    ),
                    items: ['Father', 'Mother', 'Spouse', 'Child', 'Sibling', 'Other'].map((r) {
                      return DropdownMenuItem(value: r, child: Text(r));
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setDialogState(() => relationship = val);
                    },
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
                    if (nameCtrl.text.trim().isNotEmpty) {
                      final newPerson = Person(
                        id: const Uuid().v4(),
                        name: nameCtrl.text.trim(),
                        relationship: relationship,
                        avatarColorIndex: _persons.length % 6,
                      );
                      await DatabaseService.instance.upsertPerson(newPerson);
                      Navigator.pop(ctx);
                      _loadSettings();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Add Member'),
                ),
              ],
            );
          },
        );
      },
    );
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
                'Enter your free Google Gemini API key from Google AI Studio (aistudio.google.com).',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _apiKeyController,
                obscureText: true,
                style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  hintText: 'AIzaSy...',
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
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 90),
                  children: [
                    // 2. PRIMARY OWNER PROFILE CARD
                    _buildOwnerProfileCard(),
                    const SizedBox(height: 18),

                    // 3. FAMILY MEMBERS SECTION
                    _buildSectionHeader('Family Members Section'),
                    const SizedBox(height: 8),
                    _buildFamilyMembersCard(),
                    const SizedBox(height: 18),

                    // 4. PRIVACY & LOCAL STORAGE DIAGNOSTIC CARD
                    _buildSectionHeader('Privacy & Local Storage Diagnostic Card'),
                    const SizedBox(height: 8),
                    _buildPrivacyDiagnosticCard(),
                    const SizedBox(height: 18),

                    // 5. NOTIFICATION ALERTS TOGGLE
                    _buildSectionHeader('Notification Alerts Toggle'),
                    const SizedBox(height: 8),
                    _buildNotificationTogglesCard(),
                    const SizedBox(height: 18),

                    // 6. API CONFIGURATION TILE
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

  // 3. FAMILY MEMBERS CARD
  Widget _buildFamilyMembersCard() {
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          // Self
          _buildMemberAvatar('Self\n(${_ownerName.split(' ').first})', Icons.person),

          // Father
          _buildMemberAvatar('Father', Icons.elderly),

          // Mother
          _buildMemberAvatar('Mother', Icons.face),

          // + Add Member Button
          InkWell(
            onTap: _openAddMemberModal,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 60,
              height: 70,
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFBFDBFE), style: BorderStyle.solid),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.add, color: Color(0xFF3B82F6), size: 20),
                  SizedBox(height: 4),
                  Text(
                    'Add\nMember',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: Color(0xFF3B82F6)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberAvatar(String label, IconData icon) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFF1F5F9),
            border: Border.all(color: const Color(0xFFCBD5E1), width: 1.5),
          ),
          child: Icon(icon, size: 24, color: const Color(0xFF475569)),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFF334155), height: 1.2),
        ),
      ],
    );
  }

  // 4. PRIVACY DIAGNOSTIC CARD
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

  // 5. NOTIFICATION ALERTS TOGGLES
  Widget _buildNotificationTogglesCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
      child: Column(
        children: [
          _buildToggleRow('60 Days Expiry Alert', _alert60, (v) => setState(() => _alert60 = v)),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          _buildToggleRow('30 Days Expiry Alert', _alert30, (v) => setState(() => _alert30 = v)),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          _buildToggleRow('7 Days Expiry Alert', _alert7, (v) => setState(() => _alert7 = v)),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          _buildToggleRow('1 Day Expiry Alert', _alert1, (v) => setState(() => _alert1 = v)),
        ],
      ),
    );
  }

  Widget _buildToggleRow(String title, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
          ),
          Switch(
            value: value,
            activeThumbColor: Colors.white,
            activeTrackColor: const Color(0xFF0F172A),
            inactiveThumbColor: Colors.white,
            inactiveTrackColor: const Color(0xFFCBD5E1),
            onChanged: onChanged,
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
