// results_folder_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:intl/intl.dart';

class ResultsFolderScreen extends StatefulWidget {
  const ResultsFolderScreen({Key? key}) : super(key: key);

  @override
  State<ResultsFolderScreen> createState() => _ResultsFolderScreenState();
}

class _ResultsFolderScreenState extends State<ResultsFolderScreen> with SingleTickerProviderStateMixin {
  static const _imageDirPath = '/storage/emulated/0/Pictures/ImageConverter';
  static const _pdfDirPath = '/storage/emulated/0/Documents';
  late Directory _imageDir;
  late Directory _pdfDir;
  List<File> _allFiles = [];
  List<File> _filteredFiles = [];
  String _filter = 'all';
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _imageDir = Directory(_imageDirPath);
    _pdfDir = Directory(_pdfDirPath);
    _loadFiles();

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadFiles() async {
    final List<File> files = [];
    
    if (await _imageDir.exists()) {
      await for (final entity in _imageDir.list(recursive: false)) {
        if (entity is File) {
          final path = entity.path.toLowerCase();
          if (path.endsWith('.jpg') ||
              path.endsWith('.jpeg') ||
              path.endsWith('.png') ||
              path.endsWith('.bmp') ||
              path.endsWith('.gif')) {
            files.add(entity);
          }
        }
      }
    }

    if (await _pdfDir.exists()) {
      await for (final entity in _pdfDir.list(recursive: false)) {
        if (entity is File && entity.path.toLowerCase().endsWith('.pdf')) {
          files.add(entity);
        }
      }
    }

    files.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));

    if (mounted) {
      setState(() {
        _allFiles = files;
        _applyFilter();
      });
    }
  }

  void _applyFilter() {
    _filteredFiles = _allFiles.where((file) {
      final path = file.path.toLowerCase();
      if (_filter == 'images') {
        return path.endsWith('.jpg') ||
            path.endsWith('.jpeg') ||
            path.endsWith('.png') ||
            path.endsWith('.bmp') ||
            path.endsWith('.gif');
      } else if (_filter == 'pdfs') {
        return path.endsWith('.pdf');
      }
      return true;
    }).toList();
  }

  Future<void> _openFile(File file) async {
    final result = await OpenFile.open(file.path);
    if (result.type != ResultType.done) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open file')),
      );
    }
  }

  Future<void> _deleteFile(File file) async {
    final fileName = file.path.split('/').last;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
        title: const Text('Delete File', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text(
          'Are you sure you want to delete "$fileName"?',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await file.delete();
        await _loadFiles();
      } catch (e) {
        debugPrint('Error deleting file: $e');
      }
    }
  }

  Future<void> _renameFile(File file) async {
    final oldName = file.path.split('/').last;
    final controller = TextEditingController(text: oldName);

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
        title: const Text('Rename File', style: TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: 'New file name',
            filled: true,
            fillColor: Theme.of(context).colorScheme.surfaceContainerLow,
            border: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty && newName != oldName) {
                final newPath = '${file.parent.path}/$newName';
                try {
                  await file.rename(newPath);
                  Navigator.pop(context);
                  await _loadFiles();
                } catch (e) {
                  Navigator.pop(context);
                  debugPrint('Error renaming file: $e');
                }
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  bool _isImageFile(String path) {
    final ext = path.toLowerCase();
    return ext.endsWith('.jpg') ||
        ext.endsWith('.jpeg') ||
        ext.endsWith('.png') ||
        ext.endsWith('.bmp') ||
        ext.endsWith('.gif');
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb > 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${kb.toStringAsFixed(1)} KB';
  }

  void _setFilter(String value) {
    setState(() {
      _filter = value;
      _applyFilter();
    });
  }

  Widget _buildFilterChip(String label, String value) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final isSelected = _filter == value;

    return GestureDetector(
      onTap: () => _setFilter(value),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(
                  colors: isDarkMode
                      ? [Colors.indigo.shade800, Colors.purple.shade800]
                      : [Colors.deepPurple, Colors.indigoAccent],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isSelected ? null : theme.colorScheme.surfaceContainer,
          borderRadius: const BorderRadius.all(Radius.circular(20)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : theme.colorScheme.onSurface,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        leading: const Padding(
          padding: EdgeInsets.all(8.0),
          child: Image(
            image: AssetImage('assets/logo.png'),
            width: 40,
            height: 40,
            fit: BoxFit.cover,
          ),
        ),
        title: const Text(
          'Results Folder',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
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
        elevation: 2,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDarkMode
                ? [Colors.indigo.shade900, Colors.purple.shade900]
                : [Colors.indigo.shade50, Colors.purple.shade50],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: _filteredFiles.isEmpty
                  ? const Center(
                      child: Text(
                        'No files found.',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                    )
                  : FadeTransition(
                      opacity: _fadeAnimation,
                      child: ListView.builder(
                        itemCount: _filteredFiles.length,
                        itemBuilder: (context, index) {
                          final file = _filteredFiles[index];
                          final fileName = file.path.split('/').last;
                          final modifiedTime = file.statSync().modified;
                          final formattedTime = DateFormat('MMM d, yyyy HH:mm').format(modifiedTime);

                          return Dismissible(
                            key: ValueKey(file.path),
                            background: Container(
                              margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
                              decoration: const BoxDecoration(
                                color: Colors.blueAccent,
                                borderRadius: BorderRadius.all(Radius.circular(8)),
                              ),
                              alignment: Alignment.centerLeft,
                              padding: const EdgeInsets.only(left: 16),
                              child: const Icon(Icons.edit, color: Colors.white),
                            ),
                            secondaryBackground: Container(
                              margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
                              decoration: const BoxDecoration(
                                color: Colors.redAccent,
                                borderRadius: BorderRadius.all(Radius.circular(8)),
                              ),
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 16),
                              child: const Icon(Icons.delete, color: Colors.white),
                            ),
                            confirmDismiss: (direction) async {
                              if (direction == DismissDirection.startToEnd) {
                                _renameFile(file);
                                return false;
                              } else {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    shape: const RoundedRectangleBorder(
                                      borderRadius: BorderRadius.all(Radius.circular(8)),
                                    ),
                                    title: const Text('Delete File', style: TextStyle(fontWeight: FontWeight.bold)),
                                    content: Text('Are you sure you want to delete "$fileName"?'),
                                    actions: [
                                      TextButton(
                                        child: const Text('Cancel'),
                                        onPressed: () => Navigator.pop(context, false),
                                      ),
                                      TextButton(
                                        child: const Text('Delete', style: TextStyle(color: Colors.red)),
                                        onPressed: () => Navigator.pop(context, true),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  await file.delete();
                                  return true;
                                }
                              }
                              return false;
                            },
                            onDismissed: (direction) => _loadFiles(),
                            child: Card(
                              margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
                              elevation: 1,
                              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
                              child: ListTile(
                                leading: _isImageFile(file.path)
                                    ? Image.file(
                                        file,
                                        width: 40,
                                        height: 40,
                                        fit: BoxFit.cover,
                                        cacheWidth: 80,
                                        cacheHeight: 80,
                                      )
                                    : const Icon(Icons.insert_drive_file, size: 40),
                                title: Text(
                                  fileName,
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  'Size: ${_formatFileSize(file.lengthSync())} • $formattedTime',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                onTap: () => _openFile(file),
                                trailing: PopupMenuButton<String>(
                                  icon: const Icon(Icons.more_vert),
                                  onSelected: (value) {
                                    if (value == 'rename') {
                                      _renameFile(file);
                                    } else if (value == 'delete') {
                                      _deleteFile(file);
                                    }
                                  },
                                  itemBuilder: (context) => const [
                                    PopupMenuItem(value: 'rename', child: Text('Rename')),
                                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildFilterChip('All', 'all'),
                  _buildFilterChip('Images', 'images'),
                  _buildFilterChip('PDFs', 'pdfs'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}