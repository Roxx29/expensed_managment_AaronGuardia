import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/utils/ids.dart';
import '../../../domain/entities/entities.dart';
import '../../../shared/providers/providers.dart';

/// Folder for profile photos. Only the file name is stored in the profile,
/// so paths survive app-container moves and restores on another device.
final avatarDirectoryProvider = FutureProvider<Directory>((ref) async {
  final base = await getApplicationDocumentsDirectory();
  return Directory('${base.path}${Platform.pathSeparator}avatars').create(recursive: true);
});

/// Only names this app generates are accepted: a restored backup could
/// otherwise point `avatarPath` at another file (e.g. `../database`).
final _avatarName = RegExp(r'^avatar_[0-9a-f]{8}\.jpg$');

File? _avatarFile(Directory dir, String? name) =>
    name != null && _avatarName.hasMatch(name) ? File('${dir.path}${Platform.pathSeparator}$name') : null;

/// The current profile photo, or null.
final avatarFileProvider = FutureProvider<File?>((ref) async {
  final name = ref.watch(profileProvider).value?.avatarPath;
  final file = _avatarFile(await ref.watch(avatarDirectoryProvider.future), name);
  return file != null && await file.exists() ? file : null;
});

final profileActionsProvider = Provider<ProfileActions>(ProfileActions.new);

class ProfileActions {
  ProfileActions(this._ref);

  final Ref _ref;

  Future<Profile> _current() => _ref.read(profileRepositoryProvider).watch().first;

  Future<void> save({required String name, String? email, String? countryCode}) async {
    final profile = await _current();
    await _ref.read(profileRepositoryProvider).save(Profile(
          id: profile.id,
          currency: profile.currency,
          avatarPath: profile.avatarPath,
          name: name.trim(),
          email: email?.trim(),
          countryCode: countryCode,
        ));
  }

  /// Changes only the name (account sync, registration); the rest is kept.
  Future<void> setName(String name) async {
    final profile = await _current();
    if (profile.name == name.trim()) return;
    await _ref.read(profileRepositoryProvider).save(Profile(
          id: profile.id,
          currency: profile.currency,
          avatarPath: profile.avatarPath,
          name: name.trim(),
          email: profile.email,
          countryCode: profile.countryCode,
        ));
  }

  /// Picks a photo from the gallery. Returns false if cancelled.
  Future<bool> pickPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (picked == null) return false;
    final dir = await _ref.read(avatarDirectoryProvider.future);
    final name = 'avatar_${newId().substring(0, 8)}.jpg';
    await File(picked.path).copy('${dir.path}${Platform.pathSeparator}$name');
    await _replaceAvatar(name);
    return true;
  }

  Future<void> removePhoto() => _replaceAvatar(null);

  Future<void> _replaceAvatar(String? newName) async {
    final profile = await _current();
    final old = profile.avatarPath;
    await _ref.read(profileRepositoryProvider).save(Profile(
          id: profile.id,
          currency: profile.currency,
          name: profile.name,
          email: profile.email,
          countryCode: profile.countryCode,
          avatarPath: newName,
        ));
    final oldFile = _avatarFile(await _ref.read(avatarDirectoryProvider.future), old);
    if (oldFile != null && await oldFile.exists()) await oldFile.delete();
  }
}

/// Countries offered in the profile (ISO 3166-1 alpha-2).
const countries = <String, String>{
  'AR': 'Argentina',
  'BR': 'Brazil',
  'CA': 'Canada',
  'CL': 'Chile',
  'CO': 'Colombia',
  'CR': 'Costa Rica',
  'DO': 'Dominican Republic',
  'EC': 'Ecuador',
  'SV': 'El Salvador',
  'FR': 'France',
  'DE': 'Germany',
  'GT': 'Guatemala',
  'HN': 'Honduras',
  'IT': 'Italy',
  'MX': 'Mexico',
  'NI': 'Nicaragua',
  'PA': 'Panama',
  'PE': 'Peru',
  'PT': 'Portugal',
  'PR': 'Puerto Rico',
  'ES': 'Spain',
  'GB': 'United Kingdom',
  'US': 'United States',
  'UY': 'Uruguay',
  'VE': 'Venezuela',
};
