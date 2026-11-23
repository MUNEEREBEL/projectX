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
  double _progressValue = 0.35; // Default aesthetic preview value matching reference
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
    FocusScope.of(context).unfocus();
    setState(() {
      _scanStatus = 'Accessing folder...';
      _isScanning = true;
      _scanComplete = false;
      _progressValue = 0.1;
      _dynamicInsights.clear();
    });

    final result = await FolderSyncService.pickFolderAndDiscover();
    if (result == null) {
      if (mounted) {
        setState(() {
          _isScanning = false;
          _scanStatus = '';
          _progressValue = 0.35;
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
          _scanStatus = 'No documents (.pdf, .png, .jpg) in "${result.folderDisplayName}"';
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isScanning = true;
        _scanStatus = 'Scanning: 1 / ${result.files.length} documents...';
      });
    }

    final stream = FolderSyncService.syncFiles(result.files);
    stream.listen(
      (progress) {
        if (mounted) {
          setState(() {
            _scanStatus = 'Scanning: ${progress.processedFiles} / ${progress.totalFiles} documents...';
            if (progress.logMessage != null && progress.logMessage!.isNotEmpty) {
              final cleanMsg = progress.logMessage!
                  .replaceAll('✓', '')
                  .replaceAll('📄', '')
                  .replaceAll('⚡', '')
                  .trim();
              if (cleanMsg.isNotEmpty && !_dynamicInsights.contains(cleanMsg)) {
                _dynamicInsights.insert(0, cleanMsg);
                if (_dynamicInsights.length > 3) _dynamicInsights.removeLast();
              }
            }
            if (progress.totalFiles > 0) {
              _progressValue = (progress.processedFiles / progress.totalFiles).clamp(0.05, 1.0);
            }
            if (progress.isCompleted) {
              _isScanning = false;
              _scanComplete = true;
              _progressValue = 1.0;
            }
          });

          if (progress.isCompleted) {
            Future.delayed(const Duration(milliseconds: 1200), () {
              if (mounted) _completeOnboarding();
            });
          }
        }
      },
      onError: (e) {
        if (mounted) {
          setState(() {
            _isScanning = false;
            _scanStatus = 'Error: $e';
          });
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0.0, 0.35, 0.7, 1.0],
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
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: screenHeight - MediaQuery.of(context).padding.top - MediaQuery.of(context).padding.bottom - 24,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. TOP SEGMENTED PROGRESS STEPPER
                      _buildTopStepper(),
                      const SizedBox(height: 18),

                      // 2. BRANDING & SECURITY HEADER
                      _buildBrandHeader(),
                      const SizedBox(height: 16),

                      // 3. CARDHOLDER SETUP CARD
                      _buildCardholderSetupCard(),
                      const SizedBox(height: 14),

                      // 4. FOLDER SELECTION CARD
                      _buildFolderSelectionCard(),
                      const SizedBox(height: 14),

                      // 5. LIVE INDEXING TERMINAL CARD
                      _buildLiveIndexingTerminalCard(),
                      const SizedBox(height: 14),

                      // 6. PAGINATION DOTS
                      _buildPaginationDots(),
                    ],
                  ),

                  // 7. BOTTOM CTA BUTTON
                  Padding(
                    padding: const EdgeInsets.only(top: 14, bottom: 8),
                    child: _buildEnterVaultButton(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 1. TOP SEGMENTED PROGRESS STEPPER (Welcome, Profile, Folder Selection, Scanning)
  Widget _buildTopStepper() {
    final steps = ['Welcome', 'Profile', 'Folder Selection', 'Scanning'];

    return Row(
      children: List.generate(steps.length, (index) {
        final isActive = index <= 1; // First 2 active as in reference mockup

        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              left: index == 0 ? 0 : 3,
              right: index == steps.length - 1 ? 0 : 3,
            ),
            child: Column(
              children: [
                Container(
                  height: 16,
                  decoration: BoxDecoration(
                    color: isActive
                        ? const Color(0xFF0F172A)
                        : const Color(0xFFE2E8F0).withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isActive ? Colors.white : const Color(0xFF94A3B8),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  steps[index],
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                    color: isActive ? const Color(0xFF1E293B) : const Color(0xFF64748B),
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  // 2. BRANDING & SECURITY HEADER
  Widget _buildBrandHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Left: Stylized dual-tone folded X Logo + "Project X"
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildProjectXLogo(),
            const SizedBox(width: 8),
            const Text(
              'Project X',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
                letterSpacing: -0.6,
              ),
            ),
          ],
        ),

        // Right: "100% On-Device & Zero-Knowledge" with glowing shield badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(18),
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Text(
                    '100% On-Device',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                      height: 1.15,
                    ),
                  ),
                  Text(
                    '& Zero-Knowledge',
                    style: TextStyle(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF64748B),
                      height: 1.15,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 6),
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF3B82F6), Color(0xFF10B981)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(7),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF10B981).withValues(alpha: 0.35),
                      blurRadius: 6,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.verified_user_rounded,
                  size: 13,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Dual-tone Folded X Logo
  Widget _buildProjectXLogo() {
    return SizedBox(
      width: 28,
      height: 28,
      child: CustomPaint(
        painter: _ProjectXLogoPainter(),
      ),
    );
  }

  // 3. CARDHOLDER SETUP CARD
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
                fontWeight: FontWeight.w500,
                color: Color(0xFF0F172A),
              ),
              decoration: const InputDecoration(
                hintText: 'Alex Mercer',
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

  // 4. FOLDER SELECTION CARD
  Widget _buildFolderSelectionCard() {
    final folderText = _selectedFolderName != null
        ? '/$_selectedFolderName'
        : (_selectedFolderPath != null ? _selectedFolderPath! : '/Documents/Vault');

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
                decoration: const BoxDecoration(
                  color: Color(0xFF3B82F6),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'Selected: $folderText',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF475569),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 5. LIVE INDEXING TERMINAL CARD
  Widget _buildLiveIndexingTerminalCard() {
    final statusText = _scanStatus.isNotEmpty
        ? _scanStatus
        : (_isScanning
            ? 'Scanning: ${_discoveredFiles.length} documents...'
            : (_scanComplete
                ? 'Indexed ${_discoveredFiles.length} documents'
                : 'Scanning: 4 / 12 documents...'));

    return _buildFrostedContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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

                // Vibrant Glowing Teal/Cyan-Emerald Progress Bar
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
                      widthFactor: _progressValue.clamp(0.05, 1.0),
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
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF10B981).withValues(alpha: 0.5),
                              blurRadius: 6,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Checklist Items matching the image
                _buildTerminalCheckItem(
                  _dynamicInsights.isNotEmpty ? _dynamicInsights[0] : 'Analyzing deadlines...',
                ),
                const SizedBox(height: 6),
                _buildTerminalCheckItem(
                  _dynamicInsights.length > 1 ? _dynamicInsights[1] : 'Extracting key insights...',
                ),
                const SizedBox(height: 6),
                _buildTerminalCheckItem(
                  _dynamicInsights.length > 2 ? _dynamicInsights[2] : 'Extracting key insights...',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTerminalCheckItem(String label) {
    return Row(
      children: [
        const Icon(
          Icons.check_circle_rounded,
          size: 15,
          color: Color(0xFF10B981),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: Color(0xFF334155),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  // 6. PAGINATION DOTS
  Widget _buildPaginationDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 18,
          height: 4,
          decoration: BoxDecoration(
            color: const Color(0xFF94A3B8),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Container(
          width: 4,
          height: 4,
          decoration: const BoxDecoration(
            color: Color(0xFFCBD5E1),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Container(
          width: 4,
          height: 4,
          decoration: const BoxDecoration(
            color: Color(0xFFCBD5E1),
            shape: BoxShape.circle,
          ),
        ),
      ],
    );
  }

  // 7. BOTTOM CTA BUTTON
  Widget _buildEnterVaultButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: _completeOnboarding,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF0B132B),
          foregroundColor: Colors.white,
          elevation: 2,
          shadowColor: const Color(0xFF0B132B).withValues(alpha: 0.35),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Text(
              'Enter My Vault',
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                letterSpacing: 0.2,
              ),
            ),
            SizedBox(width: 6),
            Icon(
              Icons.arrow_forward_rounded,
              color: Colors.white,
              size: 16,
            ),
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
        color: Colors.white.withValues(alpha: 0.82),
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

// Custom Painter for the modern geometric dual-tone "X" logo
class _ProjectXLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Stroke 1: Dark Slate Navy Ribbon
    final paintDark = Paint()
      ..color = const Color(0xFF1E293B)
      ..style = PaintingStyle.fill;

    final pathDark = Path()
      ..moveTo(w * 0.1, 0)
      ..lineTo(w * 0.38, 0)
      ..lineTo(w * 0.9, h)
      ..lineTo(w * 0.62, h)
      ..close();

    canvas.drawPath(pathDark, paintDark);

    // Stroke 2: Vibrant Blue-Cyan Gradient Ribbon crossing over
    final rect = Rect.fromLTWH(0, 0, w, h);
    final paintBlue = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(rect)
      ..style = PaintingStyle.fill;

    final pathBlue = Path()
      ..moveTo(w * 0.62, 0)
      ..lineTo(w * 0.9, 0)
      ..lineTo(w * 0.38, h)
      ..lineTo(w * 0.1, h)
      ..close();

    canvas.drawPath(pathBlue, paintBlue);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
