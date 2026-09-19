#!/usr/bin/env python3
"""把 Real-ESRGAN 的 RRDBNet 权重（含官方 x2plus）转换为 CoreML .mlpackage。

为什么需要它
------------
`packages/coreml_upscale` 插件只吃 `.mlmodel` / `.mlpackage`，而 Real-ESRGAN 官方
只发布 `.pth`。Breeze 现有两个 CoreML 模型（waifu2x 2x、Real-CUGAN 2x）都是预先
转好、放在 `deretame/breeze-binary` 的 `MacOS-iOS.7z` 里的；本脚本让你自己补第三个：
Real-ESRGAN 的 2x 模型。

可用的 2x 权重（均为 BSD-3-Clause，可随分发）
--------------------------------------------
1. **RealESRGAN_x2plus.pth** —— 本脚本对应这一支
   RRDBNet（23 RRDB blocks，num_feat 64），约 64 MB。
   https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.1/RealESRGAN_x2plus.pth
2. RealESRGANv2-animevideo-xsx2.pth —— 动漫视频向、XS compact（SRVGGNetCompact），
   架构与本脚本不同（不是 RRDBNet），**本脚本不处理**；如要用需另写 wrapper。
   https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.3.0/RealESRGANv2-animevideo-xsx2.pth
3. realesr-general-x4v3.pth —— 是 x4 模型，官方称可当 1/2/3x 用（靠 `--outscale`
   做输出后下采样），不是真正的 2x 网络。

依赖
----
    pip install torch coremltools numpy

不需要 clone Real-ESRGAN，也不需要 basicsr —— 本脚本内联了 RRDBNet 结构定义
（见下方注释）。权重加载走 `load_state_dict` 默认的 strict 校验，结构写错会直接报错。

与 coreml_upscale 插件的契约（重要）
------------------------------------
`packages/coreml_upscale/macos/Classes/MultiArrayModel.swift` 的拼块逻辑是：

    contentBlockSize = blockSize - 2 * shrinkSize          // 真正参与拼接的内容块
    输入 MLMultiArray 尺寸 = blockSize × blockSize          // 含四周反射边距
    从模型输出里取 **左上角** (contentBlockSize * scale)² 直接写入结果

注意最后一句：插件取的是输出的左上角，**不是中心**。所以导出的模型输出必须
**正好等于 contentBlockSize × scale**，多余部分必须在模型内裁掉。若直接把原始
RRDBNet 导出（输出 = 输入 × scale = 384），插件会取到左上角 312×312，结果是
画面整体偏移并带上边缘的反射padding。

因此本脚本包了一层 wrapper：网络跑完后再按 `shrinkSize * scale` 裁掉四周，
使输出尺寸严格等于 `--block-size * --scale`。这与 `convert_realcugan_coreml.py`
里 `F.pad(x, (-20, -20, -20, -20))` 要解决的问题是同一个。

用法
----
    python script/convert_realesrgan_coreml.py \
        --weight RealESRGAN_x2plus.pth \
        --output asset/coreml_models/RealESRGAN_x2plus_block156.mlpackage

转完后在 `lib/util/coreml_model_config.dart` 的 `families` 里追加一条（数值须与
脚本打印的一致）：

    CoreMLModelVariant(
      displayName: 'Real-ESRGAN 2x',
      fileName: 'RealESRGAN_x2plus_block156.mlpackage',
      config: <String, dynamic>{
        'inputName': 'input',
        'outputName': 'output',
        'blockSize': 192,    // = 156 + 2 * 18，即模型固定输入边长
        'shrinkSize': 18,
        'scale': 2,
      },
    ),

然后把 .mlpackage 放进 `breeze-binary` 的 `MacOS-iOS.7z`（或走设置页的
「手动导入模型」）。注意 7z 内的目录结构与 `CoreMLModelConfig.archiveName` /
`archiveSubDir` 保持一致。

注意：本文件在 Bash 通道不可用的会话里写成，**尚未在本机实际执行过**。
首次使用请先跑一次并在末尾核对打印出的输入/输出尺寸。
"""

import argparse
import os
import sys


