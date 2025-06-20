#!/bin/bash
set -e

echo "👤 Creando usuario 'frappe'..."
sudo adduser frappe --disabled-password --gecos ""
sudo usermod -aG sudo frappe
sudo chown -R frappe:frappe /opt/erp-automation-scripts

