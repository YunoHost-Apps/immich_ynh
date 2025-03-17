<!--
Ohart ongi: README hau automatikoki sortu da <https://github.com/YunoHost/apps/tree/master/tools/readme_generator>ri esker
EZ editatu eskuz.
-->

# Immich YunoHost-erako

[![Integrazio maila](https://apps.yunohost.org/badge/integration/immich)](https://ci-apps.yunohost.org/ci/apps/immich/)
![Funtzionamendu egoera](https://apps.yunohost.org/badge/state/immich)
![Mantentze egoera](https://apps.yunohost.org/badge/maintained/immich)

[![Instalatu Immich YunoHost-ekin](https://install-app.yunohost.org/install-with-yunohost.svg)](https://install-app.yunohost.org/?app=immich)

*[Irakurri README hau beste hizkuntzatan.](./ALL_README.md)*

> *Pakete honek Immich YunoHost zerbitzari batean azkar eta zailtasunik gabe instalatzea ahalbidetzen dizu.*  
> *YunoHost ez baduzu, kontsultatu [gida](https://yunohost.org/install) nola instalatu ikasteko.*

## Aurreikuspena

Self-hosted photo and video management solution.

### Features

- Simple-to-use backup tool with a native mobile app that can view photos and videos efficiently ;
- Easy-to-use and friendly interface ;


**Paketatutako bertsioa:** 1.129.0~ynh2

## Pantaila-argazkiak

![Immich(r)en pantaila-argazkia](./doc/screenshots/immich-screenshots.png)

## :red_circle: Ezaugarri zalantzagarriak

- **Alfa softwarea**: Garapenaren hasierako fasean dago. Ezaugarri aldakor edo ezegonkorrak, erroreak eta segurtasun-arazoak izan ditzazke.

## Dokumentazioa eta baliabideak

- Aplikazioaren webgune ofiziala: <https://immich.app>
- Erabiltzaileen dokumentazio ofiziala: <https://github.com/immich-app/immich#getting-started>
- Administratzaileen dokumentazio ofiziala: <https://github.com/immich-app/immich#getting-started>
- Jatorrizko aplikazioaren kode-gordailua: <https://github.com/immich-app/immich>
- YunoHost Denda: <https://apps.yunohost.org/app/immich>
- Eman errore baten berri: <https://github.com/YunoHost-Apps/immich_ynh/issues>

## Garatzaileentzako informazioa

Bidali `pull request`a [`testing` abarrera](https://github.com/YunoHost-Apps/immich_ynh/tree/testing).

`testing` abarra probatzeko, ondorengoa egin:

```bash
sudo yunohost app install https://github.com/YunoHost-Apps/immich_ynh/tree/testing --debug
edo
sudo yunohost app upgrade immich -u https://github.com/YunoHost-Apps/immich_ynh/tree/testing --debug
```

**Informazio gehiago aplikazioaren paketatzeari buruz:** <https://yunohost.org/packaging_apps>
