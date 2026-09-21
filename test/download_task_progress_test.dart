import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/service/download/download_task_progress.dart';

void main() {
  test('converts completed counts to one-based display positions', () {
    expect(downloadTaskDisplayPosition(completed: 0, total: 4), 1);
    expect(downloadTaskDisplayPosition(completed: 3, total: 4), 4);
    expect(downloadTaskDisplayPosition(completed: 4, total: 4), 4);
  });

  test('uses completed chapters and current chapter progress', () {
    expect(
      downloadTaskProgressFraction(
        completedChapters: 2,
        totalChapters: 4,
        currentChapterCompletedImages: 5,
        currentChapterTotalImages: 10,
      ),
      0.625,
    );
  });

  test('returns no progress before the chapter count is known', () {
    expect(
      downloadTaskProgressFraction(
        completedChapters: 0,
        totalChapters: 0,
        currentChapterCompletedImages: 0,
        currentChapterTotalImages: 0,
      ),
      isNull,
    );
  });
}
