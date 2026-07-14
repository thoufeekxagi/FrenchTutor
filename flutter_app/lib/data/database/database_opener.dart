export 'database_opener_unsupported.dart'
    if (dart.library.js) 'database_opener_web.dart'
    if (dart.library.ffi) 'database_opener_native.dart';
