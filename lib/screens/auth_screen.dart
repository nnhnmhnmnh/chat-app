import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'chat_screen.dart';

class AuthScreen extends StatelessWidget {
  Future<void> _signInWithGoogle(BuildContext context) async {
    try {
      // Khởi tạo GoogleSignIn
      final GoogleSignIn googleSignIn = GoogleSignIn();
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();

      if (googleUser != null) {
        // Lấy thông tin xác thực từ Google
        final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

        // Tạo thông tin xác thực Firebase
        final AuthCredential credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        // Đăng nhập Firebase với thông tin xác thực
        final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
        final User? firebaseUser = userCredential.user;

        if (firebaseUser != null) {
          // Lưu thông tin người dùng vào Firestore
          final userDoc = FirebaseFirestore.instance.collection('users').doc(firebaseUser.uid);
          await userDoc.set({
            'uid': firebaseUser.uid,
            'name': firebaseUser.displayName ?? 'Unknown',
            'email': firebaseUser.email ?? 'No email',
            'photoUrl': firebaseUser.photoURL ?? '',
            'lastLogin': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true)); // merge giữ dữ liệu cũ nếu user đã tồn tại
        }

        // Chuyển đến màn hình ChatScreen
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => ChatScreen()),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Login failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Lấy thông tin người dùng hiện tại từ FirebaseAuth
    final User? currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser != null) {
      // Nếu người dùng đã đăng nhập, chuyển tới ChatScreen
      Future.microtask(() {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => ChatScreen()),
        );
      });
    }

    // Nếu chưa đăng nhập, hiển thị màn hình đăng nhập
    return Scaffold(
      appBar: AppBar(title: Text('Login')),
      body: Center(
        child: ElevatedButton.icon(
          icon: Icon(Icons.login),
          label: Text('Sign in with Google'),
          onPressed: () => _signInWithGoogle(context),
        ),
      ),
    );
  }
}