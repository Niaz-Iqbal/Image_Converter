import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';

class ResultsFolderScreen extends StatefulWidget {
  const ResultsFolderScreen({Key? key}) : super(key: key);

  @override
  State<ResultsFolderScreen> createState() => _ResultsFolderScreenState();
}

class _ResultsFolderScreenState extends State<ResultsFolderScreen>
    with SingleTickerProviderStateMixin {
  static const _imageDirPath = '/storage/emulated/0/Pictures/ImageConverter';
  static const _pdfDirPath = '/storage/emulated/0/Documents';
  late Directory _imageDir;
  late Directory _pdfDir;
  final ValueNotifier<List<File>> _allFilesNotifier = ValueNotifier([]);
  final ValueNotifier<List<File>> _filteredFilesNotifier = ValueNotifier([]);
  String _filter = 'all';
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  Timer? _debounceTimer;
  bool _isMultiSelectMode = false;
  Set<String> _selectedFiles = {};
  bool _isLoading = true;
  bool _isFiltering = false;
  List<Animation<double>> _staggeredAnimations = [];

  @override
  void initState() {
    super.initState();
    _imageDir = Directory(_imageDirPath);
    _pdfDir = Directory(_pdfDirPath);
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _animationController.forward();
    _loadFiles();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _allFilesNotifier.dispose();
    _filteredFilesNotifier.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _debounce(
    VoidCallback callback, {
    Duration duration = const Duration(milliseconds: 300),
  }) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(duration, callback);
  }

  Future<void> _loadFiles() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });
    _debounce(() async {
      final List<File> files = [];
      try {
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
        files.sort(
          (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error loading files: $e')));
        }
      }
      if (mounted) {
        _allFilesNotifier.value = files;
        await _applyFilter();
        _initializeStaggeredAnimations();
        setState(() {
          _isLoading = false;
        });
      }
    });
  }

  void _initializeStaggeredAnimations() {
    _staggeredAnimations.clear();
    for (int i = 0; i < _filteredFilesNotifier.value.length; i++) {
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

  Future<void> _applyFilter() async {
    if (!mounted) return;
    
    setState(() {
      _isFiltering = true;
    });

    final filteredFiles = await compute(_filterFiles, {
      'files': _allFilesNotifier.value,
      'filter': _filter,
    });

    if (mounted) {
      setState(() {
        _filteredFilesNotifier.value = filteredFiles;
        _isFiltering = false;
        _initializeStaggeredAnimations();
      });
    }
  }

  static List<File> _filterFiles(Map<String, dynamic> params) {
    final List<File> files = params['files'] as List<File>;
    final String filter = params['filter'] as String;
    return files.where((file) {
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
    if (_isMultiSelectMode) {
      _toggleSelection(file.path);
      return;
    }
    final result = await OpenFile.open(file.path);
    if (result.type != ResultType.done && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open file')));
    }
  }

  Future<void> _deleteFile(File file) async {
    final fileName = file.path.split('/').last;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          'Delete File',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to delete "$fileName"?',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
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
    if (confirm == true) {
      try {
        await file.delete();
        await _loadFiles();
      } catch (e) {
        debugPrint('Error deleting file: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Error deleting file')));
        }
      }
    }
  }

  Future<void> _deleteSelectedFiles() async {
    if (_selectedFiles.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          'Delete Files',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to delete ${_selectedFiles.length} file${_selectedFiles.length > 1 ? 's' : ''}?',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
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
    if (confirm == true) {
      try {
        await Future.wait(_selectedFiles.map((path) => File(path).delete()));
        if (mounted) {
          setState(() {
            _selectedFiles.clear();
            _isMultiSelectMode = false;
          });
          await _loadFiles();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${_selectedFiles.length} file${_selectedFiles.length > 1 ? 's' : ''} deleted',
              ),
            ),
          );
        }
      } catch (e) {
        debugPrint('Error deleting files: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error deleting some files')),
          );
          await _loadFiles();
        }
      }
    }
  }

  Future<void> _renameFile(File file) async {
    final oldName = file.path.split('/').last;
    final controller = TextEditingController(text: oldName);
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
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
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Error renaming file')),
                    );
                  }
                }
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  void _toggleSelection(String filePath) {
    setState(() {
      if (_selectedFiles.contains(filePath)) {
        _selectedFiles.remove(filePath);
      } else {
        _selectedFiles.add(filePath);
      }
      if (_selectedFiles.isEmpty) {
        _isMultiSelectMode = false;
      }
    });
  }

  void _toggleMultiSelectMode() {
    setState(() {
      _isMultiSelectMode = !_isMultiSelectMode;
      _selectedFiles.clear();
    });
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

  String _getFileSize(File file) {
    try {
      if (file.existsSync()) {
        return _formatFileSize(file.lengthSync());
      }
      return 'N/A';
    } catch (e) {
      return 'Error';
    }
  }

  void _setFilter(String value) {
    if (_filter != value && mounted) {
      setState(() {
        _filter = value;
      });
      _applyFilter();
    }
  }

  Widget _buildFilterChip(String label, String value) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final isSelected = _filter == value;

    return GestureDetector(
      onTap: () => _setFilter(value),
      child: AnimatedScale(
        scale: isSelected ? 1.05 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            gradient: isSelected
                ? LinearGradient(
                    colors: isDarkMode
                        ? [Colors.blue.shade700, Colors.blue.shade900]
                        : [Colors.blue.shade400, Colors.blue.shade600],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: isSelected
                ? null
                : (isDarkMode ? Colors.grey.shade800 : Colors.white),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDarkMode ? 0.2 : 0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
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
        color: isDarkMode
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
              Icons.folder_open,
              size: 60,
              color: isDarkMode ? Colors.blue.shade300 : Colors.blue.shade600,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No Files Found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Convert or combine files to see them here',
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
              color: isDarkMode
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
        title: Text(
          _isMultiSelectMode
              ? '${_selectedFiles.length} Selected'
              : 'Results Folder',
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 20,
            color: Colors.white,
          ),
        ),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDarkMode
                  ? [Colors.blue.shade700, Colors.blue.shade900]
                  : [Colors.blue.shade400, Colors.blue.shade600],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          if (!_isMultiSelectMode)
            IconButton(
              icon: const Icon(Icons.select_all, color: Colors.white),
              onPressed: _toggleMultiSelectMode,
              tooltip: 'Select Files',
            ),
          if (_isMultiSelectMode) ...[
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: _selectedFiles.isNotEmpty ? _deleteSelectedFiles : null,
              tooltip: 'Delete Selected',
            ),
            IconButton(
              icon: const Icon(Icons.cancel, color: Colors.white),
              onPressed: _toggleMultiSelectMode,
              tooltip: 'Cancel',
            ),
          ],
        ],
      ),
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDarkMode
                    ? [Colors.indigo.shade900, Colors.purple.shade900]
                    : [Colors.deepPurple.shade50, Colors.indigo.shade50],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12.0,
                      horizontal: 16.0,
                    ),
                    decoration: BoxDecoration(
                      color: isDarkMode
                          ? Colors.indigo.shade900.withOpacity(0.85)
                          : Colors.white.withOpacity(0.95),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(
                            isDarkMode ? 0.2 : 0.1,
                          ),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.folder_open,
                          color: isDarkMode
                              ? Colors.blue.shade300
                              : Colors.blue.shade600,
                          size: 24.0,
                        ),
                        const SizedBox(width: 12.0),
                        ValueListenableBuilder<List<File>>(
                          valueListenable: _filteredFilesNotifier,
                          builder: (context, filteredFiles, child) {
                            return Text(
                              'Total Files: ${filteredFiles.length}',
                              style: TextStyle(
                                fontSize: 18.0,
                                fontWeight: FontWeight.w600,
                                color: isDarkMode
                                    ? Colors.white
                                    : Colors.indigo.shade900,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: ValueListenableBuilder<List<File>>(
                    valueListenable: _filteredFilesNotifier,
                    builder: (context, filteredFiles, child) {
                      if (_isFiltering) {
                        return Center(
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        );
                      }
                      if (filteredFiles.isEmpty && !_isLoading) {
                        return Center(child: _buildEmptyState());
                      }
                      return FadeTransition(
                        opacity: _fadeAnimation,
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDarkMode
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
                          child: ListView.builder(
                            itemCount: filteredFiles.length,
                            itemBuilder: (context, index) {
                              final file = filteredFiles[index];
                              final fileName = file.path.split('/').last;
                              final modifiedTime = file.statSync().modified;
                              final formattedTime = DateFormat(
                                'MMM d, yyyy HH:mm',
                              ).format(modifiedTime);
                              final isSelected =
                                  _selectedFiles.contains(file.path);

                              return AnimatedBuilder(
                                animation: _staggeredAnimations[index],
                                builder: (context, child) {
                                  return Transform.translate(
                                    offset: Offset(
                                      0,
                                      50 * (1 - _staggeredAnimations[index].value),
                                    ),
                                    child: Opacity(
                                      opacity: _staggeredAnimations[index].value,
                                      child: child,
                                    ),
                                  );
                                },
                                child: Dismissible(
                                  key: ValueKey(file.path),
                                  background: Container(
                                    margin: const EdgeInsets.symmetric(
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: isDarkMode
                                            ? [
                                                Colors.blue.shade700,
                                                Colors.blue.shade900,
                                              ]
                                            : [
                                                Colors.blue.shade400,
                                                Colors.blue.shade600,
                                              ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    alignment: Alignment.centerLeft,
                                    padding: const EdgeInsets.only(left: 16),
                                    child: const Icon(
                                      Icons.edit,
                                      color: Colors.white,
                                    ),
                                  ),
                                  secondaryBackground: Container(
                                    margin: const EdgeInsets.symmetric(
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.red.shade600,
                                          Colors.red.shade800,
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    alignment: Alignment.centerRight,
                                    padding: const EdgeInsets.only(right: 16),
                                    child: const Icon(
                                      Icons.delete,
                                      color: Colors.white,
                                    ),
                                  ),
                                  confirmDismiss: _isMultiSelectMode
                                      ? null
                                      : (direction) async {
                                          if (direction ==
                                              DismissDirection.startToEnd) {
                                            _renameFile(file);
                                            return false;
                                          } else {
                                            final confirm = await showDialog<bool>(
                                              context: context,
                                              builder: (context) => AlertDialog(
                                                backgroundColor:
                                                    theme.colorScheme.surfaceContainer,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(16),
                                                ),
                                                title: const Text(
                                                  'Delete File',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                content: Text(
                                                  'Are you sure you want to delete "$fileName"?',
                                                ),
                                                actions: [
                                                  TextButton(
                                                    child: const Text('Cancel'),
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                            context, false),
                                                  ),
                                                  TextButton(
                                                    child: const Text(
                                                      'Delete',
                                                      style: TextStyle(
                                                          color: Colors.red),
                                                    ),
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                            context, true),
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
                                  onDismissed: _isMultiSelectMode
                                      ? null
                                      : (direction) {
                                          // Immediately remove the dismissed file from the list
                                          final updatedFiles = List<File>.from(
                                              _filteredFilesNotifier.value);
                                          updatedFiles.removeAt(index);
                                          _filteredFilesNotifier.value =
                                              updatedFiles;
                                          // Optionally refresh the full list asynchronously
                                          _loadFiles();
                                        },
                                  child: GestureDetector(
                                    onTap: () => _openFile(file),
                                    onLongPress: () {
                                      if (!_isMultiSelectMode) {
                                        setState(() {
                                          _isMultiSelectMode = true;
                                          _selectedFiles.add(file.path);
                                        });
                                      }
                                    },
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 200,
                                      ),
                                      margin: const EdgeInsets.symmetric(
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: isDarkMode
                                              ? [
                                                  Colors.indigo.shade900,
                                                  Colors.purple.shade900,
                                                ]
                                              : [
                                                  Colors.white,
                                                  Colors.grey.shade50,
                                                ],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(
                                              isDarkMode ? 0.2 : 0.1,
                                            ),
                                            blurRadius: 6,
                                            offset: const Offset(0, 3),
                                          ),
                                        ],
                                        border: isSelected
                                            ? Border.all(
                                                color: Colors.blue.shade600,
                                                width: 2,
                                              )
                                            : null,
                                      ),
                                      child: ListTile(
                                        leading: _isMultiSelectMode
                                            ? Checkbox(
                                                value: isSelected,
                                                onChanged: (value) =>
                                                    _toggleSelection(file.path),
                                                activeColor: Colors.blue.shade600,
                                              )
                                            : _isImageFile(file.path)
                                                ? Image.file(
                                                    file,
                                                    width: 40,
                                                    height: 40,
                                                    fit: BoxFit.cover,
                                                    cacheWidth: 40,
                                                    cacheHeight: 40,
                                                    errorBuilder: (context, error,
                                                            stackTrace) =>
                                                        const Icon(
                                                      Icons.broken_image,
                                                      size: 40,
                                                    ),
                                                  )
                                                : Icon(
                                                    Icons.picture_as_pdf,
                                                    color: Colors.blue.shade600,
                                                    size: 40,
                                                  ),
                                        title: Text(
                                          fileName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        subtitle: Text(
                                          'Size: ${_getFileSize(file)} • $formattedTime',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                        trailing: _isMultiSelectMode
                                            ? null
                                            : PopupMenuButton<String>(
                                                icon: const Icon(
                                                  Icons.more_vert,
                                                ),
                                                onSelected: (value) {
                                                  if (value == 'rename') {
                                                    _renameFile(file);
                                                  } else if (value == 'delete') {
                                                    _deleteFile(file);
                                                  }
                                                },
                                                itemBuilder: (context) => const [
                                                  PopupMenuItem(
                                                    value: 'rename',
                                                    child: Text('Rename'),
                                                  ),
                                                  PopupMenuItem(
                                                    value: 'delete',
                                                    child: Text('Delete'),
                                                  ),
                                                ],
                                              ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      );
                    },
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
          
        ],
      ),
    );
  }
}