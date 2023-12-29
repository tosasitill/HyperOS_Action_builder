#!/bin/bash

# hyperOS_port project

# For V-AB Devices

# Based on Android 14 HyperOS

# tosasitill made with love 0202 & 0227

# 2023.12.26

build_user="Bruce Teng, tosasitill"
build_host="tosasitill's 编译服务器 簇N.1_S.2"

# 底包和移植包为外部参数传入
baserom="$1"
portrom="$2"

work_dir=$(pwd)
tools_dir=${work_dir}/bin/$(uname)/$(uname -m)
export PATH=$(pwd)/bin/$(uname)/$(uname -m)/:$PATH

# 定义颜色输出函数
# Define color output function
error() {
    if [ "$#" -eq 2 ]; then
        
        if [[ "$LANG" == zh_CN* ]]; then
            echo -e \[$(date +%m%d-%T)\] "\033[1;31m"$1"\033[0m"
        elif [[ "$LANG" == en* ]]; then
            echo -e \[$(date +%m%d-%T)\] "\033[1;31m"$2"\033[0m"
        fi
    elif [ "$#" -eq 1 ]; then
        echo -e \[$(date +%m%d-%T)\] "\033[1;31m"$1"\033[0m"
    else
        echo "Usage: error <Chinese> <English>"
    fi
}

yellow() {
    if [ "$#" -eq 2 ]; then
        
        if [[ "$LANG" == zh_CN* ]]; then
            echo -e \[$(date +%m%d-%T)\] "\033[1;33m"$1"\033[0m"
        elif [[ "$LANG" == en* ]]; then
            echo -e \[$(date +%m%d-%T)\] "\033[1;33m"$2"\033[0m"
        fi
    elif [ "$#" -eq 1 ]; then
        echo -e \[$(date +%m%d-%T)\] "\033[1;33m"$1"\033[0m"
    else
        echo "Usage: yellow <Chinese> <English>"
    fi
}

blue() {
    if [ "$#" -eq 2 ]; then
        
        if [[ "$LANG" == zh_CN* ]]; then
            echo -e \[$(date +%m%d-%T)\] "\033[1;34m"$1"\033[0m"
        elif [[ "$LANG" == en* ]]; then
            echo -e \[$(date +%m%d-%T)\] "\033[1;34m"$2"\033[0m"
        fi
    elif [ "$#" -eq 1 ]; then
        echo -e \[$(date +%m%d-%T)\] "\033[1;34m"$1"\033[0m"
    else
        echo "Usage: blue <Chinese> <English>"
    fi
}

green() {
    if [ "$#" -eq 2 ]; then
        if [[ "$LANG" == zh_CN* ]]; then
            echo -e \[$(date +%m%d-%T)\] "\033[1;32m"$1"\033[0m"
        elif [[ "$LANG" == en* ]]; then
            echo -e \[$(date +%m%d-%T)\] "\033[1;32m"$2"\033[0m"
        fi
    elif [ "$#" -eq 1 ]; then
        echo -e \[$(date +%m%d-%T)\] "\033[1;32m"$1"\033[0m"
    else
        echo "Usage: green <Chinese> <English>"
    fi
}

shopt -s expand_aliases
if [[ "$OSTYPE" == "darwin"* ]]; then
    yellow "检测到Mac，设置alias" "macOS detected,setting alias"
    alias tr=gtr
    alias sed=gsed
    alias grep=ggrep
    alias du=gdu
    alias date=gdate
    #alias find=gfind
fi

#检查必需命令是否缺少
#Check for the existence of the requirements command, proceed if it exists, or abort otherwise.
exists() {
    command -v "$1" > /dev/null 2>&1
}

abort() {
    error "--> Missing $1 abort! please run ./setup.sh first (sudo is required on Linux system)"
    error "--> 命令 $1 缺失!请重新运行setup.sh (Linux系统sudo ./setup.sh)"
    exit 1
}

check() {
    for b in "$@"; do
        exists "$b" || abort "$b"
    done
}

check unzip aria2c 7z zip java zipalign python3 zstd bc

# 向 apk 或 jar 文件中替换 smali 代码，不支持资源补丁
# $1: 目标 apk/jar 文件
# $2: 目标 smali 文件(支持带相对路径的smali文件)
# $3: 被替换值
# $4: 替换值
patch_smali() {
    targetfilefullpath=$(find build/portrom/images -type f -name $1)
    targetfilename=$(basename $targetfilefullpath)
    if [ -f $targetfilefullpath ];then
        yellow "正在修改 $targetfilename" "Modifying $targetfilename"
        foldername=${targetfilename%.*}
        rm -rf tmp/$foldername/
        mkdir -p tmp/$foldername/
        cp -rf $targetfilefullpath tmp/$foldername/
        7z x -y tmp/$foldername/$targetfilename *.dex -otmp/$foldername >/dev/null
        for dexfile in tmp/$foldername/*.dex;do
            smalifname=${dexfile%.*}
            smalifname=$(echo $smalifname | cut -d "/" -f 3)
            java -jar bin/apktool/baksmali.jar d --api ${port_android_sdk} ${dexfile} -o tmp/$foldername/$smalifname 2>&1 || error " Baksmaling 失败" "Baksmaling failed"
        done
        if [[ $2 == *"/"* ]];then
            targetsmali=$(find tmp/$foldername/*/$(dirname $2) -type f -name $(basename $2))
        else
            targetsmali=$(find tmp/$foldername -type f -name $2)
        fi
        if [ -f $targetsmali ];then
            smalidir=$(echo $targetsmali |cut -d "/" -f 3)
            yellow "I: 开始patch目标 ${smalidir}" "Target ${smalidir} Found"
            search_pattern=$3
            repalcement_pattern=$4
            sed -i "s/$search_pattern/$repalcement_pattern/g" $targetsmali
            java -jar bin/apktool/smali.jar a --api ${port_android_sdk} tmp/$foldername/${smalidir} -o tmp/$foldername/${smalidir}.dex > /dev/null 2>&1 || error " Smaling 失败" "Smaling failed"
            pushd tmp/$foldername/ >/dev/null || exit
            7z a -y -mx0 -tzip $targetfilename ${smalidir}.dex  > /dev/null 2>&1 || error "修改$targetfilename失败" "Failed to modify $targetfilename"
            popd >/dev/null || exit
            yellow "修补$targetfilename 完成"
            if [[ $targetfilename == *.apk ]]; then
                yellow "检测到apk，进行zipalign处理。。" "APK file detected, initiating ZipAlign process..."
                rm -rf ${targetfilefullpath}

                # Align moddified APKs, to avoid error "Targeting R+ (version 30 and above) requires the resources.arsc of installed APKs to be stored uncompressed and aligned on a 4-byte boundary" 
                zipalign -p -f -v 4 tmp/$foldername/$targetfilename ${targetfilefullpath} > /dev/null 2>&1 || error "zipalign错误，请检查原因。" "zipalign error,please check for any issues"
                yellow "apk zipalign处理完成" "APK ZipAlign process completed."
                yellow "复制APK到目标位置：${targetfilefullpath}" "Copying APK to target ${targetfilefullpath}"
            else
                yellow "复制修改文件到目标位置：${targetfilefullpath}" "Copying file to target ${targetfilefullpath}"
                cp -rf tmp/$foldername/$targetfilename ${targetfilefullpath}
            fi
        fi
    fi

}
#check if a prperty is avaialble
is_property_exists () {
    if [ $(grep -c "$1" "$2") -ne 0 ]; then
        return 0
    else
        return 1
    fi
}

