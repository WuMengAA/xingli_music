import 'package:flutter_test/flutter_test.dart';
import 'package:xingli_music/providers/tools/calendar_provider.dart';

void main() {
  group('农历转换（标准锚点验证）', () {
    test('2024-02-10 = 甲辰年正月初一（春节）', () {
      final LunarDate l = solarToLunar(DateTime(2024, 2, 10));
      expect(l.year, 2024);
      expect(l.month, 1);
      expect(l.day, 1);
      expect(l.monthName, '正月');
      expect(l.dayName, '初一');
      expect(l.zodiac, '龙');
      expect(l.festivalName, '春节');
      expect(l.isFestival, true);
    });

    test('2025-01-29 = 乙巳年正月初一', () {
      final LunarDate l = solarToLunar(DateTime(2025, 1, 29));
      expect(l.year, 2025);
      expect(l.month, 1);
      expect(l.day, 1);
      expect(l.zodiac, '蛇');
    });

    test('2026-02-17 = 丙午年正月初一（马年）', () {
      final LunarDate l = solarToLunar(DateTime(2026, 2, 17));
      expect(l.year, 2026);
      expect(l.month, 1);
      expect(l.day, 1);
      expect(l.zodiac, '马');
      expect(l.yearName, '丙午');
    });

    test('2023-01-22 = 癸卯年正月初一（兔年）', () {
      final LunarDate l = solarToLunar(DateTime(2023, 1, 22));
      expect(l.year, 2023);
      expect(l.month, 1);
      expect(l.day, 1);
      expect(l.zodiac, '兔');
    });

    test('2024 中秋节 = 农历八月十五', () {
      // 2024-09-17 是农历八月十五。
      final LunarDate l = solarToLunar(DateTime(2024, 9, 17));
      expect(l.month, 8);
      expect(l.day, 15);
      expect(l.festivalName, '中秋节');
    });

    test('2026-09-03 应为农历七月廿二（today 锚点）', () {
      final LunarDate l = solarToLunar(DateTime(2026, 9, 3));
      expect(l.year, 2026);
      expect(l.month, 7);
      expect(l.day, 22);
      expect(l.monthName, '七月');
    });
  });
}
