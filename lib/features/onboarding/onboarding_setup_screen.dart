import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../core/config/app_config.dart';
import '../../core/database/database_service.dart';
import '../../core/services/folder_sync_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/glass_card.dart';
import '../../models/person.dart';
import '../../main_navigation_shell.dart';

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
  String? _selectedFolderName;
  List<File> _discoveredFiles = [];
  bool _isScanning = false;
  String _scanStatus = '';
  double _progressValue = 0.0;
  bool _scanComplete = false;
  bool _hasApiKey = false;
  final List<String> _logs = [];
  final ScrollController _logScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _checkInitialState();
  }

  Future<void> _checkInitialState() async {
    final key = await AppConfig.getApiKey();
    if (mounted) {
      setState(() {
        _hasApiKey = key != null && key.isNotEmpty;
        if (key != null) _apiKeyController.text = key;
      });
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    _apiKeyController.dispose();
    _logScrollController.dispose();
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

  void _goToStep(int step) {
    FocusScope.of(context).unfocus();
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
    setState(() => _currentStep = step);
  }

  /// Automatically triggered as soon as the user selects a folder!
  Future<void> _onPickFolderPressed() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _scanStatus = 'Accessing folder...';
      _isScanning = true;
      _scanComplete = false;
      _progressValue = 0.0;
    });

    final result = await FolderSyncService.pickFolderAndDiscover();
    if (result == null) {
      if (mounted) {
        setState(() {
          _isScanning = false;
          _scanStatus = '';
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _selectedFolderPath = result.folderPathOrUri;
        _selectedFolderName = result.folderDisplayName;
        _discoveredFiles = result.files;
      });
    }

    if (result.files.isEmpty) {
      if (mounted) {
        setState(() {
          _isScanning = false;
          _scanStatus = 'No document files (.pdf, .png, .jpg, .docx) found in "${result.folderDisplayName}".';
        });
      }
      return;
    }

    // AUTOMATIC SCAN & EXTRACTION (Zero extra clicks required)
    if (mounted) {
      setState(() {
        _isScanning = true;
        _scanStatus = 'Discovered ${result.files.length} document(s). Starting AI extraction...';
      });
    }

    final stream = FolderSyncService.syncFiles(result.files);
    stream.listen(
      (progress) {
        if (mounted) {
          setState(() {
            _scanStatus = progress.status;
            if (progress.logMessage != null) {
              _logs.add(progress.logMessage!);
            }
            if (progress.totalFiles > 0) {
              _progressValue = progress.processedFiles / progress.totalFiles;
            }
            if (progress.isCompleted) {
              _isScanning = false;
              _scanComplete = true;
            }
          });

          // Auto-scroll logs
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_logScrollController.hasClients) {
              _logScrollController.animateTo(
                _logScrollController.position.maxScrollExtent,
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
              );
            }
          });

          // Auto-advance to vault when complete
          if (progress.isCompleted) {
            Future.delayed(const Duration(milliseconds: 1500), () {
              if (mounted) {
                _completeOnboarding();
              }
            });
          }
        }
      },
      onError: (e) {
        if (mounted) {
          setState(() {
            _isScanning = false;
            _scanStatus = 'Extraction error: $e';
            _logs.add('⚠️ Extraction error: $e');
          });
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return GlassBackgroundWrapper(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              // Top Progress Indicator (2 steps)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Row(
                  children: List.generate(2, (index) {
                    final isActive = index <= _currentStep;
                    return Expanded(
                      child: Container(
                        height: 3,
                        margin: EdgeInsets.only(right: index < 1 ? 8 : 0),
                        decoration: BoxDecoration(
                          color: isActive ? AppTheme.primaryColor : AppTheme.glassBorder,
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
                    _buildStepFolderAutoScan(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // STEP 1: Primary Cardholder Name & API Key check
  Widget _buildStepName() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
      child: ListView(
        children: [
          const SizedBox(height: 12),
          const Text(
            'Primary Cardholder',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Enter your full name as it appears on your official identity documents (Aadhaar, PAN, DL). This automatically resolves inverted naming patterns (e.g. Shaik Muneer vs Muneer Shaik).',
            style: TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.45),
          ),
          const SizedBox(height: 28),

          const Text(
            'PRIMARY CARDHOLDER NAME',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textMuted, letterSpacing: 0.6),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            style: const TextStyle(fontSize: 15, color: AppTheme.textPrimary, fontWeight: FontWeight.w500),
            decoration: const InputDecoration(
              hintText: 'e.g. Muneer Shaik or Rahul Sharma',
              prefixIcon: Icon(Icons.person_outline, color: AppTheme.primaryColor, size: 20),
            ),
          ),
          const SizedBox(height: 20),

          // API Key status card
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.bolt, color: AppTheme.primaryColor, size: 18),
                    const SizedBox(width: 8),
                    const Text(
                      'AI Vision Engine',
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
                        _hasApiKey ? 'READY' : 'KEY REQUIRED',
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
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: AppTheme.textPrimary),
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
                    'Get a free Gemini key at aistudio.google.com, or leave blank if configured in .env',
                    style: TextStyle(fontSize: 10, color: AppTheme.textMuted),
                  ),
                ] else
                  const Text(
                    'Sub-second lightweight vision OCR configured with zero cloud retention.',
                    style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: () async {
                final enteredName = _nameController.text.trim();
                if (enteredName.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter your full name to proceed.')),
                  );
                  return;
                }
                if (!_hasApiKey && _apiKeyController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please provide your free Gemini API key to proceed.')),
                  );
                  return;
                }

                // Immediately save owner name and API key to preferences
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('vault_owner_name', enteredName);
                if (_apiKeyController.text.trim().isNotEmpty) {
                  await AppConfig.setApiKey(_apiKeyController.text.trim());
                }

                // Ensure Person record in SQLite has user's actual name right now
                final persons = await DatabaseService.instance.getAllPersons();
                if (persons.isEmpty) {
                  await DatabaseService.instance.upsertPerson(
                    Person(
                      id: const Uuid().v4(),
                      name: enteredName,
                      relationship: 'Self',
                      avatarColorIndex: 0,
                    ),
                  );
                } else {
                  final primary = persons.first;
                  await DatabaseService.instance.upsertPerson(
                    Person(
                      id: primary.id,
                      name: enteredName,
                      relationship: primary.relationship,
                      avatarColorIndex: primary.avatarColorIndex,
                    ),
                  );
                }

                _goToStep(1);
              },
              child: const Text('Continue to Folder Selection', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  // STEP 2: Automatic Scoped Folder Scan & Index
  Widget _buildStepFolderAutoScan() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
      child: ListView(
        children: [
          const SizedBox(height: 12),
          const Text(
            'Select Document Folder',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Choose your folder on device. Project X will automatically discover all files (.pdf, .png, .jpg, .docx) and index them into your offline vault.',
            style: TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.45),
          ),
          const SizedBox(height: 20),

          // Primary Folder Selection Card
          GlassCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppTheme.primaryColor.withValues(alpha: 0.3),
                        AppTheme.accentColor.withValues(alpha: 0.15),
                      ],
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.4)),
                  ),
                  child: Icon(
                    _scanComplete
                        ? Icons.check_circle_outline
                        : (_isScanning ? Icons.sync : Icons.folder_open),
                    color: _scanComplete
                        ? AppTheme.successColor
                        : (_isScanning ? AppTheme.accentColor : AppTheme.primaryColor),
                    size: 26,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _selectedFolderName != null
                      ? 'Folder: $_selectedFolderName'
                      : 'Choose Monitored Folder',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: Colors.white),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  _scanStatus.isNotEmpty
                      ? _scanStatus
                      : 'Tap below to select your folder. Indexing starts automatically.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _scanStatus.startsWith('No document') ? AppTheme.warningColor : AppTheme.textSecondary,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),

                if (_isScanning) ...[
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _progressValue > 0 ? _progressValue : null,
                      backgroundColor: AppTheme.glassBorder,
                      color: AppTheme.primaryColor,
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${(_progressValue * 100).toInt()}% completed',
                    style: const TextStyle(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.w600),
                  ),
                ],

                const SizedBox(height: 16),

                if (!_isScanning && !_scanComplete)
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _onPickFolderPressed,
                      icon: const Icon(Icons.folder_open, size: 18),
                      label: Text(_selectedFolderPath != null ? 'Change Folder & Rescan' : 'Select Folder from Device'),
                    ),
                  ),

                if (_scanComplete) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.successColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.successColor.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle, color: AppTheme.successColor, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          '${_discoveredFiles.length} Document(s) Stored in Offline Vault',
                          style: const TextStyle(color: AppTheme.successColor, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _completeOnboarding,
                      child: const Text('Open Vault Now'),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // LIVE REAL-TIME API & VAULT LOGS
          if (_logs.isNotEmpty) ...[
            const SizedBox(height: 16),
            GlassCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.terminal, size: 14, color: AppTheme.accentColor),
                      const SizedBox(width: 6),
                      const Text(
                        'LIVE VAULT & AI EXECUTION LOGS',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textMuted,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const Spacer(),
                      if (_isScanning)
                        const SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(strokeWidth: 1.5, color: AppTheme.accentColor),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    height: 140,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.glassBorder),
                    ),
                    child: ListView.builder(
                      controller: _logScrollController,
                      itemCount: _logs.length,
                      itemBuilder: (context, index) {
                        final line = _logs[index];
                        final isWarn = line.contains('⚠️');
                        final isGood = line.contains('✓') || line.contains('🎉') || line.contains('💾');
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            line,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontFamily: 'monospace',
                              height: 1.3,
                              color: isWarn
                                  ? AppTheme.warningColor
                                  : (isGood ? AppTheme.successColor : AppTheme.textSecondary),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),

          if (!_isScanning)
            Center(
              child: TextButton.icon(
                onPressed: () => _goToStep(0),
                icon: const Icon(Icons.arrow_back, size: 14, color: AppTheme.textSecondary),
                label: const Text('Back to Cardholder Name', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
