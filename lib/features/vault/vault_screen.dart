import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/providers/vault_provider.dart';
import '../../models/document_model.dart';
import '../../models/person.dart';
import 'document_detail_screen.dart';

class VaultScreen extends ConsumerStatefulWidget {
  const VaultScreen({super.key});

  @override
  ConsumerState<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends ConsumerState<VaultScreen> {
  String _selectedCategory = 'All';
  final TextEditingController _searchController = TextEditingController();
  String _ownerName = 'Muneer';

  final List<String> _categories = [
    'All',
    'Identity',
    'Education',
    'Financial',
    'Vehicle',
  ];

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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final docsAsync = ref.watch(documentsProvider);
    final personsAsync = ref.watch(personsProvider);
    final selectedPersonId = ref.watch(selectedPersonIdProvider);

    final rawDocs = docsAsync.value ?? [];
    final persons = personsAsync.value ?? [];

    // Filter by Search Query
    final query = _searchController.text.trim().toLowerCase();
    var filteredDocs = rawDocs.where((doc) {
      if (query.isEmpty) return true;
      final titleMatch = doc.title.toLowerCase().contains(query);
      final idMatch = doc.idNumber != null && doc.idNumber!.toLowerCase().contains(query);
      final typeMatch = doc.docType.toLowerCase().contains(query);
      return titleMatch || idMatch || typeMatch;
    }).toList();

    // Filter by Person
    if (selectedPersonId != null) {
      filteredDocs = filteredDocs.where((d) => d.personId == selectedPersonId).toList();
    }

    // Filter by Category
    if (_selectedCategory != 'All') {
      filteredDocs = filteredDocs.where((d) {
        return d.category.toLowerCase() == _selectedCategory.toLowerCase();
      }).toList();
    }

    // Fallback Mock Documents if vault is still fresh
    final displayDocs = filteredDocs.isNotEmpty ? filteredDocs : _createMockVaultDocs(persons);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0.0, 0.35, 0.7, 1.0],
            colors: [
              Color(0xFFEFF6FF), // soft airy blue top
              Color(0xFFF8FAFC), // clean white slate
              Color(0xFFFDF2F8), // gentle blush accent
              Color(0xFFEBF4FF), // soft glow bottom
            ],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. TOP HEADER
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Documents Vault',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                        letterSpacing: -0.5,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: const Text(
                        'Vault Encrypted',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF475569),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 2. SEARCH BAR
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0F172A).withValues(alpha: 0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF0F172A),
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search Aadhaar, PAN, Roll No, IFSC...',
                      hintStyle: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w400,
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: Color(0xFF94A3B8),
                        size: 20,
                      ),
                      prefixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16, color: Color(0xFF94A3B8)),
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
              const SizedBox(height: 6),

              // 3. FAMILY MEMBERS FILTER CHIPS
              _buildFamilyFilterPills(persons, selectedPersonId),
              const SizedBox(height: 6),

              // 4. CATEGORY TEXT TABS
              _buildCategoryTabs(),
              const SizedBox(height: 10),

              // 5. 2-COLUMN DOCUMENT CARDS GRID
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(documentsProvider);
                    ref.invalidate(personsProvider);
                  },
                  color: const Color(0xFF00B4D8),
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 90),
                    physics: const BouncingScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.88,
                    ),
                    itemCount: displayDocs.length,
                    itemBuilder: (context, index) {
                      final doc = displayDocs[index];
                      final person = persons.firstWhere(
                        (p) => p.id == doc.personId,
                        orElse: () => Person(id: 'self', name: _ownerName, relationship: 'Self'),
                      );
                      return _buildVaultDocumentCard(doc, person);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 3. FAMILY FILTER PILLS
  Widget _buildFamilyFilterPills(List<Person> persons, String? selectedPersonId) {
    final selfPerson = persons.isNotEmpty
        ? persons.first
        : Person(id: 'self', name: _ownerName, relationship: 'Self');

    final otherPersons = persons.skip(1).toList();

    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          // All Chip
          _buildPillButton(
            label: 'All',
            isSelected: selectedPersonId == null,
            onTap: () => ref.read(selectedPersonIdProvider.notifier).state = null,
          ),
          const SizedBox(width: 8),

          // Self (Muneer) Chip
          _buildPillButton(
            label: 'Self (${selfPerson.name.split(' ').first})',
            hasCheck: selectedPersonId == selfPerson.id,
            isSelected: selectedPersonId == selfPerson.id,
            onTap: () {
              final isSel = selectedPersonId == selfPerson.id;
              ref.read(selectedPersonIdProvider.notifier).state = isSel ? null : selfPerson.id;
            },
          ),
          const SizedBox(width: 8),

          // Other Family Members (Father, Mother, etc.)
          ...otherPersons.map((p) {
            final isSel = selectedPersonId == p.id;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _buildPillButton(
                label: p.relationship.isNotEmpty ? p.relationship : p.name,
                isSelected: isSel,
                onTap: () {
                  ref.read(selectedPersonIdProvider.notifier).state = isSel ? null : p.id;
                },
              ),
            );
          }),

          if (otherPersons.isEmpty) ...[
            _buildPillButton(
              label: 'Father',
              isSelected: false,
              onTap: () {},
            ),
            const SizedBox(width: 8),
            _buildPillButton(
              label: 'Mother',
              isSelected: false,
              onTap: () {},
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPillButton({
    required String label,
    required bool isSelected,
    bool hasCheck = false,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0F172A) : Colors.white.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: isSelected ? 0.15 : 0.02),
              blurRadius: 6,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                color: isSelected ? Colors.white : const Color(0xFF475569),
              ),
            ),
            if (hasCheck) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.check,
                size: 13,
                color: isSelected ? Colors.white : const Color(0xFF0F172A),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // 4. CATEGORY TABS
  Widget _buildCategoryTabs() {
    return SizedBox(
      height: 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        itemCount: _categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 20),
        itemBuilder: (context, index) {
          final cat = _categories[index];
          final isSelected = _selectedCategory == cat;

          return InkWell(
            onTap: () => setState(() => _selectedCategory = cat),
            child: Center(
              child: Text(
                cat,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                  color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF94A3B8),
                  letterSpacing: -0.2,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // 5. DOCUMENT CARD
  Widget _buildVaultDocumentCard(DocumentModel doc, Person person) {
    // Icon selection matching reference image
    IconData iconData = Icons.badge_outlined;
    final typeLower = doc.docType.toLowerCase();
    final titleLower = doc.title.toLowerCase();

    if (typeLower.contains('marksheet') || titleLower.contains('marksheet') || typeLower.contains('education')) {
      iconData = Icons.school_outlined;
    } else if (typeLower.contains('passbook') || titleLower.contains('passbook') || typeLower.contains('bank')) {
      iconData = Icons.account_balance_outlined;
    } else if (typeLower.contains('insurance') || titleLower.contains('insurance') || typeLower.contains('vehicle') || titleLower.contains('rc')) {
      iconData = Icons.directions_car_outlined;
    }

    // Number extraction for "•••• 4821"
    String idMask = '•••• 4821';
    if (doc.idNumber != null && doc.idNumber!.isNotEmpty) {
      final clean = doc.idNumber!.replaceAll(' ', '');
      if (clean.length >= 4) {
        idMask = '•••• ${clean.substring(clean.length - 4)}';
      } else {
        idMask = '•••• $clean';
      }
    }

    // Status pill text and color matching reference image
    String statusText = 'Lifetime Valid';
    Color statusBg = const Color(0xFFDCFCE7);
    Color statusFg = const Color(0xFF16A34A);

    if (doc.expiryDate != null) {
      final days = doc.expiryDate!.difference(DateTime.now()).inDays;
      if (days < 0) {
        statusText = 'Expired';
        statusBg = const Color(0xFFFEE2E2);
        statusFg = const Color(0xFFDC2626);
      } else if (days <= 30) {
        statusText = 'Expiring in ${days}d';
        statusBg = const Color(0xFFFEF3C7);
        statusFg = const Color(0xFFD97706);
      } else {
        statusText = 'Valid';
        statusBg = const Color(0xFFDCFCE7);
        statusFg = const Color(0xFF16A34A);
      }
    } else if (typeLower.contains('passbook') || titleLower.contains('passbook')) {
      statusText = 'Updated recently';
      statusBg = const Color(0xFFF1F5F9);
      statusFg = const Color(0xFF475569);
    }

    final ownerDisplay = person.relationship.isNotEmpty ? person.relationship : person.name;

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DocumentDetailScreen(document: doc),
          ),
        ).then((_) {
          ref.invalidate(documentsProvider);
        });
      },
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(18),
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
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Top: Icon in rounded container
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                iconData,
                size: 18,
                color: const Color(0xFF0F172A),
              ),
            ),

            // Middle: Title & Owner Pill
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  doc.title,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                    height: 1.25,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    ownerDisplay,
                    style: const TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF3B82F6),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),

            // Bottom: Masked ID + Status Pill
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      idMask,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF334155),
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        if (doc.idNumber != null) {
                          Clipboard.setData(ClipboardData(text: doc.idNumber!));
                          HapticFeedback.lightImpact();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('ID copied to clipboard'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        }
                      },
                      child: const Icon(
                        Icons.copy_rounded,
                        size: 13,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: statusFg,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<DocumentModel> _createMockVaultDocs(List<Person> persons) {
    return [
      DocumentModel(
        id: 'mock-1',
        personId: persons.length > 1 ? persons[1].id : 'father',
        docType: 'AADHAAR',
        category: 'Identity',
        title: 'Father\'s Aadhaar Card',
        idNumber: '9876 5432 4821',
        filePath: '',
        fileName: 'aadhaar_father.pdf',
        fileType: 'pdf',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
      DocumentModel(
        id: 'mock-2',
        personId: persons.isNotEmpty ? persons[0].id : 'self',
        docType: 'CLASS_10_MARKSHEET',
        category: 'Education',
        title: 'Class 10th Marksheet',
        idNumber: '2100849871',
        filePath: '',
        fileName: 'marksheet_10.pdf',
        fileType: 'pdf',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
      DocumentModel(
        id: 'mock-3',
        personId: persons.isNotEmpty ? persons[0].id : 'self',
        docType: 'BANK_PASSBOOK',
        category: 'Financial',
        title: 'Bank Passbook',
        idNumber: '345678913456',
        filePath: '',
        fileName: 'passbook.pdf',
        fileType: 'pdf',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
      DocumentModel(
        id: 'mock-4',
        personId: persons.length > 1 ? persons[1].id : 'father',
        docType: 'VEHICLE_INSURANCE',
        category: 'Vehicle',
        title: 'Car Insurance',
        idNumber: 'POL20262289',
        expiryDate: DateTime.now().add(const Duration(days: 18)),
        filePath: '',
        fileName: 'insurance.pdf',
        fileType: 'pdf',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    ];
  }
}
