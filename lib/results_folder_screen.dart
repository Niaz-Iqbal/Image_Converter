// results_folder_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart'; // For compute

class ResultsFolderScreen extends StatefulWidget {
  const ResultsFolderScreen({Key? key}) : super(key: key);

  @override
  State<ResultsFolderScreen> createState() => _ResultsFolderScreenState();
}

class _ResultsFolderScreenState extends State<ResultsFolderScreen> with SingleTickerProviderStateMixin {
  late Directory resultsDir;
  List<FileSystemEntity> files = [];
  String _filter = 'all';
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  bool _isSelectionMode = false;
  Set<String> _selectedFiles = {};

  @override
  void initState() {
    super.initState();
    resultsDir = Directory('/storage/emulated/0/Pictures/ImageConverter');
    _loadFiles();

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
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

  Future<void> _loadFiles() async {
    final filteredFiles = await compute(_loadFilesIsolate, {'path': resultsDir.path, 'filter': _filter});
    setState(() {
      files = filteredFiles;
      _selectedFiles.clear();
      if (_isSelectionMode && filteredFiles.isEmpty) {
        _isSelectionMode = false;
      }
    });
  }

  static List<FileSystemEntity> _loadFilesIsolate(Map<String, dynamic> params) {
    final dir = Directory(params['path'] as String);
    final filter = params['filter'] as String;

    if (!dir.existsSync()) return [];

    final fileList = dir.listSync().whereType<File>().toList();
    fileList.sort((a, b) {
      final aModified = (a as File).statSync().modified;
      final bModified = (b as File).statSync().modified;
      return bModified.compareTo(aModified);
    });

    return fileList.where((file) {
      final path = file.path.toLowerCase();
      if (filter == 'images') {
        return path.endsWith('.jpg') ||
            path.endsWith('.jpeg') ||
            path.endsWith('.png') ||
            path.endsWith('.bmp') ||
            path.endsWith('.gif');
      } else if (filter == 'pdfs') {
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete File',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to delete "$fileName"?',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
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
      try {
        await file.delete();
        await _loadFiles();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File deleted')),
        );
      } catch (e) {
        debugPrint('Error deleting file: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not delete file')),
        );
      }
    }
  }

