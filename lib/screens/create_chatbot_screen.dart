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
  XFile? _selectedAvatar;

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
    }
  }

  Future<String?> _uploadAvatarToSupabase() async {
    // Nếu chưa chọn avatar hoặc avatar đã là URL thì không upload
    if (_selectedAvatar == null ||
        Uri.tryParse(_selectedAvatar!.path)?.isAbsolute == true) return null;

    try {
      String fileName = '${DateTime.now()}_${path.basename(_selectedAvatar!.path)}';
      File avatarFile = File(_selectedAvatar!.path);

      // Upload file lên Supabase Storage
      final response = await Supabase.instance.client.storage
          .from('ai-chat-bucket')
          .upload(fileName, avatarFile);
      print("Upload response: $response");

      // Lấy public URL của file đã upload
      final String publicUrl = Supabase.instance.client.storage
          .from('ai-chat-bucket')
          .getPublicUrl(fileName);
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
      // Upload avatar và lấy URL
      String? avatarUrl = await _uploadAvatarToSupabase();

      Map<String, dynamic> data = {
        'userId': FirebaseAuth.instance.currentUser?.uid,
        'name': name,
        'shortDescription': shortDescription,
        'chatbotDescription': chatbotDescription,
        'avatarUrl': avatarUrl ?? widget.chatbotData?['avatar'] ?? '',
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
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // Hình đại diện: Khi nhấn chọn để upload
              GestureDetector(
                onTap: _pickAvatar,
                child: CircleAvatar(
                  radius: 50,
                  backgroundColor: Theme.of(context).colorScheme.shadow,
                  backgroundImage: _selectedAvatar != null
                      ? (Uri.tryParse(_selectedAvatar!.path)?.isAbsolute == true
                      ? NetworkImage(_selectedAvatar!.path)
                      : FileImage(File(_selectedAvatar!.path)) as ImageProvider)
                      : (widget.chatbotData != null &&
                      widget.chatbotData!['avatar'] != '')
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
              Expanded(
                child: TextFormField(
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
                  maxLines: null,
                  expands: true,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Vui lòng nhập mô tả chatbot';
                    }
                    return null;
                  },
                ),
              ),
              // SizedBox(height: 16),
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
            ],
          ),
        ),
      ),
    );
  }
}
