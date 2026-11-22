import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/document_model.dart';
import '../../models/person.dart';
import '../database/database_service.dart';
import '../services/folder_sync_service.dart';

final selectedFolderProvider = FutureProvider<String?>((ref) async {
  return await FolderSyncService.getSelectedFolderPath();
});

final personsProvider = FutureProvider<List<Person>>((ref) async {
  return await DatabaseService.instance.getAllPersons();
});

final selectedPersonIdProvider = StateProvider<String?>((ref) => null);

final documentsProvider = FutureProvider<List<DocumentModel>>((ref) async {
  final selectedPersonId = ref.watch(selectedPersonIdProvider);
  final db = DatabaseService.instance;
  if (selectedPersonId == null) {
    return await db.getAllDocuments();
  } else {
    return await db.getDocumentsForPerson(selectedPersonId);
  }
});

final expiringDocumentsProvider = FutureProvider<List<DocumentModel>>((ref) async {
  return await DatabaseService.instance.getExpiringDocuments(daysAhead: 90);
});

class SyncStateNotifier extends StateNotifier<SyncProgress?> {
  SyncStateNotifier() : super(null);

  void setProgress(SyncProgress progress) {
    state = progress;
  }

  void reset() {
    state = null;
  }
}

final syncProgressProvider = StateNotifierProvider<SyncStateNotifier, SyncProgress?>((ref) {
  return SyncStateNotifier();
});
