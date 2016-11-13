#!/bin/bash 

# Paths
SOURCE_PATH=$(pwd)
LOCAL_PATH=$(dirname $(readlink -f $0))
BUILDS_PATH="$LOCAL_PATH/../kernel-builds/"
ANYKERNEL_PATH=$LOCAL_PATH/.anykernel
CCACHE_PATH=$LOCAL_PATH/.ccachebin
TOOLCHAIN_X86_PATH=$LOCAL_PATH/.toolchain
CROSS_COMPILE_X86="ccache arm-eabi-"
TOOLCHAIN_X64_PATH=$LOCAL_PATH/.toolchain-x64
CROSS_COMPILE_X64="ccache aarch64-linux-android-"

# Constants
USE_CCACHE=1	         # enable ccache
JOBS=$(expr 0 + $(grep -c ^processor /proc/cpuinfo)) # set JOBS to the amount of available cores

# Variables
KERNEL_TOOLCHAIN=      # Toolchain path
KERNEL_CROSS_COMPILE=  # Cross compile based on arch
KERNEL_ARCH="arm"      # ARM as default
KERNEL_CONFIG=         # Kernel defconfig
KERNEL_OPT_TARGETS=""  # For eg., mrproper
SIDELOAD=false         # Don't sideload by default

# Functions

# Usage function
function usage {
cat <<EOF
Usage: $(basename $0) [OPTION]...

  -c=<config>, --config=<config>   set kernel config

Optional options:
  -a=<arch>,   --arch=<arch>       set kernel architecture, arm, arm64/aarch64
                                   (arm is the default)
  -cl,         --clean             cleanup build output dir
  -j=<n>,      --jobs=<n>          number of jobs used to build kernel
                                   (default is the amount of available cores)
  -s,          --sideload          after pack kernel sideload it to the device                     
               --help              display this help and exit

Examples:
  $(basename $0) -c=some_arm_defconfig -a=arm         builds kernel with some_defconfig configfrom arm architecture
  $(basename $0) -c=some_arm64_defconfig -a=arm64 -s  builds kernel with some_defconfig config from arm64 architecture and tries to sideload the package
  $(basename $0) -c=some_defconfig -cl                cleans the output build directory

EOF
}

# Parse arguments function
function argvParse {
for i in "$1"
  do
    case $i in
      --arch=*|-a=*)
      KERNEL_ARCH="${i#*=}"
      shift
      ;;
      --config=*|-c=*)
      KERNEL_CONFIG="${i#*=}"
      shift
      ;;
      --clean|-cl)
      KERNEL_OPT_TARGETS="clean"
      shift
      ;;
      --sideload|-s)
      SIDELOAD=true
      shift
      ;;
      --jobs=*|-j=*)
      JOBS="${i#*=}"
      shift
      ;;
      --help)
      usage
      exit 0
      ;;
    esac
  done
}

# Evaluate variables function
function evalArguments {
  if [ -z "$KERNEL_CONFIG"  ]
  then
    echo ERROR: --config was not specified
    usage
    exit 1
  fi
}

# Iterate arguments
argvParse "$@" 

# Eval variables
evalArguments

# Define toolchain based on KERNEL_ARCH
if [[ $KERNEL_ARCH -eq arm ]]; then
	KERNEL_TOOLCHAIN=$TOOLCHAIN_X86_PATH
	KERNEL_CROSS_COMPILE=$CROSS_COMPILE_X86
elif [[ $KERNEL_ARCH -eq aarch64 || $KERNEL_ARCH -eq arm64 ]]; then
	KERNEL_ARCH="arm64"
        KERNEL_TOOLCHAIN=$TOOLCHAIN_X64_PATH
        KERNEL_CROSS_COMPILE=$CROSS_COMPILE_X64
fi

# Exports
export PATH="$PATH:/opt/local/bin/:$KERNEL_TOOLCHAIN/bin/:$CCACHEBIN/linux-x86/ccache/"
export USE_CCACHE
export JOBS
export CROSS_COMPILE=$KERNEL_CROSS_COMPILE
export ARCH=$KERNEL_ARCH
export OUT_DIR="/tmp/$KERNEL_CONFIG"
export KERNEL_FILE_NAME="$KERNEL_CONFIG-$(date +%Y%m%d%H%M%S).zip"

# Build process
mkdir -p $OUT_DIR
make -j$JOBS O="$OUT_DIR" $KERNEL_CONFIG || exit 1
make -j$JOBS O="$OUT_DIR" $KERNEL_OPT_TARGETS || exit 1

if [[ ${KERNEL_OPT_TARGETS} = clean ]]
then
  echo OUT_DIR was cleaned up, exiting...
  exit 1
fi

# Create flashable zip
rm -rf $ANYKERNEL_PATH/*.zip $ANYKERNEL_PATH/zImage
cp $SOURCE_PATH/arch/$KERNEL_ARCH/boot/zImage $ANYKERNEL_PATH/.
pushd $ANYKERNEL_PATH
zip -r9 $KERNEL_FILE_NAME * -x README $KERNEL_FILE_NAME
popd
mkdir -p $BUILDS_PATH
mv $ANYKERNEL_PATH/$KERNEL_FILE_NAME $BUILDS_PATH/.

# ADB sideload
if [ $SIDELOAD = "true" ]; then
	adb wait-for-device
	adb sideload $ANYKERNEL_PATH/$KERNEL_FILE_NAME
fi