# 移植的分区，可在 bin/port_config 中更改
port_partition=$(grep "partition_to_port" bin/port_config |cut -d '=' -f 2)
#super_list=$(grep "super_list" bin/port_config |cut -d '=' -f 2)
repackext4=$(grep "repack_with_ext4" bin/port_config |cut -d '=' -f 2)
brightness_fix_method=$(grep "brightness_fix_method" bin/port_config |cut -d '=' -f 2)

compatible_matrix_matches_enabled=$(grep "compatible_matrix_matches_check" bin/port_config | cut -d '=' -f 2)


green "开始自动移植操作"

# 检查为本地包还是链接
if [ ! -f "${baserom}" ] && [ "$(echo $baserom |grep http)" != "" ];then
    blue "底包为一个链接，正在尝试下载" "Download link detected, start downloding.."
    aria2c --max-download-limit=1024M --file-allocation=none -s10 -x10 -j10 "${baserom}"
    baserom=$(basename ${baserom} | sed 's/\?t.*//')
    if [ ! -f "${baserom}" ];then
        error "下载错误" "Download error!"
    fi
elif [ -f "${baserom}" ];then
    green "底包: ${baserom}" "BASEROM: ${baserom}"
else
    error "底包参数错误" "BASEROM: Invalid parameter"
    exit
fi

if [ ! -f "${portrom}" ] && [ "$(echo ${portrom} |grep http)" != "" ];then
    blue "移植包为一个链接，正在尝试下载"  "Download link detected, start downloding.."
    aria2c --check-certificate=false --max-download-limit=1024M --file-allocation=none -s10 -x10 -j10 ${portrom}
    portrom=$(basename ${portrom} | sed 's/\?t.*//')
    if [ ! -f "${portrom}" ];then
        error "下载错误" "Download error!"
    fi
elif [ -f "${portrom}" ];then
    green "移植包: ${portrom}" "PORTROM: ${portrom}"
else
    error "移植包参数错误" "PORTROM: Invalid parameter"
    exit
fi

if [ "$(echo $baserom |grep miui_)" != "" ];then
    device_code=$(basename $baserom |cut -d '_' -f 2)
else
    device_code="YourDevice"
fi

blue "正在检测ROM底包" "Validating BASEROM.."
if unzip -l ${baserom} | grep -q "payload.bin"; then
    baserom_type="payload"
    super_list="vendor mi_ext odm odm_dlkm system system_dlkm vendor_dlkm product product_dlkm system_ext"
elif unzip -l ${baserom} | grep -q "br$";then
    baserom_type="br"
    super_list="vendor mi_ext odm system product system_ext"
    
else
    error "底包中未发现payload.bin以及br文件，请使用MIUI官方包后重试" "payload.bin/new.br not found, please use HyperOS official OTA zip package."
    exit
fi

blue "开始检测ROM移植包" "Validating PORTROM.."
unzip -l ${portrom} |grep "payload.bin" 1>/dev/null 2>&1 || error "目标移植包没有payload.bin，请用MIUI官方包作为移植包" "payload.bin not found, please use HyperOS official OTA zip package."

green "ROM初步检测通过" "ROM validation passed."

if [[ "$portrom" =~ SHENNONG|HOUJI ]]; then
    is_shennong_houji_port=true
else
    is_shennong_houji_port=false
fi

blue "正在清理文件" "Cleaning up.."
for i in ${port_partition};do
    [ -d ./${i} ] && rm -rf ./${i}
done
sudo rm -rf app
sudo rm -rf tmp
sudo rm -rf config
sudo rm -rf build/baserom/
sudo rm -rf build/portrom/
find . -type d -name 'hyperos_*' |xargs rm -rf

green "文件清理完毕" "Files cleaned up."
mkdir -p build/baserom/images/
mkdir -p build/baserom/config/
mkdir -p build/portrom/images/
mkdir -p build/portrom/config/

# 提取分区
if [ ${baserom_type} = 'payload' ];then
    blue "正在提取底包 [payload.bin]" "Extracting files from BASEROM [payload.bin]"
    unzip ${baserom} payload.bin -d build/baserom > /dev/null 2>&1 ||error "解压底包 [payload.bin] 时出错" "Extracting [payload.bin] error"
    green "底包 [payload.bin] 提取完毕" "[payload.bin] extracted."
else
    blue "正在提取底包 [new.dat.br]" "Extracting files from BASEROM [*.new.dat.br]"
    unzip ${baserom} -d build/baserom  > /dev/null 2>&1 || error "解压底包 [new.dat.br]时出错" "Extracting [new.dat.br] error"
    green "底包 [new.dat.br] 提取完毕" "[new.dat.br] extracted."
fi

blue "正在提取移植包 [payload.bin]" "Extracting files from PROTROM [payload.bin]"
unzip ${portrom} payload.bin -d build/portrom  > /dev/null 2>&1 ||error "解压移植包 [payload.bin] 时出错"  "Extracting [payload.bin] error"
green "移植包 [payload.bin] 提取完毕" "[payload.bin] extracted."

if [ ${baserom_type} = 'payload' ];then

    blue "开始分解底包 [payload.bin]" "Unpacking [payload.bin]"
    payload-dumper-go -o build/baserom/images/ build/baserom/payload.bin >/dev/null 2>&1 ||error "分解底包 [payload.bin] 时出错" "Unpacking [payload.bin] failed"
else
    blue "开始分解底包 [new.dat.br]" "Unpacking [new.dat.br]"
        for i in ${super_list}; do 
            ${tools_dir}/brotli -d build/baserom/$i.new.dat.br >/dev/null 2>&1
            sudo python3 ${tools_dir}/sdat2img.py build/baserom/$i.transfer.list build/baserom/$i.new.dat build/baserom/images/$i.img >/dev/null 2>&1
            rm -rf $i.new.data.* $i.transfer.list $i.patch.*
        done
fi

