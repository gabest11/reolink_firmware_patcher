# Reolink Firmware Patcher

Requirements: pakler, ubi_reader (pip install ...), also mtd-utils.

Tested with E1 Zoom 5MP and 8MP. 

Don't try if there is no LAN and serial connection on the board somewhere. If there is no serial (Doorbell) it is still possible to rescue if you can pull the partitions from the update and merge with the contents of the NAND and rewrite it some programmer like the T48.

### Unpack

`./_unpack.sh <firmware.pak>`

You will find the files under the directory according to the build number. Edit the files you want. 

The nginx config files are a decoy, the executable called `device` in the `app` partition creates it under `/mnt/tmp`, you have directly edit this binary file, it's a big ascii blob in it, just make sure it stays the same size. I used Far Manager, it can handle editing and saving binary files as text.

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

Or if you want to add more, remove all the spaces, there are plenty.

        location /downloadfile/ {internal;limit_conn one 1;limit_rate 1024k;alias /mnt/sda/;}
        location /downloadfile/html/ {alias /mnt/sda/; autoindex on; autoindex_localtime on;}
        location /downloadfile/js/ {alias /mnt/sda/; autoindex on; autoindex_localtime on; autoindex_format json;}

To enable the console on serial, add `ttyS0::respawn:/bin/sh` to `/etc/inittab`.

You can try `telnetd &`, too. But Busybox in my firmware was not compiled with it. (busybox --list)

### Pack

`./_pack.sh <firmware.pak>`

This will create `<firmware_patched.pak>` where the build number is increased by one, else the camera will not see it as an update. After the update, it will still say it is on the old version, because the version files were not modified, so you can continously update it with the trick.

### Unbricking

I am not responsible for any damages. If you brick your device, you have to take it apart and find the UART solder points and use U-Boot commands to restore it.

This is an example to unbrick E1 Zoom (GND/TX/RX are next to the sensor). Every camera has different partition definition. You can find it in the boot log.

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


