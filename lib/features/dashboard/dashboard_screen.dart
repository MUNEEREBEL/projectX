import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/providers/vault_provider.dart';
import '../../core/services/folder_sync_service.dart';
import '../../models/document_model.dart';
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.invalidate(allDocumentsProvider);
      ref.invalidate(documentsProvider);
      ref.invalidate(personsProvider);
      ref.invalidate(expiringDocumentsProvider);
    });
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
          ref.invalidate(allDocumentsProvider);
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
    final documentsAsync = ref.watch(allDocumentsProvider);
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
                  const SizedBox(height: 14),

                  // 3. DOCUMENTS NEEDING ATTENTION / EXPIRY ALERTS
                  _buildDocumentsNeedingAttention(expiringDocs),
                  const SizedBox(height: 16),

                  // 4. RECENT DOCUMENTS CAROUSEL
                  _buildRecentDocumentsCarousel(documents),
                  const SizedBox(height: 16),

                  // 5. GREETING & FLOATING SYNC BUTTON
                  _buildGreetingAndSyncBar(),
                  const SizedBox(height: 76), // Clean clearance for bottom bar
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
        // Left: "PROJECT X"
        Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Text(
              'PROJECT ',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
                letterSpacing: 0.8,
              ),
            ),
            Text(
              'X',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Color(0xFF00B4D8),
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),

        // Right: Avatar (Notification bell removed per request)
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
      ],
    );
  }

  // 2. CLEAN 2-CARD METRICS ROW (Vault Security & Family Members removed per request)
  Widget _buildMetricsGrid(
    List<DocumentModel> documents,
    List<dynamic> persons,
    List<DocumentModel> expiringDocs,
  ) {
    final docCount = documents.length;
    final urgentCount = expiringDocs.where((d) => d.isExpired || (d.daysUntilExpiry ?? 999) <= 7).length;
    final activeExpiriesText = urgentCount > 0
        ? '$urgentCount Urgent'
        : (expiringDocs.isNotEmpty ? '${expiringDocs.length} Attention' : 'All Valid');

    return Row(
      children: [
        // Card 1: Total Documents
        Expanded(
          child: _buildMetricCard(
            tintColor: const Color(0xFFEFF6FF),
            headerIcon: const Icon(Icons.description_outlined, size: 16, color: Color(0xFF3B82F6)),
            title: 'Total Documents',
            value: '$docCount files',
            valueColor: const Color(0xFF0F172A),
          ),
        ),
        const SizedBox(width: 12),

        // Card 2: Active Expiries
        Expanded(
          child: _buildMetricCard(
            tintColor: urgentCount > 0 ? const Color(0xFFFFF1F2) : const Color(0xFFECFDF5),
            headerIcon: Icon(
              urgentCount > 0 ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
              size: 16,
              color: urgentCount > 0 ? const Color(0xFFEF4444) : const Color(0xFF10B981),
            ),
            title: 'Active Expiries',
            value: activeExpiriesText,
            valueColor: urgentCount > 0 ? const Color(0xFFEF4444) : const Color(0xFF10B981),
          ),
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

  // 3. DOCUMENTS NEEDING ATTENTION / EXPIRY ALERTS
  Widget _buildDocumentsNeedingAttention(List<DocumentModel> expiringDocs) {
    // Filter to expired or expiring in <= 60 days
    final attentionDocs = expiringDocs.where((d) => d.isExpired || (d.daysUntilExpiry ?? 999) <= 60).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(
              child: Text(
                'Documents Needing Attention',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (attentionDocs.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${attentionDocs.length} Action Required',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFDC2626),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        if (attentionDocs.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
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
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'All Documents Up To Date',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'No expired cards or urgent renewals detected in your vault.',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )
        else
          Column(
            children: attentionDocs.take(4).map((doc) {
              final isExpired = doc.isExpired;
              final days = doc.daysUntilExpiry ?? 0;
              final badgeText = isExpired ? 'EXPIRED' : (days <= 0 ? 'DUE TODAY' : 'Expires in ${days}d');
              final badgeBg = isExpired ? const Color(0xFFFEE2E2) : const Color(0xFFFEF3C7);
              final badgeFg = isExpired ? const Color(0xFFDC2626) : const Color(0xFFD97706);

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isExpired ? const Color(0xFFFECACA) : const Color(0xFFE2E8F0),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0F172A).withValues(alpha: 0.03),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DocumentDetailScreen(document: doc),
                      ),
                    );
                  },
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: badgeBg,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          isExpired ? Icons.warning_amber_rounded : Icons.schedule_rounded,
                          color: badgeFg,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              doc.title,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0F172A),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              doc.idNumber != null && doc.idNumber!.isNotEmpty
                                  ? 'ID: ${doc.idNumber}'
                                  : doc.fileName,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF64748B),
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: badgeBg,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          badgeText,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: badgeFg,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }

  // 4. RECENT DOCUMENTS CAROUSEL (Driven by real documents from user's vault)
  Widget _buildRecentDocumentsCarousel(List<DocumentModel> documents) {
    if (documents.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.drive_folder_upload_rounded, color: Color(0xFF3B82F6), size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'No Documents Synced Yet',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Tap the sync button below to scan and auto-extract your cards.',
                    style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final items = documents.take(10).toList();

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
          height: 138,
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
        width: 114,
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
            // Real Document Thumbnail / Image Preview
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
    final file = File(doc.filePath);
    final ext = doc.fileType.toLowerCase();
    final isImage = ['jpg', 'jpeg', 'png', 'webp', 'bmp'].contains(ext);

    // If original image file exists on device, display real photo!
    if (file.existsSync() && isImage) {
      return Image.file(
        file,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildFallbackDocIcon(doc),
      );
    }

    // PDF or other documents: clean aesthetic card with file type
    return _buildFallbackDocIcon(doc);
  }

  Widget _buildFallbackDocIcon(DocumentModel doc) {
    final isPdf = doc.fileType.toLowerCase() == 'pdf';
    return Container(
      color: isPdf ? const Color(0xFFFFF1F2) : const Color(0xFFEFF6FF),
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isPdf ? Icons.picture_as_pdf_rounded : Icons.description_rounded,
            size: 26,
            color: isPdf ? const Color(0xFFEF4444) : const Color(0xFF3B82F6),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Text(
              doc.fileType.toUpperCase(),
              style: TextStyle(
                fontSize: 8.5,
                fontWeight: FontWeight.w800,
                color: isPdf ? const Color(0xFFEF4444) : const Color(0xFF3B82F6),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 5. GREETING & FLOATING SYNC BUTTON
  Widget _buildGreetingAndSyncBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Greeting
        Expanded(
          child: Text(
            'Hello, $_ownerName 👋',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
              letterSpacing: -0.4,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 10),

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
}
