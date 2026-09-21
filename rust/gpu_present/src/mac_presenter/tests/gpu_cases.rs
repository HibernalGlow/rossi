use crate::mac_presenter::*;

    #[test]
    fn test_mac_presenter_init_and_stats() {
        let presenter = MacPresenter::new(800, 600).expect("创建 MacPresenter 失败");
        let stats = presenter.stats_json();
        assert!(stats.contains("\"backend\":\"macos/metal-uma\""));
        assert!(stats.contains("\"width\":800"));
        assert!(stats.contains("\"height\":600"));
        assert!(stats.contains("\"prerenderHit\":0"));
        // 还没上屏过：字面 `null`，Dart 侧据此回落静态底色。
        // **不能**缺字段、也不能编一个黑色出来 —— 对界面来说
        // 「这一页没采到」与「采到了一个黑」是两件事。
        assert!(
            stats.contains("\"ambient\":null"),
            "未呈现时 ambient 必须是字面 null，实际: {stats}"
        );
    }

    #[test]
    fn test_wgpu_resample_letterbox() {
        let presenter = MacPresenter::new(4, 4).expect("创建 MacPresenter 失败");
        let mut r = presenter.resampler.lock().unwrap();

        // 2x1 横图放入 4x4 目标，上下留白
        let pixels = PagePixels {
            width: 2,
            height: 1,
            source_width: 2,
            source_height: 1,
            rgba: vec![
                255, 0, 0, 255, // (0,0) 红
                0, 255, 0, 255, // (1,0) 绿
            ],
        };

        let target_w = 4;
        let target_h = 4;
        let stride = target_w * 4;
        let mut buffer = vec![0u8; (target_h * stride) as usize];

        r.resample_to_buffer(
            &pixels.rgba,
            pixels.width,
            pixels.height,
            target_w,
            target_h,
            buffer.as_mut_ptr(),
            stride as usize,
            false,
        )
        .expect("GPU 重采样失败");

        let bg = [0, 0, 0, 0];
        // y=0 行是上留白
        assert_eq!(&buffer[0..4], &bg);

        // y=3 行是下留白
        let bottom_bg_offset = (3 * stride) as usize;
        assert_eq!(&buffer[bottom_bg_offset..bottom_bg_offset + 4], &bg);
    }

    #[test]
    fn test_copy_with_tolerance_diff() {
        let frame = PreRenderedFrame {
            target_w: 10,
            target_h: 10,
            bgra: Arc::new(vec![123u8; 10 * 10 * 4]),
            stride: 40,
        };

        // 模拟 1 像素微差（例如 10x10 拷入 10x9，或者 10x10 拷入 10x11）
        let target_w = 10;
        let target_h = 11;
        let stride = 40;
        let mut dst = vec![0u8; (target_h * stride) as usize];

        unsafe {
            copy_pre_rendered_frame(
                &frame,
                dst.as_mut_ptr(),
                stride as usize,
                target_w,
                target_h,
            );
        }

        // 前 10 行应当完全匹配
        assert_eq!(&dst[0..400], &frame.bgra[0..400]);
        // 第 11 行应当填充背景色
        let bg = [0, 0, 0, 0];
        assert_eq!(&dst[400..404], &bg);
    }

    /// 验证对齐 mImageViewer 原版设计的级联解析、原图对比旁路与保留集显存淘汰
    #[test]
    fn test_cascade_resolution_and_original_preview_and_keep_set() {
        let epoch = 1;
        let red_raw = Arc::new(PagePixels {
            width: 1,
            height: 1,
            source_width: 1,
            source_height: 1,
            rgba: vec![255, 0, 0, 255],
        });
        let blue_enhanced = Arc::new(PagePixels {
            width: 2,
            height: 2,
            source_width: 1,
            source_height: 1,
            rgba: vec![0, 0, 255, 255].repeat(4),
        });

        // 1. 只有原图时：级联解析必定命中原图（原图秒开保底）
        let mut page0 = CachedPage::new_raw(0, epoch, Some(red_raw.clone()));
        assert_eq!(
            page0.resolve_display_pixels(false).unwrap().rgba,
            red_raw.rgba
        );

        // 2. 超分增强图生成后：普通模式下优先命中超分图（平滑替换）
        page0.enhanced_pixels = Some(blue_enhanced.clone());
        assert_eq!(
            page0.resolve_display_pixels(false).unwrap().rgba,
            blue_enhanced.rgba
        );

        // 3. 原图对比旁路模式（bypass_enhanced = true）：瞬时绕过超分图，返回原图
        assert_eq!(
            page0.resolve_display_pixels(true).unwrap().rgba,
            red_raw.rgba
        );

        // 4. Keep-Set 显存控制测试：超出保留集的超分大图自动被淘汰，原图完好保留
        let mut page4 = CachedPage::new_raw(4, epoch, Some(red_raw.clone()));
        page4.enhanced_pixels = Some(blue_enhanced.clone());

        let mut cache = PageCache::default();
        cache.insert(page0);
        cache.insert(page4);

        // 当前位于第 0 页，保留集为 [0, 1]
        let keep_set = compute_final_pipeline_keep_set(0, 5, 1);
        assert_eq!(keep_set, vec![0, 1]);

        cache.evict_final_pipeline_cache_for_keep_set(&keep_set, epoch);

        // 页 0 在保留集中：超分增强图完整保留
        let (p0, _) = cache.get(0, epoch, 800, 600, false).unwrap();
        assert_eq!(p0.unwrap().rgba, blue_enhanced.rgba);

        // 页 4 超出保留集：超分增强图被释放，降级回退至原图，显存安全释放
        let (p4, _) = cache.get(4, epoch, 800, 600, false).unwrap();
        assert_eq!(p4.unwrap().rgba, red_raw.rgba);
    }

    /// 回归：**原图回填不得抹掉超分轨**（「虚报替换成功」的根因）。
    ///
    /// 真实时序：预取线程先开始解第 7 页原图 → 超分注入完成（页 7 带上超分轨）
    /// → 预取线程解完，`insert(CachedPage::new_raw(7, …))` 回填原图。
    /// 旧实现在这里把超分轨整条抹掉，于是下一次 `show` 渲染回原图，而 Dart 侧那条
    /// 「超分成功 / 已替换呈现」的日志早就发出去了 —— 画面与日志各说各话。
    #[test]
    fn test_insert_raw_keeps_enhanced_track() {
        let epoch = 7;
        let red_raw = Arc::new(PagePixels {
            width: 1,
            height: 1,
            source_width: 1,
            source_height: 1,
            rgba: vec![255, 0, 0, 255],
        });
        let blue_enhanced = Arc::new(PagePixels {
            width: 2,
            height: 2,
            source_width: 1,
            source_height: 1,
            rgba: vec![0, 0, 255, 255].repeat(4),
        });

        let mut cache = PageCache::default();

        // ① 超分先注入：条目只有超分轨（此时还没有原图像素）
        cache.set_enhanced_pixels(7, epoch, blue_enhanced.clone());
        cache.add_pre_rendered_enhanced(
            7,
            epoch,
            PreRenderedFrame {
                target_w: 100,
                target_h: 100,
                bgra: Arc::new(vec![0u8; 100 * 4 * 100]),
                stride: 400,
            },
        );
        assert!(cache.prefers_enhanced(7, epoch, false));

        // ② 预取线程随后回填原图（走的是 insert，不是 set_pixels）
        cache.insert(CachedPage::new_raw(7, epoch, Some(red_raw.clone())));

        // ③ 超分轨必须还在：呈现仍应当取超分图，而不是静默退回原图
        let (pixels, frame) = cache.get(7, epoch, 100, 100, false).unwrap();
        assert_eq!(
            pixels.unwrap().rgba,
            blue_enhanced.rgba,
            "原图回填把超分张量抹掉了：画面会退回原图，而 Dart 侧仍报「替换成功」"
        );
        assert!(frame.is_some(), "原图回填把超分预渲染帧抹掉了");

        // ④ 反方向：新条目自带超分轨时，以新的为准（不能把回填的原图覆盖上去）
        let green_enhanced = Arc::new(PagePixels {
            width: 2,
            height: 2,
            source_width: 1,
            source_height: 1,
            rgba: vec![0, 255, 0, 255].repeat(4),
        });
        cache.set_enhanced_pixels(7, epoch, green_enhanced.clone());
        assert_eq!(
            cache
                .get(7, epoch, 100, 100, false)
                .unwrap()
                .0
                .unwrap()
                .rgba,
            green_enhanced.rgba
        );

        // ⑤ 原图对比旁路仍然要能瞬切回原图（超分轨在、但不参与呈现）
        assert!(!cache.prefers_enhanced(7, epoch, true));
    }

    #[test]
    fn test_raw_prefetch_never_selects_enhanced_track() {
        let epoch = 9;
        let raw = Arc::new(PagePixels {
            width: 1,
            height: 1,
            source_width: 1,
            source_height: 1,
            rgba: vec![255, 0, 0, 255],
        });
        let enhanced = Arc::new(PagePixels {
            width: 2,
            height: 2,
            source_width: 1,
            source_height: 1,
            rgba: vec![0, 0, 255, 255].repeat(4),
        });
        let mut cache = PageCache::default();
        let mut page = CachedPage::new_raw(3, epoch, Some(raw.clone()));
        page.enhanced_pixels = Some(enhanced);
        page.add_raw_frame(PreRenderedFrame {
            target_w: 100,
            target_h: 100,
            bgra: Arc::new(vec![1; 100 * 100 * 4]),
            stride: 400,
        });
        cache.insert(page);

        let (pixels, frame) = cache
            .get_raw(3, epoch, 100, 100)
            .expect("原图预取应命中原图条目");
        assert_eq!(pixels.expect("原图像素应存在").rgba, raw.rgba);
        assert!(frame.is_some(), "原图预渲染帧应从 raw 桶读取");
    }

    /// 回归：**预渲染帧要进对桶**，以及"超分图已在、镜像尺寸变了"时不再空转。
    ///
    /// 预取线程阶段 2 的输入来自 `get_unrendered_pixels`。它拿到的可能是**超分轨**
    /// 的像素（超分图已注入、但当前视口尺寸还没有匹配的预渲染帧），那时帧必须进
    /// `pre_rendered_enhanced`：
    /// - 进错桶 → 原图对比（旁路）会把超分图当原图显示出来；
    /// - 进错桶 → `resolve_display_frame` 因为"超分图在、不许透出旧原图帧"仍返回
    ///   `None`，阶段 2 于是每次轮询（15 ms）都判定"还没渲染" → **持续空转**。
    #[test]
    fn test_unrendered_pixels_report_their_track() {
        let epoch = 3;
        let raw = Arc::new(PagePixels {
            width: 4,
            height: 4,
            source_width: 4,
            source_height: 4,
            rgba: vec![255, 0, 0, 255].repeat(16),
        });
        let enhanced = Arc::new(PagePixels {
            width: 8,
            height: 8,
            source_width: 4,
            source_height: 4,
            rgba: vec![0, 0, 255, 255].repeat(64),
        });

        let mut cache = PageCache::default();
        cache.insert(CachedPage::new_raw(0, epoch, Some(raw)));
        // 只有原图、且当前尺寸没有预渲染帧 → 要渲染，且来源是原图轨
        let (pixels, enhanced_flag) = cache.get_unrendered_pixels(0, epoch, 100, 100).unwrap();
        assert_eq!(pixels.rgba[0], 255);
        assert!(!enhanced_flag, "原图像素被报成了超分轨");

        // 注入超分图：现在来源是超分轨，桶也得跟着换
        cache.set_enhanced_pixels(0, epoch, enhanced.clone());
        let (pixels, enhanced_flag) = cache.get_unrendered_pixels(0, epoch, 100, 100).unwrap();
        assert_eq!(pixels.rgba, enhanced.rgba);
        assert!(
            enhanced_flag,
            "超分像素被报成了原图轨 —— 原图对比会显示超分图"
        );

        // 按这个标志回填之后，同一尺寸就"已渲染"了 —— 预取线程不会再空转重采样
        cache.add_pre_rendered_enhanced(
            0,
            epoch,
            PreRenderedFrame {
                target_w: 100,
                target_h: 100,
                bgra: Arc::new(vec![0u8; 400 * 100]),
                stride: 400,
            },
        );
        assert!(
            cache.get_unrendered_pixels(0, epoch, 100, 100).is_none(),
            "回填到正确的那一轨之后，同一尺寸不该再判定为'待渲染'（否则每 15ms 重采样一次）"
        );
    }

    #[test]
    fn test_set_enhanced_image_from_file() {
        let mut presenter = MacPresenter::new(100, 100).expect("初始化 MacPresenter 失败");
        let temp_dir = std::env::temp_dir();
        let png_path = temp_dir.join("test_sr_enhanced.png");

        let mut img = image::RgbaImage::new(4, 4);
        for pixel in img.pixels_mut() {
            *pixel = image::Rgba([0, 255, 0, 255]); // 绿色
        }
        img.save(&png_path).expect("保存测试 PNG 失败");

        // 注入超分图
        let res = presenter.set_enhanced_image(0, png_path.to_str().unwrap(), 100, 100);
        assert!(res.is_ok());

        // 清理临时文件
        let _ = std::fs::remove_file(png_path);
    }

    #[test]
    fn test_show_into_buffer_after_set_enhanced() {
        let mut presenter = MacPresenter::new(100, 100).expect("初始化 MacPresenter 失败");
        let temp_dir = std::env::temp_dir().join("test_rossi_comic_folder");
        let _ = std::fs::remove_dir_all(&temp_dir);
        std::fs::create_dir_all(&temp_dir).expect("创建测试文件夹失败");

        // 创建原图 000.png (红色)
        let raw_png = temp_dir.join("000.png");
        let mut red_img = image::RgbaImage::new(4, 4);
        for pixel in red_img.pixels_mut() {
            *pixel = image::Rgba([255, 0, 0, 255]); // 红色
        }
        red_img.save(&raw_png).expect("保存原图失败");

        // 打开来源
        presenter.open(&temp_dir).expect("打开来源失败");
        presenter.set_prefetch(false);

        // 1. 第一次 show：上屏原图（红色）
        let mut dst = vec![0u8; 100 * 4 * 100];
        let show_raw = presenter.show_into_buffer(0, dst.as_mut_ptr(), 100 * 4, 100, 100);
        assert!(show_raw.is_ok());
        let idx = (50 * 100 + 50) * 4;
        println!(
            "Initial raw: B={}, G={}, R={}, A={}",
            dst[idx],
            dst[idx + 1],
            dst[idx + 2],
            dst[idx + 3]
        );
        assert_eq!(dst[idx + 2], 255, "初次呈现应当为原图红色");
        // 证据必须是"没用超分轨"：Dart 侧就是靠它判断替换有没有生效
        assert!(
            presenter.stats_json().contains("\"usedEnhanced\":0"),
            "原图呈现时 usedEnhanced 应为 0，实际: {}",
            presenter.stats_json()
        );

        // 原图像素已释放、仅命中预渲染帧时，仍须上报当前页的原始尺寸。
        {
            let mut cache = presenter.shared_cache.cache.lock().unwrap();
            cache
                .entries
                .iter_mut()
                .find(|e| e.index == 0)
                .unwrap()
                .raw_pixels = None;
        }
        presenter.last_source_width = 1200;
        presenter.last_source_height = 600;
        presenter
            .show_into_buffer(0, dst.as_mut_ptr(), 100 * 4, 100, 100)
            .unwrap();
        assert!(presenter.last_prerender_hit);
        assert_eq!(
            (presenter.last_source_width, presenter.last_source_height),
            (4, 4)
        );

        // 2. 模拟超分 Worker 生成了绿色超分大图并注入
        let sr_png = temp_dir.join("sr_000.png");
        let mut green_img = image::RgbaImage::new(8, 8);
        for pixel in green_img.pixels_mut() {
            *pixel = image::Rgba([0, 255, 0, 255]); // 绿色
        }
        green_img.save(&sr_png).expect("保存超分图失败");

        let res = presenter.set_enhanced_image(0, sr_png.to_str().unwrap(), 100, 100);
        assert!(res.is_ok());

        // 3. 再次 show（模拟 Swift handleShow 重新上屏）：应当原子替换为绿色！
        let show_sr = presenter.show_into_buffer(0, dst.as_mut_ptr(), 100 * 4, 100, 100);
        assert!(show_sr.is_ok());
        println!(
            "After enhanced: B={}, G={}, R={}, A={}",
            dst[idx],
            dst[idx + 1],
            dst[idx + 2],
            dst[idx + 3]
        );
        assert_eq!(dst[idx + 1], 255, "G 通道应当为 255（超分绿色）");
        assert_eq!(dst[idx + 2], 0, "R 通道应当为 0（原图红色已被平滑替换）");
        // 证据必须与画面一致：这一帧确实取自超分轨
        let stats = presenter.stats_json();
        assert!(
            stats.contains("\"currentIndex\":0") && stats.contains("\"usedEnhanced\":1"),
            "超分替换上屏后证据应当是 currentIndex=0 + usedEnhanced=1，实际: {stats}"
        );

        // 4. 原图对比旁路切换：应当毫秒级瞬切回红色
        presenter.set_original_preview(true);
        let show_orig_bypass = presenter.show_into_buffer(0, dst.as_mut_ptr(), 100 * 4, 100, 100);
        assert!(show_orig_bypass.is_ok());
        println!(
            "After bypass: B={}, G={}, R={}, A={}",
            dst[idx],
            dst[idx + 1],
            dst[idx + 2],
            dst[idx + 3]
        );
        assert_eq!(dst[idx + 1], 0, "G 通道应当为 0");
        assert_eq!(dst[idx + 2], 255, "R 通道应当为 255（瞬切回原图红色）");
        // 旁路态下证据也必须是 0，否则 Dart 侧会把"用户正在看原图"读成"替换生效"
        assert!(
            presenter.stats_json().contains("\"usedEnhanced\":0"),
            "旁路呈现时 usedEnhanced 应为 0，实际: {}",
            presenter.stats_json()
        );

        let _ = std::fs::remove_dir_all(&temp_dir);
    }

    /// 回归：**探针里的配色必须属于刚 show 的那一页**。
    ///
    /// Dart 侧决定背景色读的就是「`ambient` + `currentIndex`」这一对。两者差一拍
    /// （配色是上一页的、索引是这一页的）时，观感是「翻页后背景还留着上一页的颜色」
    /// —— 那看起来只是"取色慢半拍"，不会有人去查，所以这里逐页核对。
    ///
    /// 顺带守住两条承诺：
    /// 1. 未上屏 / 换书之后是**字面 `null`**，不是编出来的黑；
    /// 2. 缓存未命中（现场解码）那条路也必须有配色，否则就成了
    ///    「只有被预取过的那几页才有背景色」。
    #[test]
    fn test_ambient_palette_follows_the_shown_page() {
        let mut presenter = MacPresenter::new(100, 100).expect("初始化 MacPresenter 失败");
        let temp_dir = std::env::temp_dir().join("test_rossi_ambient_folder");
        let _ = std::fs::remove_dir_all(&temp_dir);
        std::fs::create_dir_all(&temp_dir).expect("创建测试文件夹失败");

        // 页 0 红、页 1 蓝：颜色不同才分得清「探针报的是哪一页的」
        for (name, color) in [
            ("000.png", [255u8, 0, 0, 255]),
            ("001.png", [0u8, 0, 255, 255]),
        ] {
            let mut img = image::RgbaImage::new(4, 4);
            for pixel in img.pixels_mut() {
                *pixel = image::Rgba(color);
            }
            img.save(temp_dir.join(name)).expect("保存测试页失败");
        }

        presenter.open(&temp_dir).expect("打开来源失败");
        presenter.set_prefetch(false);

        assert!(
            presenter.stats_json().contains("\"ambient\":null"),
            "打开来源但还没上屏时 ambient 应当是 null，实际: {}",
            presenter.stats_json()
        );

        let mut dst = vec![0u8; 100 * 4 * 100];

        // 第 0 页：首次上屏，缓存未命中 → 现场解码 → 配色必须当场就有。
        presenter
            .show_into_buffer(0, dst.as_mut_ptr(), 100 * 4, 100, 100)
            .expect("呈现第 0 页失败");
        let stats0 = presenter.stats_json();
        assert!(
            stats0.contains("\"currentIndex\":0"),
            "第 0 页应当报 currentIndex=0，实际: {stats0}"
        );
        assert!(
            stats0.contains("\"ambient\":{\"average\":\"#ff0000\""),
            "第 0 页是红的，探针里的代表色必须也是红的，实际: {stats0}"
        );

        // 第 1 页：换页之后配色必须跟着换，且索引与配色来自**同一次**统计。
        presenter
            .show_into_buffer(1, dst.as_mut_ptr(), 100 * 4, 100, 100)
            .expect("呈现第 1 页失败");
        let stats1 = presenter.stats_json();
        assert!(
            stats1.contains("\"currentIndex\":1"),
            "第 1 页应当报 currentIndex=1，实际: {stats1}"
        );
        assert!(
            stats1.contains("\"ambient\":{\"average\":\"#0000ff\""),
            "翻到蓝页之后配色必须跟着换，实际: {stats1}"
        );

        // 换书：同一个呈现器 open 另一个来源，上一本的配色不能留下来。
        let other_dir = std::env::temp_dir().join("test_rossi_ambient_folder_other");
        let _ = std::fs::remove_dir_all(&other_dir);
        std::fs::create_dir_all(&other_dir).expect("创建第二个测试文件夹失败");
        let mut img = image::RgbaImage::new(4, 4);
        for pixel in img.pixels_mut() {
            *pixel = image::Rgba([0, 255, 0, 255]);
        }
        img.save(other_dir.join("000.png")).expect("保存测试页失败");

        presenter.open(&other_dir).expect("换来源失败");
        assert!(
            presenter.stats_json().contains("\"ambient\":null"),
            "换了书之后不该还报上一本的配色，实际: {}",
            presenter.stats_json()
        );

        let _ = std::fs::remove_dir_all(&temp_dir);
        let _ = std::fs::remove_dir_all(&other_dir);
    }
