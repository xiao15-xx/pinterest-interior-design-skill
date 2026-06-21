# pinterest-interior-design-skill

A Pinterest interior-design reference finder for curated candidates, source tracking, and final image selection.
# Overview
pinterest-interior-design-skill is a Codex Skill dedicated to collecting high-quality interior design visual references from Pinterest, leveraging your existing logged-in Chrome session.
Core Design Target
It delivers bounded, visible search results to output a small refined image library with consistent candidate quantity, complete original source metadata, contact-sheet preview support, and reversible final image pick operations.
# Perfect use cases:
Interior mood boards
Design proposal materials
Space style reference collection
Material inspiration gathering
High-end visual direction sorting
# Default Standard Workflow
Parse your design brief
Generate compact bilingual (Chinese + English) search query plan
Execute one targeted Pinterest search via Chrome
Extract & retain 8–16 visible candidate images
Store original raw image files + full source metadata
Rank images by visual matching quality
Save top-rated final selected pictures
# Usage Example in Codex
Invoke this skill via the token $pinterest-interior-design-skill
# Sample instruction:
plaintext
Use $pinterest-interior-design-skill to find modern oriental luxury living room references and save 2 final images.
# Built-in Restrict# ns & User-Friendly Logic
This skill strictly avoids low-quality scraping behaviors:
No infinite page scrolling
No mass bulk image scraping
No fake / invented original source URLs
No quality-compressing shortcuts
# Special handling rules:
If Pinterest login is required: Pause workflow and return control to you to finish authentication manually
If search results are scarce: Only preserve qualified high-quality images, will not fill quota with low-standard pictures

# 中文说明
pinterest-interior-design-skill
Pinterest 室内设计灵感搜图与精选工具，支持候选图管理、来源溯源、最终选图操作
# 功能简介
pinterest-interior-design-skill 是面向室内设计灵感搜集的 Codex 工具，依托已登录的 Chrome / Pinterest 会话执行可控可视化搜图，批量产出少量精修候选图集，完整留存图片来源元数据，支持预览图排版、可撤回式最终选图。
# 适用场景
室内氛围板、设计提案素材、空间风格参考、材质灵感、高端视觉方案筛选
# 默认执行流程
解析用户设计需求
生成精简中英双语搜索关键词方案
驱动 Chrome 执行单次精准定向搜图
截取当前可视范围内 8–16 张候选效果图
完整保存原图文件、来源链接、素材编号
按匹配度对图片自动排序分级
留存综合最优的精选定稿图
# Codex 调用示例
直接使用标识 $pinterest-interior-design-skill 调用工具
# 示例指令：
使用 $pinterest-interior-design-skill 搜索现代东方轻奢客厅实景参考图，保留 2 张最终精选图片
# 安全与质量约束
工具规避粗暴爬虫行为：
不会无限下滑加载页面
不批量无差别抓取全部图片
不伪造、篡改原图来源地址
不使用压缩画质等降质捷径
# 特殊场景处理：
若 Pinterest 触发登录校验：暂停流程，交还操作权限给用户手动完成登录
若检索素材数量不足：仅留存达标优质图，不会放宽标准凑齐数量
