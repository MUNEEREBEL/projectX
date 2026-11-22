import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/database_service.dart';
import '../../core/providers/vault_provider.dart';
import '../../core/theme/app_theme.dart';

class OverlayCopilotSheet extends ConsumerStatefulWidget {
  const OverlayCopilotSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const OverlayCopilotSheet(),
    );
  }

  @override
  ConsumerState<OverlayCopilotSheet> createState() => _OverlayCopilotSheetState();
}

class _OverlayCopilotSheetState extends ConsumerState<OverlayCopilotSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedCategory = 'All';
  String? _copiedFieldId;
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;

  final List<String> _categories = ['All', 'identity', 'date', 'address', 'vehicle', 'financial'];

  @override
  void initState() {
    super.initState();
    _loadFields();
  }

  Future<void> _loadFields() async {
    setState(() => _isSearching = true);
    final selectedPersonId = ref.read(selectedPersonIdProvider);
    final results = await DatabaseService.instance.searchFields(
      _searchController.text.trim(),
      personId: selectedPersonId,
    );

    if (mounted) {
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    }
  }

  void _copyToClipboard(String id, String fieldName, String value) {
    Clipboard.setData(ClipboardData(text: value));
    HapticFeedback.lightImpact();
    setState(() => _copiedFieldId = id);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copiedFieldId = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final personsAsync = ref.watch(personsProvider);
    final selectedPersonId = ref.watch(selectedPersonIdProvider);

    // Filter results by category
    final filteredResults = _selectedCategory == 'All'
        ? _searchResults
        : _searchResults.where((r) => r['field_category'] == _selectedCategory).toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: AppTheme.darkBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: AppTheme.darkSurface, width: 1.5)),
      ),
      child: Column(
        children: [
          // Drag Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade600,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.bolt, color: AppTheme.primaryColor, size: 20),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Form Autofill Copilot',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      Text(
                        '1-Tap to copy verified details into forms',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // 1. Person Selector Chips (Multi-person handling)
          personsAsync.when(
            data: (persons) {
              if (persons.isEmpty) return const SizedBox.shrink();
              return SizedBox(
                height: 42,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    FilterChip(
                      selected: selectedPersonId == null,
                      label: const Text('All Family'),
                      onSelected: (_) {
                        ref.read(selectedPersonIdProvider.notifier).state = null;
                        _loadFields();
                      },
                    ),
                    const SizedBox(width: 8),
                    ...persons.map((p) {
                      final isSelected = selectedPersonId == p.id;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          selected: isSelected,
                          avatar: CircleAvatar(
                            backgroundColor: AppTheme.avatarColors[p.avatarColorIndex % AppTheme.avatarColors.length],
                            radius: 10,
                            child: Text(
                              p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                              style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                          label: Text('${p.name} (${p.relationship})'),
                          onSelected: (_) {
                            ref.read(selectedPersonIdProvider.notifier).state = isSelected ? null : p.id;
                            _loadFields();
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

          // 2. Search Bar for Fast Field Lookup (Prevents Clutter)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => _loadFields(),
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Type to search (e.g. pan, dl, ifsc, address, pin)...',
                prefixIcon: const Icon(Icons.search, color: AppTheme.primaryColor, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.grey, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          _loadFields();
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              ),
            ),
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
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(
                      cat[0].toUpperCase() + cat.substring(1),
                      style: TextStyle(
                        fontSize: 11,
                        color: isSelected ? Colors.white : Colors.grey,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) setState(() => _selectedCategory = cat);
                    },
                    selectedColor: AppTheme.primaryColor.withValues(alpha: 0.3),
                    backgroundColor: AppTheme.darkCard,
                    side: BorderSide(
                      color: isSelected ? AppTheme.primaryColor : AppTheme.darkSurface,
                    ),
                  ),
                );
              },
            ),
          ),

          const Divider(color: AppTheme.darkSurface, height: 20),

          // 4. Clean Field Results
          Expanded(
            child: _isSearching
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor))
                : filteredResults.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.search_off, size: 48, color: Colors.grey.shade600),
                            const SizedBox(height: 8),
                            const Text(
                              'No matching document fields found',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: filteredResults.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final item = filteredResults[index];
                          final id = item['id'] as String;
                          final fieldName = item['field_name'] as String;
                          final fieldValue = item['field_value'] as String;
                          final personName = item['person_name'] as String;
                          final docTitle = item['doc_title'] as String;
                          final isCopied = _copiedFieldId == id;

                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.darkCard,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isCopied ? AppTheme.primaryColor : AppTheme.darkSurface,
                                width: isCopied ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            fieldName,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const Spacer(),
                                          Text(
                                            '$personName • $docTitle',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.grey.shade500,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      SelectableText(
                                        fieldValue,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                ElevatedButton.icon(
                                  onPressed: () => _copyToClipboard(id, fieldName, fieldValue),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: isCopied
                                        ? AppTheme.primaryColor
                                        : AppTheme.primaryColor.withValues(alpha: 0.15),
                                    foregroundColor: isCopied ? Colors.black : AppTheme.primaryColor,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  icon: Icon(
                                    isCopied ? Icons.check : Icons.copy,
                                    size: 16,
                                  ),
                                  label: Text(
                                    isCopied ? 'Copied!' : 'Copy',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