def _build_rrdbnet_classes():
    """内联官方 RRDBNet 结构，避免依赖 basicsr / realesrgan 包。

    结构与官方 `realesrgan/archs/rrdbnet_arch.py` 一致；差异只有两处，
    都不影响 state_dict 键名与数值：
      - 去掉 `@ARCH_REGISTRY.register()`（省掉 basicsr 依赖）
      - LeakyReLU 用 inplace=False，便于 torch.jit.trace
    """
    import torch
    from torch import nn as nn
    from torch.nn import functional as F

    def make_layer(basic_block, num_basic_block, **kwargs):
        return nn.Sequential(
            *[basic_block(**kwargs) for _ in range(num_basic_block)]
        )

    def pixel_unshuffle(x, scale):
        b, c, hh, hw = x.size()
        out_channel = c * (scale**2)
        h, w = hh // scale, hw // scale
        x_view = x.view(b, c, h, scale, w, scale)
        return x_view.permute(0, 1, 3, 5, 2, 4).reshape(b, out_channel, h, w)

    class ResidualDenseBlock(nn.Module):
        """官方 ResidualDenseBlock：5 个 3x3 卷积，densely connected。"""

        def __init__(self, num_feat=64, num_grow_ch=32):
            super().__init__()
            self.conv1 = nn.Conv2d(num_feat, num_grow_ch, 3, 1, 1)
            self.conv2 = nn.Conv2d(num_feat + num_grow_ch, num_grow_ch, 3, 1, 1)
            self.conv3 = nn.Conv2d(
                num_feat + 2 * num_grow_ch, num_grow_ch, 3, 1, 1
            )
            self.conv4 = nn.Conv2d(
                num_feat + 3 * num_grow_ch, num_grow_ch, 3, 1, 1
            )
            self.conv5 = nn.Conv2d(
                num_feat + 4 * num_grow_ch, num_feat, 3, 1, 1
            )
            self.lrelu = nn.LeakyReLU(negative_slope=0.2, inplace=False)

        def forward(self, x):
            x1 = self.lrelu(self.conv1(x))
            x2 = self.lrelu(self.conv2(torch.cat((x, x1), 1)))
            x3 = self.lrelu(self.conv3(torch.cat((x, x1, x2), 1)))
            x4 = self.lrelu(self.conv4(torch.cat((x, x1, x2, x3), 1)))
            x5 = self.conv5(torch.cat((x, x1, x2, x3, x4), 1))
            # 官方经验系数 0.2，用于稳定残差
            return x5 * 0.2 + x

    class RRDB(nn.Module):
        """Residual in Residual Dense Block：3 个 RDB + 外层残差。"""

        def __init__(self, num_feat, num_grow_ch=32):
            super().__init__()
            self.rdb1 = ResidualDenseBlock(num_feat, num_grow_ch)
            self.rdb2 = ResidualDenseBlock(num_feat, num_grow_ch)
            self.rdb3 = ResidualDenseBlock(num_feat, num_grow_ch)

        def forward(self, x):
            out = self.rdb1(x)
            out = self.rdb2(out)
            out = self.rdb3(out)
            return out * 0.2 + x

    class RRDBNet(nn.Module):
        """官方 RRDBNet。

        scale=2 时先把输入 pixel_unshuffle(2)（空间 /2、通道 ×4），主干仍做两轮
        2x 最近邻上采样，净效果 2x。这也是 x2plus 权重能直接用本结构加载的原因。
        """

        def __init__(
            self,
            num_in_ch=3,
            num_out_ch=3,
            scale=4,
            num_feat=64,
            num_block=23,
            num_grow_ch=32,
        ):
            super().__init__()
            self.scale = scale
            if scale == 2:
                num_in_ch = num_in_ch * 4
            elif scale == 1:
                num_in_ch = num_in_ch * 16
            self.conv_first = nn.Conv2d(num_in_ch, num_feat, 3, 1, 1)
            self.body = make_layer(
                RRDB, num_block, num_feat=num_feat, num_grow_ch=num_grow_ch
            )
            self.conv_body = nn.Conv2d(num_feat, num_feat, 3, 1, 1)
            self.conv_up1 = nn.Conv2d(num_feat, num_feat, 3, 1, 1)
            self.conv_up2 = nn.Conv2d(num_feat, num_feat, 3, 1, 1)
            self.conv_hr = nn.Conv2d(num_feat, num_feat, 3, 1, 1)
            self.conv_last = nn.Conv2d(num_feat, num_out_ch, 3, 1, 1)
            self.lrelu = nn.LeakyReLU(negative_slope=0.2, inplace=False)

        def forward(self, x):
            if self.scale == 2:
                feat = pixel_unshuffle(x, scale=2)
            elif self.scale == 1:
                feat = pixel_unshuffle(x, scale=4)
            else:
                feat = x
            feat = self.conv_first(feat)
            body_feat = self.conv_body(self.body(feat))
            feat = feat + body_feat
            feat = self.conv_up1(
                F.interpolate(feat, scale_factor=2, mode="nearest")
            )
            feat = self.conv_up2(
                F.interpolate(feat, scale_factor=2, mode="nearest")
            )
            return self.conv_last(self.lrelu(self.conv_hr(feat)))

    return RRDBNet


