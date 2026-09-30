import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Globally unique IDs so records can later be merged across devices.
String newId() => _uuid.v4();
