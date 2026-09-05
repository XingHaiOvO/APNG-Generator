/// CRC32（与 zlib / PNG 规范一致，多项式 0xEDB88320）。
///
/// 与 ApngGenerator.cpp 中的查表法实现逐位一致。
library;

const int _polynomial = 0xEDB88320;

final List<int> _table = _buildTable();

List<int> _buildTable() {
  final table = List<int>.filled(256, 0);
  for (var i = 0; i < 256; i++) {
    var c = i;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? (_polynomial ^ (c >>> 1)) : (c >>> 1);
    }
    table[i] = c;
  }
  return table;
}

/// 计算 [data] 从 [start] 到 [end]（不含）区间的 CRC32。
int crc32(List<int> data, [int start = 0, int? end]) {
  end ??= data.length;
  var crc = 0xFFFFFFFF;
  for (var i = start; i < end; i++) {
    crc = _table[(crc ^ data[i]) & 0xFF] ^ (crc >>> 8);
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
