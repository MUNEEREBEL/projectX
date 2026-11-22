import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../core/database/database_service.dart';
import '../../core/services/folder_sync_service.dart';
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
  String? _selectedFolderPath;
  bool _isScanning = false;
  String _scanStatus = '';

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_completed', true);
    if (_nameController.text.trim().isNotEmpty) {
      await prefs.setString('vault_owner_name', _nameController.text.trim());
      
      // Ensure primary Person record exists
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
        duration: const Duration(milliseconds: 300),
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
                  _buildStepFolder(),
                  _buildStepScan(),
                  _buildStepCopilotTest(),
                ],
              ),
            ),

            // Bottom Navigation Actions
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Row(
                children: [
                  if (_currentStep > 0 && _currentStep < 3)
                    TextButton(
                      onPressed: () {
                        _pageController.previousPage(
                          duration: const Duration(milliseconds: 300),
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
                          const SnackBar(content: Text('Please enter your name to proceed.')),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          const Text(
            'Welcome to PrivDoc Vault',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Enter your full name as it appears on your official identity cards. This acts as the anchor to cleanly separate your cards from family members.',
            style: TextStyle(fontSize: 14, color: AppTheme.textSecondary, height: 1.5),
          ),
          const SizedBox(height: 36),
          const Text(
            'PRIMARY CARDHOLDER NAME',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.textMuted, letterSpacing: 0.5),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.w500),
            decoration: const InputDecoration(
              hintText: 'e.g. Rahul Sharma',
              prefixIcon: Icon(Icons.person_outline, color: AppTheme.textSecondary, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  // STEP 2: Scoped Folder Selection
  Widget _buildStepFolder() {
    return Padding(
      padding: const EdgeInsets.all(28.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          const Text(
            'Select Document Folder',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Choose the folder on your device that contains your identity and policy files (.pdf, .png, .jpg, .docx). PrivDoc only monitors this single folder.',
            style: TextStyle(fontSize: 14, color: AppTheme.textSecondary, height: 1.5),
          ),
          const SizedBox(height: 36),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppTheme.darkCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.darkBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.folder_outlined, color: AppTheme.primaryColor, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _selectedFolderPath ?? 'No folder linked yet',
                        style: TextStyle(
                          fontSize: 13,
                          color: _selectedFolderPath != null ? AppTheme.textPrimary : AppTheme.textMuted,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await FolderSyncService.pickFolder();
                      if (picked != null) {
                        setState(() => _selectedFolderPath = picked);
                      }
                    },
                    icon: const Icon(Icons.folder_open, size: 16),
                    label: Text(_selectedFolderPath == null ? 'Browse & Select Folder' : 'Change Folder'),
                  ),
                ),
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
          const SizedBox(height: 24),
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
            'We will now index the documents in your folder, extract key fields, and organize them under your name and family profiles.',
            style: TextStyle(fontSize: 14, color: AppTheme.textSecondary, height: 1.5),
          ),
          const SizedBox(height: 36),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.darkCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.darkBorder),
            ),
            child: Column(
              children: [
                Icon(
                  _isScanning ? Icons.sync : Icons.check_circle_outline,
                  color: _isScanning ? AppTheme.primaryColor : AppTheme.successColor,
                  size: 40,
                ),
                const SizedBox(height: 12),
                Text(
                  _isScanning ? 'Syncing Documents...' : 'Ready to Index',
                  style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white, fontSize: 16),
                ),
                const SizedBox(height: 6),
                Text(
                  _scanStatus.isNotEmpty ? _scanStatus : 'Tap Start Scan to verify files in selected folder.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 16),
                if (!_isScanning)
                  ElevatedButton.icon(
                    onPressed: _startScan,
                    icon: const Icon(Icons.play_arrow, size: 16),
                    label: const Text('Start Folder Scan'),
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
      _scanStatus = 'Scanning files...';
    });

    FolderSyncService.syncFolder(folderPath: _selectedFolderPath).listen(
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
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
            'When enabled, a discreet assistive ball floats on the edge of your screen while using Chrome or banking portals. Tap it to test the quick-copy and file upload card now.',
            style: TextStyle(fontSize: 14, color: AppTheme.textSecondary, height: 1.5),
          ),
          const SizedBox(height: 36),
          Center(
            child: GestureDetector(
              onTap: () => AssistiveBallDialog.show(context),
              child: Container(
                width: 72,
                height: 72,
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
                child: const Icon(Icons.touch_app, color: AppTheme.primaryColor, size: 30),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Center(
            child: Text(
              'Tap the Assistive Ball above to test',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppTheme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
