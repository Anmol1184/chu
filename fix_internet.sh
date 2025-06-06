#!/usr/bin/env bash
modprobe -r r8169 ath10k_pci
sleep 2
modprobe r8169 ath10k_pci
