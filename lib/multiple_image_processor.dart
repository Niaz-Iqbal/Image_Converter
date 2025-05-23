import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/widgets.dart' as pw;
import 'package:permission_handler/permission_handler.dart';
import 'package:media_scanner/media_scanner.dart'; // Import media_scanner

class MultipleImageProcessor extends StatefulWidget {
  const MultipleImageProcessor({super.key});

  @override
  State<MultipleImageProcessor> createState() => _MultipleImageProcessorState();
}

class _MultipleImageProcessorState extends State<MultipleImageProcessor> {
  final ImagePicker picker = ImagePicker();
  List<File> _images = [];

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await Permission.storage.request();
    await Permission.photos.request();
    await Permission.manageExternalStorage.request();
  }

  Future<void> _pickMultipleImages() async {
    final List<XFile>? pickedFiles = await picker.pickMultiImage();
    if (pickedFiles != null && pickedFiles.isNotEmpty) {
      setState(() {
        _images = pickedFiles.map((e) => File(e.path)).toList();
      });
    }
  }

  Future<void> _resizeImageDialog(int index) async {
    int? width;
    int? height;

    await showDialog(
      context: context,
      builder: (context) {
        final widthController = TextEditingController();
        final heightController = TextEditingController();

        return AlertDialog(
          title: const Text("Enter Dimensions"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: widthController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Width'),
              ),
              TextField(
                controller: heightController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Height'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                width = int.tryParse(widthController.text);
                height = int.tryParse(heightController.text);
                if (width != null && height != null) {
                  Navigator.pop(context);
                  await _resizeImage(index, width!, height!);
                }
              },
              child: const Text("Save"),
            ),
          ],
        );
      },
    );
  }

  Future<void> _resizeImage(int index, int width, int height) async {
    final bytes = await _images[index].readAsBytes();
    final original = img.decodeImage(bytes);
    final resized = img.copyResize(original!, width: width, height: height);

    final directory = Directory('/storage/emulated/0/Pictures/ImageConverter');
    if (!(await directory.exists())) await directory.create(recursive: true);

    final newPath =
        '${directory.path}/resized_${DateTime.now().millisecondsSinceEpoch}_${index}.jpg';
    final resizedFile = File(newPath);
    await resizedFile.writeAsBytes(img.encodeJpg(resized));

    setState(() {
      _images[index] = resizedFile;
    });

    // Scan the new image file to update the gallery
    await MediaScanner.loadMedia(path: newPath);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Resized image $index saved')),
    );
  }

  Future<void> _convertToFormat(int index, String format) async {
    final ext = format.toLowerCase();
    final bytes = await _images[index].readAsBytes();
    final original = img.decodeImage(bytes);
    List<int>? convertedBytes;

    switch (ext) {
      case 'jpg':
      case 'jpeg':
        convertedBytes = img.encodeJpg(original!);
        break;
      case 'png':
        convertedBytes = img.encodePng(original!);
        break;
      case 'bmp':
        convertedBytes = img.encodeBmp(original!);
        break;
      case 'gif':
        convertedBytes = img.encodeGif(original!);
        break;
      default:
        return;
    }

    final directory = Directory('/storage/emulated/0/Pictures/ImageConverter');
    if (!(await directory.exists())) await directory.create(recursive: true);

    final newFile =
        File('${directory.path}/converted_${DateTime.now().millisecondsSinceEpoch}_${index}.$ext');
    await newFile.writeAsBytes(convertedBytes);

    // Scan the new image file to update the gallery
    await MediaScanner.loadMedia(path: newFile.path);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Image $index saved as $ext')),
    );
  }

  Future<void> _convertToPDF(int index) async {
    final pdf = pw.Document();
    final imageBytes = await _images[index].readAsBytes();
    final image = pw.MemoryImage(imageBytes);

    pdf.addPage(pw.Page(build: (pw.Context context) {
      return pw.Center(child: pw.Image(image));
    }));

    final directory = Directory('/storage/emulated/0/Pictures/ImageConverter');
    if (!(await directory.exists())) await directory.create(recursive: true);

    final file =
        File('${directory.path}/converted_${DateTime.now().millisecondsSinceEpoch}_${index}.pdf');
    await file.writeAsBytes(await pdf.save());

    // Scan the new PDF file (though PDFs may not appear in gallery, this ensures consistency)
    await MediaScanner.loadMedia(path: file.path);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('PDF $index saved')),
    );
  }

  Widget _actionButton(
      int index, IconData icon, String label, VoidCallback onPressed) {
    return ElevatedButton.icon(
      icon: Icon(icon, size: 18),
      label: Text(label),
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.deepPurpleAccent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: 4,
        textStyle: const TextStyle(fontWeight: FontWeight.w500),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // Just pop to previous screen (SelectModeScreen)
        Navigator.pop(context);
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Multiple Image Processor'),
          backgroundColor: Colors.indigoAccent.shade200,
          centerTitle: true,
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _pickMultipleImages,
          icon: const Icon(Icons.photo_library),
          label: const Text('Pick Images'),
          backgroundColor: Colors.deepPurpleAccent,
        ),
        body: _images.isEmpty
            ? const Center(
                child: Text(
                  'No images selected',
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _images.length,
                itemBuilder: (context, index) {
                  return Card(
                    elevation: 5,
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(
                              _images[index],
                              height: 180,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.center,
                            children: [
                              _actionButton(
                                  index,
                                  Icons.crop,
                                  "Resize",
                                  () => _resizeImageDialog(index)),
                              _actionButton(index, Icons.image, "JPG",
                                  () => _convertToFormat(index, 'jpg')),
                              _actionButton(index, Icons.image_outlined, "PNG",
                                  () => _convertToFormat(index, 'png')),
                              _actionButton(
                                  index,
                                  Icons.blur_on,
                                  "BMP",
                                  () => _convertToFormat(index, 'bmp')),
                              _actionButton(index, Icons.gif, "GIF",
                                  () => _convertToFormat(index, 'gif')),
                              _actionButton(index, Icons.picture_as_pdf, "PDF",
                                  () => _convertToPDF(index)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}