for part in system system_dlkm system_ext product product_dlkm mi_ext ;do
    if [[ -f build/baserom/images/${part}.img ]];then 
        if [[ $($tools_dir/gettype -i build/baserom/images/${part}.img) == "ext" ]];then
            pack_type=EXT
            blue "正在分解底包 ${part}.img [ext]" "Extracing ${part}.img [ext]"
            sudo python3 bin/imgextractor/imgextractor.py build/baserom/images/${part}.img >/dev/null 2>&1
            blue "分解底包 [${part}.img] 完成" "${part}.img [ext] extracted."
            mv ${part} build/baserom/images/
            
        elif [[ $($tools_dir/gettype -i build/baserom/images/${part}.img) == "erofs" ]]; then
            pack_type=EROFS
            blue "正在分解底包 ${part}.img [erofs]" "Extracing ${part}.img [erofs]"
            extract.erofs -x -i build/baserom/images/${part}.img  > /dev/null 2>&1 || error "分解 ${part}.img 失败" "Extracting ${part}.img failed."
            blue "分解底包 [${part}.img][erofs] 完成" "${part}.img [erofs] extracted."
            mv ${part} build/baserom/images/
            
        fi
        mv config/*${part}* build/baserom/config/
    fi
    
done

for image in vendor odm vendor_dlkm odm_dlkm;do
    if [ -f build/baserom/images/${image}.img ];then
        cp -rf build/baserom/images/${image}.img build/portrom/images/${image}.img
    fi
done

# 分解镜像
green "开始提取逻辑分区镜像" "Starting extract partition from img"

for part in ${super_list};do
    if [[ $part =~ ^(vendor|odm|vendor_dlkm|odm_dlkm)$ ]] && [[ -f "build/portrom/images/$part.img" ]]; then
        blue "从底包中提取 [${part}]分区 ..." "Extracting [${part}] from BASEROM"
    else
        blue "payload.bin 提取 [${part}] 分区..." "Extracting [${part}] from payload.bin"
        payload-dumper-go -p ${part} -o build/portrom/images/ build/portrom/payload.bin >/dev/null 2>&1 ||error "提取移植包 [${part}] 分区时出错" "Extracting partition [${part}] error."
    fi
    if [ -f "${work_dir}/build/portrom/images/${part}.img" ];then
        blue "开始提取 ${part}.img" "Extracting ${part}.img"
        
        if [[ $($tools_dir/gettype -i build/portrom/images/${part}.img) == "ext" ]];then
            pack_type=EXT
            python3 bin/imgextractor/imgextractor.py build/portrom/images/${part}.img > /dev/null 2>&1 || error "提取${part}失败" "Extracting partition ${part} failed"
            mv ${part} build/portrom/images/
            mkdir -p build/portrom/images/${part}/lost+found
            mv config/*${part}* build/portrom/config/
            
            rm -rf build/portrom/images/${part}.img

            green "提取 [${part}] [ext]镜像完毕" "Extracting [${part}].img [ext] done"
        elif [[ $(gettype -i build/portrom/images/${part}.img) == "erofs" ]];then
            pack_type=EROFS
            green "移植包为 [erofs] 文件系统" "PORTROM filesystem: [erofs]. "
            [ "${repackext4}" = "true" ] && pack_type=EXT
            extract.erofs -x -i build/portrom/images/${part}.img  > /dev/null 2>&1 || error "提取${part}失败" "Extracting ${part} failed"
            mv ${part} build/portrom/images/
            mkdir -p build/portrom/images/${part}/lost+found
            mv config/*${part}* build/portrom/config/
            rm -rf build/portrom/images/${part}.img

            green "提取移植包[${part}] [erofs]镜像完毕" "Extracting ${part} [erofs] done."
        fi
        
    fi
done
rm -rf config

blue "正在获取ROM参数" "Fetching ROM build prop."

# 安卓版本
base_android_version=$(< build/portrom/images/vendor/build.prop grep "ro.vendor.build.version.release" |awk 'NR==1' |cut -d '=' -f 2)
port_android_version=$(< build/portrom/images/system/system/build.prop grep "ro.system.build.version.release" |awk 'NR==1' |cut -d '=' -f 2)
green "安卓版本: 底包为[Android ${base_android_version}], 移植包为 [Android ${port_android_version}]" "Android Version: BASEROM:[Android ${base_android_version}], PORTROM [Android ${port_android_version}]"

# SDK版本
base_android_sdk=$(< build/portrom/images/vendor/build.prop grep "ro.vendor.build.version.sdk" |awk 'NR==1' |cut -d '=' -f 2)
port_android_sdk=$(< build/portrom/images/system/system/build.prop grep "ro.system.build.version.sdk" |awk 'NR==1' |cut -d '=' -f 2)
green "SDK 版本: 底包为 [SDK ${base_android_sdk}], 移植包为 [SDK ${port_android_sdk}]" "SDK Verson: BASEROM: [SDK ${base_android_sdk}], PORTROM: [SDK ${port_android_sdk}]"

# ROM版本
base_rom_version=$(< build/portrom/images/vendor/build.prop grep "ro.vendor.build.version.incremental" |awk 'NR==1' |cut -d '=' -f 2)

#HyperOS版本号获取
port_mios_version_incremental=$(< build/portrom/images/mi_ext/etc/build.prop grep "ro.mi.os.version.incremental" | awk 'NR==1' | cut -d '=' -f 2)
#替换机型代号,比如小米10：UNBCNXM -> UJBCNXM

port_device_code=$(echo $port_mios_version_incremental | cut -d "." -f 5)

if [[ $port_mios_version_incremental == *DEV* ]];then
    yellow "检测到开发板，跳过修改版本代码" "Dev deteced,skip replacing codename"
    port_rom_version=$(echo $port_mios_version_incremental)
else
    base_device_code=U$(echo $base_rom_version | cut -d "." -f 5 | cut -c 2-)
    port_rom_version=$(echo $port_mios_version_incremental | sed "s/$port_device_code/$base_device_code/")
fi
green "ROM 版本: 底包为 [${base_rom_version}], 移植包为 [${port_rom_version}]" "ROM Version: BASEROM: [${base_rom_version}], PORTROM: [${port_rom_version}] "

# 代号
base_rom_code=$(< build/portrom/images/vendor/build.prop grep "ro.product.vendor.device" |awk 'NR==1' |cut -d '=' -f 2)
port_rom_code=$(< build/portrom/images/product/etc/build.prop grep "ro.product.product.name" |awk 'NR==1' |cut -d '=' -f 2)
green "机型代号: 底包为 [${base_rom_code}], 移植包为 [${port_rom_code}]" "Device Code: BASEROM: [${base_rom_code}], PORTROM: [${port_rom_code}]"

if grep -q "ro.build.ab_update=true" build/portrom/images/vendor/build.prop;  then
    is_ab_device=true
else
    is_ab_device=false

fi

baseAospFrameworkResOverlay=$(find build/baserom/images/product -type f -name "AospFrameworkResOverlay.apk")
portAospFrameworkResOverlay=$(find build/portrom/images/product -type f -name "AospFrameworkResOverlay.apk")
if [ -f "${baseAospFrameworkResOverlay}" ] && [ -f "${portAospFrameworkResOverlay}" ];then
    blue "正在替换 [AospFrameworkResOverlay.apk]" "Replacing [AospFrameworkResOverlay.apk]" 
    cp -rf ${baseAospFrameworkResOverlay} ${portAospFrameworkResOverlay}
fi

#baseAospWifiResOverlay=$(find build/baserom/images/product -type f -name "AospWifiResOverlay.apk")
##portAospWifiResOverlay=$(find build/portrom/images/product -type f -name "AospWifiResOverlay.apk")
#if [ -f ${baseAospWifiResOverlay} ] && [ -f ${portAospWifiResOverlay} ];then
#    blue "正在替换 [AospWifiResOverlay.apk]"
#    cp -rf ${baseAospWifiResOverlay} ${portAospWifiResOverlay}
#fi

baseDevicesAndroidOverlay=$(find build/baserom/images/product -type f -name "DevicesAndroidOverlay.apk")
portDevicesAndroidOverlay=$(find build/portrom/images/product -type f -name "DevicesAndroidOverlay.apk")
if [ -f "${baseDevicesAndroidOverlay}" ] && [ -f "${portDevicesAndroidOverlay}" ];then
    blue "正在替换 [DevicesAndroidOverlay.apk]" "Replacing [DevicesAndroidOverlay.apk]"
    cp -rf ${baseDevicesAndroidOverlay} ${portDevicesAndroidOverlay}
fi

baseDevicesOverlay=$(find build/baserom/images/product -type f -name "DevicesOverlay.apk")
portDevicesOverlay=$(find build/portrom/images/product -type f -name "DevicesOverlay.apk")
if [ -f "${baseDevicesOverlay}" ] && [ -f "${portDevicesOverlay}" ];then
    blue "正在替换 [DevicesOverlay.apk]" "Replacing [DevicesOverlay.apk]"
    cp -rf ${baseDevicesOverlay} ${portDevicesOverlay}
fi

targetDevicesAndroidOverlay=$(find build/portrom/images/product -type f -name "DevicesAndroidOverlay.apk")
if [[ -f $targetDevicesAndroidOverlay ]]; then
    mkdir tmp/  
    filename=$(basename $targetDevicesAndroidOverlay)
    yellow "修复息屏和屏下指纹问题" "Fixing AOD issue: $filename ..."
    targetDir=$(echo "$filename" | sed 's/\..*$//')
    bin/apktool/apktool d $targetDevicesAndroidOverlay -o tmp/$targetDir -f > /dev/null 2>&1
    search_pattern="com\.miui\.aod\/com\.miui\.aod\.doze\.DozeService"
    replacement_pattern="com\.android\.systemui\/com\.android\.systemui\.doze\.DozeService"
    for xml in $(find tmp/$targetDir -type f -name "*.xml");do
        sed -i "s/$search_pattern/$replacement_pattern/g" $xml
    done
    bin/apktool/apktool b tmp/$targetDir -o tmp/$filename > /dev/null 2>&1 || error "apktool 打包失败" "apktool mod failed"
    cp -rfv tmp/$filename $targetDevicesAndroidOverlay
    rm -rf tmp
fi

baseSettingsRroDeviceHideStatusBarOverlay=$(find build/baserom/images/product -type f -name "SettingsRroDeviceHideStatusBarOverlay.apk")
portSettingsRroDeviceHideStatusBarOverlay=$(find build/portrom/images/product -type f -name "SettingsRroDeviceHideStatusBarOverlay.apk")
if [ -f "${baseSettingsRroDeviceHideStatusBarOverlay}" ] && [ -f "${portSettingsRroDeviceHideStatusBarOverlay}" ];then
    blue "正在替换 [SettingsRroDeviceHideStatusBarOverlay.apk]" "Replacing [SettingsRroDeviceHideStatusBarOverlay.apk]"
    cp -rf ${baseSettingsRroDeviceHideStatusBarOverlay} ${portSettingsRroDeviceHideStatusBarOverlay}
fi

baseMiuiBiometricResOverlay=$(find build/baserom/images/product -type f -name "MiuiBiometricResOverlay.apk")
portMiuiBiometricResOverlay=$(find build/portrom/images/product -type f -name "MiuiBiometricResOverlay.apk")
if [ -f "${baseMiuiBiometricResOverlay}" ] && [ -f "${portMiuiBiometricResOverlay}" ];then
    blue "正在替换 [MiuiBiometricResOverlay.apk]" "Replacing [MiuiBiometricResOverlay.apk]"
    cp -rf ${baseMiuiBiometricResOverlay} ${portMiuiBiometricResOverlay}
fi

# displayconfig id
if [[ "$brightness_fix_method" == "port" ]];then
    for display_id_file in $(find build/baserom/images/product/etc/displayconfig/ -type f -name "display_id*.xml");do
        display_id=$(basename "$display_id_file")
        blue "复制display_id $display_id 到移植包" "Copying display_id $display_id to PortROM"
        cp -rf "$(ls -1 build/portrom/images/product/etc/displayconfig/display_id_*.xml | head -n 1)" build/portrom/images/product/etc/displayconfig/"$display_id"
    done
elif [[ "$brightness_fix_method" == "stock" ]];then
        rm -rf build/portrom/images/product/etc/displayconfig/display_id*.xml
        cp -rf build/baserom/images/product/etc/displayconfig/display_id*.xml build/portrom/images/product/etc/displayconfig/
        baseMiuiFrameworkResOverlay=$(find build/baserom/images/product -type f -name "MiuiFrameworkResOverlay.apk")
        portMiuiFrameworkResOverlay=$(find build/portrom/images/product -type f -name "MiuiFrameworkResOverlay.apk")
        if [ -f ${baseMiuiFrameworkResOverlay} ] && [ -f ${portMiuiFrameworkResOverlay} ];then
            blue "正在替换 [MiuiFrameworkResOverlay.apk]"
            cp -rf ${baseMiuiFrameworkResOverlay} ${portMiuiFrameworkResOverlay}
        fi
fi

green "正在修复 NFC"

cp -rf devices/nfc/bin/hw/vendor.nxp.hardware.nfc@2.0-service build/portrom/images/vendor/bin/hw/
cp -rf devices/nfc/bin/nqnfcinfo build/portrom/images/vendor/bin/
cp -rf devices/nfc/etc/libnfc-*.conf build/portrom/images/vendor/etc/
cp -rf devices/nfc/etc/init/vendor.nxp.hardware.nfc@2.0-service.rc build/portrom/images/vendor/etc/init/
cp -rf devices/nfc/etc/sn100u_nfcon.pnscr build/portrom/images/vendor/etc/
cp -rf devices/nfc/etc/permissions/android.*.xml build/portrom/images/vendor/etc/permissions/
cp -rf devices/nfc/firmware/96_nfcCard_RTP.bin build/portrom/images/vendor/firmware/
cp -rf devices/nfc/firmware/98_nfcCardSlow_RTP.bin build/portrom/images/vendor/firmware/
cp -rf devices/nfc/lib/nfc_nci.nqx.default.hw.so build/portrom/images/vendor/lib/
cp -rf devices/nfc/lib/vendor.nxp.hardware.nfc@2.0.so build/portrom/images/vendor/lib/
cp -rf devices/nfc/lib/modules/nfc_i2c.ko build/portrom/images/vendor/lib/modules/
cp -rf devices/nfc/lib/modules/5.4-gki/nfc_i2c.ko build/portrom/images/vendor/lib/modules/5.4-gki/
cp -rf devices/nfc/lib64/nfc_nci.nqx.default.hw.so build/portrom/images/vendor/lib64/
cp -rf devices/nfc/lib64/vendor.nxp.hardware.nfc@2.0.so build/portrom/images/vendor/lib64/

green "NFC修复成功"

# device_features
blue "复制设备特性XML文件"   
cp -rf  build/baserom/images/product/etc/device_features/* build/portrom/images/product/etc/device_features/

# A13-14 启动校验破解
blue "触控优化" "Touch optimization"
echo "ro.surface_flinger.use_content_detection_for_refresh_rate=true" >> build/portrom/images/vendor/default.prop
echo "ro.surface_flinger.set_idle_timer_ms=2147483647" >> build/portrom/images/vendor/default.prop
echo "ro.surface_flinger.set_touch_timer_ms=2147483647" >> build/portrom/images/vendor/default.prop
echo "ro.surface_flinger.set_display_power_timer_ms=2147483647" >> build/portrom/images/vendor/default.prop
APKTOOL="java -jar bin/apktool/apktool.jar"
mkdir -p tmp/
blue "开始移除 Android 签名校验" "Disalbe Android 14 Apk Signature Verfier"
cp -rf build/portrom/images/system/system/framework/services.jar tmp/services.apk
pushd tmp/
$APKTOOL d -q services.apk
target_method='getMinimumSignatureSchemeVersionForTargetSdk'
find services/smali_classes2/com/android/server/pm/ services/smali_classes2/com/android/server/pm/pkg/parsing/ -type f -maxdepth 1 -name "*.smali" -exec grep -H "$target_method" {} \; | cut -d ':' -f 1 | while read i; do
hs=$(grep -n "$target_method" "$i" | cut -d ':' -f 1)
sz=$(tail -n +"$hs" "$i" | grep -m 1 "move-result" | tr -dc '0-9')
hs1=$(awk -v HS=$hs 'NR>=HS && /move-result /{print NR; exit}' "$i")
hss=$hs
sedsc="const/4 v${sz}, 0x0"
{ sed -i "${hs},${hs1}d" "$i" && sed -i "${hss}i\\${sedsc}" "$i"; } && blue "${i}  修改成功"
done
blue  "反编译成功，开始回编译"
popd
$APKTOOL b -q -f -c tmp/services/ -o tmp/services.jar

cp -rfv tmp/services.jar build/portrom/images/system/system/framework/services.jar
# 屏幕密度修修改
for prop in $(find build/baserom/images/product build/baserom/images/system -type f -name "build.prop");do
    base_rom_density=$(< "$prop" grep "ro.sf.lcd_density" |awk 'NR==1' |cut -d '=' -f 2)
    if [ "${base_rom_density}" != "" ];then
        green "底包屏幕密度值 ${base_rom_density}" "Screen density: ${base_rom_density}"
        break 
    fi
done

# 未在底包找到则默认440,如果是其他值可自己修改
[ -z ${base_rom_density} ] && base_rom_density=440

found=0
for prop in $(find build/portrom/images/product build/portrom/images/system -type f -name "build.prop");do
    if grep -q "ro.sf.lcd_density" ${prop};then
        sed -i "s/ro.sf.lcd_density=.*/ro.sf.lcd_density=${base_rom_density}/g" ${prop}
        found=1
    fi
    sed -i "s/persist.miui.density_v2=.*/persist.miui.density_v2=${base_rom_density}/g" ${prop}
