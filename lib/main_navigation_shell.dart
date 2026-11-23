import 'dart:ui';
import 'package:flutter/material.dart';
import 'core/theme/glass_card.dart';
import 'features/assistant/assistant_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/vault/vault_screen.dart';

class MainNavigationShell extends StatefulWidget {
  const MainNavigationShell({super.key});

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    DashboardScreen(),
    VaultScreen(),
    AssistantScreen(),
    VaultScreen(), // Expiry tab navigates to vault documents
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return GlassBackgroundWrapper(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        body: IndexedStack(
          index: _currentIndex,
          children: _screens,
        ),
        bottomNavigationBar: _buildGlassBottomBar(),
      ),
    );
  }

  Widget _buildGlassBottomBar() {
    final items = [
      {'icon': Icons.grid_view_rounded, 'label': 'Dashboard'},
      {'icon': Icons.folder_outlined, 'label': 'Vault'},
      {'icon': Icons.auto_awesome_outlined, 'label': 'AI Ask'},
      {'icon': Icons.access_time_rounded, 'label': 'Expiry'},
      {'icon': Icons.settings_outlined, 'label': 'Settings'},
    ];

    return SafeArea(
      bottom: true,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              height: 64,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.9),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List.generate(items.length, (index) {
                  final isSelected = _currentIndex == index;
                  final item = items[index];

                  if (isSelected) {
                    // Active Item: Dark Rounded Rectangle with Cyan Glow & Text
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF00F2FE).withValues(alpha: 0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            item['icon'] as IconData,
                            size: 19,
                            color: const Color(0xFF00F2FE),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item['label'] as String,
                            style: const TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF00F2FE),
                              letterSpacing: -0.2,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  // Inactive Item: Clean Muted Icon and Label
                  return InkWell(
                    onTap: () => setState(() => _currentIndex = index),
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            item['icon'] as IconData,
                            size: 19,
                            color: const Color(0xFF64748B),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item['label'] as String,
                            style: const TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF64748B),
                              letterSpacing: -0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
