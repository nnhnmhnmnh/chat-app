import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

class ImageViewerScreen extends StatefulWidget {
  final String imageUrl;

  const ImageViewerScreen({Key? key, required this.imageUrl}) : super(key: key);

  @override
  _ImageViewerScreenState createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  // Biến điều khiển hiển thị của các widget overlay (nút download)
  bool _showControls = true;
  Timer? _hideControlsTimer;

  @override
  void initState() {
    super.initState();
    _startHideTimer();
  }

  /// Hàm bắt đầu bộ đếm ẩn các widget overlay sau 3 giây
  void _startHideTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      setState(() {
        _showControls = false;
      });
    });
  }

  /// Hàm ẩn hoặc hiện các widget overlay khi chạm vào màn hình.
  /// Nếu đang hiển thị, chạm sẽ ẩn ngay lập tức; nếu đang ẩn, chạm sẽ hiện lên và bắt đầu lại timer ẩn.
  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      _startHideTimer();
    } else {
      _hideControlsTimer?.cancel();
    }
  }

  /// Hàm tải file ảnh từ URL về thư mục "Download"
  Future<void> _downloadFile(String downloadLink) async {
    try {
      final Dio dio = Dio();
      // Đường dẫn tải file về thư mục "Download"
      String directoryPath = "/storage/emulated/0/Download";
      String fileName = Uri.decodeComponent(downloadLink.split('/').last)
          .split('_')
          .skip(1)
          .join('_');
      String filePath = "$directoryPath/$fileName";

      // Tải file từ URL
      await dio.download(downloadLink, filePath);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Tải file thành công! Đã lưu tại $filePath")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Tải file thất bại: $e")),
        );
      }
    }
    _startHideTimer(); // Reset timer sau khi tương tác
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        child: Stack(
          children: [
            // Hiển thị ảnh với kích thước full màn hình
            Center(
              child: InteractiveViewer(
                panEnabled: true, // Cho phép kéo ảnh
                minScale: 1.0,
                maxScale: 4.0,
                child: Image.network(
                  widget.imageUrl,
                  fit: BoxFit.contain,
                  width: double.infinity,
                  height: double.infinity,
                ),
              ),
            ),

            // Lớp phủ mờ ở đầu
            if (_showControls)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 100,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black.withOpacity(0.6), Colors.transparent],
                    ),
                  ),
                ),
              ),

            // Lớp phủ mờ ở đáy
            if (_showControls)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 100,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Colors.black.withOpacity(0.6), Colors.transparent],
                    ),
                  ),
                ),
              ),

            // Nút download overlay hiển thị ở góc trên bên phải
            Positioned(
              top: 30,
              right: 10,
              child: AnimatedOpacity(
                opacity: _showControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: IconButton(
                  iconSize: 32,
                  icon: const Icon(
                    Icons.download_rounded,
                    color: Colors.white,
                  ),
                  onPressed: () {
                    _downloadFile(widget.imageUrl);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
