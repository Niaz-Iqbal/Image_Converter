import 'dart:io';
import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/widgets.dart' as pw;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'multiple_image_processor.dart';
import 'results_folder_screen.dart';
import 'start_screen.dart';
import 'select_mode_screen.dart';
import 'package:flutter/foundation.dart'; // For compute
import 'package:media_scanner/media_scanner.dart'; // Import media_scanner

void main() {
  runApp(const ImageConverterApp());
}

class ImageConverterApp extends StatefulWidget {
  const ImageConverterApp({super.key});

  @override
  State<ImageConverterApp> createState() => _ImageConverterAppState();
}

class _ImageConverterAppState extends State<ImageConverterApp> {
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
    return MaterialApp(
      title: 'Image Converter',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigoAccent,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigoAccent,
        brightness: Brightness.dark,
      ),
      themeMode: _themeMode,
      home: StartScreen(onThemeChanged: _updateTheme),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  File? _imageFile;
  File? _originalImageFile;
  bool _isPDF = false;
  final picker = ImagePicker();
  final List<String> _formats = ['jpg', 'jpeg', 'png', 'bmp', 'gif'];
  int _selectedFormatIndex = 0;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  img.Image? _cachedImage; // Cache decoded image to avoid redundant decoding

  @override
  void initState() {
    super.initState();
    _requestPermissions();

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300), // Reduced from 800ms
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

  Future<void> _pickImage(ImageSource source) async {
    final pickedFile = await picker.pickImage(source: source);
    if (pickedFile != null) {
      setState(() {
        _imageFile = File(pickedFile.path);
        _originalImageFile = File(pickedFile.path);
        _isPDF = false;
        _cachedImage = null; // Clear cache on new image
      });
    }
  }

  String _getImageExtension(File file) {
    final extension = file.path.split('.').last.toLowerCase();
    return _formats.contains(extension) ? extension : 'png';
  }

