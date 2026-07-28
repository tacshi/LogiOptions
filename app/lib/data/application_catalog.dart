import 'package:flutter/services.dart';

class InstalledApplication {
  const InstalledApplication({
    required this.bundleId,
    required this.name,
    required this.path,
    this.icon,
  });

  factory InstalledApplication.fromMap(Map<dynamic, dynamic> map) =>
      InstalledApplication(
        bundleId: map['bundleId']?.toString() ?? '',
        name: map['name']?.toString() ?? 'Application',
        path: map['path']?.toString() ?? '',
        icon: map['icon'] as Uint8List?,
      );

  final String bundleId;
  final String name;
  final String path;
  final Uint8List? icon;
}

class ApplicationCatalog {
  const ApplicationCatalog();

  static const _channel = MethodChannel('com.logioptions/applications');

  Future<List<InstalledApplication>> listInstalled() async {
    final response =
        await _channel.invokeListMethod<dynamic>('listInstalled') ?? const [];
    return response
        .whereType<Map>()
        .map(InstalledApplication.fromMap)
        .where((application) => application.bundleId.isNotEmpty)
        .toList();
  }

  Future<InstalledApplication?> browse() async {
    final response = await _channel.invokeMapMethod<dynamic, dynamic>('browse');
    return response == null ? null : InstalledApplication.fromMap(response);
  }

  Future<String?> browseFile() => _channel.invokeMethod<String>('browseFile');
}
