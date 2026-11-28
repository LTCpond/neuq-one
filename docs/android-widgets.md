# Android 桌面小组件

「我的 → 桌面小组件」提供预览。要添加组件，请长按 Android 桌面空白处，从小组件列表选择 NEUQ One。添加后可长按调整尺寸。

| 组件 | 尺寸 | 操作 |
| --- | --- | --- |
| 今日课表 | 2×2、4×2 | 课程和考试按开始时间排序。点击课程查看详情，点击考试查看详情或冲突。超出可见行时从列表内部滑动。 |
| 周课表 | 4×5、4×6 | 箭头切换教学周，点击教学周标题回到当前周。点击日期查看当天完整日程，日期后带圆点表示有补充考试时段。 |
| 考试安排与倒计时 | 2×1、2×2、4×2 | 点击考试查看详情或冲突。空状态可以直接打开添加考试，4×2 宽版列表可滑动。 |

七种尺寸使用 Android 15 模拟器的原生 RemoteViews 渲染。预览数据均来自测试。[浅色预览](assets/android-widgets-light.png) · [深色预览](assets/android-widgets-dark.png) · [今日课表状态预览](assets/android-widgets-today-states.png)

## 实现与维护

- Dart 入口位于 `lib/features/desktop_widgets/`。账号、课表、考试、课程颜色及显示设置变化时，桥接层发布当前本地数据。考试开始和结束使用 UTC 时间戳，按北京时间绘制。考试冲突和周课表的覆盖区域由 Flutter 统一计算。
- 原生代码位于 `android/app/src/main/kotlin/org/neuqone/neuq_one/widgets/`。第 1 版快照存放在 Android 应用的 `noBackupFilesDir`，由 `AtomicFile` 提交。写入按课表和考试分段校验，旧版桌面快照内的余额字段在读取时原子清除。读写、账号切换和桌面刷新由同一个执行队列排序。续启 Flutter 身份恢复期间隐藏已有快照。相同账号确认后恢复快照，换账号或退出时丢弃旧数据。桌面在确认后可以独立于 Flutter 进程读取快照。
- Android 12 起读取桌面提供的响应式宽高，较旧 Android 通过横竖屏宽高上下界选择布局。尺寸选择依赖实际 dp，周课表空间不足时提示拉高。周课表七列和十二节用 RemoteViews 子布局，跨节色块在原生视图中保留点击和无障碍描述。浅深色跟随系统。
- 今日课表和宽版考试根据实际高度分配完整行。内容溢出时使用系统 ListView。起始位置按完整行计算，拖动后的停靠位置由系统和桌面决定。App 里的预览使用同一组 RemoteViews 布局和本地数据，预览图展示静止首屏。
- 今日课表用课程底色和朱砂红渲染左侧竖线。被考试完全覆盖的课程可从考试的冲突详情查看。待同步、今日无课、今日日程已结束各有独立状态，已知考试可在首次课表同步前显示。
- 周课表沿用十二节和七列，优先绘制考试占用的实际区域。较短或节次外的考试可通过相应日期查看。课表显示开关同时影响今日课表和周课表，独立考试组件继续展示倒计时及冲突。
- 安装、移除、拉伸、进程配置变化、系统时间变化、设备启动和安装包替换均会重新检查组件。非精确闹钟由当天最后一项日程的结束时间、考试起止时间或北京时间午夜驱动，移除最后一个组件后取消闹钟。休眠、强行停止和系统调度可推迟更新，打开 App 后恢复。

## 开发检查

```sh
dart format lib test
flutter analyze
flutter test
flutter build apk --debug
```

在 `android/` 运行 `gradlew.bat :app:assembleDebugAndroidTest`。在测试设备安装调试主 APK 与测试 APK 后运行以下命令。原生测试使用虚构课程、考试和用于迁移测试的旧快照，覆盖快照、账号隔离、尺寸、考试边界、任务取消和原生浅深渲染。截图生成在调试包的 `files/widget-test-previews/`。开启可选的 `-e host true` 前，请使用无真实小组件数据的测试安装，并为测试包对应的宿主授予小组件绑定权限。

```sh
adb shell am instrument -w org.neuqone.neuq_one.debug.test/org.neuqone.neuq_one.widgets.WidgetInstrumentation
```

Android 15 模拟器已通过标准小组件宿主绑定、列表数据及失效检查和两种主题渲染。HyperOS、OriginOS、ColorOS 及标准 Android 真机桌面仍需核对七种尺寸。优先观察长课程名和大字体、滚动初始完整行和停止位置、教学周箭头、课程和考试点击、两种方向的拉伸、深色切换、进程重建及设备重启后的恢复，以及退出后组件是否已清空。

