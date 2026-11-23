import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/vault_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/glass_card.dart';
import 'document_detail_screen.dart';

class VaultScreen extends ConsumerStatefulWidget {
  const VaultScreen({super.key});

  @override
  ConsumerState<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends ConsumerState<VaultScreen> {
  String _selectedCategory = 'All';
  final TextEditingController _searchController = TextEditingController();

  final List<String> _categories = [
    'All',
    'Identity',
    'Vehicle',
    'Financial',
    'Health',
    'Education',
    'Other'
  ];

  @override
  Widget build(BuildContext context) {
    final docsAsync = ref.watch(documentsProvider);
    final personsAsync = ref.watch(personsProvider);
    final selectedPersonId = ref.watch(selectedPersonIdProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('All Vault Documents'),
      ),
      body: Column(
        children: [
          // 1. Frosted Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: GlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              borderRadius: 14,
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Search vault by title, type, or number...',
                  hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                  prefixIcon: const Icon(Icons.search, size: 18, color: AppTheme.accentColor),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16, color: AppTheme.textMuted),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                        )
                      : null,
                ),
              ),
            ),
          ),

          // 2. Family Members Filter
          personsAsync.when(
            data: (persons) {
              if (persons.isEmpty) return const SizedBox.shrink();
              return SizedBox(
                height: 40,
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
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),

          const SizedBox(height: 8),

          // 3. Category Filter Chips
          SizedBox(
            height: 36,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final cat = _categories[index];
                final isSelected = _selectedCategory == cat;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(cat),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) setState(() => _selectedCategory = cat);
                    },
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 10),

          // 4. Document List
          Expanded(
            child: docsAsync.when(
              data: (docs) {
                final query = _searchController.text.toLowerCase().trim();

                final filtered = docs.where((doc) {
                  // Category filter
                  if (_selectedCategory != 'All' && doc.category.toLowerCase() != _selectedCategory.toLowerCase()) {
                    return false;
                  }

                  // Search query filter
                  if (query.isNotEmpty) {
                    final matchesTitle = doc.title.toLowerCase().contains(query);
                    final matchesType = doc.docType.toLowerCase().contains(query);
                    final matchesNumber = doc.idNumber?.toLowerCase().contains(query) ?? false;
                    if (!matchesTitle && !matchesType && !matchesNumber) return false;
                  }

                  return true;
                }).toList();

                if (filtered.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.folder_off_outlined, size: 40, color: AppTheme.textMuted),
                        SizedBox(height: 10),
                        Text(
                          'No documents match your filters',
                          style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final doc = filtered[index];
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
                            width: 40,
                            height: 40,
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
                            child: Icon(_getDocIcon(doc.docType), color: AppTheme.accentColor, size: 18),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  doc.title,
                                  style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary, fontSize: 13),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  doc.idNumber ?? doc.category,
                                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 11, fontFamily: 'monospace'),
                                ),
                                const SizedBox(height: 2),
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
              loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accentColor)),
              error: (err, _) => Center(child: Text('Error: $err', style: const TextStyle(color: Colors.red))),
            ),
          ),
        ],
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
