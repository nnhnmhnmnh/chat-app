import 'dart:async';
import 'dart:convert';
import 'dart:io';
// import 'dart:js_interop';
import 'package:chatapp/screens/image_viewer_screen.dart';
import 'package:chatapp/screens/setting_screen.dart';
import 'package:chatapp/screens/video_player_screen.dart';
import 'package:clipboard/clipboard.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'package:url_launcher/url_launcher.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../app_localizations.dart';
import '../services/gemini_service.dart';
import '../services/google_form_service.dart';
import '../widget/modal.dart';
import '../widget/audio_player_item.dart';
import 'package:mime/mime.dart';

class ChatScreen extends StatefulWidget {
  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<DocumentSnapshot> _chatHistories = []; // Lịch sử nhiều phiên chat từ Firestore
  List<Map<String, dynamic>> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final TextEditingController _systemInstructionController = TextEditingController();
  late GenerativeModel _model; // Model để tạo nội dung
  late GenerativeModel _namedModel; // Model để tạo tên đoạn chat
  late ChatSession _chat; // Phiên trò chuyện
  String? _currentChatId; // Lưu ID của đoạn chat hiện tại
  String? _currentChatName;
  User? _currentUser = FirebaseAuth.instance.currentUser;
  bool _isFirstMessage = true;
  bool _isExpanded = false; // Kiểm tra trạng thái mở rộng của modal
  List<Map<String, String>> _suggestions = []; // <name:..., avatarUrl:...>
  List<Map<String, String>> _allCustomNames = [];
  // late StreamSubscription _listener;
  String? selectedFilePath;
  List<File> _selectedImages = [];
  List<File> _selectedFiles = [];
  // final ScrollController _scrollController = ScrollController();
  final Map<String, Future<String?>> _videoThumbnailCache = {}; // (video_url, path)
  final _searchController = TextEditingController();
  List<DocumentSnapshot> _filteredChatHistories = [];
  StreamSubscription<QuerySnapshot>? _chatHistoriesSubscription;
  StreamSubscription<QuerySnapshot>? _suggestionsSubscription;
  bool _isLoading = false; // for send message button
  int _selectedIndex = -1;
  final FocusNode _messageFocusNode = FocusNode();
  final ImagePicker _picker = ImagePicker();
  bool _isRecordingAudio = false;
  Duration _recordDuration = Duration.zero;
  Timer? _recordTimer;
  final Record _audioRecorder = Record();
  bool _isTemporaryChat = false;
  var fbData;
  String gFormUrl = "";
  bool _isLoadingChat = false;
  String _tokenCount = "0";
  final _generateContentApi = 'streamGenerateContent';
  bool _isSearch = false;
  bool _isGenImage = false;
  List<Uri> _selectedYouTubes = [];
  bool _isAvatarEnabled = false;
  String _currentChatbotAvatar = '';


  final apiKey = dotenv.env['API_KEY']!;
  String _selectedModel = 'gemini-2.0-flash';
  double _temperature = 1.0;
  final List<String> _models = [
    // 'gemini-1.5-flash-8b',
    // 'gemini-1.5-flash',
    // 'gemini-1.5-pro',
    // 'gemini-2.0-flash-lite-preview-02-05',
    'gemini-2.0-flash-lite',
    'gemini-2.0-flash',
    'gemini-2.0-pro-exp-02-05',
    'gemini-2.0-flash-thinking-exp-01-21',
    'gemini-2.5-pro-exp-03-25',
    // 'gemini-2.0-flash-exp-image-generation',
  ];
  // Tạm thời lưu trữ các giá trị để khôi phục nếu thoát modal mà không nhấn Apply
  late String _tempModel;
  late double _tempTemperature;
  late String _tempSystemInstruction;
  late bool _tempIsTemporaryChat;


  @override
  void initState() {
    super.initState();
    _initializeModel();
    _loadChatHistories();
    _fetchSuggestions();
    _fetchDefaultBot();
    _loadAvatarSetting();

    // Lắng nghe thay đổi từ ô tìm kiếm chat histories
    _searchController.addListener(() {
      setState(() {
        String query = _searchController.text.toLowerCase();
        _filteredChatHistories = _chatHistories.where((chatDoc) {
          final chatData = chatDoc.data() as Map<String, dynamic>;
          final chatName = chatData['name'] as String? ?? '';
          return chatName.toLowerCase().contains(query);
        }).toList();
      });
    });

    _controller.addListener(() {
      final text = _controller.text;
      if (text.contains('@')) {
        final query = text.split('@').last.trim();
        _updateSuggestions(query);
      } else {
        _suggestions.clear();
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _systemInstructionController.dispose();
    // _scrollController.dispose();
    // _listener.cancel();
    _chatHistoriesSubscription?.cancel();
    _messageFocusNode.dispose();

    _searchController.dispose();
    _suggestionsSubscription?.cancel();

    super.dispose();
  }

  Future<void> _initializeModel() async {
    // final apiKey = Platform.environment['GEMINI_API_KEY'];
    if (apiKey == null) {
      throw Exception('No GEMINI_API_KEY environment variable set.');
    }

    _model = GenerativeModel(
      model: _selectedModel,
      apiKey: apiKey,
      generationConfig: GenerationConfig(
        temperature: _temperature,
        topK: 40,
        topP: 0.95,
        maxOutputTokens: 8192,
        responseMimeType: 'text/plain',
      ),
      systemInstruction: Content.system(
        _systemInstructionController.text.trim().isEmpty
            ? ''
            : _systemInstructionController.text.trim(),
      ),
    );

    _chat = _model.startChat(history: []);

    // Model đặt tên đoạn chat
    _namedModel = GenerativeModel(
      model: 'gemini-2.0-flash-lite',
      apiKey: apiKey,
      systemInstruction: Content.system(
          '''
          You're an AI chat title expert.
          Task: Use the first user message + AI reply to make a short title (max 5 words) in the same language.
          Tips: Be clear and concise. Focus on key content. Skip greetings or filler. If unsure, use main keywords.
          '''
      ),
    );
  }

  Future<void> _loadAvatarSetting() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isAvatarEnabled = prefs.getBool('isAvatarEnabled') ?? false;
    });
  }

  Future<void> _loadChatHistories() async {
    if (_currentUser == null) return;
    _chatHistoriesSubscription = _firestore
        .collection('chat_histories')
        .where('userId', isEqualTo: _currentUser!.uid)
        .orderBy('created_at', descending: true) // 'created_at' mới nhất trước
        .snapshots()
        .listen((snapshot) {
      setState(() {
        _chatHistories = snapshot.docs;
        _filteredChatHistories = List.from(_chatHistories);
      });
    });
  }

  Future<void> _saveCurrentChat() async {
    if (_messages.isEmpty) return;

    if (_currentUser == null) return; // Nếu người dùng chưa đăng nhập, thoát ra

    final chatData = {
      'name': _currentChatName ?? 'Unnamed Chat',
      'messages': _messages,
      'userId': _currentUser?.uid,
      'created_at': FieldValue.serverTimestamp(),
      // Lưu các thông số cấu hình
      'model': _selectedModel,
      'temperature': _temperature,
      'systemInstruction': _systemInstructionController.text.trim(),
    };

    if (_currentChatId == null) {
      // Tạo đoạn chat mới nếu chưa có ID
      final docRef =
        await _firestore.collection('chat_histories').add(chatData);
      _currentChatId = docRef.id;

      // Sau khi lưu, làm mới danh sách
      // _loadChatHistories();
    } else {
      // Cập nhật đoạn chat hiện tại
      await _firestore
          .collection('chat_histories')
          .doc(_currentChatId)
          .update(chatData);
    }
  }

  Future<void> _viewChatHistory(DocumentSnapshot chatDoc) async {
    if (_currentUser == null) return;

    final chatData = chatDoc.data() as Map<String, dynamic>;
    final messages = List<Map<String, dynamic>>.from(chatData['messages']);

    // setState(() {
    //   _isLoadingChat = true; // Bắt đầu hiển thị loading
    // });

    // Chờ 1 chút để tránh chặn UI
    // await Future.delayed(Duration(milliseconds: 300));

    _messages = messages;
    _currentChatId = chatDoc.id; // Gán ID đoạn chat hiện tại
    _currentChatName = chatData['name'] as String?;
    _currentChatbotAvatar = messages.last['avatar'] ?? '';
    _isFirstMessage = false;

    // Tải lại cấu hình từ dữ liệu
    _selectedModel = chatData['model'] as String;
    _temperature = chatData['temperature'] as double;
    _systemInstructionController.text =
    chatData['systemInstruction'] as String;

    // Khởi tạo lại _model với thông số đã tải
    await _updateModelConfigForCurrentChat();
    // _scrollToBottom();
    // setState(() {
    //   _isLoadingChat = false; // Ẩn loading khi load xong
    // });
  }

