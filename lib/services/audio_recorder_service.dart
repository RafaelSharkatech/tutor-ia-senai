// 1. Dart
import 'dart:async';
import 'dart:io';

// 2. Packages
// 2.1. Flutter Packages
import 'package:flutter/foundation.dart';
// 2.2. Third-Party Packages
import 'package:audioplayers/audioplayers.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class AudioRecorderException implements Exception {
  final String message;
  AudioRecorderException(this.message);

  @override
  String toString() => '###>>> AudioRecorderException: $message';
}

class RecordingSummary {
  final String uri;
  final Duration duration;

  RecordingSummary({
    required this.uri,
    required this.duration,
  });
}

class AudioRecorderService {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  String? _lastUri;
  DateTime? _recordingStartedAt;
  bool get hasRecording => _lastUri != null;

  Duration? _lastDuration;
  Duration? get lastDuration => _lastDuration;

  Future<void> start() async {
    final bool recorderHasPermission = await _recorder.hasPermission();

    if (!recorderHasPermission) {
      throw AudioRecorderException(
        'Permissao de microfone negada ou indisponivel.',
      );
    }

    final AudioEncoder encoder = await _selectEncoder();
    final String outputPath = await _buildOutputPath(encoder);

    final RecordConfig recordConfig = RecordConfig(
      encoder: encoder,
      sampleRate: 48_000,
      bitRate: 128_000,
      noiseSuppress: true,
      echoCancel: true,
    );

    await _recorder.start(recordConfig, path: outputPath);
    _recordingStartedAt = DateTime.now();
    _lastDuration = null;
  }

  Future<RecordingSummary> stop() async {
    final String? path = await _recorder.stop();

    if (path == null) {
      throw AudioRecorderException('Nenhum audio gravado.');
    }

    _lastUri = path;

    final Duration duration = _recordingStartedAt == null
        ? Duration.zero
        : DateTime.now().difference(_recordingStartedAt!);
    _recordingStartedAt = null;
    _lastDuration = duration;

    return RecordingSummary(uri: path, duration: duration);
  }

  Future<void> playLastRecording() async {
    final String? uri = _lastUri;

    if (uri == null) {
      throw AudioRecorderException('Nenhuma gravação disponível.');
    }

    await _player.stop();

    if (kIsWeb || uri.startsWith('http') || uri.startsWith('blob:')) {
      await _player.play(UrlSource(uri));
    } else {
      await _player.play(DeviceFileSource(uri));
    }
  }

  Future<void> dispose() async {
    await _player.stop();
    await _player.dispose();
    await _recorder.dispose();
  }

  Future<AudioEncoder> _selectEncoder() async {
    final List<AudioEncoder> encoders = kIsWeb
        ? [
            AudioEncoder.opus,
            AudioEncoder.wav,
          ]
        : [
            AudioEncoder.aacLc,
            AudioEncoder.opus,
            AudioEncoder.wav,
          ];

    for (final encoder in encoders) {
      try {
        final bool supported = await _recorder.isEncoderSupported(encoder);

        if (supported) {
          return encoder;
        }
      } catch (_) {
        debugPrint(
          '\n###>>> AudioRecorderService: Check Failed for Encoder: $encoder\n',
        );
        continue;
      }
    }
    return AudioEncoder.wav;
  }

  String _fileTypeFor(AudioEncoder encoder) {
    switch (encoder) {
      case AudioEncoder.aacLc:
      case AudioEncoder.aacEld:
      case AudioEncoder.aacHe:
        return 'm4a';
      case AudioEncoder.flac:
        return 'flac';
      case AudioEncoder.opus:
        return 'webm';
      case AudioEncoder.wav:
      case AudioEncoder.pcm16bits:
        return 'wav';
      default:
        return 'm4a';
    }
  }

  Future<String> _buildOutputPath(AudioEncoder encoder) async {
    final int timestamp = DateTime.now().millisecondsSinceEpoch;
    final String fileType = _fileTypeFor(encoder);
    final String filename = 'recording_$timestamp.$fileType';

    if (kIsWeb) {
      return filename;
    }

    final Directory directory = await getTemporaryDirectory();

    return p.join(directory.path, filename);
  }
}
