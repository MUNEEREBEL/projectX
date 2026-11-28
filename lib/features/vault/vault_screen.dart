import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/database/database_service.dart';
import '../../core/providers/vault_provider.dart';
import '../../models/document_field.dart';
import '../../models/document_model.dart';
import '../../models/person.dart';
import 'document_detail_screen.dart';
import 'family_graph_dialog.dart';

class VaultScreen extends ConsumerStatefulWidget {
  const VaultScreen({super.key});

  @override
  ConsumerState<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends ConsumerState<VaultScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _ownerName = 'Owner';

  @override
  void initState() {
    super.initState();
    _loadOwnerName();
  }

  Future<void> _loadOwnerName() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('vault_owner_name');
    if (name != null && name.trim().isNotEmpty && name.trim() != 'Primary Cardholder') {
      if (mounted) {
        setState(() => _ownerName = name.trim());
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

    final rawDocs = docsAsync.value ?? [];
    final persons = personsAsync.value ?? [];

    // Filter by Search Query
    final query = _searchController.text.trim().toLowerCase();
    final displayDocs = rawDocs.where((doc) {
      if (query.isEmpty) return true;
      final titleMatch = doc.title.toLowerCase().contains(query);
      final idMatch = doc.idNumber != null && doc.idNumber!.toLowerCase().contains(query);
      final typeMatch = doc.docType.toLowerCase().contains(query);
      final fileMatch = doc.fileName.toLowerCase().contains(query);
      return titleMatch || idMatch || typeMatch || fileMatch;
    }).toList();

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
              // 1. TOP HEADER (CONSTRAINED TO AVOID OVERFLOW)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
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
                          Text(
                            '${displayDocs.length} verified item${displayDocs.length == 1 ? '' : 's'} stored offline',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Family Knowledge Graph Button
                    InkWell(
                      onTap: () => FamilyGraphDialog.show(context),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFBFDBFE)),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF2563EB).withValues(alpha: 0.06),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.hub_rounded, size: 13, color: Color(0xFF2563EB)),
                            SizedBox(width: 4),
                            Text(
                              'Family Graph',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF2563EB),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 2. SEARCH BAR (BORDERLESS, NO GAP)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0F172A).withValues(alpha: 0.04),
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
                      hintText: 'Search Aadhaar, PAN, Roll No, IFSC, name...',
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
                      contentPadding: const EdgeInsets.symmetric(vertical: 11),
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
              const SizedBox(height: 8),

              // 3. DOCUMENT CARDS LIST (WITH EXTRACTED FIELDS & PURE GLASS DESIGN)
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(documentsProvider);
                    ref.invalidate(personsProvider);
                  },
                  color: const Color(0xFF00B4D8),
                  child: displayDocs.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                          children: [
                            const SizedBox(height: 80),
                            Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 64,
                                    height: 64,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.8),
                                      shape: BoxShape.circle,
                                      border: Border.all(color: const Color(0xFFE2E8F0)),
                                    ),
                                    child: const Icon(
                                      Icons.folder_open_rounded,
                                      size: 32,
                                      color: Color(0xFF94A3B8),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    query.isNotEmpty
                                        ? 'No matches for "$query"'
                                        : 'No documents in vault',
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    query.isNotEmpty
                                        ? 'Try searching with a different keyword.'
                                        : 'Sync a monitored folder or add documents to populate.',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 2, 20, 80),
                          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                          itemCount: displayDocs.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final doc = displayDocs[index];
                            final person = persons.firstWhere(
                              (p) => p.id == doc.personId,
                              orElse: () => Person(id: 'self', name: _ownerName, relationship: 'Self'),
                            );
                            return _VaultDocumentCardWidget(
                              key: ValueKey(doc.id),
                              document: doc,
                              person: person,
                              defaultOwner: _ownerName,
                              onDocumentUpdated: () {
                                ref.invalidate(documentsProvider);
                              },
                            );
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
}

/// Standalone Glassmorphic Document Card with Extracted Fields Preview
class _VaultDocumentCardWidget extends StatefulWidget {
  final DocumentModel document;
  final Person person;
  final String defaultOwner;
  final VoidCallback onDocumentUpdated;

  const _VaultDocumentCardWidget({
    super.key,
    required this.document,
    required this.person,
    required this.defaultOwner,
    required this.onDocumentUpdated,
  });

  @override
  State<_VaultDocumentCardWidget> createState() => _VaultDocumentCardWidgetState();
}

class _VaultDocumentCardWidgetState extends State<_VaultDocumentCardWidget> {
  List<DocumentField> _fields = [];

  @override
  void initState() {
    super.initState();
    _loadFields();
  }

  Future<void> _loadFields() async {
    final fields = await DatabaseService.instance.getFieldsForDocument(widget.document.id);
    if (mounted) {
      setState(() {
        _fields = fields;
      });
    }
  }

