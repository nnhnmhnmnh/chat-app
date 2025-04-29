import 'dart:convert';
import 'package:http/http.dart' as http;

class GeminiService {
  final String geminiApiKey;
  final String modelId;
  final String generateContentApi;

  GeminiService({
    required this.geminiApiKey,
    required this.modelId,
    required this.generateContentApi,
  });

  Stream<String> generateContent({
    required String userInput,
    List<Map<String, dynamic>> chatHistory = const [],
    String? videoUrl,
    String? systemInstruction,   // Thêm tham số tùy chọn cho systemInstruction
    double? temperature,         // Thêm tham số tùy chọn cho temperature
    bool includeTools = false,   // Tham số để chỉ định có sử dụng tools hay không
    bool generateImage = false,
  }) async* {
    // Xây dựng dữ liệu request

    final contents = [...chatHistory]; // Gộp lịch sử vào đầu

    // Thêm message mới từ người dùng (userInput)
    contents.add({
      "role": "user",
      "parts": [
        // Nếu có videoUrl, thêm fileData vào parts
        if (videoUrl != null)
        {
          "fileData": {
            "mimeType": "video/*",
            "fileUri": videoUrl,
          }
        },
        {
          "text": userInput,
        },
      ],
    });

    final requestData = {
      "contents": contents,

      // Chỉ thêm systemInstruction nếu người dùng cung cấp
      if (systemInstruction != null) "systemInstruction": {
        "parts": [
          {
            "text": systemInstruction
          },
        ]
      },
      "generationConfig": {
        "responseMimeType": "text/plain",
        if (generateImage) "responseModalities": ["image", "text"],
        // Chỉ thêm temperature nếu người dùng cung cấp
        if (temperature != null) "temperature": temperature,
      },
      // Thêm tools nếu người dùng chọn sử dụng
      if (includeTools) "tools": [
        {
          "googleSearch": {}
        },
      ],
    };

    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$modelId:$generateContentApi?key=$geminiApiKey',
    );

    // Gửi yêu cầu POST đến API Gemini
    final request = http.Request('POST', uri)
      ..headers['Content-Type'] = 'application/json'
      ..body = json.encode(requestData);

    final response = await http.Client().send(request);

    // Xử lý từng dòng stream (SSE format: "data: {...}")
    final stream = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final line in stream) {
      if (line.trim().startsWith('"text": ')) {
        final textLine = line.trim().length > 9
            ? line.trim().substring(9, line.trim().length-1)
                .replaceAll(r'\n', '\n')  // Chuyển ký tự \n thành dấu xuống dòng thực tế
                .replaceAll(r'\r', '\r')  // Chuyển ký tự \r thành carriage return thực tế
                .replaceAll(r'\t', '\t')  // Chuyển ký tự \t thành tab thực tế
            : '';
        yield textLine;
      } else if (line.trim().startsWith('"data": ')) { // file (image)
        final dataLine = line.trim();
        yield dataLine;
      } else if (line.trim().startsWith('"code": ')){ // error
        final errorCode = line.trim().length > 8
            ? line.trim().substring(8, line.trim().length-1)
            : '';
        yield "error:$errorCode";
      }
      // if (line.contains('"finishReason": "STOP"')) {print('doneeeee');break;}
    }

    // final headers = {
    //   'Content-Type': 'application/json',
    // };

    // final response = await http.post(
    //   uri,
    //   headers: headers,
    //   body: json.encode(requestData),
    // );

    // print("responseeeee: ${response.body}");

    // if (response.statusCode == 200) {
    //   // return (json.decode(response.body) as List<dynamic>).cast<Map<String, dynamic>>();
    //   final responseData = json.decode(response.body);
    //
    //   for (var chunk in responseData) {
    //     final parts = chunk['candidates'][0]['content']['parts'];
    //     for (var part in parts) {
    //       // await Future.delayed(Duration(milliseconds: 300));
    //       yield part['text']; // Dữ liệu được phát ra theo từng phần theo thời gian
    //       // print("part['text']: ${part['text']}");
    //     }
    //   }
    // } else {
    //   throw Exception('Failed to generate content: ${response.body}');
    // }
  }

}