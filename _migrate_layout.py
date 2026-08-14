# -*- coding: utf-8 -*-
import io
p = 'lib/core/settings_layout.dart'
s = io.open(p, encoding='utf-8').read()

old_visual = """    SettingCollection(
      id: 'visual',
      name: '画面',
      groups: <SettingGroup>[
        SettingGroup(
          id: 'visual_appearance',
          name: '外观',
          items: <SettingItem>[
            SettingItem(id: 'themeMode', title: '主题模式', kind: SettingKind.chips),
            SettingItem(id: 'themeSkin', title: '皮肤', kind: SettingKind.chips),
            SettingItem(id: 'uiDensity', title: '界面密度', kind: SettingKind.chips),
          ],
        ),
        SettingGroup(
          id: 'visual_scene',
          name: '场景',
          items: <SettingItem>[
            SettingItem(id: 'sceneEditor', title: '场景编辑器'),
            SettingItem(id: 'customSceneList', title: '自定义场景管理'),
          ],
        ),
      ],
    ),"""

new_visual = """    SettingCollection(
      id: 'visual',
      name: '画面',
      groups: <SettingGroup>[
        SettingGroup(
          id: 'visual_appearance',
          name: '外观',
          items: <SettingItem>[
            SettingItem(id: 'themeMode', title: '主题模式', kind: SettingKind.chips),
            SettingItem(id: 'themeSkin', title: '皮肤', kind: SettingKind.chips),
            SettingItem(id: 'uiDensity', title: '界面密度', kind: SettingKind.chips),
          ],
        ),
        SettingGroup(
          id: 'visual_scene',
          name: '场景',
          items: <SettingItem>[
            SettingItem(id: 'sceneEditor', title: '场景编辑器'),
            SettingItem(id: 'customSceneList', title: '自定义场景管理'),
          ],
        ),
        SettingGroup(
          id: 'visual_perf',
          name: '性能与质量',
          items: <SettingItem>[
            SettingItem(id: 'gameGraphics', title: '游戏画面（画质/视距/LOD）'),
            SettingItem(id: 'perfPreset', title: '性能预设', kind: SettingKind.chips),
            SettingItem(id: 'fpsLimit', title: '帧率限制', kind: SettingKind.chips),
            SettingItem(id: 'viewDistance', title: '视距', kind: SettingKind.chips),
            SettingItem(id: 'lodStart', title: 'LOD 起始', kind: SettingKind.chips),
            SettingItem(id: 'lodStep', title: 'LOD 步长', kind: SettingKind.chips),
            SettingItem(id: 'lodEnabled', title: 'LOD 开关', kind: SettingKind.toggle),
            SettingItem(id: 'lodStepBlocks', title: 'LOD 步长（格）', kind: SettingKind.chips),
            SettingItem(id: 'lodSample', title: 'LOD 采样（大方块）', kind: SettingKind.chips),
            SettingItem(id: 'lodMaxChunks', title: 'LOD 最远距离', kind: SettingKind.slider),
            SettingItem(id: 'engineBackend', title: '图形后端', kind: SettingKind.chips),
            SettingItem(id: 'shadowRender', title: '阴影渲染', kind: SettingKind.toggle),
            SettingItem(id: 'aoRender', title: '环境光屏蔽（AO）', kind: SettingKind.toggle),
            SettingItem(id: 'fxNoise', title: '噪点纹理', kind: SettingKind.toggle),
            SettingItem(id: 'fxBlur', title: '玻璃模糊', kind: SettingKind.toggle),
            SettingItem(id: 'fxBg', title: '背景动画', kind: SettingKind.toggle),
            SettingItem(id: 'fxLiquid', title: '液态玻璃（折射）', kind: SettingKind.toggle),
          ],
        ),
        SettingGroup(
          id: 'visual_render',
          name: '渲染（更多）',
          items: <SettingItem>[
            SettingItem(id: 'flashlight', title: '手电筒模式', kind: SettingKind.toggle),
            SettingItem(id: 'underwaterFilter', title: '水下滤镜', kind: SettingKind.toggle),
            SettingItem(id: 'faceCull', title: '侧面剔除', kind: SettingKind.toggle),
            SettingItem(id: 'occlusionCull', title: '遮挡剔除', kind: SettingKind.toggle),
            SettingItem(id: 'backFaceCull', title: '背面剔除', kind: SettingKind.toggle),
            SettingItem(id: 'frustumCull', title: '视锥剔除', kind: SettingKind.toggle),
          ],
        ),
      ],
    ),"""

