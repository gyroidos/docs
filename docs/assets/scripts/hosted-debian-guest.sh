#!/bin/bash
#
# This file is part of GyroidOS
# Copyright(c) 2013 - 2025 Fraunhofer AISEC
# Fraunhofer-Gesellschaft zur Förderung der angewandten Forschung e.V.
#
# This program is free software; you can redistribute it and/or modify it
# under the terms and conditions of the GNU General Public License,
# version 2 (GPL 2), as published by the Free Software Foundation.
#
# This program is distributed in the hope it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE. See the GPL 2 license for more details.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, see <http://www.gnu.org/licenses/>
#
# The full GNU General Public License is included in this distribution in
# the file called "COPYING".
#
# Contact Information:
# Fraunhofer AISEC <gyroidos@aisec.fraunhofer.de>
#

set -euo pipefail

print() {
	echo
	echo "$*"
}

architecture() {
	arch="$(uname -m)"

	case "$arch" in
	arm* | aarch64)
		arch="arm"
		;;
	x86*)
		arch="x86"
		;;
	*)
		echo "Unsupported architecture $arch"
		exit 1
		;;
	esac

	echo "$arch"
}

CERTS_DIR="${HOME}/test-certs"
GUEST_OS_DIR="${HOME}/cmld_guestos"
ROOTFS_DIR="rootfs-builder"
GUEST_NAME="trixie"
GUEST_DISTRO="trixie"
CONTAINER_NAME="${GUEST_NAME}container"
INSTALL_PATH="${GUEST_OS_DIR}/operatingsystems/$(architecture)/"


# Script start
if [ ! -d "${CERTS_DIR}" ]; then
	print "Certificate directory '${CERTS_DIR}' is missing"
	exit 1
fi

# 0. Check if cmld is running
if ! systemctl status cmld.service | grep "Active: active"; then
	echo "cmld is not running."
	echo "Start cmld and re-run the script"
	exit 1
fi

# 1. Create and enter GuestOS directory
print "Creating GuestOS directory at ${GUEST_OS_DIR}"
mkdir "${GUEST_OS_DIR}"
cd "${GUEST_OS_DIR}"

# 2. Initialize guest OS
print "Initializing guest OS '${GUEST_NAME}'"
printf "y\n" | cml_build_guestos init "${GUEST_NAME}" --pki "${CERTS_DIR}"

# 3. Create the latest Debian rootfs
print "Creating the latest Debian rootfs"
mkdir "${ROOTFS_DIR}"
sudo debootstrap "${GUEST_DISTRO}" "${ROOTFS_DIR}" "http://deb.debian.org/debian"

# Create tar archive of rootfs
print "Creating tar archive of rootfs"
sudo tar --owner=0 --group=0 --numeric-owner -cf "${GUEST_NAME}.tar" -C "${ROOTFS_DIR}" .
sudo mkdir -p rootfs
mv "${GUEST_NAME}.tar" rootfs/"${GUEST_NAME}os.tar"

# Build the guest OS
print "Building the guest OS '${GUEST_NAME}'"
sudo cml_build_guestos build "${GUEST_NAME}"

# Preparing to install the operating system
print "Preparing to install the operating system"
mkdir -p "$INSTALL_PATH"
sudo mv "out/gyroidos-guests/${GUEST_NAME}os-1/" "$INSTALL_PATH"

# Disable signed configs
print "Disabling signed configs for this example"
if grep -q "signed_configs" /etc/cml/device.conf; then
	echo "Already disabled"
else
	echo "signed_configs: false" | sudo tee -a /etc/cml/device.conf >/dev/null
fi

# Set update URL
print "Setting update_base_url"
update_base_url="update_base_url: \"file://$(realpath "$GUEST_OS_DIR")\""
if grep -q "update_base_url:" /etc/cml/device.conf; then
	# There already exists an URL => delete it
	sudo sed -i '/^update_base_url/d' /etc/cml/device.conf
fi
echo "$update_base_url" | sudo tee -a /etc/cml/device.conf >/dev/null

if [ ! -f "${INSTALL_PATH}/${GUEST_NAME}os-1/root.img" ]; then
	echo "root.img does not exist!"
	exit 1
fi

sudo systemctl restart cmld

# Installing operating system
print "Installing operating system"
prefix="${GUEST_OS_DIR}/out/gyroidos-guests/${GUEST_NAME}os-1"
cml-control push_guestos_config "${prefix}.conf" "${prefix}.sig" "${prefix}.cert"

# Restart cmld service, for some reason `systemctl restart cmld` does not work
print "Restarting cmld service"
sudo systemctl stop cmld.service
sleep 1
sudo systemctl start cmld.service
print "Verifying that cmld service restarted successfully"
if ! systemctl is-active --quiet cmld.service; then
	echo "cmld service failed to start"
	exit 1
fi

# Verify guest OS registration
print "Verifying that the guest OS was successfully registered"
if ! cml-control list_guestos | grep -q "${GUEST_NAME}"; then
	echo "Guest OS '${GUEST_NAME}' registration verification failed"
	exit 1
fi

# Create GyroidOS container
print "Creating GyroidOS container '${CONTAINER_NAME}'"
cml-control create "conf/${CONTAINER_NAME}.conf"

# Update container password to be empty
print "Updating container password to be empty"
printf "trustme\n\n\n" | cml-control change_pin "${CONTAINER_NAME}"

# Start the container
print "Starting the container '${CONTAINER_NAME}'"

while true; do
	STATE=$(printf "\n" | cml-control start "$CONTAINER_NAME")

	if echo "$STATE" | grep -q "CONTAINER_START_OK"; then
		echo "Container has started"
		break
	elif echo "$STATE" | grep -q "CONTAINER_START_EEXIST"; then
		echo "Container already exists"
		break
	fi

	echo "Container has not been started: $STATE. Waiting for 2 seconds before retrying"
	sleep 2
done

# Wait for the container to be running
print "Waiting for the container to be ready"
while true; do
	STATE=$(cml-control list "${CONTAINER_NAME}" | grep "state:")

	if echo "$STATE" | grep -q "RUNNING"; then
		echo "Container is running"
		break
	elif echo "$STATE" | grep -q "STOPPED"; then
		echo "Container has stopped. An error has occurred."
		exit 1
	else
		echo "Container is not yet running: $STATE. Waiting for 5 seconds before retrying"
		sleep 5
	fi
done

# Determine container's PID
print "To connect to the container, run:"
echo "cml-control run $CONTAINER_NAME bash"
