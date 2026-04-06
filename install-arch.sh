#!/bin/bash
# Arch Linux Installation Script

# Update the system
pacman -Syu

# Install essential packages
pacman -S --needed base-devel git linux linux-firmware

# Set up partitions (example for a basic setup)
fdisk /dev/sda

echo "This script is just a template. Modify it to suit your installation needs!"