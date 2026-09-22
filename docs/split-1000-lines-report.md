# 千行文件拆分 · 现状报告

基线提交 `35a6be81`（开工时 HEAD）；「上游」列取 `upstream/main`。
`对上游 +/−` 的 **−** 就是「动了上游自己的行」的行数 —— 拆前与现在的 − 必须相等。


=== B 类：上游已有、本仓在文件内加长（只许搬本仓自己的行） ===
文件                                                          上游    开工    现在   达标  对上游 +/− 开工→现在           
---------------------------------------------------------------------------------------------------------
lib/config/global/global_setting.dart                      469  1331   891    ✓  +870/−8 → +430/−8       
lib/page/comic_read/widgets/settings/reader_settings_read_tab.dart   538  1140   757    ✓  +962/−360 → +588/−369   
lib/network/sync/sync_service.dart                        1491  1890  1581    ✗  +427/−28 → +120/−30     
lib/page/setting/real_sr/service/real_sr_super_resolution.dart  1004  1204  1204    ✗  +369/−169 → +369/−169   
lib/page/comic_info/view/comic_info.dart                  1237  1355  1321    ✗  +208/−90 → +174/−90     
lib/main.dart                                              875  1066   968    ✓  +208/−17 → +110/−17     
lib/page/comic_info/models/collect_comic.dart              956  1093   961    ✓  +137/−0 → +5/−0         
lib/page/comic_read/cubit/reader_seamless_cubit.dart      1323  1345  1345    ✗  +50/−28 → +50/−28       

未达标 4 个：
  lib/network/sync/sync_service.dart  现在 1581 行
  lib/page/setting/real_sr/service/real_sr_super_resolution.dart  现在 1204 行
  lib/page/comic_info/view/comic_info.dart  现在 1321 行
  lib/page/comic_read/cubit/reader_seamless_cubit.dart  现在 1345 行

=== C 类：本仓全新文件（整体模块化） ===
文件                                                          上游    开工    现在   达标  对上游 +/− 开工→现在           
---------------------------------------------------------------------------------------------------------
lib/workspace/widgets/cards/file_manager_card.dart          -1  2764   469    ✓  （本仓新增）                  
rust/local_core/src/file_manager.rs                         -1  2727    33    ✓  （本仓新增）                  
rust/local_core/src/catalog.rs                              -1  1872   300    ✓  （本仓新增）                  
rust/local_core/src/folder_tree.rs                          -1  1633  1633    ✗  （本仓新增）                  
rust/local_core/src/file_ops/execute.rs                     -1  1596   867    ✓  （本仓新增）                  
rust/local_core/src/folder_pane.rs                          -1  1198  1198    ✗  （本仓新增）                  
rust/local_core/src/operation_binding/radial.rs             -1  1171   405    ✓  （本仓新增）                  
rust/local_core/src/page_load_scheduler.rs                  -1  1013   631    ✓  （本仓新增）                  
rust/gpu_present/src/presenter.rs                           -1  2139   881    ✓  （本仓新增）                  
rust/gpu_present/src/mac_presenter.rs                       -1  2074   857    ✓  （本仓新增）                  
rust/gpu_present/src/lib.rs                                 -1  1007    83    ✓  （本仓新增）                  
rust/gpu_present/src/wgpu_resampler.rs                      -1  1088   769    ✓  （本仓新增）                  
rust/src/api/file_manager.rs                                -1  1710   735    ✓  （本仓新增）                  
lib/debug/local_source_debug_page.dart                      -1  1957   299    ✓  （本仓新增）                  
lib/reader/gpu_present_controller.dart                      -1  1477  1072    ✗  （本仓新增）                  
lib/video/view/video_control_overlay.dart                   -1  1458   668    ✓  （本仓新增）                  
lib/page/setting/global/workspace_layout_setting_page.dart    -1  1104   399    ✓  （本仓新增）                  
lib/page/setting/real_sr/widgets/upscale_conditions_card.dart    -1  1026   322    ✓  （本仓新增）                  
web/rossi_webgpu/rossi_gpu_present.js                       -1  1354  1354    ✗  （本仓新增）                  
windows/runner/gpu_present_bridge.cpp                       -1  1092  1092    ✗  （本仓新增）                  
test/workspace/file_manager_card_test.dart                  -1  1413  1065    ✗  （本仓新增）                  
test/video/video_playback_logic_test.dart                   -1  1169   997    ✓  （本仓新增）                  
test/video/mpv_property_probe_test.dart                     -1  1081   661    ✓  （本仓新增）                  

未达标 6 个：
  rust/local_core/src/folder_tree.rs  现在 1633 行
  rust/local_core/src/folder_pane.rs  现在 1198 行
  lib/reader/gpu_present_controller.dart  现在 1072 行
  web/rossi_webgpu/rossi_gpu_present.js  现在 1354 行
  windows/runner/gpu_present_bridge.cpp  现在 1092 行
  test/workspace/file_manager_card_test.dart  现在 1065 行

