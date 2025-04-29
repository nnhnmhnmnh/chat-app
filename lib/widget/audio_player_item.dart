import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../audio_manager.dart';

class AudioPlayerItem extends StatefulWidget {
  final String audioUrl;

  AudioPlayerItem({required this.audioUrl});

  @override
  _AudioPlayerItemState createState() => _AudioPlayerItemState();
}

class _AudioPlayerItemState extends State<AudioPlayerItem> {
  late AudioPlayer _audioPlayer;
  bool isPlaying = false;
  bool isPaused = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _setupAudioListeners();
  }

  void _setupAudioListeners() {
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
      if (mounted) { // kiểm tra xem widget đã unmounted chưa
        setState(() {
          _position = position;
        });
      }
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

  @override
  void dispose() {
    _audioPlayer.dispose();
    AudioManager.clear();
    super.dispose();
  }

  Future<void> _playMusic() async {
    try {
      // Thông báo cho AudioManager rằng widget này muốn phát
      await AudioManager.play(_audioPlayer, () {
        // Callback này sẽ được gọi khi có widget khác muốn phát,
        setState(() {
          isPlaying = false;
          isPaused = false;
          // 2 false nghĩa là stop, sau khi stop mà play lại thì sẽ vào _playMusic
          // vì chỉ có _playMusic dùng AudioManager, nó sẽ dừng phát bài khác nếu có
        });
      });

      // Sau khi AudioManager đã dừng audio khác nếu có, tiếp tục phát audio của widget hiện tại
      await _audioPlayer.setUrl(widget.audioUrl);
      _audioPlayer.play();

      setState(() {
        isPlaying = true;
        isPaused = false;
      });
    } catch (e) {
      print('Error playing audio: $e');
    }
  }

  void _pauseMusic() {
    _audioPlayer.pause();
    setState(() {
      isPaused = true;
      isPlaying = false;
    });
  }

  void _resumeMusic() {
    _audioPlayer.play();
    setState(() {
      isPaused = false;
      isPlaying = true;
    });
  }

  void _seekMusic(double value) {
    final position = Duration(seconds: value.toInt());
    _audioPlayer.seek(position);
  }

  String formatTime(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }


  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(right: 10),
      height: 50,
      child: Row(
        // mainAxisSize: MainAxisSize.min,
        // mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white),
            visualDensity: VisualDensity(horizontal: -4),
            onPressed: () {
              if (!isPlaying && !isPaused) {
                // Nếu chưa phát, bấm play
                _playMusic();
              } else if (isPlaying) {
                // Nếu đang phát, bấm pause
                _pauseMusic();
              } else if (isPaused) {
                // Nếu đang tạm dừng, bấm resume
                _resumeMusic();
              }
            },
          ),
          // Text(formatTime(_position), style: TextStyle(color: Colors.white)),
          // Text(formatTime(_position), style: TextStyle(color: Colors.white)),
          Slider(
            activeColor: Colors.white,
            min: 0,
            max: _duration.inSeconds.toDouble(),
            value: _position.inSeconds.toDouble().clamp(0, _duration.inSeconds.toDouble()),
            onChanged: (value) {
              _seekMusic(value);
            },
          ),
          Text(formatTime(_duration - _position), style: TextStyle(color: Colors.white)),
          // Text(formatTime(_duration), style: TextStyle(color: Colors.white)),
        ],
      ),
    );
  }
}