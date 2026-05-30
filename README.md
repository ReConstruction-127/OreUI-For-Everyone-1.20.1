<img width="165" height="20" alt="logo" src="https://github.com/user-attachments/assets/e3b6b662-ca36-4076-ac68-0b76534ae1a6" />

本资源包将AE2的UI风格移植到了其他模组上

https://www.curseforge.com/minecraft/texture-packs/oreui-for-everyone/

欢迎您制作其他模组的兼容，您可以把你的名字及贡献写到 `contributor.csv` 中

关于适用于Windows10/11的OreUI For Windows ，请见https://github.com/ReConstruction-127/OreUI-For-Windows

### 构建/开发

要在本地进行构建, 您需要:
1. 克隆/下载本仓库
2. 使用终端在仓库根目录执行 `./srdk build`
3. 完成! 现在您可以在 `./build/` 文件夹中找到构建产物

要进行开发, 您需要:
1. 克隆/下载本仓库
2. 使用您的启动器 *(推荐使用HMCL)* 安装一个版本 (推荐打开版本隔离)
   > 如果您希望使用自动重载特性, 请一并安装 [ShulkerRRT](https://www.mcmod.cn/class/21516.html)
3. 在 `./shulker/tasks/`  目录下新建 `./settings.lvt`, 用于设定游戏目录, 例如:
    ```lvt
    var gameRoot "K:\games\.minecraft\versions\1.21.1-NeoForge"
    var targetPath "^gameRoot^\resourcepacks\debugging"
    ```
   > *其中, `gameRoot` 是您刚才安装的版本的工作目录, 而 `targetPath` 则是运行时的部署目标*
4. 使用启动器的导出启动脚本功能, 导出 `client.ps1` PowerShell脚本, 放置于 `./shulker/local/` 下

    > [!TIP]
    > 如果您的启动器不支持导出启动脚本, 也没关系! 您可以使用 `./srdk monitor` 来部署并开始监听变更, 您只需要在您的启动器手动启动客户端即可


5. 完成! 现在您可以使用终端执行 `./srdk dev` 来启动您刚才安装的客户端, 项目将会被自动部署到位
   > 您可以尝试改动 `./src/` 下的任意文件, 更改将会被自动同步, 如果是psd文件, 将自动转换为png并同步
   >
   > 如果您还安装了 ShulkerRRT, 那么同步完成后 srdk将会自动通知客户端重载资源