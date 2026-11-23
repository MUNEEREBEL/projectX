import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/config/app_config.dart';
import '../../core/database/database_service.dart';
import '../../core/services/alert_service.dart';
import '../../core/services/folder_sync_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/glass_card.dart';
import '../../models/person.dart';

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
  bool _hasActiveKey = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final key = await AppConfig.getApiKey();
    final folder = await FolderSyncService.getSelectedFolderPath();
    final prefs = await SharedPreferences.getInstance();
    final ownerName = prefs.getString('vault_owner_name') ?? 'Primary Cardholder';

    if (mounted) {
      setState(() {
        if (key != null) _apiKeyController.text = key;
        _hasActiveKey = key != null && key.isNotEmpty;
        _folderPath = folder;
        _ownerNameController.text = ownerName;
      });
    }
  }

  Future<void> _saveApiKey() async {
    await AppConfig.setApiKey(_apiKeyController.text.trim());
    setState(() {
      _isSavedKey = true;
      _hasActiveKey = _apiKeyController.text.trim().isNotEmpty;
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _isSavedKey = false);
    });
  }

  Future<void> _saveOwnerName() async {
    final newName = _ownerNameController.text.trim();
    if (newName.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('vault_owner_name', newName);

    // Also update primary person in SQLite database
    final persons = await DatabaseService.instance.getAllPersons();
    if (persons.isNotEmpty) {
      final primary = persons.first;
      await DatabaseService.instance.upsertPerson(
        Person(
          id: primary.id,
          name: newName,
          relationship: primary.relationship,
          avatarColorIndex: primary.avatarColorIndex,
        ),
      );
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cardholder name updated across vault.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Settings & Privacy'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // 1. Vault Security Shield Banner
          GlassCard(
            padding: const EdgeInsets.all(16),
            borderRadius: 18,
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.successColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.successColor.withValues(alpha: 0.3)),
                  ),
                  child: const Icon(Icons.shield_outlined, color: AppTheme.successColor, size: 22),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '100% Local Device Storage',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.textPrimary),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Zero cloud retention. Biometrics, IDs, and records are isolated in sandboxed SQLite storage.',
                        style: TextStyle(fontSize: 11, color: AppTheme.textSecondary, height: 1.3),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // 2. Vault Owner Profile
          _buildSectionHeader('PRIMARY CARDHOLDER PROFILE'),
          _buildSettingsCard([
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: const Icon(Icons.person_outline, color: AppTheme.primaryColor),
              title: const Text('Primary Cardholder Name', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: Text(
                _ownerNameController.text.isEmpty ? 'Not configured' : _ownerNameController.text,
                style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
              trailing: TextButton(
                onPressed: () => _showEditNameDialog(context),
                child: const Text('Edit', style: TextStyle(color: AppTheme.primaryColor, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ),
          ]),

          const SizedBox(height: 20),

          // 3. Documents & Monitored Folder
          _buildSectionHeader('STORAGE & MONITORED DOCUMENTS'),
          _buildSettingsCard([
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              leading: const Icon(Icons.folder_outlined, color: AppTheme.accentColor),
              title: const Text('Monitored Folder', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 2),
                  Text(
                    _folderPath ?? 'No folder selected yet',
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
              trailing: ElevatedButton(
                onPressed: () async {
                  final res = await FolderSyncService.pickFolderAndDiscover();
                  if (res != null) {
                    setState(() => _folderPath = res.folderPathOrUri);
                    if (res.files.isNotEmpty && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Auto-indexing ${res.files.length} document(s)...')),
                      );
                      FolderSyncService.syncFiles(res.files).listen((p) {
                        if (p.isCompleted && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(p.status)),
                          );
                        }
                      });
                    }
                  }
                },
                child: const Text('Change', style: TextStyle(fontSize: 11)),
              ),
            ),
          ]),

          const SizedBox(height: 20),

          // 5. Fast AI Vision Engine
          _buildSectionHeader('FAST AI VISION OCR ENGINE'),
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
                        'Google Gemini 2.5 Flash',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _hasActiveKey
                              ? AppTheme.successColor.withValues(alpha: 0.15)
                              : AppTheme.warningColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _hasActiveKey ? 'ACTIVE' : 'FREE TIER READY',
                          style: TextStyle(
                            color: _hasActiveKey ? AppTheme.successColor : AppTheme.warningColor,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'High-speed structured field extraction with Verhoeff checksum validation. Configurable via .env or input below.',
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

          // 6. Expiry Radar Alarms
          _buildSectionHeader('OFFLINE EXPIRY & RENEWAL RADAR'),
          _buildSettingsCard([
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: const Icon(Icons.alarm, color: AppTheme.warningColor),
              title: const Text('Offline Local Alarms', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: const Text(
                'Fires offline Android alarms at 60, 30, 7, and 1 day before document expiration.',
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
                      const SnackBar(content: Text('Test notification dispatched.')),
                    );
                  }
                },
                child: const Text('Test Alarm', style: TextStyle(fontSize: 11)),
              ),
            ),
          ]),

          const SizedBox(height: 20),

          // 7. Danger Zone
          _buildSectionHeader('VAULT MAINTENANCE'),
          _buildSettingsCard([
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: const Icon(Icons.delete_sweep_outlined, color: AppTheme.dangerColor),
              title: const Text('Clear All Vault Data', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.dangerColor)),
              subtitle: const Text('Erase all local document records and reset vault database.', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
              trailing: OutlinedButton(
                style: OutlinedButton.styleFrom(side: const BorderSide(color: AppTheme.dangerColor)),
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: AppTheme.darkCard,
                      title: const Text('Clear Vault Data?'),
                      content: const Text('This will delete all indexed document records from your local database.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.dangerColor),
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Clear Data', style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  );

                  if (confirm == true) {
                    await DatabaseService.instance.clearAllData();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('All vault records cleared.')),
                      );
                    }
                  }
                },
                child: const Text('Clear', style: TextStyle(fontSize: 11, color: AppTheme.dangerColor)),
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
    return GlassCard(
      padding: EdgeInsets.zero,
      borderRadius: 16,
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
          decoration: const InputDecoration(hintText: 'Enter full name (e.g. Muneer Shaik)'),
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