old_mechanics = """    SettingCollection(
      id: 'mechanics',
      name: '机制',
      groups: <SettingGroup>[
        SettingGroup(
          id: 'mechanics_world',
          name: '世界与生成',
          items: <SettingItem>[
            SettingItem(id: 'worldSfx', title: '世界音效设置'),
            SettingItem(id: 'worldSave', title: '世界存档'),
          ],
        ),
        SettingGroup(
          id: 'mechanics_perf',
          name: '性能与质量',
          items: <SettingItem>[
            SettingItem(id: 'gameGraphics', title: '游戏画面（画质/视距/LOD）'),
            SettingItem(id: 'perfPreset', title: '性能预设', kind: SettingKind.chips),
            SettingItem(id: 'fpsLimit', title: '帧率限制', kind: SettingKind.chips),
            SettingItem(id: 'viewDistance', title: '视距', kind: SettingKind.chips),
            SettingItem(id: 'lodStart', title: 'LOD 起始', kind: SettingKind.chips),
            SettingItem(id: 'lodStep', title: 'LOD 步长', kind: SettingKind.chips),
            SettingItem(id: 'lodEnabled', title: 'LOD 开关', kind: SettingKind.toggle),
            SettingItem(id: 'lodStepBlocks', title: 'LOD 步长（格）', kind: SettingKind.chips),
            SettingItem(id: 'lodSample', title: 'LOD 采样（大方块）', kind: SettingKind.chips),
            SettingItem(id: 'lodMaxChunks', title: 'LOD 最远距离', kind: SettingKind.slider),
            SettingItem(id: 'engineBackend', title: '图形后端', kind: SettingKind.chips),
            SettingItem(id: 'fxNoise', title: '噪点纹理', kind: SettingKind.toggle),
            SettingItem(id: 'fxBlur', title: '玻璃模糊', kind: SettingKind.toggle),
            SettingItem(id: 'fxBg', title: '背景动画', kind: SettingKind.toggle),
            SettingItem(id: 'fxLiquid', title: '液态玻璃（折射）', kind: SettingKind.toggle),
          ],
        ),
        SettingGroup(
          id: 'mechanics_render',
          name: '渲染与机制（更多）',
          items: <SettingItem>[
            SettingItem(id: 'flashlight', title: '手电筒模式', kind: SettingKind.toggle),
            SettingItem(id: 'faceCull', title: '侧面剔除', kind: SettingKind.toggle),
            SettingItem(id: 'occlusionCull', title: '遮挡剔除', kind: SettingKind.toggle),
            SettingItem(id: 'backFaceCull', title: '背面剔除', kind: SettingKind.toggle),
            SettingItem(id: 'frustumCull', title: '视锥剔除', kind: SettingKind.toggle),
            SettingItem(id: 'underwaterFilter', title: '水下滤镜', kind: SettingKind.toggle),
            SettingItem(id: 'waterFlow', title: '水流动', kind: SettingKind.toggle),
            SettingItem(id: 'autoBackup', title: '后台自动备份'),
          ],
        ),
      ],
    ),"""

new_mechanics = """    SettingCollection(
      id: 'mechanics',
      name: '机制',
      groups: <SettingGroup>[
        SettingGroup(
          id: 'mechanics_world',
          name: '世界与玩法',
          items: <SettingItem>[
            SettingItem(id: 'worldSfx', title: '世界音效设置'),
            SettingItem(id: 'worldSave', title: '世界存档'),
            SettingItem(id: 'autoBackup', title: '后台自动备份'),
            SettingItem(id: 'waterFlow', title: '水流动', kind: SettingKind.toggle),
          ],
        ),
      ],
    ),"""

assert old_visual in s, 'old_visual not found'
assert old_mechanics in s, 'old_mechanics not found'
s = s.replace(old_visual, new_visual).replace(old_mechanics, new_mechanics)
io.open(p, 'w', encoding='utf-8').write(s)
print('layout migrated ok')
