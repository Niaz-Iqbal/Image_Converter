import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';

class CombinePdfsScreen extends StatefulWidget {
  const CombinePdfsScreen({super.key});

  @override
  State<CombinePdfsScreen> createState() => _CombinePdfsScreenState();
}

class _CombinePdfsScreenState extends State<CombinePdfsScreen>
    with SingleTickerProviderStateMixin {
  List<File> _selectedPdfs = [];
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  bool _isProcessing = false;
  final Set<String> _clickedButtons = {};
  final Set<String> _primaryButtons = {};
  final List<Animation<double>> _staggeredAnimations = [];

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _animationController.forward();
    _assignRandomButtonStyles();
  }

  void _assignRandomButtonStyles() {
    final buttons = ['Select PDFs', 'Combine'];
    final random = Random();
    for (var button in buttons) {
      if (random.nextBool()) {
        _primaryButtons.add(button);
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _requestPermissions() async {
    final permissions = [Permission.storage, Permission.manageExternalStorage];
    for (var permission in permissions) {
      if (await permission.isDenied) {
        await permission.request();
        if (await permission.isPermanentlyDenied && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Please enable storage permissions in settings',
              ),
              action: SnackBarAction(
                label: 'Open Settings',
                onPressed: () => openAppSettings(),
              ),
            ),
          );
        }
      }
    }
  }

  Future<void> _pickPdfs() async {
    if (_isProcessing) return;
    setState(() {
      _isProcessing = true;
    });
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: true,
      );
      if (result != null && mounted) {
        final newPdfs =
            result.paths.whereType<String>().map((path) => File(path)).toList();
        setState(() {
          _selectedPdfs.addAll(newPdfs);
          _initializeStaggeredAnimations();
        });
      }
    } catch (e) {
      if (mounted) {
        _showError('Error picking PDFs: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  void _initializeStaggeredAnimations() {
    _staggeredAnimations.clear();
    for (int i = 0; i < _selectedPdfs.length; i++) {
      final animation = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _animationController,
          curve: Interval(i * 0.1, 1.0, curve: Curves.easeOutCubic),
        ),
      );
      _staggeredAnimations.add(animation);
    }
    _animationController.forward(from: 0.0);
  }

  Future<void> _combinePdfs() async {
    if (_selectedPdfs.isEmpty || _isProcessing) {
      if (mounted && !_isProcessing) {
        _showError('Please select at least one PDF file');
      }
      return;
    }
    setState(() {
      _isProcessing = true;
    });
    try {
      final result = await compute(
        _combinePdfsIsolate,
        _selectedPdfs.map((file) => file.path).toList(),
      );
      if (result != null && mounted) {
        setState(() {
          _selectedPdfs = [];
          _staggeredAnimations.clear();
        });
        _showSuccess('Combined PDF saved to Documents');
      } else {
        throw Exception('Failed to combine PDFs');
      }
    } catch (e) {
      if (mounted) {
        _showError('Error combining PDFs: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  static Future<String?> _combinePdfsIsolate(List<String> pdfPaths) async {
    final pdf = pw.Document();
    for (String path in pdfPaths) {
      try {
        pdf.addPage(
          pw.Page(
            build:
                (pw.Context context) => pw.Center(
                  child: pw.Text(
                    'Placeholder for ${path.split('/').last}',
                    style: pw.TextStyle(fontSize: 20),
                  ),
                ),
          ),
        );
      } catch (e) {
        print('Error processing PDF $path: $e');
      }
    }
    final directory = Directory('/storage/emulated/0/Documents');
    if (!directory.existsSync()) directory.createSync(recursive: true);
    final outputPath =
        '${directory.path}/combined_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final outputFile = File(outputPath);
    try {
      await outputFile.writeAsBytes(await pdf.save());
      return outputPath;
    } catch (e) {
      print('Error saving combined PDF: $e');
      return null;
    }
  }

  void _showSuccess(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.blue.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Widget _buildPdfCard(File pdfFile, int index) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    return AnimatedBuilder(
      animation: _staggeredAnimations[index],
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, 50 * (1 - _staggeredAnimations[index].value)),
          child: Opacity(
            opacity: _staggeredAnimations[index].value,
            child: child,
          ),
        );
      },
      child: GestureDetector(
        onTap: () {
          _showDeleteConfirmation(pdfFile);
        },
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors:
                  isDarkMode
                      ? [Colors.indigo.shade900, Colors.purple.shade900]
                      : [Colors.white, Colors.grey.shade50],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDarkMode ? 0.2 : 0.1),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: ListTile(
            leading: const Icon(
              Icons.picture_as_pdf,
              color: Colors.blue,
              size: 36,
            ),
            title: Text(
              pdfFile.path.split('/').last,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              _getFileSize(pdfFile),
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
            trailing: ReorderableDragStartListener(
              index: index,
              child: const Icon(Icons.drag_handle, color: Colors.grey),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showDeleteConfirmation(File pdfFile) async {
    final result = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text(
              'Delete PDF',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            content: Text(
              'Remove ${pdfFile.path.split('/').last} from the list?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
    );
    if (result == true && mounted) {
      setState(() {
        _selectedPdfs.remove(pdfFile);
        _initializeStaggeredAnimations();
      });
    }
  }

  String _getFileSize(File file) {
    if (!file.existsSync()) return 'N/A';
    final sizeInKB = file.lengthSync() / 1024;
    return sizeInKB < 1024
        ? '${sizeInKB.toStringAsFixed(1)} KB'
        : '${(sizeInKB / 1024).toStringAsFixed(1)} MB';
  }

  Widget _customButton(
    IconData icon,
    String label,
    VoidCallback onPressed, {
    bool isPrimary = false,
    bool isEnabled = true,
  }) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final effectiveIsPrimary =
        isPrimary ||
        _clickedButtons.contains(label) ||
        _primaryButtons.contains(label);
    return Semantics(
      button: true,
      label: label,
      enabled: isEnabled,
      child: GestureDetector(
        onTap:
            isEnabled
                ? () {
                  if (mounted) {
                    setState(() {
                      _clickedButtons.add(label);
                    });
                    onPressed();
                  }
                }
                : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 14,
          ), // Increased padding
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors:
                  isEnabled
                      ? effectiveIsPrimary
                          ? isDarkMode
                              ? [Colors.blue.shade700, Colors.blue.shade900]
                              : [Colors.blue.shade400, Colors.blue.shade600]
                          : isDarkMode
                          ? [Colors.indigo.shade800, Colors.purple.shade800]
                          : [Colors.deepPurple.shade400, Colors.indigo.shade400]
                      : [Colors.grey.shade200, Colors.grey.shade300],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow:
                isEnabled
                    ? [
                      BoxShadow(
                        color: Colors.black.withOpacity(
                          isDarkMode ? 0.3 : 0.15,
                        ),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ]
                    : [],
            border: Border.all(
              color: isDarkMode ? Colors.grey.shade700 : Colors.grey.shade300,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: isEnabled ? Colors.white : Colors.grey.shade600,
                size: 20, // Slightly larger icon
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: isEnabled ? Colors.white : Colors.grey.shade600,
                  fontSize: 16, // Larger font size
                  fontWeight: FontWeight.w700, // Bolder text
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      height: 200,
      decoration: BoxDecoration(
        color:
            isDarkMode
                ? Colors.indigo.shade900.withOpacity(0.5)
                : Colors.white.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedScale(
            scale: _fadeAnimation.value,
            duration: const Duration(milliseconds: 300),
            child: Icon(
              Icons.picture_as_pdf,
              size: 60,
              color: isDarkMode ? Colors.blue.shade300 : Colors.blue.shade600,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No PDFs Selected',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap the button to add PDFs',
            style: TextStyle(
              fontSize: 14,
              color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return Scaffold(
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
          'Combine PDFs',
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
                      ? [Colors.blue.shade700, Colors.blue.shade900]
                      : [Colors.blue.shade400, Colors.blue.shade600],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors:
                    isDarkMode
                        ? [Colors.indigo.shade900, Colors.purple.shade900]
                        : [Colors.deepPurple.shade50, Colors.indigo.shade50],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color:
                          isDarkMode
                              ? Colors.indigo.shade900.withOpacity(0.85)
                              : Colors.white.withOpacity(0.95),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(
                            isDarkMode ? 0.2 : 0.1,
                          ),
                          blurRadius: 12,
                          spreadRadius: 2,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_selectedPdfs.isEmpty)
                          _buildEmptyState()
                        else
                          SizedBox(
                            height: 400,
                            child: ReorderableListView(
                              onReorder: (oldIndex, newIndex) {
                                if (mounted) {
                                  setState(() {
                                    if (newIndex > oldIndex) newIndex--;
                                    final item = _selectedPdfs.removeAt(
                                      oldIndex,
                                    );
                                    _selectedPdfs.insert(newIndex, item);
                                    _initializeStaggeredAnimations();
                                  });
                                }
                              },
                              children:
                                  List.generate(
                                        _selectedPdfs.length,
                                        (index) => _buildPdfCard(
                                          _selectedPdfs[index],
                                          index,
                                        ),
                                      )
                                      .asMap()
                                      .entries
                                      .map(
                                        (entry) => KeyedSubtree(
                                          key: ValueKey(
                                            _selectedPdfs[entry.key].path,
                                          ),
                                          child: entry.value,
                                        ),
                                      )
                                      .toList(),
                            ),
                          ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            Expanded(
                              child: _customButton(
                                Icons.add,
                                'Select PDFs',
                                _pickPdfs,
                                isEnabled: !_isProcessing,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _customButton(
                                Icons.merge_type,
                                'Combine',
                                _combinePdfs,
                                isEnabled:
                                    !_isProcessing && _selectedPdfs.isNotEmpty,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_isProcessing)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Processing...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
