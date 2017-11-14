#!/bin/bash -e
# This script adds support for a new Betaflight release by applying and adjusting the patches from a
# previous release. The adjusted patches will be placed in a new release folder.

RELEASE=
FROM=

###################### check for parameters and determine previous release ######################

print_usage_and_exit() {
    echo
    echo "Adds support for a new Betaflight release by applying and adjusting the patches from a previous release."
    echo "Usage: $0 --release=<RELEASE> [--from=<FROM>]"
    echo "--release: the new release to be supported (e.g. 3.2.2)"
    echo "--from: copy patches from this release (optional, e.g. 3.2.1)"
    exit 1
}

for i in "$@"; do
    if [ -n "$i" ]; then
        case $i in
            --release=*)
            RELEASE=$(echo $i | awk -F= {'print $2'})
            ;;
            --from=*)
            FROM=$(echo $i | awk -F= {'print $2'})
            ;;
            *)
            echo "Unknown or incomplete option: $i"
            print_usage_and_exit
            ;;
        esac
    fi
done

if [ -z "$RELEASE" ]; then
    echo "No release given with --release."
    print_usage_and_exit
fi
if [ -e $RELEASE ]; then
    echo "Release $RELEASE already exists."
    exit 1
fi

if [ -n "$FROM" ]; then
    if [ ! -e $FROM ]; then
        echo "The release $FROM was not found."
        exit 1
    fi
else
    TEMP="$(ls -1 -d */ | sed 's#/$##')"
    TEMP="$TEMP\n$RELEASE"
    FROM=$(echo -e "$TEMP" | sort -n | grep -a1 $RELEASE | head -n1)
    if [ "$FROM" = "$RELEASE" ]; then
        echo "Could not automatically determine the release to copy patches from. Please call script with the --from parameter."
        exit 1
    fi
    if [ -z "$FROM" ] || [ ! -e $FROM ]; then
        echo "The release $FROM was not found. Please call script with the --from parameter."
        exit 1
    fi
fi

###################### retrieve and prepare source code ######################

if [ ! -e ../v$RELEASE.tar.gz ] || [ ! -s ../v$RELEASE.tar.gz ]; then
    rm -f ../v$RELEASE.tar.gz
    echo "Downloading source v$RELEASE.tar.gz..."
    set +e
    wget -O ../v$RELEASE.tar.gz -q --show-progress https://github.com/betaflight/betaflight/archive/v$RELEASE.tar.gz
    if [ $? != 0 ]; then
        echo "Failed download from https://github.com/betaflight/betaflight/archive/v$RELEASE.tar.gz"
        exit 1
    fi
    set -e
fi

mkdir $RELEASE

if [ -e betaflight-$RELEASE ] || [ -e betaflight-$RELEASE-patched ]; then
    echo "Cleaning up old build folders..."
    rm -rf betaflight-$RELEASE betaflight-$RELEASE-patched
fi

echo "Extracting v$RELEASE.tar.gz..."
tar xf ../v$RELEASE.tar.gz
cp -r betaflight-$RELEASE betaflight-$RELEASE-patched

###################### attempt to apply old patches and create updated patches ######################

FAILED_PATCHES=

for PATCH in $(ls $FROM/*.patch); do
    cd betaflight-$RELEASE-patched
    echo "Applying patch $PATCH..."
    set +e
    patch -p1 --no-backup-if-mismatch -r - < ../$PATCH
    if [ $? != 0 ]; then
        FAILED_PATCHES="$FAILED_PATCHES\n$PATCH"
        cd ..
        continue
    fi
    set -e
    cd ..
    
    NEW_PATCH=$RELEASE/$(echo $PATCH | xargs basename)
    rm -f $NEW_PATCH
    while IFS= read -r line; do
        if [ -n "$(echo $line | grep "^diff \-Naur")" ]; then
            break
        fi
        echo $line >> $NEW_PATCH
    done <"$PATCH"
    
    set +e
    echo "Creating patch $NEW_PATCH..."
    diff -Naur betaflight-$RELEASE betaflight-$RELEASE-patched >> $NEW_PATCH
    set -e
    
    cd betaflight-$RELEASE-patched
    echo "Reversing patch $PATCH..."
    patch -p1 --no-backup-if-mismatch -R < ../$PATCH
    cd ..
done

###################### cleanup ######################

rm -rf betaflight-$RELEASE betaflight-$RELEASE-patched

if [ -n "$FAILED_PATCHES" ]; then
    echo -e "Some patches failed to apply, please apply them manually (follow steps to create a new patch):$FAILED_PATCHES"
    exit 1
fi