  Future<void> _pickImages() async {
    // Cho phép chọn nhiều file cùng lúc, chỉ lọc ra ảnh và video
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: [
        'jpg', 'png', 'webp',
        'mp4', 'flv', 'webm',
      ],
    );
    if (result != null) {
      // Chuyển danh sách file được chọn sang List<File>
      List<File> files = result.paths.map((path) => File(path!)).toList();
      setState(() {
        _selectedImages = files;
      });
    }
  }

  Future<void> _pickFiles() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom, // Chọn loại tệp tùy chỉnh
      allowedExtensions: ['mp3','wav','aac','flac','m4a','ogg','pdf','json','xml'],
      allowMultiple: true,  // Cho phép chọn nhiều tệp
    );

    if (result != null) {
      setState(() {
        // Thêm các tệp mới vào danh sách hiện có
        _selectedFiles.addAll(result.paths
            .where((path) => path != null)
            .map((path) => File(path!))
            .toList());

        // Loại bỏ các tệp bị trùng (nếu có)
        _selectedFiles = _selectedFiles.fold<Map<String, File>>({}, (map, file) {
          map[file.path] = file;
          return map;
        }).values.toList();
      });
    }
    // TODO: sendMessageStream
  }

  void _removeFile(File file) {
    setState(() {
      _selectedFiles.remove(file);
    });
  }

  // Chụp ảnh từ camera
  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.camera);
    if (image != null) {
      setState(() {
        _selectedImages.add(File(image.path));
      });
    }
  }

  // Quay video từ camera
  Future<void> _pickVideo() async {
    final XFile? video = await _picker.pickVideo(source: ImageSource.camera);
    if (video != null) {
      setState(() {
        _selectedImages.add(File(video.path));
      });
    }
  }

  // Hiển thị lựa chọn chụp ảnh hoặc quay video
  void _showCaptureOptions() {
    showModalBottomSheet(
      context: context,
      builder: (_) => Wrap(
        children: [
          ListTile(
            leading: Icon(Icons.camera_alt),
            title: Text('Chụp ảnh'),
            onTap: () {
              Navigator.of(context).pop();
              _pickImage();
            },
          ),
          ListTile(
            leading: Icon(Icons.videocam),
            title: Text('Quay video'),
            onTap: () {
              Navigator.of(context).pop();
              _pickVideo();
            },
          ),
        ],
      ),
    );
  }

  // Hàm bắt đầu ghi âm inline
  Future<void> _startRecordingAudio() async {
    bool hasPermission = await _audioRecorder.hasPermission();
    if (!hasPermission) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Không có quyền ghi âm.")),
      );
      return;
    }
    Directory tempDir = await getTemporaryDirectory();
    String filePath = path.join(tempDir.path, '${DateTime.now().millisecondsSinceEpoch}.ogg');
    try {
      await _audioRecorder.start(
        path: filePath,
        encoder: AudioEncoder.opus,
      );
      setState(() {
        _isRecordingAudio = true;
        _recordDuration = Duration.zero;
      });
      _recordTimer = Timer.periodic(Duration(seconds: 1), (timer) {
        setState(() {
          _recordDuration = Duration(seconds: _recordDuration.inSeconds + 1);
        });
      });
    } catch (e) {
      // print("Error starting recording: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Không thể bắt đầu ghi âm: $e")),
      );
    }
  }

  // Hàm dừng ghi âm inline
  Future<void> _stopRecordingAudio() async {
    try {
      String? filePath = await _audioRecorder.stop();
      _recordTimer?.cancel();
      setState(() {
        _isRecordingAudio = false;
      });
      if (filePath != null) {
        setState(() {
          _selectedFiles.add(File(filePath));
        });
      }
    } catch (e) {
      // print("Error stopping recording: $e");
    }
  }

  Widget _showAudioRecording() {
    return _isRecordingAudio
        ? Container(
          margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.shadow,
            borderRadius: BorderRadius.circular(26),
            // border: Border.all(color: Colors.redAccent, width: 0.5),
            // boxShadow: [
            //   BoxShadow(
            //     color: Colors.redAccent.withOpacity(0.2),
            //     blurRadius: 8,
            //     offset: Offset(0, 4),
            //   ),
            // ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Phần bên trái: biểu tượng mic và thời gian ghi âm
              Row(
                children: [
                  Icon(Icons.mic, color: Colors.redAccent, size: 28),
                  SizedBox(width: 8),
                  Text(
                    formatDuration(_recordDuration),
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              // Phần bên phải: nút dừng ghi âm với biểu tượng lớn
              IconButton(
                icon: Icon(Icons.stop_circle, color: Colors.redAccent, size: 50),
                onPressed: _stopRecordingAudio,
              ),
            ],
          ),
        )
        : SizedBox.shrink();
  }

  String formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes);
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$minutes:$seconds";
  }

  Widget _showFilesPicked() {
    return _selectedFiles.isEmpty
        ? SizedBox.shrink()
        : Padding(
          padding: const EdgeInsets.all(8.0),
          child: Wrap(
            spacing: 8.0, // Khoảng cách ngang giữa các khung
            runSpacing: 8.0, // Khoảng cách dọc giữa các dòng
            children: _selectedFiles.map((file) {
              String fileName = file.path.split('/').last;
              return Container(
                padding: EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.blueAccent),
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      fileName,
                      style: TextStyle(fontSize: 14.0),
                    ),
                    SizedBox(width: 4.0),
                    GestureDetector(
                      onTap: () => _removeFile(file),
                      child: Icon(
                        Icons.close,
                        size: 16.0,
                        color: Colors.red[300],
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
    );
  }

  void _removeImage(File file) {
    setState(() {
      _selectedImages.remove(file);
    });
  }

  Widget _showImagesPicked() {
    return _selectedImages.isEmpty ? SizedBox.shrink() : Column(
      children: [
        SizedBox(height: 10),
        Wrap(
          spacing: 8.0, // Khoảng cách giữa các phần tử theo chiều ngang
          runSpacing: 8.0, // Khoảng cách giữa các dòng
          children: _selectedImages.map((file) {
            String type = _mapMimeTypeToType(lookupMimeType(file.path) ?? 'application/octet-stream');
            return Stack(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  clipBehavior: Clip.hardEdge,
                  child: type == 'image'
                    // Nếu là ảnh, hiển thị ảnh
                    ? Image.file(
                        file,
                        fit: BoxFit.cover,
                      )
                    // Nếu là video, sử dụng FutureBuilder để tạo thumbnail
                    : FutureBuilder(
                        future: VideoThumbnail.thumbnailData(
                          video: file.path,
                          imageFormat: ImageFormat.JPEG,
                          maxWidth: 128, // giảm kích thước để tăng hiệu suất
                          quality: 25,   // chất lượng thumbnail từ 0 - 100
                        ),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          } else if (snapshot.hasError || snapshot.data == null) {
                            return const Center(child: Icon(Icons.error));
                          } else {
                            return Image.memory(
                              snapshot.data!,
                              fit: BoxFit.cover,
                            );
                          }
                        },
                      ),
                ),

                // Nếu file là video, hiển thị biểu tượng video (ở giữa)
                if (type == 'video')
                  Positioned.fill(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(4.0),
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: const Icon(
                          Icons.videocam,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                  ),

                // Nút X để xóa ảnh/video, đặt ở góc trên bên phải
                Positioned(
                  top: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: () {
                      _removeImage(file);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
        SizedBox(height: 10),
      ],
    );
  }

  void _removeYoutubePicked(Uri uri) {
    setState(() {
      _selectedYouTubes.remove(uri);
    });
  }

  Widget _showYoutubePicked() {
    return _selectedYouTubes.isEmpty ? SizedBox.shrink() : Column(
      children: [
        SizedBox(height: 10),
        Wrap(
          spacing: 8.0, // Khoảng cách giữa các phần tử theo chiều ngang
          runSpacing: 8.0, // Khoảng cách giữa các dòng
          children: _selectedYouTubes.map((uri) {
            String videoId = _extractYouTubeId(uri);
            String thumbnailUrl = 'https://img.youtube.com/vi/$videoId/maxresdefault.jpg';
            return Stack(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  clipBehavior: Clip.hardEdge,
                  child: Image.network(
                    thumbnailUrl,
                    fit: BoxFit.cover,
                  )
                ),

                // Hiển thị biểu tượng youtube (ở giữa)
                Positioned.fill(
                  child: Center(
                    child: Container(
                      // padding: const EdgeInsets.all(4.0),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(
                        Icons.smart_display_rounded,
                        color: Colors.red,
                        size: 24,
                      ),
                    ),
                  ),
                ),

                // Nút X để xóa ảnh/video, đặt ở góc trên bên phải
                Positioned(
                  top: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: () {
                      _removeYoutubePicked(uri);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
        SizedBox(height: 10),
      ],
    );
  }

  String _extractYouTubeId(Uri uri) {
    final host = uri.host.toLowerCase();
    final segments = uri.pathSegments;

    if (host.contains('youtu.be')) {
      return segments.isNotEmpty ? segments[0] : '';
    }

    if (host.contains('youtube.com')) {
      if (uri.queryParameters['v'] != null) return uri.queryParameters['v'] ?? '';

      if (segments.isNotEmpty && segments[0] == 'shorts' && segments.length > 1) {
        return segments[1];
      }
    }
    return '';
  }

  Widget _buildMessageInputRow() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        children: [
          AnimatedSize(
            duration: Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: _messageFocusNode.hasFocus ? SizedBox.shrink() : _showMessageInputRowOptions()
          ),
          AnimatedSize(
            duration: Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: _messageFocusNode.hasFocus ? SizedBox.shrink() : IconButton(
              icon: Icon(Icons.photo_library),
              onPressed: _pickImages,
              visualDensity: VisualDensity(horizontal: -4),
            ),
          ),
          AnimatedSize(
            duration: Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: _messageFocusNode.hasFocus ? SizedBox.shrink() : IconButton(
              icon: Icon(Icons.camera_alt),
              onPressed: _showCaptureOptions,
              visualDensity: VisualDensity(horizontal: -4),
            ),
          ),
          AnimatedSize(
            duration: Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: _messageFocusNode.hasFocus ? SizedBox.shrink() : IconButton(
              icon: Icon(Icons.mic),
              onPressed: _isRecordingAudio ? null : _startRecordingAudio,
              visualDensity: VisualDensity(horizontal: -4),
            ),
          ),
          // Ô nhập tin nhắn
          Expanded(
            child: FocusScope(
              onFocusChange: (hasFocus) {
                setState(() {
                  _messageFocusNode.hasFocus;
                });
              },
              child: TextField(
                focusNode: _messageFocusNode,
                controller: _controller,
                textCapitalization: TextCapitalization.sentences,
                autofocus: false,
                decoration: InputDecoration(
                  hintText: AppLocalizations.of(context).translate('type_a_message'),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.shadow,
                  // fillColor: Theme.of(context).brightness == Brightness.dark
                  //     ? Colors.grey[700]  // Màu nền cho dark mode
                  //     : Colors.grey[200], // Màu nền cho light mode
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25.0),
                    borderSide: BorderSide.none,
                  ),
                  // Đặt biểu tượng vào prefixIcon
                  prefixIcon: (_messageFocusNode.hasFocus && !_isSearch)
                      ? null
                      : GestureDetector(
                        onTap: () {
                          setState(() {
                            // Khi nhấn vào biểu tượng, thay đổi màu
                            _isSearch = !_isSearch;
                            _isGenImage = false;
                          });
                        },
                        child: Icon(
                          Icons.public,
                          color: _isSearch
                              ? Colors.blue // Màu khi được chọn
                              : Theme.of(context).colorScheme.onSurface, // Màu khi không được chọn
                        ),
                      ),
                ),
                textInputAction: TextInputAction.newline, // Cho phép xuống dòng
                minLines: 1,
                maxLines: 3,
                onChanged: (text) {
                  if (text.endsWith(' ') || text.endsWith('\n')) {
                    _handleManualInput(); // Gọi hàm kiểm tra đầu vào
                  }

                  // Xử lý khi người dùng xóa '@'
                  // if (!text.contains('@')) {
                  //   setState(() {
                  //     _systemInstructionController.text = '';
                  //   });
                  // }
                },
              ),
            ),
          ),
          // Nút gửi tin nhắn
          IconButton(
            icon: _isLoading
                ? SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.0),
                )
                : Icon(Icons.send),
            onPressed: _isLoading
                ? null // Nếu đang loading thì nút sẽ bị vô hiệu hóa
                : () async {
              // Tạo bản sao của danh sách file để truyền cho hàm xử lý
              final List<File> imagesToSend = List<File>.from(_selectedImages);
              final List<File> filesToSend = List<File>.from(_selectedFiles);
              final List<Uri> urlYTsToSend = List<Uri>.from(_selectedYouTubes);
              final String textToSend = _controller.text;

              // Cập nhật giao diện ngay: Clear danh sách các file và cập nhật loading
              setState(() {
                _selectedImages.clear();
                _selectedFiles.clear();
                _selectedYouTubes.clear();
                _controller.clear();
                _isLoading = true; // Bắt đầu loading
              });

              // Gửi tin nhắn dựa trên điều kiện có ảnh hoặc file được chọn hay không
              if (imagesToSend.isNotEmpty || filesToSend.isNotEmpty || urlYTsToSend.isNotEmpty) {
                await _sendMessage([imagesToSend, filesToSend, urlYTsToSend, textToSend]);
              } else {
                if (_isSearch) {
                  _sendToGeminiService(textToSend, includeTools: true);
                } else if (_isGenImage) {
                  _sendToGeminiService(textToSend, selectedModel: "gemini-2.0-flash-exp-image-generation", generateImage: true);
                } else {
                  await _sendMessage(textToSend);
                }
              }

              setState(() {
                _isLoading = false; // Kết thúc loading
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _showMessageInputRowOptions() {
    return Padding(
      padding: EdgeInsets.only(left: 8,right: 8,),
      child: PopupMenuButton<int>(
        onSelected: (value) {
          // Xử lý khi người dùng chọn một mục trong menu
          if (value == 1) {
            _pickFiles();
          } else if (value == 2) {
            if (_selectedYouTubes.isEmpty) {
              setState(() {
                _isGenImage = !_isGenImage;
                _isSearch = false;
              });
            }
          } else if (value == 3) {
            _showYouTubeLinkDialog(context);
          }
        },
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12), // Bo góc toàn bộ popup
        ),
        itemBuilder: (BuildContext context) {
          return [
            PopupMenuItem<int>(
              value: 1, // Giá trị cho mục này
              child: Row(
                children: [
                  Icon(Icons.file_present_rounded),
                  SizedBox(width: 8),
                  Text(AppLocalizations.of(context).translate('pick_files')),
                ],
              ),
            ),
            PopupMenuItem<int>(
              value: 2,
              child: Row(
                children: [
                  Icon(
                    Icons.palette,
                    color: _isGenImage
                      ? Colors.blue // Màu khi được chọn
                      : Theme.of(context).colorScheme.onSurface,
                  ),
                  SizedBox(width: 8),
                  Text(
                    AppLocalizations.of(context).translate('create_image'),
                    style: TextStyle(
                      color: _isGenImage
                        ? Colors.blue // Màu khi được chọn
                        : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuItem<int>(
              value: 3,
              child: Row(
                children: [
                  Icon(Icons.smart_display_rounded),
                  SizedBox(width: 8),
                  Text('YouTube'),
                ],
              ),
            ),
          ];
        },
        child: Icon(
          Icons.add_circle,
          color: _isGenImage
              ? Colors.blue // Màu khi được chọn
              : Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }

  // Future<void> _youtube() async {
  //   final geminiService = GeminiService(
  //     geminiApiKey: apiKey,
  //     modelId: _selectedModel,
  //     generateContentApi: _generateContentApi,
  //   );
  //   final historyJson = _chat.history.map((e) => e.toJson()).toList();
  //
  //   try {
  //     final response = await geminiService.generateContent(
  //       userInput: 'INSERT_INPUT_HERE',
  //       chatHistory: historyJson,
  //       // videoUrl: 'https://youtu.be/W3WY0TVVqs8',
  //     );
  //     print('Response from Gemini API: $response');
  //   } catch (e) {
  //     print('Error: $e');
  //   }
  // }

  Future<void> _sendToGeminiService(String userInput,
      {
        bool includeTools = false,
        String? selectedModel,
        bool generateImage = false,
      }) async {
    if (userInput.trim().isEmpty) return;
    // Nếu không truyền selectedModel, sử dụng giá trị mặc định (_selectedModel)
    selectedModel ??= _selectedModel;
    final geminiService = GeminiService(
      geminiApiKey: apiKey,
      modelId: selectedModel,
      generateContentApi: _generateContentApi,
    );
    final historyJson = _chat.history.map((e) => e.toJson()).toList();

    try {
      setState(() {
        _messages.add({'role': 'user', 'content': userInput, 'type': 'text'});
      });

      // Xóa @... trước khi gửi cho model
      String messageToModel = await _filterWords(userInput);

      final response = geminiService.generateContent(
        userInput: messageToModel,
        chatHistory: historyJson,
        includeTools: includeTools,
        generateImage: generateImage,
        systemInstruction: _systemInstructionController.text.trim().isEmpty || generateImage
            ? null
            : _systemInstructionController.text.trim(),
      );
      // final response = Stream.fromIterable(['"data": "aádasfsfagasz"']);


      final buffer = StringBuffer();
      String responseText = "";
      setState(() {
        _messages.add({'role': 'assistant', 'content': responseText, 'type': 'text', 'avatar': _currentChatbotAvatar});
      });
      await for (var res in response) {
        // Kiểm tra nếu là ảnh base64
        if (res.startsWith('"data": "')) {
          // print("res:$res");
          final base64Data = res.substring(9, res.length-1);
          final imageBytes = base64Decode(base64Data);

          // Tải tệp lên Supabase Storage
          final fileName = 'gemini_genimage_${DateTime.now()}';
          final response = await supabase.Supabase.instance.client.storage
              .from('ai-chat-bucket')
              .uploadBinary(fileName, imageBytes);
          final String publicUrl = supabase.Supabase.instance.client.storage
              .from('ai-chat-bucket')
              .getPublicUrl(fileName);

          setState(() {
            _messages.last['content'] = publicUrl;
            _messages.last['type'] = 'image';
          });
        } else { // Nếu là text, tiếp tục ghi vào buffer
          buffer.write(res);
          setState(() {
            // Nếu message hiện tại là text đang build thì update
            if (_messages.last['type'] == 'text') {
              _messages.last['content'] = buffer.toString();
            } else {
              // Nếu chưa có hoặc trước đó là ảnh, thêm message text mới
              _messages.add({'role': 'assistant', 'content': buffer.toString(), 'type': 'text', 'avatar': _currentChatbotAvatar});
            }
          });
        }
      }
      final lastMsType = _messages[_messages.length - 1]['type'];
      if (lastMsType == 'text') {
        responseText = buffer.toString();
        setState(() {
          _messages[_messages.length - 1]['content'] = responseText;
        });
      }

      if (_isFirstMessage) {
        // Đặt tên cho đoạn chat khi gửi tin nhắn đầu tiên
        final nameResponse = await _namedModel.startChat(history: []).sendMessage(
          Content.text('''user message: $messageToModel;
                          AI response: $responseText'''),
        );
        setState(() {
          _currentChatName = nameResponse.text == null ?
          'Unnamed Chat' : nameResponse.text!.trim();
        });
        _isFirstMessage = false;
      }
      if (!_isTemporaryChat) {
        // Tự động lưu đoạn chat sau mỗi tin nhắn
        _saveCurrentChat();
      }
    } catch (e) {
      // print('Error: $e');
    }
  }

  void _showYouTubeLinkDialog(BuildContext context) {
    TextEditingController? ytController = TextEditingController();
    String? previewUrl;

    // Hiển thị dialog
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('Enter YouTube Link'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: ytController,
                    onChanged: (url) {
                      if (url.isNotEmpty && _isValidYouTubeURL(url)) {
                        // Xử lý URL YouTube hợp lệ
                        Uri uri = Uri.parse(url);
                        String ytId = _extractYouTubeId(uri);
                        setState(() {
                          previewUrl = 'https://img.youtube.com/vi/$ytId/maxresdefault.jpg';
                        });
                      }
                    },
                    decoration: InputDecoration(
                      hintText: 'Enter YouTube URL',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
                    ),
                  ),
                  SizedBox(height: 10),
                  if (previewUrl != null)
                    ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: _buildYouTubeWidget(previewUrl!),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    // Đóng dialog
                    Navigator.pop(context);
                    ytController = null;
                  },
                  child: Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    // Kiểm tra URL có hợp lệ không
                    String url = ytController!.text;
                    if (url.isNotEmpty && _isValidYouTubeURL(url)) {
                      // Xử lý URL YouTube hợp lệ
                      setState(() {
                        _selectedYouTubes.add(Uri.parse(url));
                      });
                      Navigator.pop(context);
                      ytController = null;
                    } else {
                      // Thông báo nếu URL không hợp lệ
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Invalid YouTube URL')),
                      );
                    }
                  },
                  child: Text('OK'),
                ),
              ],
            );
          }
        );
      },
    ).whenComplete(() {
      ytController?.dispose();
    });
  }

  // Hàm kiểm tra URL có phải là YouTube không
  bool _isValidYouTubeURL(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    final host = uri.host.toLowerCase();
    return host.contains('youtube.com') || host.contains('youtu.be');
  }

  // TODO: gform
  Future<String> _filterWords(String input) async {
    // Các biến để lưu kết quả
    List<String> slashStrings = [];
    List<String> linkStrings = [];
    List<String> remainingStrings = [];
    List<String> notSlashStrings = [];

    // Chia chuỗi thành các từ
    List<String> words = input.split(RegExp(r'\s+'));

    // Duyệt qua từng từ và phân loại
    for (var word in words) {
      if (word.startsWith('@')) {
        slashStrings.add(word);  // Chuỗi chứa '@'
      } else {
        notSlashStrings.add(word); // Chuỗi ko chứa '@'
        if (word.startsWith('http')) {
          linkStrings.add(word); // Chuỗi chứa link
        } else {
          remainingStrings.add(word); // Chuỗi còn lại
        }
      }
    }

    if (slashStrings.join(' ') == "@AutoFillGForm") {
      gFormUrl = linkStrings.join(' ');
      // Bước 1: Tải và giải mã dữ liệu
      fbData = await fetchFBPublicLoadData(gFormUrl);
      if (fbData == null) {
        // print("Lỗi khi tải FB_PUBLIC_LOAD_DATA_");
        return "Lỗi khi tải FB_PUBLIC_LOAD_DATA_";
      }

      // Bước 2: Xử lý dữ liệu câu hỏi - đáp án
      Map<String, List<String>> questionChoices = processQuestions(fbData);
      // print("Question choices:");
      // print(questionChoices);

      // Chuyển đổi questionChoices thành JSON string
      String processedData = jsonEncode(questionChoices);
      // print("\nProcessed Data JSON:");
      // print(processedData);

      return processedData;  // Danh sách trắc nghiệm từ google form
    }

    // In kết quả
    // print("Chuỗi chứa '@': ${slashStrings.join(' ')}");
    // print("Chuỗi chứa link: ${linkStrings.join(' ')}");
    // print("Chuỗi còn lại: ${remainingStrings.join(' ')}");

    return notSlashStrings.join(' ');
  }

  String _getPreFilledGFormLink(String response) {
    if (fbData == null) return "";
    // Bước 3: Lấy đáp án từ AI
    Map<String, List<String>> aiResponse = processAIResponse(response);
    // print("\nAI Response:");
    // print(aiResponse);

    // Lấy entry mapping từ dữ liệu gốc
    Map<String, String> entryMapping = getEntryMapping(fbData);
    // print("\nentryMapping:");
    // print(entryMapping);

    // Tạo đường link pre-filled
    String prefilledUrl = buildPrefilledUrl(gFormUrl, aiResponse, entryMapping);
    // print("\nPrefilled URL:");
    // print(prefilledUrl);

    fbData = null;
    gFormUrl = "";
    return prefilledUrl;
  }

  Future<void> _sendMessage(dynamic userMessage) async {
    if (userMessage == null // List<dynamic>
        || (userMessage is String && userMessage.trim().isEmpty)) // only text
      return;

    Content? content;
    late String messageToModel;

    if (userMessage is List<dynamic>) { // [[File('file1.jpg'),File('file2.jpg')], textt]]
      List<Part> contentPart = [];
      List<String> supabaseUrls = [];
      bool hasString = false;
      int fileMessageStartIndex = _messages.length;

      for (var item in userMessage) {
        // Nếu là danh sách uri YouTube
        if (item is List<Uri>) {
          for (var uri in item) {
            setState(() {
              _messages.add({'role': 'user', 'content':uri.toString(), 'type': 'youtube'});
            });
            contentPart.add(FilePart(uri));
          }
        } // Nếu là danh sách file
        else if (item is List<File>) {
          for (var file in item) {
            final bytes = await file.readAsBytes();
            final mimeType = lookupMimeType(file.path) ??
                'application/octet-stream';
            final type = _mapMimeTypeToType(mimeType);
            setState(() {
              _messages.add({'role': 'user', 'content': file.path, 'type': type});
            });
            contentPart.add(DataPart(mimeType, bytes));

            if (!_isTemporaryChat) {
              // Tải tệp lên Supabase Storage
              final fileName = '${DateTime.now()}_'
                  '${removeVietnameseDiacritics(file.path
                  .split('/')
                  .last)
                  .replaceAll(RegExp(r"[^a-zA-Z0-9\s._]"), "")}';
              final response = await supabase.Supabase.instance.client.storage
                  .from('ai-chat-bucket')
              // .uploadBinary(fileName, bytes);
                  .upload(fileName, File(file.path));
              final String publicUrl = supabase.Supabase.instance.client.storage
                  .from('ai-chat-bucket')
                  .getPublicUrl(fileName);
              supabaseUrls.add(publicUrl);
            }
          }
          if (!_isTemporaryChat) {
            // Cập nhật lại _messages với các URL từ Supabase
            setState(() {
              for (int i = 0; i < supabaseUrls.length; i++) {
                _messages[fileMessageStartIndex + i]['content'] =
                supabaseUrls[i];
              }
            });
          }
        } // Nếu là tin nhắn text
        else if (item is String) {
          if (item.trim().isNotEmpty) {
            setState(() {
              _messages.add({'role': 'user', 'content': item, 'type': 'text'});
            });
            // Xóa @... trước khi gửi cho model
            messageToModel = await _filterWords(item);
            contentPart.add(TextPart(messageToModel));
            hasString = true;
          }
        }
      }
      if(!hasString){
        messageToModel = "";
        contentPart.add(TextPart(""));
      }
      content = Content.multi(contentPart);
    } else if (userMessage is String) {
      setState(() {
        _messages.add({'role': 'user', 'content': userMessage, 'type': 'text'});
      });

      // Xóa @... trước khi gửi cho model
      messageToModel = await _filterWords(userMessage);
      // print(messageToModel);
      content = Content.text(messageToModel);
    }

    // _controller.clear(); // Xóa nội dung TextField
    // _scrollToBottom(); //TODO: Nếu dữ liệu messages được lấy từ một Stream hoặc Future, gọi _scrollToBottom sau khi dữ liệu được cập nhật

    try {
      // final response = await _chat.sendMessage(content!); // Gửi tin nhắn
      // String responseText = response.text ?? 'No response from AI'; // Xử lý giá trị null

      // TODO: Stream Message
      StringBuffer responseTextBuffer = StringBuffer();
      String responseText = "";
      final response = _chat.sendMessageStream(content!); // Gửi tin nhắn
      setState(() {
        _messages.add({'role': 'assistant', 'content': responseText, 'type': 'text', 'avatar': _currentChatbotAvatar});
      });
      await for (var chunk in response) {
        // responseText += chunk.text ?? '';
        responseTextBuffer.write(chunk.text ?? '');
        setState(() {
          _messages[_messages.length - 1]['content'] = responseTextBuffer.toString();
        });
      }
      responseText = responseTextBuffer.toString();

      String preFilledGFormLink = _getPreFilledGFormLink(responseText);
      if (preFilledGFormLink.isNotEmpty) {
        responseText += "\n👉 [pre-filled form]($preFilledGFormLink)";
      }
      // setState(() {
      //   _messages.add({
      //     'role': 'assistant',
      //     'content': responseText,
      //   });
      // });
      // _scrollToBottom();

      if (_isFirstMessage) {
        // Đặt tên cho đoạn chat khi gửi tin nhắn đầu tiên
        final nameResponse = await _namedModel.startChat(history: []).sendMessage(
          Content.text('''user message: $messageToModel;
                          AI response: $responseText'''),
        );
        setState(() {
          _currentChatName = nameResponse.text == null ?
          'Unnamed Chat' : nameResponse.text!.trim();
        });
        _isFirstMessage = false;
      }
      if (!_isTemporaryChat) {
        // Tự động lưu đoạn chat sau mỗi tin nhắn
        _saveCurrentChat();
      }
    } catch (e) {
      setState(() {
        _messages.add({'role': 'error', 'content': 'Error: $e', 'type': 'text'});
      });
    }
  }

  String _mapMimeTypeToType(String mimeType) {
    if (mimeType.startsWith('image/')) return 'image';
    if (mimeType.startsWith('video/')) return 'video';
    if (mimeType.startsWith('audio/')) return 'audio';
    if (mimeType == 'application/pdf') return 'pdf';
    if (mimeType.startsWith('text/')) return 'text';
    return 'file'; // fallback cho các loại khác
  }

  /// Hàm xóa tin nhắn.
  Future<void> _deleteMessage(int index) async {
    final message = _messages[index];
    final content = message['content'] ?? '';
    final type = message['type'] ?? '';

    // Nếu tin nhắn là file
    if (type != 'text' && type != 'youtube') {
      try {
        // Phân tích URL để lấy tên file.
        final uri = Uri.parse(content);
        // Giả sử URL có dạng: /storage/v1/object/public/ai-chat-bucket/<fileName>
        final segments = uri.pathSegments;
        if (segments.isNotEmpty) {
          final fileName = segments.last; // Lấy phần cuối cùng làm tên file.
          // Xóa file từ Supabase Storage
          final response = await supabase.Supabase.instance.client.storage
              .from('ai-chat-bucket')
              .remove([fileName]);

          // print('xóa file từ Supabase: ${response.last.name}');
        }
      } catch (e) {
        // Log lỗi nếu phân tích URL thất bại hoặc lỗi trong quá trình xóa file.
        // print('Lỗi khi xử lý xóa file: $e');
      }
    }

    // Xóa tin nhắn khỏi danh sách hiển thị.
    setState(() {
      _messages.removeAt(index);
    });

    // Cập nhật lại dữ liệu chat trong Firestore nếu có.
    if (_currentChatId != null) {
      try {
        await _firestore
            .collection('chat_histories')
            .doc(_currentChatId)
            .update({'messages': _messages});
      } catch (e) {
        // print('Lỗi khi cập nhật Firestore: $e');
      }
    }
    // Sau khi lưu, làm mới danh sách
    // _loadChatHistories();

    // Cập nhật thông số cấu hình và lịch sử chat
    await _updateModelConfigForCurrentChat();
  }

  void _startNewChat() async {
    if (_messages.isNotEmpty) {
      // await _saveCurrentChat();
      setState(() {
        _messages.clear();
        _controller.clear();
        _systemInstructionController.clear();
        _chat = _model.startChat(history: []);
        _currentChatId = null; // Xóa ID đoạn chat hiện tại
        _currentChatName = null;
        _isFirstMessage = true;
        _selectedIndex = -1;
        _tokenCount = "0";
        _currentChatbotAvatar = '';
      });
      _fetchDefaultBot();
    }
    await _updateModelConfigForCurrentChat();
  }

  Future<void> _updateModelConfigForCurrentChat() async {
    await _initializeModel();
    // _chat = _model.startChat(history: _messages.map((m) {
    //   return Content.text(m['content']!);
    // }).toList());
    List<Content> history = [];
    for (int i = 0; i < _messages.length; i++) {
      final msg = _messages[i];
      final String content = msg['content']!;
      final bool isUser = msg['role'] == 'user';
      final String type = msg['type'];

      // if (Uri.tryParse(content)?.hasAbsolutePath ?? false) {
      // if (content.startsWith('http')){
      if (type != 'text'){
        // Xử lý tin nhắn là file
        List<Part> parts = [];
        // while (i < _messages.length && _messages[i]['content']!.startsWith('http')) {
        while (i < _messages.length && _messages[i]['type'] != 'text') {
          // Nếu là URL YouTube
          if ((_messages[i]['type']) == 'youtube') {
            FilePart filePart = FilePart(Uri.parse(_messages[i]['content']));
            parts.add(filePart);
          } else { // Nếu là URL thường
            DataPart? filePart = await _fetchUrlAsDataPart(_messages[i]['content']!);
            if (filePart != null) {
              parts.add(filePart);
            }
          }
          i++; // Di chuyển đến tin nhắn tiếp theo
        }
        // Nếu tin nhắn tiếp theo là text từ user → thêm nó vào nhóm chung với file
        // if (i < _messages.length && _messages[i]['role'] == 'user') {
        //   parts.add(TextPart(_messages[i]['content']!));
        //   i++; // Tiếp tục bỏ qua tin nhắn đã dùng
        // }
        // history.add(Content.multi(parts));

        // (TEST)
        // Nếu tin nhắn tiếp theo là TEXT → gom luôn vào
        // if (i < _messages.length && !_messages[i]['content']!.startsWith('http')) {
        if (i < _messages.length && _messages[i]['type'] == 'text') {
          parts.add(TextPart(_messages[i]['content']!));
          i++;
        }
        // Add vào history tùy theo role của người gửi file ban đầu
        history.add(isUser
            ? Content.multi(parts)
            : Content.model(parts));

        i--; // Giảm lại (vì while có thể tăng i quá mức) vì vòng for sẽ tự động tăng i
        continue;

        // DataPart? filePart = await _fetchUrlAsDataPart(content);
        // if (filePart != null) {
        //   List<Part> parts = [filePart];
        //   // Nếu tin nhắn tiếp theo là text từ user → nhóm chung với file
        //   if (i + 1 < _messages.length && _messages[i + 1]['role'] == 'user') {
        //     parts.add(TextPart(_messages[++i]['content']!)); // ++i để cập nhật giá trị của i ngay lập tức, bỏ qua tin nhắn tiếp theo vì đã dùng nó (nếu dùng i + 1 chỉ lấy giá trị mà không thay đổi i).
        //   }
        //   history.add(Content.multi(parts));
        //   continue; // Nhảy ngay sang tin nhắn tiếp theo, bỏ qua xử lý bên dưới (tránh thêm tin nhắn 2 lần)
        // }
      }
      // Nếu là tin nhắn AI → Content.model([]), nếu là user → Content.multi([])
      history.add(isUser
          ? Content.multi([TextPart(content)])
          : Content.model([TextPart(content)]));
    }

    _chat = _model.startChat(history: history);
    // ScaffoldMessenger.of(context).showSnackBar(
    //   SnackBar(content: Text('Model configuration updated.')),
    // );
    // print("_chat.history: ${_chat.history.last.parts.last.toJson()}");
    // print("_chat.history: ${_chat.history.length}");
    // print("_chat.history: ${_chat.history.last.role}");
    // for (var content in _chat.history) {
    //   for (var part in content.parts) {
    //     print("_chat.history: ${part.toJson()}");
    //   }
    // }
    // for (var content in _chat.history) {
    //   print("_chat.history: ${jsonEncode(content.toJson())}");
    // }

    // Example:
    // [
    //   Content.multi([
    //     DataPart("application/pdf", [/* Dữ liệu hóa đơn PDF */]),
    //     DataPart("application/pdf", [/* Dữ liệu hóa đơn PDF */]),
    //     TextPart("file này là gì")
    //   ]),
    //   Content.model([
    //     TextPart("Đây là hóa đơn tiền điện ...")
    //   ]),
    //   Content.multi([
    //     TextPart("hóa đơn có gì")
    //   ]),
    //   Content.model([
    //     TextPart("Hóa đơn bao gồm ...")
    //   ])
    // ]
  }

  Future<DataPart?> _fetchUrlAsDataPart(String url) async {
    try {
      final response = await Dio().get(url, options: Options(responseType: ResponseType.bytes));
      final mimeType = lookupMimeType(url) ?? 'application/octet-stream';
      // print("mimeType: $mimeType");
      return DataPart(mimeType, response.data);
    } catch (e) {
      // print('Lỗi tải dữ liệu từ URL: $e');
      return null;
    }
  }

  void _renameChat(DocumentSnapshot chatDoc, String currentName) {
    TextEditingController _renameController = TextEditingController(text: currentName);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Rename Chat'),
          content: TextField(
            controller: _renameController,
            decoration: InputDecoration(labelText: 'New Chat Name'),
          ),
          actions: [
            TextButton(
              child: Text('Cancel'),
              onPressed: () {
                Navigator.pop(context);
              },
            ),
            TextButton(
              child: Text(AppLocalizations.of(context).translate('rename')),
              onPressed: () async {
                final newName = _renameController.text.trim();
                if (newName.isNotEmpty) {
                  await _firestore.collection('chat_histories').doc(chatDoc.id).update({'name': newName});
                  Navigator.pop(context);
                  // _loadChatHistories(); // Làm mới danh sách
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Chat renamed to "$newName".')),
                  );
                }
              },
            ),
          ],
        );
      },
    );
  }

  void _deleteChat(DocumentSnapshot chatDoc) async {
    final chatName = (chatDoc.data() as Map<String, dynamic>)['name'] ?? 'Unnamed Chat';
    final messages = (chatDoc.data() as Map<String, dynamic>)['messages'] as List?;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Delete Chat'),
          content: Text('Are you sure you want to delete "$chatName"?'),
          actions: [
            TextButton(
              child: Text('Cancel'),
              onPressed: () {
                Navigator.pop(context);
              },
            ),
            TextButton(
              child: Text(AppLocalizations.of(context).translate('delete')),
              onPressed: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Chat "$chatName" deleted.')),
                );

                // Chạy việc xóa chat trong nền
                Future.delayed(Duration.zero, () async {
                  if (messages != null) {
                    for (final message in messages) {
                      final content = message['content'];
                      final type = message['type'];
                      if (type != 'text' && type != 'youtube'){
                        // print("ishttp: $content");
                        final fileName = Uri.parse(content).pathSegments.last;
                        await supabase.Supabase.instance.client.storage
                            .from('ai-chat-bucket')
                            .remove([fileName]);
                      }
                    }
                  }
                  // Nếu đang ở trong đoạn chat bị xóa thì tạo đoạn chat mới
                  if (chatDoc.id == _currentChatId) {
                    _startNewChat();
                  }
                  await _firestore.collection('chat_histories').doc(chatDoc.id).delete();
                  // _loadChatHistories(); // Làm mới danh sách
                });
              },
            ),
          ],
        );
      },
    );
  }

  // void _openModelConfigModal() {
  //   // Lưu trữ giá trị tạm thời để khôi phục nếu thoát modal
  //   _tempModel = _selectedModel;
  //   _tempTemperature = _temperature;
  //   _tempSystemInstruction = _systemInstructionController.text.trim().isEmpty
  //       ? ''
  //       : _systemInstructionController.text;
  //   _tempIsTemporaryChat = _isTemporaryChat;
  //   TextEditingController tempSIController = TextEditingController(text: _tempSystemInstruction);
  //
  //   showModalBottomSheet(
  //     context: context,
  //     isScrollControlled: true, // Cho phép modal mở rộng dựa trên kích thước bàn phím
  //     builder: (context) {
  //       return StatefulBuilder(
  //         builder: (context, setModalState) {
  //           // Sử dụng Future.delayed để thực hiện tính toán token sau khi modal được mở
  //           Future.delayed(Duration(milliseconds: 1000), () async {
  //             var tokenCount = await _model.countTokens(_chat.history);
  //             setModalState(() {
  //               // Cập nhật giao diện sau khi có kết quả token
  //               _tokenCount = tokenCount.totalTokens.toString();
  //             });
  //           });
  //
  //           return Padding(
  //             padding: EdgeInsets.only(
  //               left: 16,
  //               right: 16,
  //               top: 16,
  //               bottom: MediaQuery.of(context).viewInsets.bottom, // Thêm khoảng trống cho bàn phím
  //             ),
  //             child: SingleChildScrollView( // Cho phép cuộn nội dung (ko cần)
  //               child: Column(
  //                   mainAxisSize: MainAxisSize.min,
  //                   children: [
  //                     Text('Model Configuration', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
  //                     SizedBox(height: 20),
  //                     DropdownButtonFormField<String>(
  //                       decoration: InputDecoration(
  //                         labelText: 'Model',
  //                         border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
  //                         prefixIcon: Icon(Icons.memory), // Biểu tượng chip/AI
  //                       ),
  //                       value: _tempModel,
  //                       items: _models.map((model) {
  //                         return DropdownMenuItem(
  //                           value: model,
  //                           child: Text(model),
  //                         );
  //                       }).toList(),
  //                       onChanged: (value) {
  //                         setModalState(() {
  //                           _tempModel = value!;
  //                         });
  //                       },
  //                     ),
  //                     SizedBox(height: 10),
  //                     // Total tokens
  //                     Align(
  //                       alignment: Alignment.center,
  //                       child: Container(
  //                         margin: EdgeInsets.symmetric(vertical: 10), // Tạo khoảng cách
  //                         padding: EdgeInsets.all(8),
  //                         decoration: BoxDecoration(
  //                           color: Colors.blueAccent.withOpacity(0.1),
  //                           borderRadius: BorderRadius.circular(8),
  //                         ),
  //                         child: Text(
  //                           'Total tokens: $_tokenCount',
  //                           style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueAccent),
  //                         ),
  //                       ),
  //                     ),
  //                     Row(
  //                       children: [
  //                         Icon(Icons.thermostat, color: Colors.red), // Biểu tượng lửa cho temperature
  //                         SizedBox(width: 5),
  //                         Text('Temperature', style: TextStyle(fontSize: 16),),
  //                         Expanded(
  //                           child: Slider(
  //                             min: 0.0,
  //                             max: 2.0,
  //                             divisions: 20,
  //                             value: _tempTemperature,
  //                             onChanged: (value) {
  //                               setModalState(() {
  //                                 _tempTemperature = value;
  //                               });
  //                             },
  //                           ),
  //                         ),
  //                         SizedBox(
  //                           width: 50,
  //                           height: 50,
  //                           child: TextField(
  //                             decoration: InputDecoration(border: OutlineInputBorder()),
  //                             controller: TextEditingController(
  //                                 text: _tempTemperature.toStringAsFixed(1)
  //                             ),
  //                             keyboardType: TextInputType.number,
  //                             onChanged: (value) {
  //                               final temp = double.tryParse(value);
  //                               if (temp != null && temp >= 0 && temp <= 2) {
  //                                 setModalState(() {
  //                                   _tempTemperature = temp;
  //                                 });
  //                               }
  //                             },
  //                           ),
  //                         ),
  //                       ],
  //                     ),
  //                     SizedBox(height: 10), // Thêm một khoảng cách dọc 10 pixels giữa các widget
  //                     // Thêm switch button cho Temporary Chat
  //                     ListTileTheme(
  //                       contentPadding: EdgeInsets.zero, // Xóa khoảng thụt lề mặc định
  //                       child: SwitchListTile(
  //                         title: Row(
  //                           children: [
  //                             Icon(Icons.chat_bubble_outline, color: Colors.blue), // Biểu tượng chat
  //                             SizedBox(width: 5),
  //                             Text('Temporary Chat', style: TextStyle(fontSize: 16)),
  //                           ],
  //                         ),
  //                         value: _tempIsTemporaryChat,
  //                         onChanged: (value) {
  //                           setModalState(() {
  //                             _tempIsTemporaryChat = value;
  //                           });
  //                         },
  //                         // Màu nút gạt khi bật
  //                         // activeColor: Theme.of(context).primaryColor,
  //                         // Màu track khi bật (dải bên dưới nút gạt)
  //                         // activeTrackColor: Theme.of(context).primaryColor.withOpacity(0.5),
  //                         inactiveThumbColor: Colors.grey,           // Màu nút gạt khi tắt
  //                         // inactiveTrackColor: Theme.of(context).colorScheme.onSurface,
  //                         // dense: true, // Giảm chiều cao tile nếu muốn
  //                       ),
  //                     ),
  //                     SizedBox(height: 10),
  //                     AnimatedContainer(
  //                       duration: Duration(milliseconds: 300),
  //                       curve: Curves.easeInOut,
  //                       height: _isExpanded ? MediaQuery.of(context).size.height * 0.6 : 60, // *0.6 giảm độ cao của modal so với *1 ??
  //                       child: TextField(
  //                         decoration: InputDecoration(
  //                           labelText: 'System Instructions',
  //                           border: OutlineInputBorder(
  //                             borderRadius: BorderRadius.circular(30.0)
  //                           ),
  //                           suffixIcon: IconButton(
  //                             icon: Icon(_isExpanded ? Icons.fullscreen_exit : Icons.fullscreen),
  //                             onPressed: () {
  //                               setModalState(() {
  //                                 _isExpanded = !_isExpanded;
  //                               });
  //                             },
  //                           ),
  //                         ),
  //                         minLines: _isExpanded ? null : 1,
  //                         maxLines: _isExpanded ? 30 : 3, // Tối đa 3 dòng hoặc không giới hạn
  //                         controller: tempSIController,
  //                         onChanged: (value) {
  //                           _tempSystemInstruction = value;
  //                         },
  //                       ),
  //                     ),
  //                     ElevatedButton(
  //                       onPressed: () async {
  //                         setState(() {
  //                           _selectedModel = _tempModel;
  //                           _temperature = _tempTemperature;
  //                           _systemInstructionController.text =
  //                               _tempSystemInstruction;
  //                           _isTemporaryChat = _tempIsTemporaryChat;
  //                         });
  //                         await _updateModelConfigForCurrentChat();
  //
  //                         Navigator.pop(context);
  //                         ScaffoldMessenger.of(context).showSnackBar(
  //                           SnackBar(content: Text('Model configuration updated.')),
  //                         );
  //                       },
  //                       child: Text('Apply'),
  //                     ),
  //                   ],
  //                 ),
  //             ),
  //           );
  //         },
  //       );
  //     },
  //   );
  // }

  void _openModelConfigModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => ModelConfigModal(
        selectedModel: _selectedModel,
        temperature: _temperature,
        systemInstruction: _systemInstructionController.text,
        isTemporaryChat: _isTemporaryChat,
        availableModels: _models,
        countTokens: () async => (await _model.countTokens(_chat.history)).totalTokens,
        onApply: (model, temp, systemInstruction, isTemp) async {
          setState(() {
            _selectedModel = model;
            _temperature = temp;
            _systemInstructionController.text = systemInstruction;
            _isTemporaryChat = isTemp;
          });
          await _updateModelConfigForCurrentChat();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Model configuration updated.')),
          );
        },
      ),
    );
  }


  void _showChatOptions(LongPressStartDetails details, DocumentSnapshot chatDoc) async {
    final chatData = chatDoc.data() as Map<String, dynamic>;
    final chatName = chatData['name'] as String? ?? 'Unnamed Chat';

    final tapPosition = details.globalPosition;
    showMenu(
      context: context,
      color: Theme.of(context).colorScheme.secondaryContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12), // Bo góc menu
      ),
      position: RelativeRect.fromLTRB(
        tapPosition.dx,
        tapPosition.dy,
        MediaQuery.of(context).size.width - tapPosition.dx,
        MediaQuery.of(context).size.height - tapPosition.dy,
      ),
      items: [
        PopupMenuItem(
          value: 'rename',
          child: ListTile(
            leading: Icon(Icons.edit),
            title: Text('Rename'),
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: ListTile(
            leading: Icon(Icons.delete),
            title: Text('Delete'),
          ),
        ),
      ],
    ).then((result) {
      if (result == 'rename') {
        _renameChat(chatDoc, chatName);
      } else if (result == 'delete') {
        _deleteChat(chatDoc);
      }
    });
  }

  // Future<void> _signOut() async {
  //   await GoogleSignIn().disconnect(); //
  //   await FirebaseAuth.instance.signOut();
  //   Navigator.of(context).pushReplacement(
  //     MaterialPageRoute(builder: (context) => AuthScreen()),
  //   );
  //   setState(() {
  //     // Reset trạng thái giao diện sau khi đăng xuất
  //     _currentUser = null;
  //   });
  // }

  Future<void> _fetchDefaultBot() async {
    final currentUserId = _currentUser?.uid;

    try {
      final userSnapshot = await FirebaseFirestore.instance
          .collection('chatbot_customizations')
          .where('userId', whereIn: [currentUserId, ""]) // Lấy cả userId hiện tại và userId rỗng
          .where('isDefault', isEqualTo: true)
          .get();

      // Kiểm tra nếu có tài liệu phù hợp
      if (userSnapshot.docs.isNotEmpty) {
        // Lấy description từ tài liệu đầu tiên
        final description = userSnapshot.docs.first['chatbotDescription'];
        if (description != null) {
          setState(() {
            _systemInstructionController.text = description;
          });
        }
        await _updateModelConfigForCurrentChat();
      }
    } catch (e) {
      // Xử lý lỗi (nếu có)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error fetching default bot: $e")),
      );
    }
  }

  void _fetchSuggestions() {
    final currentUserId = _currentUser?.uid;
    // 2 biến tạm để lưu kết quả của từng truy vấn
    List<Map<String, String>> userChatbots = [];
    List<Map<String, String>> publicChatbots = [];

    // Listener cho chatbot của người dùng
    _suggestionsSubscription = FirebaseFirestore.instance
        .collection('chatbot_customizations')
        .where('userId', isEqualTo: currentUserId)
        .snapshots()
        .listen((userSnapshot) {
      userChatbots = userSnapshot.docs.map((doc) {
        return {
          'name': doc['name'] as String,
          'avatarUrl': doc['avatarUrl'] as String? ?? '',
        };
      }).toList();

      // Cập nhật danh sách tổng hợp khi có dữ liệu từ truy vấn user
      setState(() {
        _allCustomNames = [...userChatbots, ...publicChatbots];
      });
    });

    // Listener cho chatbot public (loại bỏ những chatbot thuộc về người dùng hiện tại)
    _suggestionsSubscription = FirebaseFirestore.instance
        .collection('chatbot_customizations')
        .where('isPublic', isEqualTo: true)
        .where('userId', isNotEqualTo: currentUserId)
        .orderBy('userId') // Bắt buộc khi dùng isNotEqualTo
        .snapshots()
        .listen((publicSnapshot) {
      publicChatbots = publicSnapshot.docs.map((doc) {
        return {
          'name': doc['name'] as String,
          'avatarUrl': doc['avatarUrl'] as String? ?? '',
        };
      }).toList();

      // Cập nhật danh sách tổng hợp khi có dữ liệu từ truy vấn public
      setState(() {
        _allCustomNames = [...userChatbots, ...publicChatbots];
      });
    });
  }

  void _updateSuggestions(String query) {
    _suggestions = _allCustomNames.where((map) {
      final name = map['name']!;
      return name.toLowerCase().contains(query.toLowerCase());
    }).toList();
    setState(() {});
  }

  Widget _buildSuggestions() {
    return _suggestions.isEmpty
      ? SizedBox.shrink()
      : Container(
        margin: EdgeInsets.only(left: 10, right: 10),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(8.0),
        ),
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: _suggestions.length,
          itemBuilder: (context, index) {
            final suggestion = _suggestions[index];
            final avatarUrl = suggestion['avatarUrl'] ?? '';
            final name = suggestion['name'] ?? '';

            return ListTile(
              leading: CircleAvatar(
                backgroundImage: avatarUrl.isNotEmpty
                    ? NetworkImage(avatarUrl)
                    : AssetImage('assets/avatar/default_bot_avt.png') as ImageProvider,
                backgroundColor: Colors.grey[300],
              ),
              title: Text(name),
              onTap: () {
                _insertSuggestion(name);
                if (avatarUrl.isNotEmpty) _currentChatbotAvatar = avatarUrl;
              },
            );
          },
        ),
      );
  }

  void _insertSuggestion(String suggestion) async {
    final description = await fetchChatbotDescription(suggestion);

    if (description != null) {
      setState(() {
        _systemInstructionController.text = description;
      });
    }
    await _updateModelConfigForCurrentChat();

    // Chèn tên chatbot sau @
    final text = _controller.text;
    final atIndex = text.lastIndexOf('@');
    final newText = text.substring(0, atIndex + 1) + suggestion + ' ';
    _controller.text = newText;
    _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length));
    _suggestions.clear();
    setState(() {});
  }

  void _handleManualInput() async {
    _suggestions.clear();
    final text = _controller.text;
    final lastWord = text.split('@').last.trim();

    // Nếu có nhiều @ thì xóa @ đầu tiên
    if ('@'.allMatches(text).length > 1) {
      final regex = RegExp(r'@\S+'); // Tìm kiếm @ và các ký tự không phải khoảng trắng theo sau
      final newText = text.replaceFirst(regex, '').trim();
      _controller.text = newText;
    }

    // Gán @ thứ 2 cho SI
    if (_allCustomNames.any((map) => map['name'] == lastWord)) {
      final description = await fetchChatbotDescription(lastWord);

      if (description != null) {
        setState(() {
          _systemInstructionController.text = description;
        });
        await _updateModelConfigForCurrentChat();
      }
    }
  }

  Future<String?> fetchChatbotDescription(String name) async {
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('chatbot_customizations')
          .where('name', isEqualTo: name)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        return querySnapshot.docs.first['chatbotDescription'] as String?;
      }
    } catch (e) {
      // print('Error fetching chatbotDescription: $e');
    }
    return null;
  }

  // Future<void> _pickFile() async {
  //   final result = await FilePicker.platform.pickFiles(type: FileType.image);
  //   if (result != null && result.files.single.path != null) {
  //     setState(() {
  //       selectedFilePath = result.files.single.path;
  //       print("selectedFilePath: $selectedFilePath");
  //     });
  //     final rp = await _model.startChat(history: [
  //       Content.multi([
  //         FilePart(await Uri.file("https://generativelanguage.googleapis.com/v1beta/files/3mmkda87z1mz")),
  //       ])
  //     ]).sendMessage(Content.text("Describe this image."));
  //     print(rp.text);
  //   }
  // }

  Future<String?> _getVideoThumbnail(String videoUrl) async {
    try {
      final thumbnailFile = await VideoThumbnail.thumbnailFile(
        video: videoUrl,
        imageFormat: ImageFormat.JPEG,
        quality: 50, // Chất lượng thumbnail (0-100)
      );
      // print("thumbnailFile: $thumbnailFile");
      return thumbnailFile; // Đường dẫn đến file thumbnail
    } catch (e) {
      // print("Error getting thumbnail: $e");
      return null;
    }
  }

  // Hiển thị biểu tượng cho các loại file
  Widget _displayFile(String content, String type) {
    if (type == 'image') {
      // print("image content: $content");
      if (content.startsWith('http')) {
        return GestureDetector(
          onTap: () {
            Navigator.of(context).push(MaterialPageRoute(
              builder: (context) => ImageViewerScreen(imageUrl: content),
            ),
            );
          },
          child: Image.network(
            content,
            height: 150,
            fit: BoxFit.contain,
            // Hiển thị loading indicator khi đang tải ảnh
            loadingBuilder: (BuildContext context, Widget child, ImageChunkEvent? loadingProgress) {
              if (loadingProgress == null) {
                return child; // Ảnh đã load xong
              } else {
                return Container(
                  height: 150,
                  color: Colors.grey[300],
                  alignment: Alignment.center,
                  child: CircularProgressIndicator(
                    value: loadingProgress.expectedTotalBytes != null
                        ? loadingProgress.cumulativeBytesLoaded / (loadingProgress.expectedTotalBytes ?? 1)
                        : null,
                  ),
                );
              }
            },
            // Lỗi tải ảnh
            errorBuilder: (context, error, stackTrace) {
              return Container(
                width: 150,
                height: 150,
                color: Colors.grey[300],
                child: Icon(Icons.broken_image, color: Colors.grey[600]),
              );
            },
          ),
        );
      } else {
        return Image.file(
          File(content),
          height: 150,
          fit: BoxFit.contain,
        );
      }
    } else if (type == 'video') {
        return _buildVideoWidget(content);
    } else if (type == 'pdf') {
        return _buildFileWidget(
            content,
            Icon(Icons.picture_as_pdf, color: Colors.red)
        );
    } else if (type == 'audio') {
        return AudioPlayerItem(audioUrl: content);
    } else if (type == 'youtube') {
      String videoId = _extractYouTubeId(Uri.parse(content));
      String thumbnailUrl = 'https://img.youtube.com/vi/$videoId/maxresdefault.jpg';
      return GestureDetector(
        onTap: () async {
          try {
            // Kiểm tra URL có thể mở được không
            final uri = Uri.parse(content);
            bool canLaunchLink = await canLaunchUrl(uri);

            if (canLaunchLink) {
              // Nếu có thể mở, mở URL trong ứng dụng ngoài (trình duyệt hoặc ứng dụng YouTube)
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            } else {
              throw 'Không thể mở link: $content';  // Ném lỗi nếu không mở được
            }
          } catch (e) {
            print("Error: $e");
          }
        },
        child: Column(
          children: [
            _buildYouTubeWidget(thumbnailUrl, width: 300),
            // Đoạn đường link phía dưới thumbnail
            Container(
              width: 300,
              padding: EdgeInsets.all(10),
              child: Text(
                content,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
      );
    } else {
        return _buildFileWidget(
            content,
            Icon(Icons.description, color: Colors.white)
        );
    }
  }

  Widget _buildYouTubeWidget(String thumbnailUrl, {double? width}) {
    return Stack(
      alignment: Alignment.center, // Căn giữa các phần tử trong Stack
      children: [
        // Hiển thị thumbnail
        Image.network(
          thumbnailUrl,
          height: 150,
          width: width ?? null,
          fit: BoxFit.cover,  // Sử dụng BoxFit.cover để lấp đầy khu vực với thumbnail
          // Hiển thị loading indicator khi đang tải ảnh
          loadingBuilder: (BuildContext context, Widget child, ImageChunkEvent? loadingProgress) {
            if (loadingProgress == null) {
              return child; // Ảnh đã load xong
            } else {
              return Container(
                height: 150,
                color: Colors.grey[300], // Hiển thị ảnh xám
              );
            }
          },
          // Lỗi tải ảnh
          errorBuilder: (context, error, stackTrace) {
            return Container(
              width: 150,
              height: 150,
              color: Colors.grey[300],
            );
          },
        ),
        // Biểu tượng Play ở giữa thumbnail
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(
            Icons.smart_display_rounded,
            color: Colors.red,
            size: 50,  // Kích thước của biểu tượng Play
          ),
        ),
      ],
    );
  }

  Widget _buildVideoWidget(String content) {
    if (!_videoThumbnailCache.containsKey(content)) {
      _videoThumbnailCache[content] = _getVideoThumbnail(content);
    }
    return FutureBuilder<String?>(
      future: _videoThumbnailCache[content],
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          // Hiển thị loading
          return Container(
            height: 150,
            width: 200,
            color: Colors.grey[300],
            alignment: Alignment.center,
            child: CircularProgressIndicator(),
          );
        } else if (snapshot.hasError || snapshot.data == null) {
          // Hiển thị icon lỗi hoặc placeholder nếu không lấy được thumbnail
          return Container(
            height: 150,
            width: 200,
            alignment: Alignment.center,
            child: Icon(Icons.error_outline, size: 40, color: Colors.grey),
          );
        } else {
          final thumbnailPath = snapshot.data!;
          return GestureDetector(
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (context) => VideoPlayerScreen(videoUrl: content),
              ),
              );
            },
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  height: 150,
                  width: 200,
                  decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(8),
                      image: DecorationImage(
                          fit: BoxFit.cover,
                          image: FileImage(File(thumbnailPath))
                      )
                  ),
                ),
                Icon(
                  Icons.play_circle_fill,
                  size: 60,
                  color: Colors.white.withOpacity(0.8),
                ),
              ],
            ),
          );
        }
      },
    );
  }

  Widget _buildFileWidget(String content, Icon icon){
    String filename = Uri.decodeComponent(content.split('/').last)
        .split('_').skip(1).join('_');
    return GestureDetector(
      onTap: () => _showDownloadConfirmationDialog(context, content),
      child: Container(
        padding: EdgeInsets.all(8.0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min, // Để Row không chiếm hết chiều ngang
          children: [
            icon,
            SizedBox(width: 8), // Khoảng cách giữa icon và tên file
            Flexible( // Thêm Flexible để giới hạn độ rộng của Text
              child: Text(filename,
                style: TextStyle(
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w500,
                  decoration: TextDecoration.underline,
                  decorationColor: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
                overflow: TextOverflow.ellipsis, // Cắt bớt text nếu quá dài
                maxLines: 1, // Chỉ hiển thị 1 dòng
                softWrap: false, // Không tự động xuống dòng
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDownloadConfirmationDialog(BuildContext context, String downloadLink) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("Xác nhận tải file"),
          content: Text("Bạn có muốn tải file này?"),
          actions: <Widget>[
            TextButton(
              child: Text("Hủy"),
              onPressed: () {
                Navigator.of(context).pop(); // Đóng dialog
              },
            ),
            TextButton(
              child: Text("Tải"),
              onPressed: () {
                _downloadFile(downloadLink);
                Navigator.of(context).pop(); // Đóng dialog
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _downloadFile(String downloadLink) async {
    try {
      final Dio dio = Dio();
      // Đường dẫn tải file về thư mục "Download"
      String directoryPath = "/storage/emulated/0/Download";
      String fileName = Uri.decodeComponent(downloadLink.split('/').last)
          .split('_').skip(1).join('_');
      String filePath = "$directoryPath/$fileName";

      // Tải file từ URL
      await dio.download(downloadLink, filePath);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Tải file thành công! Đã lưu tại $filePath")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Tải file thất bại: $e")),
      );
    }
  }

  // void _scrollToBottom() {
  //   if (_scrollController.hasClients) {
  //     WidgetsBinding.instance.addPostFrameCallback((_) {
  //       _scrollController.animateTo(
  //         _scrollController.position.minScrollExtent,
  //         duration: Duration(milliseconds: 300),
  //         curve: Curves.easeOut,
  //       );
  //     });
  //   }
  // }

  String removeVietnameseDiacritics(String str) {
    final Map<String, String> _charMap = {
      'à': 'a', 'á': 'a', 'ạ': 'a', 'ả': 'a', 'ã': 'a',
      'â': 'a', 'ầ': 'a', 'ấ': 'a', 'ậ': 'a', 'ẩ': 'a', 'ẫ': 'a',
      'ă': 'a', 'ằ': 'a', 'ắ': 'a', 'ặ': 'a', 'ẳ': 'a', 'ẵ': 'a',
      'è': 'e', 'é': 'e', 'ẹ': 'e', 'ẻ': 'e', 'ẽ': 'e',
      'ê': 'e', 'ề': 'e', 'ế': 'e', 'ệ': 'e', 'ể': 'e', 'ễ': 'e',
      'ì': 'i', 'í': 'i', 'ị': 'i', 'ỉ': 'i', 'ĩ': 'i',
      'ò': 'o', 'ó': 'o', 'ọ': 'o', 'ỏ': 'o', 'õ': 'o',
      'ô': 'o', 'ồ': 'o', 'ố': 'o', 'ộ': 'o', 'ổ': 'o', 'ỗ': 'o',
      'ơ': 'o', 'ờ': 'o', 'ớ': 'o', 'ợ': 'o', 'ở': 'o', 'ỡ': 'o',
      'ù': 'u', 'ú': 'u', 'ụ': 'u', 'ủ': 'u', 'ũ': 'u',
      'ư': 'u', 'ừ': 'u', 'ứ': 'u', 'ự': 'u', 'ử': 'u', 'ữ': 'u',
      'ỳ': 'y', 'ý': 'y', 'ỵ': 'y', 'ỷ': 'y', 'ỹ': 'y',
      'đ': 'd',
    };
    final buffer = StringBuffer();
    for (final char in str.characters) {
      buffer.write(_charMap[char] ?? char);
    }
    return buffer.toString();
  }

  /// Hàm hiển thị hộp thoại với các tùy chọn cho tin nhắn.
  Future<void> _showMessageOptions(LongPressStartDetails details, BuildContext context, Map<String, dynamic> message, int index) async {
    final content = message['content'] ?? '';
    final type = message['type'] ?? '';
    Offset _tapPosition = details.globalPosition;

    final selected = await showMenu(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12), // Bo góc menu
      ),
      position: RelativeRect.fromLTRB(_tapPosition.dx, _tapPosition.dy, _tapPosition.dx, _tapPosition.dy),
      items: type != 'text' && type != 'youtube'
          ? [
        PopupMenuItem<String>(
          value: 'download',
          child: Row(
            children: [
              Icon(Icons.download),
              SizedBox(width: 8),
              Text('Tải'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete),
              SizedBox(width: 8),
              Text('Xóa'),
            ],
          ),
        ),
      ]
          : [
        PopupMenuItem<String>(
          value: 'copy',
          child: Row(
            children: [
              Icon(Icons.copy),
              SizedBox(width: 8),
              Text('Sao chép'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'select',
          child: Row(
            children: [
              Icon(Icons.text_fields),
              SizedBox(width: 8),
              Text('Chọn văn bản'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete),
              SizedBox(width: 8),
              Text('Xóa'),
            ],
          ),
        ),
      ],
    );

    if (selected != null) {
      switch (selected) {
        case 'download':
          _downloadFile(content);
          break;
        case 'delete':
          _deleteMessage(index);
          break;
        case 'copy':
          FlutterClipboard.copy(content).then((_) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Đã sao chép tin nhắn!')),
            );
          });
          break;
        case 'select':
          _selectText(message);
          break;
      }
    }
  }

  /// Hàm xử lý chọn văn bản (select text).
  /// Bạn có thể tự hiện thực hóa trình chọn văn bản tùy theo yêu cầu.
  void _selectText(Map<String, dynamic> message) {
    final content = message['content'] ?? '';

    showDialog(
      context: context,
      builder: (context) {
        return LayoutBuilder(  // Sử dụng LayoutBuilder để đo lường kích thước
          builder: (BuildContext context, BoxConstraints constraints) {
            return AlertDialog(
              title: Text('Chọn văn bản'),
              content: ConstrainedBox( // Giới hạn chiều cao tối đa
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.5,
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    content,
                    style: TextStyle(fontSize: 16),
                  ),
                  // MarkdownBody(
                  //   selectable: true,
                  //   data: content,
                  //   styleSheet: MarkdownStyleSheet(
                  //     p: TextStyle(fontSize: 16),
                  //   ),
                  // ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Đóng'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // resizeToAvoidBottomInset: false,
      // onDrawerChanged: (isOpen) {
      //   WidgetsBinding.instance.addPostFrameCallback((_) {
      //     FocusScope.of(context).unfocus(); // Hủy focus bàn phím sau build UI
      //   });
      // },
      appBar: AppBar(
        title: Text(_currentChatName ?? 'Chat with AI'),
        actions: [
          IconButton(
            icon: Icon(Icons.settings),
            onPressed: _openModelConfigModal,
          ),
          IconButton(
            icon: Icon(Icons.add),
            onPressed: _startNewChat,
          ),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              // Ô tìm kiếm (đặt ngoài expand - cố định)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: TextField(
                  controller: _searchController, // Gắn controller để search
                  decoration: InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: AppLocalizations.of(context).translate('search'),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.shadow,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.0),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              // Danh sách lịch sử chat (cuộn riêng)
              Expanded(
                child: ListView.builder(
                  itemCount: _filteredChatHistories.length,
                  itemBuilder: (context, index) {
                    final chatDoc = _filteredChatHistories[index];
                    final chatData = chatDoc.data() as Map<String, dynamic>;
                    final chatName = chatData['name'] as String? ?? 'Unnamed Chat';

                    return GestureDetector(
                      onLongPressStart: (LongPressStartDetails details) {
                        _showChatOptions(details, chatDoc);
                      },
                      child: ListTile(
                        selected: _selectedIndex == index,
                        selectedTileColor: Colors.grey.withOpacity(0.2),
                        onTap: () {
                          // Cập nhật chỉ số của item được chọn
                          setState(() {
                            _selectedIndex = index;
                          });
                          Navigator.of(context).pop();
                          _viewChatHistory(chatDoc);
                        },
                        title: Text(
                          chatName,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    );
                  },
                ),
              ),
              // Thông tin người dùng (đặt ngoài expand - cố định)
              GestureDetector(
                onTap: () async {
                  Navigator.of(context).pop();
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (context) => SettingsScreen()),
                  );
                  _loadAvatarSetting();
                },
                child: Container(
                  decoration: BoxDecoration(color: Colors.blue),
                  padding: EdgeInsets.all(10),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundImage: _currentUser != null && _currentUser?.photoURL != null
                            ? NetworkImage(_currentUser!.photoURL!)
                            : AssetImage('assets/avatar/default_avt.png') as ImageProvider,
                        backgroundColor: Colors.white,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _currentUser?.displayName ?? 'Unknown User',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),

      body: GestureDetector(
        onTap: () {
          _messageFocusNode.unfocus();
        },
        child: Column(
          children: [
            Expanded(
              child: _isLoadingChat ? Center(child: CircularProgressIndicator())
              : ListView.builder(
                reverse: true,
                // controller: _scrollController,
                itemCount: _messages.length,
                itemBuilder: (ctx, index) {
                  final idx = _messages.length - 1 - index;
                  final message = _messages[idx];
                  final isUser = message['role'] == 'user';
                  final isError = message['role'] == 'error';
                  final content = message['content'] ?? '';
                  final type = message['type'];
                  final avatar = message['avatar'] ?? '';

                  return // Align → Row → (Avatar + Flexible(GestureDetector → Container))
                    // Dismissible(
                    // key: Key(message['content'] + index.toString()),
                    // direction: isUser
                    //     ? DismissDirection.endToStart
                    //     : DismissDirection.startToEnd,
                    // confirmDismiss: (direction) async {
                    //   // Khi vuốt hoàn tất, gọi hàm reply
                    //   if (isUser && direction == DismissDirection.endToStart) {
                    //     print("Vuốt sang phải");
                    //     // _handleReply(message, idx);
                    //   } else if (!isUser && direction == DismissDirection.startToEnd) {
                    //     print("Vuốt sang trái");
                    //     // _handleReply(message, idx);
                    //   }
                    //   return false;
                    // },
                    // background: Container(
                    //   // color: Colors.green,
                    //   alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                    //   padding: EdgeInsets.symmetric(horizontal: 20),
                    //   child: Icon(Icons.reply, color: Colors.blue, size: 32),
                    // ),
                    // child:
                    Align(
                      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                      child: GestureDetector(
                        onLongPressStart: (details) {
                          _showMessageOptions(details, context, message, idx);
                        },
                        //Tin nhắn
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
                          children: [
                            if (!isUser && _isAvatarEnabled) ...[
                              Padding(
                                padding: const EdgeInsets.only(left: 8.0, right: 4.0),
                                child: CircleAvatar(
                                  radius: 18,
                                  backgroundImage: avatar.isNotEmpty
                                    ? NetworkImage(avatar)
                                    : AssetImage('assets/avatar/default_bot_avt.png') as ImageProvider,
                                ),
                              ),
                            ],
                            Flexible(
                              child: Container(
                                // key: ValueKey(message['content']), //////////////////
                                key: ValueKey(idx), // Giúp Flutter nhận diện đúng widget nào thay đổi
                                margin: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                                padding: type != 'text'
                                    ? EdgeInsets.zero : EdgeInsets.all(10),
                                constraints: isUser ? BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75) : null, // Giới hạn chiều rộng
                                decoration: BoxDecoration(
                                  color: isError
                                      ? Theme.of(context).colorScheme.error
                                      : (isUser
                                          ? Theme.of(context).colorScheme.primaryContainer
                                          : Theme.of(context).colorScheme.secondaryContainer),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: type != 'text'
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: _displayFile(content, type),
                                )
                                : MarkdownBody(
                                    data: content,
                                    onTapLink: (text, href, title) async {
                                      if (href != null) {
                                        final uri = Uri.parse(href);
                                        bool canLaunchLink = await canLaunchUrl(uri);
                                        // print("Can launch $uri: $canLaunchLink");
                                        if (canLaunchLink) {
                                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                                        } else {
                                          // print("Không thể mở link: $uri");
                                          throw 'Không thể mở link: $href';
                                        }
                                      }
                                    },
                                    styleSheet: MarkdownStyleSheet(
                                      p: TextStyle(
                                          color: isUser ? Theme.of(context).colorScheme.onPrimaryContainer : Theme.of(context).colorScheme.onSecondaryContainer,
                                          fontSize: 16, // Cỡ chữ lớn hơn một chút
                                      ),
                                    ),
                                  ),
                                ),
                            ),
                          ],
                        ),
                      ),
                    // ),
                  );
                },
              ),
            ),
            _showFilesPicked(),
            _showImagesPicked(),
            _showYoutubePicked(),
            _buildSuggestions(),
            _buildMessageInputRow(),
            _showAudioRecording(),
          ],
        ),
      ),
    );
  }
}
