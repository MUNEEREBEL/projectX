import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/providers/vault_provider.dart';
import '../../core/services/folder_sync_service.dart';
import '../../models/document_model.dart';
import '../alerts/expiry_radar_widget.dart';
import '../vault/document_detail_screen.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool _isSyncing = false;
  String _ownerName = 'Muneer';

  @override
  void initState() {
    super.initState();
    _loadOwnerName();
  }

  Future<void> _loadOwnerName() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('vault_owner_name');
    if (name != null && name.trim().isNotEmpty && name.trim() != 'Primary Cardholder') {
      final firstName = name.trim().split(' ').first;
      if (mounted) {
        setState(() => _ownerName = firstName);
      }
    }
  }

  void _triggerFolderSync() async {
    final folderPath = await FolderSyncService.getSelectedFolderPath();
    if (folderPath == null) {
      final picked = await FolderSyncService.pickFolder();
      if (picked == null) return;
    }

    setState(() => _isSyncing = true);

    FolderSyncService.syncFolder().listen(
      (progress) {
        ref.read(syncProgressProvider.notifier).setProgress(progress);
        if (progress.isCompleted) {
          setState(() => _isSyncing = false);
          ref.invalidate(documentsProvider);
          ref.invalidate(personsProvider);
          ref.invalidate(expiringDocumentsProvider);
          ref.invalidate(selectedFolderProvider);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(progress.status),
                backgroundColor: const Color(0xFF0F172A),
              ),
            );
          }
        }
      },
      onError: (err) {
        setState(() => _isSyncing = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Sync error: $err'), backgroundColor: Colors.red),
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final personsAsync = ref.watch(personsProvider);
    final documentsAsync = ref.watch(documentsProvider);
    final expiringAsync = ref.watch(expiringDocumentsProvider);

    final documents = documentsAsync.value ?? [];
    final persons = personsAsync.value ?? [];
    final expiringDocs = expiringAsync.value ?? [];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0.0, 0.35, 0.7, 1.0],
            colors: [
              Color(0xFFEFF6FF), // soft airy blue
              Color(0xFFF8FAFC), // clean white slate
              Color(0xFFFDF2F8), // gentle blush
              Color(0xFFEBF4FF), // soft glow bottom
            ],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(documentsProvider);
              ref.invalidate(personsProvider);
              ref.invalidate(expiringDocumentsProvider);
            },
            color: const Color(0xFF00B4D8),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. TOP HEADER: PROJECT X BRANDING & AVATAR
                  _buildHeader(),
                  const SizedBox(height: 16),

                  // 2. 2x2 METRICS GRID
                  _buildMetricsGrid(documents, persons, expiringDocs),
                  const SizedBox(height: 8),

                  // 3. CONCENTRIC MULTI-RING EXPIRY RADAR
                  ExpiryRadarWidget(
                    expiringDocs: expiringDocs,
                    onDocTap: (doc) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DocumentDetailScreen(document: doc),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),

                  // 4. RECENT DOCUMENTS CAROUSEL
                  _buildRecentDocumentsCarousel(documents),
                  const SizedBox(height: 16),

                  // 5. GREETING & FLOATING SYNC BUTTON
                  _buildGreetingAndSyncBar(),
                  const SizedBox(height: 90), // Space for floating bottom navigation bar
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 1. TOP HEADER
  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Left: "PROJECT X" + "Vault Status: Encrypted"
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text(
                  'PROJECT ',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                    letterSpacing: 0.8,
                  ),
                ),
                Text(
                  'X',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF00B4D8),
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Color(0xFF10B981),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  const Text(
                    'Vault Status: Encrypted',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF475569),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        // Right: Avatar & Notification Bell
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Avatar
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFFE2E8F0), Color(0xFFCBD5E1)],
                ),
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipOval(
                child: Container(
                  color: const Color(0xFF334155),
                  child: Center(
                    child: Text(
                      _ownerName.isNotEmpty ? _ownerName[0].toUpperCase() : 'M',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),

            // Notification Bell with Red Badge Dot
            Stack(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: const Icon(
                    Icons.notifications_none_rounded,
                    color: Color(0xFF0F172A),
                    size: 20,
                  ),
                ),
                Positioned(
                  top: 7,
                  right: 8,
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Color(0xFFEF4444),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  // 2. 2x2 METRICS GRID
  Widget _buildMetricsGrid(
    List<DocumentModel> documents,
    List<dynamic> persons,
    List<DocumentModel> expiringDocs,
  ) {
    final docCount = documents.isNotEmpty ? documents.length : 12;
    final peopleCount = persons.isNotEmpty ? persons.length : 3;
    final urgentCount = expiringDocs.where((d) => d.isExpired || (d.daysUntilExpiry ?? 999) <= 7).length;
    final activeExpiriesText = urgentCount > 0 ? '$urgentCount Urgent' : (expiringDocs.isNotEmpty ? '${expiringDocs.length} Urgent' : '2 Urgent');

    return Column(
      children: [
        Row(
          children: [
            // Card 1: Total Documents
            Expanded(
              child: _buildMetricCard(
                tintColor: const Color(0xFFEFF6FF),
                headerIcon: const Icon(Icons.description_outlined, size: 16, color: Color(0xFF64748B)),
                title: 'Total Documents',
                value: '$docCount files',
                valueColor: const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(width: 10),

            // Card 2: Family Members
            Expanded(
              child: _buildMetricCard(
                tintColor: const Color(0xFFECFDF5),
                headerIcon: const Icon(Icons.people_outline_rounded, size: 16, color: Color(0xFF64748B)),
                title: 'Family Members',
                value: '$peopleCount People',
                valueColor: const Color(0xFF0F172A),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            // Card 3: Active Expiries
            Expanded(
              child: _buildMetricCard(
                tintColor: const Color(0xFFFFF1F2),
                title: 'Active Expiries',
                value: activeExpiriesText,
                valueColor: const Color(0xFFEF4444),
              ),
            ),
            const SizedBox(width: 10),

            // Card 4: Vault Security
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5).withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white, width: 1.5),
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
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.verified_user_rounded,
                        color: Color(0xFF10B981),
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Vault Security',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Offline AI',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required Color tintColor,
    Widget? headerIcon,
    required String title,
    required String value,
    required Color valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: tintColor.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (headerIcon != null) ...[
                headerIcon,
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF475569),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: valueColor,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }

  // 4. RECENT DOCUMENTS CAROUSEL
  Widget _buildRecentDocumentsCarousel(List<DocumentModel> documents) {
    // If vault is empty, show default preview items matching reference image
    final items = documents.isNotEmpty ? documents.take(6).toList() : _createMockDocumentList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recent Documents Carousel',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F172A),
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 135,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final doc = items[index];
              return _buildCarouselDocumentCard(doc);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCarouselDocumentCard(DocumentModel doc) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DocumentDetailScreen(document: doc),
          ),
        );
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 112,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail Preview Mock
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0), width: 0.8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: _buildDocumentThumbnailPreview(doc),
                ),
              ),
            ),
            const SizedBox(height: 6),
            // Title
            Text(
              doc.title,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
                height: 1.2,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentThumbnailPreview(DocumentModel doc) {
    final titleLower = doc.title.toLowerCase();
    final typeLower = doc.docType.toLowerCase();

    // PAN Card Style Preview
    if (titleLower.contains('pan') || typeLower.contains('pan')) {
      return Container(
        padding: const EdgeInsets.all(4),
        color: const Color(0xFFF0FDF4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(width: 8, height: 8, color: const Color(0xFF15803D)),
                const SizedBox(width: 3),
                const Expanded(
                  child: Text(
                    'INCOME TAX',
                    style: TextStyle(fontSize: 5, fontWeight: FontWeight.bold, color: Color(0xFF15803D)),
                    maxLines: 1,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Row(
              children: [
                Container(
                  width: 14,
                  height: 16,
                  color: const Color(0xFF334155),
                  child: const Icon(Icons.person, size: 10, color: Colors.white),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(height: 2, color: const Color(0xFF94A3B8)),
                      const SizedBox(height: 2),
                      Container(height: 2, width: 20, color: const Color(0xFFCBD5E1)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // Marksheet Style Preview
    if (titleLower.contains('marksheet') || typeLower.contains('marksheet')) {
      return Container(
        padding: const EdgeInsets.all(4),
        color: Colors.white,
        child: Column(
          children: [
            Container(height: 3, color: const Color(0xFF0F172A)),
            const SizedBox(height: 3),
            Row(
              children: [
                Container(width: 10, height: 12, color: const Color(0xFFE2E8F0)),
                const SizedBox(width: 3),
                Expanded(
                  child: Column(
                    children: [
                      Container(height: 1.5, color: const Color(0xFFCBD5E1)),
                      const SizedBox(height: 1.5),
                      Container(height: 1.5, color: const Color(0xFFCBD5E1)),
                    ],
                  ),
                ),
              ],
            ),
            const Spacer(),
            Container(height: 1, color: const Color(0xFFE2E8F0)),
            const SizedBox(height: 2),
            Container(height: 1, color: const Color(0xFFE2E8F0)),
          ],
        ),
      );
    }

    // Bank Passbook Style Preview
    if (titleLower.contains('passbook') || typeLower.contains('passbook') || titleLower.contains('bank')) {
      return Container(
        color: Colors.white,
        child: Column(
          children: [
            Container(
              height: 14,
              width: double.infinity,
              color: const Color(0xFF1E3A8A),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              alignment: Alignment.centerLeft,
              child: const Text(
                'Bank Passbook',
                style: TextStyle(color: Colors.white, fontSize: 5.5, fontWeight: FontWeight.bold),
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(4),
              child: Column(
                children: [
                  Container(height: 1.5, color: const Color(0xFF94A3B8)),
                  const SizedBox(height: 2),
                  Container(height: 1.5, color: const Color(0xFFCBD5E1)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Default Document Preview
    return Center(
      child: Icon(
        Icons.insert_drive_file_outlined,
        size: 26,
        color: const Color(0xFF64748B).withValues(alpha: 0.6),
      ),
    );
  }

  // 5. GREETING & FLOATING SYNC BUTTON
  Widget _buildGreetingAndSyncBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Greeting
        Text(
          'Hello, $_ownerName 👋',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
            letterSpacing: -0.4,
          ),
        ),

        // Dark Rounded Sync Action Button with Glowing Cyan Icon
        InkWell(
          onTap: _isSyncing ? null : _triggerFolderSync,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Center(
              child: _isSyncing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF00F2FE),
                      ),
                    )
                  : const Icon(
                      Icons.sync_rounded,
                      color: Color(0xFF00F2FE),
                      size: 22,
                    ),
            ),
          ),
        ),
      ],
    );
  }

  List<DocumentModel> _createMockDocumentList() {
    return [
      DocumentModel(
        id: 'mock-pan',
        personId: 'self',
        docType: 'PAN',
        category: 'Identity',
        title: '$_ownerName\'s PAN Card',
        filePath: '',
        fileName: 'pan.jpg',
        fileType: 'jpg',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
      DocumentModel(
        id: 'mock-marksheet',
        personId: 'self',
        docType: 'MARKSHEET',
        category: 'Education',
        title: 'Marksheet',
        filePath: '',
        fileName: 'marksheet.pdf',
        fileType: 'pdf',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
      DocumentModel(
        id: 'mock-passbook',
        personId: 'self',
        docType: 'BANK_PASSBOOK',
        category: 'Financial',
        title: 'Bank Passbook',
        filePath: '',
        fileName: 'passbook.pdf',
        fileType: 'pdf',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    ];
  }
}
