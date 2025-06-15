import 'dart:typed_data';
import 'package:http/http.dart' as http;

class BackgroundRemover {
  static Future<Uint8List> removeBackground(
    Uint8List imageBytes,
    String apiKey,
  ) async {
    final url = Uri.parse('https://api.remove.bg/v1.0/removebg');
    final request =
        http.MultipartRequest('POST', url)
          ..headers['X-Api-Key'] = apiKey
          ..files.add(
            http.MultipartFile.fromBytes(
              'image_file',
              imageBytes,
              filename: 'image.png',
            ),
          )
          ..fields['size'] = 'auto';

    final response = await request.send();
    if (response.statusCode == 200) {
      return await response.stream.toBytes();
    } else {
      throw Exception('Failed to remove background: ${response.statusCode}');
    }
  }
}
