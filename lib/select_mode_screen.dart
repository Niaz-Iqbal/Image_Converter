import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'multiple_image_processor.dart';
import 'results_folder_screen.dart';
import 'main.dart';
import 'settings_screen.dart';
import 'combine_pdfs_screen.dart';
import 'image_editor_screen.dart';

class SelectModeScreen extends StatefulWidget {
  final Function(ThemeMode) onThemeChanged;

  const SelectModeScreen({super.key, required this.onThemeChanged});

  @override
  State<SelectModeScreen> createState() => _SelectModeScreenState();
}

class _SelectModeScreenState extends State<SelectModeScreen>
    with SingleTickerProviderStateMixin {
  bool _isNavigating = false; // Prevent multiple clicks
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  DateTime? _lastBackPressTime; // For double-tap-to-exit

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<bool> _onWillPop() async {
    if (_isNavigating) return false;
    final now = DateTime.now();
    if (_lastBackPressTime == null ||
        now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
      _lastBackPressTime = now;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Press back again to exit'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(10)),
            ),
          ),
        );
      }
      return false;
    }
    return true;
  }

  void _navigateTo(Widget screen) async {
    if (_isNavigating || !mounted) return;
    setState(() {
      _isNavigating = true;
    });
    await Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => screen,
        transitionDuration: const Duration(milliseconds: 300),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
    if (mounted) {
      setState(() {
        _isNavigating = false;
      });
    }
  }

  Widget _buildAnimatedButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onPressed,
    required int delay,
  }) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    return Semantics(
      button: true,
      label: title,
      hint: subtitle,
      enabled: !_isNavigating,
      child: GestureDetector(
        onTap: _isNavigating ? null : onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors:
                  isDarkMode
                      ? [Colors.indigo.shade700, Colors.blue.shade800]
                      : [Colors.indigo.shade400, Colors.blue.shade500],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow:
                _isNavigating
                    ? []
                    : [
                      BoxShadow(
                        color: Colors.black.withOpacity(
                          isDarkMode ? 0.3 : 0.15,
                        ),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
            border: Border.all(
              color: isDarkMode ? Colors.grey.shade700 : Colors.grey.shade300,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.7),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                color: Colors.white.withOpacity(0.7),
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          leading: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Container(
              decoration: BoxDecoration(
                color:
                    isDarkMode
                        ? Colors.black.withOpacity(0.4)
                        : Colors.white.withOpacity(0.9),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDarkMode ? 0.2 : 0.1),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  'assets/logo1.png',
                  width: 36,
                  height: 36,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          title: const Text(
            'Image Converter',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 20,
              color: Colors.white,
            ),
          ),
          flexibleSpace: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors:
                    isDarkMode
                        ? [Colors.indigo.shade800, Colors.blue.shade900]
                        : [Colors.indigo.shade400, Colors.blue.shade500],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          elevation: 0,
          backgroundColor: Colors.transparent,
          actions: [
            IconButton(
              icon: const Icon(Icons.settings, color: Colors.white),
              onPressed:
                  _isNavigating
                      ? null
                      : () => _navigateTo(
                        SettingsScreen(onThemeChanged: widget.onThemeChanged),
                      ),
              tooltip: 'Settings',
            ),
          ],
        ),
        body: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors:
                      isDarkMode
                          ? [Colors.indigo.shade900, Colors.grey.shade900]
                          : [Colors.indigo.shade50, Colors.grey.shade50],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth > 600;
                    return Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 24,
                        ),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: isWide ? 600 : double.infinity,
                          ),
                          child: FadeTransition(
                            opacity: _fadeAnimation,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _buildAnimatedButton(
                                  icon: Icons.photo_camera,
                                  title: 'Single Image',
                                  subtitle:
                                      'Convert, resize, format, or create PDF',
                                  onPressed:
                                      () => _navigateTo(
                                        HomeScreen(
                                          onThemeChanged: widget.onThemeChanged,
                                        ),
                                      ),
                                  delay: 0,
                                ),
                                _buildAnimatedButton(
                                  icon: Icons.photo_library,
                                  title: 'Multiple Images',
                                  subtitle:
                                      'Batch convert, resize, or create PDFs',
                                  onPressed:
                                      () => _navigateTo(
                                        const MultipleImageProcessor(),
                                      ),
                                  delay: 100,
                                ),
                                _buildAnimatedButton(
                                  icon: Icons.edit,
                                  title: 'Edit Image',
                                  subtitle:
                                      'Adjust brightness, rotate, apply filters',
                                  onPressed:
                                      () => _navigateTo(
                                        const ImageEditorScreen(),
                                      ),
                                  delay: 200,
                                ),
                                _buildAnimatedButton(
                                  icon: Icons.merge_type,
                                  title: 'Combine PDFs',
                                  subtitle: 'Merge multiple PDFs into one',
                                  onPressed:
                                      () => _navigateTo(
                                        const CombinePdfsScreen(),
                                      ),
                                  delay: 300,
                                ),
                                _buildAnimatedButton(
                                  icon: Icons.folder_open,
                                  title: 'Results Folder',
                                  subtitle: 'View and manage converted files',
                                  onPressed:
                                      () => _navigateTo(
                                        const ResultsFolderScreen(),
                                      ),
                                  delay: 400,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            if (_isNavigating)
              Container(
                color: Colors.black.withOpacity(0.5),
                child: const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.indigo),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
