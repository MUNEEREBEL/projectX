import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../core/config/app_config.dart';
import '../../core/database/database_service.dart';
import '../../core/services/folder_sync_service.dart';
import '../../core/services/overlay_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/person.dart';
import '../../main_navigation_shell.dart';
import '../overlay/assistive_ball_dialog.dart';

class OnboardingSetupScreen extends StatefulWidget {
  const OnboardingSetupScreen({super.key});

  @override
  State<OnboardingSetupScreen> createState() => _OnboardingSetupScreenState();
}

class _OnboardingSetupScreenState extends State<OnboardingSetupScreen> {
  final PageController _pageController = PageController();
  int _currentStep = 0;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  String? _selectedFolderPath;
  List<File> _selectedFiles = [];
  bool _isScanning = false;
  String _scanStatus = '';
  bool _hasApiKey = false;
  bool _overlayPermitted = false;

  @override
  void initState() {
    super.initState();
    _checkInitialState();
  }

  Future<void> _checkInitialState() async {
    final key = await AppConfig.getApiKey();
    final canOverlay = await OverlayService.canDrawOverlays();
    if (mounted) {
      setState(() {
        _hasApiKey = key != null && key.isNotEmpty;
        if (key != null) _apiKeyController.text = key;
        _overlayPermitted = canOverlay;
      });
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_completed', true);
    if (_nameController.text.trim().isNotEmpty) {
      await prefs.setString('vault_owner_name', _nameController.text.trim());

      final existing = await DatabaseService.instance.getAllPersons();
      if (existing.isEmpty) {
        await DatabaseService.instance.upsertPerson(
          Person(
            id: const Uuid().v4(),
            name: _nameController.text.trim(),
            relationship: 'Self',
            avatarColorIndex: 0,
          ),
        );
      }
    }

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MainNavigationShell()),
      );
    }
  }

  void _nextStep() {
    if (_currentStep < 3) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
      setState(() => _currentStep++);
    } else {
      _completeOnboarding();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      body: SafeArea(
        child: Column(
          children: [
            // Top Stepper Indicator
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                children: List.generate(4, (index) {
                  final isActive = index <= _currentStep;
                  return Expanded(
                    child: Container(
                      height: 3,
                      margin: EdgeInsets.only(right: index < 3 ? 8 : 0),
                      decoration: BoxDecoration(
                        color: isActive ? AppTheme.primaryColor : AppTheme.darkBorder,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
              ),
            ),

            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildStepName(),
                  _buildStepDocumentsAndApiKey(),
                  _buildStepScan(),
                  _buildStepCopilotTest(),
                ],
              ),
            ),

            // Bottom Navigation Actions
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                children: [
                  if (_currentStep > 0 && _currentStep < 3)
                    TextButton(
                      onPressed: () {
                        _pageController.previousPage(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeInOut,
                        );
                        setState(() => _currentStep--);
                      },
                      child: const Text('Back', style: TextStyle(color: AppTheme.textSecondary)),
                    ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: () {
                      if (_currentStep == 0 && _nameController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please enter your full name to proceed.')),
                        );
                        return;
                      }
                      if (_currentStep == 1 && !_hasApiKey && _apiKeyController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please provide your free Gemini API key to proceed.')),
                        );
                        return;
                      }
                      _nextStep();
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                    ),
                    child: Text(_currentStep == 3 ? 'Open Vault' : 'Continue'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // STEP 1: Full Name Anchor
  Widget _buildStepName() {
    return Padding(
      padding: const EdgeInsets.all(28.0),
      child: ListView(
        children: [
          const SizedBox(height: 16),
          const Text(
            'Primary Cardholder',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Enter your full name as it appears on your official documents (Aadhaar, PAN, DL). This automatically distinguishes your documents from family members.',
            style: TextStyle(fontSize: 14, color: AppTheme.textSecondary, height: 1.5),
          ),
          const SizedBox(height: 32),
          const Text(
            'PRIMARY CARDHOLDER NAME',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textMuted, letterSpacing: 0.6),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            style: const TextStyle(fontSize: 15, color: Colors.white, fontWeight: FontWeight.w500),
            decoration: const InputDecoration(
              hintText: 'e.g. Muneer Shaik or Rahul Sharma',
              prefixIcon: Icon(Icons.person_outline, color: AppTheme.textSecondary, size: 20),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.darkCard,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.darkBorder),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 16, color: AppTheme.accentColor),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Indian name variations (e.g. inverted "Shaik Muneer" vs "Muneer Shaik") are automatically resolved to your profile.',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // STEP 2: Scoped Documents & API Key
  Widget _buildStepDocumentsAndApiKey() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: ListView(
        children: [
          const Text(
            'Documents & Extraction',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Select your documents or choose a folder. Files are permanently preserved in your local vault.',
            style: TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 20),

          // API Key status / input
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.darkCard,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.darkBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.bolt, color: AppTheme.primaryColor, size: 18),
                    const SizedBox(width: 8),
                    const Text(
                      'Gemini Vision AI Engine',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppTheme.textPrimary),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _hasApiKey
                            ? AppTheme.successColor.withValues(alpha: 0.15)
                            : AppTheme.warningColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _hasApiKey ? 'CONFIGURED' : 'FREE KEY REQUIRED',
                        style: TextStyle(
                          color: _hasApiKey ? AppTheme.successColor : AppTheme.warningColor,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (!_hasApiKey) ...[
                  TextField(
                    controller: _apiKeyController,
                    obscureText: true,
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'Enter API Key (AIzaSy...)',
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    onChanged: (val) {
                      if (val.trim().isNotEmpty) {
                        AppConfig.setApiKey(val.trim());
                        setState(() => _hasApiKey = true);
                      }
                    },
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Get a free API key at aistudio.google.com. You can also place it in .env file.',
                    style: TextStyle(fontSize: 10, color: AppTheme.textMuted),
                  ),
                ] else
                  const Text(
                    'API key loaded from configuration. Sub-second zero-retention OCR ready.',
                    style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // File selection options
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.darkCard,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.darkBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'DOCUMENT SELECTION',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.textMuted, letterSpacing: 0.5),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Supported: .pdf, .png, .jpg, .docx',
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 14),

                // Option 1: Pick Files Directly (Primary & most reliable on Android)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final files = await FolderSyncService.pickDocumentFiles();
                      if (files.isNotEmpty) {
                        setState(() {
                          _selectedFiles = files;
                          _selectedFolderPath = null;
                        });
                      }
                    },
                    icon: const Icon(Icons.file_upload_outlined, size: 16),
                    label: Text(
                      _selectedFiles.isNotEmpty
                          ? '${_selectedFiles.length} File(s) Selected'
                          : 'Select Document Files Directly',
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                // Option 2: Pick Folder
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await FolderSyncService.pickFolder();
                      if (picked != null) {
                        setState(() {
                          _selectedFolderPath = picked;
                          _selectedFiles = [];
                        });
                      }
                    },
                    icon: const Icon(Icons.folder_open, size: 16),
                    label: Text(_selectedFolderPath != null ? 'Folder: ${p.basename(_selectedFolderPath!)}' : 'Or Select Monitored Folder'),
                  ),
                ),

                if (_selectedFiles.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ..._selectedFiles.take(4).map((f) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        const Icon(Icons.check, size: 14, color: AppTheme.successColor),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            p.basename(f.path),
                            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  )),
                  if (_selectedFiles.length > 4)
                    Text('+ ${_selectedFiles.length - 4} more files', style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // STEP 3: Scan & Ready
  Widget _buildStepScan() {
    return Padding(
      padding: const EdgeInsets.all(28.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          const Text(
            'Initial Scan & Preparation',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'PrivDoc will now extract details, verify checksums, and permanently store the documents in your private SQLite vault.',
            style: TextStyle(fontSize: 14, color: AppTheme.textSecondary, height: 1.5),
          ),
          const SizedBox(height: 36),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.darkCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.darkBorder),
            ),
            child: Column(
              children: [
                Icon(
                  _isScanning ? Icons.sync : Icons.shield_outlined,
                  color: _isScanning ? AppTheme.primaryColor : AppTheme.successColor,
                  size: 44,
                ),
                const SizedBox(height: 16),
                Text(
                  _isScanning ? 'Extracting & Saving Vault...' : 'Ready to Index',
                  style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  _scanStatus.isNotEmpty
                      ? _scanStatus
                      : (_selectedFiles.isNotEmpty
                          ? '${_selectedFiles.length} file(s) selected for indexing.'
                          : (_selectedFolderPath != null
                              ? 'Folder linked. Ready to scan.'
                              : 'Select files or folder in previous step.')),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 20),
                if (!_isScanning)
                  ElevatedButton.icon(
                    onPressed: _startScan,
                    icon: const Icon(Icons.play_arrow, size: 16),
                    label: const Text('Start Vault Extraction'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _startScan() {
    setState(() {
      _isScanning = true;
      _scanStatus = 'Starting document indexing...';
    });

    final stream = _selectedFiles.isNotEmpty
        ? FolderSyncService.syncFiles(_selectedFiles)
        : FolderSyncService.syncFolder(folderPath: _selectedFolderPath);

    stream.listen(
      (progress) {
        if (mounted) {
          setState(() {
            _scanStatus = progress.status;
            if (progress.isCompleted) {
              _isScanning = false;
            }
          });
        }
      },
      onError: (e) {
        if (mounted) {
          setState(() {
            _isScanning = false;
            _scanStatus = 'Scan error: $e';
          });
        }
      },
    );
  }

  // STEP 4: Assistive Ball & Copilot Test
  Widget _buildStepCopilotTest() {
    return Padding(
      padding: const EdgeInsets.all(28.0),
      child: ListView(
        children: [
          const SizedBox(height: 16),
          const Text(
            'Assistive Form Copilot',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'The assistive ball floats over Google Chrome, banking portals, and government websites. Tap it anytime to copy card numbers or pass upload files with 1 tap.',
            style: TextStyle(fontSize: 14, color: AppTheme.textSecondary, height: 1.5),
          ),
          const SizedBox(height: 28),

          // Ball Interactive Preview
          Center(
            child: GestureDetector(
              onTap: () => AssistiveBallDialog.show(context),
              child: Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: AppTheme.darkCard,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.primaryColor, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryColor.withValues(alpha: 0.25),
                      blurRadius: 16,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(Icons.bolt, color: AppTheme.primaryColor, size: 28),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Center(
            child: Text(
              'Tap the Assistive Ball above to test the dialog',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppTheme.textSecondary),
            ),
          ),

          const SizedBox(height: 24),

          // Android System Overlay Permission Toggle
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.darkCard,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.darkBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.layers_outlined, color: AppTheme.primaryColor, size: 18),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Display Over Other Apps (Chrome)',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Allows the assistive ball to remain accessible while filling forms in Chrome.',
                  style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await OverlayService.requestOverlayPermission();
                      final can = await OverlayService.canDrawOverlays();
                      if (can) {
                        await OverlayService.startAssistiveBall();
                      }
                      if (mounted) {
                        setState(() => _overlayPermitted = can);
                      }
                    },
                    icon: Icon(_overlayPermitted ? Icons.check : Icons.open_in_new, size: 14),
                    label: Text(
                      _overlayPermitted
                          ? 'Overlay Active Over Other Apps'
                          : 'Enable Floating Ball Permission',
                      style: const TextStyle(fontSize: 12),
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
}