done

if [ $found -eq 0  ]; then
        blue "未找到ro.fs.lcd_density，build.prop新建一个值$base_rom_density" "ro.fs.lcd_density not found, create a new value ${base_rom_density} "
        echo "ro.sf.lcd_density=${base_rom_density}" >> build/portrom/images/product/etc/build.prop
fi


# 人脸
baseMiuiBiometric=$(find build/baserom/images/product/app -type d -name "MiuiBiometric*")
portMiuiBiometric=$(find build/portrom/images/product/app -type d -name "MiuiBiometric*")
if [ -d "${baseMiuiBiometric}" ] && [ -d "${portMiuiBiometric}" ];then
    yellow "查找MiuiBiometric" "Searching and Replacing MiuiBiometric.."
    rm -rf ./${portMiuiBiometric}/*
    cp -rf ./${baseMiuiBiometric}/* ${portMiuiBiometric}/
else
    if [ -d "${baseMiuiBiometric}" ] && [ ! -d "${portMiuiBiometric}" ];then
        blue "未找到MiuiBiometric，替换为原包" "MiuiBiometric is missing, copying from base..."
        cp -rf ${baseMiuiBiometric} build/portrom/images/product/app/
    fi
fi

#其他机型可能没有default.prop
for prop_file in $(find build/portrom/images/vendor/ -name "*.prop"); do
    vndk_version=$(< "$prop_file" grep "ro.vndk.version" | awk "NR==1" | cut -d '=' -f 2)
    if [ -n "$vndk_version" ]; then
        yellow "ro.vndk.version为$vndk_version" "ro.vndk.version found in $prop_file: $vndk_version"
        break  
    fi
done
base_vndk=$(find build/baserom/images/system_ext/apex -type f -name "com.android.vndk.v${vndk_version}.apex")
port_vndk=$(find build/portrom/images/system_ext/apex -type f -name "com.android.vndk.v${vndk_version}.apex")

if [ ! -f "${port_vndk}" ]; then
    yellow "apex不存在，从原包复制" "target apex is missing, copying from baserom"
    cp -rf "${base_vndk}" "build/portrom/images/system_ext/apex/"
fi

green "正在替换徕卡相机APK"
rm -rf build/portrom/images/product/priv-app/MiuiCamera
mkdir build/portrom/images/product/priv-app/MiuiCamera
cp -rf devices/MIUIcamera.apk build/portrom/images/product/priv-app/MiuiCamera/

green "修复GPU驱动卡顿"

#解决开机报错问题
targetVintf=$(find build/portrom/images/system_ext/etc/vintf -type f -name "manifest.xml")
if [ -f "$targetVintf" ]; then
    # Check if the file contains $vndk_version
    if grep -q "<version>$vndk_version</version>" "$targetVintf"; then
        yellow "${vndk_version}已存在，跳过修改" "The file already contains the version $vndk_version. Skipping modification."
    else
        # If it doesn't contain $vndk_version, then add it
        ndk_version="<vendor-ndk>\n     <version>$vndk_version</version>\n </vendor-ndk>"
        sed -i "/<\/vendor-ndk>/a$ndk_version" "$targetVintf"
        yellow "添加成功" "Version $vndk_version added to $targetVintf"
    fi
else
    blue "File $targetVintf not found."
fi

if [[ $(echo "$portrom") == *"DEV"* ]];then
    date_format_11_27_dev=$(echo "23.11.27" | awk -F'.' '{printf "20%02d-%02d-%02d", $1, $2, $3}')
    date_current_rom=$(echo "$portrom" | awk -F'[.]' '{print $3"."$4"."$5}' | awk -F'.' '{printf "20%02d-%02d-%02d", $1, $2, $3}')
    timestamp_11_27_dev=$(date -d "$date_format_11_27_dev" +%s)
    timestamp_current_rom=$(date -d "$date_current_rom" +%s)
fi


# 主题防恢复
if [ -f build/portrom/images/system/system/etc/init/hw/init.rc ];then
	sed -i '/on boot/a\'$'\n''    chmod 0731 \/data\/system\/theme' build/portrom/images/system/system/etc/init/hw/init.rc

yellow "删除多余的App" "Debloating..." 
# List of apps to be removed
debloat_apps=("MSA" "mab" "Updater" "MiuiUpdater" "MiService" "MIService" "SoterService" "Hybrid" "AnalyticsCore")

# Find all app directories once and store in an array
app_dirs=($(find build/portrom/images/product -type d -name "*${debloat_apps[@]}*"))

# Iterate through app directories and remove them
for app_dir in "${app_dirs[@]}"; do
    if [[ -d "$app_dir" ]]; then
        yellow "删除目录: $app_dir" "Removing directory: $app_dir"
        rm -rf "$app_dir"
    fi
done

# Remove additional directories and files in one command
rm -rf build/portrom/images/product/etc/auto-install* \
       build/portrom/images/product/data-app/*GalleryLockscreen* \
       build/portrom/images/system/verity_key \
       build/portrom/images/vendor/verity_key \
       build/portrom/images/product/verity_key \
       build/portrom/images/system/recovery-from-boot.p \
       build/portrom/images/vendor/recovery-from-boot.p \
       build/portrom/images/product/recovery-from-boot.p \
       build/portrom/images/product/media/theme/miui_mod_icons/com.google.android.apps.nbu* \
       build/portrom/images/product/media/theme/miui_mod_icons/dynamic/com.google.android.apps.nbu* >/dev/null 2>&1

# Create tmp/app directory
mkdir -p tmp/app

# List of apps to keep
kept_data_apps=("Weather" "DeskClock" "Gallery" "SoundRecorder" "ScreenRecorder" "Calculator" "CleanMaster" "Calendar" "Compass" "Notes" "MediaEditor" "Scanner" "XiaoAISpeechEngine" "wps-lite")

# Move kept apps to tmp/app directory
for app in "${kept_data_apps[@]}"; do
    mv build/portrom/images/product/data-app/*"${app}"* tmp/app/ >/dev/null 2>&1
done

# Clear and repopulate the data-app directory
rm -rf build/portrom/images/product/data-app/*
cp -rf tmp/app/* build/portrom/images/product/data-app

# Remove temporary directory
rm -rf tmp/app

# build.prop 修改
blue "正在修改 build.prop" "Modifying build.prop"
# change the locale to English
export LC_ALL=en_US.UTF-8
buildDate=$(date -u +"%a %b %d %H:%M:%S UTC %Y")
buildUtc=$(date +%s)
for i in $(find build/portrom/images -type f -name "build.prop");do
    blue "正在处理 ${i}" "modifying ${i}"
    sed -i "s/ro.build.date=.*/ro.build.date=${buildDate}/g" ${i}
    sed -i "s/ro.build.date.utc=.*/ro.build.date.utc=${buildUtc}/g" ${i}
    sed -i "s/ro.odm.build.date=.*/ro.odm.build.date=${buildDate}/g" ${i}
    sed -i "s/ro.odm.build.date.utc=.*/ro.odm.build.date.utc=${buildUtc}/g" ${i}
    sed -i "s/ro.vendor.build.date=.*/ro.vendor.build.date=${buildDate}/g" ${i}
    sed -i "s/ro.vendor.build.date.utc=.*/ro.vendor.build.date.utc=${buildUtc}/g" ${i}
    sed -i "s/ro.system.build.date=.*/ro.system.build.date=${buildDate}/g" ${i}
    sed -i "s/ro.system.build.date.utc=.*/ro.system.build.date.utc=${buildUtc}/g" ${i}
    sed -i "s/ro.product.build.date=.*/ro.product.build.date=${buildDate}/g" ${i}
    sed -i "s/ro.product.build.date.utc=.*/ro.product.build.date.utc=${buildUtc}/g" ${i}
    sed -i "s/ro.system_ext.build.date=.*/ro.system_ext.build.date=${buildDate}/g" ${i}
    sed -i "s/ro.system_ext.build.date.utc=.*/ro.system_ext.build.date.utc=${buildUtc}/g" ${i}
   
    sed -i "s/ro.product.device=.*/ro.product.device=${base_rom_code}/g" ${i}
    sed -i "s/ro.product.product.name=.*/ro.product.product.name=${base_rom_code}/g" ${i}
    sed -i "s/ro.product.odm.device=.*/ro.product.odm.device=${base_rom_code}/g" ${i}
    sed -i "s/ro.product.vendor.device=.*/ro.product.vendor.device=${base_rom_code}/g" ${i}
    sed -i "s/ro.product.system.device=.*/ro.product.system.device=${base_rom_code}/g" ${i}
    sed -i "s/ro.product.board=.*/ro.product.board=${base_rom_code}/g" ${i}
    sed -i "s/ro.product.system_ext.device=.*/ro.product.system_ext.device=${base_rom_code}/g" ${i}
    sed -i "s/persist.sys.timezone=.*/persist.sys.timezone=Asia\/Shanghai/g" ${i}
    sed -i "s/ro.product.mod_device=.*/ro.product.mod_device=${base_rom_code}/g" ${i}
    #全局替换device_code
    if [[ $port_mios_version_incremental != *DEV* ]];then
        sed -i "s/$port_device_code/$base_device_code/g" ${i}
    fi
    # 添加build user信息
    sed -i "s/ro.build.user=.*/ro.build.user=${build_user}/g" ${i}
    sed -i "s/ro.build.host=.*/ro.build.host=${build_host}/g" ${i}
    
