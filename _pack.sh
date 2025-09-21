#!/bin/bash

# -----------------------------
# Helper functions
# -----------------------------

generate_config() {
    local image_file="$1"
    local vol_name="$2"
    local leb_size="$3"

    [[ -f "$image_file" ]] || { echo "Error: File '$image_file' not found."; return 1; }
    [[ -n "$leb_size" ]] || { echo "Error: LEB size not specified."; return 1; }

    local file_size base_name vol_size leb_count
    file_size=$(stat -c%s "$image_file")
    base_name="${image_file%.*}"

    # Calculate LEB count (round up)
    leb_count=$(( (file_size + leb_size - 1) / leb_size ))

    # Calculate vol_size as leb_count * leb_size
    vol_size=$(( leb_count * leb_size ))

    cat > "${base_name}.cfg" <<EOF
[${vol_name}]
mode=ubi
image=$image_file
vol_id=0
vol_name=$vol_name
vol_size=$vol_size
vol_type=dynamic
vol_alignment=1
EOF
#vol_flags=autoresize

    echo "Config file '${base_name}.cfg' created."
    echo "Image size: $file_size bytes, LEB size: $leb_size, LEB count: $leb_count, vol_size: $vol_size bytes"
}

build_ubi() {
    local dir="$1"
    local vol_name="$2"
    local bin_file="$3"

    local sqsh_file="${dir}.sqsh"
    local ubifs_file="${dir}.ubifs"
    local ubi_file="${dir}.ubi"

    # Remove old files
    rm -f "$sqsh_file" "$ubifs_file" "$ubi_file"

    info=$(ubireader_display_info "$bin_file")
    min_io=$(echo "$info" | grep "Min I/O:" | awk '{print $3}')
    leb_size=$(echo "$info" | grep "LEB Size:" | awk '{print $3}')
    peb_size=$(echo "$info" | grep "PEB Size:" | awk '{print $3}')
    echo "min_io=$min_io"
    echo "leb_size=$leb_size"
    echo "peb_size=$peb_size"
    
    if [[ -z "$min_io" || -z "$peb_size" || -z "$leb_size" ]]; then
        echo "Error: min_io or peb_size or leb_size missing in $bin_file" >&2
        exit 1
    fi

    if [[ -d "${dir}.s" ]]; then
        echo "Building SquashFS from ${dir}.s"
        mksquashfs "${dir}.s/" "$sqsh_file" -comp xz -b 262144 -noappend
        fs_file=$sqsh_file
    elif [[ -d "${dir}.u" ]]; then
        echo "Building UBIFS from ${dir}.u"

        ini_file="${dir}.ini"
        max_leb_cnt=$(grep -E '^max_leb_cnt=' "$ini_file" | cut -d= -f2)
        if [[ -z "$max_leb_cnt" ]]; then
            echo "Error: max_leb_cnt missing in $ini_file" >&2
            exit 1
        fi

        # TODO: ubireader_extract_files randomly removes group and other's write permissions
        # find "${dir}.u/" -type f -exec chmod 777 {} \;
        # find "${dir}.u/" -type d -exec chmod 777 {} \;

        echo mkfs.ubifs -r "${dir}.u/" -o "$ubifs_file" -m "$min_io" -e "$leb_size" -c "$max_leb_cnt"
        mkfs.ubifs -r "${dir}.u/" -o "$ubifs_file" -m "$min_io" -e "$leb_size" -c "$max_leb_cnt"
        fs_file=$ubifs_file
    else
        echo "Error: neither ${dir}.s nor ${dir}.u exist" >&2
        exit 1
    fi

    # Generate config
    generate_config "$fs_file" "$vol_name" "$leb_size"

    # Create UBI
    echo ubinize -o "$ubi_file" -m "$min_io" -p "$peb_size" "${dir}.cfg"
    ubinize -o "$ubi_file" -m "$min_io" -p "$peb_size" "${dir}.cfg"
}

repack_partition() {
    local firmware="$1"
    local section="$2"
    local ubi_file="$3"

    echo pakler "$firmware" -r -n "$section" -f "$ubi_file" -o tmp.pak
    pakler "$firmware" -r -n "$section" -f "$ubi_file" -o tmp.pak
    mv tmp.pak "$firmware"
}

# -----------------------------
# Main
# -----------------------------

# --- Ensure script is run as root ---
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root."
    exit 1
fi

if [[ -z "$1" ]]; then
    echo "Usage: $0 <firmware.pak>"
    exit 1
fi

firmware_orig="$1"

# Extract original folder number after first dot (existing extraction directory)
orig_folder_num=$(basename "$firmware_orig" | sed -E 's/^([^.]*\.[0-9]+).*$/\1/')
folder_name="$orig_folder_num"

# Extract parts of the filename
filename=$(basename "$firmware_orig")
dir_path=$(dirname "$firmware_orig")

# Split filename into prefix, number, and suffix
# Example: IPC_566SD664M5MP.4417_2412122178.E1-Zoom.5MP.WIFI7.PTZ.REOLINK.pak
# prefix=IPC_566SD664M5MP
# num=4417
# suffix=_2412122178.E1-Zoom.5MP.WIFI7.PTZ.REOLINK.pak
prefix=$(echo "$filename" | sed -E 's/^([^.]+)\..*$/\1/')
num=$(echo "$filename" | sed -E 's/^[^.]+\.([0-9]+).*$/\1/')
suffix=$(echo "$filename" | sed -E 's/^[^.]+\.[0-9]+(.*)\.pak$/\1/')

# Increment the number
new_num=$((num + 1))

# Construct patched firmware filename
firmware_new="${prefix}.${new_num}${suffix}_patched.pak"

echo "Patched firmware will be: $firmware_new"
cp "$firmware_orig" "$firmware_new"

# Detect sections dynamically from pak info
info=$(pakler "$firmware_orig")

declare -A sections
for part in rootfs app; do
    sections[$part]=$(echo "$info" | awk -v n="$part" '$0 ~ "Section" && $0 ~ n {print $2}')
done

cd "$folder_name" || { echo "Directory $folder_name does not exist."; exit 1; }

# Build UBI for each partition
for part in rootfs app; do
    section="${sections[$part]}"
    bin_file=$(printf "%02d_%s.bin" "$section" "$part")
    dir_name="${bin_file%.bin}"
    build_ubi "$dir_name" "$part" "$bin_file"
done

# Repack firmware
for part in rootfs app; do
    section="${sections[$part]}"
    ubi_file=$(printf "%02d_%s.ubi" "$section" "$part")
    repack_partition "../$firmware_new" "$section" "$ubi_file"
done
