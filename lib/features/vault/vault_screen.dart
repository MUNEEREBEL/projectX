import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/vault_provider.dart';
import '../../core/theme/app_theme.dart';
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
      appBar: AppBar(
        title: const Text('All Documents'),
      ),
      body: Column(
        children: [
          // 1. Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search vault by title, type, or number...',
                prefixIcon: const Icon(Icons.search, size: 18, color: AppTheme.textMuted),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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

          // 2. Family Members Filter
          personsAsync.when(
            data: (persons) {
              if (persons.isEmpty) return const SizedBox.shrink();
              return SizedBox(
                height: 38,
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

          const SizedBox(height: 6),

          // 3. Category Filter Chips
          SizedBox(
            height: 34,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final cat = _categories[index];
                final isSelected = _selectedCategory == cat;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(cat),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) setState(() => _selectedCategory = cat);
                    },
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 8),

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
                        SizedBox(height: 8),
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
              loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryColor)),
              error: (err, _) => Center(child: Text('Error: $err', style: const TextStyle(color: Colors.red))),
            ),
          ),
        ],
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
