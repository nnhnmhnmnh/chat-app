import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_localizations.dart';

class ChatbotCreate extends StatefulWidget {
  final Function onCustomizationSaved;
  final Map<String, dynamic>? chatbotData; // Dữ liệu chatbot (có thể null nếu tạo mới)

  ChatbotCreate({required this.onCustomizationSaved, this.chatbotData});

  @override
  _ChatbotCreateState createState() => _ChatbotCreateState();
}

class _ChatbotCreateState extends State<ChatbotCreate> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _shortDescriptionController = TextEditingController();
  final _chatbotDescriptionController = TextEditingController();
  final _supabaseStorage = Supabase.instance.client.storage.from('ai-chat-bucket');
  XFile? _selectedAvatar;
  bool _isDefault = false;
  String? _deleteAvatar;

  final ImagePicker _picker = ImagePicker();

  Future<void> _pickAvatar() async {
    final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _selectedAvatar = pickedFile;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.chatbotData != null) {
      _nameController.text = widget.chatbotData!['name'] ?? '';
      _shortDescriptionController.text = widget.chatbotData!['description'] ?? '';
      _chatbotDescriptionController.text = widget.chatbotData!['chatbotDescription'] ?? '';

      _isDefault = widget.chatbotData!['isDefault'] ?? false;
    }
  }

  Future<String?> _uploadAvatarToSupabase() async {
    // Nếu chưa chọn avatar hoặc avatar đã là URL thì không upload
    if (_selectedAvatar == null ||
        Uri.tryParse(_selectedAvatar!.path)?.isAbsolute == true) return null;

    try {
      String fileName = '${DateTime.now()}_${path.basename(_selectedAvatar!.path)}';
      File avatarFile = File(_selectedAvatar!.path);

      // Nếu có avatar cũ và nó là URL Supabase thì xóa
      final String? oldAvatarUrl = widget.chatbotData?['avatar'];
      if (oldAvatarUrl != null) {
        // Lấy đường dẫn file từ URL
        final String filePath = Uri.decodeFull(oldAvatarUrl.split('/ai-chat-bucket/').last);
        await _supabaseStorage.remove([filePath]);
        print('Đã xóa avatar cũ: $filePath');
      }

      // Upload file lên Supabase Storage
      final response = await _supabaseStorage.upload(fileName, avatarFile);
      // print("Upload response: $response");

      // Lấy public URL của file đã upload
      final String publicUrl = _supabaseStorage.getPublicUrl(fileName);
      print("publicUrl:$publicUrl");
      return publicUrl;
    } catch (e) {
      print('Error uploading avatar: $e');
      return null;
    }
  }

  Future<void> _saveCustomization() async {
    // Validate các trường bắt buộc trước khi lưu
    if (!_formKey.currentState!.validate()) {
      return;
    }
    String name = _nameController.text.trim();
    String shortDescription = _shortDescriptionController.text.trim();
    String chatbotDescription = _chatbotDescriptionController.text.trim();

    try {
      // Xóa avatar nếu người dùng xác nhận
      if (_deleteAvatar != null) {
        final fileName = Uri.decodeFull(_deleteAvatar!.split('/ai-chat-bucket/').last);
        await _supabaseStorage.remove([fileName]);
        _deleteAvatar = null;
      }

      // Upload avatar và lấy URL
      String? avatarUrl = await _uploadAvatarToSupabase();

      Map<String, dynamic> data = {
        'userId': FirebaseAuth.instance.currentUser?.uid,
        'name': name,
        'shortDescription': shortDescription,
        'chatbotDescription': chatbotDescription,
        'avatarUrl': avatarUrl ?? widget.chatbotData?['avatar'] ?? '',
        'isDefault': _isDefault,
      };

      if (widget.chatbotData != null && widget.chatbotData!['id'] != null) {
        // Cập nhật chatbot nếu ID tồn tại
        await FirebaseFirestore.instance
            .collection('chatbot_customizations')
            .doc(widget.chatbotData!['id'])
            .update(data);
      } else {
        // Tạo mới chatbot và lưu vào Firestore
        await FirebaseFirestore.instance
            .collection('chatbot_customizations')
            .add(data);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Customization saved successfully!')),
      );
      // Gọi callback để reload danh sách chatbot
      widget.onCustomizationSaved();

      // Quay lại màn hình trước đó
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving customization: $e')),
      );
    }
  }

  void _showDeleteAvatarConfirmationDialog() {
    if (widget.chatbotData?['avatar'] == null || widget.chatbotData?['avatar'].isEmpty) return;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Delete Avatar?'),
          content: Text('Are you sure you want to delete this avatar?'),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();  // Đóng hộp thoại
              },
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                // xóa avatar
                _deleteAvatar = widget.chatbotData!['avatar'];
                setState(() {
                  _selectedAvatar = null;
                  widget.chatbotData!['avatar'] = '';
                });
                Navigator.of(context).pop();  // Đóng hộp thoại
              },
              child: Text('Yes'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).translate('customize_chatbot')),
        actions: [
          IconButton(
            icon: Icon(Icons.save),
            onPressed: _saveCustomization, // Khi nhấn vào biểu tượng này sẽ lưu
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        // Sử dụng Form để validate các trường bắt buộc
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                // Hình đại diện: Khi nhấn chọn để upload
                GestureDetector(
                  onLongPress: _showDeleteAvatarConfirmationDialog,
                  onTap: _pickAvatar,
                  child: CircleAvatar(
                    radius: 50,
                    backgroundColor: Theme.of(context).colorScheme.shadow,
                    backgroundImage: _selectedAvatar != null
                      ? (Uri.tryParse(_selectedAvatar!.path)?.isAbsolute == true
                        ? NetworkImage(_selectedAvatar!.path)
                        : FileImage(File(_selectedAvatar!.path)) as ImageProvider)
                      : (widget.chatbotData != null && widget.chatbotData!['avatar'] != '')
                        ? NetworkImage(widget.chatbotData!['avatar'])
                        : null,
                    child: (_selectedAvatar == null &&
                        (widget.chatbotData == null ||
                            widget.chatbotData!['avatar'] == ''))
                        ? Icon(Icons.add_a_photo, size: 50, color: Colors.white)
                        : null,
                  ),
                ),
                SizedBox(height: 16),
                // Ô nhập Name
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    hintText: 'Name',
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.shadow,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15.0),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Vui lòng nhập tên chatbot';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 16),
                // Ô nhập Short Description (không bắt buộc)
                TextFormField(
                  controller: _shortDescriptionController,
                  decoration: InputDecoration(
                    hintText: 'Short Description (optional)',
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.shadow,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15.0),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                SizedBox(height: 16),
                // Ô Chatbot Description: chiếm hết phần không gian còn lại
                // Expanded(
                //   child:
                TextFormField(
                  controller: _chatbotDescriptionController,
                  decoration: InputDecoration(
                    hintText: 'Chatbot Description',
                    alignLabelWithHint: true,
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.shadow,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15.0),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  minLines: 15,
                  maxLines: 15,
                  // expands: true,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Vui lòng nhập mô tả chatbot';
                    }
                    return null;
                  },
                ),
                // ),
                SizedBox(height: 16),
                // Nút Save
                // SizedBox(
                //   width: double.infinity,
                //   height: 50,
                //   child: ElevatedButton(
                //     onPressed: _saveCustomization,
                //     child: Text(
                //       'Save',
                //       style: TextStyle(
                //       fontSize: 18,
                //       fontWeight: FontWeight.bold,
                //     ),),
                //   ),
                // ),
                ListTileTheme(
                  contentPadding: EdgeInsets.zero, // Xóa khoảng thụt lề mặc định
                  child: Card(
                    color: Theme.of(context).colorScheme.shadow,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10), // Bo góc của Card
                    ),
                    // elevation: 5, // Thêm bóng đổ cho Card
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10.0, left: 10.0, right: 10.0), // Padding xung quanh content
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Tiêu đề và Icon
                                Row(
                                  children: [
                                    Icon(Icons.chat_bubble, color: Colors.blue), // Thêm icon chatbot
                                    SizedBox(width: 10),
                                    Text(
                                      'Default Chatbot',
                                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 8),
          
                                // Mô tả
                                Text(
                                  'When enabled, this chatbot will be used by default when you open the app.',
                                  style: TextStyle(fontSize: 14, color: Colors.grey),
                                ),
                                SizedBox(height: 12),
                              ],
                            ),
                          ),
                          Switch(
                            value: _isDefault,
                            onChanged: (value) {
                              setState(() {
                                _isDefault = value;
                              });
                            },
                            inactiveThumbColor: Colors.grey, // Màu khi tắt switch
                          ),
                        ]
                      ),
                    ),
                  ),
                ),
          
              ],
            ),
          ),
        ),
      ),
    );
  }
}
