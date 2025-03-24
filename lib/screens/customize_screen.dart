import 'package:chatapp/screens/create_chatbot_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_localizations.dart';

class ChatbotCustomize extends StatefulWidget {
  @override
  _ChatbotCustomizeState createState() => _ChatbotCustomizeState();
}

class _ChatbotCustomizeState extends State<ChatbotCustomize> {
  List<Map<String, dynamic>> chatbotList = [];
  TextEditingController searchController = TextEditingController();
  List<Map<String, dynamic>> filteredList = [];

  @override
  void initState() {
    super.initState();
    _loadChatbotList();
  }

  void _loadChatbotList() async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    // Truy vấn chatbot của người dùng
    final querySnapshot = await FirebaseFirestore.instance
        .collection('chatbot_customizations')
        .where('userId', isEqualTo: currentUserId)
        .get();
    final List<Map<String, dynamic>> fetchedChatbots = querySnapshot.docs.map((doc) {
      return {
        'id': doc.id,
        'userId': doc['userId'],
        'name': doc['name'],
        'description': doc['shortDescription'],
        'avatar': doc['avatarUrl'],
        'chatbotDescription': doc['chatbotDescription'],
      };
    }).toList();

    // Truy vấn chatbot mặc định
    final defaultQuerySnapshot = await FirebaseFirestore.instance
        .collection('chatbot_customizations')
        .where('isPublic', isEqualTo: true)
        .where('userId', isNotEqualTo: currentUserId)
        .orderBy('userId') // Bắt buộc phải có orderBy trên trường dùng toán tử bất đẳng thức
        .get();
    final List<Map<String, dynamic>> fetchedDefaultChatbots = defaultQuerySnapshot.docs.map((doc) {
      return {
        'id': doc.id,
        'userId': doc['userId'],
        'name': doc['name'],
        'description': doc['shortDescription'],
        'avatar': doc['avatarUrl'],
        'chatbotDescription': doc['chatbotDescription'],
      };
    }).toList();

    // Kết hợp cả chatbot người dùng và chatbot mặc định
    final List<Map<String, dynamic>> combinedChatbotList = [
      ...fetchedDefaultChatbots,  // Thêm chatbot mặc định
      ...fetchedChatbots,     // Thêm chatbot người dùng
    ];

    setState(() {
      chatbotList = combinedChatbotList;
      filteredList = List.from(chatbotList);
    });
  }

  void filterChatbots(String query) {
    setState(() {
      filteredList = chatbotList
          .where((bot) => bot['name']!.toLowerCase().contains(query.toLowerCase()))
          .toList();
    });
  }

  void deleteChatbot(int index) async {
    final chatbotId = filteredList[index]['id'];

    // Lấy path của ảnh từ Firestore
    final docSnapshot = await FirebaseFirestore.instance
        .collection('chatbot_customizations')
        .doc(chatbotId)
        .get();

    if (docSnapshot.exists) {
      final data = docSnapshot.data();
      final avatarUrl = data?['avatarUrl'];

      // Xóa ảnh trên Supabase nếu avatarUrl tồn tại
      if (avatarUrl != null && avatarUrl.isNotEmpty) {
        final response = await Supabase.instance.client.storage
            .from('ai-chat-bucket')
            .remove([avatarUrl]);

        print("response: $response");
      }
    }

    // Xóa chatbot khỏi Firestore
    await FirebaseFirestore.instance
        .collection('chatbot_customizations')
        .doc(chatbotId)
        .delete();

    setState(() {
      filteredList.removeAt(index);
      chatbotList = List.from(filteredList);
    });
  }

  void _showChatbotMenu(LongPressStartDetails details, Map<String, dynamic> bot, int index) async {
    final tapPosition = details.globalPosition;
    final isPublicBot = bot['userId'] != FirebaseAuth.instance.currentUser?.uid;

    showMenu(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12), // Bo góc menu
      ),
      position: RelativeRect.fromLTRB(
        tapPosition.dx,
        tapPosition.dy,
        tapPosition.dx,
        tapPosition.dy,
      ),
      items: [
        PopupMenuItem(
          value: 'delete',
          enabled: !isPublicBot, // Vô hiệu hóa mục xóa nếu là chatbot mặc định
          child: ListTile(
            leading: Icon(Icons.delete),
            title: Text('Delete'),
          ),
        ),
      ],
    ).then((result) {
      if (result == 'delete') {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Delete Chatbot'),
            content: Text('Are you sure you want to delete "${bot['name']}"?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  deleteChatbot(index);
                  Navigator.pop(context);
                },
                child: Text('Delete'),
              ),
            ],
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Chatbot Customizer'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: searchController,
              onChanged: filterChatbots,
              decoration: InputDecoration(
                hintText: AppLocalizations.of(context).translate('search'),
                prefixIcon: Icon(Icons.search),
                filled: true,
                fillColor: Theme.of(context).colorScheme.shadow,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8.0),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: filteredList.length,
              itemBuilder: (context, index) {
                final bot = filteredList[index];

                return GestureDetector(
                  onLongPressStart: (LongPressStartDetails details) {
                    _showChatbotMenu(details, bot, index);
                  },
                  child: Card(
                    margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                    child: ListTile(
                      onTap: (){
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ChatbotCreate(
                              onCustomizationSaved: _loadChatbotList,
                              chatbotData: bot,
                            ),
                          ),
                        );
                      },
                      leading: CircleAvatar(
                        backgroundImage: bot['avatar'] != null && bot['avatar']!.isNotEmpty
                            ? NetworkImage(bot['avatar']!)
                            : AssetImage('assets/avatar/default_bot_avt.png') as ImageProvider,
                      ),
                      title: Text(bot['name']!),
                      subtitle: bot['description'] != null
                          ? Text(bot['description']!)
                          : null,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton( // change with transform animation
        onPressed: () {
          Navigator.of(context).push(
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) => ChatbotCreate(
                onCustomizationSaved: _loadChatbotList, // Gọi hàm load danh sách
              ),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                const begin = 0.0;
                const end = 1.0;
                const curve = Curves.easeOut;

                final tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
                final scaleAnimation = animation.drive(tween);

                return ScaleTransition(
                  scale: scaleAnimation,
                  alignment: Alignment.bottomRight, // Đặt vị trí zoom tại góc dưới bên phải
                  child: child,
                );
              },
            ),
          );
        },
        child: Icon(Icons.add),
      ),
    );
  }
}
