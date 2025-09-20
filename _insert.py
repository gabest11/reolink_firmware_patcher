import sys

def insert_with_padding(input_file, output_file, start_offset, end_offset, N=0x800, P=0x80):
    # Verify alignment of original offset
    if start_offset % N != 0:
        print(f"ERROR: start_offset 0x{start_offset:X} (decimal {start_offset}) "
              f"is not a multiple of N (0x{N:X}).")
        sys.exit(1)

    # Adjust offsets with integer arithmetic
    start_offset = start_offset * (N + P) // N
    end_offset   = end_offset   * (N + P) // N

    print(f"Insertion region: 0x{start_offset:X} - 0x{end_offset:X} "
          f"(length {end_offset - start_offset} bytes)")

    # Read the data from both files
    with open(input_file, "rb") as f:
        insert_data = f.read()
    with open(output_file, "rb") as f:
        base_data = bytearray(f.read())

    # Ensure base_data is large enough
    if len(base_data) < end_offset:
        base_data.extend(b"\x00" * (end_offset - len(base_data)))

    # Erase region with 0xFF
    for i in range(start_offset, end_offset):
        base_data[i] = 0xFF

    # Build modified data with padding
    result = bytearray()
    written = 0

    for b in insert_data:
        result.append(b)
        written += 1
        if written % N == 0:
            result.extend(b"\xFF" * P)

    # Check if result fits in the region
    max_len = end_offset - start_offset
    if len(result) > max_len:
        print(f"WARNING: Inserted data ({len(result)} bytes) exceeds available space "
              f"({max_len} bytes). Truncating to fit.")
        result = result[:max_len]

    # Overwrite in the base_data
    base_data[start_offset:start_offset + len(result)] = result

    # Write back
    with open(output_file, "wb") as f:
        f.write(base_data)


if __name__ == "__main__":
    if len(sys.argv) < 5 or len(sys.argv) > 7:
        print(f"Usage: {sys.argv[0]} <input.bin> <output.bin> <start_offset> <end_offset> [N] [P]")
        sys.exit(1)

    input_file = sys.argv[1]
    output_file = sys.argv[2]
    start_offset = int(sys.argv[3], 0)
    end_offset = int(sys.argv[4], 0)

    if len(sys.argv) >= 6:
        N = int(sys.argv[5], 0)
    else:
        N = 0x800

    if len(sys.argv) == 7:
        P = int(sys.argv[6], 0)
    else:
        P = 0x80

    insert_with_padding(input_file, output_file, start_offset, end_offset, N, P)
