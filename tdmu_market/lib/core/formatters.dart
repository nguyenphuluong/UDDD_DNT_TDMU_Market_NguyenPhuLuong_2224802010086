String currency(dynamic value) {
  final number = (value as num?)?.round() ?? 0;
  final source = number.toString();
  final out = StringBuffer();
  for (var i = 0; i < source.length; i++) {
    if (i > 0 && (source.length - i) % 3 == 0) out.write('.');
    out.write(source[i]);
  }
  return '${out.toString()} đ';
}
