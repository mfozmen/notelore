/// Opening a link a note or an answer shows.
library;

import 'package:url_launcher/url_launcher.dart';

/// Opens [href] in the browser when it is a web address; anything else
/// (`javascript:`, a missing target) opens nothing.
void openWebLink(String? href) {
  final uri = Uri.tryParse(href ?? '');
  if (uri != null && uri.hasAuthority && (uri.scheme == 'http' || uri.scheme == 'https')) {
    launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