done

# 修复各种疑难杂症
echo "ro.miui.cust_erofs=0" >> build/portrom/images/product/etc/build.prop
echo "ro.crypto.state=encrypted" >> build/portrom/images/system/system/build.prop
sed -i "s/persist\.sys\.millet\.cgroup1/#persist\.sys\.millet\.cgroup1/" build/portrom/images/vendor/build.prop

# Millet fix
blue "修复Millet" "Fix Millet"
# Function to update netlink in build.prop
update_netlink() {
  local netlink_version=$1
  local prop_file=$2

  if grep -q "ro.millet.netlink" "$prop_file"; then
    blue "找到ro.millet.netlink修改值为$netlink_version" "millet_netlink propery found, changing value to $netlink_version"
    sed -i "s/ro.millet.netlink=.*/ro.millet.netlink=$netlink_version/" "$prop_file"
  else
    blue "PORTROM未找到ro.millet.netlink值,添加为$netlink_version" "millet_netlink not found in portrom, adding new value $netlink_version"
    echo -e "ro.millet.netlink=$netlink_version\n" >> "$prop_file"
  fi
}

millet_netlink_version=$(grep "ro.millet.netlink" build/baserom/images/product/etc/build.prop | cut -d "=" -f 2)

if [[ -n "$millet_netlink_version" ]]; then
  update_netlink "$millet_netlink_version" "build/portrom/images/product/etc/build.prop"
