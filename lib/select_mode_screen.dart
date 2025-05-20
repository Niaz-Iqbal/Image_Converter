// select_mode_screen.dart
import 'package:flutter/material.dart';
import 'multiple_image_processor.dart';
import 'results_folder_screen.dart';
import 'main.dart';
import 'settings_screen.dart';
import 'combine_pdfs_screen.dart'; // Import the new file

class SelectModeScreen extends StatelessWidget {
  final Function(ThemeMode) onThemeChanged;

  const SelectModeScreen({super.key, required this.onThemeChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context);
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          leading: Padding(
            padding: const EdgeInsets.all(8.0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/logo.png',
                width: 40,
                height: 40,
                fit: BoxFit.cover, // Fills the space and removes black corners
              ),
            ),
          ),
          title: const Text(
            'Image Converter',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
              shadows: [
                Shadow(
                  color: Colors.black26,
                  offset: Offset(1, 1),
                  blurRadius: 2,
                ),
              ],
            ),
          ),
          flexibleSpace: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDarkMode
                    ? [Colors.indigo.shade900, Colors.purple.shade900]
                    : [Colors.indigoAccent, Colors.deepPurpleAccent],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          centerTitle: false,
          actions: [
            IconButton(
              icon: const Icon(Icons.settings, color: Colors.white),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SettingsScreen(onThemeChanged: onThemeChanged),
                  ),
                );
              },
              tooltip: 'Settings',
            ),
          ],
          elevation: 8,
          shadowColor: Colors.black45,
        ),
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDarkMode
                  ? [Colors.indigo.shade900, Colors.purple.shade900]
                  : [Colors.indigoAccent, Colors.purpleAccent],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildAnimatedButton(
                    context: context,
                    icon: Icons.photo_camera,
                    title: 'Single Image',
                    subtitle: 'Create, Resize, Format, Create PDF',
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const HomeScreen()),
                      );
                    },
                    delay: 200,
                  ),
                  const SizedBox(height: 24),
                  _buildAnimatedButton(
                    context: context,
                    icon: Icons.photo_library,
                    title: 'Multiple Images',
                    subtitle: 'Create, Resize, Format, Create PDF',
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const MultipleImageProcessor()),
                      );
                    },
                    delay: 400,
                  ),
                  const SizedBox(height: 24),
                  _buildAnimatedButton(
                    context: context,
                    icon: Icons.merge_type,
                    title: 'Combine PDFs',
                    subtitle: 'Merge multiple PDFs into one',
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const CombinePdfsScreen()),
                      );
                    },
                    delay: 600,
                  ),
                  const SizedBox(height: 24),
                  _buildAnimatedButton(
                    context: context,
                    icon: Icons.folder_open,
                    title: 'Results Folder',
                    subtitle: 'View and manage converted files',
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ResultsFolderScreen()),
                      );
                    },
                    delay: 800,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedButton({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onPressed,
    required int delay,
  }) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return AnimatedOpacity(
      opacity: 1.0,
      duration: Duration(milliseconds: 600 + delay),
      curve: Curves.easeInOut,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        child: Tooltip(
          message: title,
          child: GestureDetector(
            onTap: onPressed,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDarkMode
                      ? [Colors.indigo.shade800, Colors.purple.shade800]
                      : [Colors.deepPurpleAccent, Colors.indigoAccent],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDarkMode ? 0.4 : 0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(
                    icon,
                    color: Colors.white,
                    size: 28,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            shadows: [
                              Shadow(
                                color: Colors.black26,
                                offset: Offset(1, 1),
                                blurRadius: 2,
                              ),
                            ],
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
                  const Icon(
                    Icons.arrow_forward_ios,
                    color: Colors.white70,
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}