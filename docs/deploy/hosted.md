---
title: Hosted Mode
---
# Hosted mode

> [!CAUTION]
> The following scripts execute commands with root privileges (sudo).
> We therefore strongly recommend the use of a virtual machine.

GyroidOS containers can also be run natively on your host, using the hosted mode.
This section describes how to run the hosted mode.
These instructions have been tested and work on Debian 13 Trixie.

## Requirements

Have a prebuilt container image ready or build one yourself as described in [Build](../build/build.md).

### Required packages
Install all required packages with the following command:
```
sudo apt update && sudo apt-get install -y git build-essential unzip re2c pkg-config \
    check lxcfs libprotobuf-c-dev automake libtool libselinux1-dev libcap-dev \
    protobuf-c-compiler libssl-dev udhcpd udhcpd libsystemd-dev debootstrap \
    squashfs-tools python3-protobuf protobuf-compiler \
    cryptsetup-bin iptables e2fsprogs
```

### Protobuf-c-text
To install protobuf-c-text, run the following commands:
```
git clone https://github.com/gyroidos/external_protobuf-c-text.git
cd external_protobuf-c-text/
./autogen.sh
./configure --enable-static=yes
make
sudo make install
sudo ldconfig
```

## Installation

### CML

> Requires OpenSSL version >= 3.2

Clone, compile and install the neccesary components with
```
git clone https://github.com/gyroidos/cml
cd cml/
SYSTEMD=y make -f Makefile_lsb
sudo make SYSTEMD=y -f Makefile_lsb install 
```

### Additional tools
Clone and install the necessary components with
```
git clone https://github.com/gyroidos/gyroidos_build
cd gyroidos_build/cml_tools
sudo make install
```
## Setup - Daemon

### Automatic


Download and run the automatic [setup script](../assets/scripts/hosted-setup.sh) using the following commands:
```
curl -fsL https://gyroidos.github.io/assets/scripts/hosted-setup.sh -o hosted-setup.sh
chmod +x hosted-setup.sh
./hosted-setup.sh
```

### Step by Step

1. Create the Certificates
```
sudo mkdir -p /var/log/cml/
sudo cml-scd
```
2. Create the cml-control group and add the current user to it
```
sudo addgroup cml-control
sudo usermod -aG cml-control "$USER"
```
3. Create test certificates
```
cml_gen_dev_certs ~/test-certs
sudo cp ~/test-certs/ssig_rootca.cert /var/lib/cml/tokens/
```
4. Create folder for operatingssystems
```
sudo mkdir -p /var/lib/cml/operatingsystems
```
5. Start the cmld service
```
sudo systemctl start cmld.service
```

## Guest OS Setup - Trixie

### Automatic


Download and run the [guest setup script](../assets/scripts/hosted-debian-guest.sh), which automatically creates and starts a Debian 12 container.

```
curl -fsL https://gyroidos.github.io/assets/scripts/hosted-debian-setup.sh -o hosted-debian-setup.sh
chmod +x hosted-debian-setup.sh
./hosted-debian-setup.sh
```

### Step by Step


1. Create a folder for the Guest OS and initialize the folder and generate a basic configuration
```
mkdir ~/cmld_guestos
cd ~/cmld_guestos
cml_build_guestos init "trixie" --pki ~/test-certs
```

2. Create a new debian rootfs using debootstrap, add the rootfs to an uncompressed tarball, and move the tar ball into the rootfs/ directory 
```
mkdir "rootfs-builder"
sudo debootstrap trixie "rootfs-builder" "http://deb.debian.org/debian"
sudo tar --owner=0 --group=0 --numeric-owner -cf "trixie.tar" -C "rootfs-builder" .
sudo mkdir -p rootfs
mv "trixie.tar" rootfs/"trixieos.tar" 
sudo cml_build_guestos build "trixie"
```


4. Install the operatingsystem (Exchange x86 with your architecture)
```
mkdir -p ~/cmld_guestos/operatingsystems/x86
sudo mv out/gyroidos-guests/trixieos-1 ~/cmld_guestos/operatingsystems/x86
```

5. Disable signed configs and update base URL
```
echo "signed_configs: false" | sudo tee -a /etc/cml/device.conf >/dev/null
update_base_url="update_base_url: \"file://$(realpath "$HOME/cmld_guestos")\""
echo "$update_base_url" | sudo tee -a /etc/cml/device.conf >/dev/null
```

7. Restart the cmld service
```
sudo systemctl restart cmld
```

8. Push the guestos and restart the cmld
```
prefix="$HOME/cmld_guestos/out/gyroidos-guests/trixieos-1"
cml-control push_guestos_config "${prefix}.conf" "${prefix}.sig" "${prefix}.cert"
sudo systemctl restart cmld
```

You can now confirm, that your guestos has sucessfully installed by calling `cml-control list_guestos`

9. Create a GyroidOS container using the created configuration file
```
cml-control create "conf/trixiecontainer.conf"
```

10. Change the pin of the newly created Container (default: trustme)
```
 cml-control change_pin trixiecontainer
```

11. Start the container
```
cml-control start trixiecontainer
```

12. Verify that the container is running
```
cml-control list trixiecontainer
```
13. Run bash in the container
```
cml-control run trixiecontainer bash
```

## Guest OS Setup - Generic 

1. Create a folder for the Guest OS (`$BASE`)
2. Initialize the folder and generate a basic configuration with `cml_build_guestos init $GUEST_NAME --pki /path/to/dir`
3. Create a new rootfs using, e.g. `debootstrap`
4. Add the rootfs to an uncompressed tarball named `${GUEST_NAME}os.tar`
5. Move the tar ball into the `rootfs/` directory that was created in step 2
6. Build the Guest OS with `cml_build_guestos build $GUEST_NAME`
7. Create a new directory called `operatingsystems/<system-architecture>/`, replace `<system-architecture>` with `x86` or `arm`
8. Move `out/gyroidos-guests/${GUEST_NAME}os-1/` to `operatingsystems/<system-architecture>/`
9. Install the operating system with `cml-control push_guestos_config ${GUEST_NAME}os-1.conf ${GUEST_NAME}os-1.sig ${GUEST_NAME}os-1.cert`
10. In `/etc/cml/device.conf`, set
    - `signed_configs: false` to disable the signature verfication for development. This should **never** be done in production.
    - `update_base_url: "file://$BASE"`
11. Restart the `cmld` service
12. Confirm that the new Guest OS is detected by running: `cml-control list_guestos`
13. Create a GyroidOS container using its configuration file with `cml-control create conf/${GUEST_NAME}container.conf`
14. Update the container’s password (default is `"trustme"`) with `cml-control change_pin "$GUEST_NAME"`
15. Start the container with: `cml-control start "$GUEST_NAME"`. If the command returns `CONTAINER_START_EINTERNAL`, re-run the command.
16. Verify that the container is running by executing: `cml-control list "$GUEST_NAME"`
17. To access the container’s: `cml-control run $GUEST_NAME bash`


For additional details, see the [GuestOS configuration](../operate/guestos_config.md) and [Basic Operation](../operate/control.md) documentation pages.