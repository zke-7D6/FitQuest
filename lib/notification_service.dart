import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// Conditional import — loads mobile or web version automatically
export 'notification_service_mobile.dart'
    if (dart.library.html) 'notification_service_web.dart';
