// A small PNG encoder for the site screenshots (#290).
//
// Flutter's own `ImageByteFormat.png` writes RGBA at the default deflate
// level. A screenshot of the window is opaque, so the alpha channel is a
// quarter of the data for nothing; dropping it, picking each row's filter
// and deflating at level 9 makes the files about a fifth smaller — and every
// refresh of the set lands in git history. Lossless: the pixels are the ones
// Flutter drew.

import 'dart:io';
import 'dart:typed_data';

/// [rgba] — straight 8-bit RGBA, [width] × [height], as
/// `ImageByteFormat.rawStraightRgba` hands it out — as a PNG file: 8-bit RGB,
/// each row with the filter that leaves the smallest sum of magnitudes (the
/// heuristic the PNG specification suggests), deflated at level 9.
Uint8List encodeOpaquePng(Uint8List rgba, int width, int height) {
  const channels = 3;
  final stride = width * channels;
  final filtered = Uint8List((stride + 1) * height);
  var prior = Uint8List(stride);
  var row = Uint8List(stride);
  final candidate = Uint8List(stride);
  final best = Uint8List(stride);
  for (var y = 0; y < height; y++) {
    for (var x = 0, s = y * width * 4, d = 0; x < width; x++) {
      row[d++] = rgba[s];
      row[d++] = rgba[s + 1];
      row[d++] = rgba[s + 2];
      s += 4;
    }
    var bestFilter = 0;
    var bestSum = -1;
    for (var filter = 0; filter < 5; filter++) {
      var sum = 0;
      for (var i = 0; i < stride; i++) {
        final left = i >= channels ? row[i - channels] : 0;
        final up = prior[i];
        final upLeft = i >= channels ? prior[i - channels] : 0;
        final predicted = switch (filter) {
          0 => 0,
          1 => left,
          2 => up,
          3 => (left + up) >> 1,
          _ => _paeth(left, up, upLeft),
        };
        final byte = (row[i] - predicted) & 0xff;
        candidate[i] = byte;
        sum += byte < 128 ? byte : 256 - byte;
        if (bestSum >= 0 && sum >= bestSum) break;
      }
      if (bestSum < 0 || sum < bestSum) {
        bestSum = sum;
        bestFilter = filter;
        best.setAll(0, candidate);
      }
    }
    final offset = y * (stride + 1);
    filtered[offset] = bestFilter;
    filtered.setRange(offset + 1, offset + 1 + stride, best);
    final swap = prior;
    prior = row;
    row = swap;
  }

  final header = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8) // bit depth
    ..setUint8(9, 2) // colour type: RGB
    ..setUint8(10, 0) // deflate
    ..setUint8(11, 0) // adaptive filtering
    ..setUint8(12, 0); // no interlace
  final out = BytesBuilder(copy: false)
    ..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  _chunk(out, 'IHDR', header.buffer.asUint8List());
  _chunk(out, 'IDAT', ZLibEncoder(level: 9).convert(filtered));
  _chunk(out, 'IEND', const []);
  return out.takeBytes();
}

int _paeth(int a, int b, int c) {
  final p = a + b - c;
  final pa = (p - a).abs();
  final pb = (p - b).abs();
  final pc = (p - c).abs();
  if (pa <= pb && pa <= pc) return a;
  if (pb <= pc) return b;
  return c;
}

void _chunk(BytesBuilder out, String type, List<int> data) {
  final typeBytes = type.codeUnits;
  out
    ..add(_uint32(data.length))
    ..add(typeBytes)
    ..add(data)
    ..add(_uint32(_crc32([...typeBytes, ...data])));
}

Uint8List _uint32(int value) =>
    (ByteData(4)..setUint32(0, value)).buffer.asUint8List();

final List<int> _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final b in bytes) {
    crc = _crcTable[(crc ^ b) & 0xff] ^ (crc >> 8);
  }
  return crc ^ 0xFFFFFFFF;
}
