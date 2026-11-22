import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/vault_provider.dart';
import '../../core/services/folder_sync_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/document_model.dart';
import '../alerts/expiry_radar_widget.dart';
import '../overlay/overlay_copilot_sheet.dart';
import '../vault/document_detail_screen.dart';
import '../vault/vault_screen.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool _isSyncing = false;

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
                backgroundColor: progress.error != null ? AppTheme.dangerColor : AppTheme.successColor,
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
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.shield_outlined, color: AppTheme.primaryColor, size: 22),
            ),
            const SizedBox(width: 10),
            const Text(
              'PrivDoc AI',
              style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: -0.5),
            ),
          ],
        ),
        actions: [
          // Quick Copilot Launch Button
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ElevatedButton.icon(
              onPressed: () => OverlayCopilotSheet.show(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.black,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              icon: const Icon(Icons.bolt, size: 16),
              label: const Text(
                'Copilot',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
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
            // 1. Scoped Folder Banner
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.darkCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.darkSurface),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.folder_special, color: AppTheme.accentColor, size: 20),
                      const SizedBox(width: 8),
                      const Text(
                        'Scoped Documents Folder',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () async {
                          final picked = await FolderSyncService.pickFolder();
                          if (picked != null) {
                            ref.invalidate(selectedFolderProvider);
                            _triggerFolderSync();
                          }
                        },
                        icon: const Icon(Icons.edit, size: 14, color: AppTheme.primaryColor),
                        label: const Text('Change', style: TextStyle(color: AppTheme.primaryColor, fontSize: 12)),
                        style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  folderAsync.when(
                    data: (path) => Text(
                      path ?? 'No folder selected yet. Tap "Select Folder" to link your document files.',
                      style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    loading: () => const Text('Checking folder...', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    error: (_, __) => const Text('Error loading folder', style: TextStyle(color: Colors.red, fontSize: 12)),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isSyncing ? null : _triggerFolderSync,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppTheme.primaryColor),
                        foregroundColor: AppTheme.primaryColor,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: _isSyncing
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryColor),
                            )
                          : const Icon(Icons.sync, size: 16),
                      label: Text(
                        _isSyncing
                            ? (syncProgress?.status ?? 'Syncing...')
                            : 'Sync Folder (.pdf, .jpg, .png, .docx)',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 2. Family Members Profile Filter (Disambiguation)
            personsAsync.when(
              data: (persons) {
                if (persons.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Text(
                        'Family Members',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey),
                      ),
                    ),
                    SizedBox(
                      height: 50,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          ChoiceChip(
                            label: const Text('All Members'),
                            selected: selectedPersonId == null,
                            onSelected: (_) => ref.read(selectedPersonIdProvider.notifier).state = null,
                          ),
                          const SizedBox(width: 8),
                          ...persons.map((p) {
                            final isSelected = selectedPersonId == p.id;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                avatar: CircleAvatar(
                                  backgroundColor: AppTheme.avatarColors[p.avatarColorIndex % AppTheme.avatarColors.length],
                                  child: Text(
                                    p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                                    style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                label: Text(p.name),
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

            const SizedBox(height: 8),

            // 3. Expiry & Renewal Radar
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

            const SizedBox(height: 16),

            // 4. Documents in Vault
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Text(
                    'Stored Documents',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const VaultScreen()),
                      );
                    },
                    child: const Text('See All', style: TextStyle(color: AppTheme.primaryColor)),
                  ),
                ],
              ),
            ),

            documentsAsync.when(
              data: (docs) {
                if (docs.isEmpty) {
                  return Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: AppTheme.darkCard,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.darkSurface),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.folder_open, size: 48, color: Colors.grey.shade600),
                        const SizedBox(height: 12),
                        const Text(
                          'No documents in vault yet',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Choose your folder above or click "Sync Folder" to scan your Indian documents.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey, fontSize: 13),
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
                    return _DocumentCard(
                      document: doc,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => DocumentDetailScreen(document: doc)),
                        );
                      },
                    );
                  },
                );
              },
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(32.0),
                  child: CircularProgressIndicator(color: AppTheme.primaryColor),
                ),
              ),
              error: (err, _) => Center(child: Text('Error: $err', style: const TextStyle(color: Colors.red))),
            ),
          ],
        ),
      ),
    );
  }
}

class _DocumentCard extends StatelessWidget {
  final DocumentModel document;
  final VoidCallback onTap;

  const _DocumentCard({required this.document, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.darkSurface),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(_getDocIcon(document.docType), color: AppTheme.primaryColor, size: 22),
        ),
        title: Text(
          document.title,
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              document.idNumber ?? document.fileName,
              style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
            ),
            if (document.expiryDate != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    document.isExpired ? Icons.warning : Icons.alarm,
                    size: 12,
                    color: document.isExpired ? AppTheme.dangerColor : AppTheme.warningColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    document.isExpired
                        ? 'Expired'
                        : 'Expires in ${document.daysUntilExpiry} days',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: document.isExpired ? AppTheme.dangerColor : AppTheme.warningColor,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
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