  Future<void> _resizeImageDialog() async {
    if (_imageFile == null) return;
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
                  await _resizeImage(width!, height!);
                }
              },
              child: const Text("Save"),
            ),
          ],
        );
      },
    );
  }

  Future<void> _resizeImage(int width, int height) async {
    if (_imageFile == null) return;
    final bytes = await _imageFile!.readAsBytes();
    final result = await compute(_resizeImageIsolate, {'bytes': Uint8List.fromList(bytes), 'width': width, 'height': height});
    if (result != null) {
      final resizedFile = File(result['path'] as String);
      setState(() {
        _imageFile = resizedFile;
        _isPDF = false;
        _cachedImage = result['image'] as img.Image?;
      });
      // Scan the new image file to update the gallery
      await MediaScanner.loadMedia(path: result['path'] as String);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Resized image saved to Pictures/ImageConverter')));
    }
  }

  static Map<String, dynamic>? _resizeImageIsolate(Map<String, dynamic> args) {
    final bytes = args['bytes'] as Uint8List;
    final width = args['width'] as int;
    final height = args['height'] as int;
    final original = img.decodeImage(bytes);
    if (original == null) return null;
    final resized = img.copyResize(original, width: width, height: height);
    final ext = 'png'; // Default to PNG for simplicity
    final directory = Directory('/storage/emulated/0/Pictures/ImageConverter');
    if (!directory.existsSync()) directory.createSync(recursive: true);
    final newPath = '${directory.path}/resized_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final encodedBytes = img.encodePng(resized); // Simplified to PNG for speed
    final file = File(newPath)..writeAsBytesSync(encodedBytes);
    return {'path': newPath, 'image': resized};
  }

  Future<void> _convertToFormat() async {
    if (_imageFile == null) return;
    final bytes = await _imageFile!.readAsBytes();
    final result = await compute(_convertToFormatIsolate, {
      'bytes': Uint8List.fromList(bytes),
      'format': _formats[_selectedFormatIndex],
    });
    if (result != null) {
      final newFile = File(result['path'] as String);
      setState(() {
        _imageFile = newFile;
        _isPDF = false;
        _cachedImage = result['image'] as img.Image?;
      });
      // Scan the new image file to update the gallery
      await MediaScanner.loadMedia(path: result['path'] as String);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved as ${_formats[_selectedFormatIndex]} in Pictures/ImageConverter')));
    }
  }

  static Map<String, dynamic>? _convertToFormatIsolate(Map<String, dynamic> args) {
    final bytes = args['bytes'] as Uint8List;
    final format = args['format'] as String;
    final original = img.decodeImage(bytes);
    if (original == null) return null;
    final encodedBytes = _encodeImage(original, format);
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
        return img.encodeJpg(image, quality: 85); // Reduced quality for speed
      case 'png':
        return img.encodePng(image);
      case 'bmp':
        return img.encodeBmp(image);
      case 'gif':
        return img.encodeGif(image);
      default:
        return img.encodePng(image);
    }
  }

  Future<void> _convertToPDF() async {
    if (_imageFile == null) return;
    final bytes = await _imageFile!.readAsBytes();
    final result = await compute(_convertToPDFIsolate, Uint8List.fromList(bytes));
    if (result != null) {
      final file = File(result as String);
      setState(() {
        _imageFile = file;
        _isPDF = true;
        _cachedImage = null;
      });
      // Scan the new PDF file (though PDFs may not appear in gallery, this ensures consistency)
      await MediaScanner.loadMedia(path: result as String);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PDF saved to Documents')));
    }
  }

  static Future<String?> _convertToPDFIsolate(Uint8List bytes) async {
    final pdf = pw.Document();
    final image = pw.MemoryImage(bytes);
    pdf.addPage(pw.Page(build: (pw.Context context) => pw.Center(child: pw.Image(image))));
    final directory = Directory('/storage/emulated/0/Documents');
    if (!directory.existsSync()) directory.createSync(recursive: true);
    final filePath = '${directory.path}/converted_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final file = File(filePath);
    await file.writeAsBytes(await pdf.save()); // Use async save
    return file.path;
  }

  Future<void> _compressImageDialog() async {
    if (_imageFile == null) return;
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
            TextButton(onPressed: () async { Navigator.pop(context); await _compressImage(quality.round()); }, child: const Text("Compress")),
          ],
        ),
      ),
    );
  }

  Future<void> _compressImage(int quality) async {
    if (_imageFile == null) return;
    final bytes = await _imageFile!.readAsBytes();
    final result = await compute(_compressImageIsolate, {'bytes': Uint8List.fromList(bytes), 'quality': quality});
    if (result != null) {
      final compressedFile = File(result['path'] as String);
      setState(() {
        _imageFile = compressedFile;
        _isPDF = false;
        _cachedImage = result['image'] as img.Image?;
      });
      // Scan the new image file to update the gallery
      await MediaScanner.loadMedia(path: result['path'] as String);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Compressed image saved to Pictures/ImageConverter')));
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
    if (file == null || _isPDF) return 'N/A';
    if (_cachedImage == null) _cachedImage = img.decodeImage(file.readAsBytesSync());
    return _cachedImage != null ? '${_cachedImage!.width}x${_cachedImage!.height} px' : 'N/A';
  }

  String _getFileSize(File? file) {
    if (file == null) return 'N/A';
    return '${(file.lengthSync() / 1024).toStringAsFixed(1)} KB'; // Simplified for speed
  }

  Widget _buildImagePreview({required File? file, required String label, required bool isPDF}) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    return Column(children: [
      Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: isDarkMode ? [Colors.grey.shade900, Colors.black54] : [Colors.white10, Colors.black12], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDarkMode ? 0.4 : 0.2), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: file != null
              ? (isPDF
                  ? Container(height: 200, alignment: Alignment.center, child: const Icon(Icons.picture_as_pdf, size: 50, color: Colors.grey))
                  : Image.file(file, height: 200, width: double.infinity, fit: BoxFit.cover, cacheHeight: 400)) // Cache height for performance
              : Container(height: 200, alignment: Alignment.center, child: const Text("No Image Selected", textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
        ),
      ),
      const SizedBox(height: 8),
      Text(label, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
      const SizedBox(height: 4),
      Text(_getImageResolution(file), style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 14)),
      Text(_getFileSize(file), style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 14)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final isImageSelected = _imageFile != null;
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Image.asset('assets/logo.png', width: 40, height: 40, fit: BoxFit.cover, cacheWidth: 40, cacheHeight: 40), // Preload asset
        ),
        title: const Text('Image Converter', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: isDarkMode ? [Colors.indigo.shade900, Colors.purple.shade900] : [Colors.indigoAccent, Colors.deepPurpleAccent], begin: Alignment.topLeft, end: Alignment.bottomRight),
          ),
        ),
        centerTitle: false,
        elevation: 4, // Reduced from 8
        shadowColor: Colors.black45,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: isDarkMode ? [Colors.indigo.shade900, Colors.purple.shade900] : [Colors.indigoAccent, Colors.purpleAccent], begin: Alignment.topCenter, end: Alignment.bottomCenter),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Column(children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: isDarkMode ? [theme.colorScheme.surfaceContainerHighest.withOpacity(0.7), theme.colorScheme.surfaceContainerLow.withOpacity(0.7)] : [theme.colorScheme.surfaceContainerHighest.withOpacity(0.9), theme.colorScheme.surfaceContainerLow.withOpacity(0.9)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDarkMode ? 0.2 : 0.1), blurRadius: 15, spreadRadius: 2, offset: const Offset(0, 5))], // Reduced shadow
                    ),
                    child: Column(children: [
                      Row(children: [
                        Expanded(child: _buildImagePreview(file: _originalImageFile, label: "Original", isPDF: false)),
                        const SizedBox(width: 16),
                        Expanded(child: _buildImagePreview(file: _imageFile, label: "Converted", isPDF: _isPDF)),
                      ]),
                      const SizedBox(height: 24),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                        Expanded(child: _customButton(Icons.camera_alt, "Camera", () => _pickImage(ImageSource.camera))),
                        const SizedBox(width: 16),
                        Expanded(child: _customButton(Icons.photo, "Gallery", () => _pickImage(ImageSource.gallery))),
                      ]),
                      const SizedBox(height: 16),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Expanded(child: _customButton(Icons.swap_horiz, "Change Format", _convertToFormat)),
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
                    ]),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}//original