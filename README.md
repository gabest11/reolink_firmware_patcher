# Reolink Firmware Patcher

Requirements: pakler, ubi_reader (pip install ...), also mtd-utils.

Use the latest pakler from github, there was a new pak header type since the last release (`pip install git+https://github.com/vmallet/pakler.git`).

Tested with 
- E1 Zoom 5MP and 8MP
- Doorbell Wifi (2024.03.07.) 

Don't try if there is no LAN and serial connection on the board somewhere. If there is no serial (Doorbell) it is still possible to rescue if you can pull the partitions from the update and merge with the contents of the NAND and rewrite it with some programmer like the T48. Use a spring needle probe for WSON-8*6.

You have to run _unpack.sh, _pack.sh as root (sudo -i). So also run pip or pipx install as root.

### Unpack

`./_unpack.sh <firmware.pak>`

You will find the files under the directory named after the beginning of the pak file, until the second dot, for simplicity.

    ./_unpack.sh IPC_566SD664M5MP.4417_2412122178.E1-Zoom.5MP.WIFI7.PTZ.REOLINK.pak
    =>
    IPC_566SD664M5MP.4417_2412122178/...

Edit all the files you want. 

#### nginx

The nginx config files are a decoy, the executable called `device` in the `app` partition creates `nginx.conf` under `/mnt/tmp`, you have directly edit this binary file, there is a big ascii blob in it. Just make sure it stays the **same size**, or else you can go to the Unbricking section. I used Far Manager, it can handle editing and saving binary files as text.

To enable sd card access in the browser, change this:

    location /downloadfile/ {
        internal;
        limit_conn one 1;
        limit_rate 1024k;
        alias /mnt/sda/;
    }

To this: (add as many spaces as needed to balance the missing characters)

    location /downloadfile/ {
        autoindex on;
        autoindex_localtime on;
        alias /mnt/sda/;
                                   
    }

Then you will be able to just click on any file and view it. It's a lot faster this way.

<img width="494" height="244" alt="image" src="https://github.com/user-attachments/assets/91edc0f8-2d1a-48c8-98f0-4dae388eaf8d" />

Or if you want to add more, remove all the spaces, there are plenty.

    location /downloadfile/ {internal;limit_conn one 1;limit_rate 1024k;alias /mnt/sda/;}
    location /downloadfile/html/ {alias /mnt/sda/; autoindex on; autoindex_localtime on;}
    location /downloadfile/js/ {alias /mnt/sda/; autoindex on; autoindex_localtime on; autoindex_format json;}

<img width="472" height="191" alt="image" src="https://github.com/user-attachments/assets/86624d67-a000-49e3-8239-a4cacfac7bbf" />