  void _copyToClipboard(String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied $label: $value'),
        duration: const Duration(seconds: 1),
        backgroundColor: const Color(0xFF0F172A),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final doc = widget.document;

    // Resolve real holder name from document's fields
    String holderName = widget.person.name;
    for (final f in _fields) {
      final low = f.fieldName.toLowerCase().trim();
      if ((low == 'full name' ||
              low == 'name' ||
              low == 'holder name' ||
              low == 'cardholder name' ||
              low == 'student name' ||
              low == 'candidate name' ||
              low == 'policy holder' ||
              low == 'insured name' ||
              low == 'patient name') &&
          f.fieldValue.trim().isNotEmpty &&
          f.fieldValue.toLowerCase() != 'unknown' &&
          f.fieldValue.toLowerCase() != 'primary user' &&
          f.fieldValue.toLowerCase() != 'primary cardholder') {
        holderName = f.fieldValue.trim();
        break;
      }
    }
    if (holderName.isEmpty ||
        holderName.toLowerCase() == 'primary user' ||
        holderName.toLowerCase() == 'unknown') {
      holderName = widget.person.relationship == 'Self' ? widget.defaultOwner : 'Verified Document';
    }

    // Clean high-contrast document emblem
    final isPdf = doc.fileName.toLowerCase().endsWith('.pdf');
    final iconData = isPdf ? Icons.picture_as_pdf_outlined : Icons.description_outlined;
    const iconBg = Color(0xFFEFF6FF);
    const iconColor = Color(0xFF2563EB);

    // Expiry / Status evaluation
    String statusText = 'Lifetime Valid';
    Color statusBg = const Color(0xFFDCFCE7);
    Color statusFg = const Color(0xFF16A34A);

    if (doc.expiryDate != null) {
      final days = doc.expiryDate!.difference(DateTime.now()).inDays;
      if (days < 0) {
        statusText = 'EXPIRED';
        statusBg = const Color(0xFFFEE2E2);
        statusFg = const Color(0xFFDC2626);
      } else if (days <= 30) {
        statusText = 'Expires in ${days}d';
        statusBg = const Color(0xFFFEF3C7);
        statusFg = const Color(0xFFD97706);
      } else {
        statusText = 'Valid until ${doc.expiryDate!.year}';
        statusBg = const Color(0xFFDCFCE7);
        statusFg = const Color(0xFF16A34A);
      }
    }

    // Collect highlight extracted fields to display directly on the card
    final highlightFields = <({String label, String value, IconData icon})>[];
    for (final f in _fields) {
      final nameLow = f.fieldName.toLowerCase();
      if (nameLow.contains('mobile') || nameLow.contains('phone')) {
        highlightFields.add((label: 'Mobile', value: f.fieldValue, icon: Icons.phone_outlined));
      } else if (nameLow.contains('ifsc')) {
        highlightFields.add((label: 'IFSC', value: f.fieldValue, icon: Icons.account_balance_outlined));
      } else if (nameLow.contains('account number')) {
        highlightFields.add((label: 'A/C', value: f.fieldValue, icon: Icons.credit_card_outlined));
      } else if (nameLow.contains('date of birth') || nameLow == 'dob') {
        highlightFields.add((label: 'DOB', value: f.fieldValue, icon: Icons.cake_outlined));
      } else if (nameLow.contains('sgpa') || nameLow.contains('cgpa') || nameLow.contains('percentage')) {
        highlightFields.add((label: f.fieldName, value: f.fieldValue, icon: Icons.grade_outlined));
      }
    }

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DocumentDetailScreen(document: doc),
          ),
        ).then((_) {
          _loadFields();
          widget.onDocumentUpdated();
        });
      },
      borderRadius: BorderRadius.circular(20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.95),
                width: 1.3,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                  blurRadius: 14,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. TOP ROW: ICON, TITLE, AND EXPIRY BADGE
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: iconBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(iconData, color: iconColor, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            doc.title,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F172A),
                              height: 1.25,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFF6FF),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.person_outline, size: 11, color: Color(0xFF2563EB)),
                                    const SizedBox(width: 3),
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(maxWidth: 140),
                                      child: Text(
                                        holderName,
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF2563EB),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusBg,
                        borderRadius: BorderRadius.circular(8),
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

                // 2. PRIMARY ID NUMBER CHIP (IF PRESENT)
                if (doc.idNumber != null && doc.idNumber!.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.pin_outlined, size: 14, color: Color(0xFF64748B)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            doc.idNumber!,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1E293B),
                              letterSpacing: 0.3,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        InkWell(
                          onTap: () => _copyToClipboard('ID Number', doc.idNumber!),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFFCBD5E1)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(Icons.copy_rounded, size: 11, color: Color(0xFF334155)),
                                SizedBox(width: 3),
                                Text(
                                  'Copy',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF334155),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // 3. EXTRACTED DATA HIGHLIGHTS CHIPS (PREVIEW ON CARD)
                if (highlightFields.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: highlightFields.take(3).map((item) {
                      return InkWell(
                        onTap: () => _copyToClipboard(item.label, item.value),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(item.icon, size: 11, color: const Color(0xFF64748B)),
                              const SizedBox(width: 4),
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 160),
                                child: Text(
                                  '${item.label}: ${item.value}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF334155),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 3),
                              const Icon(Icons.copy, size: 9, color: Color(0xFF94A3B8)),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],

                // 4. FOOTER: VERIFIED BADGE & TAP TO VIEW
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            doc.isVerified ? Icons.check_circle_rounded : Icons.pending_outlined,
                            size: 13,
                            color: doc.isVerified ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              doc.isVerified ? 'Verified Extraction' : 'Draft / Processing',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: doc.isVerified ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Text(
                          'View all fields',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF38BDF8),
                          ),
                        ),
                        SizedBox(width: 2),
                        Icon(Icons.chevron_right_rounded, size: 14, color: Color(0xFF38BDF8)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
