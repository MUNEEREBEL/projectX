import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/providers/vault_provider.dart';
import '../../core/services/folder_sync_service.dart';
import '../../core/theme/app_theme.dart';
import '../alerts/expiry_radar_widget.dart';
import '../overlay/assistive_ball_dialog.dart';
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
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.shield_outlined, color: AppTheme.primaryColor, size: 18),
            ),
            const SizedBox(width: 10),
            Text(
              _ownerName,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
          ],
        ),
        actions: [
          // Floating Copilot Assistive Button
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: OutlinedButton.icon(
              onPressed: () => AssistiveBallDialog.show(context),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppTheme.primaryColor),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              ),
              icon: const Icon(Icons.bolt, size: 14, color: AppTheme.primaryColor),
              label: const Text(
                'Copilot',
                style: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.w600, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(documentsProvider);
          ref.invalidate(personsProvider);
          ref.invalidate(expiringDocumentsProvider);
        },
        color: AppTheme.primaryColor,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            // 1. Scoped Folder Bar
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(14),
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
                      const Icon(Icons.folder_outlined, color: AppTheme.accentColor, size: 18),
                      const SizedBox(width: 8),
                      const Text(
                        'SCOPED VAULT FOLDER',
                        style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textMuted, fontSize: 10, letterSpacing: 0.6),
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
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          child: Text('Change', style: TextStyle(color: AppTheme.primaryColor, fontSize: 11, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  folderAsync.when(
                    data: (path) => Text(
                      path ?? 'No folder selected. Tap Change to link your documents folder.',
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    loading: () => const Text('Checking folder...', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                    error: (_, __) => const Text('Error loading folder', style: TextStyle(color: Colors.red, fontSize: 12)),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 36,
                    child: OutlinedButton.icon(
                      onPressed: _isSyncing ? null : _triggerFolderSync,
                      icon: _isSyncing
                          ? const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryColor),
                            )
                          : const Icon(Icons.sync, size: 14),
                      label: Text(
                        _isSyncing
                            ? (syncProgress?.status ?? 'Syncing...')
                            : 'Sync Folder (.pdf, .png, .jpg, .docx)',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
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
                      padding: EdgeInsets.only(left: 16, top: 8, bottom: 4),
                      child: Text(
                        'PROFILES',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: AppTheme.textMuted),
                      ),
                    ),
                    SizedBox(
                      height: 42,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          ChoiceChip(
                            label: const Text('All Family'),
                            selected: selectedPersonId == null,
                            onSelected: (_) => ref.read(selectedPersonIdProvider.notifier).state = null,
                          ),
                          const SizedBox(width: 6),
                          ...persons.map((p) {
                            final isSelected = selectedPersonId == p.id;
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
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

            const SizedBox(height: 12),

            // 4. Stored Documents
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Text(
                    'STORED DOCUMENTS',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: AppTheme.textMuted),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const VaultScreen()),
                      );
                    },
                    child: const Text('View All', style: TextStyle(color: AppTheme.primaryColor, fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),

            documentsAsync.when(
              data: (docs) {
                if (docs.isEmpty) {
                  return Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: AppTheme.darkCard,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.darkBorder),
                    ),
                    child: const Column(
                      children: [
                        Icon(Icons.folder_open, size: 40, color: AppTheme.textMuted),
                        SizedBox(height: 10),
                        Text(
                          'No documents in vault yet',
                          style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Select your documents folder and tap "Sync Folder" to automatically extract cards.',
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
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.darkCard,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.darkBorder),
                      ),
                      child: ListTile(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => DocumentDetailScreen(document: doc)),
                          );
                        },
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                        leading: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: AppTheme.darkBg,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.darkBorder),
                          ),
                          child: Icon(_getDocIcon(doc.docType), color: AppTheme.primaryColor, size: 18),
                        ),
                        title: Text(
                          doc.title,
                          style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary, fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 2),
                            Text(
                              doc.idNumber ?? doc.category,
                              style: const TextStyle(color: AppTheme.textMuted, fontSize: 11, fontFamily: 'monospace'),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              doc.expiryDate != null
                                  ? (doc.isExpired ? 'Expired' : 'Expires in ${doc.daysUntilExpiry} days')
                                  : 'Lifetime Validity (No Expiry)',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: doc.expiryDate != null
                                    ? (doc.isExpired ? AppTheme.dangerColor : AppTheme.warningColor)
                                    : AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 12, color: AppTheme.textMuted),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(32.0),
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryColor),
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
      case 'AADHAAR': return Icons.badge;
      case 'PAN': return Icons.credit_card;
      case 'DRIVING_LICENSE': return Icons.directions_car;
      case 'PASSPORT': return Icons.flight;
      case 'VEHICLE_RC': return Icons.two_wheeler;
      case 'VEHICLE_INSURANCE': return Icons.security;
      case 'HEALTH_INSURANCE': return Icons.medical_services;
      default: return Icons.description;
    }
  }
}
