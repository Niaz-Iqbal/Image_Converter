import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/widgets.dart' as pw;
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';
import 'package:media_scanner/media_scanner.dart';

class MultipleImageProcessor extends StatefulWidget {
  const MultipleImageProcessor({super.key});

  @override
  State<MultipleImageProcessor> createState() => _MultipleImageProcessorState();
}

class _MultipleImageProcessorState extends State<MultipleImageProcessor>
    with SingleTickerProviderStateMixin {
  List<File> _originalImageFiles = [];
  List<File> _processedImageFiles = [];
  final ImagePicker _picker = ImagePicker();
  final List<String> _formats = ['jpg', 'jpeg', 'png', 'bmp', 'gif'];
  int _selectedFormatIndex = 0;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  Map<File, img.Image?> _cachedImages = {};
  bool _isConvertedToPDF = false;
  bool _isProcessing = false;
  final Set<String> _clickedButtons = {};
  final Set<String> _primaryButtons = {};

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
    final buttons = [
      'Camera',
      'Gallery',
      'Convert',
      'Resize Images',
      'Compress Images',
    ];
    final random = Random();
    for (var button in buttons) {
      if (random.nextBool()) {
        _primaryButtons.add(button);
      }
    }
    // "Convert to PDF" is always primary
    _primaryButtons.add('Convert to PDF');
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _requestPermissions() async {
    final permissions = [
      Permission.storage,
      Permission.photos,
      Permission.camera,
      Permission.manageExternalStorage,
    ];
    for (var permission in permissions) {
      if (await permission.isDenied) {
        await permission.request();
      }
    }
  }

  Future<void> _pickImages(ImageSource source) async {
    if (_isProcessing) return;
    try {
      setState(() {
        _isProcessing = true;
      });
      final pickedFiles = await _picker.pickMultiImage();
      if (pickedFiles.isNotEmpty && mounted) {
        setState(() {
          _originalImageFiles =
              pickedFiles.map((pickedFile) => File(pickedFile.path)).toList();
          _processedImageFiles = List.from(_originalImageFiles);
          _cachedImages = Map.fromEntries(
            _originalImageFiles.map((file) => MapEntry(file, null)),
          );
          _isConvertedToPDF = false;
          _isProcessing = false;
        });
      } else {
        setState(() {
          _isProcessing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        _showError('Error picking images: $e');
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  String _getImageExtension(File file) {
    final extension = file.path.split('.').last.toLowerCase();
    return _formats.contains(extension) ? extension : 'png';
  }

  Future<void> _resizeImageDialog() async {
    if (_originalImageFiles.isEmpty || _isProcessing) return;
    int? width;
    int? height;
    final widthController = TextEditingController();
    final heightController = TextEditingController();

    await showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text(
              "Resize Images",
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: widthController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Width (px)',
                    filled: true,
                    fillColor:
                        Theme.of(context).colorScheme.surfaceContainerLow,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: heightController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Height (px)',
                    filled: true,
                    fillColor:
                        Theme.of(context).colorScheme.surfaceContainerLow,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancel"),
              ),
              TextButton(
                onPressed: () {
                  width = int.tryParse(widthController.text);
                  height = int.tryParse(heightController.text);
                  if (width != null &&
                      height != null &&
                      width! > 0 &&
                      height! > 0) {
                    Navigator.pop(context);
                    _resizeImages(width!, height!);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please enter valid dimensions.'),
                      ),
                    );
                  }
                },
                child: const Text("Resize"),
              ),
            ],
          ),
    );
  }

  Future<void> _resizeImages(int width, int height) async {
    if (_originalImageFiles.isEmpty || _isProcessing) return;
    setState(() {
      _isProcessing = true;
    });
    try {
      final results = await Future.wait(
        _originalImageFiles
            .map((file) async {
              final bytes = await file.readAsBytes();
              return await compute(_resizeImageIsolate, {
                'bytes': Uint8List.fromList(bytes),
                'width': width,
                'height': height,
              });
            })
            .take(5),
      );
      final newFiles =
          results
              .whereType<Map<String, dynamic>>()
              .map((result) => File(result['path'] as String))
              .toList();
      if (newFiles.isNotEmpty && mounted) {
        setState(() {
          _processedImageFiles = newFiles;
          _cachedImages = Map.fromEntries(
            Iterable.generate(
              newFiles.length,
              (i) => MapEntry(newFiles[i], results[i]!['image'] as img.Image?),
            ),
          );
          _isConvertedToPDF = false;
          _isProcessing = false;
        });
        for (final path in newFiles.map((file) => file.path)) {
          await MediaScanner.loadMedia(path: path);
        }
        _showSuccess('Resized images saved to Pictures/ImageConverter');
      } else {
        _showError('Failed to resize images.');
      }
    } catch (e) {
      _showError('Error resizing images: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  static Map<String, dynamic>? _resizeImageIsolate(Map<String, dynamic> args) {
    final bytes = args['bytes'] as Uint8List;
    final width = args['width'] as int;
    final height = args['height'] as int;
    final original = img.decodeImage(bytes);
    if (original == null) return null;
    final resized = img.copyResize(
      original,
      width: width,
      height: height,
      interpolation: img.Interpolation.cubic,
    );
    final directory = Directory('/storage/emulated/0/Pictures/ImageConverter');
    if (!directory.existsSync()) directory.createSync(recursive: true);
    final newPath =
        '${directory.path}/resized_${DateTime.now().millisecondsSinceEpoch}.png';
    final encodedBytes = img.encodePng(resized, level: 6);
    final file = File(newPath)..writeAsBytesSync(encodedBytes);
    return {'path': newPath, 'image': resized};
  }

  Future<void> _convertToFormat() async {
    if (_originalImageFiles.isEmpty || _isProcessing) return;
    setState(() {
      _isProcessing = true;
    });
    try {
      final results = await Future.wait(
        _originalImageFiles
            .map((file) async {
              final bytes = await file.readAsBytes();
              return await compute(_convertToFormatIsolate, {
                'bytes': Uint8List.fromList(bytes),
                'format': _formats[_selectedFormatIndex],
              });
            })
            .take(5),
      );
      final newFiles =
          results
              .whereType<Map<String, dynamic>>()
              .map((result) => File(result['path'] as String))
              .toList();
      if (newFiles.isNotEmpty && mounted) {
        setState(() {
          _processedImageFiles = newFiles;
          _cachedImages = Map.fromEntries(
            Iterable.generate(
              newFiles.length,
              (i) => MapEntry(newFiles[i], results[i]!['image'] as img.Image?),
            ),
          );
          _isConvertedToPDF = false;
          _isProcessing = false;
        });
        for (final path in newFiles.map((file) => file.path)) {
          await MediaScanner.loadMedia(path: path);
        }
        _showSuccess(
          'Converted to ${_formats[_selectedFormatIndex].toUpperCase()} in Pictures/ImageConverter',
        );
      } else {
        _showError('Failed to convert images.');
      }
    } catch (e) {
      _showError('Error converting images: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  static Map<String, dynamic>? _convertToFormatIsolate(
    Map<String, dynamic> args,
  ) {
    final bytes = args['bytes'] as Uint8List;
    final format = args['format'] as String;
    final original = img.decodeImage(bytes);
    if (original == null) return null;
    final encodedBytes = _encodeImage(original, format);
    final directory = Directory('/storage/emulated/0/Pictures/ImageConverter');
    if (!directory.existsSync()) directory.createSync(recursive: true);
    final newPath =
        '${directory.path}/converted_${DateTime.now().millisecondsSinceEpoch}.$format';
    final file = File(newPath)..writeAsBytesSync(encodedBytes);
    return {'path': newPath, 'image': original};
  }

  static List<int> _encodeImage(img.Image image, String format) {
    switch (format) {
      case 'jpg':
      case 'jpeg':
        return img.encodeJpg(image, quality: 90);
      case 'png':
        return img.encodePng(image, level: 6);
      case 'bmp':
        return img.encodeBmp(image);
      case 'gif':
        return img.encodeGif(image);
      default:
        return img.encodePng(image);
    }
  }

  Future<void> _convertToPDF() async {
    if (_originalImageFiles.isEmpty || _isProcessing) return;
    setState(() {
      _isProcessing = true;
    });
    try {
      final results = await Future.wait(
        _originalImageFiles
            .map((file) async {
              final bytes = await file.readAsBytes();
              return await compute(
                _convertToPDFIsolate,
                Uint8List.fromList(bytes),
              );
            })
            .take(5),
      );
      final newFiles =
          results.whereType<String>().map((path) => File(path)).toList();
      if (newFiles.isNotEmpty && mounted) {
        setState(() {
          _processedImageFiles = newFiles;
          _cachedImages = Map.fromEntries(
            newFiles.map((file) => MapEntry(file, null)),
          );
          _isConvertedToPDF = true;
          _isProcessing = false;
        });
        for (final path in newFiles.map((file) => file.path)) {
          await MediaScanner.loadMedia(path: path);
        }
        _showSuccess('PDFs saved to Documents');
      } else {
        _showError('Failed to convert to PDFs.');
      }
    } catch (e) {
      _showError('Error converting to PDFs: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  static Future<String?> _convertToPDFIsolate(Uint8List bytes) async {
    final pdf = pw.Document();
    final image = pw.MemoryImage(bytes);
    pdf.addPage(
      pw.Page(
        build:
            (pw.Context context) =>
                pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
      ),
    );
    final directory = Directory('/storage/emulated/0/Documents');
    if (!directory.existsSync()) directory.createSync(recursive: true);
    final filePath =
        '${directory.path}/converted_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final file = File(filePath);
    await file.writeAsBytes(await pdf.save());
    return file.path;
  }

  Future<void> _compressImageDialog() async {
    if (_originalImageFiles.isEmpty || _isProcessing) return;
    double quality = 80;

    await showDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setState) => AlertDialog(
                  backgroundColor:
                      Theme.of(context).colorScheme.surfaceContainer,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  title: const Text(
                    "Compress Images",
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "Adjust quality (lower = smaller file size):",
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Slider(
                        value: quality,
                        min: 10,
                        max: 100,
                        divisions: 90,
                        label: quality.round().toString(),
                        activeColor: Theme.of(context).colorScheme.primary,
                        onChanged: (value) => setState(() => quality = value),
                      ),
                      Text(
                        "Quality: ${quality.round()}%",
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("Cancel"),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _compressImages(quality.round());
                      },
                      child: const Text("Compress"),
                    ),
                  ],
                ),
          ),
    );
  }

  Future<void> _compressImages(int quality) async {
    if (_originalImageFiles.isEmpty || _isProcessing) return;
    setState(() {
      _isProcessing = true;
    });
    try {
      final results = await Future.wait(
        _originalImageFiles
            .map((file) async {
              final bytes = await file.readAsBytes();
              return await compute(_compressImageIsolate, {
                'bytes': Uint8List.fromList(bytes),
                'quality': quality,
              });
            })
            .take(5),
      );
      final newFiles =
          results
              .whereType<Map<String, dynamic>>()
              .map((result) => File(result['path'] as String))
              .toList();
      if (newFiles.isNotEmpty && mounted) {
        setState(() {
          _processedImageFiles = newFiles;
          _cachedImages = Map.fromEntries(
            Iterable.generate(
              newFiles.length,
              (i) => MapEntry(newFiles[i], results[i]!['image'] as img.Image?),
            ),
          );
          _isConvertedToPDF = false;
          _isProcessing = false;
        });
        for (final path in newFiles.map((file) => file.path)) {
          await MediaScanner.loadMedia(path: path);
        }
        _showSuccess('Compressed images saved to Pictures/ImageConverter');
      } else {
        _showError('Failed to compress images.');
      }
    } catch (e) {
      _showError('Error compressing images: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  static Map<String, dynamic>? _compressImageIsolate(
    Map<String, dynamic> args,
  ) {
    final bytes = args['bytes'] as Uint8List;
    final quality = args['quality'] as int;
    final original = img.decodeImage(bytes);
    if (original == null) return null;
    final compressed = img.encodeJpg(original, quality: quality);
    final directory = Directory('/storage/emulated/0/Pictures/ImageConverter');
    if (!directory.existsSync()) directory.createSync(recursive: true);
    final newPath =
        '${directory.path}/compressed_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final file = File(newPath)..writeAsBytesSync(compressed);
    return {'path': newPath, 'image': original};
  }

  void _showSuccess(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Theme.of(context).colorScheme.primary,
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
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
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
    // Make button primary if clicked or in _primaryButtons
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
                  setState(() {
                    _clickedButtons.add(label);
                  });
                  onPressed();
                }
                : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: isEnabled ? Colors.white : Colors.grey.shade600,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  Widget _formatChip(String format, bool isSelected) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    return Semantics(
      selected: isSelected,
      label: 'Format $format',
      enabled: !_isProcessing && _originalImageFiles.isNotEmpty,
      child: GestureDetector(
        onTap:
            _isProcessing || _originalImageFiles.isEmpty
                ? null
                : () {
                  if (mounted) {
                    setState(
                      () => _selectedFormatIndex = _formats.indexOf(format),
                    );
                  }
                },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            gradient:
                isSelected
                    ? LinearGradient(
                      colors:
                          isDarkMode
                              ? [Colors.blue.shade700, Colors.blue.shade900]
                              : [Colors.blue.shade400, Colors.blue.shade600],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                    : null,
            color:
                isSelected
                    ? null
                    : isDarkMode
                    ? Colors.indigo.shade800
                    : Colors.deepPurple.shade400,
            borderRadius: BorderRadius.circular(20),
            boxShadow:
                isSelected
                    ? [
                      BoxShadow(
                        color: Colors.black.withOpacity(isDarkMode ? 0.2 : 0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ]
                    : [],
          ),
          child: Text(
            format.toUpperCase(),
            style: TextStyle(
              color:
                  isSelected
                      ? Colors.white
                      : isDarkMode
                      ? Colors.white70
                      : Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  String _getImageResolution(File? file) {
    if (file == null || _isConvertedToPDF) return 'N/A';
    if (_cachedImages[file] == null && file.existsSync()) {
      final bytes = file.readAsBytesSync();
      _cachedImages[file] = img.decodeImage(bytes);
    }
    return _cachedImages[file] != null
        ? '${_cachedImages[file]!.width}x${_cachedImages[file]!.height} px'
        : 'N/A';
  }

  String _getFileSize(File? file) {
    if (file == null || !file.existsSync()) return 'N/A';
    final sizeInKB = file.lengthSync() / 1024;
    return sizeInKB < 1024
        ? '${sizeInKB.toStringAsFixed(1)} KB'
        : '${(sizeInKB / 1024).toStringAsFixed(1)} MB';
  }

  Widget _buildImagePreview({
    required File? file,
    required String label,
    required bool isPDF,
  }) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    return Semantics(
      label: '$label image preview',
      child: Column(
        children: [
          Container(
            width: 150,
            height: 180,
            decoration: BoxDecoration(
              color: isDarkMode ? Colors.indigo.shade900 : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDarkMode ? 0.2 : 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child:
                  file != null && file.existsSync()
                      ? isPDF
                          ? const Center(
                            child: Icon(
                              Icons.picture_as_pdf,
                              size: 40,
                              color: Colors.grey,
                            ),
                          )
                          : Image.file(
                            file,
                            fit: BoxFit.contain,
                            height: 180,
                            cacheHeight: 360,
                            errorBuilder:
                                (context, error, stackTrace) => const Center(
                                  child: Text(
                                    'Error loading image',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ),
                          )
                      : const Center(
                        child: Text(
                          'No Image',
                          style: TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                      ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
            ),
          ),
          Text(
            _getImageResolution(file),
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          Text(
            _getFileSize(file),
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 12,
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
    final isImagesSelected = _originalImageFiles.isNotEmpty;

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
          'Batch Image Converter',
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
                      ? [Colors.blue.shade800, Colors.blue.shade900]
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
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!isImagesSelected)
                          Container(
                            height: 180,
                            alignment: Alignment.center,
                            child: Text(
                              "Select Images to Begin",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          )
                        else
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              Expanded(
                                child: _buildImagePreview(
                                  file:
                                      _originalImageFiles.isNotEmpty
                                          ? _originalImageFiles[0]
                                          : null,
                                  label: "Original",
                                  isPDF: false,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildImagePreview(
                                  file:
                                      _processedImageFiles.isNotEmpty
                                          ? _processedImageFiles[0]
                                          : null,
                                  label: "Converted",
                                  isPDF: _isConvertedToPDF,
                                ),
                              ),
                            ],
                          ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            Expanded(
                              child: _customButton(
                                Icons.camera_alt,
                                "Camera",
                                () => _pickImages(ImageSource.camera),
                                isEnabled: !_isProcessing,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _customButton(
                                Icons.photo,
                                "Gallery",
                                () => _pickImages(ImageSource.gallery),
                                isEnabled: !_isProcessing,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Text(
                          "Convert Format",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onSurface,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _customButton(
                                Icons.swap_horiz,
                                "Convert",
                                _convertToFormat,
                                isEnabled: !_isProcessing && isImagesSelected,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: SizedBox(
                                height: 36,
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: _formats.length,
                                  itemBuilder:
                                      (context, index) => _formatChip(
                                        _formats[index],
                                        index == _selectedFormatIndex,
                                      ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        _customButton(
                          Icons.picture_as_pdf,
                          "Convert to PDF",
                          _convertToPDF,
                          isPrimary: true,
                          isEnabled: !_isProcessing && isImagesSelected,
                        ),
                        const SizedBox(height: 12),
                        _customButton(
                          Icons.crop,
                          "Resize Images",
                          _resizeImageDialog,
                          isEnabled: !_isProcessing && isImagesSelected,
                        ),
                        const SizedBox(height: 12),
                        _customButton(
                          Icons.compress,
                          "Compress Images",
                          _compressImageDialog,
                          isEnabled: !_isProcessing && isImagesSelected,
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
                      "Processing...",
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
