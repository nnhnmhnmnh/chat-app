import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

class MusicPlayer extends StatefulWidget {
  @override
  _MusicPlayerState createState() => _MusicPlayerState();
}

class _MusicPlayerState extends State<MusicPlayer> {
  late AudioPlayer _audioPlayer;
  bool isPlaying = false;
  bool isPaused = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  /// Lưu lại URL của audio hiện tại đang được load/phát
  String? currentUrl;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();

    // Lắng nghe thay đổi thời lượng của audio
    _audioPlayer.durationStream.listen((duration) {
      if (duration != null) {
        setState(() {
          _duration = duration;
        });
      }
    });

    // Lắng nghe vị trí hiện tại của audio
    _audioPlayer.positionStream.listen((position) {
      setState(() {
        _position = position;
      });
    });

    // Khi audio kết thúc thì cập nhật trạng thái
    _audioPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        setState(() {
          isPlaying = false;
          isPaused = false;
          _position = Duration.zero;
        });
      }
    });
  }

  /// Phát audio của tin nhắn với URL được truyền vào.
  /// Nếu đang phát audio khác thì dừng và load audio mới.
  Future<void> playMusic(String url) async {
    try {
      // Nếu URL khác với audio đang phát hiện tại thì tải audio mới
      if (currentUrl != url) {
        await _audioPlayer.stop(); // Dừng audio hiện tại nếu có
        currentUrl = url;
        await _audioPlayer.setUrl(url);
      }
      // Nếu audio đang tạm dừng thì chỉ cần tiếp tục phát lại
      if (isPaused) {
        _audioPlayer.play();
      } else {
        // Nếu audio đã được tải từ trước hoặc vừa tải mới thì phát
        _audioPlayer.play();
      }
      setState(() {
        isPlaying = true;
        isPaused = false;
      });
    } catch (e) {
      print('Error: $e');
    }
  }

  /// Tạm dừng audio
  void pauseMusic() {
    _audioPlayer.pause();
    setState(() {
      isPaused = true;
      isPlaying = false;
    });
  }

  /// Tiếp tục phát audio khi đang tạm dừng
  void resumeMusic() {
    _audioPlayer.play();
    setState(() {
      isPaused = false;
      isPlaying = true;
    });
  }

  /// Dừng phát audio và reset trạng thái
  void stopMusic() {
    _audioPlayer.stop();
    setState(() {
      isPlaying = false;
      isPaused = false;
      _position = Duration.zero;
    });
  }

  /// Di chuyển vị trí phát audio
  void seekMusic(double value) {
    final position = Duration(seconds: value.toInt());
    _audioPlayer.seek(position);
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  String formatTime(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    // Giả sử đây là danh sách các tin nhắn có chứa URL audio
    final List<Map<String, String>> messages = [
      {
        'id': '1',
        'text': 'Tin nhắn 1',
        'audioUrl': 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3'
      },
      {
        'id': '2',
        'text': 'Tin nhắn 2',
        'audioUrl': 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3'
      },
      // Thêm các tin nhắn khác nếu cần
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text('Chat Audio Player'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            // Danh sách các tin nhắn (ở đây chỉ hiển thị text và nút play)
            Expanded(
              child: ListView.builder(
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  final message = messages[index];
                  return ListTile(
                    title: Text(message['text']!),
                    trailing: IconButton(
                      icon: Icon(Icons.play_arrow),
                      onPressed: () {
                        // Mỗi khi bấm nút play, gọi playMusic với URL tương ứng của tin nhắn
                        playMusic(message['audioUrl']!);
                      },
                    ),
                  );
                },
              ),
            ),
            Divider(),
            // Phần điều khiển cho audio hiện tại đang được phát
            Column(
              children: [
                Slider(
                  min: 0,
                  max: _duration.inSeconds.toDouble(),
                  value: _position.inSeconds.toDouble().clamp(
                    0,
                    _duration.inSeconds.toDouble(),
                  ),
                  onChanged: (value) {
                    seekMusic(value);
                  },
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(formatTime(_position)),
                    Text(formatTime(_duration)),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      onPressed: isPlaying || isPaused ? stopMusic : null,
                      child: Text('Stop'),
                    ),
                    SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: () {
                        if (!isPlaying && !isPaused) {
                          // Nếu chưa phát thì không làm gì vì phải bấm vào tin nhắn
                          print("Chọn tin nhắn để phát audio.");
                        } else if (isPlaying) {
                          pauseMusic();
                        } else if (isPaused) {
                          resumeMusic();
                        }
                      },
                      child: Text(
                        !isPlaying && !isPaused ? 'Play' : (isPlaying ? 'Pause' : 'Resume'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
