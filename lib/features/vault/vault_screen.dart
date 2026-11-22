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
        title: const Text('Document Vault'),
      ),
      body: Column(
        children: [
          // 1. Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search vault by title, type, or number...',
                prefixIcon: const Icon(Icons.search, color: AppTheme.primaryColor),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.grey),
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
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    FilterChip(
                      label: const Text('All Members'),
                      selected: selectedPersonId == null,
                      onSelected: (_) => ref.read(selectedPersonIdProvider.notifier).state = null,
                    ),
                    const SizedBox(width: 8),
                    ...persons.map((p) {
                      final isSelected = selectedPersonId == p.id;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
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
            height: 38,
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
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.folder_off_outlined, size: 56, color: Colors.grey.shade600),
                        const SizedBox(height: 12),
                        const Text(
                          'No documents match your filters',
                          style: TextStyle(color: Colors.grey, fontSize: 15),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final doc = filtered[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: AppTheme.darkCard,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.darkSurface),
                      ),
                      child: ListTile(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => DocumentDetailScreen(document: doc)),
                          );
                        },
                        leading: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(_getDocIcon(doc.docType), color: AppTheme.primaryColor, size: 22),
                        ),
                        title: Text(
                          doc.title,
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              doc.idNumber ?? doc.category,
                              style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                            ),
                            if (doc.expiryDate != null)
                              Text(
                                doc.isExpired ? '⚠️ Expired' : 'Expires in ${doc.daysUntilExpiry} days',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: doc.isExpired ? AppTheme.dangerColor : AppTheme.warningColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                          ],
                        ),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor)),
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