else
  blue "原包未发现ro.millet.netlink值，请手动赋值修改(默认为29)" "ro.millet.netlink property value not found, change it manually(29 by default)."
  millet_netlink_version=29
  update_netlink "$millet_netlink_version" "build/portrom/images/product/etc/build.prop"
fi

#自定义替换
if [[ -d "devices/common" ]];then
    commonCamera=$(find devices/common -type f -name "MiuiCamera.apk")
    targetCamera=$(find build/portrom/images/product -type d -name "MiuiCamera")
    bootAnimationZIP=$(find devices/common -type f -name "bootanimation_${base_rom_density}.zip")
    targetAnimationZIP=$(find build/portrom/images/product -type f -name "bootanimation.zip")
    if [[ -f "$bootAnimationZIP" ]];then
        yellow "替换开机第二屏动画" "Repacling bootanimation.zip"
        cp -rfv $bootAnimationZIP $targetAnimationZIP
    fi
fi

# 去除avb校验
blue "去除avb校验" "Disable avb verification."
for fstab in $(find build/portrom/images/ -type f -name "fstab.*");do
    blue "Target: $fstab"
    sed -i "s/,avb_keys=.*avbpubkey//g" $fstab
    sed -i "s/,avb=vbmeta_system//g" $fstab
    sed -i "s/,avb=vbmeta_vendor//g" $fstab
    sed -i "s/,avb=vbmeta//g" $fstab
    sed -i "s/,avb//g" $fstab
