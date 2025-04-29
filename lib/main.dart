import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart' as Pvd;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_localizations.dart';
import 'locale_provider.dart';
import 'screens/auth_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
// import 'package:flutter_displaymode/flutter_displaymode.dart';


void main() async {
  await dotenv.load();
  WidgetsFlutterBinding.ensureInitialized();
  // try {
  //   await FlutterDisplayMode.setHighRefreshRate();
  // } catch (e) {
  //   debugPrint("Không thể bật chế độ 120fps: $e");
  // }
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );
  runApp(
    Pvd.ChangeNotifierProvider(
      create: (context) => LocaleProvider(),
      child: MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  static _MyAppState? of(BuildContext context) =>
      context.findAncestorStateOfType<_MyAppState>();

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _loadThemeMode();
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

  void setThemeMode(ThemeMode themeMode) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('themeMode', themeMode.toString());
    setState(() {
      _themeMode = themeMode;
    });
  }

@override
  Widget build(BuildContext context) {
    final provider = Pvd.Provider.of<LocaleProvider>(context);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Chat App',
      locale: provider.locale, // Ngôn ngữ mặc định
      supportedLocales: const [
        Locale('en'), // Tiếng Anh
        Locale('vi'), // Tiếng Việt
      ],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      theme: ThemeData(
        brightness: Brightness.light,
        primarySwatch: Colors.blue,
        primaryColor: Colors.white,
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 0,
        ),
        drawerTheme: DrawerThemeData(
          backgroundColor: Color(0xFFF5F5F5),
        ),
        colorScheme: ColorScheme.light(
          primary: Colors.blue,
          secondary: Colors.green,
          surface: Colors.grey[100]!,
          onSurface: Color(0xFF424242),
          error: Colors.redAccent,
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          shadow: Color(0xFFE0E0E0),
          primaryContainer: Color(0xFF90CAF9),
          onPrimaryContainer: Color(0xFF212121),
          secondaryContainer: Color(0xFFE0E0E0),
          onSecondaryContainer: Color(0xFF212121),
        ),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Color(0xFF050505), // Màu nền ứng dụng
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0, // Loại bỏ bóng để không có viền giữa AppBar và nội dung
        ),
        drawerTheme: DrawerThemeData(
          backgroundColor: Color(0xFF090909), // Màu nền Drawer
        ),
        colorScheme: ColorScheme.dark(
          primary: Colors.blue, // Màu primary cho các widget chính
          secondary: Colors.green, // Màu phụ cho các widget phụ
          // surface: Colors.grey[900]!, // Màu bề mặt của các card, tin nhắn
          onSurface: Color(0xFFE0E0E0), // Màu chữ trên các bề mặt (surface)
          error: Colors.redAccent, // Màu cho lỗi
          onPrimary: Colors.white, // Màu chữ trên các phần có màu primary
          onSecondary: Colors.white, // Màu chữ trên các phần có màu secondary
          shadow: Color(0xFF1E1E1E), // Màu bóng (cho hiệu ứng nhẹ)
          primaryContainer: Color(0xFF1E3A8A), // Nền tin nhắn gửi
          onPrimaryContainer: Color(0xFFFFFFFF), // Chữ trong tin nhắn gửi
          secondaryContainer: Color(0xFF212121), // Nền tin nhắn nhận
          onSecondaryContainer: Color(0xFFD3D3D3), // Chữ trong tin nhắn nhận
        ),
      ),
      themeMode: _themeMode,
      // home: ChatScreen(),
      home: AuthScreen(),
    );
  }
}
