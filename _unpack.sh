#!/bin/bash

# --- Ensure script is run as root ---
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root."
    exit 1
fi

# check input
if [ -z "$1" ]; then
    echo "Usage: $0 <pak_file>"
    exit 1
fi

pak_file="$1"

# extract folder name from pak filename: take the number after the first dot
folder_name=$(echo "$pak_file" | sed -E 's/^([^.]*\.[0-9_]+).*$/\1/')

if [ -d "$folder_name" ]; then
    rm -rf "$folder_name"
fi

# extract pak
pakler "$pak_file" -e -d "$folder_name"
info=$(pakler "$pak_file")
cd "$folder_name"

get_section_and_len() {
    name="$1"
    section=$(echo "$info" | awk -v n="$name" '$0 ~ "Section" && $0 ~ n {print $2}')
    len_hex=$(echo "$info" | awk -v n="$name" '$0 ~ "Mtd_part" && $0 ~ n {
        for(i=1;i<=NF;i++){
            if($i ~ /^len=/){
                sub("len=","",$i)
                print $i
                exit
            }
        }
    }')
    len_dec=$((len_hex))  # hex to decimal
    echo "$section $name $len_hex $len_dec"
}

# Loop over partitions
for part in rootfs app; do
    read section name len_hex len_dec <<< $(get_section_and_len "$part")
    echo "$part: section=$section name=$name len_hex=$len_hex len_dec=$len_dec"

	bin_file=$(printf "%02d_%s.bin" "$section" "$part")
    out_dir="${bin_file%.bin}"  # strip .bin for output folder

    ubireader_extract_images "$bin_file" -o __tmp__

    for f in __tmp__/"$bin_file"/*; do
        if [ -f "$f" ]; then
            # detect file type
            ftype=$(file -b "$f")

            if [[ "$ftype" == *"Squashfs"* ]]; then
                echo "Extracting SquashFS from $f..."
                unsquashfs -d "${out_dir}.s" "$f"
            elif [[ "$ftype" == *"UBI"* || "$ftype" == *"UBIFS"* ]]; then
                echo "Extracting UBIFS from $f..."                
                ubireader_extract_files -k -o "${out_dir}.u" "$f"
                file_info=$(ubireader_display_info "$f")
                # min_io_size=$(echo "$file_info" | awk '/min_io_size:/ {print $2}')
                # leb_size=$(echo "$file_info" | awk '/leb_size:/ {print $2}')
                max_leb_cnt=$(echo "$file_info" | awk '/max_leb_cnt:/ {print $2}')
                # echo "min_io_size=${min_io_size}" > "${out_dir}.ini"
                # echo "leb_size=${leb_size}" >> "${out_dir}.ini"
                echo "max_leb_cnt=${max_leb_cnt}" >> "${out_dir}.ini"
            else
                echo "Unknown filesystem type in $f ($ftype)"
                exit 1
            fi
        fi
    done
    
    rm -rf __tmp__
done
