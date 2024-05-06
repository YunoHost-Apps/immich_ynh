<!--
注意：此 README 由 <https://github.com/YunoHost/apps/tree/master/tools/readme_generator> 自动生成
请勿手动编辑。
-->

# YunoHost 上的 Immich

[![集成程度](https://dash.yunohost.org/integration/immich.svg)](https://dash.yunohost.org/appci/app/immich) ![工作状态](https://ci-apps.yunohost.org/ci/badges/immich.status.svg) ![维护状态](https://ci-apps.yunohost.org/ci/badges/immich.maintain.svg)

[![使用 YunoHost 安装 Immich](https://install-app.yunohost.org/install-with-yunohost.svg)](https://install-app.yunohost.org/?app=immich)

*[阅读此 README 的其它语言版本。](./ALL_README.md)*

> *通过此软件包，您可以在 YunoHost 服务器上快速、简单地安装 Immich。*  
> *如果您还没有 YunoHost，请参阅[指南](https://yunohost.org/install)了解如何安装它。*

## 概况

Self-hosted photo and video management solution.

### Features

- Simple-to-use backup tool with a native mobile app that can view photos and videos efficiently ;
- Easy-to-use and friendly interface ;


**分发版本：** 1.103.1~ynh2

## 截图

![Immich 的截图](./doc/screenshots/immich-screenshots.png)

## 免责声明 / 重要信息

This package provides support for the JPEG, PNG, WebP, AVIF (limited to 8-bit depth), TIFF, GIF and SVG (input) image formats.
HEIC/HEIF file format is not supported (see cf. https://github.com/YunoHost-Apps/immich_ynh/issues/40#issuecomment-2096788600).

## 文档与资源

- 官方应用网站： <https://immich.app>
- 官方用户文档： <https://github.com/immich-app/immich#getting-started>
- 官方管理文档： <https://github.com/immich-app/immich#getting-started>
- 上游应用代码库： <https://github.com/immich-app/immich>
- YunoHost 商店： <https://apps.yunohost.org/app/immich>
- 报告 bug： <https://github.com/YunoHost-Apps/immich_ynh/issues>

## 开发者信息

请向 [`testing` 分支](https://github.com/YunoHost-Apps/immich_ynh/tree/testing) 发送拉取请求。

如要尝试 `testing` 分支，请这样操作：

```bash
sudo yunohost app install https://github.com/YunoHost-Apps/immich_ynh/tree/testing --debug
或
sudo yunohost app upgrade immich -u https://github.com/YunoHost-Apps/immich_ynh/tree/testing --debug
```

**有关应用打包的更多信息：** <https://yunohost.org/packaging_apps>