#!/bin/bash

# -----------------------------
# Helper functions
# -----------------------------

get_ubinize_args() {
    local file="$1"
    read min_io peb_size < <(ubireader_display_info "$file" | awk -F: '
    /Min I\/O/ {gsub(/ /,"",$2); min=$2}
    /PEB Size/ {gsub(/ /,"",$2); peb=$2}
    END {print min, peb}
    ')
    echo "$min_io $peb_size"
}

generate_config() {
    local image_file="$1"
    local vol_name="$2"

    [[ -f "$image_file" ]] || { echo "Error: File '$image_file' not found."; return 1; }

    local file_size base_name
    file_size=$(stat -c%s "$image_file")
    base_name="${image_file%.*}"

    cat > "${base_name}.cfg" <<EOF
[${vol_name}]
mode=ubi
image=$image_file
vol_id=0
vol_size=$file_size
vol_type=dynamic
vol_name=$vol_name
EOF

    echo "Config file '${base_name}.cfg' created."
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

    if [[ -d "${dir}.s" ]]; then
        echo "Building SquashFS from ${dir}.s"
        mksquashfs "${dir}.s/" "$sqsh_file" -comp xz -b 262144 -noappend
        fs_file=$sqsh_file
    elif [[ -d "${dir}.u" ]]; then
        echo "Building UBIFS from ${dir}.u"
        ini_file="${dir}.ini"
        min_io_size=$(grep -E '^min_io_size=' "$ini_file" | cut -d= -f2)
        leb_size=$(grep -E '^leb_size=' "$ini_file" | cut -d= -f2)
        max_leb_cnt=$(grep -E '^max_leb_cnt=' "$ini_file" | cut -d= -f2)
        if [[ -z "$min_io_size" || -z "$leb_size" ]]; then
            echo "Error: min_io_size or leb_size missing in $ini_file" >&2
            exit 1
        fi
        sudo mkfs.ubifs -r "${dir}.u/" -o "$ubifs_file" -m "$min_io_size" -e "$leb_size" -c "$max_leb_cnt"
        fs_file=$ubifs_file
    else
        echo "Error: neither ${dir}.s nor ${dir}.u exist" >&2
        exit 1        
    fi

    # Generate config
    generate_config "$fs_file" "$vol_name"

    # Get ubinize args and create UBI
    read m p < <(get_ubinize_args "$bin_file")
    sudo ubinize -o "$ubi_file" -m "$m" -p "$p" "${dir}.cfg"
}

repack_partition() {
    local firmware="$1"
    local section="$2"
    local ubi_file="$3"

    pakler "$firmware" -r -n "$section" -f "$ubi_file" -o tmp.pak
    mv tmp.pak "$firmware"
}

# -----------------------------
# Main
# -----------------------------
if [[ -z "$1" ]]; then
    echo "Usage: $0 <firmware.pak>"
    exit 1
fi

firmware_orig="$1"

# Extract original folder number after first dot (existing extraction directory)
orig_folder_num=$(basename "$firmware_orig" | sed -E 's/^[^.]*\.([0-9]+).*$/\1/')
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

# Set ownership
OWNER=${SUDO_USER:-$USER}
sudo chown "$OWNER":"$(id -gn "$OWNER")" *.ubi

# Repack firmware
for part in rootfs app; do
    section="${sections[$part]}"
    ubi_file=$(printf "%02d_%s.ubi" "$section" "$part")
    repack_partition "../$firmware_new" "$section" "$ubi_file"
done
