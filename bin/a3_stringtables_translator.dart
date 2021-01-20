import 'dart:io';
import 'package:googleapis/translate/v3.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:args/args.dart';
import 'package:xml/xml.dart';

class _TranslationNode {
  final XmlElement key;
  final String text;
  String translated;

  _TranslationNode(this.key, this.text);
}

class _TranslationTable {
  final List<_TranslationNode> nodes;
  final XmlDocument doc;
  final String srcLang;
  final String dstLang;

  _TranslationTable(this.nodes, this.doc, this.srcLang, this.dstLang);
}

Future<void> main(List<String> args) async {
  final argParser = ArgParser();
  argParser.addOption('file', abbr: 'f', defaultsTo: 'Stringtable.xml');
  argParser.addOption('srclang', abbr: 's', defaultsTo: 'Original');
  argParser.addOption('dstlang', abbr: 'd', defaultsTo: 'Russian');
  argParser.addOption('srclangcode', abbr: 'c', defaultsTo: 'en-US');
  argParser.addOption('dstlangcode', abbr: 't', defaultsTo: 'ru-RU');
  argParser.addOption('out', abbr: 'o', defaultsTo: 'Stringtable_Out.xml');
  argParser.addOption('auth', abbr: 'a', defaultsTo: '.auth.json');
  argParser.addOption('project', abbr: 'p', defaultsTo: '.project.txt');
  final params = argParser.parse(args);

  final tab =
      await _loadXmlTable(params['file'], params['srclang'], params['dstlang']);
  await _translateTable(tab, params['auth'], params['project'],
      params['srclangcode'], params['dstlangcode']);
  await _updateXmlTableAndSave(tab, params['out']);

  print('INFO: Done');
}

Future<void> _translateTable(_TranslationTable tab, String authFilePath,
    String projectFilePath, String srcLangCode, String dstLangCode) async {
  final authFile = File(authFilePath);
  if (!authFile.existsSync()) {
    print('ERROR: Authorization file not found ($authFilePath)!');
    exit(1);
  }

  final authString = await authFile.readAsString();

  final projectFile = File(projectFilePath);
  if (!authFile.existsSync()) {
    print('ERROR: Project file not found ($projectFilePath)!');
    exit(1);
  }

  final projectString = await projectFile.readAsString();

  final credentials = ServiceAccountCredentials.fromJson(authString);

  final httpClient = await clientViaServiceAccount(
      credentials, [TranslateApi.CloudTranslationScope]);

  final translReq = TranslateTextRequest();
  translReq.sourceLanguageCode = srcLangCode;
  translReq.targetLanguageCode = dstLangCode;
  translReq.contents = [];
  var totalSrcLen = 0;
  for (var k in tab.nodes) {
    totalSrcLen += k.text.length;
    translReq.contents.add(k.text);
  }

  final api = TranslateApi(httpClient);

  final translRes = await api.projects.translateText(translReq, projectString);
  final translations = translRes.translations;

  if (translations.length != tab.nodes.length) {
    print('Count of translated entrys not equal to orignal count');
  }

  var totalDstLen = 0;
  var i;
  for (i = 0; i < tab.nodes.length; i++) {
    final translated = translations[i].translatedText;
    tab.nodes[i].translated = translated;
    totalDstLen += translated.length;
  }

  httpClient.close();
  print('INFO: Total source symbols: $totalSrcLen');
  print('INFO: Total translated symbols: $totalDstLen');
  print('INFO: Total translated messages: $i');
}

Future<void> _updateXmlTableAndSave(
    _TranslationTable tab, String filename) async {
  for (var n in tab.nodes) {
    if (n.translated != null && n.translated.isNotEmpty) {
      final e = XmlElement(XmlName(tab.dstLang));
      final t = XmlText(n.translated);
      e.children.add(t);
      n.key.children.add(e);
    }
  }
  final xmlStr = tab.doc.toXmlString();
  final f = File(filename);
  await f.writeAsString(xmlStr);
}

Future<_TranslationTable> _loadXmlTable(
    String fileName, String srcLang, String dstLang) async {
  final tableFile = File(fileName);
  if (!tableFile.existsSync()) {
    print('ERROR: File ${fileName} not found!');
    exit(1);
  }
  final textTable = await tableFile.readAsString();
  final xmlTable = XmlDocument.parse(textTable);

  final list = <_TranslationNode>[];
  final projectNode = xmlTable.firstElementChild;
  final packageNode = projectNode.firstElementChild;

  for (var container in packageNode.children) {
    if (container is XmlElement) {
      for (var key in container.children) {
        if (key is XmlElement) {
          final t = _hasTranslatedText(key, dstLang);
          if (!t) {
            final text = _getSrcText(key, srcLang);
            if (text.isNotEmpty) {
              list.add(_TranslationNode(key, text));
            }
          }
        }
      }
    }
  }
  return _TranslationTable(list, xmlTable, srcLang, dstLang);
}

String _getSrcText(XmlElement key, String lang) {
  final langElems = key.findElements(lang);
  if (langElems.isNotEmpty) {
    final single = langElems.first;
    final textNode = single.firstChild;
    if (textNode != null && textNode is XmlText) {
      return textNode.text;
    }
  }
  return '';
}

bool _hasTranslatedText(XmlElement key, String lang) {
  final langElems = key.findElements(lang);
  return langElems.isNotEmpty;
}