done

# data 加密
remove_data_encrypt=$(grep "remove_data_encryption" bin/port_config |cut -d '=' -f 2)
if [ ${remove_data_encrypt} = "true" ];then
    blue "去除data加密"
    for fstab in $(find build/portrom/images -type f -name "fstab.*");do
		blue "Target: $fstab"
		sed -i "s/,fileencryption=aes-256-xts:aes-256-cts:v2+inlinecrypt_optimized+wrappedkey_v0//g" $fstab
		sed -i "s/,fileencryption=aes-256-xts:aes-256-cts:v2+emmc_optimized+wrappedkey_v0//g" $fstab
		sed -i "s/,fileencryption=aes-256-xts:aes-256-cts:v2//g" $fstab
		sed -i "s/,metadata_encryption=aes-256-xts:wrappedkey_v0//g" $fstab
		sed -i "s/,fileencryption=aes-256-xts:wrappedkey_v0//g" $fstab
		sed -i "s/,metadata_encryption=aes-256-xts//g" $fstab
		sed -i "s/,fileencryption=aes-256-xts//g" $fstab
        sed -i "s/,fileencryption=ice//g" $fstab
		sed -i "s/fileencryption/encryptable/g" $fstab
	done
fi

for pname in ${port_partition};do
    rm -rf build/portrom/images/${pname}.img
done
echo "${pack_type}">fstype.txt
superSize=9126805504
green "Super大小为${superSize}" "Super image size: ${superSize}"
green "开始打包镜像" "Packing super.img"
for pname in ${super_list};do
    if [ -d "build/portrom/images/$pname" ];then
        if [[ "$OSTYPE" == "darwin"* ]];then
            thisSize=$(find build/portrom/images/${pname} | xargs stat -f%z | awk ' {s+=$1} END { print s }' )
        else
            thisSize=$(du -sb build/portrom/images/${pname} |tr -cd 0-9)
        fi
        case $pname in
            mi_ext) addSize=4194304 ;;
            odm) addSize=134217728 ;;
            system|vendor|system_ext) addSize=154217728 ;;
            product) addSize=204217728 ;;
            *) addSize=8554432 ;;
        esac
        if [ "$pack_type" = "EXT" ];then
            for fstab in $(find build/portrom/images/${pname}/ -type f -name "fstab.*");do
                #sed -i '/overlay/d' $fstab
                sed -i '/system * erofs/d' $fstab
                sed -i '/system_ext * erofs/d' $fstab
                sed -i '/vendor * erofs/d' $fstab
                sed -i '/product * erofs/d' $fstab
            done
            thisSize=$(echo "$thisSize + $addSize" |bc)
            blue 以[$pack_type]文件系统打包[${pname}.img]大小[$thisSize] "Packing [${pname}.img]:[$pack_type] with size [$thisSize]"
            python3 bin/fspatch.py build/portrom/images/${pname} build/portrom/config/${pname}_fs_config
            python3 bin/contextpatch.py build/portrom/images/${pname} build/portrom/config/${pname}_file_contexts
            make_ext4fs -J -T $(date +%s) -S build/portrom/config/${pname}_file_contexts -l $thisSize -C build/portrom/config/${pname}_fs_config -L ${pname} -a ${pname} build/portrom/images/${pname}.img build/portrom/images/${pname}

            if [ -f "build/portrom/images/${pname}.img" ];then
                green "成功以大小 [$thisSize] 打包 [${pname}.img] [${pack_type}] 文件系统" "Packing [${pname}.img] with [${pack_type}], size: [$thisSize] success"
                #rm -rf build/baserom/images/${pname}
            else
                error "以 [${pack_type}] 文件系统打包 [${pname}] 分区失败" "Packing [${pname}] with[${pack_type}] filesystem failed!"
            fi
        else
            
                blue 以[$pack_type]文件系统打包[${pname}.img] "Packing [${pname}.img] with [$pack_type] filesystem"
                python3 bin/fspatch.py build/portrom/images/${pname} build/portrom/config/${pname}_fs_config
                python3 bin/contextpatch.py build/portrom/images/${pname} build/portrom/config/${pname}_file_contexts
                mkfs.erofs -zlz4hc,1 --mount-point=/${pname} --fs-config-file=./build/portrom/config/${pname}_fs_config --file-contexts=./build/portrom/config/${pname}_file_contexts build/portrom/images/${pname}.img build/portrom/images/${pname}
                if [ -f "build/portrom/images/${pname}.img" ];then
                    green "成功以 [erofs] 文件系统打包 [${pname}.img]" "Packing [${pname}.img] successfully with [erofs] format"
                    #rm -rf build/portrom/images/${pname}
                else
                    error "以 [${pack_type}] 文件系统打包 [${pname}] 分区失败" "Faield to pack [${pname}]"
                    exit 1
                fi
        fi
        unset fsType
        unset thisSize
    fi
