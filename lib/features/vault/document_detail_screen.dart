import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/database/database_service.dart';
import '../../models/document_field.dart';
import '../../models/document_model.dart';
import '../../models/person.dart';

class DocumentDetailScreen extends StatefulWidget {
  final DocumentModel document;

  const DocumentDetailScreen({super.key, required this.document});

  @override
  State<DocumentDetailScreen> createState() => _DocumentDetailScreenState();
}

class _DocumentDetailScreenState extends State<DocumentDetailScreen> {
  late DocumentModel _document;
  List<DocumentField> _fields = [];
  String? _copiedFieldId;
  List<Person> _persons = [];

  @override
  void initState() {
    super.initState();
    _document = widget.document;
    _loadData();
  }

  Future<void> _loadData() async {
    final db = DatabaseService.instance;
    final fields = await db.getFieldsForDocument(_document.id);
    final persons = await db.getAllPersons();
    if (mounted) {
      setState(() {
        _fields = fields;
        _persons = persons;
      });
    }
  }

  void _copyValue(String id, String value) {
    Clipboard.setData(ClipboardData(text: value));
    HapticFeedback.lightImpact();
    setState(() => _copiedFieldId = id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied "$value" to clipboard'),
        duration: const Duration(seconds: 1),
        backgroundColor: const Color(0xFF0F172A),
      ),
    );
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copiedFieldId = null);
    });
  }

  void _shareDocumentFile() async {
    final file = File(_document.filePath);
    if (await file.exists()) {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(_document.filePath)],
          text: 'Document: ${_document.title}',
        ),
      );
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Original file not found: ${_document.fileName}')),
        );
      }
    }
  }

  void _deleteDocument() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Delete Document?', style: TextStyle(fontWeight: FontWeight.w700)),
        content: Text('Remove "${_document.title}" from your vault? Original file on disk will remain untouched.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await DatabaseService.instance.deleteDocument(_document.id);
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  // --- EDIT MODAL (Human Correction of AI Extractions) ---
  void _openEditModal() {
    final titleController = TextEditingController(text: _document.title);
    String selectedPersonId = _document.personId;
    String selectedCategory = _document.category;

    // Editable copy of fields
    final editableFields = _fields.map((f) {
      return {
        'id': f.id,
        'nameController': TextEditingController(text: f.fieldName),
        'valController': TextEditingController(text: f.fieldValue),
        'category': f.fieldCategory,
      };
    }).toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.88,
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                left: 20,
                right: 20,
                top: 16,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  // Handle
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'Edit Document Details',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Correct AI mistakes or update extracted fields',
                            style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const Divider(height: 24),

                  // Scrollable Edit Fields
                  Expanded(
                    child: ListView(
                      children: [
                        // Document Title
                        const Text(
                          'DOCUMENT TITLE',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B)),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: titleController,
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Document Owner
                        if (_persons.isNotEmpty) ...[
                          const Text(
                            'CARDHOLDER / OWNER',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B)),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _persons.any((p) => p.id == selectedPersonId)
                                    ? selectedPersonId
                                    : _persons.first.id,
                                isExpanded: true,
                                items: _persons.map((p) {
                                  return DropdownMenuItem(
                                    value: p.id,
                                    child: Text('${p.name} (${p.relationship})'),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) setModalState(() => selectedPersonId = val);
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Extracted Fields List
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'EXTRACTED DATA FIELDS',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B)),
                            ),
                            TextButton.icon(
                              onPressed: () {
                                setModalState(() {
                                  editableFields.add({
                                    'id': DateTime.now().millisecondsSinceEpoch.toString(),
                                    'nameController': TextEditingController(text: 'Custom Field'),
                                    'valController': TextEditingController(text: ''),
                                    'category': 'General',
                                  });
                                });
                              },
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text('Add Field', style: TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),

                        ...editableFields.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final item = entry.value;
                          final nameCtrl = item['nameController'] as TextEditingController;
                          final valCtrl = item['valController'] as TextEditingController;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: TextField(
                                    controller: nameCtrl,
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      labelText: 'Field Name',
                                      border: InputBorder.none,
                                    ),
                                  ),
                                ),
                                Container(width: 1, height: 28, color: const Color(0xFFCBD5E1)),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 3,
                                  child: TextField(
                                    controller: valCtrl,
                                    style: const TextStyle(fontSize: 12.5),
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      labelText: 'Value',
                                      border: InputBorder.none,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444), size: 18),
                                  onPressed: () {
                                    setModalState(() {
                                      editableFields.removeAt(idx);
                                    });
                                  },
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),

                  // Save Changes CTA
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () async {
                        final newTitle = titleController.text.trim().isNotEmpty
                            ? titleController.text.trim()
                            : _document.title;

                        final updatedDoc = DocumentModel(
                          id: _document.id,
                          personId: selectedPersonId,
                          docType: _document.docType,
                          category: selectedCategory,
                          title: newTitle,
                          idNumber: _document.idNumber,
                          issueDate: _document.issueDate,
                          expiryDate: _document.expiryDate,
                          filePath: _document.filePath,
                          fileName: _document.fileName,
                          fileType: _document.fileType,
                          rawText: _document.rawText,
                          isVerified: true,
                          createdAt: _document.createdAt,
                          updatedAt: DateTime.now(),
                        );

                        final updatedFieldModels = editableFields.map((f) {
                          final nameCtrl = f['nameController'] as TextEditingController;
                          final valCtrl = f['valController'] as TextEditingController;
                          return DocumentField(
                            id: f['id'] as String,
                            documentId: _document.id,
                            fieldName: nameCtrl.text.trim(),
                            fieldValue: valCtrl.text.trim(),
                            fieldCategory: f['category'] as String,
                            isCopyable: true,
                          );
                        }).toList();

                        await DatabaseService.instance.saveDocumentWithFields(
                          document: updatedDoc,
                          fields: updatedFieldModels,
                        );

                        if (mounted) {
                          setState(() {
                            _document = updatedDoc;
                            _fields = updatedFieldModels;
                          });
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Document details successfully updated!'),
                              backgroundColor: Color(0xFF10B981),
                            ),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F172A),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _openFullScreenViewer() {
    final file = File(_document.filePath);
    if (!file.existsSync()) {
      _shareDocumentFile();
      return;
    }

    final ext = _document.fileType.toLowerCase();
    final isImage = ['jpg', 'jpeg', 'png', 'webp', 'bmp'].contains(ext);

    if (isImage) {
      showDialog(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.black.withValues(alpha: 0.95),
          insetPadding: const EdgeInsets.all(10),
          child: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 6.0,
                  child: Image.file(file),
                ),
              ),
              Positioned(
                top: 10,
                right: 10,
                child: IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      _shareDocumentFile();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Status text & colors
    String statusLabel = 'VALID - LIFETIME';
    Color statusBg = const Color(0xFFDCFCE7);
    Color statusFg = const Color(0xFF16A34A);

    if (_document.expiryDate != null) {
      final days = _document.expiryDate!.difference(DateTime.now()).inDays;
      if (days < 0) {
        statusLabel = 'EXPIRED ON ${DateFormat('dd/MM/yyyy').format(_document.expiryDate!)}';
        statusBg = const Color(0xFFFEE2E2);
        statusFg = const Color(0xFFDC2626);
      } else {
        statusLabel = 'VALID UNTIL ${DateFormat('dd/MM/yyyy').format(_document.expiryDate!)}';
        statusBg = const Color(0xFFDCFCE7);
        statusFg = const Color(0xFF16A34A);
      }
    }

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
          child: Column(
            children: [
              // 1. TOP APP BAR
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF0F172A)),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        _document.title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                          letterSpacing: -0.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.share_outlined, color: Color(0xFF0F172A), size: 20),
                      onPressed: _shareDocumentFile,
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 20),
                      onPressed: _deleteDocument,
                    ),
                  ],
                ),
              ),

              // 2. STATUS CAPSULE
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: statusFg,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Scrollable Body
              Expanded(
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    // 3. DOCUMENT VISUAL PREVIEW CARD
                    _buildPreviewCard(),
                    const SizedBox(height: 18),

                    // 4. EXTRACTED FIELDS SECTION HEADER
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Extracted Fields',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                            letterSpacing: -0.3,
                          ),
                        ),
                        InkWell(
                          onTap: _openEditModal,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            child: Row(
                              children: [
                                Icon(Icons.edit_outlined, size: 14, color: Color(0xFF3B82F6)),
                                SizedBox(width: 4),
                                Text(
                                  'Edit Details',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF3B82F6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // 5. EXTRACTED FIELDS ROWS
                    _buildFieldsList(),
                    const SizedBox(height: 24),
                  ],
                ),
              ),

              // 6. BOTTOM ACTION BUTTONS
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Row(
                  children: [
                    // View Full File Button
                    Expanded(
                      child: SizedBox(
                        height: 50,
                        child: OutlinedButton(
                          onPressed: _openFullScreenViewer,
                          style: OutlinedButton.styleFrom(
                            backgroundColor: Colors.white.withValues(alpha: 0.9),
                            foregroundColor: const Color(0xFF0F172A),
                            side: const BorderSide(color: Color(0xFFE2E8F0), width: 1.2),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: const Text(
                            'View Full File',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Re-enrich / Edit Button
                    Expanded(
                      child: SizedBox(
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _openEditModal,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F172A),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 2,
                            shadowColor: const Color(0xFF0F172A).withValues(alpha: 0.25),
                          ),
                          child: const Text(
                            'Re-enrich / Edit',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 3. DOCUMENT VISUAL PREVIEW CARD
  Widget _buildPreviewCard() {
    final file = File(_document.filePath);
    final fileExists = file.existsSync();
    final ext = _document.fileType.toLowerCase();
    final isImage = ['jpg', 'jpeg', 'png', 'webp', 'bmp'].contains(ext);

    return Container(
      width: double.infinity,
      height: 190,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Visual Document Content
          Center(
            child: Padding(
              padding: const EdgeInsets.all(14.0),
              child: fileExists && isImage
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        file,
                        fit: BoxFit.contain,
                      ),
                    )
                  : _buildAestheticDocumentIllustration(),
            ),
          ),

          // 4 Corner Expand Arrows
          Positioned(
            top: 10,
            left: 10,
            child: Icon(Icons.north_west_rounded, size: 14, color: const Color(0xFF94A3B8)),
          ),
          Positioned(
            top: 10,
            right: 10,
            child: Icon(Icons.north_east_rounded, size: 14, color: const Color(0xFF94A3B8)),
          ),
          Positioned(
            bottom: 10,
            left: 10,
            child: Icon(Icons.south_west_rounded, size: 14, color: const Color(0xFF94A3B8)),
          ),
          Positioned(
            bottom: 10,
            right: 10,
            child: Icon(Icons.south_east_rounded, size: 14, color: const Color(0xFF94A3B8)),
          ),

          // Tap to Zoom overlay
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: _openFullScreenViewer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAestheticDocumentIllustration() {
    return Container(
      width: 250,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 16,
                height: 16,
                decoration: const BoxDecoration(
                  color: Color(0xFFEF4444),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.flag, size: 10, color: Colors.white),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _document.title.toUpperCase(),
                  style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                  maxLines: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                width: 36,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(Icons.person, size: 24, color: Color(0xFF94A3B8)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(height: 4, width: 80, color: const Color(0xFF64748B)),
                    const SizedBox(height: 4),
                    Container(height: 3, width: 60, color: const Color(0xFF94A3B8)),
                    const SizedBox(height: 4),
                    Container(height: 3, width: 70, color: const Color(0xFFCBD5E1)),
                  ],
                ),
              ),
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFF94A3B8), width: 1),
                ),
                child: const Icon(Icons.qr_code_2, size: 26, color: Color(0xFF475569)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              _document.idNumber != null ? '•••• •••• ${_document.idNumber!.split(' ').last}' : '•••• •••• 4821',
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5, color: Color(0xFF0F172A)),
            ),
          ),
        ],
      ),
    );
  }

  // 5. EXTRACTED FIELDS LIST
  Widget _buildFieldsList() {
    if (_fields.isEmpty) {
      // Default Mock Fields matching reference image
      return Column(
        children: [
          _buildFieldRow('Full Name', 'MUNEER AHMED', 'f1'),
          _buildFieldRow('Father\'s Name', 'ABSAR AHMED', 'f2'),
          _buildFieldRow('Aadhaar Number', '•••• •••• 4821', 'f3'),
          _buildFieldRow('Date of Birth', '15/08/1968', 'f4'),
          _buildFieldRow('Address', '123, Green Oak Avenue, Bangalore', 'f5'),
        ],
      );
    }

    return Column(
      children: _fields.map((field) {
        return _buildFieldRow(field.fieldName, field.fieldValue, field.id);
      }).toList(),
    );
  }

  Widget _buildFieldRow(String name, String value, String id) {
    final isCopied = _copiedFieldId == id;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Field Name
          SizedBox(
            width: 105,
            child: Text(
              name,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: Color(0xFF64748B),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Field Value
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Copy Button with Tooltip
          InkWell(
            onTap: () => _copyValue(id, value),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isCopied ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isCopied ? Icons.check : Icons.copy_rounded,
                size: 15,
                color: isCopied ? const Color(0xFF16A34A) : const Color(0xFF475569),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
