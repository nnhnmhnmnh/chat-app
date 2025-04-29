import 'package:chatapp/screens/customize_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../app_localizations.dart';
import '../locale_provider.dart';
import '../main.dart';
import 'auth_screen.dart';

class SettingsScreen extends StatefulWidget {
  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  ThemeMode _themeMode = ThemeMode.system;
  bool _isAvatarEnabled = false;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _loadThemeMode();
    _loadAvatarSetting();
  }

  Future<Map<String, dynamic>> _getUserData() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      return {};
    }
    final userDoc = await _firestore.collection('users').doc(userId).get();
    return userDoc.exists ? userDoc.data() as Map<String, dynamic> : {};
  }

  void _loadThemeMode() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? theme = prefs.getString('themeMode');
    if (theme != null) {
      setState(() {
        _themeMode = ThemeMode.values.firstWhere((e) => e.toString() == theme);
      });
    }
  }

  void _setAvatarSetting(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isAvatarEnabled', value);
    setState(() {
      _isAvatarEnabled = value;
    });
  }

  Future<void> _loadAvatarSetting() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isAvatarEnabled = prefs.getBool('isAvatarEnabled') ?? false;
    });
  }

  void _showLanguageDialog(BuildContext context, LocaleProvider provider) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(AppLocalizations.of(context).translate('select_language')),
          content: Container(
            width: double.minPositive, // Đảm bảo width của container không quá nhỏ
            child: ListView(
              shrinkWrap: true,
              children: [
                ListTile(
                  title: Text('English'),
                  onTap: () {
                    provider.setLocale(Locale('en'));
                    Navigator.of(context).pop(); // Đóng hộp thoại
                  },
                ),
                ListTile(
                  title: Text('Tiếng Việt'),
                  onTap: () {
                    provider.setLocale(Locale('vi'));
                    Navigator.of(context).pop(); // Đóng hộp thoại
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLeadingThemeMode(ThemeMode themeMode) {
    switch (themeMode) {
      case ThemeMode.system:
        return Icon(Icons.brightness_auto);
      case ThemeMode.light:
        return Icon(Icons.light_mode);
      case ThemeMode.dark:
        return Icon(Icons.dark_mode);
      default: return Icon(Icons.brightness_auto);
    }
  }

  void _showThemeModeDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(AppLocalizations.of(context).translate('select_theme')),
          content: Container(
            width: double.minPositive, // Đảm bảo width của container không quá nhỏ
            child: ListView(
              shrinkWrap: true,
              children: [
                ListTile(
                  leading: Icon(Icons.brightness_auto),
                  title: Text(AppLocalizations.of(context).translate('system')),
                  onTap: () {
                    MyApp.of(context)?.setThemeMode(ThemeMode.system);
                    Navigator.of(context).pop(); // Đóng hộp thoại
                    setState(() {
                      _themeMode = ThemeMode.system;
                    });
                  },
                ),
                ListTile(
                  leading: Icon(Icons.light_mode),
                  title: Text(AppLocalizations.of(context).translate('light')),
                  onTap: () {
                    MyApp.of(context)?.setThemeMode(ThemeMode.light);
                    Navigator.of(context).pop(); // Đóng hộp thoại
                    setState(() {
                      _themeMode = ThemeMode.light;
                    });
                  },
                ),
                ListTile(
                  leading: Icon(Icons.dark_mode),
                  title: Text(AppLocalizations.of(context).translate('dark')),
                  onTap: () {
                    MyApp.of(context)?.setThemeMode(ThemeMode.dark);
                    Navigator.of(context).pop(); // Đóng hộp thoại
                    setState(() {
                      _themeMode = ThemeMode.dark;
                    });
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _signOut() async {
    await GoogleSignIn().disconnect(); //
    await FirebaseAuth.instance.signOut();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => AuthScreen()),
          (Route<dynamic> route) => false,
    );
  }

  void _showDeleteConfirmation() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Delete All Chat'),
          content: Text('Are you sure you want to delete all chat?'),
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
                _deleteAllChats();
                Navigator.pop(context);
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteAllChats() async {
    try {
      // Lấy toàn bộ document trong collection 'chat_histories'
      final QuerySnapshot querySnapshot =
      await _firestore.collection('chat_histories')
          .where('userId', isEqualTo: _auth.currentUser?.uid)
          .get();

      // Danh sách các Future để xóa file trên Supabase (sẽ thực hiện đồng thời)
      final List<Future> fileDeletionFutures = [];

      // Sử dụng WriteBatch để xóa tất cả document trong một batch (nếu số lượng < 500)
      WriteBatch batch = _firestore.batch();

      // Duyệt qua từng document chat
      for (final QueryDocumentSnapshot doc in querySnapshot.docs) {
        final messages = (doc.data() as Map<String, dynamic>)['messages'] as List?;

        if (messages != null) {
          for (final message in messages) {
            if (message is Map &&
                message['role'] == 'user' &&
                message.containsKey('content')) {
              final String content = message['content'] as String;
              if (content.startsWith('http')){
                final fileName = Uri.parse(content).pathSegments.last;
                // Thêm Future xóa file từ Supabase Storage.
                // Lưu ý: phương thức remove nhận vào danh sách các file cần xóa.
                fileDeletionFutures.add(
                  supabase.Supabase.instance.client.storage
                      .from('ai-chat-bucket').remove([fileName]),
                );
              }
            }
          }
        }
        // Thêm lệnh xóa document vào batch
        batch.delete(doc.reference);
      }

      // Thực hiện đồng thời tất cả các lệnh xóa file trên Supabase
      await Future.wait(fileDeletionFutures);

      // Commit batch xóa các document trên Firestore
      await batch.commit();

      print('Đã xóa thành công tất cả đoạn chat và file liên quan.');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('All chat deleted.')),
      );
    } catch (e) {
      print('Có lỗi xảy ra: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<LocaleProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).translate('setting')),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _getUserData(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final userData = snapshot.data ?? {};
          final name = userData['name'] ?? 'Unknown User';
          final email = userData['email'] ?? 'Unknown Email';
          final avatar = userData['photoUrl'] ?? '';

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundImage: avatar != null
                          ? NetworkImage(avatar!)
                          : AssetImage('assets/avatar/default_avt.png') as ImageProvider,
                      backgroundColor: Colors.white,
                    ),
                    SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          email,
                          style: TextStyle(
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                SizedBox(height: 24),
                ListTile(
                  leading: Icon(Icons.email),
                  title: Text('Email'),
                  subtitle: Text(email),
                  onTap: () {
                    // Hành động khi nhấn vào mục Email (nếu cần)
                  },
                ),
                ListTile(
                  leading: Icon(Icons.tune),
                  title: Text(AppLocalizations.of(context).translate('customize_chatbot')),
                  onTap: () {
                    // Chuyển đến màn hình Customize
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (context) => ChatbotCustomize()),
                    );
                  },
                ),
                ListTile(
                  leading: Icon(Icons.language),
                  title: Text(AppLocalizations.of(context).translate('language')),
                  trailing: Text(provider.locale.languageCode.toUpperCase()),
                  onTap: () {
                    _showLanguageDialog(context, provider);
                  },
                ),
                ListTile(
                  leading: _buildLeadingThemeMode(_themeMode),
                  title: Text(AppLocalizations.of(context).translate('theme')),
                  onTap: () {
                    _showThemeModeDialog(context);
                  },
                ),
                SwitchListTile(
                  title: Text(AppLocalizations.of(context).translate('message_avatar')),
                  secondary: Icon(Icons.account_circle),
                  value: _isAvatarEnabled,
                  onChanged: (value) {
                    setState(() {
                      _isAvatarEnabled = value;
                      _setAvatarSetting(value);
                    });
                  },
                  inactiveThumbColor: Colors.grey, // Màu nút gạt khi tắt
                ),
                ListTile(
                  leading: Icon(Icons.delete_sweep),
                  title: Text(AppLocalizations.of(context).translate('delete_all')),
                  onTap: () {
                    _showDeleteConfirmation();
                  },
                ),
                ListTile(
                  leading: Icon(Icons.logout),
                  title: Text(AppLocalizations.of(context).translate('logout')),
                  onTap: () {
                    _signOut();
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
