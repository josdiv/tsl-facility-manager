import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

enum PhotoSource { camera, gallery }

/// Picking and storing photos, behind an interface so tests never open the
/// camera.
///
/// A photo is known by one string: a local file path (starting with `/`)
/// until it's uploaded, then its Cloud Storage path.
abstract interface class PhotoService {
  /// Whether picking asks camera or gallery. Sample mode adds a placeholder
  /// straight away instead.
  bool get asksForSource;

  /// Up to [max] new photos, as local file paths.
  Future<List<String>> pick(PhotoSource source, {required int max});

  /// Uploads [localPath] to [storagePath] and returns [storagePath].
  Future<String> upload(String localPath, String storagePath);

  /// A link to show a stored photo, or null when it can't be shown.
  Future<String?> downloadUrl(String storagePath);
}

bool isLocalPhoto(String photo) => photo.startsWith('/');

bool isStoredPhoto(String photo) => !isLocalPhoto(photo) && photo.contains('/');

/// The file name, for labels.
String photoName(String photo) => photo.split('/').last;

/// The phone's camera and gallery, and Cloud Storage.
class FirebasePhotoService implements PhotoService {
  FirebasePhotoService({ImagePicker? picker, FirebaseStorage? storage})
    : _picker = picker ?? ImagePicker(),
      _storage = storage ?? FirebaseStorage.instance;

  final ImagePicker _picker;
  final FirebaseStorage _storage;
  final _urls = <String, Future<String?>>{};

  // Big enough to read a meter or a crack, small enough for mobile data.
  static const _maxWidth = 1600.0;
  static const _quality = 80;

  @override
  bool get asksForSource => true;

  @override
  Future<List<String>> pick(PhotoSource source, {required int max}) async {
    if (max <= 0) return const [];
    if (source == PhotoSource.camera) {
      final photo = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: _maxWidth,
        imageQuality: _quality,
      );
      return [?photo?.path];
    }
    final photos = max == 1
        ? [
            ?await _picker.pickImage(
              source: ImageSource.gallery,
              maxWidth: _maxWidth,
              imageQuality: _quality,
            ),
          ]
        : await _picker.pickMultiImage(
            maxWidth: _maxWidth,
            imageQuality: _quality,
            limit: max,
          );
    return [for (final photo in photos.take(max)) photo.path];
  }

  @override
  Future<String> upload(String localPath, String storagePath) async {
    final extension = localPath.split('.').last.toLowerCase();
    await _storage
        .ref(storagePath)
        .putFile(
          File(localPath),
          SettableMetadata(
            contentType: switch (extension) {
              'png' => 'image/png',
              'webp' => 'image/webp',
              'heic' => 'image/heic',
              'heif' => 'image/heif',
              _ => 'image/jpeg',
            },
          ),
        );
    return storagePath;
  }

  @override
  Future<String?> downloadUrl(String storagePath) =>
      _urls.putIfAbsent(storagePath, () async {
        try {
          return await _storage.ref(storagePath).getDownloadURL();
        } on FirebaseException {
          _urls.remove(storagePath); // Try again next time.
          return null;
        }
      });
}

/// Sample mode: placeholder names instead of real photos.
class SamplePhotoService implements PhotoService {
  var _count = 0;

  @override
  bool get asksForSource => false;

  @override
  Future<List<String>> pick(PhotoSource source, {required int max}) async =>
      max <= 0 ? const [] : ['Photo-${++_count}.jpg'];

  @override
  Future<String> upload(String localPath, String storagePath) async =>
      storagePath;

  @override
  Future<String?> downloadUrl(String storagePath) async => null;
}
