import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../core/database/database_service.dart';
import '../../core/services/folder_sync_service.dart';
import '../../models/person.dart';
import '../../main_navigation_shell.dart';

class OnboardingSetupScreen extends StatefulWidget {
  const OnboardingSetupScreen({super.key});

  @override
  State<OnboardingSetupScreen> createState() => _OnboardingSetupScreenState();
}

class _OnboardingSetupScreenState extends State<OnboardingSetupScreen> {
  final TextEditingController _nameController = TextEditingController();

  String? _selectedFolderPath;
  String? _selectedFolderName;
  List<File> _discoveredFiles = [];
  bool _isScanning = false;
  String _scanStatus = '';
  double _progressValue = 0.0;
  bool _scanComplete = false;
  final List<String> _dynamicInsights = [];

  @override
  void initState() {
    super.initState();
    _loadExistingOwner();
  }

  Future<void> _loadExistingOwner() async {
    final prefs = await SharedPreferences.getInstance();
    final savedName = prefs.getString('vault_owner_name');
    if (savedName != null && savedName.isNotEmpty) {
      if (mounted) {
        setState(() => _nameController.text = savedName);
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _completeOnboarding() async {
    FocusScope.of(context).unfocus();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_completed', true);

    final enteredName = _nameController.text.trim();
    if (enteredName.isNotEmpty) {
      await prefs.setString('vault_owner_name', enteredName);

      final existing = await DatabaseService.instance.getAllPersons();
      if (existing.isEmpty) {
        await DatabaseService.instance.upsertPerson(
          Person(
            id: const Uuid().v4(),
            name: enteredName,
            relationship: 'Self',
            avatarColorIndex: 0,
          ),
        );
      } else {
        final primary = existing.first;
        await DatabaseService.instance.upsertPerson(
          Person(
            id: primary.id,
            name: enteredName,
            relationship: primary.relationship,
            avatarColorIndex: primary.avatarColorIndex,
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

  Future<void> _onPickFolderPressed() async {
    if (_isScanning) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Document indexing is already in progress...'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    FocusScope.of(context).unfocus();

    final result = await FolderSyncService.pickFolderAndDiscover();
    if (result == null) return;

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
          _scanStatus = 'No supported documents found in "${result.folderDisplayName}"';
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isScanning = true;
        _scanComplete = false;
        _progressValue = 0.0;
        _dynamicInsights.clear();
        _scanStatus = 'Analyzing documents with Vision AI...';
      });
    }

    final stream = FolderSyncService.syncFiles(result.files);
    stream.listen(
      (progress) {
        if (mounted) {
          setState(() {
            _scanStatus = progress.status;
            if (progress.logMessage != null && progress.logMessage!.isNotEmpty) {
              final cleanMsg = progress.logMessage!
                  .replaceAll('✓', '')
                  .replaceAll('📄', '')
                  .replaceAll('⚡', '')
                  .replaceAll('🎉', '')
                  .trim();
              if (cleanMsg.isNotEmpty && !_dynamicInsights.contains(cleanMsg)) {
                _dynamicInsights.insert(0, cleanMsg);
                if (_dynamicInsights.length > 4) _dynamicInsights.removeLast();
              }
            }
            if (progress.totalFiles > 0) {
              _progressValue = (progress.processedFiles / progress.totalFiles).clamp(0.0, 1.0);
            }
            if (progress.isCompleted) {
              _isScanning = false;
              _scanComplete = true;
              _progressValue = 1.0;
            }
          });
        }
      },
      onError: (e) {
        if (mounted) {
          setState(() {
            _isScanning = false;
            _scanStatus = 'Extraction error: $e';
          });
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0.0, 0.4, 0.7, 1.0],
            colors: [
              Color(0xFFEFF6FF), // soft airy blue
              Color(0xFFF8FAFC), // clean white slate
              Color(0xFFF1F5F9), // light subtle tint
              Color(0xFFEBF4FF), // soft glow bottom
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 10),

                // 1. BRANDING & SECURITY HEADER
                _buildBrandHeader(),
                const SizedBox(height: 24),

                // 2. CARDHOLDER SETUP CARD
                _buildCardholderSetupCard(),
                const SizedBox(height: 16),

                // 3. FOLDER SELECTION CARD
                _buildFolderSelectionCard(),
                const SizedBox(height: 16),

                // 4. LIVE INDEXING TERMINAL CARD (Only when files are selected/scanning)
                if (_isScanning || _scanComplete || _selectedFolderPath != null)
                  _buildLiveIndexingTerminalCard(),

                const SizedBox(height: 32),

                // 5. BOTTOM CTA BUTTON
                _buildEnterVaultButton(),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 1. BRANDING & SECURITY HEADER
  Widget _buildBrandHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Left: Logo + "Project X"
        Expanded(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  'assets/logo.png',
                  width: 32,
                  height: 32,
                  errorBuilder: (_, __, ___) => const Icon(Icons.shield, color: Color(0xFF0F172A), size: 30),
                ),
              ),
              const SizedBox(width: 8),
              const Flexible(
                child: Text(
                  'Project X',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),

        // Right: "100% On-Device & Zero-Knowledge" with glowing shield badge
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white, width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Text(
                        '100% On-Device',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                          height: 1.15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '& Zero-Knowledge',
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF64748B),
                          height: 1.15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 5),
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF3B82F6), Color(0xFF10B981)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.verified_user_rounded,
                    size: 12,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // 2. CARDHOLDER SETUP CARD
  Widget _buildCardholderSetupCard() {
    return _buildFrostedContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Cardholder Setup',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F172A),
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Primary Cardholder Name',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
            ),
            child: TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0F172A),
              ),
              decoration: const InputDecoration(
                hintText: 'Enter your full name',
                hintStyle: TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w400,
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 3. FOLDER SELECTION CARD
  Widget _buildFolderSelectionCard() {
    final folderText = _selectedFolderName != null
        ? '/$_selectedFolderName'
        : (_selectedFolderPath != null ? _selectedFolderPath! : 'No folder chosen yet');

    return _buildFrostedContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Folder Selection',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F172A),
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: _onPickFolderPressed,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFEDF2F7), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.folder_open_rounded,
                      size: 22,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Choose Local Document Folder',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Select directory to search, find expiry dates & get easy answers',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: Color(0xFF64748B),
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: _selectedFolderName != null ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Selected: $folderText',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF475569),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 4. LIVE INDEXING TERMINAL CARD
  Widget _buildLiveIndexingTerminalCard() {
    final statusText = _scanStatus.isNotEmpty
        ? _scanStatus
        : (_isScanning
            ? 'Scanning: ${_discoveredFiles.length} documents...'
            : (_scanComplete
                ? 'Indexing complete (${_discoveredFiles.length} files saved)'
                : 'Ready to scan folder'));

    return _buildFrostedContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Live Indexing Terminal',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.2,
                ),
              ),
              if (_isScanning)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0F172A)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC).withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0).withValues(alpha: 0.8)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  statusText,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 8),

