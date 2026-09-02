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

GROUP_NAME="cml-control"
CERTS_DIR=~/test-certs

# Create and add user to the cml-control group
if groups | grep -q "$GROUP_NAME"; then
	echo "Group '$GROUP_NAME' already exists"
else
	echo "Creating cml-control group"
	sudo addgroup cml-control
fi

if id | grep -q "$GROUP_NAME"; then
	echo "User is already in the '$GROUP_NAME' group"
else
	echo "Adding current user to group"
	sudo usermod -aG $GROUP_NAME "$USER"

	echo "Restarting script with new group..."

	exec sg "$GROUP_NAME" "$0" "$@"
fi

# Create the logging directory
print "Creating log directory"
sudo mkdir -p /var/log/cml/cml-scd

# Create operatingsystems dir
print "Creating operatingsystems directory"
sudo mkdir -p /var/lib/cml/operatingsystems


# Creating tokens
if [ -d "/var/lib/cml/tokens/" ] && [ -n "$(ls -A '/var/lib/cml/tokens/')" ]; then
	echo "Using existing tokens"
else
	echo "Initalizing tokens"
	sudo cml-scd
fi

# Calling `cml_gen_dev_certs` on an existing directory does not create any certificates
if [ -d $CERTS_DIR ]; then
	echo "Remove the directory at '$CERTS_DIR' and re-run the script"
	exit 1
fi

# Creating cml certificates
print "Creating root certificates"
cml_gen_dev_certs $CERTS_DIR

print "Installing root certificates"
sudo cp $CERTS_DIR/ssig_rootca.cert /var/lib/cml/tokens/

print "Starting cmld.service"
sudo systemctl start cmld.service

print "Waiting for the service to start"
sleep 2
if systemctl is-active --quiet cmld.service; then
	echo "Starting the service was successful."
	echo "You're good to go"
else
	echo "Starting the service failed"
	echo "Run 'systemctl status cmld.service' for more information"
fi