## 文件清单

<details>
<summary>查看本次新增和修改的文件</summary>

### 修改

- `README.md`
- `android/app/build.gradle.kts`
- `android/app/src/main/AndroidManifest.xml`
- `android/app/src/main/kotlin/org/neuqone/neuq_one/MainActivity.kt`
- `docs/architecture.md`
- `lib/app/app.dart`
- `lib/app/router.dart`
- `lib/features/grades/presentation/academic_page.dart`
- `lib/features/profile/presentation/profile_page.dart`
- `lib/features/timetable/data/local_timetable.dart`
- `lib/features/timetable/presentation/timetable_page.dart`
- `lib/features/timetable/presentation/timetable_palette.dart`
- `lib/features/timetable/presentation/week_timetable.dart`

### 新增

- `android/app/src/androidTest/kotlin/org/neuqone/neuq_one/widgets/WidgetInstrumentation.kt`
- `android/app/src/main/kotlin/org/neuqone/neuq_one/widgets/WidgetDataBridge.kt`
- `android/app/src/main/kotlin/org/neuqone/neuq_one/widgets/WidgetNavigation.kt`
- `android/app/src/main/kotlin/org/neuqone/neuq_one/widgets/WidgetRenderer.kt`
- `android/app/src/main/kotlin/org/neuqone/neuq_one/widgets/WidgetSizePolicy.kt`
- `android/app/src/main/kotlin/org/neuqone/neuq_one/widgets/WidgetSnapshotStore.kt`
- `android/app/src/main/kotlin/org/neuqone/neuq_one/widgets/WidgetUpdateManager.kt`
- `android/app/src/main/res/drawable-v31/widget_surface.xml`
- `android/app/src/main/res/drawable/widget_calendar.xml`
- `android/app/src/main/res/drawable/widget_chevron_left.xml`
- `android/app/src/main/res/drawable/widget_chevron_right.xml`
- `android/app/src/main/res/drawable/widget_course_surface.xml`
- `android/app/src/main/res/drawable/widget_date_badge.xml`
- `android/app/src/main/res/drawable/widget_day_done.xml`
- `android/app/src/main/res/drawable/widget_day_free.xml`
- `android/app/src/main/res/drawable/widget_grid_stroke.xml`
- `android/app/src/main/res/drawable/widget_pill.xml`
- `android/app/src/main/res/drawable/widget_surface.xml`
- `android/app/src/main/res/layout/widget_course_small.xml`
- `android/app/src/main/res/layout/widget_course_wide.xml`
- `android/app/src/main/res/layout/widget_exam_empty.xml`
- `android/app/src/main/res/layout/widget_exam_small.xml`
- `android/app/src/main/res/layout/widget_exam_square.xml`
- `android/app/src/main/res/layout/widget_exam_wide.xml`
- `android/app/src/main/res/layout/widget_exams_list.xml`
- `android/app/src/main/res/layout/widget_today_list.xml`
- `android/app/src/main/res/layout/widget_week.xml`
- `android/app/src/main/res/layout/widget_week_cell.xml`
- `android/app/src/main/res/layout/widget_week_column.xml`
- `android/app/src/main/res/layout/widget_week_course.xml`
- `android/app/src/main/res/layout/widget_week_day.xml`
- `android/app/src/main/res/layout/widget_week_month.xml`
- `android/app/src/main/res/layout/widget_week_period.xml`
- `android/app/src/main/res/layout/widget_week_periods.xml`
- `android/app/src/main/res/values-night/widget_colors.xml`
- `android/app/src/main/res/values/widget_colors.xml`
- `android/app/src/main/res/values/widget_exams_strings.xml`
- `android/app/src/main/res/values/widget_today_strings.xml`
- `android/app/src/main/res/values/widget_week_strings.xml`
- `android/app/src/main/res/xml/widget_exams_info.xml`
- `android/app/src/main/res/xml/widget_today_info.xml`
- `android/app/src/main/res/xml/widget_week_info.xml`
- `docs/android-widgets.md`
- `docs/assets/android-widgets-dark.png`
- `docs/assets/android-widgets-light.png`
- `docs/assets/android-widgets-today-states.png`
- `lib/features/desktop_widgets/data/desktop_widget_bridge.dart`
- `lib/features/desktop_widgets/presentation/desktop_widgets_page.dart`
- `lib/features/timetable/domain/course_period_span.dart`
- `test/desktop_widgets/desktop_widget_bridge_test.dart`

</details>
