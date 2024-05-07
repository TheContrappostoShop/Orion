// Directory class
import 'package:orion/api_services/api_services.dart';
import 'package:orion/util/orion_api_filesystem/orion_api_item.dart';
import 'package:path/path.dart' as path;

class OrionApiDirectory implements OrionApiItem {
  @override
  final String path;
  final String name;
  final int lastModified;
  final String locationCategory;
  @override
  final String parentPath;

  OrionApiDirectory({
    required this.path,
    required this.name,
    required this.lastModified,
    required this.locationCategory,
    required this.parentPath,
  });

  factory OrionApiDirectory.fromJson(Map<String, dynamic> json) {
    return OrionApiDirectory(
      path: json['path'],
      name: json['name'],
      lastModified: json['last_modified'],
      locationCategory: json['location_category'],
      parentPath: json['parent_path'],
    );
  }
}

// _getDirs method
Future<List<OrionApiDirectory>> _getDirs(
    String directory, String defaultDirectory) async {
  try {
    String subdirectory = path.relative(directory, from: defaultDirectory);

    final response =
        await ApiService.listItems('uploads', 100, 0, subdirectory);

    final List<OrionApiDirectory> dirs = (response['dirs'] as List)
        .where((item) => item != null)
        .map<OrionApiDirectory>((item) {
      OrionApiDirectory dir = OrionApiDirectory.fromJson(item);
      return dir;
    }).toList();

    return dirs;
  } catch (e) {
    return [];
  }
}
