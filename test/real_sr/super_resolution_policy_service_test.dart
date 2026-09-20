import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/page/setting/real_sr/model/super_resolution_condition.dart';
import 'package:zephyr/page/setting/real_sr/service/super_resolution_policy_service.dart';

void main() {
  const defaultInput = SuperResolutionPolicyInput(
    trigger: SuperResolutionPolicyTrigger.auto,
    width: 800,
    height: 1200,
    bookPath: r'D:\Library\02COS\book.cbz',
    imagePath: r'D:\Cache\page-001.png',
    innerPath: 'chapter/cover.png',
    createdAt: 100,
    modifiedAt: 200,
    metadata: {'rating': 4.5, 'artist': 'alice and bob'},
  );

  group('SuperResolutionPolicyService (移植自 neo)', () {
    test('默认策略解析（未开启条件超分或未命中任何条件）', () {
      final policy = SuperResolutionPolicyService(
        const SuperResolutionPolicyPreferences(
          autoUpscaleEnabled: true,
          defaultModelId: 'realesr-animevideov3',
          defaultScale: 2,
          defaultTileEnabled: true,
          defaultTileSize: 256,
          defaultNoise: 0,
          defaultGpuId: '1',
        ),
      );

      final decision = policy.decide(defaultInput);
      expect(decision.kind, 'run');
      expect(decision.reason, 'default-policy');
      expect(decision.modelId, 'realesr-animevideov3');
      expect(decision.scale, 2);
      expect(decision.noise, 0);
      expect(decision.tileSize, 256);
      expect(decision.gpuId, '1');
      expect(decision.useCache, isTrue);
      expect(decision.conditionId, isNull);
    });

    test('优先级顺序：优先选择首个匹配的已启用条件', () {
      final policy = SuperResolutionPolicyService(
        SuperResolutionPolicyPreferences(
          autoUpscaleEnabled: true,
          conditionalEnabled: true,
          defaultModelId: 'realesr-animevideov3',
          defaultScale: 2,
          conditions: [
            const SuperResolutionCondition(
              id: 'later',
              name: '后置条件',
              enabled: true,
              priority: 10,
              match: ConditionMatch(minWidth: 1),
              action: ConditionAction(modelId: 'realcugan', scale: 4),
            ),
            SuperResolutionCondition(
              id: 'cos',
              name: 'COS 漫画规则',
              enabled: true,
              priority: 1,
              match: ConditionMatch(
                maxWidth: 1024,
                maxMegapixels: 1.0,
                bookPathRegex: r'(?:^|/)02COS(?:/|$)',
                imagePathRegex: r'^chapter/',
                matchInnerPath: true,
                metadata: {
                  'rating': const ConditionMetadataExpression(
                    operator: 'gte',
                    value: 4,
                  ),
                  'artist': const ConditionMetadataExpression(
                    operator: 'contains',
                    value: 'alice',
                  ),
                },
              ),
              action: const ConditionAction(
                modelId: 'realesrgan-x4plus-anime',
                scale: 4,
                tileEnabled: false,
                useCache: false,
              ),
            ),
          ],
        ),
      );

      final decision = policy.decide(defaultInput);
      expect(decision.kind, 'run');
      expect(decision.reason, 'condition-match');
      expect(decision.conditionId, 'cos');
      expect(decision.modelId, 'realesrgan-x4plus-anime');
      expect(decision.scale, 4);
      expect(decision.tileSize, isNull);
      expect(decision.useCache, isFalse);
    });

    test('Skip 动作与预超分排除动作（excludeFromPreload）', () {
      final skipPolicy = SuperResolutionPolicyService(
        const SuperResolutionPolicyPreferences(
          autoUpscaleEnabled: true,
          conditionalEnabled: true,
          conditions: [
            SuperResolutionCondition(
              id: 'large',
              name: '大图跳过',
              enabled: true,
              priority: 0,
              match: ConditionMatch(minWidth: 700),
              action: ConditionAction(skip: true),
            ),
          ],
        ),
      );
      final skipDecision = skipPolicy.decide(defaultInput);
      expect(skipDecision.kind, 'skip');
      expect(skipDecision.reason, 'condition-skip');
      expect(skipDecision.conditionId, 'large');

      final preloadPolicy = SuperResolutionPolicyService(
        const SuperResolutionPolicyPreferences(
          autoUpscaleEnabled: true,
          preUpscaleEnabled: true,
          conditionalEnabled: true,
          conditions: [
            SuperResolutionCondition(
              id: 'current-only',
              name: '仅当前页超分',
              enabled: true,
              priority: 0,
              match: ConditionMatch(excludeFromPreload: true),
              action: ConditionAction(modelId: 'realcugan', scale: 2),
            ),
          ],
        ),
      );
      final preloadDecision = preloadPolicy.decide(
        const SuperResolutionPolicyInput(
          trigger: SuperResolutionPolicyTrigger.preload,
          width: 800,
          height: 1200,
          bookPath: 'test.cbz',
          imagePath: 'test.png',
        ),
      );
      expect(preloadDecision.kind, 'skip');
      expect(preloadDecision.reason, 'condition-excludes-preload');
      expect(preloadDecision.conditionId, 'current-only');
    });

    test('触发器隔离：manual 手动触发不受全局自动开关和最小尺寸限制', () {
      final policy = SuperResolutionPolicyService(
        const SuperResolutionPolicyPreferences(
          autoUpscaleEnabled: false,
          preUpscaleEnabled: false,
          defaultModelId: 'realcugan',
          defaultScale: 2,
        ),
      );
      expect(
        policy.decide(defaultInput).kind,
        'disabled',
      );
      expect(
        policy
            .decide(
              const SuperResolutionPolicyInput(
                trigger: SuperResolutionPolicyTrigger.manual,
                width: 800,
                height: 1200,
                bookPath: 'test.cbz',
                imagePath: 'test.png',
              ),
            )
            .kind,
        'run',
      );

      final conditionalMinPolicy = SuperResolutionPolicyService(
        const SuperResolutionPolicyPreferences(
          autoUpscaleEnabled: true,
          conditionalEnabled: true,
          conditionalMinWidth: 1000,
          conditionalMinHeight: 1000,
          defaultModelId: 'realcugan',
          defaultScale: 2,
        ),
      );
      expect(
        conditionalMinPolicy.decide(defaultInput).kind,
        'skip',
      );
      expect(
        conditionalMinPolicy
            .decide(
              const SuperResolutionPolicyInput(
                trigger: SuperResolutionPolicyTrigger.manual,
                width: 800,
                height: 1200,
                bookPath: 'test.cbz',
                imagePath: 'test.png',
              ),
            )
            .kind,
        'run',
      );
    });

    test('尺寸判定方式：dimensionMode 为 or 时满足宽或高之一即可', () {
      final orPolicy = SuperResolutionPolicyService(
        const SuperResolutionPolicyPreferences(
          autoUpscaleEnabled: true,
          conditionalEnabled: true,
          defaultModelId: 'default',
          defaultScale: 2,
          conditions: [
            SuperResolutionCondition(
              id: 'or-rule',
              name: '宽或高符合',
              enabled: true,
              priority: 0,
              match: ConditionMatch(
                dimensionMode: 'or',
                minWidth: 900, // 不满足（实际 800）
                minHeight: 1000, // 满足（实际 1200）
              ),
              action: ConditionAction(modelId: 'matched-model'),
            ),
          ],
        ),
      );
      expect(
        orPolicy.decide(defaultInput).modelId,
        'matched-model',
      );

      final andPolicy = SuperResolutionPolicyService(
        const SuperResolutionPolicyPreferences(
          autoUpscaleEnabled: true,
          conditionalEnabled: true,
          defaultModelId: 'default',
          defaultScale: 2,
          conditions: [
            SuperResolutionCondition(
              id: 'and-rule',
              name: '宽高全符合',
              enabled: true,
              priority: 0,
              match: ConditionMatch(
                dimensionMode: 'and',
                minWidth: 900, // 不满足
                minHeight: 1000,
              ),
              action: ConditionAction(modelId: 'matched-model'),
            ),
          ],
        ),
      );
      expect(
        andPolicy.decide(defaultInput).modelId,
        'default',
      );
    });
  });
}
