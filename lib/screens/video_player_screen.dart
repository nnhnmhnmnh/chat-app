import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class VideoPlayerScreen extends StatefulWidget {
  final String videoUrl;

  const VideoPlayerScreen({Key? key, required this.videoUrl}) : super(key: key);

  @override
  _VideoPlayerScreenState createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late VideoPlayerController _VPController;
  late Future<void> _initializeVideoPlayerFuture;

  // Biến điều khiển hiển thị của thanh điều khiển (bottom controls) và nút download (top right)
  bool _showControls = true;
  Timer? _hideControlsTimer;

  @override
  void initState() {
    super.initState();
    _VPController = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
    _initializeVideoPlayerFuture = _VPController.initialize().then((_) {
      setState(() {
        _VPController.play(); // Tự động phát video sau khi khởi tạo
      });
      _startHideTimer(); // Bắt đầu đếm giờ ẩn thanh điều khiển
    });
    _VPController.setLooping(true);

    // Lắng nghe thay đổi của video để cập nhật giao diện (đặc biệt slider)
    _VPController.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
  }

  /// Hàm bắt đầu bộ đếm ẩn các widget điều khiển sau 3 giây
  void _startHideTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      setState(() {
        _showControls = false;
      });
    });
  }

  /// Hàm ẩn hoặc hiện các widget điều khiển khi chạm vào màn hình.
  /// Nếu đang hiển thị, chạm sẽ ẩn ngay lập tức (và hủy timer);
  /// Nếu đang ẩn, chạm sẽ hiện lên và bắt đầu lại timer ẩn.
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

  /// Hàm chuyển đổi giữa phát và tạm dừng video
  void _togglePlayPause() {
    setState(() {
      if (_VPController.value.isPlaying) {
        _VPController.pause();
      } else {
        _VPController.play();
      }
    });
    // Khi tương tác, reset timer ẩn
    _startHideTimer();
  }

  /// Hàm tải file video
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
    _VPController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: FutureBuilder(
        future: _initializeVideoPlayerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return GestureDetector(
              onTap: _toggleControls,
              child: Stack(
                children: [
                  // Video chiếm toàn bộ màn hình
                  Center(
                    child: AspectRatio(
                      aspectRatio: _VPController.value.aspectRatio,
                      child: VideoPlayer(_VPController),
                    ),
                  ),
                  // Nút download ở góc trên bên phải
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
                          _downloadFile(widget.videoUrl);
                        },
                      ),
                    ),
                  ),
                  // Thanh điều khiển bottom overlay: nút play/pause, seekbar, thời gian
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: AnimatedOpacity(
                      opacity: _showControls ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 300),
                      child: Container(
                        color: Colors.black54,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8.0, vertical: 4.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Nút play/pause
                            IconButton(
                              iconSize: 32,
                              icon: Icon(
                                _VPController.value.isPlaying
                                    ? Icons.pause
                                    : Icons.play_arrow,
                                color: Colors.white,
                              ),
                              onPressed: _togglePlayPause,
                            ),
                            // Thanh seekbar
                            Expanded(
                              child: Slider(
                                activeColor: Colors.redAccent,
                                inactiveColor: Colors.grey,
                                min: 0.0,
                                max: _VPController.value.duration.inSeconds
                                    .toDouble(),
                                value: _VPController.value.position.inSeconds
                                    .toDouble()
                                    .clamp(
                                  0.0,
                                  _VPController.value.duration.inSeconds
                                      .toDouble(),
                                ),
                                onChanged: (value) {
                                  setState(() {
                                    _VPController.seekTo(
                                        Duration(seconds: value.toInt()));
                                  });
                                  _startHideTimer();
                                },
                              ),
                            ),
                            // Hiển thị thời gian: current/total
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4.0),
                              child: Text(
                                '${_formatDuration(_VPController.value.position)}/${_formatDuration(_VPController.value.duration)}',
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          } else {
            return const Center(child: CircularProgressIndicator());
          }
        },
      ),
    );
  }

  /// Hàm chuyển đổi Duration sang định dạng mm:ss
  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$minutes:$seconds";
  }
}
