import sys
import os

def extract_with_padding(output_file, extracted_file, start_offset, end_offset, N=0x800, P=0x80):
    BLOCK_SIZE = 0x20000  # 128 KB

    # Exit if the extracted file already exists
    if os.path.exists(extracted_file):
        print(f"ERROR: '{extracted_file}' already exists. Aborting.")
        sys.exit(1)
    
    # Verify alignment
    if start_offset % N != 0:
        print(f"ERROR: start_offset 0x{start_offset:X} is not a multiple of N (0x{N:X}).")
        sys.exit(1)
    if end_offset % N != 0:
        print(f"ERROR: end_offset 0x{end_offset:X} is not a multiple of N (0x{N:X}).")
        sys.exit(1)

    # Adjust offsets
    start_offset = start_offset * (N + P) // N
    end_offset   = end_offset   * (N + P) // N

    print(f"Extracting from offset 0x{start_offset:X} to 0x{end_offset:X} "
          f"(length {end_offset - start_offset} bytes)")

    # Read the output file
    with open(output_file, "rb") as f:
        data = f.read()

    # Ensure end_offset is within bounds
    if end_offset > len(data):
        print(f"WARNING: end_offset 0x{end_offset:X} exceeds file length. Adjusting.")
        end_offset = len(data)

    # Extract original bytes, skipping inserted padding
    extracted = bytearray()
    pos = start_offset
    while pos < end_offset:
        # Copy N bytes (or until end_offset)
        block_end = min(pos + N, end_offset)
        extracted.extend(data[pos:block_end])
        pos = block_end
        # Skip P padding bytes
        pos += P

    # Trim trailing N-size blocks that are all 0xFF
    # while len(extracted) >= N and all(b == 0xFF for b in extracted[-N:]):
    #    extracted = extracted[:-N]
        
    # Trim trailing N-size blocks that are all 0xFF (fast version)
    num_blocks = len(extracted) // N
    trim_index = len(extracted)

    for i in range(num_blocks - 1, -1, -1):
        block_start = i * N
        block_end = block_start + N
        if extracted[block_start:block_end] == b'\xFF' * N:
            trim_index = block_start
        else:
            break

    # Slice once at the end
    extracted = extracted[:trim_index]

    # Pad with 0xFF to the next multiple of 128 KB
    pad_len = (BLOCK_SIZE - len(extracted) % BLOCK_SIZE) % BLOCK_SIZE
    if pad_len > 0:
        extracted.extend(b'\xFF' * pad_len)

    # Write to extracted file
    with open(extracted_file, "wb") as f:
        f.write(extracted)

    print(f"Extraction complete: {len(extracted)} bytes written to {extracted_file} "
          f"(padded to next 128KB boundary)")


if __name__ == "__main__":
    if len(sys.argv) < 5 or len(sys.argv) > 7:
        print(f"Usage: {sys.argv[0]} <extracted.bin> <output.bin> <start_offset> <end_offset> [N] [P]")
        sys.exit(1)

    extracted_file = sys.argv[1]
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

    extract_with_padding(output_file, extracted_file, start_offset, end_offset, N, P)
