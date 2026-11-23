import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/providers/vault_provider.dart';
import '../../core/services/folder_sync_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/glass_card.dart';
import '../alerts/expiry_radar_widget.dart';
import '../vault/document_detail_screen.dart';
import '../vault/vault_screen.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool _isSyncing = false;
  String _ownerName = 'Primary Vault';

  @override
  void initState() {
    super.initState();
    _loadOwnerName();
  }

  Future<void> _loadOwnerName() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('vault_owner_name');
    if (name != null && mounted) {
      setState(() => _ownerName = name);
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
                backgroundColor: progress.error != null ? AppTheme.dangerColor : AppTheme.darkCard,
              ),
            );
          }
        }
      },
      onError: (err) {
        setState(() => _isSyncing = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Sync error: $err'), backgroundColor: AppTheme.dangerColor),
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final folderAsync = ref.watch(selectedFolderProvider);
    final personsAsync = ref.watch(personsProvider);
    final documentsAsync = ref.watch(documentsProvider);
    final expiringAsync = ref.watch(expiringDocumentsProvider);
    final selectedPersonId = ref.watch(selectedPersonIdProvider);
    final syncProgress = ref.watch(syncProgressProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.primaryColor.withValues(alpha: 0.4),
                    AppTheme.accentColor.withValues(alpha: 0.2),
                  ],
                ),
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.glassBorder),
              ),
              child: const Icon(Icons.shield_outlined, color: AppTheme.accentColor, size: 18),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _ownerName,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, letterSpacing: -0.3),
                ),
                const Row(
                  children: [
                    Icon(Icons.lock, size: 10, color: AppTheme.successColor),
                    SizedBox(width: 4),
                    Text(
                      'Zero-Knowledge Encrypted Vault',
                      style: TextStyle(fontSize: 10, color: AppTheme.textMuted, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(documentsProvider);
          ref.invalidate(personsProvider);
          ref.invalidate(expiringDocumentsProvider);
        },
        color: AppTheme.accentColor,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 40),
          children: [
            // 1. Frosted Scoped Folder Card
            GlassCard(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(16),
              borderRadius: 18,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppTheme.accentColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.folder_outlined, color: AppTheme.accentColor, size: 16),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'MONITORED VAULT DIRECTORY',
                        style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textMuted, fontSize: 10, letterSpacing: 0.8),
                      ),
                      const Spacer(),
                      InkWell(
                        onTap: () async {
                          final picked = await FolderSyncService.pickFolder();
                          if (picked != null) {
                            ref.invalidate(selectedFolderProvider);
                            _triggerFolderSync();
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppTheme.glassBorder),
                          ),
                          child: const Text('Change', style: TextStyle(color: AppTheme.accentColor, fontSize: 11, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  folderAsync.when(
                    data: (path) => Text(
                      path ?? 'No folder selected. Tap Change to monitor a folder.',
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    loading: () => const Text('Checking folder...', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                    error: (_, __) => const Text('Error loading folder', style: TextStyle(color: Colors.red, fontSize: 12)),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isSyncing ? null : _triggerFolderSync,
                          icon: _isSyncing
                              ? const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accentColor),
                                )
                              : const Icon(Icons.sync, size: 14, color: AppTheme.accentColor),
                          label: Text(
                            _isSyncing
                                ? (syncProgress?.status ?? 'Syncing...')
                                : 'Sync Folder',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isSyncing
                              ? null
                              : () async {
                                  final res = await FolderSyncService.pickFolderAndDiscover();
                                  if (res != null && res.files.isNotEmpty) {
                                    ref.invalidate(selectedFolderProvider);
                                    setState(() => _isSyncing = true);
                                    FolderSyncService.syncFiles(res.files).listen((p) {
                                      ref.read(syncProgressProvider.notifier).setProgress(p);
                                      if (p.isCompleted) {
                                        setState(() => _isSyncing = false);
                                        ref.invalidate(documentsProvider);
                                        ref.invalidate(personsProvider);
                                        ref.invalidate(expiringDocumentsProvider);
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text(p.status)),
                                          );
                                        }
                                      }
                                    });
                                  }
                                },
                          icon: const Icon(Icons.folder_open, size: 14),
                          label: const Text('Change Folder', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // 2. Family Members Filter Chips (Disambiguation)
            personsAsync.when(
              data: (persons) {
                if (persons.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(left: 20, top: 12, bottom: 6),
                      child: Text(
                        'IDENTITY PROFILES',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: AppTheme.textMuted),
                      ),
                    ),
                    SizedBox(
                      height: 44,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          ChoiceChip(
                            label: const Text('All Family'),
                            selected: selectedPersonId == null,
                            onSelected: (_) => ref.read(selectedPersonIdProvider.notifier).state = null,
                          ),
                          const SizedBox(width: 8),
                          ...persons.map((p) {
                            final isSelected = selectedPersonId == p.id;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text('${p.name} (${p.relationship})'),
                                selected: isSelected,
                                onSelected: (_) {
                                  ref.read(selectedPersonIdProvider.notifier).state = isSelected ? null : p.id;
                                },
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ],
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),

            const SizedBox(height: 6),

            // 3. Renewal Radar
            expiringAsync.when(
              data: (expiringDocs) => ExpiryRadarWidget(
                expiringDocs: expiringDocs,
                onDocTap: (doc) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => DocumentDetailScreen(document: doc)),
                  );
                },
              ),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),

            const SizedBox(height: 14),

            // 4. Stored Documents
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Text(
                    'ENCRYPTED DOCUMENTS',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: AppTheme.textMuted),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const VaultScreen()),
                      );
                    },
                    child: const Text('View All', style: TextStyle(color: AppTheme.accentColor, fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),

            documentsAsync.when(
              data: (docs) {
                if (docs.isEmpty) {
                  return GlassCard(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    padding: const EdgeInsets.all(28),
                    borderRadius: 18,
                    child: const Column(
                      children: [
                        Icon(Icons.folder_open, size: 40, color: AppTheme.textMuted),
                        SizedBox(height: 12),
                        Text(
                          'No documents in vault yet',
                          style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Select your documents folder or tap "Add Files" to extract your identity cards.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: docs.take(6).length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    return GlassCard(
                      margin: const EdgeInsets.only(bottom: 8),
                      borderRadius: 14,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => DocumentDetailScreen(document: doc)),
                        );
                      },
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  AppTheme.primaryColor.withValues(alpha: 0.25),
                                  AppTheme.accentColor.withValues(alpha: 0.15),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppTheme.glassBorder),
                            ),
                            child: Icon(_getDocIcon(doc.docType), color: AppTheme.accentColor, size: 20),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  doc.title,
                                  style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary, fontSize: 13),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  doc.idNumber ?? doc.category,
                                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 11, fontFamily: 'monospace'),
                                ),
                                const SizedBox(height: 3),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: doc.expiryDate != null
                                        ? (doc.isExpired ? AppTheme.dangerColor.withValues(alpha: 0.15) : AppTheme.warningColor.withValues(alpha: 0.15))
                                        : AppTheme.successColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: doc.expiryDate != null
                                          ? (doc.isExpired ? AppTheme.dangerColor.withValues(alpha: 0.3) : AppTheme.warningColor.withValues(alpha: 0.3))
                                          : AppTheme.successColor.withValues(alpha: 0.3),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Text(
                                    doc.expiryDate != null
                                        ? (doc.isExpired ? 'Expired' : 'Expires in ${doc.daysUntilExpiry} days')
                                        : 'Lifetime Validity (No Expiry)',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600,
                                      color: doc.expiryDate != null
                                          ? (doc.isExpired ? AppTheme.dangerColor : AppTheme.warningColor)
                                          : AppTheme.successColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.arrow_forward_ios, size: 12, color: AppTheme.textMuted),
                        ],
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(32.0),
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accentColor),
                ),
              ),
              error: (err, _) => Center(child: Text('Error: $err', style: const TextStyle(color: Colors.red))),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getDocIcon(String docType) {
    switch (docType.toUpperCase()) {
      case 'AADHAAR': return Icons.badge_outlined;
      case 'PAN': return Icons.credit_card_outlined;
      case 'DRIVING_LICENSE': return Icons.directions_car_outlined;
      case 'PASSPORT': return Icons.flight_outlined;
      case 'VEHICLE_RC': return Icons.two_wheeler_outlined;
      case 'VEHICLE_INSURANCE': return Icons.security_outlined;
      case 'HEALTH_INSURANCE': return Icons.medical_services_outlined;
      default: return Icons.description_outlined;
    }
  }
}