                // Glowing Progress Bar
                Stack(
                  children: [
                    Container(
                      height: 5,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: _progressValue.clamp(0.0, 1.0),
                      child: Container(
                        height: 5,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFF00F2FE),
                              Color(0xFF4FACFE),
                              Color(0xFF10B981),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Dynamic Checklist Items
                if (_dynamicInsights.isNotEmpty)
                  ..._dynamicInsights.map((insight) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_rounded, size: 14, color: Color(0xFF10B981)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              insight,
                              style: const TextStyle(fontSize: 11.5, color: Color(0xFF334155), fontWeight: FontWeight.w500),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  })
                else
                  Row(
                    children: const [
                      Icon(Icons.check_circle_rounded, size: 14, color: Color(0xFF10B981)),
                      SizedBox(width: 8),
                      Text('Ready to discover documents in vault', style: TextStyle(fontSize: 11.5, color: Color(0xFF334155))),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 5. BOTTOM CTA BUTTON
  Widget _buildEnterVaultButton() {
    final bool canEnter = _scanComplete && !_isScanning;

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: canEnter ? _completeOnboarding : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: canEnter ? const Color(0xFF0F172A) : const Color(0xFFCBD5E1),
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFFE2E8F0),
          disabledForegroundColor: const Color(0xFF94A3B8),
          elevation: canEnter ? 2 : 0,
          shadowColor: const Color(0xFF0F172A).withValues(alpha: 0.35),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isScanning) ...[
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF64748B)),
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Indexing Documents in Progress...',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B),
                ),
              ),
            ] else if (_scanComplete) ...[
              const Text(
                'Enter My Vault',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.arrow_forward_rounded,
                color: Colors.white,
                size: 16,
              ),
            ] else ...[
              const Icon(
                Icons.lock_outline_rounded,
                size: 16,
                color: Color(0xFF94A3B8),
              ),
              const SizedBox(width: 8),
              const Text(
                'Select Folder to Complete Indexing',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF94A3B8),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Reusable Frosted Glass Container
  Widget _buildFrostedContainer({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}
