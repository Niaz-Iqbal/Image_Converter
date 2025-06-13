import 'dart:io';
import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/widgets.dart' as pw;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart'; // For compute
import 'package:media_scanner/media_scanner.dart'; // Import media_scanner

class MultipleImageProcessor extends StatefulWidget {
  const MultipleImageProcessor({super.key});

  @override
  State<MultipleImageProcessor> createState() => _MultipleImageProcessorState();
}

class _MultipleImageProcessorState extends State<MultipleImageProcessor> {
  ThemeMode _themeMode = ThemeMode.light;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final themeString = prefs.getString('themeMode') ?? 'light';
    if (mounted) {
      setState(() {
        _themeMode = themeString == 'dark' ? ThemeMode.dark : ThemeMode.light;
      });
    }
  }

  Future<void> _updateTheme(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('themeMode', mode == ThemeMode.dark ? 'dark' : 'light');
    if (mounted) {
      setState(() {
        _themeMode = mode;
      });
    }
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
              color: isDarkMode ? Colors.black.withOpacity(0.3) : Colors.white.withOpacity(0.8),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDarkMode ? 0.2 : 0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/logo1.png',
                width: 40,
                height: 40,
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
        title: const Text(
          'Image Converter',
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
        elevation: 4,
        shadowColor: Colors.black45,
      ),
      body: MultipleImageHomeScreen(
        themeMode: _themeMode,
        updateTheme: _updateTheme,
      ),
    );
  }
}

class MultipleImageHomeScreen extends StatefulWidget {
  final ThemeMode themeMode;
  final Function(ThemeMode) updateTheme;

  const MultipleImageHomeScreen({
    super.key,
    required this.themeMode,
    required this.updateTheme,
  });

  @override
  State<MultipleImageHomeScreen> createState() => _MultipleImageHomeScreenState();
}

class _MultipleImageHomeScreenState extends State<MultipleImageHomeScreen> with SingleTickerProviderStateMixin {
  List<File> _originalImageFiles = [];
  List<File> _processedImageFiles = [];
  final picker = ImagePicker();
  final List<String> _formats = ['jpg', 'jpeg', 'png', 'bmp', 'gif'];
  int _selectedFormatIndex = 0;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  Map<File, img.Image?> _cachedImages = {};
  bool _isConvertedToPDF = false; // Track PDF conversion state

  @override
  void initState() {
    super.initState();
    _requestPermissions();

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

  Future<void> _requestPermissions() async {
    await [
      Permission.storage,
      Permission.photos,
      Permission.camera,
      Permission.manageExternalStorage,
    ].request();
  }

  Future<void> _pickImages(ImageSource source) async {
    final pickedFiles = await picker.pickMultiImage();
    if (pickedFiles.isNotEmpty) {
      setState(() {
        _originalImageFiles = pickedFiles.map((pickedFile) => File(pickedFile.path)).toList();
        _processedImageFiles = List.from(_originalImageFiles);
        _cachedImages.clear();
        _cachedImages.addAll(Map.fromEntries(_originalImageFiles.map((file) => MapEntry(file, null))));
        _isConvertedToPDF = false; // Reset PDF state on new selection
      });
    }
  }

  String _getImageExtension(File file) {
    final extension = file.path.split('.').last.toLowerCase();
    return _formats.contains(extension) ? extension : 'png';
  }

  Future<void> _resizeImageDialog() async {
    if (_originalImageFiles.isEmpty) return;
    int? width;
    int? height;

    await showDialog(
      context: context,
      builder: (context) {
        final widthController = TextEditingController();
        final heightController = TextEditingController();
        return AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text("Enter Dimensions", style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: widthController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Width',
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerLow,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: heightController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Height',
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerLow,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
            TextButton(
              onPressed: () async {
                width = int.tryParse(widthController.text);
                height = int.tryParse(heightController.text);
                if (width != null && height != null) {
                  Navigator.pop(context);
                  await _resizeImages(width!, height!);
                  setState(() => _isConvertedToPDF = false); // Reset PDF state
                }
              },
              child: const Text("Save"),
            ),
          ],
        );
      },
    );
  }

