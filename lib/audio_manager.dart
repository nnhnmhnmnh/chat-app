import 'package:just_audio/just_audio.dart';

class AudioManager {
  static AudioPlayer? currentPlayer;
  static Function? onStopCallback;

  /// Khi một widget muốn phát, nó sẽ gọi hàm này
  static Future<void> play(AudioPlayer newPlayer, Function stopCallback) async {
    // Nếu đã có player đang chạy, dừng nó trước
    if (currentPlayer != null && currentPlayer != newPlayer) {
      if (onStopCallback != null) {
        onStopCallback!();  // Yêu cầu widget đó dừng phát (cập nhật UI)
      }
      await currentPlayer!.seek(Duration.zero);
      await currentPlayer!.stop();
    }
    // Lưu lại để gọi sau (gọi ở phần trên, khi bấm nghe một audio khác)
    currentPlayer = newPlayer;
    onStopCallback = stopCallback;
  }

  static void clear() {
    currentPlayer = null;
    onStopCallback = null;
  }
}
