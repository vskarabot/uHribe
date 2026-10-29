// The list of summits hikers actually go to, used only to decide which OSM
// peaks to keep. Read from hribi.net's mountain lists for Slovenia's ten
// mountain groups; nothing from it is stored, the peaks themselves are OSM.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

typedef ReferencePeak = ({List<String> names, int? elevation});

const _baseUrl = 'https://www.hribi.net';
const _requestDelay = Duration(seconds: 1);
const _retryDelays = [Duration(seconds: 5), Duration(seconds: 15), Duration(seconds: 45)];

const _groups = [
  '/gorovje/gorisko_notranjsko_in_sneznisko_hribovje/26',
  '/gorovje/julijske_alpe/1',
  '/gorovje/kamnisko_savinjske_alpe/3',
  '/gorovje/karavanke/11',
  '/gorovje/pohorje_dravinjske_gorice_in_haloze/4',
  '/gorovje/polhograjsko_hribovje_in_ljubljana/5',
  '/gorovje/posavsko_hribovje_in_dolenjska/25',
  '/gorovje/prekmurje/163',
  '/gorovje/skofjelosko_cerkljansko_hribovje_in_jelovica/21',
  '/gorovje/strojna_kosenjak_kozjak_in_slovenske_gorice/162',
];

final _listRow = RegExp(
    r'<a href="/gora/[^"]+/(\d+)">([^<]+)</a></td><td[^>]*><a href="[^"]+">([^<]*)</a>');

final _http = http.Client();

Future<List<ReferencePeak>> fetchReferencePeaks() async {
  final entries = <String, ReferencePeak>{};
  for (final group in _groups) {
    final html = await _get(group);
    for (final m in _listRow.allMatches(html)) {
      entries.putIfAbsent(m[1]!, () => (
            names: _decodeEntities(m[2]!).split('/').map((n) => n.trim()).where((n) => n.isNotEmpty).toList(),
            elevation: int.tryParse(m[3]!.replaceAll(RegExp(r'[^0-9]'), '')),
          ));
    }
  }
  return entries.values.toList();
}

Future<String> _get(String path) async {
  for (var attempt = 0;; attempt++) {
    await Future<void>.delayed(_requestDelay);
    try {
      final response = await _http
          .get(Uri.parse('$_baseUrl$path'), headers: {'User-Agent': 'uhribe-import/1.0'})
          .timeout(const Duration(seconds: 60));
      if (response.statusCode == 200) return utf8.decode(response.bodyBytes, allowMalformed: true);
      if (attempt >= _retryDelays.length) {
        throw Exception('$path: HTTP ${response.statusCode}');
      }
    } on Exception catch (e) {
      if (attempt >= _retryDelays.length) rethrow;
      stderr.writeln('  $path: $e');
    }
    await Future<void>.delayed(_retryDelays[attempt]);
  }
}

String _decodeEntities(String s) => s
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAllMapped(RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m[1]!)))
    .replaceAll('&amp;', '&');