  Future<void> _resizeImages(int width, int height) async {
    if (_originalImageFiles.isEmpty) return;
    final results = await Future.wait(_originalImageFiles.map((file) async {
      final bytes = await file.readAsBytes();
      return await compute(_resizeImageIsolate, {'bytes': Uint8List.fromList(bytes), 'width': width, 'height': height});
    }).take(5));
    final newFiles = results.whereType<Map<String, dynamic>>().map((result) => File(result['path'] as String)).toList();
    if (newFiles.isNotEmpty) {
      setState(() {
        _processedImageFiles = newFiles;
        _cachedImages.clear();
        _cachedImages.addAll(Map.fromEntries(newFiles.map((file) => MapEntry(file, null))));
      });
      for (final path in newFiles.map((file) => file.path)) {
        await MediaScanner.loadMedia(path: path);
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Resized images saved to Pictures/ImageConverter')));
    }
  }

  static Map<String, dynamic>? _resizeImageIsolate(Map<String, dynamic> args) {
    final bytes = args['bytes'] as Uint8List;
    final width = args['width'] as int;
    final height = args['height'] as int;
    final original = img.decodeImage(bytes);
    if (original == null) return null;
    final resized = img.copyResize(original, width: width, height: height);
    final directory = Directory('/storage/emulated/0/Pictures/ImageConverter');
    if (!directory.existsSync()) directory.createSync(recursive: true);
    final newPath = '${directory.path}/resized_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final encodedBytes = img.encodeJpg(resized, quality: 80);
    final file = File(newPath)..writeAsBytesSync(encodedBytes);
    return {'path': newPath, 'image': resized};
  }

  Future<void> _convertToFormat() async {
    if (_originalImageFiles.isEmpty) return;
    final results = await Future.wait(_originalImageFiles.map((file) async {
      final bytes = await file.readAsBytes();
      return await compute(_convertToFormatIsolate, {
        'bytes': Uint8List.fromList(bytes),
        'format': _formats[_selectedFormatIndex],
      });
    }).take(5));
    final newFiles = results.whereType<Map<String, dynamic>>().map((result) => File(result['path'] as String)).toList();
    if (newFiles.isNotEmpty) {
      setState(() {
        _processedImageFiles = newFiles;
        _cachedImages.clear();
        _cachedImages.addAll(Map.fromEntries(newFiles.map((file) => MapEntry(file, null))));
        _isConvertedToPDF = false; // Reset PDF state
      });
      for (final path in newFiles.map((file) => file.path)) {
        await MediaScanner.loadMedia(path: path);
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved as ${_formats[_selectedFormatIndex]} in Pictures/ImageConverter')));
    }
  }

  static Map<String, dynamic>? _convertToFormatIsolate(Map<String, dynamic> args) {
    final bytes = args['bytes'] as Uint8List;
    final format = args['format'] as String;
    final original = img.decodeImage(bytes);
    if (original == null) return null;
    final resized = img.copyResize(original, width: original.width, height: original.height);
    final encodedBytes = _encodeImage(resized, format);
    final directory = Directory('/storage/emulated/0/Pictures/ImageConverter');
    if (!directory.existsSync()) directory.createSync(recursive: true);
    final newPath = '${directory.path}/converted_${DateTime.now().millisecondsSinceEpoch}.$format';
    final file = File(newPath)..writeAsBytesSync(encodedBytes);
    return {'path': newPath, 'image': original};
  }

  static List<int> _encodeImage(img.Image image, String format) {
    switch (format) {
      case 'jpg':
      case 'jpeg':
        return img.encodeJpg(image, quality: 80);
      case 'png':
        return img.encodePng(image, level: 6);
      case 'bmp':
        return img.encodeBmp(image);
      case 'gif':
        return img.encodeGif(image);
      default:
        return img.encodeJpg(image, quality: 80);
    }
  }

  Future<void> _convertToPDF() async {
    if (_originalImageFiles.isEmpty) return;
    final results = await Future.wait(_originalImageFiles.map((file) async {
      final bytes = await file.readAsBytes();
      return await compute(_convertToPDFIsolate, Uint8List.fromList(bytes));
    }).take(5));
    final newFiles = results.whereType<String>().map((path) => File(path)).toList();
    if (newFiles.isNotEmpty) {
      setState(() {
        _processedImageFiles = newFiles;
        _cachedImages.clear();
        _isConvertedToPDF = true; // Set PDF state to true
      });
      for (final path in newFiles.map((file) => file.path)) {
        await MediaScanner.loadMedia(path: path);
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PDFs saved to Documents')));
    }
  }

  static Future<String?> _convertToPDFIsolate(Uint8List bytes) async {
    final pdf = pw.Document();
    final image = pw.MemoryImage(bytes);
    pdf.addPage(pw.Page(build: (pw.Context context) => pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain))));
    final directory = Directory('/storage/emulated/0/Documents');
    if (!directory.existsSync()) directory.createSync(recursive: true);
    final filePath = '${directory.path}/converted_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final file = File(filePath);
    await file.writeAsBytes(await pdf.save());
    return file.path;
  }

  Future<void> _compressImageDialog() async {
    if (_originalImageFiles.isEmpty) return;
    double quality = 80;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text("Compress Image", style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text("Adjust quality (lower = smaller file size):", style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            Slider(value: quality, min: 0, max: 100, divisions: 100, label: quality.round().toString(), activeColor: Colors.deepPurpleAccent, onChanged: (value) => setState(() => quality = value)),
            Text("Quality: ${quality.round()}%", style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await _compressImages(quality.round());
                setState(() => _isConvertedToPDF = false); // Reset PDF state
              },
              child: const Text("Compress"),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _compressImages(int quality) async {
    if (_originalImageFiles.isEmpty) return;
    final results = await Future.wait(_originalImageFiles.map((file) async {
      final bytes = await file.readAsBytes();
      return await compute(_compressImageIsolate, {'bytes': Uint8List.fromList(bytes), 'quality': quality});
    }).take(5));
    final newFiles = results.whereType<Map<String, dynamic>>().map((result) => File(result['path'] as String)).toList();
    if (newFiles.isNotEmpty) {
      setState(() {
        _processedImageFiles = newFiles;
        _cachedImages.clear();
        _cachedImages.addAll(Map.fromEntries(newFiles.map((file) => MapEntry(file, null))));
      });
      for (final path in newFiles.map((file) => file.path)) {
        await MediaScanner.loadMedia(path: path);
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Compressed images saved to Pictures/ImageConverter')));
    }
  }

  static Map<String, dynamic>? _compressImageIsolate(Map<String, dynamic> args) {
    final bytes = args['bytes'] as Uint8List;
    final quality = args['quality'] as int;
    final original = img.decodeImage(bytes);
    if (original == null) return null;
    final compressed = img.encodeJpg(original, quality: quality);
    final directory = Directory('/storage/emulated/0/Pictures/ImageConverter');
    if (!directory.existsSync()) directory.createSync(recursive: true);
    final newPath = '${directory.path}/compressed_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final file = File(newPath)..writeAsBytesSync(compressed);
    return {'path': newPath, 'image': original};
  }

  Widget _customButton(IconData icon, String label, VoidCallback onPressed, {int delay = 0}) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: isDarkMode ? [Colors.indigo.shade800, Colors.purple.shade800] : [Colors.deepPurpleAccent, Colors.indigoAccent], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDarkMode ? 0.4 : 0.2), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
        ]),
      ),
    );
  }

  Widget _formatChip(String format, bool isSelected) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    return GestureDetector(
      onTap: () => setState(() => _selectedFormatIndex = _formats.indexOf(format)),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          gradient: isSelected ? LinearGradient(colors: isDarkMode ? [Colors.indigo.shade800, Colors.purple.shade800] : [Colors.deepPurple, Colors.indigoAccent], begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
          color: isSelected ? null : theme.colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(20),
          boxShadow: isSelected ? [BoxShadow(color: Colors.black.withOpacity(isDarkMode ? 0.4 : 0.2), blurRadius: 5, offset: const Offset(0, 2))] : null,
        ),
        child: Text(format.toUpperCase(), style: TextStyle(color: isSelected ? Colors.white : theme.colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 12)),
      ),
    );
  }

  String _getImageResolution(File? file) {
    if (file == null) return 'N/A';
    if (_cachedImages[file] == null) {
      final bytes = file.readAsBytesSync();
      _cachedImages[file] = img.decodeImage(bytes);
    }
    return _cachedImages[file] != null ? '${_cachedImages[file]!.width}x${_cachedImages[file]!.height} px' : 'N/A';
  }

  String _getFileSize(File? file) {
    if (file == null) return 'N/A';
    return '${(file.lengthSync() / 1024).toStringAsFixed(1)} KB';
  }

  Widget _buildImagePreview({required File? file, required String label, required bool isPDF}) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    return Column(
      children: [
        Container(
          width: 150,
          height: 200,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: isDarkMode ? [Colors.grey.shade900, Colors.black54] : [Colors.white10, Colors.black12], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDarkMode ? 0.4 : 0.2), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: file != null
                ? (isPDF
                    ? Container(alignment: Alignment.center, child: const Icon(Icons.picture_as_pdf, size: 50, color: Colors.grey))
                    : Image.file(file, fit: BoxFit.cover, cacheHeight: 200))
                : Container(alignment: Alignment.center, child: const Text("No Image Selected", textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
        const SizedBox(height: 4),
        Text(_getImageResolution(file), style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 14)),
        Text(_getFileSize(file), style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 14)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isImagesSelected = _originalImageFiles.isNotEmpty;
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    return SafeArea(
      child: SingleChildScrollView(
        child: Container(
          constraints: BoxConstraints(minHeight: MediaQuery.of(context).size.height - MediaQuery.of(context).padding.top - kToolbarHeight),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDarkMode
                  ? [Colors.indigo.shade900, Colors.purple.shade900]
                  : [Colors.indigoAccent, Colors.purpleAccent],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isDarkMode
                            ? [theme.colorScheme.surfaceContainerHighest.withOpacity(0.7), theme.colorScheme.surfaceContainerLow.withOpacity(0.7)]
                            : [theme.colorScheme.surfaceContainerHighest.withOpacity(0.9), theme.colorScheme.surfaceContainerLow.withOpacity(0.9)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(isDarkMode ? 0.2 : 0.1),
                          blurRadius: 15,
                          spreadRadius: 2,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!isImagesSelected)
                          Container(
                            height: 200,
                            alignment: Alignment.center,
                            child: const Text("No Images Selected", textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          )
                        else
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Expanded(child: _buildImagePreview(file: _originalImageFiles.isNotEmpty ? _originalImageFiles[0] : null, label: "Original", isPDF: false)),
                              const SizedBox(width: 16),
                              Expanded(child: _buildImagePreview(file: _processedImageFiles.isNotEmpty ? _processedImageFiles[0] : null, label: "Converted", isPDF: _isConvertedToPDF)),
                            ],
                          ),
                        const SizedBox(height: 24),
                        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                          Expanded(child: _customButton(Icons.camera_alt, "Camera", () => _pickImages(ImageSource.camera))),
                          const SizedBox(width: 16),
                          Expanded(child: _customButton(Icons.photo, "Gallery", () => _pickImages(ImageSource.gallery))),
                        ]),
                        const SizedBox(height: 16),
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          Expanded(child: _customButton(Icons.swap_horiz, "Change", _convertToFormat)),
                          const SizedBox(width: 16),
                          Expanded(
                            child: SizedBox(
                              height: 40,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                itemCount: _formats.length,
                                itemBuilder: (context, index) => _formatChip(_formats[index], index == _selectedFormatIndex),
                              ),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 16),
                        _customButton(Icons.picture_as_pdf, "Convert to PDF", _convertToPDF),
                        const SizedBox(height: 16),
                        _customButton(Icons.crop, "Resize Image", _resizeImageDialog),
                        const SizedBox(height: 16),
                        _customButton(Icons.compress, "Compress Image", _compressImageDialog),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}//original