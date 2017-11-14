#!/bin/bash -e
# This script creates a new patch by comparing two directories and storing the diff for a given release.

RELEASE=
NAME=
ORIGINAL=
PATCHED_DIR=
DESCRIPTION=

###################### check for parameters and if they're valid ######################

print_usage_and_exit() {
    echo
    echo "Creates a new patch by comparing two directories and storing the diff for a given release."
    echo "Usage: $0 --release=<RELEASE> --original=<ORIGINAL> --patched=<PATCHED> [--name=<NAME>] [--desc=<DESCRIPTION>]"
    echo "--release: the release version this patch applies to (e.g. 3.2.1)"
    echo "--original: path to the original unmodified betaflight source, either a tarball or root directory (e.g. ../v3.2.1.tar.gz or betaflight-3.2.1)"
    echo "--patched: path to the modified source, must be a betaflight root directory (e.g. betaflight-3.2.1-patched)"
    echo "--name: the patch name without the trailing '.patch' (optional, e.g. disablePidProfile)"
    echo "--desc: patch description (optional, e.g. \"Disable PID profile change via RC control\")"
    exit 1
}

clean_up() {
    if [ -f $ORIGINAL ]; then
        echo "Deleting $ORIGINAL_DIR..."
        rm -rf $ORIGINAL_DIR
    fi
}

for i in "$@"; do
    if [ -n "$i" ]; then
        case $i in
            --release=*)
            RELEASE=$(echo $i | awk -F= {'print $2'})
            ;;
            --original=*)
            ORIGINAL=$(echo $i | awk -F= {'print $2'})
            ;;
            --patched=*)
            PATCHED_DIR=$(echo $i | awk -F= {'print $2'})
            ;;
            --name=*)
            NAME=$(echo $i | awk -F= {'print $2'})
            ;;
            --desc=*)
            DESCRIPTION=$(echo $i | awk -F= {'print $2'})
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
mkdir -p $RELEASE

if [ -z "$ORIGINAL" ]; then
    echo "No original path given with --original."
    print_usage_and_exit
elif [ ! -e $ORIGINAL ]; then
    echo "The file/directory $ORIGINAL does not exist."
    exit 1
elif [ -f $ORIGINAL ]; then
    if [ -z "$(file $ORIGINAL | grep "compressed data")" ]; then
        echo "The file $ORIGINAL does not seem to be a tarball."
        exit 1
    fi
    ORIGINAL_DIR=$(tar -tzf $ORIGINAL | head -1 | cut -f1 -d"/")
    if [ -e $ORIGINAL_DIR ]; then
        echo "Cannot untar $ORIGINAL. The directory $ORIGINAL_DIR already exists. Please rename this directory."
        exit 1
    fi
elif [ -d $ORIGINAL ]; then
    ORIGINAL_DIR=$ORIGINAL
else
    echo "$ORIGINAL is neither a tarball nor a directory."
    exit 1
fi

if [ -z "$NAME" ]; then
    echo -n "Patch name: "
    read NAME
fi
if [ -z "$NAME" ]; then
    echo "Patch name cannot be empty."
    exit 1
fi
NAME=$(echo "$NAME" | sed 's/ //g') # deletes potential whitespaces in the name

PATCH=$RELEASE/$NAME.patch
if [ -e $PATCH ]; then
    echo "Patch $PATCH already exists."
    exit 1
fi

if [ -z "$PATCHED_DIR" ]; then
    echo "No patched path given with --patched."
    print_usage_and_exit
elif [ ! -d $PATCHED_DIR ]; then
    echo "The directory $PATCHED_DIR does not exist."
    exit 1
fi

if [ -z "$DESCRIPTION" ]; then
    echo -n "Patch description: "
    read DESCRIPTION
fi
if [ -z "$DESCRIPTION" ]; then
    echo "Patch description cannot be empty."
    exit 1
fi

###################### compare and find differences between original and patched ######################

if [ -f $ORIGINAL ]; then
    echo "Extracting $ORIGINAL..."
    tar xf $ORIGINAL
fi

echo "Creating patch $PATCH..."
echo "$DESCRIPTION" > $PATCH
echo >> $PATCH
set +e
diff -Naur $ORIGINAL_DIR $PATCHED_DIR >> $PATCH
if [ $? = 0 ]; then
    echo "No differences!"
    rm -f $PATCH
    clean_up
    exit 1
fi
set -e
echo "done."

clean_up
