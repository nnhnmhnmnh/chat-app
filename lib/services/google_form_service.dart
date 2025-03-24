import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;

/// Bước 1: Lấy FB_PUBLIC_LOAD_DATA_ từ link Google Form
Future<dynamic> fetchFBPublicLoadData(String url) async {
  final response = await http.get(Uri.parse(url));
  if (response.statusCode == 200) {
    String pageContent = response.body;
    // Tìm chuỗi bắt đầu từ "FB_PUBLIC_LOAD_DATA_ = " đến đoạn kết thúc có '"/forms"'
    RegExp regExp = RegExp(r'FB_PUBLIC_LOAD_DATA_ = (.*?"/forms")', dotAll: true);
    var match = regExp.firstMatch(pageContent);
    if (match != null) {
      String jsonDataStr = match.group(1)!;
      // Thay thế chuỗi ',"/forms"' bằng dấu ngoặc vuông kết thúc
      jsonDataStr = jsonDataStr.replaceAll(',"/forms"', ']');
      try {
        var fbPublicLoadData = jsonDecode(jsonDataStr);
        return fbPublicLoadData;
      } catch (e) {
        print("Lỗi khi giải mã JSON: $e");
      }
    } else {
      print("Không tìm thấy dữ liệu FB_PUBLIC_LOAD_DATA_ trên trang.");
    }
  } else {
    print("Không thể tải trang, mã lỗi: ${response.statusCode}");
  }
  return null;
}

/// Bước 2: Chuyển FB_PUBLIC_LOAD_DATA_ thành JSON câu hỏi – câu trả lời
Map<String, List<String>> processQuestions(dynamic fbData) {
  // Lấy danh sách câu hỏi từ fbData[1][1]
  List<dynamic> questions = fbData[1][1];
  Map<String, List<String>> questionChoices = {};

  for (var q in questions) {
    // Lấy nội dung câu hỏi
    String questionText = q[1] ?? "";
    // Kiểm tra nếu có danh sách câu trả lời tại vị trí q[4]
    if (q.length > 4 && q[4] is List) {
      // Duyệt qua từng phần trong danh sách đáp án
      for (var option in q[4]) {
        if (option is List && option.length > 1 && option[1] is List) {
          List<dynamic> optionList = option[1];
          List<String> validChoices = [];
          // Lấy các đáp án không rỗng
          for (var choice in optionList) {
            if (choice is List &&
                choice.isNotEmpty &&
                choice[0] is String &&
                (choice[0] as String).isNotEmpty) {
              validChoices.add(choice[0]);
            }
          }
          if (validChoices.isNotEmpty) {
            // Ở đây bạn chỉ lấy danh sách đáp án (không cần xác suất)
            questionChoices[questionText] = validChoices;
          }
        }
      }
    }
  }
  // Xóa các câu hỏi không có đáp án
  questionChoices.removeWhere((key, value) => value.isEmpty);
  return questionChoices;
}

/// Hàm xử lý kết quả từ AI
Map<String, List<String>> processAIResponse(String rawResponse) {
  // Xử lý response (loại bỏ các định dạng không cần thiết, nếu có)
  String responseText = rawResponse
      .trim()
      .replaceAll("```json", "")
      .replaceAll("```", "");

  // Chuyển response thành đối tượng Map từ JSON
  Map<String, dynamic> data = jsonDecode(responseText);
  Map<String, List<String>> aiResponse = {};
  data.forEach((question, answers) {
    if (answers is List && answers.isNotEmpty) {
      // Ở đây ta chỉ chọn đáp án đầu tiên, có thể thay đổi logic nếu cần
      aiResponse[question] = [answers[0]];
    }
  });
  return aiResponse;
}

/// Lấy entry_mapping: { "Tên câu hỏi": "entry_id", ... }
Map<String, String> getEntryMapping(dynamic fbData) {
  List<dynamic> questions = fbData[1][1];
  Map<String, String> entryMapping = {};
  for (var q in questions) {
    if (q.length > 4 && q[4] is List && (q[4] as List).isNotEmpty) {
      var entryId = q[4][0][0];
      if (entryId != null) {
        String questionTitle = q[1] ?? "";
        entryMapping[questionTitle] = entryId.toString();
      }
    }
  }
  return entryMapping;
}

/// Tạo link auto fill với đáp án từ AI
String buildPrefilledUrl(String baseUrl, Map<String, List<String>> aiResponse,
    Map<String, String> entryMapping) {
  // URL gốc với tham số usp=pp_url
  String prefilledUrl = "$baseUrl?usp=pp_url";
  aiResponse.forEach((question, answers) {
    if (entryMapping.containsKey(question)) {
      String entryId = entryMapping[question]!;
      for (var answer in answers) {
        // Mã hóa đáp án an toàn cho URL
        String encodedAnswer = Uri.encodeComponent(answer);
        prefilledUrl += "&entry.$entryId=$encodedAnswer";
      }
    }
  });
  return prefilledUrl;
}

// Future<void> main() async {
//   // URL của Google Form
//   String url =
//       "https://docs.google.com/forms/d/e/1FAIpQLSe9pLnbYOnfY9L0JOPIu_n2JLqI2dRhmu34L5GiBgV6c_xwOw/viewform";
//
//   // Bước 1: Tải và giải mã dữ liệu
//   var fbData = await fetchFBPublicLoadData(url);
//   if (fbData == null) {
//     print("Lỗi khi tải FB_PUBLIC_LOAD_DATA_");
//     return;
//   }
//
//   // Bước 2: Xử lý dữ liệu câu hỏi - đáp án
//   Map<String, List<String>> questionChoices = processQuestions(fbData);
//   print("Question choices:");
//   print(questionChoices);
//
//   // Chuyển đổi questionChoices thành JSON string
//   String processedData = jsonEncode(questionChoices);
//   print("\nProcessed Data JSON:");
//   print(processedData);
//
//   // Bước 3: Lấy đáp án từ AI (ở đây mô phỏng chọn đáp án đầu tiên)
//   Map<String, List<String>> aiResponse = processAIResponse(processedData);
//   print("\nAI Response:");
//   print(aiResponse);
//
//   // Lấy entry mapping từ dữ liệu gốc
//   Map<String, String> entryMapping = getEntryMapping(fbData);
//
//   // Tạo đường link pre-filled
//   String prefilledUrl = buildPrefilledUrl(url, aiResponse, entryMapping);
//   print("\nPrefilled URL:");
//   print(prefilledUrl);
// }