Include also works, if there is a lot of stuff to add. If you just want to add locations, place the include inside the server block.

    include /etc/nginx/conf.d/*.conf;

#### console

To enable the console on serial, add `ttyS0::respawn:/bin/sh` to `/etc/inittab`.

<img width="992" height="467" alt="image" src="https://github.com/user-attachments/assets/4f0abe09-7cef-4037-8e1d-4aec8101e3bc" />

#### telnet

You can try `telnetd &`, too. But Busybox in my firmware was not compiled with it. (busybox --list)

#### start programs from the sd card

If you want to access the sd card (`/mnt/sda`) from the init files, sleep a few seconds at the end of `/etc/init.d/rcS` and it will be available. In my experience it takes time for the starting services to mount it.

    /etc/ini.d/rcS:
    ...
    sleep 10
    /bin/sh /mnt/sda/boot.sh

Make sure `boot.sh` has Linux style line endings.

#### ttyd

First you have to figure out the architecture, my cameras are all `armhf`. If you are not sure, paste the output of `readelf -A 04_rootfs.s/bin/busybox` into chatgpt and it will tell you.

    git clone https://github.com/tsl0922/ttyd.git
    cd ttyd
    env BUILD_TARGET=armhf ./scripts/cross-build.sh

If it compiles without errors, copy the executable `build/ttyd` to rootfs (or the sd card) and add `/path/to/ttyd/ttyd -W /bin/login &` to the end of your init script. Or just call `/mnt/sda/boot.sh` and put it there, then you don't have to update the firmware every time. 

To auto-restart (because it crashes a lot!), add it to the end of /etc/inittab.

    ::respawn:/bin/ttyd
    ... or if you want to throttle it:
    ::respawn:/bin/ttyd.sh

/bin/ttyd.sh: (chmod +x /bin/ttyd.sh)

    #!/bin/sh
    while true; do
        /bin/ttyd -W /bin/login
        echo "ttyd crashed with exit code $? — restarting in 5s..." >&2
        sleep 5
    done

The default root password is stored as a hash in `/etc/passwd`, hard to find out. Create a second line with your own username and hash, keep uid=0 gid=0 to be the root user too.

    root:XF4sg5T82tV4k:0:0:root:/root:/bin/sh
    gabest:<PASSWORD HASH>:0:0:gabest:/root:/bin/sh

Run this to generate the hash.

    perl -le 'print crypt("password","ab")'

Default port is 7681, but you can use a reverse proxy with nginx:

    location /ttyd {
        proxy_pass http://127.0.0.1:7681/;

        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "Upgrade";

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
    }

<img width="469" height="158" alt="image" src="https://github.com/user-attachments/assets/f163fdbc-f68f-494f-b5f0-14b5721b3978" />

#### other

While you are at `/etc/init.d`, you might want to fix `/etc/init.d/K99_Sys`, change `umount /mnt/sd` to `umount /mnt/sda`.

### Pack

`./_pack.sh <firmware.pak>`

This will create `<firmware_patched.pak>` where the build number is increased by one, else the camera will not see it as an update. After the update, it will still say it is on the old version, because the version files were not modified, so you can continuously update it with the trick.

### Unbricking

I am not responsible for any damages. If you brick your device, you have to take it apart and find the UART solder points and use U-Boot commands to restore it.

#### This is an example to unbrick **E1 Zoom**

GND/TX/RX are next to the sensor. 

Every camera has different partition definition. You can find it in the boot log.

Download and split the firmware file into parts, use [pakler](https://pypi.org/project/pakler/) or [reolink-fw](https://github.com/AT0myks/reolink-fw). 
Find `rootfs` and `app` and convert them from UBI to squashfs with `ubireader_extract_images`. Do not directly write UBI with `ubi write`.
Start a TFTP server in the directory (192.168.1.11/24).
Connect to the camera and mash ctrl+c right after boot, it will give you a command prompt.

    setenv mtdparts 'mtdparts=spi_nand.0:0x40000@0x0(loader),0x40000@0x40000(fdt),0x100000@0x80000(uboot),0x400000@0x180000(kernel),0xf00000@0x580000(rootfs),0xb00000@0x1480000(app),0x800000@0x1f80000(para),0x80000@0x2380000(sp),0x80000@0x2400000(ext_para),0x1b80000@0x2480000(download)'

    tftpboot 0x2000000 rootfs.sqsh
    nand erase.part rootfs
    ubi part rootfs
    ubi create rootfs
    ubi write 0x2000000 rootfs 0x${filesize}

    tftpboot 0x2000000 app.sqsh
    nand erase.part app
    ubi part app
    ubi create app
    ubi write 0x2000000 app 0x${filesize}

There may be other partitions, restore whichever you messed with, but not all are squashfs. As long as your bootloader is intact, you are safe.

If the app.sqsh file is too large, delete the non-english audio files.

#### Another example to unbrick the Doorbell Wifi/PEO (not with the battery) by rewriting the NAND with a programmer.

Read the contents of the NAND into a file (firmware.bin). It should be 142606336 bytes.

Extract 06_rootfs.bin and 07_app.bin from the firmware update. These are the raw UBI files needed, do no convert them.

    python3 _insert.py 06_rootfs.bin firmware.bin 0x700000 0x2700000 0x800 0x80
    python3 _insert.py 07_app.bin firmware.bin 0x2700000 0x3C00000 0x800 0x80

Real insertation will happen at 0x770000 and 0x2970000, adjusted for NAND's extra data. Every 0x800 bytes you need 0x80 additional. _insert.py will take care of it.

    Mtd_part name="rootfs"         mtd="/dev/mtd12"      a=0x00700000  start=0x00700000  len=0x02000000
    Mtd_part name="app"            mtd="/dev/mtd12"      a=0x02700000  start=0x02700000  len=0x01500000
    Mtd_part name="para"           mtd="/dev/mtd12"      a=0x03c00000  start=0x03c00000  len=0x00800000

    0x700000 * 0x880 / 0x800 => 0x770000
    0x2700000 * 0x880 / 0x800 => 0x2970000

Write it back to the NAND.

You can check the boot log about 0x800 and 0x80 if you are not sure (page size and OOB size). It can vary, depends on the type of the NAND chip.

    nand: device found, Manufacturer ID: 0xc8, Chip ID: 0x51
    nand: ESMT GD5F1GQ4UEYIH 1GiB 3.3V
    nand: 128 MiB, SLC, erase size: 128 KiB, page size: 2048, OOB size: 128

_extract.py is also provided for completeness.
