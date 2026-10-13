{{flutter_js}}
{{flutter_build_config}}

// Register only our versioned offline worker from index.html.
// Flutter's generated unregistering worker must not compete for this scope.
_flutter.loader.load();