def main():
    parser = argparse.ArgumentParser(
        description="Convert Real-ESRGAN (RRDBNet) weights to CoreML"
    )
    parser.add_argument("--weight", required=True, help=".pth 权重文件路径")
    parser.add_argument("--output", required=True, help="输出 .mlpackage 路径")
    parser.add_argument(
        "--block-size", type=int, default=156,
        help="内容块边长，对应插件 config 的 blockSize - 2*shrinkSize（默认 156）",
    )
    parser.add_argument(
        "--shrink-size", type=int, default=18,
        help="每边反射边距，与 Real-CUGAN 对齐（默认 18）",
    )
    parser.add_argument("--scale", type=int, default=2, choices=[2, 4], help="放大倍率")
    parser.add_argument("--num-feat", type=int, default=64, help="RRDB 特征通道数")
    parser.add_argument("--num-block", type=int, default=23, help="RRDB 块数")
    parser.add_argument("--ios", type=int, default=15, help="最低 iOS 版本")
    parser.add_argument(
        "--fp32", action="store_true",
        help="用 FP32 导出（默认 FP16，更省内存/更快，但极端情况下有精度损失）",
    )
    parser.add_argument(
        "--no-clamp", action="store_true",
        help="不把输出 clamp 到 [0,1]（默认 clamp，与官方 inference 一致）",
    )
    args = parser.parse_args()

    import numpy as np
    import torch
    import coremltools as ct

    if not os.path.isfile(args.weight):
        raise FileNotFoundError(f"权重文件不存在: {args.weight}")

    RRDBNet = _build_rrdbnet_classes()

    input_size = args.block_size + 2 * args.shrink_size
    output_size = args.block_size * args.scale

    # x2 走 pixel_unshuffle，输入边长必须能被 2 整除；x1 需被 4 整除。
    divisor = 4 if args.scale == 1 else 2
    if input_size % divisor != 0:
        raise ValueError(
            f"输入尺寸 {input_size} 不能被 {divisor} 整除（scale={args.scale} 的 "
            f"pixel_unshuffle 要求）。请调整 --block-size / --shrink-size。"
        )

    net = RRDBNet(
        num_in_ch=3,
        num_out_ch=3,
        scale=args.scale,
        num_feat=args.num_feat,
        num_block=args.num_block,
        num_grow_ch=32,
    )
    # strict 校验：结构写错会在这里直接抛错，而不是产出一个静默错模型。
    net.load_state_dict(torch.load(args.weight, map_location="cpu"))
    net.eval()

    crop = args.shrink_size * args.scale
    do_clamp = not args.no_clamp

    class CoreMLWrapper(torch.nn.Module):
        """把网络输出裁到内容块大小，满足插件「取左上角 content*scale」的契约。"""

        def __init__(self, m, crop: int, clamp: bool):
            super().__init__()
            self.m = m
            self.crop = crop
            self.clamp = clamp

        def forward(self, x):
            y = self.m(x)
            if self.crop > 0:
                end = y.shape[-1] - self.crop
                y = y[..., self.crop : end, self.crop : end]
            if self.clamp:
                y = torch.clamp(y, 0.0, 1.0)
            return y

    wrapped = CoreMLWrapper(net, crop, do_clamp).eval()

    example = torch.randn(1, 3, input_size, input_size)
    with torch.no_grad():
        out = wrapped(example)
    print(f"输入 {tuple(example.shape)} -> 输出 {tuple(out.shape)}")
    assert out.shape[-2:] == (output_size, output_size), (
        f"输出尺寸 {tuple(out.shape[-2:])} 与预期 {output_size}x{output_size} 不符。"
        f"检查 --block-size / --shrink-size / --scale 是否与插件 config 自洽。"
    )

    traced = torch.jit.trace(wrapped, example)

    precision = ct.precision.FLOAT32 if args.fp32 else ct.precision.FLOAT16
    mlmodel = ct.convert(
        traced,
        inputs=[
            ct.TensorType(
                name="input",
                shape=(1, 3, input_size, input_size),
                dtype=np.float32,
            )
        ],
        outputs=[ct.TensorType(name="output", dtype=np.float32)],
        minimum_deployment_target=getattr(ct.target, f"iOS{args.ios}"),
        compute_precision=precision,
        compute_units=ct.ComputeUnit.ALL,
    )

    os.makedirs(os.path.dirname(args.output) or ".", exist_ok=True)
    mlmodel.save(args.output)
    print(f"已保存: {args.output}")
    print(
        "Dart 侧 config："
        f"blockSize={input_size}, shrinkSize={args.shrink_size}, scale={args.scale}"
        f"  （contentBlock = {args.block_size}）"
    )


if __name__ == "__main__":
    sys.exit(main())
