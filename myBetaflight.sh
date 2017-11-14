#!/bin/bash -e
# This script builds a patched version of Betaflight using docker. The applied patches are configured in
# the config file (CONFIG_FILE). The resulting Betaflight binary is found in the firmware folder.

CONFIG_FILE="myBetaflight.config"

###################### check for configuration and required commands ######################

if ! [ $(id -u) = 0 ]; then
   echo "Please run script as root or with sudo (this is required for running docker, e.g. sudo $0)"
   exit 1
fi

PLATFORM=$(cat $CONFIG_FILE | egrep -v "^ *#" | egrep "platform *= *" | cut -d= -f2 | awk '{$1=$1;print}')
if [ -z "$PLATFORM" ]; then
    echo "Please set a target platform in $CONFIG_FILE (e.g. BETAFLIGHTF3)"
    exit 1
fi

RELEASE=$(cat $CONFIG_FILE | egrep -v "^ *#" | egrep "release *= *" | cut -d= -f2 | awk '{$1=$1;print}')
if [ -z "$RELEASE" ]; then
    echo "Please set a release in $CONFIG_FILE (e.g. 3.2.1)"
    exit 1
fi
if [ ! -d releases/$RELEASE ]; then
    RELEASES=$(ls -d releases/*/ | sed 's#^releases/\([0-9\.]\+\)/$#\1#g')
    echo "Release $RELEASE not (yet) supported. Supported releases are:" $RELEASES
    exit 1
fi

OPTIONS="$(cat $CONFIG_FILE | egrep -v "^ *#" | egrep "options *= *" | cut -d= -f2 | awk '{$1=$1;print}')"

if [ -z "$(which docker)" ]; then
    echo "Please install docker first"
    exit 1
fi
if [ -z "$(which patch)" ]; then
    echo "Please install patch first"
    exit 1
fi

###################### retrieve and prepare source code ######################

if [ ! -e v$RELEASE.tar.gz ] || [ ! -s v$RELEASE.tar.gz ]; then
    rm -f v$RELEASE.tar.gz
    
    if [ -z "$(which wget)" ]; then
        echo "Please install wget first"
        exit 1
    fi
    
    echo "Downloading source v$RELEASE.tar.gz..."
    set +e
    wget -O v$RELEASE.tar.gz -q --show-progress https://github.com/betaflight/betaflight/archive/v$RELEASE.tar.gz
    if [ $? != 0 ]; then
        echo "Failed download from https://github.com/betaflight/betaflight/archive/v$RELEASE.tar.gz"
        exit 1
    fi
    set -e
fi

echo "Cleaning up old build files/folders..."
rm -rf betaflight-$RELEASE firmware docker.log

echo "Extracting v$RELEASE.tar.gz..."
tar xf v$RELEASE.tar.gz

###################### apply patches to source code ######################

for PATCH in $(cat $CONFIG_FILE | egrep -v "^ *#" | egrep "\.patch *= *yes *$" | cut -d. -f1); do
    if [ -f releases/$RELEASE/$PATCH.patch ]; then
        unset CONFIG
        declare -A CONFIG
        while read line ; do
            K="$(echo $line | cut -d= -f1 | awk '{$1=$1;print}')"
            V="$(echo $line | cut -d= -f2-5 | awk '{$1=$1;print}')"
            CONFIG[$K]="$V"
        done < <(cat $CONFIG_FILE | grep "^$PATCH\." | grep -v "\.patch")
        
        SOURCE_FILES=$(cat releases/$RELEASE/$PATCH.patch | grep "^\-\-\-" | awk '{print $2}')
        
        cd betaflight-$RELEASE/
        echo "Applying patch releases/$RELEASE/$PATCH.patch..."
        patch -p1 < ../releases/$RELEASE/$PATCH.patch
        cd ..
        
        for KEY in "${!CONFIG[@]}"; do
            sed -i "s/##$KEY##/${CONFIG[$KEY]}/g" $SOURCE_FILES
        done
    else
        echo "No patch file found for $PATCH. Skipping..."
    fi
done

###################### build Betaflight using docker ######################

if [ -z "$(docker images | grep betaflight/betaflight-build)" ]; then
    echo "Pulling docker image..."
    docker pull betaflight/betaflight-build
    echo
fi

echo "Building custom version of Betaflight... (this might take a few minutes)"
set +e
IFS=","
for P in $PLATFORM; do
    P=$(echo $P | awk '{$1=$1;print}')
    echo "target: $P"
    docker run -e "PLATFORM=$P" -e "OPTIONS=$OPTIONS" --rm -ti -v `pwd`/betaflight-$RELEASE:/opt/betaflight betaflight/betaflight-build >docker.log
    if [ $? != 0 ]; then
        echo "Error during build, check docker.log for more information"
        exit 1
    else
        rm -f docker.log
    fi
done
set -e

mkdir -p firmware
cp betaflight-$RELEASE/obj/*.hex firmware/

echo "Done."
echo
echo "Built firmware:"
ls -1 firmware/*.hex

rm -rf betaflight-$RELEASE/
