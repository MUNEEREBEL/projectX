import '../database/database_service.dart';
import '../../models/document_field.dart';
import '../../models/document_model.dart';
import '../../models/person.dart';
import 'person_resolution_engine.dart';

class FamilyMemberNode {
  final String id;
  final String name;
  final String relationship;
  final int avatarColorIndex;
  final int documentCount;
  final List<String> categoriesPresent;
  final List<String> missingCategories;
  final List<DocumentModel> documents;

  const FamilyMemberNode({
    required this.id,
    required this.name,
    required this.relationship,
    required this.avatarColorIndex,
    required this.documentCount,
    required this.categoriesPresent,
    required this.missingCategories,
    required this.documents,
  });

  /// Regulatory document health completeness score (0 to 100%)
  int get completenessPercentage {
    const essentialCategories = ['Identity', 'Financial', 'Certificates'];
    int matched = 0;
    for (final c in essentialCategories) {
      if (categoriesPresent.contains(c)) matched++;
    }
    return ((matched / essentialCategories.length) * 100).round();
  }
}

class FamilyGraphEdge {
  final String sourcePersonId;
  final String targetPersonId;
  final String relationType; // 'FATHER_OF', 'MOTHER_OF', 'SPOUSE_OF', 'CHILD_OF'

  const FamilyGraphEdge({
    required this.sourcePersonId,
    required this.targetPersonId,
    required this.relationType,
  });
}

class FamilyGraphData {
  final List<FamilyMemberNode> members;
  final List<FamilyGraphEdge> edges;
  final int totalDocumentsCount;
  final int totalFamilyMembersCount;

  const FamilyGraphData({
    required this.members,
    required this.edges,
    required this.totalDocumentsCount,
    required this.totalFamilyMembersCount,
  });
}

/// Family Knowledge Graph (FKG) Engine
/// Constructs clean, canonical, deduplicated family entity hierarchies and identifies civic coverage gaps.
class FamilyGraphService {
  static const List<String> standardCivicCategories = [
    'Identity',
    'Financial',
    'Education',
    'Vehicle',
    'Certificates',
    'Health',
  ];

  static Future<FamilyGraphData> buildFamilyGraph() async {
    final db = DatabaseService.instance;
    await db.cleanupDuplicatePersons();

    final allPersons = await db.getAllPersons();
    final allDocs = await db.getAllDocuments();

    final docFieldsCache = <String, List<DocumentField>>{};
    for (final doc in allDocs) {
      docFieldsCache[doc.id] = await db.getFieldsForDocument(doc.id);
    }

    final members = <FamilyMemberNode>[];
    String? primaryUserId;

    for (final p in allPersons) {
      if (PersonResolutionEngine.isGenericPlaceholder(p.name)) continue;

      // Smart Document Association:
      // Include direct docs + shared family cards (e.g. Ration Card) + docs with holder matching p.name
      final docs = allDocs.where((doc) {
        if (doc.personId == p.id) return true;
        final fields = docFieldsCache[doc.id] ?? [];
        final hasName = fields.any((f) =>
            (f.fieldName == 'Full Name' || f.fieldName.startsWith('Family Member')) &&
            PersonResolutionEngine.isNameMatch(p.name, f.fieldValue));
        final matchesTitle = doc.title.toLowerCase().contains(p.relationship.toLowerCase()) &&
            p.relationship.toLowerCase() != 'self';
        return hasName || matchesTitle;
      }).toList();

      final presentCats = docs.map((d) => d.category).toSet().toList();
      final missingCats = standardCivicCategories.where((c) => !presentCats.contains(c)).toList();

      if (p.relationship.toLowerCase() == 'self') {
        primaryUserId = p.id;
      }

      members.add(FamilyMemberNode(
        id: p.id,
        name: p.name,
        relationship: p.relationship,
        avatarColorIndex: p.avatarColorIndex,
        documentCount: docs.length,
        categoriesPresent: presentCats,
        missingCategories: missingCats,
        documents: docs,
      ));
    }

    // Build relational edges linking relatives to the primary user
    final edges = <FamilyGraphEdge>[];
    if (primaryUserId != null) {
      for (final m in members) {
        if (m.id == primaryUserId) continue;
        final rel = m.relationship.toLowerCase();
        String edgeType = 'FAMILY_OF';
        if (rel.contains('father') || rel.contains('dad')) {
          edgeType = 'FATHER_OF';
        } else if (rel.contains('mother') || rel.contains('mom')) {
          edgeType = 'MOTHER_OF';
        } else if (rel.contains('spouse') || rel.contains('wife') || rel.contains('husband')) {
          edgeType = 'SPOUSE_OF';
        } else if (rel.contains('child') || rel.contains('son') || rel.contains('daughter')) {
          edgeType = 'CHILD_OF';
        }

        edges.add(FamilyGraphEdge(
          sourcePersonId: m.id,
          targetPersonId: primaryUserId,
          relationType: edgeType,
        ));
      }
    }

    return FamilyGraphData(
      members: members,
      edges: edges,
      totalDocumentsCount: allDocs.length,
      totalFamilyMembersCount: members.length,
    );
  }
}
