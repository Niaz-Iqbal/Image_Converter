import 'dart:io';
import 'dart:typed_data'; // For Uint8List
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart'; // For compute

class CombinePdfsScreen extends StatefulWidget {
  const CombinePdfsScreen({super.key});

  @override
  State<CombinePdfsScreen> createState() => _CombinePdfsScreenState();
}

class _CombinePdfsScreenState extends State<CombinePdfsScreen> with SingleTickerProviderStateMixin {
  List<File> _selectedPdfs = [];
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

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
      Permission.manageExternalStorage,
    ].request();
  }

  Future<void> _pickPdfs() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      allowMultiple: true,
    );

    if (result != null) {
      setState(() {
        _selectedPdfs = result.paths.map((path) => File(path!)).toList();
      });
    }
  }

  Future<void> _combinePdfs() async {
    if (_selectedPdfs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one PDF file')),
      );
      return;
    }

    // Offload PDF combining to an isolate
    final result = await compute(_combinePdfsIsolate, _selectedPdfs.map((file) => file.path).toList());
    if (result != null) {
      final outputFile = File(result);
      setState(() {
        _selectedPdfs = [];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Combined PDF saved to Documents')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error combining PDFs')),
      );
    }
  }

  static Future<String?> _combinePdfsIsolate(List<String> pdfPaths) async {
    final pdf = pw.Document();

    // Add a page for each selected PDF (placeholder content)
    for (String path in pdfPaths) {
      pdf.addPage(
        pw.Page(
          build: (pw.Context context) => pw.Center(
            child: pw.Text(
              'Content from ${path.split('/').last}',
              style: const pw.TextStyle(fontSize: 20),
            ),
          ),
        ),
      );
    }

    final directory = Directory('/storage/emulated/0/Documents');
    if (!directory.existsSync()) directory.createSync(recursive: true);

    final outputPath = '${directory.path}/combined_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final outputFile = File(outputPath);
    await outputFile.writeAsBytes(await pdf.save());
    return outputPath;
  }

  Widget _buildPdfCard(File pdfFile) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDarkMode
              ? [Colors.grey.shade900, Colors.black54]
              : [Colors.white10, Colors.black12],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDarkMode ? 0.2 : 0.1), // Reduced shadow intensity
            blurRadius: 5, // Reduced from 10
            offset: const Offset(0, 2), // Reduced from 4
          ),
        ],
      ),
      child: ListTile(
        leading: const Icon(
          Icons.picture_as_pdf,
          color: Colors.grey,
          size: 40,
        ),
        title: Text(
          pdfFile.path.split('/').last,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
        ),
        subtitle: Text(
          _getFileSize(pdfFile),
          style: TextStyle(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 14,
          ),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete, color: Colors.red),
          onPressed: () {
            setState(() {
              _selectedPdfs.remove(pdfFile);
            });
          },
        ),
      ),
    );
  }

  String _getFileSize(File file) {
    final sizeInBytes = file.lengthSync();
    return '${(sizeInBytes / 1024).toStringAsFixed(1)} KB'; // Simplified for speed
  }

  Widget _customButton(IconData icon, String label, VoidCallback onPressed, {int delay = 0}) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
              color: Colors.black.withOpacity(isDarkMode ? 0.2 : 0.1), // Reduced shadow intensity
              blurRadius: 5, // Reduced from 10
              offset: const Offset(0, 2), // Reduced from 4
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
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
            cacheWidth: 40, // Preload asset
            cacheHeight: 40,
          ),
        ),
        title: const Text(
          'Combine PDFs',
          style: TextStyle(
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
        elevation: 4, // Reduced from 8
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
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isDarkMode
                              ? [
                                  theme.colorScheme.surfaceContainerHighest.withOpacity(0.7),
                                  theme.colorScheme.surfaceContainerLow.withOpacity(0.7),
                                ]
                              : [
                                  theme.colorScheme.surfaceContainerHighest.withOpacity(0.9),
                                  theme.colorScheme.surfaceContainerLow.withOpacity(0.9),
                                ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(isDarkMode ? 0.2 : 0.1), // Reduced shadow intensity
                            blurRadius: 15, // Reduced from 25
                            spreadRadius: 2, // Reduced from 5
                            offset: const Offset(0, 5), // Reduced from 10
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          if (_selectedPdfs.isEmpty)
                            Container(
                              height: 200,
                              alignment: Alignment.center,
                              child: Text(
                                "No PDFs Selected",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            )
                          else
                            Column(
                              children: _selectedPdfs.map((pdfFile) => _buildPdfCard(pdfFile)).toList(),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Expanded(
                      child: _customButton(
                        Icons.add,
                        "Select PDFs",
                        _pickPdfs,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _customButton(
                        Icons.merge_type,
                        "Combine",
                        _combinePdfs,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}//original