done
rm fstype.txt

# 打包 super.img

if [[ "$is_ab_device" == false ]];then
    blue "打包A-only super.img" "Packing super.img for A-only device"
    lpargs="-F --output build/portrom/images/super.img --metadata-size 65536 --super-name super --metadata-slots 2 --block-size 4096 --device super:$superSize --group=qti_dynamic_partitions:$superSize"
    for pname in odm mi_ext system system_ext product vendor;do
        if [ -f "build/portrom/images/${pname}.img" ];then
            if [[ "$OSTYPE" == "darwin"* ]];then
               subsize=$(find build/portrom/images/${pname}.img | xargs stat -f%z | awk ' {s+=$1} END { print s }')
            else
                subsize=$(du -sb build/portrom/images/${pname}.img |tr -cd 0-9)
            fi
            green "Super 子分区 [$pname] 大小 [$subsize]" "Super sub-partition [$pname] size: [$subsize]"
            args="--partition ${pname}:none:${subsize}:qti_dynamic_partitions --image ${pname}=build/portrom/images/${pname}.img"
            lpargs="$lpargs $args"
            unset subsize
            unset args
        fi
    done
else
    blue "打包V-A/B机型 super.img" "Packing super.img for V-AB device"
    lpargs="-F --virtual-ab --output build/portrom/images/super.img --metadata-size 65536 --super-name super --metadata-slots 3 --device super:$superSize --group=qti_dynamic_partitions_a:$superSize --group=qti_dynamic_partitions_b:$superSize"

    for pname in ${super_list};do
        if [ -f "build/portrom/images/${pname}.img" ];then
            subsize=$(du -sb build/portrom/images/${pname}.img |tr -cd 0-9)
            green "Super 子分区 [$pname] 大小 [$subsize]" "Super sub-partition [$pname] size: [$subsize]"
            args="--partition ${pname}_a:none:${subsize}:qti_dynamic_partitions_a --image ${pname}_a=build/portrom/images/${pname}.img --partition ${pname}_b:none:0:qti_dynamic_partitions_b"
            lpargs="$lpargs $args"
            unset subsize
            unset args
        fi
    done
fi
lpmake $lpargs
#echo "lpmake $lpargs"
if [ -f "build/portrom/images/super.img" ];then
    green "成功打包 super.img" "Pakcing super.img done."
else
    error "无法打包 super.img"  "Unable to pack super.img."
    exit 1
fi
for pname in ${super_list};do
    rm -rf build/portrom/images/${pname}.img
done

blue "正在压缩 super.img" "Comprising super.img"
zstd --rm build/portrom/images/super.img -o build/portrom/images/super.zst
mkdir -p out/hyperos_${device_code}_${port_rom_version}/META-INF/com/google/android/

blue "正在生成刷机脚本" "Generating flashing script"
if [[ "$is_ab_device" == false ]];then

    mv -f build/portrom/images/super.zst out/hyperos_${device_code}_${port_rom_version}/
    #firmware
    if [ -d build/baserom/firmware-update ];then
        mkdir -p out/hyperos_${device_code}_${port_rom_version}/firmware-update
        cp -rf build/baserom/firmware-update/*  out/hyperos_${device_code}_${port_rom_version}/firmware-update
    fi
        # disable vbmeta
    for img in $(find out/hyperos_${device_code}_${port_rom_version}/firmware-update -type f -name "vbmeta*.img");do
        python3 bin/patch-vbmeta.py ${img}
    done
    mv -f build/baserom/boot.img out/hyperos_${device_code}_${port_rom_version}/boot_official.img
    cp -rf bin/flash/a-only/update-binary out/hyperos_${device_code}_${port_rom_version}/META-INF/com/google/android/
    cp -rf bin/flash/zstd out/hyperos_${device_code}_${port_rom_version}/META-INF/
    custom_bootimg_file=$(find devices/$base_rom_code/ -type f -name "boot*.img")
    if [[ -f "$custom_bootimg_file" ]];then
        bootimg=$(basename "$custom_bootimg_file")
        sed -i "s/boot_tv.img/$bootimg/g" out/hyperos_${device_code}_${port_rom_version}/META-INF/com/google/android/update-binary
        cp -rf "$custom_bootimg_file" out/hyperos_${device_code}_${port_rom_version}/
    fi
    sed -i "s/portversion/${port_rom_version}/g" out/hyperos_${device_code}_${port_rom_version}/META-INF/com/google/android/update-binary
    sed -i "s/baseversion/${base_rom_version}/g" out/hyperos_${device_code}_${port_rom_version}/META-INF/com/google/android/update-binary
    sed -i "s/andVersion/${port_android_version}/g" out/hyperos_${device_code}_${port_rom_version}/META-INF/com/google/android/update-binary
    sed -i "s/device_code/${base_rom_code}/g" out/hyperos_${device_code}_${port_rom_version}/META-INF/com/google/android/update-binary

else
    mkdir -p out/hyperos_${device_code}_${port_rom_version}/images/
    mv -f build/portrom/images/super.zst out/hyperos_${device_code}_${port_rom_version}/images/
    cp -rf devices/haydn/* out/hyperos_${device_code}_${port_rom_version}/
fi

find out/hyperos_${device_code}_${port_rom_version} |xargs touch
pushd out/hyperos_${device_code}_${port_rom_version}/ >/dev/null || exit
zip -r hyperos_${device_code}_${port_rom_version}.zip ./*
mv hyperos_${device_code}_${port_rom_version}.zip ../
popd >/dev/null || exit
pack_timestamp=$(date +"%m%d%H%M")
hash=$(md5sum out/hyperos_${device_code}_${port_rom_version}.zip |head -c 8)
mv out/hyperos_${device_code}_${port_rom_version}.zip out/HyperOS_${device_code}_${port_rom_version}_${hash}_${port_android_version}_${port_rom_code}_${pack_timestamp}_${pack_type}.zip
green "移植完毕" "Porting completed"    
green "输出包路径：" "Output: "
green "$(pwd)/out/HyperOS_${device_code}_${port_rom_version}_${hash}_${port_android_version}_${port_rom_code}_${pack_timestamp}_${pack_type}.zip"
end_time=$SECONDS

# 计算运行时间
elapsed_time=$((end_time - start_time))
green "本次移植共耗时${elapsed_time} 秒"
if [[ $pack_type == "EROFS" ]];then
    yellow "检测到打包类型为EROFS,请确保官方内核支持，或者在devices机型目录添加有支持EROFS的内核，否者将无法开机！" "EROFS filesystem detected. Ensure compatibility with the official boot.img or ensure a supported boot_tv.img is placed in the device folder."
    pack_type="ROOT_"${pack_type}
fi


