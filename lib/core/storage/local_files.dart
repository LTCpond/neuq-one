import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

Future<bool> saveTextFile(String filename, String contents) async =>
    await FilePicker.saveFile(
      dialogTitle: '保存文件',
      fileName: filename,
      mimeType: filename.endsWith('.ics')
          ? 'text/calendar'
          : 'application/json',
      bytes: Uint8List.fromList(utf8.encode(contents)),
    ) !=
    null;
