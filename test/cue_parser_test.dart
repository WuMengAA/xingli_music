import 'package:flutter_test/flutter_test.dart';
import 'package:xingli_music/services/cue/cue_parser.dart';

void main() {
  group('parseCue', () {
    test('解析三段式整轨：FILE + 三 TRACK + INDEX', () {
      const String src = '''
REM GENRE "Classical"
REM DATE 1998
PERFORMER "卡拉扬"
TITLE "贝多芬第九交响曲"
FILE "beethoven.flac" WAVE
  TRACK 01 AUDIO
    TITLE "第一乐章"
    PERFORMER "卡拉扬与柏林爱乐"
    INDEX 01 00:00:00
  TRACK 02 AUDIO
    TITLE "第二乐章"
    INDEX 00 12:01:00
    INDEX 01 12:10:25
  TRACK 03 AUDIO
    TITLE "第三乐章"
    INDEX 01 22:45:50
''';
      final CueSheet? sheet = parseCue(src);
      expect(sheet, isNotNull);
      expect(sheet!.files, ['beethoven.flac']);
      expect(sheet.tracks.length, 3);

      final CueTrack t1 = sheet.tracks[0];
      expect(t1.number, 1);
      expect(t1.title, '第一乐章');
      expect(t1.performer, '卡拉扬与柏林爱乐');
      expect(t1.startMs, 0);

      final CueTrack t2 = sheet.tracks[1];
      expect(t2.title, '第二乐章');
      expect(t2.pregap, isNotNull);
      // 12:10:25 → (12*60+10)*1000 + 25*1000/75
      expect(
        t2.startMs,
        (12 * 60 + 10) * 1000 + (25 * 1000 / 75).round(),
      );

      // withEnds：t1.end = t2.start，t3.end 未知
      final int t2Start = (12 * 60 + 10) * 1000 + (25 * 1000 / 75).round();
      expect(t1.endMs, t2Start);
      expect(t2.endMs, (22 * 60 + 45) * 1000 + (50 * 1000 / 75).round());
      expect(sheet.tracks[2].endMs, isNull);
    });

    test('轨级缺省回退专辑级 PERFORMER/TITLE', () {
      const String src = '''
PERFORMER "乐队A"
TITLE "专辑B"
FILE "x.mp3" MP3
  TRACK 01 AUDIO
    INDEX 01 00:00:00
''';
      final CueSheet? sheet = parseCue(src);
      expect(sheet, isNotNull);
      expect(sheet!.tracks.first.performer, '乐队A');
      expect(sheet.tracks.first.title, '专辑B');
    });

    test('容错：REM 注释、空行、脏空白、无 quotes', () {
      const String src = '''
REM COMMENT junk
FILE "a.wav" WAVE
TRACK 01 AUDIO
TITLE SomeTitle
INDEX 01 00:02:00
INDEX 02 00:05:00
''';
      final CueSheet? sheet = parseCue(src);
      expect(sheet, isNotNull);
      // 无引号的 TITLE 不解析（防误读），回退专辑名为空不影响结构
      expect(sheet!.tracks.first.title, '');
      expect(sheet.tracks.first.performer, '');
      // INDEX 02 被忽略，start 仍是 INDEX 01
      expect(sheet.tracks.first.startMs, 2000);
    });

    test('空输入返回 null；无 TRACK 返回 null', () {
      expect(parseCue('  \n  '), isNull);
      expect(parseCue('TITLE "只有专辑"'), isNull);
    });

    test('多 FILE（多盘）各自归属首个文件', () {
      const String src = '''
FILE "disc1.flac" WAVE
  TRACK 01 AUDIO
    TITLE "盘一首"
    INDEX 01 00:00:00
  TRACK 02 AUDIO
    TITLE "盘二首"
    INDEX 01 00:10:00
FILE "disc2.flac" WAVE
  TRACK 03 AUDIO
    TITLE "盘二首之二"
    INDEX 01 00:00:00
''';
      final CueSheet? sheet = parseCue(src);
      expect(sheet, isNotNull);
      expect(sheet!.files, ['disc1.flac', 'disc2.flac']);
      // 简化归属：FILE 归属按首个文件
      expect(sheet.tracks[0].file, 'disc1.flac');
      expect(sheet.tracks[2].file, 'disc1.flac');
    });
  });
}