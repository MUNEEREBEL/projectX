import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/alert_service.dart';
import '../../core/services/folder_sync_service.dart';
import '../../core/services/vision_extractor_service.dart';
import '../../core/theme/app_theme.dart';
import '../overlay/assistive_ball_dialog.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _ownerNameController = TextEditingController();
  String? _folderPath;
  bool _isSavedKey = false;
  bool _obscureKey = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final key = await VisionExtractorService.getApiKey();
    final folder = await FolderSyncService.getSelectedFolderPath();
    final prefs = await SharedPreferences.getInstance();
    final ownerName = prefs.getString('vault_owner_name') ?? 'Vault Owner';

    if (mounted) {
      setState(() {
        if (key != null) _apiKeyController.text = key;
        _folderPath = folder;
        _ownerNameController.text = ownerName;
      });
    }
  }

  Future<void> _saveApiKey() async {
    await VisionExtractorService.setApiKey(_apiKeyController.text);
    setState(() => _isSavedKey = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _isSavedKey = false);
    });
  }

  Future<void> _saveOwnerName() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('vault_owner_name', _ownerNameController.text.trim());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Owner name updated.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings & Privacy'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // 1. Vault Owner Profile
          _buildSectionHeader('VAULT PROFILE'),
          _buildSettingsCard([
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: const Icon(Icons.person_outline, color: AppTheme.primaryColor),
              title: const Text('Primary Cardholder Name', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: Text(
                _ownerNameController.text.isEmpty ? 'Not set' : _ownerNameController.text,
                style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
              trailing: TextButton(
                onPressed: () => _showEditNameDialog(context),
                child: const Text('Edit', style: TextStyle(color: AppTheme.primaryColor, fontSize: 12)),
              ),
            ),
          ]),

          const SizedBox(height: 20),

          // 2. Documents Folder
          _buildSectionHeader('STORAGE & MONITORED FOLDER'),
          _buildSettingsCard([
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              leading: const Icon(Icons.folder_outlined, color: AppTheme.accentColor),
              title: const Text('Scoped Document Folder', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 2),
                  Text(
                    _folderPath ?? 'No folder selected',
                    style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Supported: .pdf, .png, .jpg, .docx',
                    style: TextStyle(fontSize: 10, color: AppTheme.textSecondary, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              trailing: OutlinedButton(
                onPressed: () async {
                  final picked = await FolderSyncService.pickFolder();
                  if (picked != null) {
                    setState(() => _folderPath = picked);
                  }
                },
                child: const Text('Browse', style: TextStyle(fontSize: 11)),
              ),
            ),
          ]),

          const SizedBox(height: 20),

          // 3. Assistive Ball & Copilot
          _buildSectionHeader('ASSISTIVE FORM COPILOT'),
          _buildSettingsCard([
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: const Icon(Icons.touch_app_outlined, color: AppTheme.primaryColor),
              title: const Text('Test Assistive Ball', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: const Text(
                'Opens the compact quick-copy and file upload dialog box.',
                style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
              ),
              trailing: ElevatedButton(
                onPressed: () => AssistiveBallDialog.show(context),
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
                child: const Text('Test', style: TextStyle(fontSize: 11)),
              ),
            ),
          ]),

          const SizedBox(height: 20),

          // 4. Free Gemini Vision Engine
          _buildSectionHeader('FAST AI VISION ENGINE'),
          _buildSettingsCard([
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.bolt, color: AppTheme.primaryColor, size: 20),
                      const SizedBox(width: 8),
                      const Text(
                        'Google Gemini 2.5 Flash API Key',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.successColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('FREE TIER', style: TextStyle(color: AppTheme.successColor, fontSize: 9, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Sub-second Indian document parsing and factual Q&A. Keys are stored locally on your device.',
                    style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _apiKeyController,
                    obscureText: _obscureKey,
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Enter API Key (AIzaSy...)',
                      suffixIcon: IconButton(
                        icon: Icon(_obscureKey ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 16),
                        onPressed: () => setState(() => _obscureKey = !_obscureKey),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      onPressed: _saveApiKey,
                      icon: Icon(_isSavedKey ? Icons.check : Icons.save, size: 14),
                      label: Text(_isSavedKey ? 'Key Saved' : 'Save Key', style: const TextStyle(fontSize: 12)),
                    ),
                  ),
                ],
              ),
            ),
          ]),

          const SizedBox(height: 20),

          // 5. Expiry Alarms
          _buildSectionHeader('EXPIRY & RENEWAL RADAR'),
          _buildSettingsCard([
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: const Icon(Icons.alarm, color: AppTheme.warningColor),
              title: const Text('Local Alarm Notifications', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: const Text(
                'Fires offline Android alarms at 60, 30, 7, and 1 day before document expiry.',
                style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
              ),
              trailing: OutlinedButton(
                onPressed: () async {
                  await AlertService.instance.showQuickNotification(
                    title: 'PrivDoc Renewal Alert',
                    body: 'Your local offline expiry radar is running and active.',
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Test notification sent.')),
                    );
                  }
                },
                child: const Text('Test Alarm', style: TextStyle(fontSize: 11)),
              ),
            ),
          ]),

          const SizedBox(height: 20),

          // 6. Zero-Knowledge Architecture
          _buildSectionHeader('SECURITY & ZERO-KNOWLEDGE ARCHITECTURE'),
          _buildSettingsCard([
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.lock_outline, color: AppTheme.textSecondary, size: 16),
                      SizedBox(width: 8),
                      Text(
                        '100% Local Device Storage',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppTheme.textPrimary),
                      ),
                    ],
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Your documents, biometrics, and database records remain strictly on your physical phone in a sandboxed SQLite vault. AI extraction uses an ephemeral zero-retention transit tunnel.',
                    style: TextStyle(fontSize: 11, color: AppTheme.textMuted, height: 1.5),
                  ),
                ],
              ),
            ),
          ]),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 6),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: AppTheme.textMuted,
        ),
      ),
    );
  }

  Widget _buildSettingsCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Column(
        children: children,
      ),
    );
  }

  void _showEditNameDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        title: const Text('Edit Cardholder Name'),
        content: TextField(
          controller: _ownerNameController,
          decoration: const InputDecoration(hintText: 'Enter full name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              _saveOwnerName();
              setState(() {});
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