  Future<void> _deleteSelectedFiles() async {
    if (_selectedFiles.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Selected Files',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to delete ${_selectedFiles.length} file${_selectedFiles.length > 1 ? 's' : ''}?',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
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
      int deletedCount = 0;
      for (final path in _selectedFiles) {
        try {
          final file = File(path);
          await file.delete();
          deletedCount++;
        } catch (e) {
          debugPrint('Error deleting file $path: $e');
        }
      }
      await _loadFiles();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$deletedCount file${deletedCount > 1 ? 's' : ''} deleted'),
        ),
      );
      setState(() {
        _isSelectionMode = false;
        _selectedFiles.clear();
      });
    }
  }

  Future<void> _renameFile(File file) async {
    final oldName = file.path.split('/').last;
    final TextEditingController controller = TextEditingController(text: oldName);

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Rename File',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: 'New file name',
            filled: true,
            fillColor: Theme.of(context).colorScheme.surfaceContainerLow,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context),
          ),
          TextButton(
            child: const Text('Rename'),
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty && newName != oldName) {
                final newPath = '${file.parent.path}/$newName';
                try {
                  await file.rename(newPath);
                  Navigator.pop(context);
                  await _loadFiles();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('File renamed')),
                  );
                } catch (e) {
                  debugPrint('Error renaming file: $e');
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Rename failed')),
                  );
                }
              }
            },
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
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }

  void _setFilter(String value) {
    setState(() {
      _filter = value;
      _selectedFiles.clear();
      _isSelectionMode = false;
    });
    _loadFiles();
  }

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      _selectedFiles.clear();
    });
  }

  void _toggleFileSelection(String filePath) {
    setState(() {
      if (_selectedFiles.contains(filePath)) {
        _selectedFiles.remove(filePath);
      } else {
        _selectedFiles.add(filePath);
      }
      if (_selectedFiles.isEmpty) {
        _isSelectionMode = false;
      }
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
          borderRadius: BorderRadius.circular(20),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDarkMode ? 0.2 : 0.1),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : theme.colorScheme.onSurface,
            fontWeight: FontWeight.bold,
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
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Image.asset(
            'assets/logo.png',
            width: 40,
            height: 40,
            fit: BoxFit.cover,
            cacheWidth: 40,
            cacheHeight: 40,
          ),
        ),
        title: Text(
          _isSelectionMode ? '${_selectedFiles.length} Selected' : 'Results Folder',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
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
        elevation: 4,
        shadowColor: Colors.black45,
        actions: [
          IconButton(
            icon: Icon(_isSelectionMode ? Icons.close : Icons.select_all),
            color: Colors.white,
            onPressed: _toggleSelectionMode,
          ),
          if (_isSelectionMode && _selectedFiles.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.white),
              onPressed: _deleteSelectedFiles,
            ),
        ],
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
        child: Column(
          children: [
            Expanded(
              child: files.isEmpty
                  ? Center(
                      child: Text(
                        'No files found in Results folder.',
                        style: TextStyle(
                          fontSize: 18,
                          color: theme.colorScheme.onSurface.withOpacity(0.7),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                  : FadeTransition(
                      opacity: _fadeAnimation,
                      child: ListView.builder(
                        itemCount: files.length,
                        itemBuilder: (context, index) {
                          final file = files[index];
                          final fileName = file.path.split('/').last;
                          final fileObj = File(file.path);
                          final modifiedTime = fileObj.statSync().modified;
                          final formattedTime = DateFormat('MMM d, yyyy, h:mm a').format(modifiedTime);
                          final isSelected = _selectedFiles.contains(file.path);

                          return Dismissible(
                            key: Key(file.path),
                            background: Container(
                              margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                              decoration: BoxDecoration(
                                color: Colors.blueAccent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              alignment: Alignment.centerLeft,
                              padding: const EdgeInsets.only(left: 20),
                              child: const Icon(Icons.edit, color: Colors.white),
                            ),
                            secondaryBackground: Container(
                              margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                              decoration: BoxDecoration(
                                color: Colors.redAccent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              child: const Icon(Icons.delete, color: Colors.white),
                            ),
                            confirmDismiss: _isSelectionMode
                                ? null
                                : (direction) async {
                                    if (direction == DismissDirection.startToEnd) {
                                      _renameFile(fileObj);
                                      return false;
                                    } else if (direction == DismissDirection.endToStart) {
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                          title: const Text(
                                            'Delete File',
                                            style: TextStyle(fontWeight: FontWeight.bold),
                                          ),
                                          content: Text(
                                            'Are you sure you want to delete "$fileName"?',
                                            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.of(context).pop(false),
                                              child: const Text('Cancel'),
                                            ),
                                            TextButton(
                                              onPressed: () => Navigator.of(context).pop(true),
                                              child: const Text('Delete', style: TextStyle(color: Colors.red)),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (confirm == true) {
                                        await fileObj.delete();
                                        return true;
                                      }
                                    }
                                    return false;
                                  },
                            onDismissed: _isSelectionMode
                                ? null
                                : (direction) async {
                                    setState(() {
                                      files.removeAt(index);
                                    });
                                    await _loadFiles();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('$fileName deleted')),
                                    );
                                  },
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: isDarkMode
                                      ? [
                                          theme.colorScheme.surfaceContainerHighest.withOpacity(isSelected ? 0.9 : 0.7),
                                          theme.colorScheme.surfaceContainerLow.withOpacity(isSelected ? 0.9 : 0.7),
                                        ]
                                      : [
                                          theme.colorScheme.surfaceContainerHighest.withOpacity(isSelected ? 1.0 : 0.9),
                                          theme.colorScheme.surfaceContainerLow.withOpacity(isSelected ? 1.0 : 0.9),
                                        ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(isDarkMode ? 0.2 : 0.1),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                leading: _isImageFile(file.path)
                                    ? Image.file(
                                        fileObj,
                                        width: 50,
                                        height: 50,
                                        fit: BoxFit.cover,
                                        cacheWidth: 100,
                                        cacheHeight: 100,
                                      )
                                    : Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.black54,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Icon(
                                          Icons.insert_drive_file,
                                          color: Colors.white,
                                          size: 30,
                                        ),
                                      ),
                                title: Text(
                                  fileName,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Size: ${_formatFileSize(fileObj.lengthSync())}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: theme.colorScheme.onSurface.withOpacity(0.7),
                                      ),
                                    ),
                                    Text(
                                      'Last Edited: $formattedTime',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: theme.colorScheme.onSurface.withOpacity(0.7),
                                      ),
                                    ),
                                  ],
                                ),
                                onTap: _isSelectionMode
                                    ? () => _toggleFileSelection(file.path)
                                    : () => _openFile(fileObj),
                                trailing: _isSelectionMode
                                    ? Checkbox(
                                        value: isSelected,
                                        activeColor: isDarkMode ? Colors.indigoAccent : Colors.deepPurple,
                                        checkColor: Colors.white,
                                        onChanged: (value) => _toggleFileSelection(file.path),
                                      )
                                    : PopupMenuButton<String>(
                                        icon: Icon(Icons.more_vert, color: theme.colorScheme.onSurface),
                                        onSelected: (value) {
                                          if (value == 'rename') {
                                            _renameFile(fileObj);
                                          } else if (value == 'delete') {
                                            _deleteFile(fileObj);
                                          }
                                        },
                                        itemBuilder: (context) => [
                                          const PopupMenuItem(value: 'rename', child: Text('Rename')),
                                          const PopupMenuItem(value: 'delete', child: Text('Delete')),
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