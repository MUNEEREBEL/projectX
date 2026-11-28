import 'package:flutter/material.dart';
import '../../core/services/family_graph_service.dart';

class FamilyGraphDialog extends StatefulWidget {
  const FamilyGraphDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const FamilyGraphDialog(),
    );
  }

  @override
  State<FamilyGraphDialog> createState() => _FamilyGraphDialogState();
}

class _FamilyGraphDialogState extends State<FamilyGraphDialog> {
  FamilyGraphData? _graphData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadGraph();
  }

  Future<void> _loadGraph() async {
    try {
      final data = await FamilyGraphService.buildFamilyGraph();
      if (mounted) {
        setState(() {
          _graphData = data;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // Drag Handle
          const SizedBox(height: 12),
          Container(
            width: 44,
            height: 4.5,
            decoration: BoxDecoration(
              color: const Color(0xFFCBD5E1),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(height: 14),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.hub_rounded, color: Color(0xFF2563EB), size: 20),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Family Knowledge Graph',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                            letterSpacing: -0.3,
                          ),
                        ),
                        Text(
                          'Entity Resolution & Civic Coverage Gaps',
                          style: TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ],
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B), size: 20),
                ),
              ],
            ),
          ),
          const Divider(height: 24, thickness: 1, color: Color(0xFFE2E8F0)),

          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _graphData == null || _graphData!.members.isEmpty
                    ? const Center(child: Text('No family members registered in vault yet.'))
                    : ListView(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        children: [
                          // 1. Overview Stats Banner
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF0F172A).withValues(alpha: 0.15),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _buildStatColumn('Family Entities', '${_graphData!.totalFamilyMembersCount}', const Color(0xFF38BDF8)),
                                Container(width: 1, height: 36, color: const Color(0xFF334155)),
                                _buildStatColumn('Vault Records', '${_graphData!.totalDocumentsCount}', const Color(0xFF4ADE80)),
                                Container(width: 1, height: 36, color: const Color(0xFF334155)),
                                _buildStatColumn('Relational Edges', '${_graphData!.edges.length}', const Color(0xFFFBBF24)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),

                          // 2. Family Entity Cards
                          const Text(
                            'Family Nodes & Document Coverage',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F172A),
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 10),

                          ..._graphData!.members.map((member) => _buildMemberCard(member)),
                          const SizedBox(height: 20),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatColumn(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildMemberCard(FamilyMemberNode member) {
    final completeness = member.completenessPercentage;
    final isComplete = completeness >= 100;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Name, Relationship Pill, Completeness
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFFEFF6FF),
                child: Text(
                  member.name.isNotEmpty ? member.name[0].toUpperCase() : '?',
                  style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF2563EB), fontSize: 14),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member.name,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            member.relationship,
                            style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${member.documentCount} docs',
                          style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isComplete ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$completeness% Civic Health',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isComplete ? const Color(0xFF16A34A) : const Color(0xFFD97706),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Categories Present Chips
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: member.categoriesPresent.map((cat) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check, size: 10, color: Color(0xFF2563EB)),
                    const SizedBox(width: 3),
                    Text(
                      cat,
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF1D4ED8)),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),

          // Missing Coverage Warning (Research Recommendation)
          if (member.missingCategories.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 12, color: Color(0xFFD97706)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Missing civic records: ${member.missingCategories.take(2).join(", ")}',
                      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFFB45309)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
