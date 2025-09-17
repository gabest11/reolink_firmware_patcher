#!/bin/bash

# check input
if [ -z "$1" ]; then
    echo "Usage: $0 <pak_file>"
    exit 1
fi

pak_file="$1"

# extract folder name from pak filename: take the number after the first dot
folder_name=$(echo "$pak_file" | sed -E 's/^[^.]*\.([0-9]+).*$/\1/')

rm -rf "$folder_name"

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
    
    ubireader_extract_images "$bin_file" -o tmp
	unsquashfs -d "$out_dir" tmp/"$bin_file"/*
    rm -rf tmp
done
